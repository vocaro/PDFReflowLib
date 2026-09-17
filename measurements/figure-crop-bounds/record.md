# Figure crops bounded by their clip (#98, #52)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 (26A428) arm64, Xcode 27.0
(27A266a), release CLI. Baseline: repository `63680df` (release SHA-256
`12627d618726db5073ff56ea2af8b56b118c1ad14cba55eb629e25ba6e1f35be`); candidate: `63680df` plus the
working tree (`022e30f9fb7675775ee56c9499bd7ede8536c9c1b54bbebee2574a3f25c49f81`). Raster probe
`851d6d0a…`. The work began on `0d4f24e` and was carried to `ffc45a4`, `9884ed6`, `bc5eb8c`, `36c6265`,
`d333b4d`, `785a974` and `63680df` by fast-forwarding and reapplying the uncommitted patch. The survey,
review sheets and DGA/USGS/NBS runs are from `d333b4d`; FAA, Fed, Wallace and Our Flag were rerun on
`63680df` with the same changed pages and per-page text deltas as every earlier tip. No source PDF or full EPUB is committed.

## Missing-text survey (FAA handbook, 522 pages)

[`tools/survey.swift`](tools/survey.swift) replicates per-page extraction (native lines, validated
tags, `HiddenTextFilter`, `TintDetector.compose`) and `graphicsWithLabels`, and records every native
line with its hidden flag and the crop it intersects. [`tools/analyze.py`](tools/analyze.py) looks
each line (at least six letters/digits after normalization) up in the EPUB text of its page and the
pages either side (`check_corpus_content.read_pages`) and classifies the lines not found. Furniture
removal is not replicated; folios and running heads are shorter than the six-character floor.

| Cause | Baseline lines / words / pages | Candidate lines / words / pages |
| --- | --- | --- |
| Inside a figure crop | 571 / 4,480 / 59 | 150 / 737 / 17 |
| — of which body-size prose on a column measure | 322 / 3,073 / 26 | 1 / 20 / 1 (page 461) |
| Inside a formula or table crop | 56 / 318 / 13 | 56 / 318 / 13 |
| Hidden by design (`HiddenTextFilter`) | 1 / 11 / 1 (a page-159 caption line, not diagnosed) | same |
| Whole-page image fallback (`unsupportedGraphics`, pages 226, 286, 288, 302, 448) | 249 / 2,278 / 5 | same |

