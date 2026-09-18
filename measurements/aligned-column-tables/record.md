# Tables of aligned columns (#150, #137)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, Xcode 27, release CLIs.
Work on `f3840f4` (branch `claude/fable-agents-coordination-d95da7`). Date 2026-09-17.

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline | `git archive f3840f4` | `28a89d440ad1622c51ace2ceb7eacd4df53b8b46099e6fa0f5750b1e00cb3f52` |
| candidate | this tree on `f3840f4` | `2882e15636f27eeb52c486c127041cb5b25333f3a05e25759fc2fa8985f4bdbc` |
| probe | `tools/probe-raster-environment.swift` (baseline tree) | `ba7f59525cdecf1e5e7749bfd41ff5d3233d703fb4fc51dce5065d56e06b0a4c` |

Both converters were launched as `pdf-reflow` from separate directories (`tools/case.py`), so every
lane shares one Vision model cache name and compiled programs. No PDF or EPUB is committed; each
lane's outputs were deleted after its comparison and page review, and `lane-summaries/` keeps the
run summaries and comparisons. Only English sources were read.

## Evidence

**Census pages 12 and 15** (`census-rrs2002-01`). Four tables, each a title (`Table 2. Domingo Data
Reidentification Rates`), one or two header rows, a rule under the header and thirteen body rows at
10.9-point leading in 9-point type; no cell rule, no shading, lower-case headings. After #143's
decoding PDFKit returns most rows as one line (`rnkswp05 0.8861 0.9620`; Table 3 and Table 7 split
some rows into the label and one line of six numbers). PDFKit's one-character selections give the
columns (`words.swift`-style dump, 0.25-em word gaps):

| Table | Columns | Channels between columns (ems, clear through every body row) | Alignment |
| --- | ---: | --- | --- |
| 2 (p. 12) | 3 | 0.81 (after `scalmixadd01`), 1.19 | labels flush left at 244.6; numbers flush right at 331.3, 367.6 |
| 3 (p. 12) | 7 | 0.99 after the labels, then 0.78–0.99 | numbers flush right (`6.11` at 260.5–276.8 under `46.11` at 256.0–276.8) |
| 7 (p. 15) | 7 | 0.78–0.99 | as Table 3 |
| 8 (p. 15) | 10 | **0.33** between every column, the width of a word space | numbers flush right at 237.6, 261.3, … 455.5 |

The header words sit over their columns: Table 2's `d metric l metric` is one line whose word gaps
(0.49, 0.32, 0.48 em) are no wider than the gap inside a heading, but `d metric` is centred on the
second column to 0.05 pt and `l metric` on the third to 0.1 pt; Table 3's `Ascore … Sscore` words are
each within 3 pt (0.33 em) of their column's centre; `d Metric` and `l Metric` stand 5.96 em apart,
each centred over three scores (292.3 against 295.4 for the three columns; `l Metric` ends 2.0 pt
short of the sixth column's right edge, so it is near but not on it).

**FAA page 410** (`faa-phak-8083-25c`). The VOR/VORTAC table in the left page column: `Class` at
74.5, altitudes flush left at 144.0, distances flush right at 309.0 (`25`, `40`, `40`, `100`, `130`,
`100`); channels 6.2 em and 1.19 em; the fourth H row wraps (`Within the conterminous 48 states` /
`only, between 14,500 and 17,999'`) with its `100` set on the second line. `Distance` and the
letter-spaced `(Miles)` both end at 309.0. The right page column starts 12 pt (1.2 em) away. FAA
tags the wrapped line and its `100` as one paragraph (group 5771, two lines) and leaves the other
cells untagged.

**The other #137 pages** measured the same way:

- 9/11 pages 50–51: two flights' timelines side by side, four columns (times at 39.7 and 201.7,
  events at 75.7 and 240.7). The flights' entries start on different baselines: a line continuing
  flight A's event carries flight B's next time and event.
- 9/11 pages 447–448: two columns (abbreviation at 44.7 or 39.7, expansion at 134.7 or 129.7), gutters
  3.5–7.3 em, expansions up to 14.7 em; no numbers, no header row.
