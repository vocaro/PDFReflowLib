# Monochrome images written gray (#216)

Tier: deterministic Apple PDF stack, macOS 27.0 arm64 (Darwin 27.0.0), release CLIs built from
`main` at `a9a097b6` plus the #216 verification commit `a7582213` (the baseline) and from this
change (the candidate), run one case at a time with `tools/run_corpus_regressions.py` on a machine
shared with other agents' work. 2026-09-25. Every EPUB was deleted as soon as its numbers were
read; no raster or book is committed.

## Why Warren stopped fitting

`a7582213` sends Warren pages 289, 291, 292, 301, 328, 339, 547 and 551 to required page images.
Converted with the budget lifted, the full report measures:

| Build | Entry bytes | Against the 512 MiB budget | Images |
| --- | ---: | --- | --- |
| `a9a097b6` | 536,707,447 | 163,465 bytes inside | 932, all JPEG |
| `a9a097b6` + `a7582213` | 537,384,617 | **513,705 bytes over** | 932: 931 JPEG, 1 PNG |

The eight pages were not new images: on `a9a097b6` each already carried a full-page reference.
Seven of the eight page images are byte-identical to the references they replace (same raster,
same JPEG 0.90). The whole cost is page 547: a required fallback is judged as a crop, the
classifier calls a crop of type on a ground `lineArt`, and the page's chroma share (ink on cream,
measured against the cream's hue) is over 2%, so its 417,819-byte JPEG became a 1,098,781-byte
PNG, +680,962 bytes. The book had only 163,465 bytes to spare before that; the #242 record's
628,685 had already been eaten by later changes. At 180 DPI and JPEG 0.90, 931 of Warren's 932
images were JPEG and averaged 573 KB.

## What the page offers

**Resolution.** The Internet Archive scans are mixed-raster: every page places a 167-ppi JPEG 2000
background, a 501-ppi JPEG 2000 foreground and a 501-ppi JBIG2 mask
(`pdfimages -list`, pages 285–295, 325–340 and 545–552). The text and handwriting are drawn at
501 ppi, so the 180-DPI render is already a reduction; there is no upscaling to avoid, and a lower
DPI is what #28 measured against (tiny notes recover 5 of 9 phrases at 180, 3 at 150).

**Colour.** The pages are black print, handwriting and halftone on yellowed paper. The paper's
modal colour is at lightness 203 or more with at most 51 levels of tint (red − blue), and always
red ≥ green ≥ blue, on every page but the black-grounded covers 1 and 920. Over each page, a pixel's hue (R − G, G − B) was
compared with the paper's hue scaled by the pixel's lightness over the paper's — the line from
black to the paper that ink on tinted stock follows. On all 920 pages rendered as the converter
renders them, 895 have no more than 0.1% of pixels 24 levels or more off that line and none 64
levels off; median page 0.001%, 99th percentile 0.2%. The 25 that fail hold real colour: the
colour cover (page 1), a yellow-green JPEG 2000 speck (page 219: one blob of 226 pixels at 139
levels), the coloured edge of a scan strip (pages 165 and 169), and similar. They keep their
colour.

Written gray, a Warren page loses only the paper's tint. The same rasters encode as:

| Warren page | RGB JPEG 0.90 (shipped) | Gray JPEG 0.90 | Gray PNG |
| ---: | ---: | ---: | ---: |
| 50 (prose) | 570,392 | 538,847 | 437,408 |
| 289 (cursive letter) | 380,581 | 352,098 | 344,173 |
| 547 (handwritten form) | 417,819 (PNG 1,098,781 as fallback) | 385,685 | 383,427 |
| 890 (small notes) | 617,323 | 581,995 | 463,928 |
| 141 (halftone photograph) | 336,060 | 313,951 | 519,792 |

For type and handwriting the lossless gray PNG is smaller than the lossy colour JPEG, because the
three channels of a nearly neutral scan are three copies of one picture. Only photographs stay
smaller as JPEG.

## The rule

Under `.automatic`, an image is written gray when its ground is paper and its hue lies on the
paper's tint line (thresholds and wording in `doc/behavior.md`, *PageRasterizer and
PageAssetWriter*). Two decisions came from corpus review of the first draft, which used one
24-level step and any ground:

- **The ground must be paper.** Our Flag's back cover is a flat (12, 32, 117) blue; every pixel
  is its ground, so every pixel lay on its own tint line and the page went gray. A ground now has
  to be neutral within 4 levels or light, warm and faint.
- **On a neutral ground the step is 8, not 24.** The Earthdata slides' slate-blue fill,
  (52, 73, 94) on (238, 238, 238) gray, sits 21 levels off gray and went gray at 24. A render's
  grays are exact and white paper has no tint to vary, so 8 levels is colour there; on yellowed
  paper the tint itself varies across a page by up to 21 levels at the 99th percentile, and the
  chroma test's 24 stays.

Lossy permission is unchanged. Page 547, a fallback, is still refused JPEG, and its gray PNG is
383,427 bytes. Recognition and the text-layer tests read the RGB raster as before.

## Legibility

