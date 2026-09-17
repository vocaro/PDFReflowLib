# Ruled tables with merged header cells (#65) and page decoration rules (#66)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, Xcode 27, release CLIs.
The work started on `9116393`, and each new tip was fast-forwarded in: `d333b4d`, `785a974`, `63680df`
and `de0df61`. For overlapping files (`LayoutReconstructor.swift`, `GraphicsReader.swift`,
`HeadingTests.swift`, `doc/architecture.md`) the change was re-applied with `git apply --3way`.
`corpus/regressions.json` edits are regenerated with `tools/addcontract.py`. Every figure below
compares these binaries:

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline | `git archive de0df61` | `d6f7d89b8642777629855a789b96609e9099ef427c86c102f44a47a350fa179c` |
| candidate | this tree on `de0df61` | `7c25b4605d551b34ac2ad1450e7934e1a45a78627559ebd040682f56196416a0` |

Earlier baselines (`d333b4d` `b8c63f59…`, `785a974` `d777f72a…`, `63680df` `8b7e7a8f…`) gave the same
page-level differences in every case. No source PDF or EPUB is committed. Each lane output was
deleted after its comparison and page diff were recorded.

## #65: Table 3.1 stays an image

### Diagnosis

Fed page 46's Table 3.1 has a blue title band and a grey header band (`re f`, outside `/Figure`)
over four body rows. The rows are separated only by 0.5-pt rules, which InDesign draws as one
segment per column. Two things kept it an image:

1. **The frame fails the prose test.** The title band, header band and the box of four stroked
   sides form one cluster. It holds only two prose lines (the title and the first caption line),
   so `TintDetector` never made it a tint. The whole grid (88,76 436×350 pt) stayed a crop.
2. **PDFKit merges the header.** `selectionsByLine()` returns the three header cells as one line,
   `Tool Definition In practice` (94.5–402.6 pt). The body cells start at 94.5, 219.4 and 364.0 pt.
   With the merged line in the header row, `ShadedTableDetector` treats it as a crossing line and
   finds no header.

The tag route was checked first. `StructureTreeReader` does not consume `Table`/`TR`/`TH`/`TD`: a
`Table` element outside a group rejects its subtree, so no cell structure reaches reconstruction
on any page. Building tables from tags would mean new structure-reader and `MarkedTextReader`
semantics. That is a wider change than this issue, and the geometry is sufficient here.

PDFKit's `characterBounds(at:)` offsets do not line up with the selection's string on this OS,
as the existing `NativeTextReader` comment warns: the probe put `T` of `Tool` at x = 380. Rectangle
sub-selections are reliable. `page.selection(for:)` over 94.5–154.5 pt returns exactly `Tool`
(94.5–109.1). A selection that reaches the space's centre returns `Tool ` with bounds stretched to
219.4, because the space glyph spans the gap.

### Change

- **`GraphicsReader.columnJoints`** (new; `ColumnJoint` value in `DocumentModel.swift`). Thin
  horizontal paints at least 24 pt wide are grouped into rule rows (midY within 1.5 pt). Two
  neighbouring segments in a row abut when the next starts within the 6 pt padding overlap (or
  1 pt beyond) of the previous end. Their meeting x is a joint if it recurs within 3 pt in at
  least three rule rows. The joint spans those rows. Fed 46 yields x = 215.4 and 360.0 over seven rows.
