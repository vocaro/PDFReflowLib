# Glyph-level structure checks for preserved equations and tables

Part of [#27](https://github.com/vocaro/PDFReflowLib/issues/27). The 36 DPI source-region check
([image-regions](../image-regions/record.md)) proves a preserved crop is present, complete and
aligned, but it cannot see single glyph parts: erasing the final exponent from Wallace exercise 35
still correlated at 0.97. This record covers the `glyphRegions` contract type, which checks every
ink component of a full-resolution reference. macOS 27.0 (26A428), arm64; Python 3.14.6, numpy
2.4.6, Pillow 12.2.0, Poppler 26.04.0 (reference rendering only). Converter `56e70e2`, release build.

## Method

`tools/render_region_reference.py --kind glyph` renders a reviewed source region with Poppler at
180 DPI grayscale and keeps the full raster (no averaging), trimmed to ink with a four-pixel white
margin. The sidecar records `kind: glyph`, `referenceDPI: 180` and the source identity like the
36 DPI references.

`tools/glyph_structure.py` locates the reference in each converted image on the page with the
existing 36 DPI grid-phase search, refines the placement at full resolution (±5 px), then:

1. labels 8-connected ink components of the reference (gray < 160; specks under 6 px ignored) and
   splits each component into 16-px tiles so a long connected stroke (a radical with its vinculum,
   a fraction bar, a table rule) is checked piecewise;
2. computes **coverage** for every unit as the ratio of converted to reference ink mass within the
   unit's footprint (grown by two pixels, excluding other components' ink grown by one pixel and the
   exact pixels of the same component's other tiles). The page's score is the minimum over units.
   Blur and resampling spread ink but conserve it; an erased stroke leaves only its neighbours' spill;
3. computes **extra ink**: the fraction of the converted window's ink mass outside the reference's
   ink grown by two pixels, so substituted or added strokes are caught even where they overlap;
4. reports **sharpness** (median of the 3×3 peak-darkness ratio over components) and the weakest
   stroke for review. Sharpness is gated only when a contract sets `minimumSharpness` (see Limits).

A check passes when some image on the page reaches `minimumCoverage` (default 0.4) with at most
`maximumExtraInk` (default 0.12). Candidate approaches that were measured and rejected:

- Whole-component peak darkness (3×3 maximum): a σ=1.5 px blur drops one-pixel rules (minus signs,
  fraction bars) to 0.28–0.35, the same range as an illegible 60 DPI upsample, so it cannot be a
  tolerance-respecting gate. Kept as the informational sharpness statistic.
- Whole-component ink mass without tiling: erasing only the radical's check stroke still scored 0.60
  because the radical shares one component with its vinculum over `b² − 4ac`.
- Full-resolution normalized correlation: a correct Wallace page-343 crop scores only 0.687 because
  Core Graphics draws the hairline fraction bar thinner than Poppler, below every blur and resample
  control of the other crops (0.72–0.94).

## References

| Reference | Region (points) | Pixels | Components |
| --- | --- | --- | --- |
| `wallace-algebra-2010/page-343-our-solution-glyphs` | 176,658–283,690 | 263×73 | 18 |
| `wallace-algebra-2010/page-347-exercise-35-glyphs` | 80,625–245,645 | 385×39 | 23 |
| `usgs-mcs2025-copper/page-1-salient-statistics-glyphs` | 40,205–565,481 | 1289×666 | 932 |

Page 343 was rendered at 72 and 180 DPI and reviewed: the "Our Solution" line is
x = (−b ± √(b² − 4ac)) / 2a. Its component map (reference pixel boxes x0,y0,x1,y1) drives the
negative controls: exponent ² of b² at 168,7–177,20; fraction bar 54,41–259,43; radical sign with
vinculum 132,4–256,33 (the check stroke occupies 132–156). Exercise 35 on page 347 is
35) −5n² − 3n − 52 = 2 − 7n²; its final exponent is at 372,4–381,17 and the minus before 3n at
61,20–79,21. The USGS table reference is the reviewed Salient Statistics region already used at
36 DPI; every digit, label and rule is a component.

## Controls

`controls.py <corpus-evaluation-directory>` recomputes `controls.json` from the converted EPUBs.
Erasures are specified in reference coordinates and applied at the aligned position in the real
converted image, so they do not depend on where the converter placed its crop.

