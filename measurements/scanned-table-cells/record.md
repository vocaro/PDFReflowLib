# A grid is not a table: what recognition makes of the Blue Book's table pages

Measured under [#31](https://github.com/vocaro/PDFReflowLib/issues/31), baseline `9dfbd4b`,
2026-09-21, macOS 27 / Xcode 27, arm64, release CLI and probes at library defaults with a fixed
package identifier and modification date. Source: `cia-blue-book-14-1955`, SHA-256
`90e05e77…52ee3`, physical pages 74 (printed 64) and 150 (printed 141), read visually at 150 DPI
before any expectation was written.

[#19](https://github.com/vocaro/PDFReflowLib/issues/19) established this book's warning and
refusal contract. #31 asks the separate question: can the tables on its scanned pages be
*detected* and their row and column structure *reconstructed* — by fresh OCR, by layout analysis,
or, failing both, by an explicit warned image fallback per cell or region? This is what the two
pages the issue names actually offer.

## What the two pages print

**Page 74** is one typewritten table, `TABLE IV CHI SQUARE TEST OF KNOWNS VERSUS UNKNOWNS ON THE
BASIS OF SHAPE`: a `Shape` column and four numeric columns (`Number of KNOWNS`, `Adjusted Number
of KNOWNS (K)`, `Number of UNKNOWNS (n)`, `x², (K-n)²/K`) over eight body rows and a `Total`, then
`Degrees of freedom 6`, `5% 12.6` and `1% 16.8`. Horizontal rules, no vertical ones. The whole
page is one placed raster covering the crop box; a punched margin prints a black mark down the
right edge.

**Page 150** is `TABLE A63 EVALUATION OF ALL SIGHTINGS FOR ALL YEARS BY COLORS REPORTED`: four
stacked ruled grids, each 25 columns wide — an `Evaluation` label column and four color groups of
`Number` and `Per Cent` over `Certain`, `Doubtful`, `Total` — with eleven evaluation rows and a
`Total`. Group headings and row labels are hand-lettered or typed; **every value in the body is
written by hand in ink**.

## 1. The inherited text layer cannot give rows, let alone cells

Extraction of the two pages (`tools/probes/capture-layout-fixture.swift`) returns, for each
printed row, **one line with no cell geometry at all**: the columns survive only as runs of spaces
inside one string.

| Page | Lines | Graphics | What a numeric row comes back as |
| ---: | ---: | ---: | --- |
| 74 | 30 | 1 (the page-sized raster) | `Elliptical 838 206 195 0.59 I` |
| 150 | 104 | 1 (the page-sized raster) | `II 'i "J.7 "·' r,_3 ,_q 5 I I, ~..l Al 1·3 s 7 1, A.~ r,.:i A.4 I t) I t).J o.l r,. I` |

Three further facts close the layout-analysis route on this book:

- **The rows are not even in order.** PDFKit merges the punched margin's mark into alternate rows,
  so those rows' rectangles are inflated from ~11 pt to ~31 pt tall and their `minY` is dragged
  down. Sorted top down, page 74's rows come back `Elliptical` (431.2), `Rocket and aircraft`
  (424.5), `Teardrop, lenticular,` (397.1), `Meteor or comet` (395.4) — the source prints `Meteor
  or comet` *above* `Teardrop`.
- **`rowBlocks` cannot read them.** Its run test needs one leading; the margin merge makes page
  74's row-to-row drops 6.7, 27.4, 1.7, 35.8, 3.3, 32.0 and 6.6 pt. On page 150 the type sizes of
  twelve consecutive numeric rows are 10.6, 7.2, 9.0, 6.0, 6.4, 7.6, 7.2, 6.2, 16.1, 8.3, 8.8 and
  7.5, so the one-size test fails as well. This confirms, page by page, what #257 recorded for the
  book's other table pages.
- **Whitespace is not a column boundary.** Page 74's layer reads `Meteor or comet 55 14 4 7. 14`
  and `Flame 96 24 10 8. 17`: splitting on spaces gives six tokens for a five-column row, and the
  sixth is half of a number.

Today's conversion shows the cost directly. The reader is given page 74 as, among others, the
paragraph `Rocket and aircraft 80 20 33 8.45 Meteor or comet 55 14 4 7. 14 I` — two printed rows
run together — and page 150 as 30 paragraphs of `/3J vF oR /.'.uw1N6' f;i;.vr` and the like, with
one page-sized reference picture and the page-wide `unverifiedTextLayer` notice. No signal names
a table.

## 2. Fresh OCR finds the tables on both pages and reads the cells of neither

Vision's `RecognizeDocumentsRequest` returns document *tables*, with rows, columns and per-cell
transcriptions. Run through this library's own rasterizer and reading
(`tools/probes/probe-table-cell-evidence.swift`):

| Page | Tables located | Grid | Cells transcribed |
| ---: | ---: | --- | --- |
| 74 | 1 | 12 × 5 | 50 of 60 (83%) |
| 150 | 2 | 15 × 26 and 15 × 25 | 104 of 390 (27%) and 49 of 375 (13%) |

**Detection works.** Page 74's grid stands on the table (74.4, 225.5, 456.3 × 282.8 pt); page
150's two stand on the second and fourth of its four printed grids. Repeated runs on one host
reproduce these exactly.

**Reconstruction does not.** Page 150's reading misses two of the page's four tables before a cell
is read, rules one of the two it does return 26 columns wide where the page rules 25, and fills
what it returns with, among others:

| Cell | The page's own writing |
| --- | --- |
| `CRASSE DR GLONINS CRAVGE` | `ORANGE OR GLOWING ORANGE` |
| `GRKEN OR GUWING GREEN` | `GREEN OR GLOWING GREEN` |
| `Cotan/ CaEFa Toni Cetas CaRiN/ Toal Setae \| Deatihi Tetl` | `Certain Doubtful Total` ×4 |
| `0,3 09 k`, `39.06`, `٥٠١١`, `S122` | the hand-written figures of row `0-Balloon` and after |

Neither `0-Balloon` nor any of its values (`18 11 29 0.6 0.3 0.9`) appears anywhere in the grid.

And page 74, the page the recognizer reads well, still is not fit to publish as cells:

| Row as the page prints it | Row as the reading returns it |
| --- | --- |
| `Meteor or comet 55 14 4 7.14` | `Meteor or comet 55 14 <empty> 7.14` |
| `Flame 96 24 10 8.17` | `Flame 96 24 10 8,17` |
| `Total 1765 434 434 29.05` | `Total 1765 434 434 29.05îŚę` |

One value dropped and two corrupted in a table of forty numbers. Nothing in either result says
which of the two pages was read: both come back as tables, with no confidence on the grid and
none on a cell.

## 3. The measurement that separates them

A table the recognizer read fills most of its grid; a grid it drew over writing it could not read
is ruled wider than the page and left mostly empty, because only the few pieces it transcribed
have anywhere to go. Measured over this book and one born-digital control:

| Table | Grid | Transcribed |
| --- | --- | ---: |
| USGS copper 1, tariff | 6 × 3 | 17 of 18 (94%) |
| Blue Book 74, `TABLE IV` | 12 × 5 | 50 of 60 (83%) |
| USGS copper 1, salient statistics | 24 × 6 | 97 of 144 (67%) |
| USGS copper 2, world production | 21 × 6 | 79 of 126 (63%) |
| **Blue Book 150, first grid** | 15 × 26 | **104 of 390 (27%)** |
| **Blue Book 150, second grid** | 15 × 25 | **49 of 375 (13%)** |

Thirty-six points separate the emptiest table the recognizer read from the fullest it did not,
with nothing between them. `TableCellEvidence.minimumTranscribedCells` is half. The share is read
from the grid, not from the cells' text, so the rule needs no lexicon.

Negative controls, same probe, same defaults: the Blue Book's prose pages 4, 9, 12, 111 and 250,
Our Flag's flag-size table pages 22–25, and CDC's comic pages 13 and 17 return **no table at
all**, so no prose page is judged by this measure and none can become one.

## 4. What changed, and what did not

Taken: the **explicit warned image fallback per region**, not reconstruction.

- Every table a recognition locates already becomes a crop. That crop is now described as
  `Table from page N, preserved as an image. Its cells are not transcribed; read them in this
  picture.` instead of `Preserved region from page N`. It states no row, column or cell count,
  because on page 150 the grid the reading returned is not the page's.
- A located table under the half rule raises `unreadTableCells`, **once per table**, beside that
  picture: *"A table on this page is preserved as an image: OCR found the table but transcribed
  only 13% of the 375 cells in the grid it returned, so its rows, columns and cells are not
  reconstructed and no cell of it reaches the reflowed text."* It reports a measurement of the
  reading and never a claim about the page.
- No cell is transcribed into the reader's text on either side of the rule, so a table this
  measure believes is signaled, not repaired. Section 2's page-74 rows are why.

Not taken, and why: transcribing Vision's cells would publish `Flame 96 24 10 8,17` and an empty
`Number of UNKNOWNS` for `Meteor or comet` under this book's name on its best page, and 26 columns
of `٥٠١١` on its worst.

## 5. The ceiling this leaves, honestly

Under the library's default `.automatic` OCR policy **this book is never recognized**: the
baseline conversion at `9dfbd4b` reports `recognizedPageCount = 0` over all 312 pages. So the rule
this change adds does not reach pages 74 and 150 in the book's own conversion, and those pages'
output is what it was. What reaches them is the measurement above and the regressions that pin it.

Why the layer stands is worth recording exactly, because the obvious answer is wrong. It is *not*
the digit exemption. `EnglishText.wordCounts` over each page's extracted layer:

| Page | Tokens | Holding a digit | Judged | English | Misread | Words | `wordFinding` |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 74 | 110 | 42 (38%) | 64 | 60 | 1 | 71 | nil |
| 150 | 613 | 150 (24%) | 254 | 168 | 23 | 446 | nil |

Page 150 is exempted from the word tests by the 20% digit share, but it would pass them anyway:
counting only tokens that *are* numbers puts the share at 16%, and the layer is then judged and
still found plausible — 168 of 254 judged words are English (66%, against a floor of 50%) and 23
of 446 are misread (5%, against a floor of 10%). The ink test never runs either: it is gated at
`maximumWordsForInkTest`, 32 English words, and this layer has 168.

The layer passes because the page's *printed* matter is genuinely English — `Evaluation`,
`Balloon`, `Astronomical`, `Certain Doubtful Total`, `Total` — while the hand-written body it
fails to transcribe comes back as `/J.() ,.o o.o I I 2 IJ./`, which is symbols and one- and
two-character tokens rather than damaged *words*, and so counts against nothing. A page can
therefore transcribe every label of a table correctly, transcribe none of its values, and be
called a plausible layer. That is a gap in `TextLayerPlausibility`, not in this rule, and it is
filed separately as [#275](https://github.com/vocaro/PDFReflowLib/issues/275).

## Reproducing

```sh
swiftc $(python3 tools/pdfreflow_tools/swift_sources.py probe-table-cell-evidence.swift) \
  -o /tmp/probe-table-cell-evidence
/tmp/probe-table-cell-evidence cia-blue-book-14-1955 4 9 12 74 111 150 250
/tmp/probe-table-cell-evidence usgs-mcs2025-copper 1 2
/tmp/probe-table-cell-evidence gpo-our-flag-2003 22 23 24 25
/tmp/probe-table-cell-evidence cdc-zombie-pandemic-2011 13 17
```

The grids quoted above are committed as `Tests/PDFReflowLibTests/fixtures/blue-74-150-tables.json`
and replayed by `Tests/PDFReflowLibTests/ScannedTableTests.swift`, because Vision's reading of a
page is not stable across compiled model sets
([#173](https://github.com/vocaro/PDFReflowLib/issues/173)).
