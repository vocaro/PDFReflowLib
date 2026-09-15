# Raster resolution and encoding across six documents

The sampled evidence supports **180 DPI as the starting baseline, with a 240-DPI trial for
dense small print and fine diagram labels**. At fixed encoding, 240 DPI improves edge detail
but adds about 47-49% to full-page image storage relative to 180 in this seven-page sample.
120 DPI saves bytes but visibly coarsens small scan notes and labels. These observations
refine the conversion-options roadmap task; they do not establish an optimal universal range.

JPEG 0.90 remains useful for the tinted Warren scans. It barely reduces the checked Blue Book
table page at 180 DPI, increases the clean Flag table and algebra equation crops, and introduces
visible edge artifacts in the small colored FAA label. Keep lossless PNG as the starting
region policy and compare clean black-and-white scans separately. Runtime defaults are unchanged.

## Identity and experiment

Base revision `ad8bba4`, Mac17,6 arm64, macOS 27.0 (26A428), Xcode 27.0 (27A266a),
2026-09-15. [identity.json](identity.json) retains full source SHA-256/byte identities, the
compiled probe and producer hashes, tool versions and compilation command.

The development probe compiles the **actual production `PageRasterizer` and value types**.
It opens the original pinned PDFs directly and renders each page's crop box plus one manually
selected source-coordinate region. These regions are review targets, not claims about the
library's region detector or a conversion's exact image inventory. There are no PDF derivatives,
OCR calls, native-text extraction, reconstruction, EPUB packaging or runtime changes.

For every page/region at each requested DPI, PNG and ImageIO JPEG 0.90 encode the **same
CGImage**, with identical dimensions. Each process renders seven pages and seven regions,
then encodes both formats: 28 images. The measured main campaign uses the unchanged
12-million-pixel ceiling and three fresh processes per DPI, rotating DPI execution order:
180/120/240, 240/180/120, 120/240/180. PNG always encodes before JPEG; per-encoding time is
retained but is not used for a comparative speed recommendation.

A tenth fresh process requests 240 DPI with a separate 1-million-pixel ceiling to demonstrate
cap behavior. This is an experimental control, not a recommended pixel budget. All 280
image outputs have independently decoded dimensions within the specified ceiling. Repeat
trials have identical image SHA-256 values. [results.json](results.json) includes every
image size, actual DPI in each axis, rectangle, hash, same-DPI JPEG error metric, operation
time and process resource observation.

## Source review

Targets were selected from source renders, before measuring converter rasters.
[targets.json](targets.json) records normalized crop-box rectangles with a top-left origin
and the independently reviewed text/detail. Original PDFs remain in the checksum-verified
ignored corpus cache. Poppler renders each original at 360 DPI, independently of the library;
[source-references.json](source-references.json) pins those commands, images and crop bounds.

The retained sheets compare identical source areas at a common 240-DPI display size. Lower-DPI
output is enlarged with nearest-neighbor sampling so its coarse pixels remain visible; the
360-DPI Poppler reference is reduced with Lanczos. This presentation exaggerates pixels relative
to readers that smooth magnification; it does not model a particular reader, screen or vision
impairment. Native-resolution region assets and source crops are also retained. Source-coordinate
crop edges intentionally cut the same surrounding material, including the DGA title continuation.
Poppler and Core Graphics have different antialiasing and color behavior; the source render is a
content reference, not a pixel-equality oracle.

