# Can the converter choose PNG or JPEG per image?

Tier: deterministic Apple PDF stack, macOS 27.0 arm64 (Darwin 27.0.0), release CLI built from
this worktree at `88803ac` plus this measurement directory, `--execution-context host-terminal`.
Date 2026-09-17. English corpus only; the Arabic USCIS guide and the Chinese IRS publication are
out of scope, and Loper Bright emits no images. The machine was shared with other agents, so the
seconds below are single observations. **Nothing in `Sources/` was changed. The default was not
changed.** No PDF or EPUB is committed.

**Result.** A content-aware default is worth having, and the rule that earns its keep is not the
one the question assumes. The damage JPEG does at 0.85–0.95 on this encoder is not ringing from
the quality setting: it is **chroma subsampling**, which ImageIO turns on at every quality below
1.00 and which the quality knob does not control. So the classifier's real job is to find the
images that carry **fine coloured detail** — coloured labels on diagrams, chart keys, seal
lettering — and keep those lossless. Everything else, including 890 scanned text pages, takes
JPEG without a visible defect.

Proposed default, measured over 6,076 images from 20 documents: **−44.1% against PNG
everywhere**, within **12.5%** of what `smallest:0.9` achieves, while sending 1,528 images to
JPEG instead of 2,234 and cutting the images that take a worst-case edge error of 30 levels or
more from 337 to 56.

**The Warren answer is no.** A content-aware rule that keeps text pages lossless leaves Warren
**517,922,441 bytes** (494.0 MiB) over the 512 MiB default — 853 of its 932 images *are* text
pages and they are 93% of the book's bytes. Warren fits only when every image is lossy. It does then
fit, which is new: **300,007 bytes of headroom**, verified by a real conversion.

## How the measurement works

`survey.py` converts one document with library defaults except `--maximum-output-bytes unlimited
--maximum-epub-bytes unlimited`, so the whole book's images are emitted and countable, and PNG
stays the encoding, so the PNG column is the bytes the converter actually wrote. It then, per
image:

* reads the raster and computes the features in `classifier.py` — all of them are available to
  `PageRasterizer` from the `CGImage` it already holds;
