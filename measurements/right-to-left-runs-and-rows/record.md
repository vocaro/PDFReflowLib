# Right-to-left runs, rows and base direction (#41)

Tier: deterministic Apple PDF stack, isolated macOS arm64 release CLI.
Corpus: every gated case, with *Welcome to the United States: A Guide for New Immigrants*
(M-618-A, Arabic, rev. 09/15) as the subject; 116 pages, 4,156,497 bytes, SHA-256
`354effbbe38450664959b8832d136cfd158d3c17d1ba777b8b1e4a5b6aa36d54`.
Build: this branch merged over `main` at `860e9d2`, Xcode 27.0, macOS 27.0
(Darwin 27.0.0, xnu-13432.1.9~1); release executable SHA-256
`b81d53f0679cc71e516566e9e3ddaa05fe0485e52a3288f731ddc60d7d61c734`.
Baseline: `860e9d2` alone, executable SHA-256
`08a6efd019bf68e4fd31cba5e8f615a7fe954e1ceb5d9219215269316c013823`.

## What the reading was doing

PDFKit does not hand back a string; it inverts a layout. The Arabic of this book comes back in
the order it was written, and three things do not.

**Numbers and identifiers.** The bidirectional algorithm folds a separator between two numbers
into the number (rule W4), and a number after a Latin term into that term (rule W7), so the page
paints `I-551` and `1-800-870-3676` left to right inside its Arabic. PDFKit's inversion applies
neither rule, resolves the `-` as a right-to-left neutral, and reverses the parts around it. Page
21 (printed 15) therefore returned `551-I`, `485-I`, `90-I` three times and `3676-870-800-1`, and
the same page's web addresses — `www.uscis.gov` and `www.uscis.gov/uscis-elis` — came back
correct, because a separator between two words is resolved the same way by the page and by the
reading. That difference is the whole discriminator the fix uses.

**A line with no right-to-left letter in it.** The paragraph on page 21 that ends `(USCIS).` on a
line of its own came back `.)USCIS(`. The page paints that line right to left: the stop leftmost,
then the mirrored glyph of `)`, then `USCIS`, then the mirrored glyph of `(` at x 540–545 — a
strip selection over the line confirms each position. PDFKit takes its base direction from the
line's own characters, finds only `USCIS`, reads the line left to right and hands the painted
order back verbatim, with the logical bracket characters in it. Nothing else on the page does
this, because every other line carries Arabic.

**Printed rows.** PDFKit splits a row at a full stop in this book's Arabic, and returns the two
pieces left to right. Page 21's row at y 563 comes back as `551-I) كإثبات … الولايات المتحدة`
over x 343–543 and `. ويطلق بعض الأشخاص على هذه البطاقة` over x 184–342, the second of which is
the *continuation* of the first. Five rows on that page split this way and two on page 5, and
each left-hand piece opens with the stop that ends the previous sentence, which is why the
reading showed sentence-final periods at the start of a paragraph.

Two more things follow from the writing rather than from PDFKit. A right-to-left paragraph stands
on its right edge: page 21's ten wrapped lines have right edges within a point of 543 and left
edges spread over 92 points, so the column test that joins wraps, which measured left edges,
refused every one of them. And this page's shaping raises single Arabic letters off the baseline
— the `ا` of `إذا` by 2.34 points and the `ف` of `للتعرف` by 1.52, on a twelve-point body against
the 1.44 an inline script needs — so two letters were emitted `<sup>` in the middle of their own
words.

## What changed

`ArabicText` counts a page's right-to-left letters against its Latin letters; a page with at
least as many of the first is right to left. Nothing in this work runs on any other page, and
nothing consults the declared language, which is `en` for this book at library defaults, exactly
as `LayoutReconstructor.releasesProse` already reasons about it. The extraction reorders such a
page's identifiers and its direction-less lines as permutations that carry every attribute; the
layout reads its columns, rows and paragraph edges the other way round; `TableRegionDetector`
reads a row's trailing cell at the end the row ends at; and a block whose own text reads right to
left is written `dir="rtl"`, with `page-progression-direction="rtl"` on the spine of a book most
of whose blocks do.

