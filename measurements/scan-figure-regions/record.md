# Paper Capture inline images as figure and equation evidence (#37)

Tier: deterministic Apple PDF stack, library defaults, macOS 27 arm64 release CLI. Work began on
`eb0197c` and was merged forward to `bfe0476`. Every lane result below is final: baseline `bfe0476`
(`ef968f2a…`, built from `git archive bfe0476`), candidate `bfe0476` plus this change (`883a88e2…`).
The owner approved the NBS figures and equation crops as reviewed on `ffc45a4`; on `bfe0476` all 35
reviewed crops are byte-identical and the reflowed text is unchanged except page 4's
`ab-sorptions` → `absorptions`, a line-end join from the merged hyphen work.

## Diagnosis

`nbs-jres-geltman-1977` pages 1–6 fell back to page images because `GraphicsReader` registered `EI`
as unsupported. Each page is a page-sized 1-bit scan with an invisible (`3 Tr`) Paper Capture OCR
layer, plus 1, 10, 7, 6, 4 and 4 inline images: `/W 1 /H 1 /IM true /BPC 1` stencil masks with one
`0x00` sample under `w 0 0 h x y cm`, all inside `q 0 0 W H re 0 0 W H re W* n`, an even-odd clip of
two identical rectangles, which is empty. Core Graphics paints nothing there: the dark fraction
inside every box matches Poppler (for example 0.04/0.04, 0.11/0.13; a painted mask would read 1.00;
`tools/cgcheck.py`). No exclusion from crops is needed.

Boxes against 100 DPI renders with PDFKit line rectangles and `isProseRow` (`tools/regions.swift`,
`tools/overlay2.py`):

| Page | Boxes | What they cover |
| ---: | ---: | --- |
| 1 | 1 | equation (4), whole |
| 2 | 10 | Figure 1: three waveform strips and the arrow detail (4); an empty box on the scan border at x 522–535 in the top margin; equations (6), (7), (9) whole; (11) as two boxes (left `d/dt⟨Δε⟩`, right integral) |
| 3 | 7 | Figure 2: plot area and a separate top-axis strip; (12), (13), (14), the first line of (15), (16) |
| 4 | 6 | (19) numerator row, (20), (21), (23) two rows, (24) |
| 5 | 4 | (25), (26); Figure 3 without its top label; a strip along the bottom of Figure 4 |
| 6 | 4 | (27), `α₁ = ħω(R₊₁ − R₋₁)`, a sum rule, a small box in the middle of Figure 5 |

Paper Capture leaves no OCR text under a box, so a box used as a crop would lose everything beside
it, and a box dropped would lose its content from the reflow. Captions are OCR text
(`FIGURE 1.`, `FICURE 3.`), axis and curve labels are short non-prose OCR lines (`--.t - - -`,
`Uo ~ ~ (a . u . )`), and the unboxed parts of a display are garbled OCR lines on the same row.
Equation numbers are separate OCR lines up to 80 points to the right.

Two findings shaped the ink map. At two pixels per point Core Graphics' downsampling nearly
erases a scan's one-pixel rules (Figure 4's right axis: 161 of 280 rows dark at gray < 160; 524 of
560 at four pixels per point; `tools/scale.swift`). A zero-length stroke (`0 0 m 0 0 l S`) on every
NBS page becomes a 4×4-point paint that, once not clustered into the scan, was a 2×1.6-point crop.

## Change

- **`GraphicsReader`**: `EI` pops the stream operand and validates it: positive `W`/`H` (or
  `Width`/`Height`) up to 100,000; `IM true` with `BPC` 1 or absent, or `BPC` 1/2/4/8/16 with a device
  (`G`/`RGB`/`CMYK` and full names, `CalGray`/`CalRGB`) or `Indexed` colour space; for decoded data at
  least `ceil(W·BPC·components/8)·H` bytes, otherwise non-empty data. Resource-named colour spaces,
  a missing operand or any failure keep `unsupported`. The image is the unit square under the CTM,
  clipped to the clip in force like an image XObject (since `0fa3057`), and added to `paints` and
  to the new `Result.inlineImages`; a sampled axis-aligned inline image is a cover like an image
  XObject, a stencil mask is not.
- **`ScanEvidenceRegions`** (new file): the growth rule, below.
- **`PDFReflowLibPipeline.extractPage`**: only on an image-backed page with invisible text and
  inline images, graphics become `TintDetector.compose` of the sub-page paints (not page-sized, not
  inline images, not point-sized) plus the grown regions; a nil result sends the page to its image.
  Every other image-backed page clears graphics as before. A first version kept sub-page graphics on
  every image-backed page, as the issue proposed: DGA dropped from 10 to 6 reflowed pages with eight
  content failures (art behind visible text took the text into crops), so it was scoped.