* takes page-level PDF-side evidence from Poppler (`pdftotext` for native text, `pdfimages
  -list` for the page's image XObjects and their filters). In the library both are already at
  hand: the extractor's text layer answers the first and the page's resource dictionary the
  second;
* re-encodes as JPEG at 0.95, 0.90 and 0.85 with `reencode`, a compiled ImageIO call identical
  to `PageRasterizer.write`, so both byte columns come from the converter's own encoders and
  not from Pillow, whose quality scale is different;
* measures the JPEG against the PNG: PSNR over the whole image, and a worst case concentrated
  on edges — the largest mean absolute error over any 8×8 block that contains a step edge
  (gradient ≥ 48, dilated), plus the 99.9th percentile and maximum error on edge pixels.

The EPUB is deleted as soon as its PNGs are extracted, and the whole scratch tree is deleted in
a `finally`. `analyse.py` recomputes the classification from the stored features, so the rule
can be argued about without reconverting anything; `measurements/image-encoding/rows.jsonl.gz`
holds all 6,076 rows and `analysis.md` the generated tables.

Free space was checked before every conversion (`run-survey.sh` refuses under 8 GiB) and never
fell below 25.7 GiB. NOAA and Warren were run last and singly.

## The classification

Seven classes. The first three are what the owner asked for; the text pages split because what
a scan is made of, not what it depicts, decides whether PNG can compress it.

| Class | What it is | Evidence the rule reads |
| --- | --- | --- |
| `photograph` | captured tone | almost nothing flat, ramps everywhere, no ground to speak of; or ramp-dominated over a JPEG/JPX XObject |
| `continuous-tone art` | painted or shaded artwork | washes and gradients, but flat fields and hard outlines survive |
| `line art or chart` | drawn matter, including cropped tables and equations | ≤ 4,096 colours on flat fields, or step edges on a flat ground |
| `text page (bilevel scan)` | a fax-like scan of a printed page | a page of type on one ground, and only ever ground or ink |
| `text page (tonal scan)` | a photograph of a page: tinted paper, halftone | a page of type on one ground, with everything in between |
| `text page (born-digital)` | drawn type the converter still rasterized | a page of type, and the page has no image XObject |
| `mixed` | neither type on paper nor captured tone | the residue |

Two features earn their place and are worth naming, because the obvious versions of them are
wrong:

* **`backgroundShare`, not `whiteShare`.** A page of type is mostly its paper, and the paper is
  white only sometimes. The NBS journal scans are grey (`whiteShare` 0.01) and the Warren scans
  are yellowed. The feature is the share of pixels within 10 levels of the image's *modal*
  colour.
* **`chromaShare` measured against the page's own ground, not against grey.** Warren's paper is
  (237, 228, 208): every pixel of all 853 scanned pages has a channel spread over 24, so an
  absolute test calls the whole book "coloured" and refuses it lossy encoding. Measuring hue
  against the ground's hue puts those pages at `chromaShare` ≈ 0.00 where they belong.

`text page` is a whole-page class: a region crop that is nothing but type is reported as line
art, because it is drawn matter and takes the same encoding.

What the corpus emits, by class:

| | Full-page references and fallbacks | Region crops |
| --- | ---: | ---: |
| `line art or chart` | 16 | 4,079 |
| `text page (tonal scan)` | 890 | — |
| `text page (bilevel scan)` | 305 | — |
| `text page (born-digital)` | 21 | — |
| `mixed` | 87 | 311 |
| `photograph` | 67 | 162 |
| `continuous-tone art` | 11 | 127 |
| **total** | **1,397** (1,637.24 MiB of PNG) | **4,679** (568.13 MiB of PNG) |

## What the quality setting actually does

Before any per-class table is worth reading: on this encoder the three qualities the task names
are nearly the same encoder.

`chroma-subsampling.py`, three documents, every image each:

| Document | Quality | Luma sampling | Chroma sampling | Luma quant [0:3] | Chroma quant [0:3] | JPEG of PNG median | PSNR median | Worst edge-block MAE median / worst |
| --- | --- | --- | --- | --- | --- | ---: | ---: | --- |
| DGA (37) | 1.00 | 1x1 | 1x1 | [1, 1, 1] | [1, 1, 1] | 96% | 51.0 dB | 1.5 / 1.6 |
| | 0.95 | 2x2 | 1x1 | [1, 1, 1] | [1, 1, 2] | 38% | 41.4 dB | 19.2 / 23.9 |
| | 0.90 | 2x2 | 1x1 | [1, 1, 1] | [1, 1, 2] | 36% | 41.2 dB | 18.9 / 24.1 |
| | 0.85 | 2x2 | 1x1 | [1, 1, 1] | [2, 2, 3] | 34% | 41.0 dB | 19.7 / 24.4 |
| Our Flag (123) | 1.00 | 1x1 | 1x1 | [1, 1, 1] | [1, 1, 1] | 111% | 51.4 dB | 1.5 / 1.6 |
| | 0.95 | 2x2 | 1x1 | [1, 1, 1] | [1, 1, 2] | 40% | 39.1 dB | 9.8 / 47.8 |
| | 0.90 | 2x2 | 1x1 | [1, 1, 1] | [1, 1, 2] | 39% | 39.0 dB | 9.8 / 47.4 |
| | 0.85 | 2x2 | 1x1 | [1, 1, 1] | [2, 2, 3] | 37% | 38.8 dB | 10.2 / 47.6 |
| FAA PHAK (567) | 1.00 | 1x1 | 1x1 | [1, 1, 1] | [1, 1, 1] | 148% | 50.6 dB | 1.6 / 2.0 |
| | 0.95 | 2x2 | 1x1 | [1, 1, 1] | [1, 1, 2] | 62% | 37.3 dB | 29.4 / 101.7 |
| | 0.90 | 2x2 | 1x1 | [1, 1, 1] | [1, 1, 2] | 59% | 37.2 dB | 29.6 / 102.2 |
| | 0.85 | 2x2 | 1x1 | [1, 1, 1] | [2, 2, 3] | 56% | 37.0 dB | 29.9 / 101.6 |

At 1.00 ImageIO writes 4:4:4 and a quantisation table of ones: near-lossless, and 96% to 148% of
the PNG, which is no use. At anything below 1.00 it halves both chroma planes, and the luma
table does not move at all between 0.95 and 0.90. **Almost the entire error between PNG and
JPEG at these settings is chroma error, and it is the same error at 0.95, 0.90 and 0.85.**

That is why dropping from 0.95 to 0.85 buys 4 percentage points of size and costs 0.4 dB: the
knob is turning something that is not the problem. It is also why the per-class fidelity tables
below barely move across the three qualities.

The consequence for a classifier: the question to ask an image is not "does it have sharp
edges" but "does it have sharp edges **in colour**".

| `chromaShare` | Images | With a worst 8×8 edge-block error ≥ 30 levels at 0.90 | Median worst edge-block error |
| --- | ---: | ---: | ---: |
| 0.00–0.02 | 4,286 | 20 (0%) | 1.3 |
| 0.02–0.10 | 357 | 73 (20%) | 19.9 |
| 0.10–0.30 | 714 | 147 (21%) | 16.5 |
| 0.30–1.00 | 719 | 186 (26%) | 18.4 |

An image with no chroma to lose is undamaged whatever it depicts. This is the single strongest
result in the survey and it is what the proposed rule is built on.

## Per class: what JPEG costs and what it saves

### Full-page references and fallbacks

| Class | Images | PNG MiB | JPEG 0.95 | JPEG 0.90 | JPEG 0.85 | median 0.90 of PNG | worst 0.90 of PNG |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| text page (tonal scan) | 890 | 1011.84 | 542.87 | 515.07 | 495.47 | 52% | 186% |
| photograph | 67 | 257.20 | 72.58 | 68.18 | 65.09 | 26% | 35% |
| text page (bilevel scan) | 305 | 173.60 | 199.62 | 190.40 | 186.49 | **109%** | 148% |
| mixed | 87 | 146.95 | 39.04 | 36.84 | 35.04 | 23% | 49% |
| continuous-tone art | 11 | 31.99 | 9.22 | 8.67 | 8.26 | 26% | 36% |
| line art or chart | 16 | 9.66 | 4.20 | 4.00 | 3.83 | 50% | 117% |
| text page (born-digital) | 21 | 6.00 | 10.48 | 9.99 | 9.77 | **168%** | 189% |

| Class | Quality | PSNR median / worst | Worst edge-block MAE median / worst | Edge p99.9 median / worst |
| --- | --- | --- | --- | --- |
| text page (tonal scan) | 0.95 | 44.1 / 37.9 dB | 6.5 / 31.2 | 12 / 65 |
| | 0.90 | 43.5 / 37.8 dB | 6.8 / 30.9 | 13 / 65 |
| | 0.85 | 42.8 / 37.7 dB | 7.2 / 31.3 | 13 / 66 |
| text page (bilevel scan) | 0.95 | 52.5 / 49.3 dB | 1.3 / 1.6 | 5 / 5 |
| | 0.90 | 51.2 / 48.0 dB | 1.5 / 1.9 | 6 / 6 |
| | 0.85 | 50.0 / 46.8 dB | 1.8 / 2.1 | 6 / 7 |
| text page (born-digital) | 0.90 | 52.9 / 47.8 dB | 1.4 / 25.4 | 6 / 39 |
| mixed | 0.95 | 47.3 / 34.8 dB | 6.3 / 41.7 | 15 / 84 |
| | 0.90 | 46.7 / 34.7 dB | 6.6 / 41.6 | 15 / 85 |
| | 0.85 | 46.0 / 34.6 dB | 6.9 / 42.4 | 16 / 85 |
| photograph | 0.90 | 43.3 / 30.9 dB | 17.4 / 51.3 | 28 / 112 |
| continuous-tone art | 0.90 | 42.1 / 32.7 dB | 25.9 / 51.8 | 41 / 90 |
| line art or chart | 0.90 | 50.4 / 36.6 dB | 6.0 / 36.2 | 16 / 76 |

### Region crops

| Class | Images | PNG MiB | JPEG 0.95 | JPEG 0.90 | JPEG 0.85 | median 0.90 of PNG | worst 0.90 of PNG |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| line art or chart | 4,079 | 247.30 | 246.93 | 235.27 | 227.92 | **143%** | 1378% |
| mixed | 311 | 126.84 | 51.15 | 48.41 | 46.06 | 37% | 212% |
| photograph | 162 | 121.05 | 35.42 | 33.29 | 31.65 | 27% | 51% |
| continuous-tone art | 127 | 72.94 | 27.15 | 25.61 | 24.45 | 32% | 220% |

| Class | Quality | PSNR median / worst | Worst edge-block MAE median / worst | Edge p99.9 median / worst |
| --- | --- | --- | --- | --- |
| line art or chart | 0.95 | 50.2 / 26.9 dB | 1.1 / 70.2 | 5 / 169 |
| | 0.90 | 48.9 / 26.9 dB | 1.3 / 70.1 | 6 / 169 |
| | 0.85 | 47.7 / 26.9 dB | 1.5 / 70.6 | 7 / 169 |
| mixed | 0.95 | 38.2 / 23.2 dB | 23.1 / 101.7 | 47 / 184 |
| | 0.90 | 38.1 / 23.2 dB | **23.2 / 102.2** | 47 / 184 |
| | 0.85 | 37.8 / 23.2 dB | 23.2 / 101.6 | 47 / 184 |
| photograph | 0.90 | 40.9 / 27.8 dB | 12.4 / 53.6 | 26 / 93 |
| continuous-tone art | 0.90 | 39.8 / 24.9 dB | 16.8 / 96.5 | 35 / 138 |

Read together:

* **Line art, bilevel scans and born-digital text pages are bigger as JPEG.** 4,079 region
  crops at a median 143% of their PNG, 305 scanned Blue Book pages at 109%, 21 rasterized
  born-digital pages at 168%. There is no size argument for lossy here at all, and the worst
  case in the corpus (1378%) is a small chart crop that PNG stores in a few KB.
* **Photographs and continuous-tone art are a quarter to a third of their PNG**, on both full
  pages and crops, with median PSNR 40–43 dB.
* **Tonal scans are about half**, at 43.5 dB, and are the largest single pile of bytes in the
  corpus — 1,011.84 MiB over 890 pages, almost all of it Warren.
* **`mixed` region crops are the most damaged content in the corpus**: 23.2 levels of median
  worst-block error and 102.2 at worst. These are the FAA's cropped diagrams with saturated
  labels. `mixed` full pages, at 6.6 / 41.6, are a different animal — a whole illustrated page
  whose type is large.

The bilevel/tonal split is the right one for bytes, and the feature that carries it is not
perfect:

| `bilevelShare` | Full-page scans | median JPEG 0.90 of PNG |
| --- | ---: | ---: |
| 0.4–0.5 | 8 | 110% |
| 0.5–0.6 | 11 | 29% |
| 0.6–0.7 | 2 | 27% |
| 0.7–0.8 | 5 | 29% |
| 0.8–0.9 | 11 | 29% |
| 0.9–1.0 | 1,158 | 54% |

The 0.9–1.0 bucket holds both families — Blue Book's fax scans and Warren's tinted ones — and
`distinctColours` separates them (256 against 20,000–40,000). The seven NBS journal pages sit
on the wrong side of that line: they are grey-background halftone scans that `bilevelShare`
calls two-tone, and JPEG is in fact 71% of their PNG. The proposed rule recovers them anyway,
because they are neutral (see below), not because the class is right.

## The proposed default

Two questions, answered separately, because neither answers the other:

1. **Is lossy safe here?** `classifier.lossy_is_safe` says yes when the image has no chroma to
   lose (`chromaShare` < 0.02), or its content is tonal (photograph, continuous-tone art, tonal
   scan), or it is a full-page `mixed` reference. It says no to coloured line art, coloured
   charts and `mixed` *crops*.
2. **Is lossy smaller here?** `smallest` semantics: encode both, keep the smaller. Nothing else
   predicts this reliably — JPEG is larger on 4,079 line-art crops and smaller on the scans.

`mixed` is admitted for pages and refused for crops because of what they are for. A full-page
reference is a picture of a page the reader already has reflowed beside it; a region crop is
often the only copy of a figure, and the crops that ring are exactly the cropped diagrams with
saturated labels.

### What it costs and saves, per document

| Document | Images | PNG MiB | proposed MiB | vs PNG | vs `smallest:0.9` |
| --- | ---: | ---: | ---: | ---: | ---: |
| arxiv-replay-clocks-2023 | 34 | 0.90 | 0.90 | +0.0% | +1.4% |
| cdc-zombie-pandemic-2011 | 42 | 124.38 | 31.50 | −74.7% | +0.0% |
| census-rrs2002-01 | 51 | 5.31 | 5.31 | +0.0% | +0.0% |
| cia-blue-book-14-1955 | 424 | 188.71 | 186.23 | −1.3% | +0.0% |
| dga-2025-2030 | 37 | 4.61 | 1.82 | −60.5% | +16.0% |
| faa-phak-8083-25c | 567 | 205.51 | 121.27 | −41.0% | +43.7% |
| fed-explained-2021 | 57 | 26.72 | 11.93 | −55.4% | +9.8% |
| gpo-911-2004 | 50 | 5.45 | 2.96 | −45.6% | +0.0% |
| gpo-our-flag-2003 | 123 | 10.97 | 6.58 | −40.1% | +84.9% |
| gpo-warren-1964 | 932 | 1059.90 | 508.92 | −52.0% | +0.0% |
| nbs-jres-geltman-1977 | 42 | 6.52 | 4.65 | −28.6% | +0.0% |
| noaa-nca5-2023 | 1,548 | 480.19 | 282.96 | −41.1% | +46.8% |
| ntrs-20180003024-earthdata-slides-2018 | 22 | 3.02 | 2.80 | −7.4% | +7.2% |
| ntrs-20190030725-dasc-2019 | 28 | 0.86 | 0.86 | +0.0% | +0.0% |
| ntrs-20200002975-gwl-2020 | 31 | 5.88 | 4.28 | −27.3% | +36.3% |
| ntrs-20210020887-techport-thm-2021 | 37 | 0.99 | 0.98 | −0.3% | +17.4% |
| uscourts-pro-se-1-2016 | 21 | 0.01 | 0.01 | +0.0% | +0.0% |
| usda-ars-agresearch-2012-11 | 52 | 36.53 | 20.66 | −43.5% | +24.5% |
| usgs-mcs2025-copper | 3 | 0.33 | 0.33 | +0.0% | +0.0% |
| wallace-algebra-2010 | 1,975 | 38.59 | 38.59 | −0.0% | +0.0% |
| **all 20** | **6,076** | **2205.37** | **1233.54** | **−44.1%** | **+12.5%** |
| **19 without Warren** | **5,144** | **1145.47** | **724.62** | **−36.7%** | **+23.3%** |

Nine documents move by under 8%: they emit mostly line art, tables, equations and
born-digital text, and PNG is already the right answer for all of it. Wallace's 1,975 equation
and figure crops move by −0.0%. The savings are concentrated where the pictures are: the CDC
comic −74.7%, the DGA −60.5%, the Fed −55.4%, Warren −52.0%, NOAA −41.1%, the FAA handbook
−41.0%.

### What it costs in fidelity

| Policy | Images sent to JPEG | With a worst edge-block error ≥ 30 levels | Worst in the corpus |
| --- | ---: | ---: | ---: |
| `png` | 0 | 0 | — |
| `smallest:0.9` | 2,234 | 337 (15% of them) | 102.2 |
| proposed | 1,528 | 56 (3.7% of them) | 96.5 |

The 56 that remain are the honest cost of the rule, and they are of two kinds. Most are real
photographs and paintings where a 30–50 level difference sits on a genuine high-contrast
boundary and is invisible — the metric is measuring where JPEG differs most, not where it looks
wrong. A minority are genuine misses: FAA figure crops that are an illustration *with*
saturated annotation, which the class calls continuous-tone art because the illustration
dominates the pixels. The worst image in the corpus under the proposed rule, FAA page 67 at 96.5
levels, is one of these.

## Which classes lose visible quality, judged on crops

`measurements/image-encoding/crops/` holds eleven worst-case comparisons: the four 256-pixel tiles
`survey.py` wrote (PNG, 0.95, 0.90, 0.85) centred on the image's worst 8×8 edge block, above the
middle 64×64 of the same four tiles at 4×. Each has a `.txt` beside it naming the document,
page, class, the worst-block error and the two byte counts. Red rules separate the tiles.

Rights: the two NASA insignia decks, the two NASA papers, the ARS magazine and the Pro Se form
commit no rasters from any page (doc/corpus.md), so `run-survey.sh` never writes a strip for
them and none can appear here. They are measured like every other book; only their pictures are
withheld.

What the crops show:

* **`line art or chart` in colour loses visibly, and identically at all three qualities.**
  `faa-phak-8083-25c-mixed` is the documented coloured-label case: red "Aftflap" and pink
  "Midflap" on a dark blue block. In PNG the letterforms are clean; in all three JPEGs they are
  muddy, and 0.95 is no better than 0.85. `noaa-nca5-2023-line-art-or-chart` (the back cover of
  agency seals) loses the white "STATES OF" lettering inside the seal's blue ring the same way.
  `gpo-our-flag-2003-line-art-or-chart` and `fed-explained-2021-line-art-or-chart` are the same
  effect on smaller type.
* **`continuous-tone art` with saturated annotation loses visibly.**
  `faa-phak-8083-25c-continuous-tone-art` is the worst image in the corpus under the proposed
  rule: an attitude indicator whose yellow aircraft symbol and white pitch marks on blue pick up
  a green-olive fringe and lose their edges in every JPEG panel.
* **`text page (tonal scan)` does not lose visibly.**
  `gpo-warren-1964-text-page-tonal-scan` is the worst Warren page at 4×: the glyph edges soften
  by a level or two and the letterforms are intact, with no halo. The ink is neutral, so there
  is no chroma to subsample. This is the finding the Warren arithmetic rests on.
* **`text page (bilevel scan)` does not lose visibly**, and does not save either —
  `cia-blue-book-14-1955-text-page-bilevel-scan` is indistinguishable across all four panels
  while the JPEG is 9% larger.
* **`photograph` does not lose visibly.** `noaa-nca5-2023-photograph` carries a worst-block
  error of 51.3 levels at a hard specular boundary and looks the same in all four panels, which
  is the clearest illustration of why the metric alone must not be read as a verdict.
* **`mixed` full pages sit in between.** `cdc-zombie-pandemic-2011-mixed` is painted comic art
  with lettered speech balloons; the lettering is black on white and survives.

At every one of these, 0.95, 0.90 and 0.85 are visually the same picture. There is no quality in
the 0.85–0.95 band that rescues coloured line art and none that is needed for scans.

## The Warren question, answered

Warren converts to 932 images and 1,114,309,483 uncompressed entry bytes under library defaults
— 2.08× the 512 MiB budget, matching the [opaque-raster record](../opaque-page-rasters/record.md)
to within the `dc:identifier` the writer randomises. 853 of its 932 images are full-page tonal
scans (985.70 MiB of PNG); 2,927,879 bytes of the book are not images.

| Policy | Entry bytes | Headroom under 512 MiB |
| --- | ---: | ---: |
| `png` (today's default) | 1,114,309,483 | −577,438,571 |
| **content-aware, text pages lossless** | **1,054,793,353** | **−517,922,441** |
| content-aware, tonal classes only | 1,109,976,638 | −573,105,726 |
| content-aware, tonal + mixed + tonal scans, line art lossless | 541,207,428 | −4,336,516 |
| **proposed rule** | **536,570,905** | **+300,007** |
| `smallest:0.9`, full pages and regions | 536,570,905 | +300,007 |

**Keeping text pages lossless leaves Warren 517,922,441 bytes — 494.0 MiB — over.** That is not
a near miss and no tuning closes it: text pages are the book. The question's premise does not
survive contact with this document.

What does fit is the proposed rule, and only because Warren's remaining lossless candidates are
neutral: its ~20 line-art images have `chromaShare` under 0.02, so `lossy_is_safe` admits them
and `smallest` takes the JPEG. Keep even those twenty lossless — the "line art lossless" row
above — and the book is **4,336,516 bytes over**. Warren's fit is decided by about twenty small
images.

**Verified, not projected.** A real conversion with `--full-page-image-encoding smallest:0.9
--region-image-encoding smallest:0.9` and the **default 512 MiB budget** exited 0 and wrote 932
assets, every one of them JPEG — the same image count as the unlimited PNG run of the same
book: **536,560,653 entry bytes, 310,259 bytes of
headroom (0.058%)**, 531,833,226 bytes of final EPUB, 6 min 35 s. The survey's projection for
the same policy was 536,570,905 / +300,007 — 10,252 bytes apart, which is the package
identifier and modification date.

This is a different result from the one on the opaque-raster record, which had Warren 349,408
bytes over with `smallest:0.9`. The difference is the region encoding: that run left
`--region-image-encoding` at its PNG default, and Warren's 22 crops cost about 650 KB more as
PNG than as JPEG. Setting both makes the book fit.

**It fits by 0.058%.** That is a pass on one machine with one encoder build, not a budget. Any
change that adds a few hundred KB of image bytes puts Warren back over, and the gate is what
would report it.

### NOAA, for contrast

| Policy | Entry bytes | Headroom under 512 MiB |
| --- | ---: | ---: |
| `png` (today's default) | 510,379,696 | +26,491,216 |
| proposed rule | 303,567,498 | **+233,303,414** |
| `smallest:0.9` | 208,937,964 | +327,932,948 |

NOAA passes today with 4.9% of the budget to spare, which the opaque-raster record called "a
pass, not a comfortable one". The proposed rule turns that into 43.5%. That headroom, not the
44% corpus saving, is the strongest practical argument for changing the default.

## A recommendation the owner can accept or refuse

**Full pages: `.smallest(jpegQuality: 0.90)`, gated by the classifier.** Lossy where
`lossy_is_safe` allows it — photographs, continuous-tone art, tonal scans, mixed pages and
anything neutral — and PNG otherwise. Full-page rasters are where the bytes are (1,637 of 2,205
MiB) and where lossy is safest, because the page's text is also reflowed beside the picture.

**Regions: `.smallest(jpegQuality: 0.90)`, gated by the same classifier with `mixed` refused.**
4,079 of 4,679 crops are line art that PNG stores more compactly anyway, so the region default
barely moves; what the gate buys is refusing JPEG on the 311 mixed crops that are the worst
content in the corpus.

**Quality 0.90, not 0.95.** 0.95 costs 3–4% more bytes and buys 0.5 dB, because the damage is
chroma subsampling and both qualities subsample identically. If a future release wants a
lossless-looking JPEG it must ask for 1.00, which is 96–148% of PNG and therefore pointless.

**Do not adopt bare `smallest:0.9` as the default.** It reaches only 12.5% further on bytes and
it picks JPEG for 337 images with a worst-case edge error of 30 levels or more, including every
coloured-label diagram in the FAA handbook. `smallest` chooses by bytes and cannot see a
ringing label; that is exactly the gap the classifier fills.

**Keep Warren excluded, or admit it knowing what it costs.** It now fits, by 0.058%, but only
under a policy that encodes every image lossily — including its twenty line-art images. Whether
a 0.058% pass is a pass is a policy decision for #5, not a measurement.

A conservative alternative, if the owner would rather not move a default on one corpus: ship the
classifier behind a new `ImageEncoding` case (`.automatic(jpegQuality:)`) and leave `.png` as
the default until it has run in a release. Every number above is a projection of what that case
would do, and the Warren line is a verified conversion.

## What a classifier in `PageRasterizer` would need

`PageRasterizer.encode` today takes a `CGImage` and an `ImageEncoding` and knows nothing else.
The classifier needs two things it does not have.

**From the raster, which it already holds.** Everything in `classifier.features` is one pass
over the pixels: the modal colour and the share within 10 levels of it, the share whose hue
differs from that ground's hue by 24 or more, the distinct-colour count, the zero-gradient
share, and the hard/soft edge shares. On a 3-megapixel page raster that is a few tens of
milliseconds of arithmetic against an encode measured in hundreds. It would want a
`CGImage`-backed implementation (`CGBitmapContext` or Accelerate), not a per-pixel loop, and it
can be computed on a strided sample — the survey used every pixel, and nothing here needs that
precision.

**From the page, which its caller holds.** Two page-level facts:

* whether the page's type is *drawn* or *scanned* — the survey approximated this with "does the
  page have any image XObject", and the library has better: the image-backed-page signal the
  extractor already computes, the one `unverifiedTextLayer` and `TextLayerPlausibility` are
  built on;
* whether the image being encoded is a **full-page reference or fallback** or a **region crop**,
  because `mixed` is admitted for one and refused for the other. The caller knows this; the
  rasterizer does not.

So the shape is: **the classifier does not belong inside `PageRasterizer.encode`.** It belongs
in the caller that already knows what it is asking for and what page it came from, as a function
from (raster, page evidence, image role) to an `ImageEncoding`, which is then passed to the
existing `encode`. `encode` keeps its present contract; `.smallest` already implements "encode
both, keep the smaller", which is the second half of the rule, and needs no change at all.

Two things to decide before porting:

* **Thresholds are corpus-fitted.** `chromaShare` < 0.02, `bilevelShare` ≥ 0.95,
  `distinctColours` ≤ 4,096, `softEdgeShare` < 0.15 and the rest were set by looking at these
  20 documents. The 0.02 chroma threshold is the one with a real margin behind it (0% damage
  below, 20% above, over 4,286 images); the others are ordinary fitted constants and a document
  outside this corpus can fall the wrong side of any of them.
* **Misclassification is one-sided in cost.** Calling a photograph line art costs bytes; calling
  a coloured diagram continuous-tone costs a visibly damaged figure. If the rule is ported it
  should be biased toward PNG, and the thresholds above already are — `lossy_is_safe` refuses
  4,548 of 6,076 images.

## What this does not establish

* **Not a reader study.** "Visible" here means a human reading four tiles at 1× and 4× on a
  desktop display, on eleven crops chosen as each document's worst case per class. It is not a
  controlled comparison and it is not a judgement at a phone's pixel density.
* **Not a recognition claim.** OCR reads the in-memory raster before encoding, so no number here
  can move it. Nothing in this survey re-ran Vision.
* **Not a device budget.** Every figure is a Mac release CLI process; the memory ceilings the
  corpus gates use were not measured and are not affected.
* **Not the final ZIP.** Every byte count except the two verified Warren figures is uncompressed
  entry bytes, which is what the `maximumOutputBytes` budget counts, and the projections say
  nothing about `maximumEPUBBytes`. The ZIP saves little on any image-heavy book already —
  measured EPUB-to-entry ratios run 0.934 to 0.999 across the 20 PNG conversions, and 0.68 only
  on the one book with almost no images — and Warren's verified JPEG run wrote 536,560,653 entry
  bytes into a 531,833,226-byte file, a ratio of 0.991 against its PNG run's 0.999.
* **Not other encoders.** The chroma-subsampling behaviour is ImageIO's on this macOS build. A
  different OS version could pick different sampling factors and the whole shape of the
  recommendation would have to be re-measured.
* **Not the excluded documents' pictures.** The six rights-restricted cases contribute every
  number in the tables and no crop.

## Files

| File | What it is |
| --- | --- |
| `classifier.py` | the feature set and the classification rule, with `lossy_is_safe` and `encode_as_jpeg` |
| `survey.py` | converts one document and measures every image it emits; writes crops |
| `reencode.swift` | the ImageIO JPEG encoder the survey calls, identical to `PageRasterizer.write` |
| `run-survey.sh` | drives the English corpus one document at a time, with the free-space check and the rights list |
| `chroma-subsampling.py` | the 1.00-against-0.95 experiment |
| `analyse.py` | per-class and per-document tables from the stored rows |
| `curate-crops.py` | assembles the committed crops from the strips `survey.py` wrote |
| `analysis.md` | the generated tables in full |
| `rows.jsonl.gz` | all 6,076 measured images: class, features, bytes, fidelity |
| `conversions.json` | each document's conversion report, warning codes and entry bytes |
| `crops/` | eleven worst-case comparisons with their labels |