| Source, physical page | Reviewed detail | Observation |
| --- | --- | --- |
| Warren 50 | Opening date, thin serifs and the Soviet Embassy phrase | Both encodings retain the checked phrase; 120 has coarse/broken-looking thin edges, 180 improves them, 240 is smoother. [Page](review/warren-50-page-comparison.png), [region](review/warren-50-region-comparison.png). |
| Warren 890 | Small notes 415-421, names and punctuation | 120 makes tiny character shapes harder to distinguish, including the first note's `8 H 232`; 180/240 preserve clearer shapes. No inherited-OCR or note-link accuracy is inferred. [Page](review/warren-890-page-comparison.png), [region](review/warren-890-region-comparison.png). |
| Blue Book 150 | Printed Certain/Doubtful/Total headers and handwritten first-row cells | 120 weakens the tiny headers; 180/240 separate their letter shapes better. Checked first-row digits/decimal points remain visible in both formats. The remaining handwriting is unqualified. [Page](review/blue-150-page-comparison.png), [region](review/blue-150-region-comparison.png). |
| FAA 121 | Orange `Level flight / forces balanced / constant speed` callout | All words remain identifiable; 240 provides smoother letter edges than 120/180. JPEG produces edge/color artifacts around the orange border even where its bytes are lower. [Page](review/faa-121-page-comparison.png), [region](review/faa-121-region-comparison.png). |
| DGA 3 | Food photograph beside green title and small body text | Higher DPI sharpens lettering and photo detail. JPEG retains the reviewed visible text; its smaller file alone does not establish indistinguishable image quality. [Page](review/dga-3-page-comparison.png), [region](review/dga-3-region-comparison.png). |
| Our Flag 27 | Two small-cap headers, ten numeric pairs and dot leaders | All checked pairs survive at the three settings; small caps and dots are cleaner at 240. PNG is smaller than JPEG for this clean region. [Page](review/flag-27-page-comparison.png), [region](review/flag-27-region-comparison.png). |
| Wallace algebra 343 | Three equation steps, radicals, exponents, fraction rules and plus/minus signs | The checked structures remain visible in both formats; 120 has weaker fine edges. PNG is smaller for this clean region. This does not qualify formula detection or semantics. [Page](review/algebra-343-page-comparison.png), [region](review/algebra-343-region-comparison.png). |

The review finds no missing checked glyph or changed checked number caused by JPEG 0.90 in
these crops. It is a bounded visual observation, not a reader study, character-error rate or
guarantee for every cell, image or DPI. Pixel-error statistics compare JPEG only against its
same-DPI PNG; they do not measure readability and are not compared across resolution settings.

