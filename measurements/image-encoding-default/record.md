# The automatic image-encoding default, hand-ported (#242)

Tier: deterministic Apple PDF stack, macOS 27.0 arm64 (Darwin 27.0.0), release CLIs built from
`a75ed4d` (baseline: PNG everywhere, alpha plane written) and from this change (candidate), run
one at a time from a worktree on a machine shared with other agents' lanes, so every second is a
single observation. Date 2026-09-19. No PDF, EPUB or raster is committed; every conversion's
output was deleted as soon as its numbers were read
([measurements policy](../../tools/check_measurements.py)).

Two features of the abandoned coordination branch are ported here under the
[hand-porting convention](../../doc/decisions/0005-abandoned-coordination-branch.md), against
main's own code and re-measured against the checksum-pinned documents rather than copied from the
branch's records:

- **`73cbdfe`, the constant alpha plane.** Every raster is drawn into a `premultipliedLast` RGBA
  context over an opaque white fill, so its alpha channel is a constant 255 plane that ImageIO
  wrote into every PNG. `PageRasterizer.write` now relabels the raster opaque over its own pixel
  buffer — no copy, no pixel read — so PNG records colour type 2.
- **`fbe3464`, the per-image encoding classifier.** `ImageContentClassifier` decides per image
  whether lossy is safe; `ImageEncoding.automatic(jpegQuality: 0.90)` is the new default for both
  full pages and regions.

The branch's `measurements/image-encoding/` survey (`aadbaf2`), which fitted the thresholds, is
**not** in the tree and was not re-run: this record re-measures what the ported rule does, not why
the thresholds are where they are.

## What was ported, and what was not

`ImageContentClassifier.swift` and its tests are the branch's files unchanged — they compile and
pass against main without modification, which is itself evidence that the classifier depends on
nothing that evolved on the branch. The wiring is adapted to main's pipeline:

| Branch | Main |
| --- | --- |
| the pipeline's inline `saveImage` resolves the encoding | `PageAssetWriter.save` does, main's single asset-writing seam, through a new `drawnFromImage:` parameter |
| `pagesDrawnFromImage` computed inline from `noText`/`imageBackedText` | the same set, from `PageEvidence.hasText` and `PageEvidence.imageBackedText`, which main's `PageDiagnosis` already produces |
| `check-conversion-policies.py` | `check_conversion_policies.py` (renamed on main), same three added cases and three added rejections |

Not ported: the branch's FAA `imageAppearance` reference for page 67
(`page-67-attitude-indicator-color.png`). It is a committed raster and a new contract check; the
encoding decision it was added to pin is already pinned by `ImageContentClassifierTests`, and the
region-reference machinery is measured below to be insensitive to the encoding either way.

## Fidelity

The metric is the survey's, recomputed here: each JPEG the candidate wrote is compared with the
baseline's lossless PNG **of the same raster** (same asset name, checked for the same pixel
size), and the figure quoted is the worst mean absolute error over any 8×8 block holding a step
edge — where chroma subsampling shows — plus PSNR over the whole image.

Every gated case, both builds, every image paired:

