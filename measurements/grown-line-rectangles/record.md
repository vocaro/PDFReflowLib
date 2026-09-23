# A line rectangle PDFKit grew to fit what the line carries (#230)

Tier: deterministic Apple PDF stack, isolated macOS arm64 release CLI.
Corpus: every cached source, with *Beginning and Intermediate Algebra*
(`Beginning_and_Intermediate_Algebra.pdf`, 489 pages, SHA-256
`856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678`) as the subject.
Build: `main` at `f283360` with this change, Xcode 27.0, macOS 27.0 (Darwin 27.0.0).
Baseline: `f283360` alone, executable SHA-256
`a78e7aa41ef82d343c69ad713e4c0e5aab2e507e8aaffc049087290741bd9807`.

## The defect, as the page states it

`PDFSelection.selectionsByLine()` gives a line the height of the tallest glyph on it rather than
the line's own extent, so a line of running prose carrying one inline radical is reported two to
four times its neighbours' height and its rectangle reaches into the line beneath it. The owner
reproduced this with an Apple-SDK-only probe and drafted a Feedback report
(`measurements/apple-feedback-line-heights/report.md`); this record is about what the reading does
with the rectangles Apple returns today.

Wallace's page 290, captured with `tools/probes/capture-layout-fixture.swift`:

| line | y | top | height | text |
| ---: | ---: | ---: | ---: | --- |
| 1 | 695.98 | 707.96 | 11.98 | `The previous example could have been done in fewer steps if we had noticed` |
| 2 | 672.74 | 693.20 | **20.46** | `72= 36· 2, but often the time it takes to discover the larger perfect square is more` |
| 3 | 666.58 | 678.56 | 11.98 | `than it would take to simplify in several steps.` |

By their tops the three stand 14.76 and 14.64 points apart, which is the page's own leading — they
are consecutive lines of one paragraph, and `onStatedLeading` reads them as such. By their
rectangles, line 2's bottom is 5.82 points *below* line 3's top, and `continuesParagraph`'s bound
on how far two lines may overlap (`-0.4` of a body, 4.8 points here) refused it. The paragraph
broke in the middle of its own sentence.

## The rule

The page's own lines say what an ordinary line of each type size measures.
`LayoutReconstructor.ordinaryLineHeights` reads the lower quartile of the heights of a page's
lines at each rounded size — the lower quartile rather than the median because a page of
mathematics sets more tall lines than short ones, and page 290's median at 12 points is 13.30
against a true ordinary height of 11.98.

`BlockAssembler.gapBeneath` then measures the white under a line from that depth rather than from
the rectangle, and only where two conditions hold: the two rectangles **overlap**, and the upper
rectangle is **taller than an ordinary line of its size** by more than a quarter of a body. It
returns `max(gap, rect.maxY - ordinary - line.maxY)`, so the adjustment can bring a negative gap
back towards nothing and can never open one. No pair of lines the reading already joins is
separated by it, in either direction, which is what makes this safe to ask of every page.

On page 290: the ordinary height at 12 points is 11.98, line 2's rectangle is 20.46, and its own
depth ends at 693.20 − 11.98 = 681.22, which is 2.66 points above line 3. The paragraph reads as
one.

## What moved, book by book

Every cached source was converted with both executables at `--no-ocr` and fixed packaging
(`--package-identifier urn:uuid:identity --modification-date 2026-01-01T00:00:00Z`), one book at a
time, and each XHTML document summarized by its SHA-256, block count, character count and hashes
of its tag-stripped text and of that text's marks with whitespace removed.
`GPO-WARRENCOMMISSIONREPORT` and `noaa_61592_DS1` are skipped: they exceed the default output
budget and write no book.

**Nineteen of the twenty-two are byte-identical**, every document of every one — the 9/11 report,
the FAA handbook, Project Blue Book, the USCIS Arabic guide, the replay-clocks paper, *The Fed
Explained*, IRS Publication 596 in Chinese, the DGA, *Loper Bright*, *Our Flag*, *Agricultural
Research*, the CDC graphic novel, the NASA slides, the NTRS papers, the THM report, the Pro Se
complaint, the NBS paper, the USGS copper summary and the Warren suspect-text excerpt. Three move,
and all three are books that set mathematics inline:

| case | documents | blocks | what moved |
| --- | ---: | ---: | --- |
| wallace-algebra-2010 | 15 → 15 | 6,931 → 6,842 | 89 paragraphs the reading had broken mid-sentence read as one |
| census-rrs2002-01 | 2 → 2 | 385 → 366 | 19 of the same, where the break falls at a mathematical symbol |
| `20190030725` (cached, not in the manifest) | 2 → 2 | 380 → 378 | two subscript fragments rejoin their line |

**No text is gained, lost or reordered inside a paragraph.** Over the whole of Wallace, the
character multiset of the book's marks differs in exactly one character: ten fewer hyphens, which
are the line-end hyphens `HyphenRepair` resolves once the two halves stand in one paragraph
(`multipli-` / `cation` now reads `multiplication`). Over the whole census paper the multiset is
identical; what differs there is only where a figure falls relative to a paragraph that has
merged.

## What the joins are

All 91 of Wallace's join sites were read. Eighty-nine are the defect: a paragraph broken at a line
the page set taller, most of them mid-word or mid-sentence —
`…in slope-` / `intercept form.`, `…the fol-` / `lowing examples.`,
`Graph the points A(3, 2), … F (0, 2),` / `G(0, 0)`.

Two are not, and both are rows of a worked example rather than lines of prose:
`7· 3 Multiply 2+ 15 Add` takes `21 Solution 17 Solution`, and `Divide out common factors` takes
`(a + 2), (a + 2), (a + 1), (a +5)`. Both are rows the reading already merges across their two
printed columns before this rule sees them, which is the defect #210 and #212 track; the union
rectangle of such a merged row is taller than an ordinary line, so it is what this rule adjusts.
They are recorded rather than rounded off: 89 against 2 on this book, and the census paper's
nineteen all correct.

## Gates

`scripts/check-all.sh --fast` passes, exit status read directly. The corpus lane passes 18 of 18
covered cases, every case's `runPassed` and content assessment read from its own `result.json` and
`content-assessment.json`. All 677 Swift tests pass.

Two tests are added to `Tests/PDFReflowLibTests/ReadingOrderTests.swift`, both citing #230: page
290 from a checksum-pinned layout capture (`algebra-290-layout.json`), which pins the three
heights, the 5.82-point overlap, the ordinary height the page states and the joined paragraph; and
a control page of ordinary rectangles, where a line the page set a paragraph's space below still
opens its own block, because nothing overlaps and nothing is adjusted.

## What is not claimed

Page 290 and the two worked-example rows were read against the source; the other 88 join sites
were read as text and the rest of every book only through the per-document hashes above. This does
not address the other outcome of the same measurement — a display cropped into an image because
its rectangle is oversized, which is #213 — and it does not make PDFKit's rectangles right. It
says only that where a page's own lines state what an ordinary line measures, a rectangle grown
past that is not evidence that two lines overlap.