| Control | Coverage | Extra ink | Sharpness | Result |
| --- | ---: | ---: | ---: | --- |
| Wallace 343 solution line, current crop | 0.590 | 0.005 | 0.994 | pass |
| Wallace 347 exercise 35, current crop | 1.049 | 0.000 | 1.038 | pass |
| USGS Salient Statistics table, current crop | 0.693 | 0.000 | 1.000 | pass |
| 343 crop, 0.75 px Gaussian blur | 0.618 | 0.026 | 0.761 | pass |
| 343 crop, 1.5 px Gaussian blur | 0.588 | 0.072 | 0.488 | pass |
| 343 crop, resampled 180→150→180 DPI | 0.694 | 0.001 | 0.966 | pass |
| 343 crop, resampled 180→120→180 DPI | 0.725 | 0.005 | 0.911 | pass |
| 343 crop shifted by (3, 2) px | 0.590 | 0.005 | 0.994 | pass |
| 347 crop, 0.75 px blur / 1.5 px blur | 1.279 / 1.209 | 0.002 / 0.046 | 0.829 / 0.528 | pass |
| 347 crop, resampled 150 / 120 DPI | 1.273 / 1.326 | 0.000 | 0.961 / 0.905 | pass |
| **343: b² exponent erased** | 0.001 | 0.006 | 0.975 | fail |
| **343: fraction bar erased** | 0.000 | 0.000 | 1.041 | fail |
| **343: radical sign erased** (vinculum kept) | 0.000 | 0.006 | 0.975 | fail |
| **343: solution line erased; similar preceding line remains** | 0.000 | 0.304 | 0.803 | fail |
| **347: final exponent erased** | 0.003 | 0.000 | 1.038 | fail |
| **347: minus sign before 3n erased** | 0.064 | 0.000 | 1.038 | fail |
| **347: exercise 35 erased; other exercises remain** | 0.000 | 0.272 | 0.312 | fail |
| **343 reference against the page-347 exercise column** | 0.000 | 0.442 | 0.000 | fail |
| **343 crop, 4 px Gaussian blur** | 0.328 | 0.340 | 0.250 | fail |
| **all-black image** | 0.000 | 0.666 | 1.030 | fail |
| Limitation: 343 crop resampled 180→60→180 DPI | 0.657 | 0.073 | 0.574 | pass |
| Limitation: 347 crop resampled 180→60→180 DPI | 1.267 | 0.042 | 0.613 | pass |

The 36 DPI region check scores the erased-exponent control 0.959 (pass) and the erased-row control
0.439; the glyph check now fails both. Python unit tests (`tools/test_glyph_structure.py`) add
synthetic controls for offsets, mild blur, resampling, an erased exponent/bar/radical, a substituted
digit, extra ink inside and outside the window, blank/black images, heavy blur, component and tile
labelling, page-image selection, and contract validation (kind, resolution, page, thresholds).

Margins: the weakest correct unit is the page-343 fraction bar at 0.590 (Core Graphics renders the
hairline with about 60% of Poppler's ink mass; ordinary glyphs score 1.0–1.4); the strongest failing
erasure is 0.064. The 0.4 default sits between them with about 0.19 of margin on the positive side.

## Commands

```sh
python3 tools/render_region_reference.py --case wallace-algebra-2010 --page 343 --region 176,658,283,690 \
  --name our-solution-glyphs --kind glyph --target "..."
python3 tools/render_region_reference.py --case wallace-algebra-2010 --page 347 --region 80,625,245,645 \
  --name exercise-35-glyphs --kind glyph --target "..."
python3 tools/render_region_reference.py --case usgs-mcs2025-copper --page 1 --region 40,205,565,481 \
  --name salient-statistics-glyphs --kind glyph --target "..."
python3 tools/run_corpus_regressions.py --converter .build/release/pdf-reflow --epubcheck /opt/homebrew/bin/epubcheck \
  --output /tmp/corpus-base --case wallace-algebra-2010 --case usgs-mcs2025-copper ...
python3 measurements/equation-structure/controls.py /tmp/corpus-base
python3 tools/check_corpus_content.py --case wallace-algebra-2010 --evaluation /tmp/corpus-base/wallace-algebra-2010
```

## What the check proves and does not prove

It proves every reviewed stroke of the source region is present in some converted image on the
page with comparable ink mass, in the right place, and that no significant ink was added inside the
region. It does not prove glyph identity beyond ink shape and placement (a digit swapped for one
whose ink covers the same pixels within two pixels would pass), and it does not prove legibility:
an upsampled 60 DPI crop conserves ink mass and passes (0.657 / 1.267) although its sharpness
falls to 0.57–0.61. Sharpness cannot gate that case without also failing a σ=1.5 px blur
(0.49–0.53), so it is reported and left to `imageAppearance` scale checks and reviewer judgment.
References assume the library's 180 DPI raster; a different DPI fails alignment until they are
regenerated.

## Fidelity defect observed (resolved)

Wallace page 343, "Factor" line (x² + (b/a)x + b²/4a² = …): the converter emitted the leading
"x² +" as a standalone paragraph with a flattened exponent ("x2 +") while the preserved equation
image started at "(b/a)x". Observed in converter `56e70e2` output and filed as #46. Fixed by the
crop rule in [split-display-rows](../split-display-rows/record.md): the crop now takes the piece of
a display row its edge left outside, so the whole equation is one region. The page-343 glyph
reference is unaffected — it checks the "Our Solution" line, which was already inside a crop — and
its control scores above are unchanged.