- **Contract tooling**: `imageRegions` accepts `"excludePageReference": true`, which skips the page's
  `Original page N` image (`check_corpus_content.py`, test in `test_image_regions.py`).
- Docs: README (image-backed paragraph), `doc/architecture.md`, `doc/regression-testing.md`.
  No public API or default changed.

## Growth rule

The page is rendered at four pixels per point into a one-point grid; a cell is ink when two of its
sixteen pixels are darker than 160. A summed-area table gives ink extents inside any rectangle.
Walls are prose rows (`LayoutReconstructor.isProseRow`) and caption blocks (a line opening
`fi[gc](ure|.) N.` or `:`, plus same-size lines directly beneath it). Evidence whose centre lies
outside the prose/caption measure, or over no ink, is dropped (the page-2 border box).

- **Figures.** Evidence lies under the nearest caption below it when it overlaps the caption's
  measure (± 2 body sizes) with no wall between them. Its boxes merge; growth starts from their ink
  and repeatedly takes the ink extent within 1.25 body sizes on the sides and top and all the way
  down to 2 points above the caption, never past a wall beside, above or below it, nor other
  evidence. A figure touching a wall returns nil and the page keeps its image.
- **Display rows.** Other evidence, and the formula crops `graphicsWithLabels` would make from the
  OCR text, grow over their column row: the measure of the prose within six body sizes that overlaps
  the box (both columns for a display spanning the gutter), taking all ink across that measure within
  0.6 body sizes above and below until stable. Growth starts from the ink inside the box clipped to
  that measure, so a formula crop's margin cannot reach the gutter (without this, page 4 lost its
  column cut and read its columns line by line). A display that would touch a wall keeps only its
  box's ink; a formula crop that would is dropped (layout recreates it unchanged).
