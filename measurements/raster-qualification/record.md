# Raster DPI and JPEG quality across 17 pages and four complete books (#28, Mac scope)

This measurement extends the [seven-page raster sweep](../raster-dpi/record.md) to 17 reviewed
pages from eleven English corpus documents at 96, 120, 150, 180, 240 and 300 DPI, with PNG and
JPEG 0.60, 0.75, 0.85, 0.90 and 0.95 encoded from the same raster, and converts four complete
books at 120, 180 and 240 DPI through the release CLI and the real-document evaluator. Items (1)
and (2) of issue #28 are covered on this Mac. **Item (3), physical iPhone/iPad raster and memory
budgets, is out of scope here and remains open**; nothing below is a device budget.

Observations and recommendations are separated. Runtime defaults are unchanged.

## Observations in brief

- Full-page PNG bytes track pixel count: relative to 180 DPI, the 17 pages need −63% at 96,
  −47% at 120, −28% at 150, +49% at 240 and +94% at 300. Class ratios are similar (scans +50%
  at 240, figures +52%, small text +32%).
- Resolution, not JPEG quality, decides legibility of small scan type. Vision finds none of the
  nine tiny Warren page-890 notes at 96 or 120 DPI, 3 at 150, 5 at 180, 6 at 240 and 8 at 300;
  the Warren page-100 body text goes 0/4/7 of 7 phrases at 96/120/150. The 9/11 endnotes recover
  3 of 11 phrases at 96 DPI and all 11 from 120 up. Born-digital figure labels, the Fed table
  rows, the USGS table and the typewritten Blue Book table are found in full at every setting.
- At a fixed DPI, JPEG quality from 0.60 to 0.95 changes phrase recovery by at most ±1 phrase
  on any target, glyph coverage by under 0.06, ink contrast by under 0.005 and color agreement
  by under 0.002. The glyph checker's extra-ink measure does register JPEG ringing on clean
  crops (0.000 PNG → 0.024 at 0.60 → 0.008 at 0.95 for the Flag table), far below its 0.12 gate.
- Storage: at 180 DPI, JPEG 0.60/0.75/0.85/0.90/0.95 full pages are −62/−52/−43/−41/−38% of PNG
  for the six scans and −67/−58/−49/−48/−45% for the six figure pages, but clean table, equation
  and small-text pages are *larger* as JPEG at 0.75 and above (+18…+61%) and only break even at
  0.60. Same-raster PSNR at 0.60 is 36–48 dB, at 0.90 38–57 dB.
- Visible artifacts: at 3× magnification the FAA orange callout and the Fed dark-red header
  band show faint blocking and letter halos at 0.60 and, less, at 0.75; 0.85 and above are
  visually close to PNG. Tinted Warren scans show no visible change from 0.60 to PNG.
- Whole books (CDC comic, Fed, Blue Book, Wallace): changing DPI changes only image bytes,
  elapsed time, physical footprint and the OCR transcription of pages that were already OCR
  pages. No page changes reflow/OCR status, warning counts are identical, every text and
  order contract passes at 120 and 240, all memory gates pass, and EPUB size scales with image
  bytes (CDC 72/143/225 MiB, Blue Book 117/197/273 MiB at 120/180/240).
- The corpus reference-image checks are bound to 180 DPI by construction: every region and
  glyph reference fails raw at any other resolution (`gate_view` below), so a changed
  `rasterDPI` cannot pass the current corpus lane without regenerating references.

## Recommendations (evidence-bounded)

- Keep **180 DPI** as the documented baseline. **96 DPI is not recommended for scans or small
  print** (tiny notes are lost to Vision and thin strokes lose peak darkness); 120 DPI remains a
  storage-only choice with visibly coarse small scan type. **150 DPI** recovers most body-size
  scan text at −28% bytes and is a measured intermediate for storage-constrained scanned reading
  copies whose small notes are not essential. **240 DPI** improves tiny notes further and 300
  DPI more still, at +49% and +94% bytes; both passed all four book gates on this Mac, which is
  not a device qualification.
