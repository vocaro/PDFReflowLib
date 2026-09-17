# Table leftovers after #121 (#124)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, Xcode 27, release CLIs.
Work started on `a295f33` and was fast-forwarded to `0fa3057` (#125 font weight) before any lane
whose figures are recorded here ran; both binaries below are built from that tree, with one
capability probe for both:

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline | `git archive 0fa3057` | `8b41572c34b05a255fa953f22788abb06ab341f6ac0822ae649d2329d93a1e26` |
| candidate | this tree on `0fa3057` | `cf58e4e569bada3b416232bab606acda9ee9dba56d6b31d43fc85be94fd9ce1b` |
| probe | `tools/probe-raster-environment.swift` | `c53464fd9f526ea3284bcad1ce629c3b4f5c7eeaf241067b6baeff6928c8d0c8` |

No source PDF or EPUB is committed; each lane's outputs were deleted after its comparison and page
review. No fixture was added or recaptured.

## #124.1: section rows are header cells

### Evidence

`ShadedTableDetector` reads a single first-column line that crosses the columns, or sits on a
full-width band of its own, as a section row: one cell spanning the table. The Fed tags every such
row `TH` spanning the table (`../table-captions-and-tags/tag-survey.txt`): page 82 `Banks and
banking`; page 83 `Holding companies and nonbank financial companies`, `Federal Reserve Credit`,
`Monetary policy and reserve requirements`, `Securities credit transactions`; page 120 `General
banking`, `Depository accounts`, `Credit/general lending`; page 121 `Mortgage lending`, `Other
financial topics`. These ten are exactly the section rows the detector reads in the book; no
section row is tagged `TD`. They were written `<td colspan="2">` inside the table's one `<tbody>`.

### Rule

A section row's spanning cell is a header cell (`ReflowBlock.Table.Cell.header`). The EPUB writer
treats a body row whose only cell is a header spanning every column as a section: it opens a new
`<tbody>` (rows before the first section keep a body of their own) and is written
`<th colspan="N" scope="rowgroup">`, so its scope is exactly the rows beneath it up to the next
section. A spanning data cell, a row header spanning part of the table and a spanning header row
are unchanged. The checker reads `scope="rowgroup"` as its own cell kind, which never makes a row a
header row, so page 120 (which opens with `General banking` and has no `<th>` header row) still
reads its first row as the header as before.

## #124.2: row headers beyond the first column

### Evidence

Table A (page 47) is two label/amount lists side by side under `Assets (billions of dollars)` and
`Liabilities (billions of dollars)`, each header cell spanning two columns. The Fed tags the asset
labels (column 1, 4 cells) and the liability labels (column 3, 5 cells) `TH /Scope /Row`. The #121
rule reads labels only in the first column.

### Rule

`ShadedTableDetector.rowHeaders`: when the header row is two or more cells that each span at least
two columns and together span the body's columns, each spanned group of columns is judged alone by
the #121 rule (at least two labelled rows, every label holding a letter, distinct within the group,
with a value in its own group), its first column the labels. Otherwise the first-column rule is
unchanged. On page 47 both groups qualify: 4 asset and 5 liability row headers, the Treasury row's
empty asset label a data cell. No other corpus table has such a header (page 82/83/109's
`Regulation (by letter and name)` spans the letter and name columns PDFKit merges, so it reads as
one column).

## Before and after (`review-fed-explained-2021.txt`, `pagediff-fed-explained-2021.txt`)

`tools/review.py` undoes exactly the intended rewrites (a rowgroup header back to a spanning `td`,
the section bodies merged back into one, a row header after a row's first cell back to `td`) and
compares the whole page markup with the baseline: every table page of the book is otherwise
identical.

| Page | Rowgroup headers (tagged spanning `TH`) | Row headers, base → candidate (tagged `TH /Scope /Row`) | `tbody` |
| --- | ---: | ---: | ---: |
| 46 | 0 (0) | 4 → 4 (4) | 1 |
| 47 | 0 (0) | 4 → 9 (9) | 1 |
| 64 | 0 (0) | 7 → 7 (7) | 1 |
| 82 | 1 (1) | 13 → 13 (13) | 1 |
| 83 | 4 (4) | 15 → 15 (15) | 1 → 4 |
| 97 | 0 (0) | 0 → 0 (0) | 1 |
| 109 | 0 (0) | 6 → 6 (6) | 1 |
| 120 | 3 (3) | 9 → 9 (9) | 1 → 3 |
| 121 | 2 (2) | 8 → 8 (8) | 1 → 3 |

Page 121 continues page 120's `Credit/general lending` group: its first three rows form a body
without a rowgroup header, as their section heading is on the previous page.

## #124.3: borderless tables PDFKit merges completely

### Survey (`borderless-survey.txt`, `tools/borderless-survey.swift`)

Every English corpus source was read whole: each baseline's glyphs (one-character PDFKit
selections) split at gaps of at least two ems, and runs of at least three such rows sharing a
gutter were listed, with the rows PDFKit returned as one line counted. Runs with a merged row:

