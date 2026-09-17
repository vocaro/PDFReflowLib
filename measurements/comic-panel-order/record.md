# Comic panel and speech-balloon order (#18): audit, no runtime change

Tier: deterministic Apple PDF/OCR stack, library defaults, macOS 27.0 (26A428) arm64, Xcode 27.0
(27A266a), release CLI, host terminal. Source: Preparedness 101: Zombie Pandemic
(`cdc_6023_DS1.pdf`, SHA-256 `d95e9ec2…efc3`, 42 pages). The audit was run at `9bf4e76` (CLI
`0666945a…556b`) and confirmed at `43b20aa` (CLI `f5219c58…3c2f`): `compare_conversion_runs.py
--allow-different-converters` reports no changed page, image, OCR page or report field, with
equal Vision model programs ([receipts/](receipts/)). Renders: `pdftoppm` 26.04.0 at 80 DPI.

**Result: #18 remains open. No library, test, contract or default change is proposed.** The
issue asks for panels found from paints; this book has none, and the only panel evidence is in
the page raster. A raster prototype is recorded below as a rejected approach.

## The source has no panel geometry

- **No paints.** Each of the 42 content streams draws one image `Do` covering the page (39
  distinct DCT or JBIG2 scans; blank pages 2, 38, 40 and 41 share one) plus, on 33 pages, one text
  object. `qpdf --qdf` shows no path
  operator (`re`, `m`, `l`, `c`, `S`, `f`, `W`, `sh`) on any page. `GraphicsReader` finds one
  page-sized region per page (the `cdc-26` fixture has one paint, `[0, 0, 612, 792]`).
- **The pipeline clears graphics on these pages anyway.** Text over a page-sized graphic is an
  `unverifiedTextLayer` page, and `extractPage` sets `graphics`, `tints` and `separators` to empty.
  OCR pages keep only recognized tables. `ordered()` never receives a rectangle to test for panels.