One rule that would have applied in both directions is held to right-to-left writing: a printed
row the extractor split is one line as far as the next line's column test is concerned. Removing
that guard joins `At the time of their travel through` with `Iran, the al Qaeda operatives
themselves were probably not aware of the specific details of their future operation.` in the
9/11 report — the paragraph the page prints — and re-packs five of its spine documents. That is
right and it is not this issue's; it is [#272](https://github.com/vocaro/PDFReflowLib/issues/272).
[#273](https://github.com/vocaro/PDFReflowLib/issues/273) is the other thing this measurement
found: a run of whitespace alone is written `<sup> </sup>`, in four books including this one.

## What moved, book by book

Every gated case was converted with both executables at `--no-ocr` and fixed packaging
(`--package-identifier urn:uuid:identity --modification-date 2026-01-01T00:00:00Z`) and compared
entry by entry with `tools/epub_identity.py`. Seventeen of the eighteen are **byte-identical**:
the FAA handbook, Wallace, the 9/11 report, the Fed, the Dietary Guidelines, *Our Flag*, the Blue
Book, the CDC novel, the NBS paper, the arXiv paper, the copper summary, *Loper Bright*, the
census report, IRS Publication 596 in Chinese, the NASA slides, the Warren excerpt and
*Agricultural Research*. `--no-ocr` is what makes that comparison meaningful: with recognition on,
the scanned books differ between any two builds because Vision does
([#269](https://github.com/vocaro/PDFReflowLib/issues/269)), and the baseline executable converts
the 9/11 report to the same bytes twice in a row on this host, which is the control for the
comparison.

The eighteenth is the Arabic guide:

| | `860e9d2` | this branch |
| --- | ---: | ---: |
| blocks | 1,408 | 814 |
| paragraphs | 1,102 | 504 |
| preformatted blocks | 53 | 57 |
| headings | 102 | 102 |
| figures | 151 | 151 |
| `<sup>` | 26 | 1 |
| `dir="rtl"` blocks | 0 | 634 |
| characters of text | 115,211 | 115,039 |

The 172 characters are spaces, all of them: the multiset of non-space characters is identical,
95,176 either way, so no word of the book is gained or lost. They are the spaces a join no longer
inserts before the stop a split row hands back at the head of its left-hand piece.

Page 21 reads as the issue asks. Its first paragraph is now
`… للمقيمين الدائمين (استمارة I-551) كإثبات لوضعهم القانوني في الولايات المتحدة. ويطلق بعض الأشخاص …`
— one paragraph over four extracted lines and one split row, with the form number, the stop and
the parenthesis where the page sets them. `I-485`, `I-90` twice, `1-800-870-3676`, `(USCIS)`,
`(USCIS ELIS)`, `[Permanent Resident Card]`, `[Green Card]`, `[USCIS Forms Line]`,
`www.uscis.gov` and `www.uscis.gov/uscis-elis` all read correctly; fifteen paragraph fragments
became four paragraphs, which is every paragraph the page prints, one of them standing apart
because the page prints a callout picture inside it (#137's cut, not this issue's); and neither
`<sup>` remains. Page 5's contents are thirty-one blocks where they were twenty-seven — 24
preformatted entries and 3 paragraphs holding seven entries between them become 30 preformatted
entries and one paragraph, one entry each — each with its own page number and each read from its
title: `أين تتلقى المساعدة … 8` and `التعليم في الولايات المتحدة … 58`, whose rows the extractor
split, were read title-last and joined to the entry above them before.

## Gates

`scripts/check-all.sh --fast` passes, exit status read directly. `swift test` passes 548 tests,
eight of them new (`Tests/PDFReflowLibTests/BidirectionalTextTests.swift`), each with a Latin or
Chinese control beside it. The corpus lane passes 18 of 18 covered cases, every case's `runPassed`
read from its own `result.json` and true, and `860e9d2` passes the same 18.

The Arabic case's own gate: EPUBCheck 5 reports 0 fatals, 0 errors and 0 warnings on the 39,561,191-byte
EPUB; peak converter RSS is 180,289,536 bytes (171.9 MiB) against the case's 256 MiB ceiling,
where `860e9d2` used 174,735,360 (166.6 MiB); all 399 progress events pass. Its reviewed contract
now runs 26 checks, up from 9: the added ones name `I-551`, `I-90`, `1-800-870-3676`,
`(USCIS ELIS)` and `(USCIS).` as paragraph text, the two split contents rows as preformatted
blocks of their own, the contents entries in order, and `551-I`, `485-I`, `90-I`,
`3676-870-800-1` and `)USCIS(` as text the reading must not produce. Run against `860e9d2`'s own
output those 26 checks fail with ten errors, which is what makes them a regression gate rather
than a description.

## What is not claimed

Two pages of 116 were reviewed, as before; the rest of the book is unread and
`qualifiedForFidelity` stays false. The rule that a page is right to left is a majority of its
own letters, so a page of an Arabic book set wholly in English is read left to right, which is
what such a page is. A number whose separator has a digit beside it is always put back, because
the page's resolution and the reading's always differ there; a book that really did print
`551-I` inside Arabic would be read as `I-551`, and no page of this one does. Hebrew, Syriac,
Thaana, NKo, Samaritan and Mandaic are named in the same test as Arabic on the strength of the
bidirectional algorithm alone: no corpus case sets them.
