# A run of whitespace alone is not an inline script (#273)

Tier: deterministic Apple PDF stack, isolated macOS arm64 release CLI.
Corpus: the 18 gated cases, with the census report, the FAA handbook, the CDC graphic novel and
the USCIS Arabic guide as the subjects — `rrs2002-01.pdf`, SHA-256
`0f97380ae4308581bd70013b7317faafd7c217654236bd31d1448f26eae56905`; `faa-h-8083-25c.pdf`,
`247929cace0ab56b376e683eba540cc4c8f39f199ab35414e8b604e24f395cb7`; `cdc_6023_DS1.pdf`,
`d95e9ec2d8cf52cb8c218a6195e132ec140725018358fd2122928bab8a13efc3`; `M-618_a.pdf`,
`354effbbe38450664959b8832d136cfd158d3c17d1ba777b8b1e4a5b6aa36d54`.
Build: this branch merged over `main` at `a1bbea8`, Xcode 27.0 (27A266a), Swift 6.4, macOS 27.0
(26A428, Darwin 27.0.0, xnu-13432.1.9~1), EPUBCheck 5.3.0; release executable SHA-256
`7f66a0ad49d5d99d2890894ac455f28d7e00c4b00a596f1efd87c72f9361a4de`.
Baseline: `a1bbea8` alone, executable SHA-256
`b4bb9c73f8f9f66edf0e0d4b294b189d30f5b208ed02af303ab7767d7b5f5b15`.
`main` moved to `94a24ad` while this was measured. Every per-book number below was taken again
over that merge — branch executable SHA-256
`583abdf5f6ebea0852c215f798597b133456f215eb0b7ff3e929504774c8b255` against baseline
`c7ed605dbe039203681d5de52837cef9059619c8c523b1826ba99344810fd5a0` — and nothing moved between
the two bases: the same 40 elements in the same four books, the same thirteen books byte-identical,
and the same spine boundary shift in the FAA handbook.

## What the markup was saying

`NativeTextReader.inlineText` decided an inline script from the run's baseline offset and the
guards that had accumulated around it — a drop cap's initial, a redrawn dingbat, a right-to-left
letter — and from nothing about the run's own characters. A run holding only a space therefore
took `.superscript` or `.subscript` like any other, and the writer wrapped it: `<sup> </sup>`,
`<sub> </sub>`, and, where the run was bold as well, `<sub><strong> </strong></sub>`. The element
claims an inline script over no glyph at all, and a reader that styles `<sup>` — smaller type,
raised — applies that to a space.

Forty such elements stood in the 18 gated cases, converted at library defaults with `--no-ocr`:

| book | `<sup>` | `<sub>` | of all inline scripts |
| --- | ---: | ---: | ---: |
| census report | 5 | 24 | 68 |
| FAA handbook | 0 | 9 | 176 |
| CDC graphic novel | 1 | 0 | 7 |
| USCIS Arabic guide | 1 | 0 | 1 |

The issue counted 33 of these. The seven it missed are the FAA's, where the element is
`<sub><strong> </strong></sub>` and a search for `<sub> </sub>` does not find it.

## Where each one came from

Two different mechanisms produce the run, which is why the guard belongs at the decision and not
at either source. A standalone probe over the four books' own PDFKit runs — every run holding no
non-whitespace character whose offset falls inside the inline-script band — finds 9 in the FAA
handbook, 3 in the Arabic guide, 1 in the CDC novel and **none at all** in the census report.

**The page's own spaces.** The FAA handbook's glossary, physical pages 509 and 510, sets each
V-speed entry as `VLO. Landing gear operating speed.`, and PDFKit reports the word space after the
term on its own, lowered 2.0 points on a 7-point body, with the term and the definition both on
the baseline. Eight entries do this (`VLO`, `VMC`, `VNE`, `VNO`, `VS0`, `VS1`, `VX`, `VY`), and
the ninth is page 233's figure caption, whose whole line is set 5.54 points low, space included.
The CDC novel's page 12 sets a raised caption and a lowered one on one line, and the space where
they meet takes the raised one's 4.9-point offset. The Arabic guide's pages 77, 93 and 103 raise
a *word space* by 1.52 to 1.98 points on a 10.45- to 12-point body: the same shaping that #41
found raising single Arabic letters, over a character that draws nothing, so #41's own guard —
which asks whether the run's letters read right to left — does not apply to it.

