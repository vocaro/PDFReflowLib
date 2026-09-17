# Column cuts: heading bands and text-measured gutters (#47, #56)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 (26A428) arm64, Xcode 27.0
(27A266a), release CLI. Baseline: repository `6a5d67f`, built from `git archive` into a scratch tree
with the same `corpus/cache` symlink; candidate: `6a5d67f` plus the working tree. The work was
developed on `62877e6` and carried forward to `b339e39` and `6a5d67f` as a patch reapplied after a
fast-forward (no commits). The whole lane was compared against both the `b339e39` and the `6a5d67f`
baselines: the same pages change, and every reviewed page's ordered output is identical between
the two comparisons except FAA 199, 261 and 372, where #67 changes baseline and candidate alike
(sub-heading and bullet paragraphs), not the order this change sets. `identity.json` pins both
CLIs, the sources, the new fixtures and the commands.

## What was wrong

`LayoutReconstructor.ordered()` cuts recursively: the widest vertical whitespace gutter first, then
the widest horizontal band, then #64's bullet columns, then a reading-order sort. Both issues are in
the first two steps; neither concerns tags, notes, furniture or the list branch.

**#47, Wallace answer keys** (`corpus/cache/Beginning_and_Intermediate_Algebra.pdf`,
`856bd81e…`). On `62877e6` page 438 still read `0.1`, answers 1–21, `0.2`, the column-1 fraction
crops, *then* `Answers - Chapter 0`, `Answers - Integers` and columns 2–3 (#64 had only stopped the
columns interleaving). Captured geometry (`algebra-438`): column 1 spans x 85.0–124.3, column 2
233.4–278.6, column 3 381.7–430.9; the title is centred at 213.1–381.8 and `Answers - Integers` at
250.2–344.9. The only vertical gap over all elements is 88.8 pt at x 168.7, between column 1 and the
title, because the title's own extent closes the column-2/3 gutter. That cut fires first and the
title goes to the right-hand half, where a horizontal cut then reads it ahead of columns 2–3 only.
The horizontal whitespace that would have separated the title (27.0 pt below it) is never
consulted, and the labels sit closer still: `0.1` is 11.0 pt above `Answers - Integers`, which is
10.7 pt above the answers, both under the 1.1-body (13.2 pt) band test. Page 471 is the same shape
one level down: the 41.4-pt gutter at x 192.4 runs from the 7.7 answers through 7.8 to 8.1, so `8.1`
and its first answers joined the left column ahead of the 7.8 right column, and
`Answers - Chapter 8` read after the whole 7.8 section's right column.

**#56, FAA columns beside figures** (`corpus/cache/faa-h-8083-25c.pdf`, `247929ca…`). Captured
`faa-165`, `faa-199`, `faa-262` and measured the gutters with and without the preserved regions:

| Page | Text-only gutter | With regions | Region that closes it |
| --- | --- | --- | --- |
| 165 | 11.7 pt at x 315.1 | 6.5 pt | figure 7-6, x 0.0–312.5, heads the left column |
| 199 | 11.6 pt at x 315.0 | 7.3 pt | figure 7-45, x 70.2–311.5, heads the left column |
| 262 | 11.8 pt at x 279.1 | 7.4 pt | the KE/PE formula crop, x 281.0–499.0, in the right column |
| 91 (control) | 11.8 pt | 11.8 pt | none |
| 511 (control) | 11.9 pt | 11.9 pt | none |

The body is 10 pt, so the vertical test needs more than 7.5 pt. The three pages keep exactly the
controls' prose gutter, but a figure rectangle overhangs the text measure by 2–4 pt and swallows
it. No vertical cut is found, the only horizontal band is above the folio, and the page falls to the
reading-order sort: page 199 alternates columns line by line, and on 165 and 262 the figure's midpoint
sits below the right column's first lines, so the right column's opening paragraphs read first. The
figure is not a barrier that removes its column from the cut; it hides the gutter.

## What changed

`Sources/PDFReflowLib/LayoutReconstructor.swift` only (+89/−8). No public API, default or other
source file changed.

1. **`gap(horizontal:measuring:)`** measures whitespace over a subset of elements but returns a cut
   only when *every* element lies wholly on one side. Over the full set this is always true (the
   old behaviour); over a subset it prevents a cut that would drop the elements left out, since
   `ordered()` keeps only elements strictly on one side of a cut.