- **The text layer does sit on the artwork.** Native line rectangles match the lettering in the
  renders (page 4's `WELL I'M GOING…` balloon at render x 322–409, y 137–173, as drawn). The
  disorder comes from reading order, not misplaced text.

## Per-page audit (`43b20aa`)

[page-audit.tsv](page-audit.tsv) lists every page. Each page's EPUB text
([receipts/cdc-page-text-9bf4e76.txt](receipts/cdc-page-text-9bf4e76.txt)) was read against its
render. A *unit* is a speech balloon or caption box; sound effects in the art are not counted.
The counts are manual.

| Order of the dialogue that is reflowed | Pages | Count |
| --- | --- | ---: |
| Panel order | 3, 5, 9, 10, 18, 25, 26, 28, 32, 35 | 10 |
| Panels out of order | 4, 6, 7, 8, 11, 12, 13, 19, 21, 22, 24, 27, 29, 30, 33 | 15 |
| A balloon interleaved line by line with a caption box | 14, 23, 34 | 3 |
| One rotated caption, lines reversed (OCR) | 17 | 1 |
| Dialogue page with at most one unit reflowed | 20 (0 of 3), 31 (1 of 12), 36 (1 of 1) | 3 |
| No dialogue: cover, title, sign art, afterword, checklist, back cover, blank pages (2, 38, 40, 41 are page-image fallbacks) | 1, 2, 15, 16, 37, 38, 39, 40, 41, 42 | 10 |

- **Text source.** Of the 32 dialogue pages, 29 reflow the inherited native layer (damaged
  spelling, #7) and three use fresh OCR (13, 17, 36). No dialogue page is image-only; page 20's
  layer holds only noise.
- **Coverage.** About 124 of 231 dialogue units have any reflowed text. Most missing units are
  simply absent from the inherited layer: page 7 has 2 of 6, page 10 has 3 of 13, page 25 has 2
  of 8. That is text loss, not order.
- **The out-of-order pages share one cause.** `ordered()` cuts the widest vertical gutter first.
  On a grid of panels, the whitespace between balloons in the left panels and those in the right
  panels runs the full page height, so the page reads column-major: left panels of every row, then
  right panels (page 21 reads panels 1, 3, 5, then 2, 6, 4). Page 4 cuts away `VERY FUNNY.` (render
  x ≤ 110) as a left column ahead of the whole top panel. On OCR page 13 the single-line
  `(WHINE!)` and `UH? WHA?` already read first ([column-cuts](../column-cuts/record.md) records
  #47's heading bands moving them there), but the two-line `WHAT IS IT MAX? IT'S STILL DARK OUT.`
  still stays in the right column. It reads after `OKAY, OKAY… I'M COMING.`, which the review
  target forbids.
- **Interleaving** (14, 23, 34): a balloon beside a caption box leaves no gutter over text or
  whitespace, so the page falls to the reading-order sort and alternates their lines.

## Why text geometry cannot decide

Page 26 (the `speechBalloonsAreNotHeadingBands` control, correct today) and page 24 (wrong today)
have the same arrangement: balloons in a left panel, and balloons in the right panel set higher
and lower than them.

| Page | Left-panel balloon tops (render y) | Right-panel balloon tops | Source order | Column-first (today) | Top-to-bottom |
| --- | --- | --- | --- | --- | --- |
| 26 (one row, 2 panels) | `UH OH` 493, `WHAT? YOU'RE OUT OF GAS` 795 | `WELL…` 621, `DO ME A FAVOR` 815 | left, then right | correct | wrong (`WELL…` second) |
| 24 (two rows) | `WE'RE GONNA…` 261, `…AND THE CAR'S` 367, `I'VE GOT WATER` 463 (row 2) | `ALRIGHT, LET'S PACK` 169, `THE COAST…` 513 (row 2) | row 1 left, row 1 right, row 2 | wrong (`I'VE GOT WATER` third) | wrong (`ALRIGHT` first) |

Only the gutter between page 24's two panel rows separates the cases. It lies between y 438 and
451 in the artwork. A 72-px band of text whitespace (y 391–463) contains it, but it is not
distinctive. Page 24 has a wider band inside its second row (y 549–670, 121 px, between
`THE COAST…` and `OKAY, AS SOON…`) and one almost as wide inside its first (y 297–367, 70 px).
Page 26 has 92- and 150-px bands within its single row. Reading the widest band first would
read page 26 as `UH OH`, `WELL…`, `WHAT?`, `DO ME A FAVOR`. Any text-only rule that fixes
page 24 either breaks the page-26 control or relies on a threshold with no source basis.

## Rejected approach: panels from the raster

[panel-prototype.py](panel-prototype.py) runs recursive gutter cuts over an 80-DPI render: rows
before columns; ink as local contrast (a pixel 45 levels darker than its 8-px box mean); a gutter
is a light band flanked by border lines that passes through the region's own border lines.
[panel-prototype.tsv](panel-prototype.tsv) has every page's rectangles.
[panel-prototype-overlays.jpg](panel-prototype-overlays.jpg) shows pages 13, 24, 6 (correct) and
11 (rows 2–3 merged).

Development, each step on the same 42 renders:

1. Absolute ink (luma < 60), gutter lines ≤ 3% ink: tiers found on 7 pages, most gutters missed
   (gutter lines carry 3–7% JPEG and texture ink; borders peak beyond a 6-px search).
2. Gutter lines ≤ 8% ink, border ≥ 40% within 10 px: 25 comic pages split. The page foot's
   vignette (rows 853–879 of page 6 reach 60% "ink") blocked bottom-row gutters, and page 24's
   window frame split a panel.
3. A border-pierce test removed the window-frame split. Trimming regions to their strongest border
   lines collapsed regions onto interior borders (page 9 trimmed to y ≥ 572) and was dropped.
4. Local-contrast ink removed the vignette (page 6's gutter columns fall to 1–2% ink).

Final prototype, on the 32 dialogue pages:

| Segmentation | Pages |
| --- | --- |
| Correct | 6, 19, 22, 24, 25, 26, 27, 28, 29, 32 |
| Tiers correct, one row merged | 7, 8, 13, 30 |
| Mostly correct or partly merged | 9, 10, 18, 31, 33, 34 |
| Rows merged | 11, 12, 21 |
| A panel lost (a caption box straddles the gutter) | 5 |
| Tier gutter not found | 4, 14 |
| Irregular panels merged | 23 |
| Single panel (correct) | 3, 20, 35, 36 |

It also splits non-comic page 15 into its title band and image. No split inside a panel remained
on the comic pages.

Reading the overlays against the audit, tier-first ordering with these rectangles would plausibly
repair 6, 7, 8, 13, 19, 22, 24, 29 and 30. It would not repair 4, 11, 12, 21 and 33 (merged
rows or no tier gutter), nor the interleaved pages. This estimate was not run through the
reconstructor.

It is not shipped, for these reasons:

- **Environment-dependent input.** The CDC rasters themselves differ between execution
  environments: 36 images differ in decoded RGB between sandbox and host
  ([raster-environment](../raster-environment/record.md)). Reading order derived from pixels
  would inherit that drift, and panel cuts at 8% ink have little margin.
- **Thresholds fitted to one book.** Seven parameters (contrast, radius, gutter ink, border ink,
  gutter width, border search, panel size) were tuned by hand on these 42 pages. No second comic
  exists in the corpus to test them, and the rule that fixed one page broke others at each step.
  That is the kind of document-fitted threshold the [OCR headings record](../ocr-headings/record.md)
  refused for this issue.
- **New pipeline stage.** Rendering and analysing every image-backed page during extraction,
  adding a `PageContent` field and fixtures carrying rasters or derived panels is an
  architecture decision, not an `ordered()` rule.
- **Incomplete result.** Balloons that break panel borders (page 27's `YOU FOLKS MADE IT` and
  `GO ON INSIDE` sit in the large panel but speak for the row below), caption boxes across
  gutters (page 5) and merged rows need further rules. Missing dialogue is the larger loss on most
  pages.

## Verification

- CDC corpus lane at `9bf4e76` and `43b20aa`: PASS, 11 content checks, EPUBCheck, progress and
  memory gates ([receipts/](receipts/)); the two runs are page-identical.
- `swift test` at `43b20aa`: 527 tests pass. `scripts/check-all.sh --fast`: exit 0 (527 Swift,
  210 Python, 8/8 concurrency trials, 6 fixture conversions, 13 policy conversions and 22
  rejection/cleanup cases).
- No source, test or contract changed, so the other lane books (FAA, Fed, DGA, Our Flag) were not
  rerun: they cannot differ from the tip's own receipts.
- `python3 measurements/comic-panel-order/panel-prototype.py <renders>` reproduces
  `panel-prototype.tsv` from `pdftoppm -r 80 -jpeg corpus/cache/cdc_6023_DS1.pdf <renders>/p`
  (numpy 2.4.6, Pillow 12.2.0, Python 3.14.6).

## Defects to file (not fixed)

1. **CDC inherited text layer omits about half the dialogue** (roughly 107 of 231 units; e.g.
   page 7 `MAN I FORGOT I HAD THIS.`, `OH YEAH, BUDDY…`; page 20's three balloons; page 31's 11 of
   12 units). The pages report `unverifiedTextLayer`, not `ocrUsed`, so nothing recovers them.
   Expected: missing lettering recognized, or the page flagged as incomplete transcription.
   (OCR text-loss area.)
2. **A balloon beside a caption box interleaves line by line** on pages 14, 23 and 34 (e.g. 34:
   `wow... THAT o ld THINg STILL` / `in effect fo r THe FOLLowiNg couNTies…` / `w o r k s !`).
   Expected: each unit's lines kept together. `ordered()` reading-order sort fallback.
3. **Rotated OCR caption lines read bottom-first** on page 17 (`ATLANTA, GEORGIA...` before
   `SEVERAL DAYS LATER AT THE CENTERS FOR`). Expected: the caption's three lines in reading order.
4. **Panel order needs raster-derived panel evidence or a reviewed transcription**, which is an
   owner decision (raster determinism, calibration corpus). Until then the
   `unverifiedTextLayer`/`ocrUsed` warnings and the page reference image are the only signal on
   the 15 out-of-order pages; no warning says that reading order is unreliable.