Before/after crops at 1× and 3× nearest-neighbour were compared for Warren 289 and 301 (cursive),
547 (cursive on a ruled form), 890 (the tiny notes #28 reviewed) and 141 (halftone photograph),
from the same rasters. Every stroke, dot and serif is where it was. The handwriting and the notes
lose JPEG's ringing where the gray PNG is chosen; the photograph keeps the same JPEG quality in
one channel. The difference a reader sees is the ground: cream becomes light gray (lightness
about 229 on page 289). No glyph became harder to read. This is one reviewer at a desktop
display, not a reader study.

## Every corpus case

All 24 regression cases were run with the runner on both builds (Warren's baseline with the CLI
and the budget lifted, since the runner stops at the budget). Every case passes on the candidate:
`runPassed`, EPUBCheck, and `content-assessment.json` with no errors. Entry bytes:

| Case | Before | After | Change | Images | Newly gray |
| --- | ---: | ---: | ---: | ---: | ---: |
| gpo-warren-1964 | 537,384,617 | 390,047,922 | −27.4% | 932 | 906 |
| gpo-warren-1964-suspect-text-excerpt | 2,018,707 | 1,719,731 | −14.8% | 6 | 6 |
| cia-blue-book-14-1955 | 209,156,162 | 130,977,187 | −37.4% | 448 | 448 |
| faa-phak-8083-25c | 133,154,491 | 132,465,871 | −0.5% | 599 | 74 |
| wallace-algebra-2010 | 38,359,428 | 22,235,548 | −42.0% | 3,278 | 3,277 |
| gpo-911-2004 | 4,265,884 | 3,467,006 | −18.7% | 59 | 31 |
| fed-explained-2021 | 14,227,025 | 14,046,464 | −1.3% | 316 | 12 |
| dga-2025-2030 | 4,983,011 | 4,983,011 | 0 | 30 | 0 |
| noaa-nca5-2023 | 256,774,068 | 256,730,678 | −0.02% | 1,618 | 13 |
| gpo-our-flag-2003 | 7,231,499 | 7,207,142 | −0.3% | 146 | 4 |
| cdc-zombie-pandemic-2011 | 33,072,291 | 32,885,777 | −0.6% | 42 | 6 |
| census-rrs2002-01 | 3,264,626 | 1,867,459 | −42.8% | 35 | 35 |
| uscis-m618-arabic-2015 | 39,957,057 | 39,844,482 | −0.3% | 150 | 4 |
| irs-p596-zhs-2025 | 11,842,462 | 7,456,277 | −37.0% | 179 | 115 |
| nbs-jres-geltman-1977 | 4,421,320 | 3,819,460 | −13.6% | 8 | 8 |
| arxiv-replay-clocks-2023 | 1,223,698 | 980,500 | −19.9% | 66 | 47 |
| ntrs-20180003024-earthdata-slides-2018 | 2,900,445 | 2,900,445 | 0 | 44 | 0 |
| usda-ars-agresearch-2012-11 | 14,204,430 | 14,193,529 | −0.1% | 83 | 27 |
| ntrs-20210020887-techport-thm-2021 | 373,666 | 372,262 | −0.4% | 31 | 19 |
| tufs-hoshino-tategaki-2017 | 1,157,194 | 705,931 | −39.0% | 3 | 2 |
| openlogic-hindi-reader-2026 | 6,114,038 | 5,874,243 | −3.9% | 50 | 32 |
| ucl-hebrew-shakespeare-2017 | 9,436,305 | 9,344,659 | −1.0% | 487 | 480 |

`usgs-mcs2025-copper` and `scotus-loper-bright-2024` write no images and are unchanged. Every
image count and every pixel size is unchanged.

**Warren fits with 146,822,990 bytes (140.0 MiB, 27.3% of the budget) to spare**, against
513,705 bytes over before. 906 of its 932 images are gray: 768 gray PNG, 138 gray JPEG; the 26
that keep colour are the 25 pages above plus page 920's black back cover.

**What went gray outside Warren.** Each case was converted again with both builds (with the
manifest's flags) and every image the candidate wrote gray was paired with the baseline's:
4,640 images, 273.4 MB → 169.3 MB. 4,042 of them held no hue at all (every pixel R = G = B);
4,487 decode to exactly the lightness of the baseline's image, the rest having been or become
JPEG. Outside the Warren scans, the largest per-pixel saturation (max − min channel) of any image
written gray is 11 levels, on a 17 × 17 checkbox over off-white paper in TechPort; the rest are
at 7 or under (anti-aliasing through colour management on grayscale art). Blue Book's 448
images are one-bit scans rendered hue-free, Wallace's 3,277 are black equations; both lose
nothing.

## What this does not establish

* **Not a reader study,** and not a judgment that the paper's tint carries nothing: a reader who
  wants the yellowed-paper look loses it. Naming an encoding keeps RGB.
* **Thresholds are corpus-fitted:** the 24-level tinted step, the 8-level neutral step, the 0.1%
  share and the paper bounds come from Warren's 920 pages and the controls above. A colour
  fainter than 24 levels of hue on tinted paper is taken for the paper's own.
* **Not other encoders or OS builds.** Gray PNG and JPEG sizes are ImageIO's on this build.

## Files

None beyond this record. The probe (a PDFKit render matching `PageRasterizer.image`, then the
tint-line statistics and four encodings of the same raster), the corpus driver and the pairing
audit ran from a scratch directory; their outputs were deleted after the numbers above were read.
