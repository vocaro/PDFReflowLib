# Column order: full-measure figures, stacked answer blocks, row-numbered grids (#86, #78)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 (26A428) arm64, Xcode 27.0
(27A266a), release CLI. Baseline: repository `d63bbbc`, built in the worktree with
`LayoutReconstructor.swift` restored from `d63bbbc`; candidate: `d63bbbc` plus the working tree. The
work began on `9cf6b85` and was carried to `eb0197c`, `d63bbbc` and `213c944` by merging each tip and
reapplying the uncommitted patch (no commits). The whole six-book lane was compared against the
`9cf6b85`, `eb0197c` and `d63bbbc` baselines; the numbers below are the `d63bbbc` comparison. After
merging `213c944` (#88, URL hyphens) the merged release CLI passed all six lane cases again, with
every contract. [identity.json](identity.json) pins both CLIs, the probe, the sources, the new
fixtures and the commands.

## What was wrong

`LayoutReconstructor.ordered()` cuts recursively: the widest vertical gutter over all elements
(with #47's `headingBand`), then the widest horizontal band, then #56's gutter measured over text,
then #64's bullet columns, then a reading-order sort. Captured geometry (`tools/capture-layout-
fixture.swift`) and a temporary trace of which branch fired at each depth give the cause on each
reported page.

**#86, FAA two-column pages read line by line** (`corpus/cache/faa-h-8083-25c.pdf`, `247929ca…`).

- **Page 340.** No cut fires at depth 0; the page falls straight to the sort. The runway figure's
  crop (x 34–566, bottom edge ≈ 309.9) ends 0.7 pt above the column headings (top 309.2), so there is
  no horizontal band (the test needs more than 1.1 body, 11 pt). Measured over text the 11-pt
  gutter at x 279.5 is there, but the full-width figure straddles it and #56's text gutter refuses
  a cut that would drop it.
- **Page 401.** The same at the foot: the two wind-triangle crops (top edge 436) begin 8 pt under
  the left column's last line (444), and the `Figure 16-20` caption (x 36.6–280.2) also crosses the
  text gutter at x 279.
- **Pages 108 and 19**, found in the lane: the crop comes closer still. Page 108's figure-5-17 crop
  rises to within points of both columns' last lines (`downwash, and wingtip vortices.` at y 391,
  `In order for ground effect…`); page 19's airmail-map crop reaches the two lines beneath it. Any
  whitespace band that isolates the figure also takes those column lines.
- **Pages 439 and 392**, found in the lane: both columns also break a paragraph at the same height.
  Under page 439's drug-table crop (10 pt below the columns) the aligned paragraph space is exactly
  11.0 pt, so the horizontal band fires first and the page reads left, right, left, right.
- **Page 317** (reported during the work): its full-width figure 13-5 sits a few points under both
  columns; item 12 and the METAR example alternated line by line with items 8–11. Same cause.
- **Page 207** (the #56 residual) had a different cause: a figure hides the whole-element gutter
  (7 pt) and the aligned paragraph band cuts first. On `eb0197c` the formula-crop change already
  restores that gutter and page 207 reads left then right without this change.

**#78, Wallace** (`corpus/cache/Beginning_and_Intermediate_Algebra.pdf`, `856bd81e…`).

- **Page 487.** After `headingBand` peels `10.6`, the title and `1)`, the 23-element region takes the
  whole-element gutter at x 208.8, which runs through both blocks. The sub-answers a–i (rows 215.3–
  282.4) and answers 2–15 (top 177.1) stand 38.2 pt apart, while no column's own rows are more
  than 14.8 pt apart (`12)` → `13)`). That band is never consulted before the gutter.
- **Page 448.** The graphs are numbered along the rows (15, 16, 17 / 18, 19, 20 / 21, 22) with no
  whitespace between rows (3.4 pt between rows 1 and 2; graph 20's crop hangs 5 pt below label 21's
  top), so no horizontal cut exists and the column gutters read 15, 18, 21, 16, 19, 22, 17, 20.
  Geometry alone cannot decide: page 449's graphs are numbered down the columns (31–36, 37–42), and
  the exercise sets are numbered along their rows two to a row (`1)` | `2)`) but are read column by
  column by contract (pages 10, 26).

## What changed

`Sources/PDFReflowLib/LayoutReconstructor.swift` only (+213/−5). No public API, default or other
source file changed.

1. **`spanningFigures` (#86)**, tried after the text-measured gutter and before `bulletColumns`. A
   partition, not a cut: the gutter is measured over text lines other than captions (`Figure N`/
   `Table N` lines and the lines wrapped beneath them); the preserved regions straddling it must
   all lie above the columns' first line or below their last (within half a body); every other
   element must fall on one side of a gutter with prose on both sides (two lines ≥ 12 bodies
   each). Figures and the captions whose lines all lie beyond the columns read before or after the
   columns; a caption against a figure of a column's own stays in its column (page 194's
   `Figure 7-38`, page 19's two-line photo caption).
2. **A paragraph-sized band gives way to that partition.** When the widest horizontal band is no
   wider than 1.5 body and `spanningFigures` applies, the figures are set apart first (pages 439,
   392). Our Flag's state grids band their rows with 62 pt and are unaffected.
3. **`stackedBlocks` (#78)**, tried when a whole-element gutter is found and `headingBand` declines:
   the widest horizontal band of at least two bodies, at least twice the widest whitespace inside
   either side of the gutter above or below it, with columns beside each other on both sides of it,
   is cut first. Never for prose columns (any line ≥ 12 bodies), whose paragraphs flow from one
   column's foot to the next column's head.
4. **`rowMajorLabels` / `inNumberOrder` (#78)**: after a whole-element gutter splits a region into
   columns, `N)` labels forming a grid of at least three columns (labels on the first row's column
   edges, at least two rows of two, nothing above the first row) whose numbers run consecutively
   row by row regroup the column-ordered cells by number, each label leading the elements that
   follow it in its column.
5. `gap(horizontal:measuring:in:)` measures a subset region, so the partition can test its columns.

Designs tried and rejected, each on lane evidence:

- A *horizontal cut* at the first band isolating the figure (with up to three caption lines) fixed
  pages 340 and 401 but took column lines into the figure band on pages 19 and 108, which then
  read as a row ahead of or behind both columns; replaced by the partition.
- Without prose sides, the cut also fired on Wallace's worked examples (pages 186 and 429: formula
  crops and triangles beside short notes).
- Letting a paragraph-sized band give way to a *text-measured gutter* fixed page 207 on `9cf6b85`;
  on `eb0197c` page 207 no longer needs it and it fired on no lane page, so it was removed.
- Row-major regrouping for any grid of two or more columns changed 22 Wallace exercise pages (10,
  25, 26, 111, 122, 200, 220, 228, 236, 323, 413, 423, 424–427, 429, 433–436) from their contracted
  column order (page 10 also read `Find each product.` between 29 and 30); limited to three or more
  columns. A bare-label requirement and a "figures reach the columns' full measure" requirement
  were redundant with the other guards and are not kept.

## Before and after (`d63bbbc` → candidate)

`tools/compare_conversion_runs.py --allow-different-converters` per book
([page-comparison/](page-comparison/)), `measurements/column-cuts/block-order.py` ordered-block
diffs for every changed page, and for FAA a reading path per changed page
([reading-paths-faa-phak-8083-25c.txt](page-comparison/reading-paths-faa-phak-8083-25c.txt)): each
block's first line located in a native capture of the page and printed as column and height, before
and after. **Every changed page was read against a `pdftoppm` render (45–70 DPI).** No image bytes
change in any book, and book-wide characters are identical in both changed books (FAA 1,410,505;
Wallace 390,095). Fed and Our Flag runs report equal `structureFallback` counts (56 and 33).

| Book | Changed pages | Fixed | Improved | Neutral | Regression |
| --- | --- | --- | --- | --- | --- |
| faa-phak-8083-25c | 50 | 48 | 2 | 0 | 0 |
| wallace-algebra-2010 | 2 | 2 | 0 | 0 | 0 |
| gpo-911-2004 | 0 | | | | |
| fed-explained-2021 | 0 | | | | |
| cdc-zombie-pandemic-2011 | 0 | | | | |
| gpo-our-flag-2003 | 0 | | | | |

**FAA.** Fixed — the complete left column (with its figures and captions) reads before the right
column, and full-width figures read before or after both: 19, 78, 96, 100, 101, 103, 106, 108, 112,
115, 130, 132, 146, 150, 153, 191, 193, 194, 206, 219, 221, 228, 229, 264, 275, 283, 290, 294, 295,
303, 306, 317, 340, 345, 349, 351, 355, 359, 361, 368, 389, 392, 393, 394, 401, 408, 439, 449. All
but a few read line by line before (page 349 only in its bullet rows; 439 and 392 by paragraphs).
Where a page's last paragraph continues onto the next page, #45 places the page's foot figure
before that paragraph (100, 132, 206, 290, 303, 306, 389), its documented placement. Improved: 265
(the left column and lower right column are in order; the right column's opening paragraph and its
formula crops still read first, as before) and 354 (unchanged order; its paragraph now continues
onto 355). With the columns in order, 15 cross-page continuations are joined, each checked against
the source as a continuation ([joins](page-comparison/joins-faa-phak-8083-25c.txt)): 100→101,
102→103, 111→112, 131→132, 193→194, 227→228, 228→229 (`Acceleration causes an` / `indication
toward north`), 263→264, 274→275, 282→283, 294→295, 305→306, 354→355, 358→359 and 400→401;
174→175 on `eb0197c` is a paragraph set with no space at the column head. Report: three
`uncertainHyphen` notices added (228, 229, 449) where hyphenated lines now join inside their own
paragraph (`Acceleration-` / `North/Deceleration-South`). Navigation: page 355 gains
`Example: Key to Traffic Pattern Operations— Single Runway`, formerly lost in the interleaving.

**Wallace.** Fixed: 487 (`10.6`, the title, `1)`, a–d, e–h, i, then 2–6, 7–11, 12–15) and 448 (15–22 in
number order, each label followed by its own graph). Exercise pages 10 and 26 and every other page
are unchanged.

## Verification

- `swift test`: 441 tests pass on the merged tree (429 at `213c944` plus twelve in
  `Tests/PDFReflowLibTests/ColumnCutTests.swift`; 433 on `d63bbbc`).
- `scripts/check-all.sh --fast`: exit 0 (Swift, 196 Python tests, 8/8 concurrency trials, fixture
  conversions, 13 policy conversions and 22 rejection/cleanup cases).
- Corpus lane, `tools/run_corpus_regressions.py … --case` for faa-phak-8083-25c,
  wallace-algebra-2010, gpo-911-2004, gpo-our-flag-2003, fed-explained-2021 and
  cdc-zombie-pandemic-2011, one case per call: the candidate and the merged CLI pass EPUBCheck,
  progress, memory and content gates with the new contracts (FAA 299 checks, Wallace 128). The
  `d63bbbc` baseline passes the old contracts.
- **Contracts** (`corpus/regressions.json`, +49 checks): FAA `orderedText` on page 340 (extended) and
  new entries 401, 317, 439 and 108 (+25); Wallace 448 (`orderedText` and `minimumImages`) and 487
  (+24). Negative control ([before-contracts.json](before-contracts.json)): the `d63bbbc` EPUBs fail
  exactly the new expectations — FAA 11 errors, Wallace 8 — and nothing else.
- **Swift negative control** ([before-tests.log.gz](before-tests.log.gz)): against the `d63bbbc`
  reconstructor the reproducers fail (FAA 340, 401, 108, 439, 392; FAA 194 and 19, which the baseline
  interleaves; Wallace 448 and 487; the synthetic wide band under a head figure; 11 issues) and every
  control passes.
- **Guard mutations** ([guard-mutations.log](guard-mutations.log)): removing each guard fails exactly
  its control — prose sides → `shortCellsUnderAFigureKeepTheirRows`; figures beyond the columns →
  `figureBetweenColumnBlocksKeepsItsPlace`; paragraph-sized band → `wideBandBeneathAHeadFigureIsCutFirst`;
  caption against its own figure and whole caption groups → `captionOfAColumnFigureStaysInItsColumn`;
  three columns → `columnNumberedGridsAndExerciseSetsKeepColumnOrder` (pages 10, 26, 424); stacked
  prose → `alignedSpaceInProseColumnsIsNotAStackedBlock`; stacked spacing →
  `columnNumberedGridsAndExerciseSetsKeepColumnOrder`; stacked sides →
  `columnTailBelowABandStaysWithItsColumn`. The consecutive-numbering guard has no isolating
  control: for any grid numbered down its columns, number order equals column order, so it only
  withholds regrouping where numbering restarts or skips inside one region.
- Fixtures captured from the checksum-pinned sources with the `d63bbbc` capture tool (tags
  recorded where they validate): `faa-340`, `faa-401`, `faa-108`, `faa-392`, `algebra-448`,
  `algebra-487` (reproducers); `faa-19`, `faa-194`, `algebra-186`, `algebra-429`, `algebra-424`,
  `algebra-449` (controls). The page-439 test reuses the existing `faa-439` fixture; pages 10 and
  26 reuse `algebra-10` and `algebra-26`.

## Controls that did not change

FAA 91/511/165/199/262 column order and 121 figures (contracts; unchanged pages), Our Flag row order
on 27, 34, 42 and 43 (book unchanged page for page), 9/11 page 451 rows (book unchanged), CDC 26
balloons (book unchanged), Fed bullet columns on 58 (book unchanged), Wallace answer keys 438/471 and
exercise pages 10/26 (unchanged pages, contracts and Swift tests).

## Remaining gaps

- **FAA 265**: the right column's opening paragraph (`A common element…`) and its three formula
  crops still read before the left column's figure 11-10 and prose.
- **Wallace 448's answer section** under the graphs still reads out of order around its fraction
  crops (#47 residual, unchanged).
- The consecutive-numbering guard is kept without an isolating control (above).

## Defects to file (not fixed)

1. **FAA prose absent from the EPUB text on crop-adjacent columns.** faa-phak-8083-25c, verified on
   `9cf6b85` (identical characters in every later run of these pages): page 130 right column
   `Load Factors in Aircraft Design`, `The answer to the question “How strong…` (native line at
   x 321, y 706) and the next paragraph; page 191 left column from `electricity as a source of power`
   through `Fuses or circuit breakers…` (x 72, y 419) and the right column after
   `amount of charging current…`; page 351 right column `Runway Lighting` and
   `There are various lights that identify…` (x 321, y 607); page 146's right column opening above
   `controls. The primary flight controls…`; page 19's left column above
   `United States. This legislation…`, inside the airmail-map crop. The native text layer has these
   lines; neither run emits them as text. Expected: reflowed prose (crops/furniture area, not
   ordering).
