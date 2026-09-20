# Source-region image checks

Part of [#27](https://github.com/vocaro/PDFReflowLib/issues/27): table cells, equation structure and
image appearance. The converter emits no `<table>` element: tables, displayed equations, figures and
page fallbacks are preserved as images, so text contracts and `minimumImages` cannot tell whether a
crop shows the right, complete region. macOS 27.0 (26A428), arm64; Python 3.14.6, numpy 2.4.6,
Pillow 12.2.0, Poppler 26.04.0 (reference rendering only).

## Method

A reviewer chooses a region from the rendered source page (grid renders in PDF points), never from
converter output. `tools/render_region_reference.py` verifies the cached source against the manifest,
renders the region with `pdftoppm` at 180 DPI in grayscale, averages 5×5 blocks to 36 DPI, trims to
ink with a one-sample margin and writes the PNG plus a sidecar (case, source SHA-256, page, region,
target, renderer, resolutions, pixels, reference SHA-256).

`tools/image_regions.py` averages each converted image on the page the same way at all 25 grid
phases, pads it by two white samples and computes normalized cross-correlation at every placement
(integral images and FFT; equal to an exhaustive search in a unit test). The best score across the
page's images must reach `minimumCorrelation` (default 0.95). Converted images are assumed to use the
library's default 180 DPI.

Grid-phase search was added after the first measurement. Without it, correctly cropped dense text
scored as low as 0.81 (Geltman page), 0.84 (USGS statistics) and 0.60 (Wallace exercise column),
because a crop's origin is arbitrary relative to the reference's averaging grid. Rescaling the
converted image by ±1% lowered every score, so the loss was sampling phase, not scale.

## References and results

`scores.json` scores each reference against every image on its page in the complete corpus gate
outputs for `92bea9e`:

| Case | Page | Region | Best score |
| --- | --- | --- | --- |
| `gpo-our-flag-2003` | 27 | Flag-size table: headers and ten rows | 0.983 |
| `usgs-mcs2025-copper` | 1 | Salient Statistics table | 0.989 |
| `usgs-mcs2025-copper` | 1 | Tariff table | 0.988 |
| `usgs-mcs2025-copper` | 2 | World production and reserves table | 0.985 |
| `faa-phak-8083-25c` | 121 | Figure 5-35 turn diagrams | 0.982 |
| `faa-phak-8083-25c` | 121 | Figure 5-36 | 0.993 |
| `faa-phak-8083-25c` | 121 | Figure 5-37 | 0.989 |
| `wallace-algebra-2010` | 347 | Exercise 35 with squared terms | 0.984 |
| `nbs-jres-geltman-1977` | 1 | Complete page-image fallback | 0.984 |
| `cdc-zombie-pandemic-2011` | 13 | Complete image-only comic page | 0.997 |

Each crop was also viewed: the Our Flag crop holds both headers and all ten rows, the Wallace crop
is the left exercise column with exercise 35's exponents, and the USGS crops hold their complete
tables (with surrounding prose, #36).

`controls.py` recomputes `controls.json` from real outputs. Wrong images on the same page score
0.12–0.62, the Our Flag table with its lower half blanked 0.64, and the Wallace crop with exercise
35 erased 0.44, all failing. A 1.5-pixel Gaussian blur of the table still scores 0.96. Python unit
tests add synthetic controls for placement, tight crops, off-grid offsets, clipping, blank images,
different content, half-substituted rows (0.915), wrong scale, reference validation (path, sidecar
source and page, resolution, threshold bounds) and unavailable images.

## Limits

The check proves a region is present, complete and aligned at 36 DPI. It does not verify individual
glyphs, colors or legibility: erasing the final exponent from Wallace exercise 35 still scores 0.97.
Poppler and Core Graphics rasterize differently, so references are not pixel-exact; the 0.95 default
leaves about 0.03 of margin below correct crops. A different raster DPI or a binding pixel ceiling
changes image scale and fails every reference until they are regenerated. Scanned-table cell
transcription (#31) and structured table output remain separate work.

## Rows, columns and colour

A second pass on top of `e00432b` asked what a whole-table reference is actually sensitive to, and
added six references inside the two table crops: the Salient Statistics rows "Mine, recoverable"
and "London Metal Exchange, grade A, cash" and its 2022 column, and the flag-size table's
125-foot and 250-foot rows and its column of pole heights. Each region was chosen by reading the
source page cell by cell at 180 and 300 DPI; the renders were inspected before the references were
written. `cell-controls.py` recomputes `cell-controls.json` from converted output, mutating the
converted crop rather than the reference, so every control describes a defect a reader would see.

| Control | Whole table | Its row reference | Its column reference |
| --- | --- | --- | --- |
| USGS correct output | 0.989 | 0.995 / 0.997 | 0.991 |
| USGS London row erased | 0.954 | 0.676 | 0.940 |
| USGS Mine 2022 cell erased | 0.986 | 0.919 | 0.951 |
| USGS Mine 2022/2023 cells exchanged | 0.988 | 0.975 | 0.986 |
| USGS London 2020/2021 cells exchanged | 0.987 | 0.958 | 0.991 |
| USGS 2022 column, two rows' values exchanged | 0.987 | 0.975 | 0.957 |
| Our Flag correct output | 0.983 | 0.992 / 0.993 | 0.983 |
| Our Flag 125-foot row erased | 0.927 | 0.870 | 0.903 |
| Our Flag 125-foot size cell erased | 0.951 | 0.870 | 0.983 |
| Our Flag two rows' sizes exchanged | 0.975 | 0.963 | 0.983 |
| Our Flag two rows' pole heights exchanged | 0.962 | 0.963 | 0.890 |

At the 0.95 default the whole-table reference misses a lost cell (0.951, 0.986) and, on USGS, a
lost row (0.954); the row reference catches both (0.676–0.919), and the column reference catches a
value moved to another row (0.890) that nothing else catches. No reference catches two cells of
similar shape exchanged inside one row or column: the lowest such score is 0.957, and the closest
pair (1,230 against 1,130) scores 0.975 even in a crop holding only those two cells. Raising the
floor to about 0.98 would catch them, but correct crops sit at 0.982–0.997, so the margin would be
smaller than the renderer disagreement the 0.95 floor exists to absorb. The references were left at
the default and the limit recorded instead.

Colour is not compared at all: the reference is rendered `-gray` and every converted image is
reduced to `L`. Recolouring CDC's page-13 comic to its complementary chroma in CIE Lab, which
preserves lightness while changing 23.2% of the pixels by more than 20 levels in some channel and
1.9% by more than 60, leaves the score at 0.997 against 0.997 for the correct output. What an
appearance gate would need before it could be added is in
[regression-testing](../../doc/regression-testing.md#why-there-is-no-colour-or-pixel-appearance-gate).