The remaining figure-crop lines are figure-internal text (trim-tab labels on 159, the wind triangle
on 401, the Challenger charts and tables on 457–459, the sign legend on 475), three captions still
inside crops (374, printed inside its figure's frame; 25 and 185, not diagnosed), and appendix/chapter-opener titles over title
art (3, 453–456, 461, 473, 477), whose drop-shadow group box also touches the first body line on page
461. Formula/table-crop lines are table-of-contents entries with `=` (pages 6, 14), displayed word
equations and worked examples (208, 251, 254, 262, 265, 266, 298, 398) and PAVE titles.

## What was wrong

Every prose line inside a figure crop was diagnosed from the footprint that claimed it
(a trace build of `GraphicsReader` logging each footprint with the clip in force):

- **Page 19 (#52).** Not a form box: the airmail-route map is an image placed 338 × 400 pt
  (x 256.8–595, y 453.9–853.8) under a 206.6 × 128.9 pt clip at x 300.2. Its placement reached 43 pt
  into the left column; 27 lines (the column from `mass produced to serve as fighters` to `which served
  as the cornerstone`) were inside the crop and the page read interleaved.
- **Page 96 (#98).** The tip-vortex figure's streamlines and wing paths have control-point extents
  from x 258 to 580 under clips starting at x 322.7; `are identical. In both examples…` and `As an
  airfoil moves through air…` were inside the crop.
- **Page 130.** The P-factor arrows' paths reach x 449 under the two panel clips (x 103–194 and
  217–309); `Load Factors in Aircraft Design` and the right column's first two paragraphs.
- **Page 146.** Streamline paths of one panel drawn under the other panel's clip (they never show),
  and a transparency-group copy whose box misses its clip entirely, reach x 328 over the right
  column's opening at x 321; the whole right column above `primary flight controls and secondary`.
- **Page 191.** The master-switch art is a path 700 × 715 pt under a 161 × 202 pt clip; the crop ran
  from the bus-bar paragraph to the page foot across both columns (42 lines).
- **Page 351.** The pulsating-VASI glow path overhangs its 22 × 46 pt frame into the right column;
  its crop merged with the neighbouring figure and took `Runway Lighting` and its paragraph.
- **Page 361** (found by the survey). A filled rectangle wholly outside the vortex figure's clip
  reached 5 pt above the frame into the tall line rectangles of `(A380) and “Heavy”…`, admitting the
  row and its neighbours in both columns.
- The same cause, found by the survey: pages 78, 103, 126, 150, 153, 193, 195, 216, 344, 347, 348,
  349, 367, 368, 393, 394, 396, 412, 443 and 449 (images and paths drawn beyond their frames).

`GraphicsReader` already limited a form's box to its clip (#77) but recorded paths and images at
their whole extent. The tracked clip is a conservative bounding rectangle (the intersection of clip
paths' bounds and form boxes, restored by `Q`), so what lies outside it is never painted.

## What changed

`Sources/PDFReflowLib/GraphicsReader.swift` only (+12/−2); no public API, default or layout rule.

- A stroked or filled path's footprint (still padded by 2 pt) and an image's placed rectangle are
  intersected with the clip in force; a path or image wholly outside its clip is no footprint.
- `36c6265`'s rule (a paint wholly off the crop box is dropped) is kept after it.

No rule in `graphicsWithLabels` changed. With footprints bounded by painted extents, no prose line
on a column measure is admitted except the one on page 461 (a remaining defect below), so no new
admission guard was added.

## Before and after (release CLI, library defaults, baseline → candidate)

`tools/compare_conversion_runs.py --allow-different-converters` (no provenance errors), page digests
([`tools/digest.py`](tools/digest.py); FAA: [faa-page-digest.txt](faa-page-digest.txt)), before/after
sheets of every changed page's images ([`tools/sheet.py`](tools/sheet.py)) and a source render of every
page whose reading changed.

| Book | Contracts | Changed pages | Text | Images |
| --- | --- | --- | --- | --- |
| faa-phak-8083-25c | base fails 30 new checks only; candidate passes 394 | 278 (53 text) | +3,802 words; one caption moves into its figure (374) | 577 → 595 |
| wallace-algebra-2010 | both pass | 32 (3 text) | +4 (exercise labels 1), 8), 10), 12)) | 2026 → 2027 |
| fed-explained-2021 | both pass | 3 (2 text) | +49 (page 135 closing paragraph) | 261 → 263 |
| gpo-our-flag-2003 | both pass | 14 (1 text) | +1 (`LOUISIANA`, page 36) | 147 → 147 |
| dga-2025-2030 | both pass | 5 (images only) | 0 | 28 → 28 |
| usgs-mcs2025-copper | both pass | 0 (strict comparison passes) | 0 | 3 → 3 |
| nbs-jres-geltman-1977 (extra, scan path) | both pass | 0 (strict comparison passes) | 0 | 7 → 7 |

**Ink check.** [`tools/inkcheck.py`](tools/inkcheck.py) renders each FAA page whose crops changed
(72 dpi) and counts non-background pixels inside a baseline crop that neither a candidate crop nor
any text-line rectangle covers: **0 pixels on all 272 pages**. Control: the same check against the
candidate crops shrunk 8 pt per side ([`tools/shrink.py`](tools/shrink.py)) flags 348 pages. The
survey's line diff ([`tools/diff.py`](tools/diff.py)) releases 518 lines (4,521 words) from crops and
captures none; every released line was read: body prose, headings, captions, bullet markers and
folios, no figure-internal label.