- Our Flag page 4: two roster columns at 45.0 and 220.4, entries 19.6–22 ems wide in 7-point type,
  each followed by an indented title line (`Chairman`, `Vice Chairman`); no numbers.

## Prototype survey: what alignment alone would read (`prototype/grid.swift`)

Every English source was read glyph by glyph (PDFKit's one-character selections): runs of baselines
at no more than 1.8 ems' leading in one size, split into columns at channels at least 0.6 em wide
clear through the run, every column at most fifteen ems wide and flush left or right, every row
filling every column (a baseline without first-column text continuing the row above, continuing at
most one filled cell), at least three rows, no column of list markers. With nothing else required
(`prototype/unconstrained/`):

| Source | Runs | What they are |
| --- | ---: | --- |
| wallace-algebra-2010 | 163 | worked examples, each step beside its comment (`2+3(5)2 \| Exponents`); exercise grids (`1) 2−(−3a−8)=1 \| 2) 2(−3n+8)=−20`) |
| cia-blue-book-14-1955 | 74 | scanned typescript tables through the inherited OCR layer, garbled (the pages are recognized) |
| faa-phak-8083-25c | 14 | **410** (the table); 416 NDB classes; 207–208 altimeter arithmetic; 459 a flight-planning figure (preserved); 463–472 the glossary's two page columns read as one table |
| gpo-911-2004 | 14 | 9 list of figures; 13–14 staff roster (names over titles); 50–51 the flight headings and timeline fragments; 447–448 abbreviations; 454 names |
| ntrs-20190030725-dasc-2019 | 10 | 6 severity matrix (ruled, preserved); 8 schedule labels inside a figure |
| census-rrs2002-01 | 6 | 12, 14, 15 (text undecoded in this tool) |
| fed-explained-2021 | 4 | 9, 39 private-use glyphs; 75, 103 prose columns inside figures |
| usgs-mcs2025-copper | 2 | statistics tables (preserved, #36) |
| ntrs-20210020887-techport-thm-2021 | 2 | contents |
| dga-2025-2030, usda-ars-agresearch-2012-11 | 1 each | signature block; masthead telephone list |
| Warren, Our Flag, CDC, NBS, arXiv, SCOTUS, pro se, GWL, Earthdata | 0 | |

Alignment finds the tables, and many things that are not: Wallace's worked examples set as a step
beside its comment (`2+3(5)2 | Exponents`), its exercise grids, FAA's glossary set in two page
columns (`BCA—benefit/cost analysis | radar approach control`, each column its own list), 9/11's
staff roster (names over titles in two columns), the flight headings above the timelines, the Fed's
prose columns inside figures, the DGA's signature block, the USDA masthead's telephone list and
TechPort's contents. None of these has a column holding one number in every row under a heading.
Every intended table does: Census's scores, FAA's distances. The rule therefore also requires a
numeric column and a header.

## Rule

`ColumnGrid` (`Sources/PDFReflowLib/ColumnGrid.swift`) reads the grid; extraction splits merged rows
into cells with it, and layout reads the cells as a table with it
(`BorderlessTableDetector.alignedTables`).

- **Candidates.** At least three pieces ending in a number (`0.8861`, `25`, `8:46:40`; not `45.`)
  on baselines at most 3.6 ems apart share a right edge within a quarter em. The window is the band
  of ink holding that edge between 0.6-em channels: in extraction the merged rows' band; in layout,
  where cells are separate lines, the run of bands whose pieces are each at most fifteen ems wide, so
  FAA's prose page column 1.2 em away stays out. The rows are the baselines from three leadings
  above the stack to two below, restricted to the window.
- **Body.** A run of baselines at no more than 1.8 ems' leading in one size. Columns are ink between
  channels at least 0.6 em wide clear through every baseline and at least twice any gap inside a
  cell; a column whose last piece on every baseline is a number, those numbers sharing a right edge
  within a quarter em and ending after the rest of the column, splits the stack off as a column of
  its own (Table 8). Every column at most fifteen ems wide and flush left or right within a quarter
  em. A baseline with first-column text opens a row; one without continues the open row, adding to
  at most one cell that already holds text (FAA's wrap, and its `100` fills the empty distance
  cell; the second flight's new entry on 9/11 page 50 would add to two). Every row fills every
  column; at least three rows; one column holds exactly one number in every row; no column opens
  every row with a list marker (`1)`, `a.`, a bullet); no baseline holds dot leaders.
- **Header.** One to three baselines directly above the body, each within 1.8 ems and in its size,
  inside its width widened by an em. A header line divides where its words' centres fall over
  different columns and each part is centred on its column within half an em (`d metric | l
  metric`), and at 0.6-em gaps. The lowest row places its cells in the column each aligns with (left
  edge on a flush-left column, right edge on a flush-right one) or overlaps most, in at least two
  columns, with a heading over every numeric column; a row with first-column text and numbers over
  every numeric column reads as a body row and heads nothing (Census page 14's first row under its
  undivided heading line), while years may head their columns over an empty label heading. A higher row's cell whose edge and the edge of the heading beneath both lie
  within a tenth of an em of a column's flush edge continues that heading (`Distance` over
  `(Miles)`); its other cells share the columns beneath by nearest centre, each a contiguous span
  containing its centre (`d Metric` over three scores). A body without a header is no table.
- **Cutting (extraction).** The lines of a candidate region are measured into words; each line whose
  words fall into more than one cell is cut between them. A cell takes its words' share of the
  line's own styled, repaired text when the line has one word per glyph word (PDFKit's selections
  inside a Census row report the index glyphs undecoded, so re-selecting would undo #143), and
  PDFKit's rectangle selections otherwise; the cells must spell the line. The cuts are kept only
  when every line of the grid cuts and the cut lines read as the same grid (rows, columns, every
  piece placed) in layout's reading.
- **Edges.** Text outside the window within two ems of the grid's edge on at least half its body's
  baselines, and nowhere above or below the table, continues the grid past its edge: a label column
  too wide to be one, whose numbers alone would otherwise read as the table. A page column beside
  the table runs on above or below it and does not count.
- **Layout.** Lines tagged as headings are never cells; a line tagged as a paragraph is one only when
  every line of its paragraph is in the table (FAA's group 5771). Header cells span their columns
  (an empty header column is an empty cell); body cells span one; first cells name their rows by
  #121's rule (Census's distinct labels do, FAA's repeated `H` does not). Captions are not inferred:
  the titles are set in the cells' size, so `ShadedTableDetector.caption` finds no title, and they
  stay paragraphs before their tables.
- **Guard (#143).** `PDFReflowLibPipeline.holdsUnreadNumericGrid`: a repaired page keeps #38's path
  only for a numeric grid outside the tables layout reads. Extraction has already split a read
  table's rows into cells, which hold one number each; the explicit exclusion also releases a table
  whose cells each hold two decimals (a range beside its value, tested).

## Library survey (`survey.swift`, `survey/`)

The same reading over every page of every English source, after extraction as the pipeline does it:

| Source | Tables | Pages |
| --- | ---: | --- |
| census-rrs2002-01 | 8 | 11, 12 (Tables 2, 3), 13 (two), 15 (Tables 7, 8), 16 |
| faa-phak-8083-25c | 1 | 410 |
| ntrs-20190030725-dasc-2019 | 1 | 6 (the severity matrix) |
| every other English source, Warren and NOAA included | 0 | |

Census pages 11, 13 and 16 hold the same kind of table, but those pages keep OCR for their math
fonts (#143), so their output does not change. Census page 14's table has PDFKit's own split rows
under a header line PDFKit keeps whole (`Total File Matches 20% Zone Matches`, whose words
extraction measures only where it splits rows), so its lowest heading row would be the first body
row, which reads as a body row and heads nothing; the page keeps OCR anyway. DASC page
6's severity matrix is read, but it is ruled and preserved as an image, so its lines never reach
layout.

## Before and after

`tools/run_corpus_regressions.py --case <id>` (EPUBCheck, probe, `--execution-context
host-terminal`), one case per call for each binary, then `tools/compare_conversion_runs.py
--allow-different-converters` (`tools/case.py`). The contracts below were updated first, so the
baseline fails them. NOAA was not run: it has no index-glyph font (#143's survey) and the library
survey reads no table in it, so neither the split nor the guard can change it.

| Case | Baseline | Candidate (content checks) | Wall time, base → cand | Changed pages |
| --- | --- | --- | --- | --- |
| census-rrs2002-01 | fails 11 new checks | pass (80) | 9 → 8 s | 12, 13, 14, 15, 16, 17, 18, 19 |
| faa-phak-8083-25c | fails its 1 new check | pass (561) | 55 → 54 s | 410 |
| wallace-algebra-2010 | pass | pass (288) | 35 → 33 s | none |
| gpo-911-2004 | pass | pass (306) | 18 → 18 s | none |
| fed-explained-2021 | pass | pass (201) | 8 → 8 s | none |
| gpo-our-flag-2003 | pass | pass (134) | 5 → 5 s | none |
| ntrs-20190030725-dasc-2019 | pass | pass (246) | 3 → 3 s | none |
| dga-2025-2030 | pass | pass (96) | 3 → 3 s | none |
| cdc-zombie-pandemic-2011 | pass | pass (60) | 16 → 16 s | none |
| cia-blue-book-14-1955 | pass | pass (10) | 50 → 54 s | none |
| usgs-mcs2025-copper | pass | pass (51) | 4 → 4 s | none |
| scotus-loper-bright-2024 | pass | pass (115) | 4 → 4 s | none |
| nbs-jres-geltman-1977 | pass | pass (64) | 5 → 5 s | none |
| arxiv-replay-clocks-2023 | pass | pass (71) | 4 → 4 s | none |
| uscourts-pro-se-1-2016 | pass | pass (162) | 2 → 2 s | none |
| ntrs-20200002975-gwl-2020 | pass | pass (286) | 4 → 4 s | none |
| usda-ars-agresearch-2012-11 | pass | pass (242) | 8 → 8 s | none |
| ntrs-20180003024-earthdata-slides-2018 | pass | pass (225) | 3 → 3 s | none |
| ntrs-20210020887-techport-thm-2021 | pass | pass (72) | 3 → 2 s | none |

Census and FAA were run with the final candidate (`2882e156…`); the other cases with `f67cb35d…`,
whose source differs from the final tree only in comments (which move line numbers, so the binaries'
hashes differ). NOAA (no index-glyph font, no table in the library survey) and the Arabic and
Chinese cases were not run. Wall times include EPUBCheck and the content contract; other agents'
lanes shared the machine.

**Census review** (candidate EPUB against 150-dpi renders of pages 12 and 15). Page 12: `Table 2.
Domingo Data Reidentiﬁcation Rates` as a paragraph (bold `Table 2.`), then a table with an empty
label heading over `d metric` and `l metric` (`d` and `l` italic) and 13 rows, each label a row
header, every value equal to the render (`rnkswp05 0.8861 0.9620` … `scalmixadd20 0.0269 0.1241`);
`Table 3. Domingo Data Scoring Metrics`, then a table whose first header row is an empty cell,
`d Metric` spanning three columns and `l Metric` spanning three, the second `Ascore Dscore Sscore
Ascore Dscore Sscore`, and 13 rows equal to the render (`rnkswp15 6.11 8.36 5.91 20.87 23.12 30.67`).
Page 15: Table 7 (`Full File Matches` and `20% Zone Matches` each over three scores; `add01_sw 0.70
16.80 11.65 0.65 16.75 11.60`) and Table 8 (nine headings `IL1 … s2`; `rnkswp05 0.114 0.081 1.407
39.020 158.950 0.123 48.875 39.923 40.141`, `add_sw01 …`), every row equal to the render. Both pages
lose their three images (two table crops and the source-page reference) and `damagedTextEncoding`
/ `ocrUsed`; the baseline's OCR headings `Table 2.`/`Table 3.` (h5/h6) become paragraphs. Pages 13,
14, 16, 18 and 19 differ only in `headingRanks` (their heading tags are identical; the book's
heading ranking lost page 12's two OCR headings), and their OCR text is identical (5,218 words in
both runs). The report records 15 recognized pages (17 before) and 45 images (51).

**FAA review** (page 410 against a 100-dpi render). The table reads `Class | Altitudes | Distance (
M i l e s )` over six rows: `T | 12,000' and below | 25`, `L | Below 18,000' | 40`, `H | Below
14,500' | 40`, `H | Within the conterminous 48 states only, between 14,500 and 17,999' | 100`, `H |
18,000'—FL 450 | 130`, `H | FL 450—60,000' | 100`, all cells `<td>`. Before, the page read
`Class Altitudes ( M i l e s )` and the rows as paragraphs (`T 12,000' and below 25 L Below 18,000'
40 …`). `VOR/VORTAC NAVAIDS` and `Normal Usable Altitudes and Radius Distances` stay the paragraphs
above, and the prose around the table and the right page column are unchanged. `( M i l e s )` is
PDFKit's reading of the letter-spaced `(Miles)`, the same in both runs (follow-up below).

## Contracts

`corpus/regressions.json` (one entry per page):

- `census-rrs2002-01` page 12: `absentWarningCodes` `damagedTextEncoding`, `ocrUsed`; `maximumImages:
  0`; the two titles as `paragraphs`; `absentText` the shifted forms `Wdeoh 51` and `uqnvzs38` (the
  run-together forms #143 recorded, `0.9620 rnkswp10`, are dropped: the spine reader joins a table's
  cells with spaces, so a row's last value and the next row's label meet in the page text; the
  `tableCells` rows now pin each value to its own cell and row); `tableCells` for
  Table 2 (columns `d metric`, `l metric`; rows `rnkswp05`, `add05`, `mixadd20`, `scalmixadd20`) and
  Table 3 (header paths `d Metric Ascore` … `l Metric Sscore`; rows `rnkswp05`, `rnkswp15`,
  `mixadd05`, `scalmixadd20`), each with `headerCells` and `rowHeaders` true. Replaces
  `minimumImages: 3` and `warningCodesAnyOf: damagedTextEncoding`.
- Page 15: the same warnings, images and titles; `absentText` `Wdeoh ;1` and `uqnvzs38` in place of
  the run-together forms; `tableCells` for Table 7 (paths
  `Full File Matches Ascore` … `20% Zone Matches Sscore`; rows `rnkswp05`, `add01_sw`,
  `scalmixadd20`) and Table 8 (`IL1` … `s2`; rows `rnkswp05`, `add_sw01`, `scalmixadd20`).
- `faa-phak-8083-25c` page 410 gains `tableCells`: columns `Class`, `Altitudes`, the six rows,
  `headerCells` true and `rowHeaders` false. The distance column is not named, since its heading
  reads `Distance ( M i l e s )` until PDFKit's letter spacing is repaired; the Swift test pins the
  distances.

Every value was read from the renders. The baseline fails exactly the new checks (Census 11: on
page 12 the two titles, two tables, images and warnings; on page 15 the Table 8 title, whose Table 7
title OCR already reads as a paragraph, two tables, images and warnings; FAA 1: page 410's table);
the candidate passes.

## Tests

`Tests/PDFReflowLibTests/AlignedColumnTablesTests.swift`, 14 functions:

| Test | Reproducer / control |
| --- | --- |
| `censusPage12TablesReadWithTheirHeadersAndRowLabels` | `census-12`: both tables, spans `[1, 3, 3]`, row headers, titles as paragraphs, markup. |
| `censusPage15TablesReadIncludingNumbersAWordSpaceApart` | `census-15`: Tables 7 and 8. |
| `censusRowsAsPDFKitMergesThemAreNoTableAndKeepTheNumericGridGuard` | Reproducer: rows re-merged read as no table and keep the guard. |
| `faa410ServiceVolumesReadAsAThreeColumnTable` | `faa-410`: the table, no row headers, prose kept; re-merged rows read as no table. |
| `faa410TableNeedsTheWholeTaggedParagraphInside` | FAA's paragraph tag admitted; a tag reaching outside, a heading tag. |
| `alignedColumnsUnderAHeaderReadAsATable` | Synthetic Table 2. |
| `alignedColumnsWithoutTableEvidenceKeepTheirReflow` | Read in layout and directly as extraction reads words: no header, two rows, cells ending in numbers without a numeric column, a marker column, leaders, a label column wider than fifteen ems, a body row above, a ragged column, a channel narrower than twice the gaps inside the cells beside it (and its control). |
| `aContinuationLineContinuesOneCellAndFillsEmptyOnes` | FAA's wrap; timelines side by side. |
| `higherHeadingsSpanTheColumnsNearestThemOrContinueAnAlignedHeading` | Centred group headings, a near miss, `Distance` over `(Miles)`. |
| `aNumericGridATableReadsNoLongerHoldsARepairedPage` | Range cells: guard released by the table, held without its header. |
| `aProseColumnBesideTheTableStaysOutOfIt` | A prose page column 1.3 em away running above and below the table, two of its baselines on the table's. |
| `mergedRowsOfAnAlignedTableAreSplitIntoCells` | Synthetic PDF, one TJ per row: split; without the header, whole. |
| `aShiftedFontTableUnderAHeaderReflowsNativelyAsATable` | End to end, `G<code + 3>` font: the table page reflows natively with decoded cells under `.never` and `.automatic`; the same rows without a header keep `damagedTextEncoding`. |
| `styledTextDividesAtItsWordsIntoCells` | Slicing keeps styles; wrong counts and linked markers give none. |

Fixtures `census-12`, `census-15` and `faa-410` were captured on this tree with
`tools/capture-layout-fixture.swift`, which now decodes index glyphs as the pipeline does (its build
command gains `GlyphIndexDecoder.swift`, `TextEncodingCheck.swift` and `ColumnGrid.swift`).

Negative controls (`tools/mutate.py`, `negative-mutations.txt`), each over the table and index-glyph
suites (AlignedColumnTables, TableHeadersAndBorderless, TableLeftovers, TableCaption,
RuledTablesAndHeaderRules, TintedBox, GlyphIndexDecoding):

| Part disabled | Failing tests |
| --- | --- |
| no numeric column | `alignedColumnsWithoutTableEvidenceKeepTheirReflow` |
| no header | `aNumericGridATableReadsNoLongerHoldsARepairedPage`, `aShiftedFontTableUnderAHeaderReflowsNativelyAsATable`, `alignedColumnsWithoutTableEvidenceKeepTheirReflow`, `mergedRowsOfAnAlignedTableAreSplitIntoCells` |
| numeric columns need no heading | `faa410TableNeedsTheWholeTaggedParagraphInside` |
| a body row may head the body | `aShiftedFontTableUnderAHeaderReflowsNativelyAsATable`, `alignedColumnsWithoutTableEvidenceKeepTheirReflow`, `faa410TableNeedsTheWholeTaggedParagraphInside`, `mergedRowsOfAnAlignedTableAreSplitIntoCells` |
| columns need not be flush | `alignedColumnsWithoutTableEvidenceKeepTheirReflow` |
| continuation continues any cells | `aContinuationLineContinuesOneCellAndFillsEmptyOnes` |
| marker columns allowed | `alignedColumnsWithoutTableEvidenceKeepTheirReflow` |
| leaders allowed | `alignedColumnsWithoutTableEvidenceKeepTheirReflow` |
| no fifteen-em cell | `alignedColumnsWithoutTableEvidenceKeepTheirReflow` |
| no number stacks a word space apart | `censusPage15TablesReadIncludingNumbersAWordSpaceApart` |
| no in-cell gap test | `alignedColumnsWithoutTableEvidenceKeepTheirReflow` |
| headings continue at a quarter em | `censusPage12TablesReadWithTheirHeadersAndRowLabels`, `higherHeadingsSpanTheColumnsNearestThemOrContinueAnAlignedHeading` |
| no centred header division | `aProseColumnBesideTheTableStaysOutOfIt`, `alignedColumnsUnderAHeaderReadAsATable`, `alignedColumnsWithoutTableEvidenceKeepTheirReflow`, `censusPage12TablesReadWithTheirHeadersAndRowLabels`, `censusPage15TablesReadIncludingNumbersAWordSpaceApart`, `higherHeadingsSpanTheColumnsNearestThemOrContinueAnAlignedHeading` |
| layout window takes prose columns | `aProseColumnBesideTheTableStaysOutOfIt`, `faa410ServiceVolumesReadAsAThreeColumnTable`, `faa410TableNeedsTheWholeTaggedParagraphInside` |
| grids may continue past their edge | `alignedColumnsWithoutTableEvidenceKeepTheirReflow` |
| page columns count as continuing | `aProseColumnBesideTheTableStaysOutOfIt` |
| tagged paragraphs anywhere | `faa410TableNeedsTheWholeTaggedParagraphInside` |
| heading-tagged lines are cells | `faa410TableNeedsTheWholeTaggedParagraphInside` |
| cells re-selected, not sliced | `aShiftedFontTableUnderAHeaderReflowsNativelyAsATable` |
| no split | `aShiftedFontTableUnderAHeaderReflowsNativelyAsATable`, `mergedRowsOfAnAlignedTableAreSplitIntoCells` |
| guard ignores read tables | `aNumericGridATableReadsNoLongerHoldsARepairedPage` |

Every mutation fails at least one test, and none fails a test of the other table readers.

## Verification

- `swift build -c release`: clean. `swift test`: 917 pass (903 on `f3840f4`, and the 14 above).
- `python3 -m unittest discover -s tools -p 'test_*.py'`: 242 pass.
- `scripts/check-all.sh --fast`: exit 0 (917 Swift, 242 Python, doc counts current, 8/8 fresh
  concurrency processes, fixture, policy and rejection conversions, byte-identical repeat
  conversions). The concurrency probe compiles `NativeTextReader.swift` from a fixed list, which
  gains `ColumnGrid.swift` (`tools/check_pdfkit_concurrency.py`), as do the documented capture
  commands.
- The three fixtures recaptured on the final tree are byte-identical to the committed ones.
- Corpus lanes above, 73–81 GB free throughout; each lane's outputs were deleted after review.

Commands:

```sh
python3 measurements/aligned-column-tables/tools/case.py <case-id>     # ALIGNED_TABLES_WORK=<dir with bin/{base,cand}/pdf-reflow, bin/probe>
python3 measurements/aligned-column-tables/tools/mutate.py <log-dir>
swiftc -O measurements/aligned-column-tables/prototype/grid.swift -o <scratch>/grid
<scratch>/grid corpus/cache/<file>.pdf > measurements/aligned-column-tables/prototype/unconstrained/<case>.txt
# survey.swift: build and run as its header says
```

## Scope of #137

Covered: FAA page 410. Not covered, each for a measured reason:

- **9/11 pages 50–51** are two tables side by side. Read as one grid, a line continuing flight A's
  event carries flight B's next entry, so the grid fails (a continuation adds to two filled cells);
  without that test the rows would pair unrelated entries. Reading each flight alone needs the
  flight headings above as evidence of two tables, which the headings' own alignment gives (#124).
- **9/11 pages 447–448** (abbreviations) and **Our Flag page 4** (roster) have no numeric column.
  The prototype shows the cost of reading two aligned text columns as a table without other
  evidence: FAA's glossary page columns, 9/11's staff roster and Wallace's worked examples would
  become tables too. Our Flag's entries are also 19.6–22 ems wide. A definition-list or roster rule
  needs its own evidence (a hanging title line, the abbreviation's capitals).

## Follow-ups

1. **FAA page 410's `(Miles)` reads `( M i l e s )`**: PDFKit spaces the letter-spaced heading, whose
   show is `(Miles)`. Expected `Distance (Miles)`; then the contract can name the distance column.
2. **9/11 pages 50–51**: two flight timelines side by side (see above).
3. **9/11 pages 447–448 and Our Flag page 4**: definition lists and rosters in two columns (above).
4. **Census page 14** (math fonts keep it on OCR): PDFKit splits the rows but keeps the two-heading
   line `Total File Matches 20% Zone Matches` whole, and extraction measures words only where it
   splits merged rows, so no header divides and the table is not read.
5. **Captions set in the cells' size** stay paragraphs before their tables (`Table 2. …`); the
   table's `<caption>` needs a title rule for same-size titles.
6. **FAA page 416's NDB table** (`Compass Locator | Under 25 | 15`, `H | 50–1999 | *50`) is not read:
   its distance column holds a footnote-marked `*50`, so no column holds a number in every row.
7. **USGS's statistics tables** are preserved as images (#36), and the library survey reads none of
   them; why was not examined, since their output cannot change.