2. **Text-measured gutter (#56).** After both whitespace cuts over all elements have failed, and
   before #64's bullet columns, a gutter is measured over text lines alone and cut when every
   figure still falls on one side (with the existing narrow-gutter prose test). A figure heading a
   column then joins that column. It is deliberately tried *after* the horizontal band: Our Flag
   page 34's four-flag grid keeps its folio `28` in the gutter, 3.6 pt from the right-hand flags, so
   no gutter separates every element; the text alone leaves 6.3 pt, and 61.7 pt of whitespace
   separates the rows. Trying the text gutter first read the grid column by column (FLORIDA,
   HAWAII, GEORGIA, IDAHO) and failed the page-34/42/43 contracts.
3. **`headingBand` (#47).** When a vertical gutter over all elements is found, the region's
   horizontal whitespace at 0.8 body divides it into bands, read from the top. A band that is a
   single text line — a title, a section number, a table label — is cut off horizontally first
   (at the whitespace above it when anything precedes it, otherwise below it), so it heads every
   column. Two further conditions came from controls:
   - *Columns must still run beside each other beneath the band* (both sides non-empty and their
     vertical extents overlap), or the search ends. FAA glossary page 511 fills its left column
     below the right column's last entry with only the folio `G-35` beyond the gutter; a first
     version that only required something on each side cut there and read the left column's tail
     after `Zulu time.` (failing the page-511 contract).
   - *The band must be one element, a text line.* The CDC comic's two- and three-line speech
     balloons stand clear of one another exactly like labels; a first version that accepted any
     one-sided band peeled balloons ahead of the panel beside them (CDC 26 read the bottom-right
     balloon between the bottom-left panel's two).

   The 0.8-body band measure is safe because rows of the columns are never a single line: page
   471's 7.8 block has aligned 11.2-pt row gaps across both columns, wider than page 438's 10.7-pt
   label gap, and the single-line test, not the measure, refuses them.

## Before and after (`6a5d67f` → candidate)

Release CLIs, library defaults. [page-comparison/](page-comparison/) holds `compare-pages.py` output
per book and `block-order.py` ordered-block diffs for every changed page. **Every image is
byte-identical in all six books, `<pre>` counts are unchanged, and book-wide characters are
identical** in each changed book. Fed and Our Flag runs were paired on equal `structureFallback`
counts (Fed 57 pages, Our Flag 33, in both runs).

| Book | Pages whose blocks or text change | Fixed | Improved | Neutral | Regression |
| --- | --- | --- | --- | --- | --- |
| wallace-algebra-2010 | 24 | 10 | 14 | 0 | 0 |
| faa-phak-8083-25c | 13 (+5 neighbours through joins) | 12 | 1 | 0 | 0 |
| cdc-zombie-pandemic-2011 | 3 | 0 | 1 | 2 | 0 |
| gpo-911-2004 | 0 | | | | |
| gpo-our-flag-2003 | 0 | | | | |
| fed-explained-2021 | 0 | | | | |

Every changed page was read against a `pdftoppm` render (45–90 DPI). *Fixed* means the page now
reads in source order; *improved* means every block that moved moved toward source order and what
remains out of order was already so.

**Wallace.** Fixed: 438 (`Answers - Chapter 0`, `0.1`, `Answers - Integers`, 1–21, 22–42, 43–60,
`0.2`, column-1 fractions, `Answers - Fractions`, column-2 fractions — the issue's expected order),
440, 449 (graph columns 31–36 then 37–42, formerly 37/31/38/32…, through the text-measured gutter),
457, 460, 461, 468, 471 (the 7.7 columns, `7.8`, `Answers - Dimensional Analysis`, 1–15, 16–30,
`Answers - Chapter 8`, `8.1`, then `Answers - Square Roots` — the issue's defect is gone), 483, 484.
Improved: 443, 445, 446, 448, 454, 455, 458, 459, 462, 466, 470, 477, 487, 488 — sections that were
interleaved into their neighbours' columns now read whole; the residuals are listed under
remaining gaps.

**FAA.** Fixed: 123, 136, 156, 165, 199, 227, 262, 276, 277, 344, 396 read the complete left column
(figures, captions, prose) before the right; 372's two side-by-side figure captions, formerly
interleaved line by line, each follow their own image. Improved: 207 (below). Where a paragraph
continues onto the next page, #45's rule places the page's stepped-over figure before it (123 figure
5-40, 199 figure 7-47, 276 figure 11-21), which is its documented placement. With the columns in
order, five continuations #45 refused are now joined, each a mid-sentence continuation read against
the source: 164→165 (`…same angle of incidence` / `throughout its entire length…`), 199→200
(`…free of oil, grease,` / `and dirt. Aircraft with…`), 227→228 (`…so that it can` / `rotate only
in the horizontal plane.`), 261→262 (`Conversely, when the` / `aircraft is operated…`), 276→277
(`…Follow` / `straight across to the third reference line…`). Cross-page paragraphs 124 → 129;
none lost.

**CDC.** Page 13 improved (`(WHINE!)` and `UH? WHA?` of the top-right panel now precede the
bottom-left panel; that panel's two-line third balloon still follows it). Pages 6 and 26 neutral:
only an OCR noise line (`____`, `m m`) moves, to its own position; no dialogue reorders.

## Verification

- `swift test`: 334 tests pass (327 at `6a5d67f` plus seven in
  `Tests/PDFReflowLibTests/ColumnCutTests.swift`).
- `python3 -m unittest discover -s tools -p 'test_*.py'`: 166 tests OK.
- `scripts/check-all.sh --fast`: exit 0 (334 Swift, 166 Python, 8/8 concurrency trials, fixture
  conversions, 13 policy conversions and 22 rejection/cleanup cases).
- Corpus lane, `tools/run_corpus_regressions.py … --case` for faa-phak-8083-25c,
  wallace-algebra-2010, gpo-911-2004, gpo-our-flag-2003, fed-explained-2021 and
  cdc-zombie-pandemic-2011: all pass EPUBCheck, progress, memory and content gates with the new
  contracts (FAA 91 checks, Wallace 89, 9/11 133, Our Flag 67, Fed 110, CDC 11; zero errors). The
  `6a5d67f` baseline passes the old contracts.
- **Contracts** (`corpus/regressions.json`, +48 checks on 5 new page entries): Wallace 438 and 471
  `orderedText` extended to the title, section labels and all columns (+18); FAA 165, 199 and 262
  `orderedText` for left column then right plus `minimumImages` (+27); `continuedParagraphs` for
  164→165, 199→200 and 261→262 (+3). Negative control ([before-contracts.json](before-contracts.json)):
  the `6a5d67f` EPUBs fail exactly the new expectations — FAA 11 errors, Wallace 11 — and nothing else.
- **Swift negative controls.** [before-tests.log.gz](before-tests.log.gz): against the `6a5d67f`
  reconstructor the five reproducer cases fail (438, 471, FAA 165, 199, 262; 11 issues) and the four
  controls pass. [guard-mutations.log.gz](guard-mutations.log.gz): removing each guard from the
  candidate fails exactly its control and nothing else — text gutter before the horizontal cut →
  `rowBandedGridKeepsRowOrderAheadOfTheTextGutter`; overlap guard → `columnTailBesideAFolioStays…`;
  single-line guard → `speechBalloonsAreNotHeadingBands`; straddle check →
  `textMeasuredGutterNeverCutsAFigureSpanningIt`.

- **Cost.** Lane wall-clock times swing with host load, so conversions were repeated three times
  alternating the two CLIs and child CPU seconds compared: 9/11 10.8–11.6 s baseline vs 11.0–12.2 s
  candidate, Wallace 19.4–21.9 s vs 19.9–21.1 s, Our Flag 1.22–1.24 s both (after one cold-cache
  run). Peak RSS is unchanged in every lane case (within 3 MB). No measurable cost.
- The final tree's release CLI is byte-identical to the one the lane ran (`29b3266e…`); the only
  later edits were comments.

Fixtures captured from the checksum-pinned sources with `tools/capture-layout-fixture.swift`:
`faa-165`, `faa-199`, `faa-262` (reproducers), `flag-34` and `cdc-26` (controls). The reproducers
reuse the existing `algebra-438` and `algebra-471`; the page-511 control reuses `faa-511` with its
folio kept.

## Controls that did not change

FAA 91/511 left-before-right (`faaSourceColumnsCompleteBeforeTheNextColumn`, contracts), FAA 121
figures and captions, FAA 50/325 tag-restored order and page 81 caption placement (contracts; every
FAA page outside the list above keeps identical text, paragraphs, list items and images), Our Flag
row order on 27, 34, 42 and 43, the 9/11
page-451 name/description rows (`narrowGutterDoesNotSeparateNamesFromDescriptions`; 9/11 unchanged
page for page), CDC page 5, the Fed tinted boxes (#54) and bullet columns (#64; Fed unchanged page
for page), and the algebra exercise pages 10 and 26 (not in the change set). The synthetic
`narrowGuttersStillKeepSpanningHeadingsAndFiguresInPlace` passes unchanged.

## Remaining gaps

- **Titles over crop-headed columns (#47 residual).** When column 1's answers are preserved crops
  (fractions, radicals) whose rectangles rise into the title's band, no whitespace separates the
  title and it still reads after column 1: 443 `Answers to Solving with Fractions` and
  `Answers - Formulas`, 446 `Answers - Distance, Rate, and Time Problems`, 448 `Answers - Slope`,
  466 `Answers - Reduce Rational Expressions`, 470 `Answers - Proportions` and
  `Answers - Solving Rational Equations`, 487 `Answers - Logarithmic Functions`.
- **Labels set tight under the previous section (#47 residual).** A section number less than 0.8
  body below column 1's last row stays with that column, one column early: 454 `4.2` (5.8 pt) and
  `4.3`, 455 `4.4` and `4.5`, 458 `5.3`, 459 `5.5`; titles within 0.8 body of their answers stay
  after column 1 on 477 (both sections), 488 (`Answers - Inverse Trigonometric Functions`) and 471
  (`Answers - Square Roots`, 1.3 pt above its crop). A lower band measure would rest the
  single-line test on row spacing, so it was not lowered.
- **A heading over a one-column tail.** The columns-continue guard cannot tell a single-column
  closing section from a column's own tail: 455 `Answers - Value Problems` with its one answer, 446
  `Answers - Chapter 2` and `2.1` at the page foot.
- **Aligned paragraph gaps across figure-hidden gutters (#56 residual).** FAA 207's figure hides
  the gutter and both columns break paragraphs at the same height, so the horizontal cut takes the
  page in two bands (left, right, left, right) before the text gutter is tried. Before, the lower
  band interleaved line by line. Trying the text gutter first would break Our Flag's row grids.
- **Stacked blocks sharing gutters.** Wallace 487's section 10.6 sets item 1's sub-answers a–i in
  three columns above answers 2–15 in three aligned columns; one gutter spans both blocks, so they
  read column-major across both (`1)`, a–d, 2–6, e–h, 7–11, i, 12–15).

## Defects to file (not fixed)

1. **FAA sub-headings run into their paragraph on untagged pages.** faa-phak-8083-25c pages 136
   (`Radius of Turn The radius of turn is directly linked…`), 156 (`V-Tail …`,
   `Secondary Flight Controls …`, `Flaps …`), 165 (`Fixed-Pitch Propeller A propeller…`) and 262
   (`Climb Performance If an aircraft…`). Expected: the 11-pt sub-heading as its own block, as pages
   91 (`Pressure Altitude`) and 199 (`Pulse Oximeters`) already have on `6a5d67f` (all six are
   `structureFallback` pages). Before this change the pages were interleaved, so every line was a
   separate paragraph and the merge did not show. Prose-branch paragraph breaks (#60/#61 area).
2. **Wallace graph grids read column-wise.** Page 448's graphs are numbered row-wise (15, 16, 17 /
   18, 19, 20 / 21, 22) and read 15, 18, 21, 16, 19, 22, 17, 20 before and after this change.
   Expected: numeric order.
3. **FAA 227 sentence end inside a formula crop.** `…starting from the` ends the paragraph; `true
   course desired.` is inside the Step 1 formula region. Expected: the sentence reflows.
4. **Doc totals stale at `6a5d67f`.** `doc/regression-testing.md` states 621 checks on 129 pages and
   200 ordered-text checks, and `README.md` 502 checks on 122 pages; `corpus/regressions.json` at
   `6a5d67f` already holds 221 ordered-text, 24 continuation and 77 image-presence checks on 156
   page entries (this change: 263, 27, 80 on 161). Not rewritten here to avoid conflicting totals
   across parallel changes; the Swift and Python test counts are updated.
