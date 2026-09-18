# The automatic image-encoding default (#193)

Tier: deterministic Apple PDF stack, macOS 27.0 arm64 (Darwin 27.0.0), release CLIs built from
`0046fdd` (baseline, PNG default) and from this change (candidate), `--execution-context
host-terminal`, one environment probe shared by both sides. Date 2026-09-17. The machine was shared
with other agents' corpus lanes, so seconds are single observations. No PDF or EPUB is committed;
the two crops below are from rights-cleared books (FAA, NOAA), and none of the six books that
commit no rasters (doc/corpus.md) contributes a picture.

**Result.** `ConversionOptions()` now encodes every image with `.automatic(jpegQuality: 0.90)`:
`ImageContentClassifier`, a Swift port of the [survey's prototype](../image-encoding/record.md)
that agrees with it exactly, decides per image whether lossy is permitted, and a permitted image
takes the smaller of PNG and JPEG 0.90. Over the 22 gated books plus Warren, 6,385 images, image
bytes fall from 2,259.34 to 1,285.69 MiB (**−43.1%**), 1,555 images are written as JPEG, and the
per-book bytes and JPEG counts land on the survey's projection. The FAA attitude indicator is
kept PNG by one tightening of the class. NOAA's headroom under the 512 MiB default grows from
5.1% to 40.9%. **Warren converts under the default budget**, with 316,202 bytes (0.059%) to spare,
because every one of its 932 images is permitted; nothing was tuned to get there. The cost is
about 20 ms of arithmetic per 3-megapixel raster, 7.8% more CPU over the gated corpus, and no
measurable memory.

## What the default does

Per emitted image, in the pipeline's `saveImage` (the caller of `PageRasterizer`):

1. **Role.** A supplementary page reference sits beside its page's reflowed text and is judged as
   a page; a region crop, and a required full-page fallback (the page's only copy), are judged as
   crops. The survey measured fallbacks as crops too: its index labels them "Preserved region".
2. **Page evidence.** A page whose type arrives inside an image — no text layer, or text over a
   page-sized graphic, the image-backed signal `unverifiedTextLayer` uses — is recorded during
   extraction. A typeset page reference of such a page is a scan; otherwise born-digital text.
3. **Features and class**, exactly as `classifier.features` / `classify`: the modal colour and
   the share within 10 levels of it, the share whose hue differs from it by 24 levels, the
   bilevel share, the distinct colours, and the flat / step-edge / ramp shares of the grey
   gradient. The prototype's second photograph test (ramp-dominated over a JPEG XObject) is
   omitted: every image it admits passes the continuous-tone test after it, and both classes
   permit lossy, so no verdict depends on it.
4. **Verdict**, `lossy_is_safe` plus one tightening (below): permitted when the chroma share is
   under 2%, or the class is photograph, continuous-tone art or tonal text scan, or it is a
   `mixed` page reference; refused for coloured line art and charts, `mixed` crops, coloured
   bilevel and born-digital text pages, **and continuous-tone crops at least 30% flat**.
5. A permitted image goes to `PageRasterizer.encode` as `.smallest(jpegQuality: 0.90)`, the rest
   as `.png`. `encode` is unchanged; a caller that names `.png`, `.jpeg` or `.smallest` gets
   exactly that, for pages and regions, and the classifier never runs.

The features are read from the bitmap context's own buffer through a new `inspect` hook on
`PageRasterizer.image`, before the `CGImage` is made. Reading a finished `CGImage`'s bytes
(`CGDataProvider.data`) copies them: 22.9 MiB of extra footprint for a 6-megapixel raster,
measured with a standalone probe, which at the 12-megapixel ceiling would be 46 MiB per image.

## The port agrees with the prototype

`compare_features.py` runs `classifier.py` and the library's own `ImageContentClassifier.swift`
(compiled into `features.swift`) on the same PNG files: up to 40 images per book, spread evenly
over the assets, from PNG conversions of the 21 gated books that emit images.

| | Result |
| --- | --- |
| images compared | 734 from 21 books (485 line art, 65 continuous-tone, 60 mixed, 59 photograph, 53 bilevel and 12 tonal scans) |
| class | identical on 734 |
| lossy verdict (with the tightening on both sides) | identical on 734 |
| modal colour | identical on 734 |
| largest difference in any share or in the distinct-colour count | **0** |

The modal colour is exact, not approximated: counts are taken inside the most populated 4-bit
bins, most populated first, until no unexamined bin could hold more than the best exact count.
`agreement.jsonl.gz` holds every row. A Swift test pins a hand-computed 4×4 raster to the same
numbers the prototype gives.

End to end, `decisions.py` pairs each written image with the survey row for the same raster
(same document, page, role and PNG bytes; asset numbers moved since the survey because crops were
added) and compares the written format with the survey's projection under the adopted rule:
**5,936 of 5,937 paired images agree**. The one difference is the page signal: Earthdata slide 4
has 56 characters of text and a small image, so the survey (which called any page with an image
XObject or under 200 characters "scanned") projected a tonal scan; the library's image-backed
signal says born-digital, and at chroma share 0.055 the page stays PNG (414,046 bytes, 226,459 as
JPEG). The difference is in the conservative direction. 448 images have no survey row (crops added
since `88803ac`, and the IRS and USCIS books the survey left out).

## The attitude indicator: the class is tightened

The survey's worst case under its rule is FAA page 67, an instrument panel drawn with a flat
blue sky and brown ground, shaded bezels, and a yellow aircraft symbol (96.5 levels). Its features
sit at the continuous-tone boundary (ramp share 0.212 against the 0.20 threshold, hard-edge ratio
0.29) and its flat share is 0.352. No photograph in the corpus reaches a flat share of 0.30 —
captured tone leaves almost no pixel with an exactly equal neighbour — while drawn illustration
does, and drawn illustration is where saturated fills and labels meet at hard coloured edges.

Candidate tightenings, projected from the survey's 6,076 stored rows:

| Rule | Corpus MiB | JPEG | ≥ 30 levels | Worst |
| --- | ---: | ---: | ---: | ---: |
| survey's `lossy_is_safe` | 1,233.54 | 1,528 | 56 | 96.5 |
| crop continuous-tone needs ramp share ≥ 0.25 | 1,253.48 | 1,481 | 45 | 81.2 |
| crop continuous-tone refused if hard-edge ratio ≥ 0.25 | 1,246.10 | 1,507 | 50 | 81.2 |
| every coloured continuous-tone crop refused | 1,276.70 | 1,435 | 41 | 53.6 |
| **coloured continuous-tone crop refused if flat share ≥ 0.30 (adopted)** | **1,251.80** | **1,497** | **51** | **53.6** |

The adopted rule reuses the line-art test's own "flat fields" constant rather than fitting a new
one, and it refuses 31 crops, all continuous-tone art, none a photograph: the attitude indicator,
the FAA's magnetic-pole map (81.2, thin red meridians on blue), a NOAA page-621 crop (55.7), the Fed
screenshot with "CONSUMER ALERT" in yellow (34.1), the Our Flag seal, and 26 others; the 31 have a median
error of 17.3 levels. It gives up 18.3 MiB (1.5% of the projected total) and takes the worst
projected case from 96.5 to 53.6 levels. Page references are untouched: their text is reflowed
beside them. Reviewed as PNG | JPEG strips at 1× and 4×, the refused crops lose the edges of
their saturated lettering and lines at 4× (the attitude indicator's yellow triangle picks up a
green fringe; the pole map's red meridians turn grey-pink), and the collateral ones (a waving flag
already soft in its source) show nothing. In the converted FAA book the attitude indicator is
`image-52.png`.

The rule's measured limit is the same family on *photographs*: callouts with coloured text laid
over a photo (FAA pages 78, 344, 347, 368, 450, "Stabilator pivot point" and the like) are
continuous-tone crops under 0.30 flat and stay JPEG, at 32–49 levels, visible at 4× and legible at
1×. No existing feature separates them from ordinary photographs without refusing photographs.

## Re-measured corpus

Each gated case was converted twice through `tools/run_corpus_regressions.py`, one case per call,
with EPUBCheck, the memory gate and the shared probe: the baseline converter, then the candidate.
`remeasure.py` pairs the two EPUBs image by image (same name, same pixel dimensions), measures each
written JPEG against the baseline's lossless PNG of the same raster with the survey's
`fidelity` (worst mean absolute error over an 8×8 block holding a step edge), and checks that
every non-image entry is identical once image names, media types and the per-run identifier and
date are normalized. Warren is not gated (#5) and was converted with the CLI directly. Each
book's EPUBs were deleted as soon as its numbers were written. `tables.md` is the generated
table; `summaries.json` and `remeasured.jsonl.gz` hold the numbers.

"Projected" recomputes the survey's rows for the same document: under the survey's rule, and
under the adopted rule. Image sets moved since the survey for USDA (52 → 64 images), Techport,
Wallace and the Earthdata deck, so those rows compare different pictures.

| Document | Images | PNG MiB | automatic MiB | vs PNG | projected MiB (survey / adopted) | JPEG | projected JPEG (survey / adopted) | worst edge error | ≥ 30 |
| --- | ---: | ---: | ---: | ---: | --- | ---: | --- | ---: | ---: |
| arxiv-replay-clocks-2023 | 34 | 0.90 | 0.90 | +0.0% | 0.90 / 0.90 | 0 | 0 / 0 | — | 0 |
| cdc-zombie-pandemic-2011 | 42 | 124.38 | 31.50 | −74.7% | 31.50 / 31.50 | 36 | 36 / 36 | 41.5 | 1 |
| census-rrs2002-01 | 51 | 5.31 | 5.31 | +0.0% | 5.31 / 5.31 | 0 | 0 / 0 | — | 0 |
| cia-blue-book-14-1955 | 424 | 188.71 | 186.23 | −1.3% | 186.23 / 186.23 | 98 | 98 / 98 | 1.8 | 0 |
| dga-2025-2030 | 37 | 4.61 | 1.82 | −60.5% | 1.82 / 1.82 | 16 | 16 / 16 | 24.1 | 0 |
| faa-phak-8083-25c | 567 | 205.50 | 123.90 | −39.7% | 121.27 / 123.91 | 136 | 143 / 136 | 53.6 | 27 |
| fed-explained-2021 | 57 | 26.72 | 12.86 | −51.9% | 11.93 / 12.86 | 12 | 14 / 12 | 25.9 | 0 |
| gpo-911-2004 | 50 | 5.45 | 2.96 | −45.6% | 2.96 / 2.96 | 34 | 34 / 34 | 1.7 | 0 |
| gpo-our-flag-2003 | 123 | 10.97 | 6.77 | −38.3% | 6.58 / 6.77 | 19 | 23 / 19 | 28.5 | 0 |
| gpo-warren-1964 (not gated) | 932 | 1,059.88 | 508.91 | −52.0% | 508.92 / 508.92 | 932 | 932 / 932 | 18.1 | 0 |
| irs-p596-zhs-2025 | 146 | 13.57 | 13.23 | −2.5% | not surveyed | 1 | — | 2.0 | 0 |
| nbs-jres-geltman-1977 | 42 | 6.52 | 4.65 | −28.6% | 4.65 / 4.65 | 42 | 42 / 42 | 1.9 | 0 |
| noaa-nca5-2023 | 1,544 | 479.25 | 295.87 | −38.3% | 282.96 / 297.45 | 126 | 143 / 125 | 51.3 | 14 |
| ntrs-20180003024-earthdata-slides-2018 | 21 | 3.06 | 3.02 | −1.5% | 2.80 / 2.80 | 4 | 5 / 5 | 30.9 | 4 |
| ntrs-20190030725-dasc-2019 | 28 | 0.85 | 0.85 | +0.0% | 0.86 / 0.86 | 0 | 0 / 0 | — | 0 |
| ntrs-20200002975-gwl-2020 | 31 | 5.88 | 4.28 | −27.3% | 4.28 / 4.28 | 15 | 15 / 15 | 39.5 | 2 |
| ntrs-20210020887-techport-thm-2021 | 39 | 0.74 | 0.66 | −10.8% | 0.98 / 0.98 | 3 | 1 / 1 | 20.9 | 0 |
| scotus-loper-bright-2024 | 0 | 0.00 | 0.00 | — | not surveyed | 0 | — | — | 0 |
| uscis-m618-arabic-2015 | 150 | 51.02 | 33.26 | −34.8% | not surveyed | 44 | — | 28.8 | 0 |
| uscourts-pro-se-1-2016 | 21 | 0.01 | 0.01 | +0.0% | 0.01 / 0.01 | 0 | 0 / 0 | — | 0 |
| usda-ars-agresearch-2012-11 | 64 | 27.11 | 9.81 | −63.8% | 20.66 / 20.66 | 21 | 19 / 19 | 73.9 | 2 |
| usgs-mcs2025-copper | 3 | 0.33 | 0.33 | +0.0% | 0.33 / 0.33 | 0 | 0 / 0 | — | 0 |
| wallace-algebra-2010 | 1,979 | 38.57 | 38.57 | −0.0% | 38.59 / 38.59 | 16 | 7 / 7 | 1.7 | 0 |
| **23 books** | **6,385** | **2,259.34** | **1,285.69** | **−43.1%** | | **1,555** | | **73.9** | **50** |

Against the survey's corpus-wide prediction:

| | Survey, its rule | Survey rows, adopted rule | Written, the 20 surveyed books |
| --- | ---: | ---: | ---: |
| image bytes | 1,233.54 MiB (−44.1%) | 1,251.80 MiB | 1,239.19 MiB (−43.5% of 2,194.75) |
| images sent to JPEG | 1,528 | 1,497 | 1,510 |
| JPEGs with a worst edge-block error ≥ 30 levels | 56 | 51 | 50 |
| worst edge-block error | 96.5 | 53.6 | 73.9 |

Bytes, counts and the damaged tally land where the adopted rule's projection puts them; the
residual differences are the books whose images changed since the survey. The one number that
moved is the worst case, and it comes from one of those new images: USDA page 21, a full-page
reference (`mixed`, chroma share 0.59) whose blue hyperlinks on tan paper fringe at 4×, beside
the page's reflowed text. It is a page reference, which the owner's rule admits, in a book whose
rasters may not be committed, so no crop of it is here. The worst *crop* is FAA page 103 at 53.6,
as projected (`crops/faa-phak-8083-25c-p103-image-96.png`).

The 50 images at 30 levels or more are the survey's two kinds: page references and photographs
where the difference sits on a genuine high-contrast boundary, and photographs or painted art
carrying saturated annotation. Four of them are "neutral" by share and still coloured where it
matters: charts and slides that are mostly white with small coloured labels (NOAA page 46,
46.1 levels, `crops/noaa-nca5-2023-p46-image-87.png`; the Earthdata deck's NASA insignia,
30.9, on references that save only 3–15%). The survey found the same tail below the 2% line
(20 of 4,286 images).

Every gated case passed both sides, with EPUBCheck clean on every candidate EPUB. The comparator
(`compare_conversion_runs.py --allow-different-converters`, same probe) reports changed pages only
in their `images`, `markup` and `pageReferences` fields; `remeasure.py` confirms that markup differs
only in image names and media types, with no text, navigation or report field changing and every
image the same pixel size. No content contract changed; the reference-image, glyph and appearance
checks all still pass on JPEG crops where the default chose JPEG.

### NOAA

| | Entry bytes | Headroom under 512 MiB |
| --- | ---: | ---: |
| `png` (0046fdd default) | 509,394,704 | +27,476,208 (5.1%) |
| survey's projection, its rule | 303,567,498 | +233,303,414 (43.5%) |
| **automatic (written)** | **317,101,396** | **+219,769,516 (40.9%)** |

The tightening costs NOAA about 14 MiB of the survey's projection.

## Warren

| | Entry bytes | Headroom under 512 MiB | EPUB bytes |
| --- | ---: | ---: | ---: |
| `png` (0046fdd, unlimited budgets) | 1,114,294,736 | −577,423,824 | 1,112,789,913 |
| survey's verified `smallest:0.9` run | 536,560,653 | +310,259 | 531,833,226 |
| **automatic, unlimited budgets** | **536,554,710** | **+316,202 (0.059%)** | **531,827,310** |

With library defaults and the **default 512 MiB budget**, the candidate CLI converted the whole
book, exit 0, 932 images, 450 s, 1.17 GB peak RSS. Every one of the 932 images was written as
JPEG: its 853 tonal scans are permitted by class, and its line-art images are neutral (chroma
share under 2%), so the automatic default does for Warren exactly what `smallest:0.9` did in the
survey. The worst edge-block error is 18.1 levels. EPUBCheck: 0 errors, 0 warnings.

This contradicts the expectation in #193 and the survey's "text pages lossless" row, which kept
Warren's text pages PNG; the owner's rule permits tonal scans, and Warren's pages are tonal scans.
No quality knob was touched. The margin is 316,202 bytes: any change that adds a few hundred KB of
Warren's image bytes puts it back over. Warren stays excluded from the corpus lane; whether a
0.059% pass admits it is #5's decision. The exclusion reason and the manifest status now say so.

## Cost

Classification is one pass of integer and float arithmetic, a second pass per batch of candidate
grounds (almost always one), and a third for the shares, over the raster the converter already
holds. Transient memory is a 2 MiB distinct-colour bitset, three rows of grey and 512 KiB of exact
counts. Measured in `features` (release build): median 7.6 ms per megapixel, 17–31 ms for a
3-megapixel page raster.

In the paired lane runs (22 gated books, one run each on a shared machine):

| | baseline (PNG) | automatic | change |
| --- | ---: | ---: | ---: |
| conversion seconds, sum | 322.0 | 351.7 | +9.2% |
| converter CPU seconds, sum | 315.8 | 340.3 | +7.8% |
| largest peak RSS (FAA) | 809 MiB | 808 MiB | — |
| NOAA peak RSS | 998 MiB | 979 MiB | — |

Separate CLI runs split the cost between classification and the extra encode `.smallest` does
(user seconds, one run each):

| Book | `png` | `smallest:0.9` everywhere | automatic |
| --- | ---: | ---: | ---: |
| FAA handbook (567 images) | 47.9 | 47.9 | 50.3–52.8 |
| Blue Book (424 page scans) | 45.5 | 47.5 | 56.9 |
| Wallace (1,979 crops) | 28.1 | 28.8 | 31.2 |

So the classifier itself costs about 20 ms per page-sized raster (Blue Book: 9.4 s over 424 pages)
and a few ms per crop. Peak RSS moved by no more than run-to-run noise in any run. Peak physical
footprint is noisy on the FAA book (558–810 MiB across three identical automatic runs, 559–561 MiB
for `png` and `smallest`), and the gated lane's footprint for FAA was 534 → 533 MiB; nothing in the
classifier allocates on that scale, so the spread is attributed to ImageIO and system caches, not
measured further. The Warren run was 420 s automatic against 434 s PNG.

## Contract

FAA page 67 gains an `imageAppearance` check on the attitude indicator
(`corpus/references/faa-phak-8083-25c/page-67-attitude-indicator-color.png`, rendered from the
source at points 308,63–358,113). On the candidate conversion the crop scores 0.99 correlation,
0.70 contrast and 0.99 colour agreement over 373 coloured samples; a grayscale copy scores 0.00
agreement. A JPEG 0.90 copy of the same crop scores the same as the PNG (0.99 / 0.69 / 0.99): the
check works at 36 DPI, where chroma subsampling is invisible, so it pins that the figure is there
in colour and not which encoding it took. The encoding decision is pinned by
`ImageContentClassifierTests` (the drawn-illustration crop refused, its page reference and a
shaded crop under 30% flat permitted), whose tests fail when the tightening is disabled. The FAA
case passes with the new check.

## Reader check

The candidate FAA EPUB (567 images, 136 JPEG) passes EPUBCheck with no messages and opens in the
repository's foliate-js reader (`tools/view_epub.py`): the JPEG crops and page references load and
render (chapter 5 of 33, source pages 66–74: 12 images, 6 JPEG, none failing to decode), and the
attitude indicator on page 67 is served as `image-52.png`. Not checked in Apple Books or on a device.

## What this does not establish

* **Not a reader study.** "Visible" means PNG | JPEG strips at 1× and 4× on a desktop display.
* **Not other encoders.** The chroma subsampling this rule is built around is ImageIO's on this
  macOS build; another OS could change the numbers.
* **Not a device budget.** Every number is a Mac release CLI.
* **Thresholds are corpus-fitted**, as the survey says; the tightening reuses an existing constant
  but was chosen by looking at this corpus.
* **The neutral share is a share.** A mostly white chart with small saturated labels is admitted
  by the 2% rule and loses those labels' edges at 4× (NOAA page 46).

## Files

| File | What it is |
| --- | --- |
| `features.swift` | prints the library classifier's features and verdict for PNG files; compiles `Sources/PDFReflowLib/ImageContentClassifier.swift` |
| `compare_features.py` | runs the prototype and the port on the same PNGs |
| `agreement.jsonl.gz` | the 734 compared images |
| `remeasure.py` | pairs a baseline and a candidate EPUB, measures each written JPEG against the lossless PNG, checks the rest of the book is unchanged |
| `decisions.py` | pairs written images with the survey's rows and compares decisions |
| `analyse.py` | per-book tables against the survey's projections |
| `tables.md` | the generated per-book table and the list of JPEGs at 30 levels or more |
| `remeasured.jsonl.gz` | every written image: format, bytes, baseline bytes, fidelity for JPEGs |
| `summaries.json` | per-book totals, lane timings and memory, and comparator results |
| `crops/` | two PNG / JPEG strips from rights-cleared books, with labels |