**FAA review.** Every one of the 53 text-changed pages was read on before/after sheets and the
reported pages against renders: each figure keeps its labels, legends, inset photographs and frame;
merged crops split into their figures (78, 103, 146, 150, 153, 193, 216, 347, 348, 349, 368, 393, 403).
Reading order fixed besides the reported pages: 381 (both columns interleaved line by line; now in
column order with whole bullet items), 265 (the #86 residual: left column before the right), 18 and
264 (the foot figure now precedes the paragraph continuing onto the next page, #45's placement, and
the paragraph joins across the page). Six pages lose a false `unverifiedTextLayer` warning and their
whole-page reference image (67, 138, 216, 253, 347, 374): an image placed beyond the page edge had
counted as a page-sized graphic, so the page's crops were discarded; they are now ordinary figure
crops. On page 374 the caption `Figure 14-60. An airport diagram with EMAS information.` is printed
inside the figure's frame and now stays in the image (8 words leave the text). 14 pages add a
`structureFallback` notice ("Caption, list or oversized heading tags…"): captions that left crops now
reach the tag check, which rejects caption tags as before. The 225 image-only pages re-cut crops
by the padding beyond their clip (covered by the ink check; sampled on sheets).

**Controls.** Page 121's three `imageRegions` and `imageAppearance` checks pass; Our Flag's flags,
seals and page-16 flag-part labels are whole (crops lose only empty margin, the flags' soft shadows
are kept); DGA's illustrations and sodium box lose a 3-px blank strip; USGS tables unchanged; Wallace
glyph regions on 343/347 pass, all graphs, triangles and answer crops keep their axes, arrowheads
and labels, and pages 100 and 105 now read each exercise label before its own graph (base: `6)` before
`5)`, labels `8)`, `10)`, `12)` inside crops); Fed chart boxes (#54) unchanged, cover (page 3) becomes a
seal crop and a photo crop in reading order without the false image-backed warning.

## Verification

- `swift test`: 500 tests pass (487 at `63680df` plus 13 in
  `Tests/PDFReflowLibTests/FigureCropBoundsTests.swift`).
- Negative control ([log](negative-old-reader.log.gz)): with `d333b4d`'s `GraphicsReader.swift` and
  fixtures recaptured by it, the 12 reproducers fail with 59 issues; the label-bearing control
  (`labelBearingFiguresKeepTheirLabels`, pages 159 and 401) passes on both.
- Mutations ([mutants.log](mutants.log)): unclipped paths fail the stroked-path, two-column and
  outside-fill tests; unclipped images fail the image test; keeping the extent of a footprint wholly
  outside its clip fails the outside-fill test. Fixture tests consume captured footprints, so they
  do not see reader mutations; the synthetic tests do.
- `scripts/check-all.sh --fast`: exit 0 (500 Swift, 204 Python, fixture conversions, 13 policy
  conversions and 22 rejection/cleanup cases, repeat-run identity).
- Corpus lane, `tools/run_corpus_regressions.py --converter <CLI> --epubcheck
  /opt/homebrew/bin/epubcheck --environment-probe .build/raster-environment/probe --execution-context
  host-terminal --case <id>`, one case per invocation, baseline then candidate: all candidate runs
  pass EPUBCheck, resource, memory and content gates.
- Contracts (`corpus/regressions.json`, FAA +42 checks, 352 → 394 on `63680df`): new `orderedText`, `headings`
  and `minimumImages` for pages 19, 130, 146, 351 and 361; `orderedText` on 96; page 191's
  `orderedText` extended and `Hydraulic Systems` heading. Negative control
  ([faa-baseline-contract-errors.json](faa-baseline-contract-errors.json)): the baseline EPUB fails
  exactly 30 of the new expectations and nothing else.
- Fixtures `faa-{19,96,130,146,159,191,351,361,401}-clipped-layout.json`, captured from the
  checksum-pinned source with `tools/capture-layout-fixture.swift` built from the working tree
  ([`tools/capture.sh`](tools/capture.sh)); recaptures on `9884ed6`, `36c6265`, `d333b4d`, `785a974` and `63680df` are
  byte-identical.

The tools in `tools/` were run from a scratch directory; paths inside them are those of the run.

## Remaining gaps

- **Page 461** (`This is a list of common acronyms and abbreviations…`): the title's drop shadow is a
  transparency-group form whose box overlaps the top 2 pt of the first body line's rectangle; the
  paragraph is too short for `isProseRow` to recognize it. The same shadow groups keep the titles of
  pages 3, 453, 461, 473 and 477 inside crops.
- Captions still inside crops: 374 (printed inside the figure's frame), 25 and 185 (not diagnosed).
- Formula-crop text listed in the survey (step instructions on 251, closing sentence on 298) is
  unchanged; the page 6 and 14 contents entries reflow since `785a974`.

## Defects to file

1. **Appendix and chapter-opener titles preserved as images with their shadow.** FAA pages 3, 453,
   461, 473, 477: the title's drop-shadow transparency group seeds a crop over the title text (and on
   461 the first body line). Expected: titles and body text reflow; the shadow is decoration.
2. ~~Table-of-contents entries with `=` become formula crops (FAA 6, 14).~~ Fixed by `785a974` (#100/#102);
   confirmed on the merged build: the entries reflow as text.
3. **Worked-example prose inside formula crops.** FAA page 251 (`2. Enter the moment for each item
   listed. Remember` / `3. Find the total weight and total moment.`) and page 298 (`The height of the
   cloud base is 3,180 feet AGL.`). Expected: the instructions and conclusion reflow beside the
   displayed arithmetic.
4. **Five FAA pages fall back to whole-page images for unsupported graphics** (226, 286, 288, 302,
   448; 2,278 words). Expected: reflowed text where the drawing budget or operator is the only cause.
