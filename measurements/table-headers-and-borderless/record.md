# Table headers, row headers and a borderless table (#121)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, Xcode 27, release CLIs.
The work started on `43b20aa` and was fast-forwarded to `d35285f` (list items, hyphen tier, FAA
coded reports) before any lane ran; `corpus/regressions.json` edits were re-applied by script after
that merge. Every lane figure below compares these binaries, with one capability probe for both:

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline | `git archive d35285f` | `98026febf7231e991cb04fa16fdd4c78fb943547b73e0492ac9abc51a8641968` |
| candidate | this tree on `d35285f` | `3b8dacdf8a3c49b927394fb096be1226fb7d438451eaa2ae5d14d2862f5a39f2` |

No source PDF or EPUB is committed; each lane's outputs were deleted after its comparison and page
review. Fixture `faa-131` is new (captured with `tools/capture-layout-fixture.swift`, which now
applies the borderless split as the pipeline does; recapturing after the gutter guard gave identical
bytes).

## #121.1: Fed page 97's header on two column bands

### Diagnosis

`ShadedTableDetector` takes the first grid row as the header only when it sits on a band of its
own at least 90% of the table's width (`ownBand`). Figure 6.5 draws its header as two 205.6-point
bands (x 101.7–307.3 and 303.3–508.9, y 151.3–168.8) inside a 437-point frame, and its body as two
more column bands beneath. The test failed, so `Credit transfer` / `Debit transfer` were body cells.
The PDF tags both `TH`. The table was still accepted only because the misread header counted as
the second of the two body rows the detector requires.

### Rule

`ownColumnBands(row)`: at least two bands through the row's middle, each narrower than 90% of the
table, side by side (overlap at most one body size), together spanning 90% of its width; every band
holds some of this row's lines and no other row's, and every line of the row lies on one. A body
beneath on column bands never qualifies, because those bands hold many rows. A header found this
way still counts toward the two rows a table needs, so acceptance is unchanged: page 97 (header
plus one body row) stays a table and nothing that was rejected before is accepted by the count.

### Before and after

| Page | Baseline | Candidate |
| --- | --- | --- |
| 97 | `<tbody><tr><td>Credit transfer</td><td>Debit transfer</td></tr><tr><td>Payroll…` | `<thead><tr><th>Credit transfer</th><th>Debit transfer</th></tr></thead><tbody><tr><td>Payroll…` |

`TintDetector`'s ruled-table trial asks for a header row and two body rows, so a frame with a
column-band header and two body rows could now pass it; no page in the six lane books changed that
way (no image changed).

## #121.2: row headers

### Evidence

The tag survey (`../table-captions-and-tags/tag-survey.txt`) marks the first-column cell of every
body row `TH /Scope /Row` in each table the geometry reads with at least two body rows (46, 47, 64,
82, 83, 109, 120–121) and `TD` in page 97's single body row, a list of payment kinds under its
column header. Typography cannot confirm it: the Fed sets labels in FranklinGothic Demi and values
in Book (`pdffonts`, source raster of page 46), but PDFKit reports every run in these tables as
`Helvetica` (the `attributedLines` of all seven Fed table fixtures), and `NativeTextReader` marks
bold only for a font name containing `bold`.

### Rule