| Source | Runs with a merged row | What they are |
| --- | ---: | --- |
| faa-phak-8083-25c | 9 | 131 (the #121 table, already read); **410 VOR/VORTAC classes, every row merged, three columns**; 207/208 altimeter subtractions (worked arithmetic, partly preserved images); 416 two page columns; 458/459 flight-planning figures (preserved images) |
| gpo-911-2004 | 14 | 9 list of figures; 14 staff roster; **50/51 flight timelines (four columns, two flights side by side)**; **447/448 abbreviations (two-column list, most rows merged, no heading row)**; 449–454 names (read as name and description paragraphs) |
| fed-explained-2021 | 8 | 5/6 contents; 46, 47, 109 tables already read; 77 and 103 inside preserved figures |
| gpo-our-flag-2003 | 2 | 4 committee roster (two columns merged); 19 flag-display illustration labels |
| usgs-mcs2025-copper | 3 | tables preserved as images (#36) |
| census-rrs2002-01 | 5 | tables in the unmapped font encoding (damaged text) |
| nbs-jres-geltman-1977, arxiv-replay-clocks-2023 | 1, 4 | equations beside prose, algorithm listings |
| wallace-algebra-2010 | 103 | worked-example steps beside their comments, exercise grids |
| cia-blue-book-14-1955 | 938 | scanned typescript tables (#31) |
| dga, cdc, scotus | 0 | |

No English source has a borderless table with capital headings that is missed because PDFKit
merged every row or because it has three columns: FAA 131 is the only such table and #121 reads it.
The tables that do come out as paragraphs lack the #121 heading evidence entirely:

- FAA page 410 (baseline: `<p><em>Class Altitudes ( M i l e s )</em> T 12,000' and below 25 L Below
  18,000' 40 …</p>`): title-case italic headings, the third heading on two letter-spaced lines
  (`Distance` above `(Miles)`), right-aligned numbers, and a wrapped altitude cell whose value `100`
  PDFKit joins to the cell's second line across a gap of only about one em.
- 9/11 pages 50/51: two flights' timelines side by side, times and events in four columns.
- 9/11 pages 447–448: an abbreviation list with no heading row.

Each needs its own evidence (italic headings and right-aligned columns, two tables side by side,
definition lists without headings), and their merged rows must be measured glyph by glyph on every
page that might hold one (FAA 410 has no pair PDFKit kept apart to locate its gutters). A rule fitted
to one page each was not added; they are listed as follow-ups below. 9/11 is also another agent's lane (kerned spaces).

## #124.4: Fed 54/77/86 and the book-wide `structureFallback` warning

**Fed 54, 77, 86 stay images.** Rendered at 80 DPI: page 54 (Figure 4.2) is a diagram of four
coloured boxes, each a heading over a description, tagged as a two-row table; page 77 (Figure 5.6)
has bulleted lists with nested dash lists in its cells, initial letters coloured to spell CAMELS,
two footnotes, and a header PDFKit returns as one line across four cells (`Rating system CAMELS
RFI/C(D) LFI`, tagged as four cells sharing that line); page 86 (Figure 5.8) has two header rows on
differently tinted bands over cells holding bulleted lists with bold run-in labels. The table model's
cells hold inline text only, so lists in cells would lose their structure, and the ruled/shaded
readers have no column joints for page 77's merged header. Reading them as tables is not a clean
improvement; they remain preserved images, and the figure titles around them are unchanged.

**The book-wide warning stays.** `tools/role-survey.swift` counts every structure element's role
(after RoleMap) by whether `StructureTreeReader` accepts it where it stands (`role-survey.txt`;
rejected counts include the descendants of a rejected element):

| Source | Rejected roles |
| --- | --- |
| faa-phak-8083-25c | Link 40968, unmapped `t` 3576, OBJR 1858, Figure 550, LBody/LI 14 each, P 8, TD 6, Sect 6, TR 4, L 3, TH 2, Annot, Span, Table, TBody, THead 1 each |
| fed-explained-2021 | OBJR 257, Link 211, P 177, TH 147, LBody/LI 146 each, Lbl 127, Reference 118, TR 94, TD 93, TOCI 56, Note 53, Caption 50, L 44, Figure 41, Quote 39, TOC 15, Table 11 |
| gpo-our-flag-2003 | Span 196, Figure 103, LI 15 |
| dga-2025-2030 | Figure 15 |
| scotus-loper-bright-2024 | Span 23, LI 13, LBody 12, Lbl 12, L 6 |
| cia-blue-book-14-1955 | Figure 312 |

Every tagged source that raises the warning also has unconsumed roles other than tables (figures,
lists, links, notes, references, object references), so excluding table roles would not remove the
warning from any book, and its message ("invalid or outside supported paragraph/heading roles;
spatial reconstruction remains in use for that content") is accurate for each. It is also one of
many `structureFallback` warnings in the reports (Fed 58, FAA 685 in the `a295f33` reports; the others are per-page tag
association fallbacks). A narrower warning would need per-role reporting that names what is lost
(lists, figures' alternate text, notes); no change was made.

## Contracts

`tools/table_cells.py` gains two optional keys:

- `rowHeaderColumns` (with `rowHeaders` true): the 1-based expected columns whose cells name their
  rows instead of the first grid cell; each holding text must be `<th scope="row">`, every other
  cell of the row `<td>`. It needs `rowHeaders` true and distinct in-range indexes.
- `groupHeaders` (boolean): the group row nearest before each matched row (named by `group`) must
  be `<th scope="rowgroup">` cells opening their own `<tbody>` (true) or data cells (false). Grids
  now record `groupStarts`, the rows that open a `thead`, `tbody` or `tfoot`.

`corpus/regressions.json`: Fed 47 `rowHeaderColumns: [1, 3]`; Fed 83 `groupHeaders: true`; Fed 120
gains the `Electronic Fund Transfer Act/Regulation E*` (group `Depository accounts`) and `Truth in
Lending Act/Regulation Z*` (group `Credit/general lending`) rows, checked against the source text,
and `groupHeaders: true`; Fed 82 is a new entry (caption, header, rows F and K under `Banks and
banking`, `rowHeaders`, `headerCells`, `groupHeaders`). The baseline fails exactly the new checks:
5 row-kind errors on page 47, 3 group-row errors on 83, 2 on 120 and 2 on 82; the candidate passes
(Fed 167 content checks). Counts: 1529 checks on 354 pages, 9 table-cell checks.

Negative controls (`tools/test_table_cells.py`, 2 new tests): for `rowHeaderColumns`, the #121
output (first column only), one liabilities label a data cell, an amount a row header, a label
without scope, the first-column expectation against both columns, and invalid indexes or a missing
or false `rowHeaders`; for `groupHeaders`, the #121 output (spanning data cells in one body),
spanning data cells in separate bodies, a header without scope, `scope="row"`, all sections in one
body, `false` against rowgroup headers, a leading rowgroup row that is not a header row, and invalid
values. Run against the committed checker the two new tests error and the sixteen others pass
(`negative-old-checker.log`).

## Tests

`Tests/PDFReflowLibTests/TableLeftoversTests.swift`, 4 functions (5 cases):

| Test | Reproducer / control |
| --- | --- |
| `fedSectionRowsNameTheirRowGroups` | `fed-83` (4 sections), `fed-120` (3): spanning header cells, other rows' kinds unchanged, one `tbody` and rowgroup header per section, no spanning `td`. |
| `sectionRowsOpenTheirOwnBodyAndOtherSpanningCellsDoNot` | Synthetic serialization: rows before the first section, escaping; controls a spanning data cell, a partial-width row header, a spanning header row. |
| `fed47LiabilityLabelsNameTheirRowsToo` | `fed-47`: header cells in columns 1 and 3 of every body row, the Treasury row's empty asset label a data cell. |
| `labelColumnsFollowHeaderCellsThatEachSpanALabelAndItsValues` | Synthetic rows: both lists; repeated labels or a value only on the other side cost one list its headers; controls a single-column header cell, one spanning header cell, spans short of the body. |

`TableHeadersAndBorderlessTests.fedFirstColumnLabelsAreRowHeaders` now allows page 47's column-3
headers and section rows' header cells (checked by the new tests).

Negative controls (`tools/mutate.py`, `negative-mutations.txt`), each over the five table suites:

| Mutation | Failing tests |
| --- | --- |
| section rows data cells | `fedSectionRowsNameTheirRowGroups` (15 issues) |
| label-column groups disabled | `fed47LiabilityLabelsNameTheirRowsToo`, `labelColumnsFollowHeaderCellsThatEachSpanALabelAndItsValues` |
| one `tbody` | `fedSectionRowsNameTheirRowGroups`, `sectionRowsOpenTheirOwnBodyAndOtherSpanningCellsDoNot` |
| section rows `scope="row"` | `fedSectionRowsNameTheirRowGroups`, `sectionRowsOpenTheirOwnBodyAndOtherSpanningCellsDoNot` |

## Verification

- `swift build -c release`: clean. `swift test`: 609 pass.
- `python3 -m unittest discover -s tools -p 'test_*.py'`: 216 pass (includes the 2 new tests).
- `scripts/check-all.sh --fast`: exit 0 (609 Swift, 216 Python, 8/8 fresh concurrency processes,
  fixture, policy and rejection conversions, byte-identical repeat conversions).
- Corpus lanes, one case per call (`tools/case.py`: `run_corpus_regressions.py --epubcheck
  /opt/homebrew/bin/epubcheck --environment-probe <probe> --execution-context host-terminal`, then
  `compare_conversion_runs.py --allow-different-converters`; outputs deleted). 32–34 GB free
  throughout.

  | Case | Baseline | Candidate | compare_conversion_runs |
  | --- | --- | --- | --- |
  | fed-explained-2021 | fails the 12 new checks | pass (10 s) | 5 pages (47, 82, 83, 120, 121), markup and tables only, reviewed above; images, navigation, markers and report equal |
  | faa-phak-8083-25c | pass | pass (48 s) | no changes |
  | gpo-911-2004 | pass | pass | no changes |
  | wallace-algebra-2010 | pass | pass | no changes |
  | gpo-our-flag-2003 | pass | pass | no changes |
  | dga-2025-2030 | pass | pass | no changes |
  | cdc-zombie-pandemic-2011 | pass | pass | no changes |
  | cia-blue-book-14-1955 | pass | pass (41 s) | no changes |
  | usgs-mcs2025-copper | pass | pass | no changes |
  | scotus-loper-bright-2024 | pass | pass | no changes |
  | census-rrs2002-01 | pass | pass | no changes |
  | nbs-jres-geltman-1977 | pass | pass | no changes |
  | arxiv-replay-clocks-2023 | pass | pass | no changes |

## Remaining gaps and defects to file

1. **FAA page 410's VOR/VORTAC table reflows as scrambled paragraphs.** Expected: a table captioned
   `VOR/VORTAC NAVAIDS` / `Normal Usable Altitudes and Radius Distances` with header `Class`,
   `Altitudes`, `Distance (Miles)` and rows T `12,000' and below` 25; L `Below 18,000'` 40; H `Below
   14,500'` 40; H `Within the conterminous 48 states only, between 14,500 and 17,999'` 100; H
   `18,000'—FL 450` 130; H `FL 450—60,000'` 100.
2. **9/11 pages 50/51's flight timelines are interleaved paragraphs** (`7:59 Takeoff`, `8:14
   Takeoff`, `8:14 Last routine radio` …). Expected: each flight's times and events in order (two
   two-column tables, or each flight's timeline whole before the next).
3. **9/11 pages 447–448's abbreviation list runs together** (`CENTCOM Central Command CIA Central
   Intelligence Agency CONR …` in one paragraph; `CAP combat air patrol CAPPS` split from its
   expansion). Expected: one entry per abbreviation with its expansion (a two-column table or
   definition list).
4. **Fed pages 82 and 83's regulation letters are subscripts** (`<sub>F</sub> Limitations on
   Interbank Liabilities`; 13 cells on page 82, 15 on page 83). Expected: the letter as ordinary text
   (`F Limitations on Interbank Liabilities`), as on page 109. The table-cell checks compare text
   only, so they pass either way.
5. **Our Flag page 4's committee roster merges its two columns** (`ROBERT W. NEY, Representative from
   Ohio, SAXBY CHAMBLISS, Senator from Georgia,` then `Chairman Vice Chairman`). Expected: the House
   members' column, then the Senate members' column, each name with its title.
6. Still open from #121: Fed 54/77/86 tables inside preserved figures (lists inside cells need a
   cell model with block content), figure titles around preserved images, and the book-wide
   `structureFallback` warning (needs per-role reporting, see #124.4).