**A rewriter that splits one.** The census report has none of these: PDFKit hands its page 4 back
with `ij ` as a single lowered run, trailing space included, on a 7.08-point body inside a
10.08-point line. What splits it is the glyph redraw (#217). This book's Type 1C fonts carry no
`ToUnicode` map and report every letter shifted by three, so `GlyphIdentityReader` rebuilds each
line character by character from the fonts' own tables, and a kept space comes back as a run of
its own, still carrying the offset of the subscript it used to close. Built with that redraw
switched off, the census report produces **0** whitespace-only script runs instead of 35; built
with the spacing repair (#119) switched off instead, it still produces all 35. So the redraw is
the whole of it, and no character of the page is at fault.

Extraction produces 35 such runs in the census report, 9 in the FAA handbook, 3 in the Arabic
guide and 1 in the CDC novel. Six of the census report's and two of the guide's never reach the
reader as text at all — their lines stand inside blocks this library preserves as pictures (the
census report alone writes 58 `Preserved region from page N` figures) — which is the difference
between 48 runs read and 40 elements written.

## What changed

One guard, in the same condition that already refuses a drop cap's initial, a redrawn dingbat and
a right-to-left letter: a run with no non-whitespace character in it takes no script style,
however its metrics place it. The run itself is untouched — the page set that space and the words
on either side of it need it — so the space is written where the page put it and only the claim
about its baseline is dropped. Whitespace *inside* a run that also holds a glyph stays that
script's own: `<sup>1 2</sup>` is still one raised run, because that run has something raised in
it. Nothing here reads a rendered character's width, a font, or the markup after the fact.

## What moved, book by book

Every gated case was converted with both executables at `--no-ocr` and fixed packaging
(`--package-identifier urn:uuid:identity --modification-date 2026-01-01T00:00:00Z`) and compared
entry by entry. Thirteen of the eighteen are **byte-identical**: Wallace's algebra, the 9/11
report, the Fed, the Dietary Guidelines, *Our Flag*, the Blue Book, the NBS paper, the arXiv
paper, the copper summary, IRS Publication 596 in Chinese, the NASA slides, the Warren excerpt and
*Agricultural Research*. Between them those thirteen carry 3,765 inline scripts, none of which
moved — Wallace's 1,963 exponents and the 9/11 report's 1,727 endnote markers are the control this
guard had to leave alone, and they are identical byte for byte.

The five that moved lose exactly the elements above and nothing else. **Read as a reader meets it
— the spine in order, tags removed — the text of all eighteen books is unchanged, character for
character, and so is every page marker.**

| book | whitespace-only scripts | all inline scripts | what else moved |
| --- | ---: | ---: | --- |
| census report | 29 → 0 | 68 → 39 | one spine document's markup |
| FAA handbook | 9 → 0 | 176 → 167 | markup in three documents; the spine boundary between documents 32 and 33 moved by two index entries |
| CDC graphic novel | 1 → 0 | 7 → 6 | one spine document's markup |
| USCIS Arabic guide | 1 → 0 | 1 → 0 | one spine document's markup |
| *Loper Bright* | 0 → 0 | 48 → 48 | five footnote markers |

*Loper Bright* is the case the count does not describe. Its footnote markers are drawn as the
private-use bullet U+F0B7 followed by a space, reported as two raised runs, and the two used to
merge into one: `<sup>` then the bullet, then a space, then `</sup>Under the Public Health Service
Act…`. The marker is a real raised glyph and keeps its `<sup>`; the space beside it is now written
outside it, which is where the page set it. Five footnotes on one page read that way and nothing
else in the book differs.

The FAA handbook's two index entries — `Land and hold short lights` and `Landing` — move from
spine document 33 to document 32 because document 32's body lost nine `<sub>…</sub>` wrappers and
two more blocks now fit under the 60,000-byte target. Its 8,994 blocks are identical in kind, in
text and in order on both sides; only where the writer cuts between two documents moved.

## Gates

`scripts/check-all.sh --fast` passes, exit status read directly, with 596 Swift tests, three of
them new. The corpus lane passes 18 of 18 covered cases at four jobs — every case's `runPassed`
read from its own `result.json` and true, and every `content-assessment.json` holding zero errors
and zero warnings. The baseline executable run through the same lane passes 18 of 18 as well:
this change moves no contract, and both sides record the same `outputTextCharacters` for every
case and EPUBCheck exit 0 for every case. (The lane does not pin packaging, so its `outputBytes`
differ by a byte or two in books whose markup is identical; the fixed-packaging comparison above
is what the per-book claims rest on.)

## What is not claimed

The guard reads characters, not rendering: a run of one space that the page really did raise is
still written as an ordinary space, because there is nothing in it for a reader to see raised, and
this library has no way to show that a page raised a gap. The four books' remaining inline scripts
are not re-examined here — the FAA's page 233 sets a whole figure caption 5.54 points low and it
is still written `<sub>`, which is a question about a line, not about a run, and no part of #273.
Whitespace-only *emphasis* is left alone too: five elements survive across the corpus after this
change (`<em> </em>` and `<strong> </strong>` in the FAA handbook, the Arabic guide and
*Agricultural Research*), and a bold space renders as a space, so the case for a guard there is
markup tidiness rather than fidelity; it is filed as
[#278](https://github.com/vocaro/PDFReflowLib/issues/278).