| Document | Images | PNG MiB | automatic MiB | vs PNG | JPEG | worst edge error | ≥ 30 | kept PNG identical |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| arxiv-replay-clocks-2023 | 70 | 8.09 | 7.05 | −12.9% | 0 | — | 0 | 70/70 |
| cdc-zombie-pandemic-2011 | 42 | 143.10 | 31.50 | −78.0% | 36 | 41.5 | 1 | 6/6 |
| census-rrs2002-01 | 37 | 4.43 | 3.85 | −13.0% | 0 | — | 0 | 37/37 |
| cia-blue-book-14-1955 | 421 | 205.18 | 185.56 | −9.6% | 95 | 1.8 | 0 | 326/326 |
| dga-2025-2030 | 28 | 7.59 | 4.75 | −37.4% | 6 | 24.4 | 0 | 22/22 |
| faa-phak-8083-25c | 619 | 247.65 | 133.77 | −46.0% | 144 | 52.8 | 27 | 475/475 |
| fed-explained-2021 | 317 | 73.97 | 52.18 | −29.5% | 12 | 26.0 | 0 | 305/305 |
| gpo-911-2004 | 101 | 17.73 | 13.37 | −24.6% | 34 | 1.7 | 0 | 67/67 |
| gpo-our-flag-2003 | 147 | 12.71 | 6.78 | −46.7% | 19 | 28.5 | 0 | 128/128 |
| gpo-warren-1964-suspect-text-excerpt | 5 | 6.03 | 1.89 | −68.7% | 5 | 7.8 | 0 | 0/0 |
| irs-p596-zhs-2025 | 140 | 35.30 | 32.82 | −7.0% | 4 | 24.6 | 0 | 136/136 |
| nbs-jres-geltman-1977 | 8 | 6.14 | 4.21 | −31.5% | 8 | 1.9 | 0 | 0/0 |
| ntrs-20180003024-earthdata-slides-2018 | 21 | 4.22 | 3.51 | −17.0% | 5 | 30.9 | 5 | 16/16 |
| scotus-loper-bright-2024 | 0 | 0.00 | 0.00 | — | 0 | — | 0 | 0/0 |
| uscis-m618-arabic-2015 | 213 | 102.07 | 73.67 | −27.8% | 40 | 28.8 | 0 | 173/173 |
| usgs-mcs2025-copper | 3 | 0.38 | 0.33 | −13.6% | 0 | — | 0 | 3/3 |
| usda-ars-agresearch-2012-11 | 75 | 78.63 | 43.56 | −44.6% | 25 | 51.8 | 3 | 50/50 |
| wallace-algebra-2010 | 2,151 | 45.01 | 39.59 | −12.0% | 9 | 1.7 | 0 | 2,142/2,142 |
| **18 gated cases** | **4,398** | **998.25** | **638.38** | **−36.1%** | **442** | **52.8** | **36** | **3,956/3,956** |

Plus the two excluded books: NOAA, 2,410 images, 1,098.93 → 773.61 MiB (−29.6%), 126 JPEG, worst
51.3, 14 at 30 levels or more, 2,284 of 2,284 kept PNGs identical; and Warren, 931 images,
1,185.96 → 508.61 MiB (−57.1%), all 931 JPEG (measured on a 62-page even spread of the book,
below).

Three things in that table matter more than the byte column:

1. **Every image count is unchanged**, book by book, and every paired image has the same pixel
   size. Nothing is dropped, added, rescaled or re-cropped.
2. **3,956 of 3,956 images the candidate kept as PNG decode to pixels identical to the
   baseline's**, and so do 2,284 of 2,284 on NOAA. The alpha-plane removal is lossless, as
   claimed: it drops a constant plane and nothing else.
3. **36 of 442 JPEGs (8%) reach 30 levels or more** on the worst edge block. That is the cost,
   and it is concentrated: 27 of them are FAA figures.

### The 36, looked at

The three worst FAA crops were re-rendered as PNG | JPEG strips at 1× and 4×, centred on the
worst 8×8 block (strips are raw captures and stay out of the tree; `strips.py`'s recipe is in the
Files table):

| Asset | What it is | Class, flat share | Worst edge block | PSNR | At 1× | At 4× |
| --- | --- | --- | ---: | ---: | --- | --- |
| `image-299` | isogonic chart: thin red and blue meridians over a pale green map | continuous-tone art, 0.152 | 52.8 | 27.9 | indistinguishable | the thin red meridians desaturate and pick up grey fringes |
| `image-116` | "SPHERE WITH A FAIRING": yellow lettering on saturated blue | continuous-tone art, 0.213 | 52.5 | 29.3 | indistinguishable, fully legible | the yellow letters pick up a green fringe |
| `image-279` | dark photographic panel with coloured callouts | continuous-tone art, 0.129 | 49.1 | 40.1 | indistinguishable | soft colour edges on the callout text |