- For tinted scans and photographic full pages, **JPEG 0.75–0.90** is a measured range: 0.75
  saves a further 18–19% of bytes over 0.90 on scans with no measured legibility change; 0.60
  saves 35% more but shows faint halos on colored labels. Keep PNG for clean crops (tables,
  equations, small black-on-white text), where JPEG above 0.60 is larger.
- **No library default change is proposed.** The evidence would support a scan-oriented client
  configuration of JPEG 0.75–0.85 full pages with PNG regions, but making JPEG the library
  default trades lossless output for storage on documents where it is larger, and the
  evidence stops at this Mac, these 17 pages and four books.

## Identity

The page sweep ran on base revision `ad7dcf4`; the whole-book runs and gates ran on `3507d7d`
(after #29 and #36 landed), both with this measurement's uncommitted tooling (CLI `--raster-dpi`
and `--maximum-raster-pixels`, evaluator `--converter-option`, `tools/raster_sweep.py`,
`tools/probe-raster-sweep.swift`, `tools/raster_book_comparison.py`). The sweep probe renders
each page's crop box and a reviewed source rectangle directly through `PageRasterizer`; it does
not run region detection, so #36's crop-expansion rewrite (which changes which regions become
crops on USGS pages 1–2, Wallace and FAA pages) does not affect any sweep number. The four
compiled production sources are byte-identical between the two revisions (hashes in
`sweep/identity.json`). Mac17,6 (Apple M5 Max),
macOS 27.0 (26A428), Xcode 27.0 (27A266a), Poppler pdftoppm 26.04.0, 2026-09-16, host terminal
(Metal `Apple M5 Max`, Vision succeeded in every capability probe).

- Release CLI SHA-256 `fc0bc441c2891abf7beb18c577241ae382dd8b7cb4c55618dbd852cf00895190` (`3507d7d`
  plus the CLI flags) for the retained book runs.
- Capability probe (`tools/probe-raster-environment.swift`)
  `805c9c5f5b56c31896e9a563d1ab9428d4159efa0d50ee7b348848f61d694d34`.
- Sweep probe binary `01b52a18892ca0b2581bc5ba85ea1a1840cc071c8590ea459c9c6bdafb87dfa3`;
  [sweep/identity.json](sweep/identity.json) lists the compile command and the SHA-256 of
  every compiled production source and producer script.
- Sources are the manifest-pinned corpus cache; every target and reference records the source
  SHA-256.

## Part 1: page sweep

### Method

`tools/raster_sweep.py` compiles `tools/probe-raster-sweep.swift` with the production
`PageRasterizer` and value types, then runs one fresh process per DPI. Each process renders
every target's crop box (with page rotation, as full-page images are produced) and one reviewed
source region, encodes the identical `CGImage` as PNG and as ImageIO JPEG at each quality, and
recognizes each *encoded* region file with Vision `RecognizeDocumentsRequest` (English, no
language correction), so both resolution and lossy encoding reach the recognizer. The driver
records bytes, dimensions, effective DPI, JPEG error against the same-DPI PNG, per-process peak
RSS and footprint from `/usr/bin/time -l`, the corpus checkers' metrics, and the fraction of
reviewed phrases found (whitespace-insensitive substring match).

Checker metrics are computed two ways: **raw**, on the image as encoded, which is what the
corpus gate would compute if a book were converted at that setting; and **normalized**, after
Lanczos resampling to the 180 DPI the references assume, which measures whether the content
survives independently of scale. Both the region crop and the page raster are checked.

There is no extraction, reconstruction, EPUB packaging or runtime change in the sweep; it
measures isolated page rasters. Vision phrase recovery is a bounded legibility proxy, not an
OCR accuracy rate or a reader study.

### Targets