Algebra crops and arrangements derive from *Beginning and Intermediate Algebra*, copyright
2010 Tyler Wallace, [source](http://wallace.ccfaculty.org/book/book.html),
[CC BY 3.0](https://creativecommons.org/licenses/by/3.0/). They retain that license and are not
relicensed under MIT. Other sources retain their corpus provenance; see
[third-party notices](../../doc/third-party-notices.md).

## Storage and resource observations

Each storage cell sums the seven full-page files or seven manually selected region files at
that one encoding. Pages and crops intentionally contain duplicate source content; do not add
the columns and treat the result as a predicted EPUB size. MiB = 1,048,576 bytes; KiB = 1,024.

| Requested DPI | Full-page PNG MiB | Full-page JPEG MiB | Region PNG KiB | Region JPEG KiB | Median probe seconds | Peak RSS range, MiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 120 | 3.160 | 2.297 | 150.2 | 123.2 | 0.901 | 188.1-191.5 |
| 180 | 6.031 | 4.268 | 287.2 | 214.6 | 1.135 | 191.4-191.9 |
| 240 | 8.847 | 6.353 | 427.9 | 319.4 | 1.256 | 210.3-211.1 |

The full-page pixel totals are 7,485,565 / 16,844,536 / 29,951,133 across the seven pages.
At the same encoding, raising 180 to 240 increases full-page bytes by 46.7% (PNG) or 48.8%
(JPEG); lowering to 120 decreases them by 47.6% or 46.2%. These percentages belong to this
sample, not every page or complete book. The three settings do not trigger the default pixel cap.

Encoding benefits differ even at a fixed 180 DPI:

| Target | Full-page PNG bytes | Full-page JPEG bytes | Region PNG bytes | Region JPEG bytes |
| --- | ---: | ---: | ---: | ---: |
| Warren 50 | 1,351,535 | 570,392 | 46,323 | 21,779 |
| Warren 890 | 1,436,021 | 617,323 | 47,692 | 22,571 |
| Blue Book 150 | 1,074,338 | 1,065,180 | 45,835 | 42,572 |
| FAA 121 | 849,627 | 831,296 | 21,969 | 13,548 |
| DGA 3 | 1,073,634 | 696,061 | 80,669 | 42,601 |
| Our Flag 27 | 262,312 | 372,986 | 29,950 | 51,652 |
| Algebra 343 | 276,960 | 322,111 | 21,638 | 25,038 |

Warren full pages shrink about 57%, Blue Book only 0.9%, FAA 2.2%, and DGA 35.2%. At 240 DPI
the FAA full-page JPEG is instead 3.9% larger than PNG. The FAA 180-DPI region's same-raster
JPEG comparison has 29.13 dB RGB PSNR and maximum channel error 98, versus 42.00/42.39 dB for
the two Warren crops. These errors help locate encoding changes; their magnitude is not a
legibility threshold. JPEG is not universally smaller, even for image-heavy pages.

The separate 1-million-pixel control reduces the requested 240-DPI FAA full page to 876 x 1141
pixels, approximately 106 DPI. Its small region remains 405 x 134, approximately 239 DPI after
integer rounding. All seven full pages are capped, at approximately 102-146 DPI, while all
seven small regions remain close to 240. The ceiling applies independently per raster; increasing
requested DPI alone cannot increase detail once the cap binds.

Process timing includes opening originals, rendering, both encoders and JSON output. It excludes
compilation, Python image decoding/metrics and Poppler review. RSS is the fresh **raster probe's**
high-water mark, not library conversion RAM; peak physical footprint is recorded separately.
Three short Mac runs do not establish a timing distribution, long-running memory behavior or an
iPhone/iPad budget. The final campaign ran after the offline gate. An earlier overlapping gate/
experiment run is retained in `exploratory-receipts.tar.gz`; its timings are not used above.
Its output image hashes match the final campaign. A sandbox-blocked hardware-identification
launch stopped before any raster measurements and is not counted as a trial.

## Verification, retained evidence and reproduction

`scripts/check-all.sh --fast` passes 160 Swift tests, 77 Python tests, the fresh-process native
concurrency smoke gate, six fixture EPUB conversions, eight CLI policy conversions and twelve
rejection/cleanup cases. `fast-gate.log.gz` retains the complete log; `gate-receipts.tar.gz`
contains fixture/policy/concurrency JSON and validator logs. This is the existing offline lane;
the full corpus and iOS Simulator are not rerun because no runtime, test fixture, extraction,
layout or rendering implementation changed. The experiment uses seven original source pages
and does not claim complete-book EPUB validation.

The measured probe requires the pinned corpus cache, full Xcode, Python with Pillow, and
Poppler. It makes no downloads and refuses an existing output directory. From the repository root:

```sh
python3 measurements/raster-dpi/measure.py --output /tmp/pdfreflow-raster-dpi-review
scripts/check-all.sh --fast
```

`receipts.tar.gz` contains every raw final process JSON/log and the first-trial native region
assets at all settings, including the separate cap control. `review/` retains both page and
region comparison sheets and independent 360-DPI source crops. Full-page native images,
independent full-page source renders and all repeat assets remain in the local run directory;
their hashes and dimensions are retained in the JSON evidence. Producer sources are committed
with this record and identified by hash, so no temporary standalone producer is required.

Only the bounded raster-DPI measurement is completed. The broader roadmap entry remains with
precise remaining work: broader pages/settings, full-book conversion and OCR effects of changed
DPI, and physical-device raster/storage budgets. No issue is closed. This experiment does not
repair inherited text, classify diagrams, qualify formula/table semantics, or revisit the rejected
OCR-heading approach.