- Each region gets a 2-point margin on every side that stays clear of walls (antialiased stroke ends
  lighter than the threshold: Figure 1's top curve end), then overlapping regions merge. OCR lines
  inside a region are absorbed by the existing `graphicsWithLabels` expansion, so labels never reflow.

## NBS before/after

`tools/lane.sh`, `lane-summaries/nbs-jres-geltman-1977-*`. Words are reflowed words on the page in
the candidate EPUB; the baseline reflowed none on pages 1–6.

| Page | Baseline | Candidate | Crops (excluding the page reference) | Words |
| ---: | --- | --- | --- | ---: |
| 1 | page image | reflow + unverifiedTextLayer + reference | 3: (1); (2)+(3); (4) | 771 |
| 2 | page image | same | 7: Figure 1; (5), (6), (7), (9), (10), (11) | 453 |
| 3 | page image | same | 7: Figure 2; (12)–(17) | 623 |
| 4 | page image | same | 8: (18), (19), (20), (21), (22), (23) as two stacked rows, (24) | 694 |
| 5 | page image | same | 4: (25), (26), Figure 3, Figure 4 | 678 |
| 6 | page image | same | 6: two sum identities, (27), (28), `α₁`, Figure 5 | 609 |
| 7 | reflow | reflow; page 6's closing paragraph now joins across the break; folio `179` removed as furniture (new `furnitureRemoved`) | 0 | 948 (876) |

Report: 7 of 7 pages reflow (baseline 1), 42 images (baseline 7). `compare_conversion_runs.py`
against `bfe0476` changes pages 1–7 only (page 7 as in the table). Captions follow their figures as
text; no figure label OCR line reflows (checked by `absentText` on pages 2, 3, 5 and 6).

Every crop was reviewed at 180 DPI against Poppler renders. Figures 1–5 are each one image holding
the whole drawing and its labels (Figure 1's top curve end and `v_f`, Figure 2's top axis and rotated
y label, Figure 3's `E₀/ω = 1 a.u.` arrow and x label, Figure 4's axis titles and faint right axis,
Figure 5's `F` and `x`). Every equation crop holds the whole display with its number, including the
two-line (9), (15) and (22) and the spanning (19). Equation (8) has neither evidence nor a formula
crop and stays OCR text.

### References

`corpus/references/nbs-jres-geltman-1977/`: `page-2-figure-1` (120,38,432,194), `page-3-figure-2`
(8,120,256,342), `page-1-equation-4` (296,655,510,688), `page-2-equation-11` (284,608,522,656),
`page-3-equation-15` (260,208,508,274), chosen on source renders. `tools/scores.py`:

| Reference | Candidate crop | Source-page reference image | Wrong crops from the page |
| --- | ---: | ---: | --- |
| Figure 1 | 0.989 | 0.981 | one evidence strip, the evidence span, the left half: no placement (−1) |
| Figure 2 | 0.985 | 0.989 | plot box only, axis strip only: −1 |
| (4) | 0.998 | 0.989 | without its number: −1 |
| (11) | 0.987 | 0.989 | left box only, right box only: −1 |
| (15) | 0.987 | 0.994 | first-line box only: −1 |

The source-page image satisfies every region reference, hence `excludePageReference`. The contract
(`tools/contract.py`) asserts on pages 1–6 `unverifiedTextLayer`, no `pageImageFallback` or
`unsupportedGraphics`, minimum images, text and order phrases, label `absentText`, the five crop
references and the existing page-1 page reference: 52 content checks on 7 pages (was 17 on 3).
The contracts now hold 1564 checks on 358 pages (1529 on 354 at `bfe0476`; `tools/countchecks.py`
runs `assess` on every contract). The baseline fails the NBS contract with 30 errors; the candidate
passes.

## Controls

`tools/lane.sh` (corpus lane, one case per call, then `compare_conversion_runs.py
--allow-different-converters` against `bfe0476`; summaries in `lane-summaries/`, EPUBs deleted) and
`tools/controls.sh` (pinned-identifier conversions compared by EPUB hash and report).

| Control | Lane | Comparison with `bfe0476` |
| --- | --- | --- |
| Blue Book (312 pages, inherited OCR, no inline images) | pass both | 0 changed pages, images or report fields |
| CDC comic (art behind visible text) | pass both | 0 |
| DGA (illustrated, image-backed pages) | pass both | 0 |
| FAA handbook (vector and photo figures) | pass both | 0 |
| Our Flag (figures, tables) | pass both | 0 |
| The Fed Explained (image-backed chapter openers) | pass both | 0 |
| Warren nine-page excerpt (`image-backed-structure/warren-excerpt.swift`) | — | byte-identical EPUB |
| `rotated.pdf`, `scanned.pdf` fixtures | — | byte-identical EPUBs |

An intermediate DGA run on the `0d4f24e` merge showed a page-6 paragraph difference against the older
`eb0197c` baseline; against `bfe0476` it is gone, so it came from the merged commits.

## Tests

`Tests/PDFReflowLibTests/ScanEvidenceRegionTests.swift` (8 tests, 16 cases):

- `anInlineImageIsThePaintedUnitSquareUnderItsTransform`: stencil mask, raw samples containing `EI`,
  ASCIIHex RGB, `Indexed`, inside a form.
- `aMalformedInlineImageKeepsThePageImage` (9 cases): missing/zero width, truncated samples, huge
  dimensions with tiny data, no colour space, resource colour space, invalid depth, mask depth,
  `EI` without an image.
- The reproducer: a synthetic page with a 1-bit scan image (prose rows, a framed figure with a
  curve, a side label, an axis label 20 points below the frame, a caption, a display equation and its
  number), invisible OCR text, and Paper Capture evidence (two strips inside the figure, the left half
  of the equation) inside an empty even-odd clip.
  `paperCaptureEvidenceGrowsToTheWholeFigureAndDisplayRow` checks exactly two regions: the figure
  with both labels, stopping above the caption, and the equation row with its number.
  `aScannedPageWithEvidenceReflowsAroundOneWholeFigure` checks reflow, the warning, three assets,
  the caption as text, and neither labels nor the number as text. At the baseline the page falls back.
- Controls: the same page without evidence keeps only its reference; a truncated inline image on it
  keeps the page image; evidence overlapping a prose row returns nil and the page image;
  an inline image on a born-digital page is an ordinary region.

`swift test` on `bfe0476` plus this change: 617 passed. `scripts/check-all.sh --fast`: exit 0 (617
Swift, 217 Python, repeat conversions byte-identical).

## Remaining gaps and defects to file

- To file (minor follow-up, owner decision): NBS page 1, the formula heuristic merges (2) and (3)
  with the prose line `subject to the initial condition` between them into one crop (existing
  `graphicsWithLabels` behaviour on OCR text). Expected: two crops with that line reflowed between.
- NBS page 4: `where D_nmj is the jth "diagram"…`, the first right-column line, is read before the
  left column's (18) crop (`ordered()`).
- NBS page 4: (23) is two stacked crops (its two evidence rows are more than 0.6 body sizes apart);
  accepted by the owner.
- NBS page 1: stray OCR lines `-----------` and `--` open the page.
- Raster fidelity (not filed as a defect yet): Core Graphics' default downsampling renders a 1-bit
  scan's one-pixel rules very faintly (Figure 4's right axis is legible but light in its 180 DPI crop,
  darker in Poppler).
- Equation (8) has no evidence and no formula crop; it stays garbled OCR text (documented limitation,
  accepted by the owner).