[targets.json](targets.json) records each region (PDF points from the crop box's top-left, or
the earlier sweep's normalized rectangle), the reviewed content, the phrases and references.
Eleven measurement-only references were rendered from the sources with
`render_references.py` into [references/](references/) (never `corpus/references`); the rest
are the committed corpus references.

| Target | Class | Region | Phrases | References |
| --- | --- | --- | ---: | --- |
| warren-50, warren-890 | scan (tinted, thin serifs / tiny notes) | as raster-dpi sweep | 2, 9 | glyph + region (new) |
| warren-100 | scan (body prose with note markers) | new | 7 | glyph + region (new) |
| blue-150 | scan (printed headers, handwritten row) | as raster-dpi sweep | 10 | glyph + region (new) |
| blue-74 | scan (typewritten Table IV) | new | 21 | glyph + region (new) |
| geltman-1 | scan (two-column paper abstract) | new | 5 | glyph + region (new), page (corpus) |
| faa-121 | figure (orange callout) | as raster-dpi sweep | 3 | three region + color (corpus) |
| fed-45, fed-82 | figure (diagram node; regulations table) | new | 5, 8 | glyph + color (+ region) (new) |
| dga-3 | figure (photo, gradient title) | as raster-dpi sweep | 2 | color + region (new) |
| flag-27 | table (clean numeric) | corpus reference region | 15 | region (corpus), glyph (new) |
| flag-33 | figure (Colorado flag) | corpus reference region | 0 | color (corpus) |
| cdc-13 | figure (comic, upper-right quarter) | new | 0 | page (corpus) |
| algebra-343, algebra-347 | equation | as sweep / corpus region | 2, 0 | glyph (+ region) (corpus) |
| usgs-1 | small text (borderless table) | corpus reference region | 15 | region ×2, glyph, appearance (corpus) |
| 911-472 | small text (endnotes 38–41) | new | 11 | glyph + region (new) |

Each DPI process renders 17 pages and 17 regions and writes 204 images; 1,224 images in
total, all with independently decoded dimensions equal to the probe's and within the unchanged
12-million-pixel ceiling (300 DPI letter pages are 2,550 × 3,300 = 8.4 Mpx, so the ceiling never
binds). No Vision call failed. [sweep/results.json.gz](sweep/results.json.gz) retains every
row including recognized lines; [sweep/tables.md](sweep/tables.md) is regenerated from it by
`tables.py`, and [sweep/summary.md](sweep/summary.md) by the driver.

### Storage

Full-page PNG MiB by class; the change is relative to 180 DPI. MiB = 1,048,576 bytes.

| Class (pages) | 96 DPI | 120 DPI | 150 DPI | 180 DPI | 240 DPI | 300 DPI |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| scan (6) | 2.16 (−66%) | 3.14 (−50%) | 4.76 (−24%) | 6.27 | 9.39 (+50%) | 11.48 (+83%) |
| figure (6) | 2.55 (−62%) | 3.56 (−47%) | 4.43 (−34%) | 6.68 | 10.14 (+52%) | 13.91 (+108%) |
| table (1) | 0.11 (−55%) | 0.15 (−39%) | 0.19 (−22%) | 0.25 | 0.36 (+44%) | 0.43 (+73%) |
| equation (2) | 0.21 (−57%) | 0.28 (−44%) | 0.38 (−22%) | 0.49 | 0.67 (+37%) | 0.93 (+89%) |
| small-text (2) | 0.45 (−56%) | 0.60 (−42%) | 0.82 (−20%) | 1.02 | 1.35 (+32%) | 1.78 (+74%) |
| All (17) | 5.48 (−63%), 12.0 Mpx | 7.73 (−47%), 18.8 Mpx | 10.58 (−28%), 29.4 Mpx | 14.72, 42.3 Mpx | 21.92 (+49%), 75.3 Mpx | 28.53 (+94%), 117.6 Mpx |

Full-page MiB at 180 DPI by encoding; the change is relative to PNG of the same raster.

| Class (pages) | png | jpeg60 | jpeg75 | jpeg85 | jpeg90 | jpeg95 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| scan (6) | 6.27 | 2.37 (−62%) | 3.03 (−52%) | 3.59 (−43%) | 3.70 (−41%) | 3.89 (−38%) |
| figure (6) | 6.68 | 2.21 (−67%) | 2.84 (−58%) | 3.39 (−49%) | 3.50 (−48%) | 3.69 (−45%) |
| table (1) | 0.25 | 0.24 (−5%) | 0.30 (+18%) | 0.35 (+39%) | 0.36 (+42%) | 0.37 (+49%) |
| equation (2) | 0.49 | 0.38 (−22%) | 0.46 (−6%) | 0.53 (+9%) | 0.54 (+11%) | 0.57 (+16%) |
| small-text (2) | 1.02 | 1.03 (+1%) | 1.30 (+27%) | 1.52 (+49%) | 1.56 (+53%) | 1.64 (+61%) |
| All | 14.72 | 6.23 (−58%) | 7.92 (−46%) | 9.38 (−36%) | 9.66 (−34%) | 10.16 (−31%) |

Per-target bytes, PSNR per quality and the DPI × quality cross-tables are in
[sweep/tables.md](sweep/tables.md). The 180-DPI Warren 50/890, Blue Book 150, FAA 121, DGA 3,
Flag 27 and algebra 343 PNG/JPEG-0.90 byte counts reproduce the earlier record exactly
(for example Warren 50: 1,351,535 / 570,392), so the two sweeps share one rasterizer output.

### Probe process resources

| DPI | Peak RSS MiB | Peak footprint MiB | Seconds |
| ---: | ---: | ---: | ---: |
| 96 | 460.2 | 307.4 | 15.0 |
| 120 | 389.8 | 293.8 | 13.7 |
| 150 | 404.9 | 305.3 | 14.3 |
| 180 | 442.6 | 306.3 | 14.6 |
| 240 | 362.2 | 347.8 | 16.8 |
| 300 | 476.7 | 405.4 | 17.7 |

Each process renders 34 rasters, encodes 204 files and runs 102 Vision requests. Peak RSS is
not monotonic in DPI (Vision's working set dominates); the sampled footprint rises from about
300 MiB at 96–180 DPI to 348 MiB at 240 and 405 MiB at 300. These are fresh-probe figures on
a Mac, not converter or device budgets.

### Fidelity: which measures discriminate

Vision phrase recovery from the PNG region crop by DPI (found / reviewed):

| Target (phrases) | 96 | 120 | 150 | 180 | 240 | 300 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| warren-50 (2) | 1 | 1 | 2 | 2 | 2 | 2 |
| warren-890 (9) | 0 | 0 | 3 | 5 | 6 | 8 |
| warren-100 (7) | 0 | 4 | 7 | 6 | 7 | 7 |
| blue-150 (10) | 5 | 5 | 9 | 7 | 8 | 9 |
| blue-74 (21) | 21 | 21 | 21 | 21 | 21 | 21 |
| geltman-1 (5) | 1 | 3 | 5 | 5 | 4 | 5 |
| faa-121 (3) | 3 | 3 | 1 | 3 | 3 | 3 |
| fed-45 (5) | 5 | 5 | 5 | 5 | 5 | 5 |
| fed-82 (8) | 8 | 8 | 8 | 8 | 8 | 8 |
| dga-3 (2) | 1 | 1 | 1 | 1 | 1 | 1 |
| flag-27 (15) | 15 | 15 | 14 | 14 | 13 | 14 |
| algebra-343 (2) | 2 | 2 | 2 | 2 | 2 | 2 |
| usgs-1 (15) | 15 | 15 | 15 | 15 | 15 | 15 |
| 911-472 (11) | 3 | 11 | 11 | 11 | 10 | 11 |

The same table at each DPI by encoding (in `tables.md`) varies by at most one phrase between
PNG and any JPEG quality, in both directions, on every target; the misses at 180 are
recognizer line-splitting and misreads (`Td.` for `Id.`, `IOTALS`, the DGA `hiah-auality`,
the Flag `4 x 6` pair split across lines), not encoding effects. Handwritten Blue Book digits
stay partially recognized at every setting. The FAA 150-DPI dip (1 of 3) reproduces across all
six encodings of that raster and is a recognizer sensitivity to that one scale, not a
resolution trend.

Glyph **sharpness** (median peak stroke darkness against the reference) rises monotonically
with DPI for small born-digital and typewritten type and plateaus at 180–240: Fed 45 caption
0.74/0.84/0.90/0.95/0.97/0.99, Fed 82 rows 0.73/0.83/0.89/0.94/0.96/0.98, 9/11 notes
0.78/0.90/1.00/1.07/1.05/1.07, Geltman abstract 0.77/0.83/0.85/1.02/1.01/1.02, Blue Book 150
headers 0.79/0.91/0.95/0.97/0.99/1.00. Tinted Warren scans sit at 1.03–1.10 at every DPI:
their source is already softer than the 180-DPI Poppler reference, so the probe cannot lose
what the scan lacks. Sharpness never changes by more than 0.01 with JPEG quality.

Measures that **cannot** discriminate these settings, with the reason:

- Glyph **coverage** (minimum tile ink ratio) is non-monotonic after resampling (Blue Book 74:
  0.45/0.70/0.59/0.54/0.11/0.48; USGS: 0.71/0.42/0.62/0.60/0.24/0.22). The checker aligns at
  the reference grid and tests erasure; hairline rules and resampling phase move the weakest
  tile. Ink is conserved by resampling, as the checker's design notes state, so coverage
  reports presence, not legibility.
- Glyph **extra ink** is a property of the source, not the setting: 0.24–0.44 for tinted
  scans and 0.10–0.32 for colored Fed bands at every DPI and quality, so the 0.12 gate fails
  those references regardless. On clean crops it stays under 0.03 at every setting.
- Ink **contrast** varies by under 0.03 across DPI and under 0.005 across quality; tinted
  Warren, Geltman and the pale FAA figure 5-35 sit below the 0.4 appearance gate at every
  setting because of the source tint.
- **Color agreement** is 0.99–1.00 at every setting for the Fed, DGA and Flag references.
- **Region correlation** of the page image rises from 0.91–0.93 at 96 DPI to 0.98–0.99 at 300
  for the Warren scans and stays ≥ 0.97 for born-digital pages; it separates only 96/120 from
  the rest on scans.
- Same-raster **PSNR** orders qualities but does not order legibility: the Blue Book table has
  47.8 dB at 0.60 and the FAA callout 38.1 dB at 0.95, yet both keep every phrase at every
  quality.

Raw checker results on PNG page images, as the corpus gate would see them:

| DPI | region passes | glyph passes | appearance passes | scale range |
| ---: | ---: | ---: | ---: | ---: |
| 96 | 0/18 | 0/13 | 5/23 | 0.528–3.083 |
| 120 | 0/18 | 0/13 | 5/23 | 0.660–3.851 |
| 150 | 0/18 | 0/13 | 10/23 | 0.825–4.813 |
| 180 | 18/18 | 5/13 | 18/23 | 0.991–5.779 |
| 240 | 0/18 | 0/13 | 15/23 | 1.321–7.706 |
| 300 | 0/18 | 0/13 | 18/23 | 1.651–9.630 |

Every region and glyph reference fails at any DPI other than 180 because the 36-DPI pooling
and full-resolution alignment assume the default raster. The 180-DPI glyph failures are the
eight tinted or colored measurement-only references (extra ink); the committed corpus
references all pass. Two large glyph references (Blue Book 74, USGS) pass on the region crop
but fail on the full 180-DPI page image (coverage 0.06 and 0.10) because the coarse search
then ±5-pixel refinement mis-aligns on a page-sized target; the corpus gate checks converter
crops, so this is a checker limitation to note, not a conversion defect.

### Visual review

The sweep writes 34 equal-area sheets (nearest-neighbour magnification beside a
Lanczos-reduced 360-DPI Poppler source crop; one DPI sheet and one encoding sheet per target)
plus all 1,224 native images to its output directory. To keep the committed footprint small,
[sweep/review/](sweep/review/) retains only the Warren 890 DPI and encoding sheets (quantized
to 48 colours, which leaves the magnified pixels intact) and a 3× zoom of the FAA callout
encodings at 180 DPI. `review-sheet-hashes.json` records the SHA-256 of every generated sheet
at full colour; rerunning the reproduction command below regenerates all of them and the
images.

- Warren 890 at 96 and 120 DPI has broken serifs and merged digits (`246-248` reads as
  `246-218` at 96); 150 is readable but soft; 180 is clean; 240/300 add smoother curves. The
  encoding sheet shows no visible difference from 0.60 to PNG on this tinted scan.
- 9/11 472 at 96 DPI has filled counters and ragged italics; from 120 up the notes read
  cleanly, matching the phrase table.
- FAA callout at 0.60 and 0.75 shows faint blocking in the orange gradient and a slight halo
  along the black letters at 3×; 0.85 and above match PNG at that magnification. The Fed
  header band shows the same order of effect on its white condensed text.

## Part 2: complete books at 120, 180 and 240 DPI

`books.py` ran each case sequentially through `tools/evaluate-real-document.py` with EPUBCheck,
the case's existing memory ceiling, the compiled capability probe, `--execution-context
host-terminal`, and `--converter-option=--raster-dpi=N` (new evaluator flag; the CLI gained
`--raster-dpi`). A library-default run precedes the three explicit settings. Each run was then
assessed by `tools/check_corpus_content.py`. `tools/raster_book_comparison.py` produced the
tables below ([books/*-comparison.json](books/)); the strict comparator
(`compare_conversion_runs.py`) refuses defaults-vs-explicit pairs because their receipt
`options` differ, so repeat runs of both `defaults` and `dpi-180` were captured and compared
strictly: all eight [repeat comparisons](books/) pass with no changed page records, images or
report fields. Between `defaults` and `dpi-180` the comparison tool reports zero changed text
pages and identical image bytes for all four books, so the explicit option reproduces the
default path.

Content (ref/other errors) counts reference-image failures separately from every other
contract check. RSS and footprint are converter-process figures on this Mac.

CDC Zombie Pandemic (42 pages, 9 OCR pages):

| Run | Passed | Peak RSS MiB | Footprint MiB | Seconds | EPUB MiB | Images | Image MiB | Reflowed | OCR pages | Content | Changed text pages |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| defaults | True | 375.1 | 211.3 | 7.8 | 142.8 | 42 | 143.1 | 38 | 9 | pass (0/0) | baseline |
| dpi-120 | True | 355.4 | 183.7 | 4.5 | 72.0 | 42 | 72.1 | 38 | 9 | fail (1/0) | 3 |
| dpi-180 | True | 371.7 | 215.6 | 7.6 | 142.8 | 42 | 143.1 | 38 | 9 | pass (0/0) | 0 |
| dpi-240 | True | 384.2 | 224.0 | 11.1 | 224.7 | 42 | 225.3 | 38 | 9 | fail (1/0) | 2 |
| defaults-repeat | True | 366.3 | 201.8 | 7.1 | 142.8 | 42 | 143.1 | 38 | 9 | pass (0/0) | 0 |

The Fed Explained (135 pages, 7 OCR pages):

| Run | Passed | Peak RSS MiB | Footprint MiB | Seconds | EPUB MiB | Images | Image MiB | Reflowed | OCR pages | Content | Changed text pages |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| defaults | True | 282.7 | 227.8 | 7.9 | 69.6 | 315 | 74.1 | 123 | 7 | pass (0/0) | baseline |
| dpi-120 | True | 260.9 | 208.1 | 5.8 | 41.0 | 315 | 42.9 | 123 | 7 | pass (0/0) | 1 |
| dpi-180 | True | 282.8 | 194.7 | 8.0 | 69.6 | 315 | 74.1 | 123 | 7 | pass (0/0) | 0 |
| dpi-240 | True | 309.3 | 217.8 | 10.3 | 95.4 | 315 | 103.7 | 123 | 7 | pass (0/0) | 1 |
| defaults-repeat | True | 280.1 | 231.8 | 7.0 | 69.6 | 315 | 74.1 | 123 | 7 | pass (0/0) | 0 |

Blue Book Special Report 14 (312 scanned pages, no fresh OCR):

| Run | Passed | Peak RSS MiB | Footprint MiB | Seconds | EPUB MiB | Images | Image MiB | Reflowed | OCR pages | Content | Changed text pages |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| defaults | True | 160.7 | 143.6 | 32.9 | 196.7 | 425 | 205.5 | 312 | 0 | pass (0/0) | baseline |
| dpi-120 | True | 151.8 | 139.7 | 28.4 | 117.3 | 425 | 120.5 | 312 | 0 | pass (0/0) | 0 |
| dpi-180 | True | 261.6 | 221.6 | 32.6 | 196.7 | 425 | 205.5 | 312 | 0 | pass (0/0) | 0 |
| dpi-240 | True | 206.9 | 192.0 | 41.3 | 272.9 | 425 | 290.3 | 312 | 0 | pass (0/0) | 0 |
| defaults-repeat | True | 162.1 | 147.5 | 32.0 | 196.7 | 425 | 205.5 | 312 | 0 | pass (0/0) | 0 |

Wallace algebra (489 pages, no OCR):

| Run | Passed | Peak RSS MiB | Footprint MiB | Seconds | EPUB MiB | Images | Image MiB | Reflowed | OCR pages | Content | Changed text pages |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| defaults | True | 78.1 | 58.7 | 18.5 | 42.8 | 2047 | 45.2 | 482 | 0 | pass (0/0) | baseline |
| dpi-120 | True | 72.4 | 55.0 | 16.8 | 25.2 | 2047 | 25.8 | 482 | 0 | fail (4/0) | 0 |
| dpi-180 | True | 75.4 | 56.7 | 18.4 | 42.8 | 2047 | 45.2 | 482 | 0 | pass (0/0) | 0 |
| dpi-240 | True | 81.1 | 57.8 | 19.8 | 56.1 | 2047 | 61.1 | 482 | 0 | fail (4/0) | 0 |
| defaults-repeat | True | 76.7 | 57.9 | 19.8 | 42.8 | 2047 | 45.2 | 482 | 0 | pass (0/0) | 0 |

Whole-book observations:

- Image counts, reflowed/recognized page counts, OCR page sets and warning counts (CDC 85,
  Fed 577) are identical at all three resolutions for all four books. Reference policy, OCR
  selection and layout do not depend on `rasterDPI`.
- The only text drift is on pages that are OCR pages at every setting: CDC pages 13, 15 and
  16 at 120 DPI and pages 13 and 16 at 240 (comic lettering; for example `OKAY` → `ОКДУ` at
  120 and `A` ↔ `Д` at 240 on page 13), and Fed page 7 (one letter of a 14-character
  image-only page) at both. [books/text-drift.json](books/text-drift.json) retains the texts.
  Fresh OCR of noisy lettering is not monotonically better at higher DPI in this sample; it
  is different, on 1–3 pages of the 16 OCR pages across the two books.
- Every content contract passes at 120 and 240 except the reference-image checks (CDC page 13
  page reference, four Wallace region/glyph references), which are 180-bound as shown above.
- Elapsed time follows raster work: 7–42% faster at 120 and 7–42% slower at 240 (the
  scan-heavy CDC and Blue Book move most, the text-heavy Wallace least). The converter's
  physical footprint at 240 is 3–13 MiB above 180 for CDC, Fed and Wallace, but two runs with
  byte-identical EPUBs differ by up to 101 MiB in peak RSS and 78 MiB in footprint (Blue Book
  `defaults` 160.7/143.6 versus `dpi-180` 261.6/221.6 MiB), more than any DPI effect, so
  these single Mac runs do not resolve the memory cost of this DPI range. All runs stay under
  their existing ceilings (CDC and Blue Book 512 MiB, Fed 768 MiB, Wallace 256 MiB); the
  240-DPI Blue Book run's 290 MiB of images is the largest output here and remains under the
  512 MiB entry budget.
- Image bytes at 120 and 240 are −50%/+57% (CDC), −42%/+40% (Fed), −41%/+41% (Blue Book) and
  −43%/+35% (Wallace) of 180, consistent with the page sweep.
- An earlier pass of the same runs on `ad7dcf4` (before #36) gave identical CDC and Fed
  outputs and the same drift pages; #36 changed the Blue Book (422 → 425 images) and Wallace
  (2,050 → 2,047 images, 481 → 482 reflowed pages) crops at every DPI alike. Only the
  `3507d7d` runs are retained.

## Documentation changes made

`doc/conversion-options.md` gains the measured 0.75–0.90 JPEG range for scans, the
96/150/300 DPI observations, the sweep tooling, and a rewritten gaps statement; it keeps
`.png` as the region recommendation and 180 DPI as the baseline. `doc/memory-testing.md`
documents `--converter-option`; `doc/regression-testing.md` notes that reference-image checks
are 180-bound and the renderer's `--output-root`. No default in `ConversionOptions` changed.

## Reproduction

From the worktree root with the pinned corpus cache, full Xcode, Python with numpy/Pillow,
Poppler and EPUBCheck:

```sh
swift build -c release
mkdir -p .build/raster-environment
xcrun swiftc -parse-as-library -O -module-cache-path .build/raster-environment/module-cache \
  Sources/PDFReflowLib/PageRasterizer.swift Sources/PDFReflowLib/ConversionTypes.swift \
  Sources/PDFReflowLib/DocumentModel.swift Sources/PDFReflowLib/ReflowDocument.swift \
  tools/probe-raster-environment.swift -o .build/raster-environment/probe
python3 measurements/raster-qualification/render_references.py
python3 tools/raster_sweep.py --targets measurements/raster-qualification/targets.json \
  --output /tmp/raster-sweep --workers 10
python3 measurements/raster-qualification/tables.py --results /tmp/raster-sweep/results.json
python3 measurements/raster-qualification/books.py --output /tmp/raster-books \
  --converter .build/release/pdf-reflow --environment-probe .build/raster-environment/probe \
  --case cdc-zombie-pandemic-2011 --case fed-explained-2021 \
  --case cia-blue-book-14-1955 --case wallace-algebra-2010
python3 tools/raster_book_comparison.py --case cdc-zombie-pandemic-2011 \
  --run defaults=/tmp/raster-books/cdc-zombie-pandemic-2011/defaults \
  --run dpi-120=/tmp/raster-books/cdc-zombie-pandemic-2011/dpi-120 \
  --run dpi-180=/tmp/raster-books/cdc-zombie-pandemic-2011/dpi-180 \
  --run dpi-240=/tmp/raster-books/cdc-zombie-pandemic-2011/dpi-240 --output /tmp/cdc-raster.json
```

The sweep took about 90 s of probe time plus about 6 minutes of parallel checker work; the
book runs 5–46 s each. Output directories must be new. `tools/test_raster_sweep.py`,
`tools/test_raster_book_comparison.py` and the new `tools/test_memory_gate.py` controls cover
the phrase matcher, normalization, target/reference validation, summaries, drift detection,
error classification and the evaluator's option forwarding and rejection.

## Verification

On the merged tree (`3507d7d` plus this work): `swift build -c release`, `swift test` (218 tests
in 3 suites passed), `python3 -m unittest discover -s tools -p 'test_*.py'` (155 tests OK) and
`scripts/check-all.sh --fast` (exit 0: the same suites, 8/8 native-concurrency processes, six
fixture conversions, 13 policy conversions and 22 rejection/cleanup cases including seven new
`--raster-dpi`/`--maximum-raster-pixels` rejections). The corpus lane and iOS Simulator were
not rerun: no extraction, layout or rendering implementation changed here.

## Open items and follow-ups

- **Physical iPhone/iPad raster and memory budgets (#28 item 3)** are untouched; no device ran.
- Whole-book runs cover 120/180/240 on four books; 96, 150 and 300 were measured only on
  isolated pages, and Warren and NOAA remain outside the passing lane (#5).
- The corpus reference-image, glyph and appearance checks are 180-bound. Qualifying another
  default would require regenerating every reference or resampling converted images to the
  reference resolution inside the checker; this record does neither.
- Large glyph references (Blue Book 74, USGS) mis-align on full-page images at 180 DPI while
  passing on crops; a checker follow-up could widen the refinement window or search at the
  reference scale. Not a conversion defect.
- Vision phrase recovery is a proxy. A reader study, or character-level accuracy against full
  transcriptions, would be needed before quoting legibility rates.
- No conversion crash, resource failure or page wrong at every setting was found in these runs.