All three are the family the rule documents as its own limit: **coloured continuous-tone crops
below the 0.30 flat share**, which the classifier calls captured tone rather than drawn
illustration. The branch's worst crop was the same kind and the same size (FAA page 103, yellow
lettering on blue, 53.6 levels); nothing here is worse than what the rule was adopted knowing.
What the rule does refuse — coloured line art, charts, mixed crops, coloured text pages — stays
PNG and is byte-identical in pixels, which is why Wallace's 2,142 equation crops and the CIA
book's 326 line-art scans do not move.

The five Earthdata JPEGs at 30.1–30.9 are one repeated element, the NASA insignia on full-page
slide references, beside the page's own reflowed text. The CDC, NOAA and USDA cases at 41–52 are
page references and photographs carrying saturated annotation.

### Warren, sampled over the whole book

A 62-page even spread of the pinned Warren PDF (every fifteenth page from 5 to 920, cut with
`qpdf` after verifying the manifest's SHA-256) converted on both builds: 63 images, all 63 JPEG
on the candidate, **worst edge block 9.4 levels, median 6.6, minimum PSNR 42.7 dB, none at 30**.
Warren's pages are yellowed tonal scans with almost no chroma, which is the case JPEG 0.90 costs
least. The five-page gated Warren excerpt agrees: worst 7.8.

### Region references

All 17 committed region references, scored on both builds with the gate's own
`image_regions.region_score`:

| | Result |
| --- | --- |
| references scored | 17, on 6 cases |
| correlation identical to 4 decimals, before and after | **17 of 17** |
| references now scored against a JPEG asset | 3 (nbs page 1, cdc page 13, faa page 19) |
| lowest score, either build | 0.9735 (faa page 19), floor 0.95 |

This is a weaker check than it looks, and the reason is worth recording: a region reference is
rendered `-gray` and pooled to 36 DPI, so it is insensitive by construction to chroma
subsampling, which is the only damage this change does. The references prove the figure is still
there, complete and aligned; they are not the fidelity evidence. The edge-block measurements
above are.

## Do the two excluded books fit?

Both books converted end to end on both builds. "Baseline" needs the budget lifted on both books;
"candidate" is a plain default run for Warren.

| | Entry bytes | Against the 512 MiB default | Images |
| --- | ---: | --- | ---: |
| **Warren**, baseline (budget lifted) | 1,246,503,733 | 2.32× over | 931, 0 JPEG |
| **Warren**, candidate, library defaults | **536,242,227** | **628,685 bytes (0.117%) inside** | 931, 931 JPEG |
| **NOAA**, baseline (budget lifted) | 1,158,819,926 | 2.16× over | 2,410, 0 JPEG |
| NOAA, alpha plane removed only | 1,011,966,197 | 1.88× over | 2,410, 0 JPEG |
| **NOAA**, candidate (budget lifted) | **817,716,220** | **1.52× over** | 2,410, 126 JPEG |
| NOAA, candidate forced to `smallest:0.9` | 694,592,660 | 1.29× over | 2,410, 490 JPEG |

**Warren fits. NOAA does not**, and the two halves of the change contribute very differently to
each. Warren's whole gain is the classifier: all 931 of its images are tonal scans or neutral, all
931 go to JPEG, and the alpha plane it would otherwise have dropped is worth nothing to it because
no image stays PNG. NOAA's gain is mostly the alpha plane (−12.7% on its own); the classifier adds
a further −19.2% and no more, because only 126 of its 2,410 images are ones JPEG encodes smaller —
the rest are the chart and line-art crops the classifier is right to refuse. Forcing the book to
`smallest:0.9`, which takes JPEG wherever it is smaller and asks nothing about content, sends 490
images to JPEG and still lands **1.29× over**: no encoding choice this library offers makes NOAA
fit. Making NOAA fit is not an encoding problem — at 2,410 crops and 180 DPI it is a question
about how many crops the book should emit, or at what resolution.

### Warren's margin is too thin to gate on

628,685 bytes of 536,870,912 is 0.117%. To put a scale on that, the same 62-page excerpt
converted at five JPEG qualities:

| quality | image bytes | vs 0.90 |
| --- | ---: | ---: |
| 0.88 | 35,100,237 | −1.10% |
| 0.89 | 35,274,725 | −0.61% |
| 0.90 | 35,490,662 | — |
| 0.91 | 35,490,662 | — |
| 0.92 | 36,305,862 | +2.30% |

One step of 0.01 in requested quality moves Warren's image bytes by about 0.6%, five times the
whole margin; the margin is worth roughly **0.002 of JPEG quality**. Nothing in the library
controls that: the bytes come from ImageIO's encoder on this macOS build, and a minor OS revision
that changed its tables by a fifth of a percent would put the book back over the budget with no
change in this repository. The branch measured the same book at 316,202 bytes (0.059%) of margin
and drew the same conclusion.

So Warren converting at the default is a real result and is recorded as one, but it is not a
result the corpus lane can be pinned to. Both `excludedFullConversions` entries stay, with reasons
that now state the measured position and cite the open issue instead of the closed one. Admitting
Warren is a one-line change whenever the owner decides a 0.117% pass is a pass; what would make it
defensible is either margin (a lower default DPI for wholly unverified scanned books, or a
reference policy for them) or a lane that runs Warren under an explicit larger budget.

## Cost

| | baseline | candidate | change |
| --- | ---: | ---: | ---: |
| 18 gated cases, conversion seconds, one run each | 170.2 | 218.2 | +28% |
| NOAA | 163.8 | 195.0 | +19% |
| Warren (candidate at defaults, baseline with the budget lifted) | 389.5 | 460.0 | +18% |

The classifier reads the raster's own buffer through `PageRasterizer.image`'s `inspect` hook
before the `CGImage` is made — `CGDataProvider.data` on a finished image copies the pixels — and
its transient memory is a 2 MiB bitset, three rows of grey and 512 KiB of counts whatever the
raster's size. Measured directly on FAA crops, `features` runs in 2–8 ms each. The wall-clock
figures above are larger in proportion than the branch's (+9.2%), and they are single observations
on a machine running five other agents' work; the split between classification, the second encode
`.smallest` performs, and the neighbours was not measured further. Peak RSS was not measured here;
the memory gate is not part of `--fast`.

## What this does not establish

* **Not a reader study.** "Visible" means PNG | JPEG strips at 1× and 4× on a desktop display,
  read by one reviewer.
* **Not other encoders, and not other OS builds.** The chroma subsampling the rule is built
  around is ImageIO's, on this macOS build. Warren's 0.117% margin in particular is a property of
  this encoder.
* **Not a device budget.** Every number is from a Mac release CLI.
* **Thresholds are corpus-fitted.** They were fitted on the branch, on a survey this repository
  does not hold; this record measures the fitted rule's behaviour, and cannot re-derive it.
* **Warren is sampled.** Its fidelity figures are 63 images from a 62-page spread plus the gated
  five-page excerpt, not all 931.
* **The neutral share is a share.** A mostly white chart with small saturated labels passes the
  2% rule and loses those labels' edges at 4× (NOAA's worst images are of this kind).

## Files

| File | What it is |
| --- | --- |
| `summaries.json` | every number quoted above: per-book baseline/candidate bytes, counts and seconds, per-book fidelity summaries and worst three images, the Warren excerpt's fidelity and quality sweep, and all 17 region-reference scores |

The harness (conversion and byte accounting, the fidelity metric, region scoring, the strip
renderer) ran from a scratch directory and is not part of the tree; `summaries.json` is what it
produced. The fidelity metric is the branch survey's `fidelity`, and the region scores come from
the repository's own `tools/image_regions.py`.
