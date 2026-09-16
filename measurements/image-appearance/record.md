# Image appearance checks: scale, ink contrast and color

Part of [#27](https://github.com/vocaro/PDFReflowLib/issues/27). Region correlation is normalized, so
it cannot see whether a preserved crop is emitted at a legible resolution, whether its ink is dark
enough to read, or whether a colored source (a state flag, a colored FAA illustration) kept its
hues. This record covers the `imageAppearance` contract type. macOS 27.0 (26A428), arm64; Python
3.14.6, numpy 2.4.6, Pillow 12.2.0, Poppler 26.04.0 (reference rendering only). Converter `56e70e2`.

## Method

`tools/render_region_reference.py --kind color` renders a reviewed region with Poppler at 180 DPI in
RGB, averages it to 36 DPI exactly like the grayscale region references, trims it by the same ink
box and writes an RGB PNG with a `kind: color` sidecar. An `imageAppearance` expectation may name a
color reference or an existing grayscale `region` reference; only a color reference enables the
color measure.

`tools/image_appearance.py` locates the reference's grayscale form in each converted image with the
36 DPI grid-phase search and measures, on the aligned window:

- **scale**: the converted image's pixel size relative to the reviewed region rendered at the
  library's 180 DPI (minimum over width and height); default minimum 0.95. A crop emitted smaller
  than its source region fails. This is the literal pixel-dimension check; it is not a sharpness
  measure (see Limits).
- **contrast**: (98th − 2nd percentile) of the window's gray values over 255; default minimum 0.4.
- **colorAgreement**: over reference samples with chroma (max − min channel) ≥ 48, the fraction
  whose converted sample keeps at least half the chroma and a hue within 30°; default minimum 0.8.
  A reference must have at least 16 colored samples or it is rejected as a color reference.

The page passes when some image meets every applicable threshold; metrics of the best-correlated
image are reported.

## References

| Reference | Region (points) | Pixels | Colored samples |
| --- | --- | --- | --- |
| `gpo-our-flag-2003/page-33-colorado-flag-color` | 224,160–373,255 | 74×47 RGB | 2,653 |
| `faa-phak-8083-25c/page-121-figure-5-36-color` | 35,550–275,697 | 120×73 RGB | 6,171 |
| `usgs-mcs2025-copper/page-1-salient-statistics` (existing grayscale) | 40,205–565,481 | 106×56 L | — |

Page 33 of Our Flag was rendered at 72 and 180 DPI and reviewed: the Colorado flag is blue-white-blue
horizontal stripes with a red C around a gold disc. Figure 5-36 (FAA page 121) is the climb-entry
illustration with a blue sky gradient, three yellow labels and aircraft silhouettes, already used as
a grayscale region reference. Poppler's CMYK/spot-color conversion differs from Core Graphics'
(pdftoppm warns about PANTONE spot colors on Our Flag), which is why the color measure compares hue
and chroma retention rather than RGB distance.

## Controls

`controls.py <corpus-evaluation-directory>` recomputes `controls.json` from the converted EPUBs.

| Control | Scale | Contrast | Color agreement | Result |
| --- | ---: | ---: | ---: | --- |
| Colorado flag, current page images | 0.990 | 0.696 | 0.994 | pass |
| FAA figure 5-36, current page images | 1.003 | 0.546 | 0.9998 | pass |
| USGS table (grayscale reference), current page images | 0.983 | 0.594 | — | pass |
| Colorado crop, 1.5 px Gaussian blur | 0.990 | 0.694 | 0.994 | pass |
| Colorado crop, JPEG quality 75 | 0.990 | 0.695 | 0.994 | pass |
| Figure 5-36 crop, 1.5 px Gaussian blur | 1.003 | 0.529 | 0.997 | pass |
| **Colorado crop converted to grayscale** | 0.990 | 0.696 | 0.000 | fail |
| **Colorado crop, red and blue channels swapped** | 0.990 | 0.695 | 0.004 | fail |
| **Colorado crop compressed to gray levels 96–160** | 0.990 | 0.183 | 0.000 | fail |
| **Colorado crop downscaled to half size** | 0.497 | 0.694 | 0.091 | fail |
| **Colorado crop downscaled to 80 percent** | 0.792 | 0.694 | 0.356 | fail |
| **Figure 5-36 crop converted to grayscale** | 1.003 | 0.546 | 0.000 | fail |
| **Figure 5-36 crop, red and blue channels swapped** | 1.003 | 0.582 | 0.103 | fail |
| **Figure 5-36 crop compressed to gray levels 96–160** | 1.003 | 0.134 | 0.000 | fail |
| **USGS table crop compressed to gray levels 96–160** | 0.983 | 0.150 | — | fail |
| **USGS table crop downscaled to half size** | 0.491 | 0.371 | — | fail |
| **Colorado reference against the figure 5-36 crop** | 1.558 | 0.537 | 0.163 | fail |

Contrast percentiles were chosen after measuring: with the 5th/95th percentiles the pale FAA
illustration scored 0.483, below a 0.5 gate, while the 2nd/98th percentiles give 0.546 for the
figure and 0.12–0.18 for every compressed control; the 0.4 default leaves 0.13 of margin below the
weakest correct crop and 0.22 above the strongest failing one. Python unit tests
(`tools/test_image_appearance.py`) add a synthetic tricolour flag with offset, blur and JPEG
positives; grayscale, hue-swap, low-contrast and downscaled negatives; a grayscale-reference case
that checks scale and contrast only; hue arithmetic; reference validation (mode, kind, resolution,
region points, thresholds, page-image selection).

## Commands

```sh
python3 tools/render_region_reference.py --case gpo-our-flag-2003 --page 33 --region 224,160,373,255 \
  --name colorado-flag-color --kind color --target "..."
python3 tools/render_region_reference.py --case faa-phak-8083-25c --page 121 --region 35,550,275,697 \
  --name figure-5-36-color --kind color --target "..."
python3 measurements/image-appearance/controls.py /tmp/corpus-base
python3 tools/check_corpus_content.py --case gpo-our-flag-2003 --evaluation /tmp/corpus-base/gpo-our-flag-2003
```

## What the checks prove and do not prove

Scale proves the crop was not emitted below the source region's size at 180 DPI; it does not prove
sharpness, so a crop rendered at low resolution and upsampled to the nominal size passes scale (the
glyph-structure record measures that case). Contrast proves the aligned window spans most of the
gray range; it says nothing about which pixels are dark. Color agreement proves the colored parts of
the reviewed region keep their hue family and most of their saturation; it tolerates the CMYK
conversion differences between Poppler and Core Graphics and therefore cannot detect small color
casts. Only the Colorado flag and figure 5-36 are color-checked; the other flags, FAA figures and
Fed diagrams are not.