`ShadedTableDetector.rowHeaders`: among body rows (not header rows, not section rows of one spanning
cell), those whose first cell has text are labelled. When there are at least two, every label holds
a letter, has a value beside it in its row and differs from every other label, the labelled first
cells become row-header cells (`ReflowBlock.Table.Cell.header`, written `<th scope="row">`). A row
whose first cell is empty (Table A's liabilities-only `U.S. Treasury, General Account`) keeps a data
cell without costing the others theirs. One labelled row, a repeated label, a label without a value
or numeric labels leave every cell a data cell. Header-row cells are unchanged (`<th>` with no
scope).

### Before and after (`review-fed-explained-2021.txt`, `pagediff-fed-explained-2021.txt`)

`tools/review.py` undoes exactly the intended rewrites (`<th scope="row">` back to `<td>`, and on
page 97 the new `<thead>` row back to data cells) and compares the whole page markup with the
baseline: all nine changed pages are otherwise identical.

| Page | Row-header cells | Tagged first-column `TH /Scope /Row` |
| --- | ---: | ---: |
| 46 Table 3.1 | 4 | 4 |
| 47 Table A | 4 (Treasury row's empty asset label stays `td`) | 4 in column 1 (+5 in column 3) |
| 64 Figure 4.6 | 7 | 7 |
| 82 Figure 5.7 | 13 | 13 rows (letter and name, tagged as two cells, are one cell here) |
| 83 Figure 5.7 (continued) | 15 | 15 |
| 97 Figure 6.5 | 0 | 0 (`TD`) |
| 109 Figure 6.11 | 6 | 6 |
| 120–121 Figure 7.2 | 9 + 8 | 17 |

Residuals: Table A's liabilities labels (column 3) and the section rows (`General banking`,
`Banks and banking`, …) are tagged `TH` but stay `td`.

## #121.3: FAA page 131's borderless load-factor table

### Diagnosis

The table is two centred columns in body type (Times-Roman 10) with no rules or tints. PDFKit
returns three rows as one line spanning both columns (`CATEGORY LIMIT LOAD FACTOR`, `Normal1 3.8 to
–1.52`, `Acrobatic 6.0 to –3.00`) but keeps the Utility row's cells apart (`Utility (mild
acrobatics,` at x 47–143, `4.4 to –1.76` at x 189–237, and `including spins)` below). The lines were
in row order; paragraph grouping joined the heading with the Normal row and `including spins)` with
the Acrobatic row. Tags cannot repair it (three lines each shared by two cells) and no rule grid
supplies the column joints that split Fed page 46's header. A table therefore needs the merged rows
split during extraction, where PDFKit's selections can measure the whitespace.

### Rule

Extraction (`NativeTextReader.splitBorderlessTables`, enabled by the pipeline and the capture tool
with the page's painted rectangles): a pair of short lines PDFKit kept apart on one baseline (two to
ten ems apart, each at most fifteen ems wide, nothing between them) gives a column gap. The rows
chained to that pair (baselines at most 1.8 ems apart, among lines overlapping the pair's width
widened by an em, so the neighbouring page column is outside) are read against the gap's middle:
each line is on one side, or is cut inside the gap where the selections show at least two ems of
whitespace and the pieces spell the line. The run must open with a heading in capitals on both
sides, hold at least three rows with text on both sides, leave an em of whitespace common to every
row, and contain no painted rectangle. Only then are its crossing lines split. Before any selection
is measured, the rows chained to the pair must include a capital row.

Layout (`BorderlessTableDetector`): an untagged heading of two or more capital lines on one baseline
(each at most fifteen ems, two to ten ems apart); the baselines beneath at no more than 1.8 ems'
leading, in the same size and at most fifteen ems wide, among the lines overlapping the heading's
width widened by an em; each line in the column whose heading it overlaps most; an em of whitespace
between neighbouring columns. A baseline with text in two columns starts a row and one with text in
a single column continues the row above. At least two body rows, every one filling every column.
No row headers (FAA tags those cells `TD`).

### Before and after (`pagediff-faa-phak-8083-25c.txt`)

| Baseline | Candidate |
| --- | --- |
| `<p>CATEGORY LIMIT LOAD FACTOR Normal<sup>1 </sup>3.8 to –1.52</p>` `<p>Utility (mild acrobatics,</p>` `<p>4.4 to –1.76</p>` `<p>including spins) Acrobatic 6.0 to –3.00</p>` | `<table><thead><tr><th>CATEGORY</th><th>LIMIT LOAD FACTOR</th></tr></thead><tbody><tr><td>Normal<sup>1</sup></td><td>3.8 to –1.52</td></tr><tr><td>Utility (mild acrobatics, including spins)</td><td>4.4 to –1.76</td></tr><tr><td>Acrobatic</td><td>6.0 to –3.00</td></tr></tbody></table>` |

Compared with the source raster (110 DPI `mutool draw`): cells, row order and the footnote marker
match. The introduction before and the footnote after are unchanged paragraphs.

## Contracts

`tools/table_cells.py` gains two optional booleans:

- `rowHeaders`: true requires each matched row's first grid cell to be `<th scope="row">` when it
  holds text (`<td>` when empty) and no other cell of the row to be a header; false requires no
  header cell in the row. A `<th scope="row">` never makes its row a header row.
- `headerCells`: true requires the header rows to be `<th>`; false requires none. Without it a first
  row of `<td>` cells still serves as the header, which is why page 97's old output passed.

`corpus/regressions.json`: Fed 46, 47, 64, 83, 109, 120 `rowHeaders: true`; Fed 97 `headerCells:
true, rowHeaders: false`; FAA 131 (new entry) transcribes the table with `headerCells: true,
rowHeaders: false`. The baseline fails exactly these: 16 row-kind errors on the six Fed pages, the
header-cell error on 97 and `no table element on the page` on FAA 131; the candidate passes every
check (Fed 166, FAA 469 content checks).

Negative controls (`tools/test_table_cells.py`): for `rowHeaders`, data cells, a `th` without scope,
`scope="col"`, a second row header in the row, a value written `th`, the empty label written as a row
header, and `false` against emitted row headers; a leading row of row headers is not a header row;
for `headerCells`, a header row of `td`, one header cell written `td`, and `false` against a real
header; non-boolean values are rejected. Run against the committed checker the two new tests error
and the fourteen others pass (`negative-old-checker.log`).

## Tests

`Tests/PDFReflowLibTests/TableHeadersAndBorderlessTests.swift`, 9 functions (14 cases):

| Test | Reproducer / control |
| --- | --- |
| `fed97HeaderOnColumnBandsIsTheHeaderRow` | Fed 97: header row, one body row, no row headers, `thead` markup, caption kept. |
| `columnBandsThatAreNotTheRowsOwnLeaveItABodyRow` | Fed 97's header bands edited: narrow together, running through the body, one band, overlapping; the table stays with its first row as data. |
| `fedFirstColumnLabelsAreRowHeaders` | Fed 46, 47, 64, 83, 109, 120: labelled body rows' first cells only; not header or section rows; Table A's empty label. |
| `rowHeadersNeedTwoDistinctLabelsWithValues` | Synthetic rows: positive with a section row and an empty label; one labelled row, repeated labels, a label without a value, numeric labels, header rows only. |
| `rowHeaderCellsSerializeWithRowScope` | `th scope="row"`, with `colspan`, escaping, header rows without scope. |
| `faa131LoadFactorTableReadsAsATable` | `faa-131`: one four-row table between the introduction and the footnote; no cell text elsewhere. |
| `faa131MergedRowsAreNotATable` | The rows merged back as PDFKit returns them: no table, the scrambled paragraphs. |
| `borderlessTablesNeedCapitalHeadingsAndAFullGrid` | Synthetic lines: title-case heading, one body row, a missing value, a label across the gap, prose, another size or a tag under the heading, distant headings, distant rows. |
| `borderlessRowsPDFKitMergesAreSplitAtTheColumnGap` | Synthetic PDF set like page 131: PDFKit merges the same three rows; the split; controls title-case heading, a drawn rule, a row too tight for a common gutter, a heading with no rows. |

Negative controls (`tools/mutate.py`, `negative-mutations.txt`), each over the four table suites:

| Mutation | Failing tests |
| --- | --- |
| column-band header disabled | `fed97HeaderOnColumnBandsIsTheHeaderRow`, `columnBandsThatAreNotTheRowsOwnLeaveItABodyRow` |
| `rowHeaders` not applied | `fedFirstColumnLabelsAreRowHeaders` (46 issues) |
| borderless split disabled | `borderlessRowsPDFKitMergesAreSplitAtTheColumnGap` |
| common-gutter guard removed | `borderlessRowsPDFKitMergesAreSplitAtTheColumnGap` (the tight-row control) |
| borderless detector disabled | `faa131LoadFactorTableReadsAsATable` |

## Verification

- `swift build`, `swift build -c release`: clean. `swift test`: 544 pass (535 at `d35285f` + 9).
- `python3 -m unittest discover -s tools -p 'test_*.py'`: 213 pass (211 + 2).
- `scripts/check-all.sh --fast`: exit 0 (544 Swift, 213 Python, 8/8 fresh concurrency processes,
  6 fixture conversions, 13 policy conversions and 22 rejection/cleanup cases, 6 byte-identical
  repeat conversions).
- Corpus lane, one case per call (`tools/case.py`: `run_corpus_regressions.py --epubcheck
  /opt/homebrew/bin/epubcheck --environment-probe <probe> --execution-context host-terminal`, then
  `compare_conversion_runs.py --allow-different-converters`; `tools/review.py` and `tools/pagediff.py`
  for changed pages; outputs deleted). No memory-gate failure; 34–36 GB free throughout. FAA took 45 s
  in both lanes.

  | Case | Baseline | Candidate | compare_conversion_runs |
  | --- | --- | --- | --- |
  | fed-explained-2021 | fails the 17 new header checks | pass | 9 pages (46, 47, 64, 82, 83, 97, 109, 120, 121), markup and tables only, reviewed above; images, navigation and markers equal |
  | faa-phak-8083-25c | fails the new page-131 check | pass | page 131 only (reviewed above); other pages' paragraph ids shift; no image, navigation or report change |
  | usgs-mcs2025-copper | pass | pass | no changes (borderless tables stay preserved images; region checks pass) |
  | wallace-algebra-2010 | pass | pass | no changes |
  | gpo-our-flag-2003 | pass | pass | no changes |
  | dga-2025-2030 | pass | pass | no changes |

## Remaining gaps and defects to file

1. **Row headers beyond the first column.** Table A's liabilities labels (column 3) are tagged
   `TH /Scope /Row` and stay `td`; the rule reads only the first column.
2. **Section rows are `td`.** The Fed tags spanning section rows (`General banking`, `Banks and
   banking`) `TH`; they are one spanning data cell.
3. **Demi and bold weights PDFKit renames are invisible.** Every Fed table run reports `Helvetica`
   though the source uses FranklinGothic Book and Demi; style detection sees no bold, so a bold label
   column (or bold box titles) cannot be evidence. `NativeTextReader` also treats only names
   containing `bold` as bold (`Dm`, `Demi`, `Semibold`, `Heavy` are not).
4. **Borderless tables are read only with capital headings and one PDFKit-split pair.** A borderless
   table whose heading is not in capitals, or whose every row PDFKit merges (no pair to find the
   gap), or with three or more columns merged on one line, still reflows as paragraphs.
5. Out of scope here and still open from #121: Fed 54/86 tables inside figure crops, Fed 77's merged
   header line, figure titles around preserved images, and the book-wide `structureFallback` warning.