- **`NativeTextReader.lines(on:limit:includeStyle:columnJoints:)`** (default `[]`; pipeline and
  capture tool pass the page's joints on native pages only). A line splits at a joint when all of these hold:
  - its middle lies within the joint's rows and it reaches more than an em past the joint on both sides;
  - the joint falls in whitespace, so the left and right selections rejoin to the line's text with one space;
  - the glyphs on either side, measured by shrinking each selection until its visible text changes,
    stand at least one em apart, with the joint between them;
  - all pieces together spell the line exactly.

  Pieces are built by `textLine(semantic:bounds:attributed:)` from their own attributed selections,
  so styles survive. The split runs inside the extraction lock, before tag association.
- **`TintDetector.compose`**. A frame cluster that fails the prose test becomes a tinted block
  (`ruled: true`) only when all of these hold:
  - no solid ink intersects it;
  - it has at least two horizontal rules;
  - `ShadedTableDetector.tables` reads a trial page (its text-holding rectangles as tints, its thin
    ink as separators) as a table whose first row is a header on its own band, with at least two
    body rows, inside the frame;
  - every other line in the frame lies above the table (the title band).

  In a ruled block the unshaded-grid rule that restores the strokes as a crop does not apply, and
  its rules become separators. Every other cluster composes exactly as before.

### Before and after

| Page | Baseline | Candidate |
| --- | --- | --- |
| Fed 46, Table 3.1 | 1090×875 crop + 1246×10 rule crop; 209 words | title band paragraph, then `<table>`: header `Tool` / `Definition` / `In practice`, four body rows; 472 words |
| Fed 47, Box 3.5 Table A | reflowed as prose, with `securities holdings` after `1,915` | `<table>` with header cells `Assets (billions of dollars)` and `Liabilities (billions of dollars)`, each `colspan="2"`; 5 body rows including the empty left cells beside `U.S. Treasury, General Account 1,587`; note after the table |

Both were reviewed against 70–100 DPI `mutool draw` renders and `pdftotext -layout`. Every cell
matches word for word.

Split census (`tools/census.swift`: every line crossing a joint, split or kept whole):

| Book | Pages with joints | Lines crossing a joint | Split |
| --- | ---: | ---: | ---: |
| Fed | 10 | 48 | 24 |
| FAA | 3 (307, 437, 439) | 0 | 0 |
| Our Flag, DGA, USGS | 0 | 0 | 0 |

Fed splits by page:

- **46:** the header.
- **47:** Table A's five rows, e.g. `Treasury securities held outright 4,197 Deposits of depository
  institutions 2,938` → four cells.
- **77:** `Depository institutions` | `Bank holding companies (BHCs)`, inside the ratings-grid
  figure, which stays an image with byte-identical output.
- **82, 83 and 109:** regulation letters from their names (`Y` | `Bank Holding Companies…`).
  #54's column-pair merge still joins them into the `Regulation (by letter and name)` cell, and the
  output on these pages is unchanged.

Every title, caption, note, section row and prose line that crosses a joint stayed whole (the
`whole:` entries in [census-fed-explained-2021.txt](census-fed-explained-2021.txt)). No ruled table
in FAA or Fed other than pages 46 and 47 changes output.

## #66: the running-header rule becomes an image on every page

### Diagnosis

The Fed's running head sits above a 0.5-pt rule at y ≈ 744 (x 56.8–555.2 on even pages, 58–554 on
odd ones). The rule touches no line box and no other paint. `graphicsWithLabels` returned a rule
with no owner line unchanged ("an isolated rule stays a graphic", #36), so every page emitted a
1246×10 or 1240×10 px crop. By default the running head is removed as furniture, and then no text
is anywhere near the rule. With headers kept, the 8-pt head sits 2.5 pt above it.

Our Flag page 27's two graphics are 310-pt rules 1.6 pt beneath the 22-pt titles `Care of Your Flag`
and `Sizes of Flags`. They are isolated in the same sense.

### Change (`LayoutReconstructor.isDecorationRule`, applied only to a thin rule with no owner line)

The rule produces no crop when all of these hold:

- it touches no other graphic and no other crop seed (formula, dot-leader table, fraction,
  underlined-column table, algorithm float) within 4 pt;
- it intersects no line;
- it spans at least half of the page's text extent;
- either no line lies within one body size above or below it, or the lines that do are one row
  of text no larger than 1.2× body, all on the page-edge side of the rule and within the outer 12%
  of the page height, with every other line on the far side (a running head).

A rule beneath a heading-sized row, beside other text, short, touching ink, or mid-page with text
around it keeps its crop. The 1.2 factor comes from Fed page 13, whose 7-pt figure labels set the
body size under its 8-pt head.

### Before and after

| Book | Images | Thin (≤ 16 px tall) images | Pages changed |
| --- | --- | --- | --- |
| Fed (135 pages) | 263 → 147 (−115 rules, −1 Table 3.1 crop) | 115 → 0 | 115: 113 lose only the rule; 46 and 47 as above |
| Our Flag (56) | 147 → 123 | 54 → 30 | 24 (11, 12, 14, 18, 19, 22–25, 33–45, 48, 54), each losing only a 775×10 or 776×10 rule |
| USGS copper (2) | 3 → 3 | 0 → 0 | none; the three table crops keep their underline evidence |
| DGA (10) | 28 → 28 | 1 → 1 | none |
| FAA (522) | 595 → 595 | 1 → 1 | none |

On every changed page, text, tables and page markers are otherwise identical and navigation is
unchanged ([pagediff-*.txt](.), [lane-summaries/compare-*.json](lane-summaries/)).

**Our Flag review.** Renders of pages 11, 12, 22, 33, 36, 48 and 54 show a pink rule across the top
margin of a continuation page, with no text near it; these rules are dropped. Renders of pages 13,
20, 46, 50 and 27 show the rule directly beneath a chapter or section title (`Early American Flags`,
`Flag Illustrations`, `Flag Day`, `The Flag House`, `Care of Your Flag`); those 30 rules keep their
crops. Page 27 is unchanged: three images, two title rules and the flag-size table. Its contract
(`minimumImages: 3`, reviewed) stands, and `rulesThatTextOrInkSitsAgainstStayGraphics` pins it.

## Tests

`Tests/PDFReflowLibTests/RuledTablesAndHeaderRulesTests.swift`, 8 functions:

| Test | Reproducer / control |
| --- | --- |
| `mergedHeaderCellsAreSplitAtTheRuleGridsColumnJoints` | Synthetic PDF: per-column segments in four rule rows, header cells at the Fed's x. Without joints PDFKit returns `Tool Definition In practice` (reproducer). With joints: three bold lines at 94.5/219.5/364, each under 60 pt wide. |
| `proseAndWordGapsAcrossAJointStayWhole` | Controls: a title crossing both joints stays whole; a cell ending within an em of the next column stays merged. |
| `columnJointsNeedAbuttingSegmentsInThreeRuleRows` | Fed 46 paints give 215.4 and 360. Controls: two rows, gapped segments, full-width rules and thick bars give none. |
| `fedTable31ReadsAsAThreeColumnTableWithItsHeader` | Fed 46 with the header re-merged keeps the crop and no table (reproducer). As captured: no crop, a 3-column table with its header and four rows, title before the table. |
| `splitRegulationLettersStillJoinTheirNamesInOneCell` | Fed 83 recaptured: `Y` and its name are separate lines and still one cell. |
| `ruledGridsWithoutAReadableHeaderOrWithInkKeepTheirImage` | Controls: no header band, a chart inside the frame, a line crossing the grid; each keeps the crop. |
| `runningHeaderRuleIsDecorationOnEveryFedFixture` | All 23 Fed fixtures with the rule; synthetic pages with the head removed and kept. |
| `rulesThatTextOrInkSitsAgainstStayGraphics` | Controls: Our Flag 27's title rules; a 22-pt heading above the rule; a touching graphic; a short rule; a mid-page rule with text around it; text beyond the running head; a body-sized row away from the margin. |

`HeadingTests.fedTableTypographyDoesNotPromoteSurroundingProse` asserted at least two images on Fed
46 (the table crop and the rule). It now asserts a table block and no image; its heading
expectations are unchanged. The `fed-46` and `fed-83` fixtures were recaptured with the updated
`tools/capture-layout-fixture.swift` (joints passed to extraction). Against the committed fixtures,
the recapture differs only in the split lines, and it is identical under `de0df61`'s clipped
paints. `fed-77` and `fed-109` were not recaptured: a recapture also changes their tag structures and paints
(extraction changes since they were captured), which would confound this change.

**Negative control** ([negative-old-detectors.log](negative-old-detectors.log)). Run with
`TintDetector.swift` and `LayoutReconstructor.swift` from `d333b4d`, keeping the joint API so the
tests compile:
- **Fail:** Table 3.1 (no table, crop kept), the running-header test (all 23 fixtures and both
  synthetic pages), the running-head control and the updated heading test.
- **Pass:** the split and joint tests (independent of the detectors), the ink/no-band controls and
  Our Flag's controls.

**Checker.** `tools/check_corpus_content.py` gains `maximumImages`: a non-negative integer that fails
a page with more images (source-page references included). `tools/test_corpus_content.py` covers
pass, fail and invalid values (`-1`, `True`, `1.0`, `'0'`).

## Contracts (`tools/addcontract.py`)

- **Fed 46:** `minimumImages: 2` is dropped (only the table crop and the rule strip satisfied it).
  Added a `tableCells` transcription of Table 3.1 (three columns, four rows) and `maximumImages: 1`
  (the page's link-annotation reference image).
- **Fed 47** (new entry): `tableCells` on Table A's label columns, four ordered row phrases carrying
  the amounts, and `maximumImages: 1`. Table A's header cells span a label and an amount column each,
  and `table_cells` maps one grid column per distinct header path, so its amounts are checked as
  ordered text.
- **Fed 32, 64:** `maximumImages: 1`. **Fed 120:** `maximumImages: 0`.
- **Our Flag 12, 54:** `maximumImages: 0`.

The baseline lane fails exactly these expectations: Fed 8 (32, 46 ×2, 64, 120, 47 ×3) and Our
Flag 2. The candidate passes every check.

## Verification

- `swift build`, `swift build -c release`: clean. `swift test`: 508 pass (500 at `de0df61` + 8).
- `scripts/check-all.sh --fast`: exit 0 (508 Swift, 205 Python, 8/8 fresh concurrency processes,
  6 fixture conversions, policy conversions). An early run failed because the concurrency probe
  compiles `NativeTextReader.swift` without `GraphicsReader.swift`, so `ColumnJoint` moved to
  `DocumentModel.swift`.
- Corpus lane, one case per call (`tools/case.sh`, which runs `tools/lane.sh` for base and cand,
  `tools/compare.sh`, `tools/pagediff.py`, then deletes the outputs). Each runs
  `tools/run_corpus_regressions.py --epubcheck /opt/homebrew/bin/epubcheck --environment-probe
  <probe> --execution-context host-terminal`, then `tools/compare_conversion_runs.py
  --allow-different-converters`. No memory-gate failure occurred; free space stayed at 36–38 GB.

  | Case | Baseline | Candidate | compare_conversion_runs |
  | --- | --- | --- | --- |
  | fed-explained-2021 | fails 8 new expectations | pass | 115 pages (images/markup/warnings); navigation unchanged; markers equal; no OCR change |
  | gpo-our-flag-2003 | fails 2 new expectations | pass | 24 pages (one rule image each); navigation unchanged |
  | usgs-mcs2025-copper | pass | pass | no changes |
  | dga-2025-2030 | pass | pass | no changes |
  | faa-phak-8083-25c | pass | pass | no changes |

## Remaining gaps and defects to file

1. **Table titles read as one paragraph.** Fed pages 46 and 47 read `Table 3.1 Traditional tools
   in an ample-reserves regime In recent years, …` and `Table A. Simplified view … The Federal
   Reserve publishes data weekly …`. The title and the description line become one `<p>` before the
   table. Expected: a title (heading or caption) and its description, ideally the table's
   `<caption>`. The #54 tables on 64/83/120 do the same.
2. **Tagged table structure is never consumed.** `StructureTreeReader` rejects `Table`/`TR`/`TH`/
   `TD` subtrees on every tagged page (Fed, FAA, DGA, Our Flag). Cell structure from tags would read
   ruled tables with no shaded header band, and tables PDFKit merges without a rule grid.
3. **Ruled tables without a shaded header band stay images.** A header row must sit on its own band.
   None was found in the five books (FAA's three joint pages have no crossing lines), but a purely
   ruled table elsewhere would not reflow.
4. **`tableCells` cannot express spanning headers over label and amount columns.** Column labels
   must be distinct header paths, so Table A's amounts need ordered text instead of cell checks.
5. **Our Flag title rules remain 30 thin images.** They sit directly beneath chapter and section
   titles and are as decorative as the dropped rules. The contract (page 27) and this change keep
   them; whether a rule beneath a heading is decoration needs its own decision.
6. **Fixture drift.** `fed-77` and `fed-109` no longer match current extraction: tag structures on
   their prose lines and some paint rectangles differ from a fresh capture. That predates this change.
