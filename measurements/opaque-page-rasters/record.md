# Page rasters written without their constant alpha plane (#5, #170)

Tier: deterministic Apple PDF stack, macOS 27.0 arm64 (Darwin 27.0.0, xnu-13432.1.9), release CLIs,
`--execution-context host-terminal`, library defaults unless a converter option is named. Date
2026-09-17, on `754eb7a`. Baseline CLI `c7c28877…bc06` is that tree unmodified; candidate CLI
`626d04ee…9620` is that tree with this change. The machine was shared with five other agents
(load average 7–19 across the runs, recorded per run below), so times are single observations, not
budgets. No PDF or EPUB is committed.

**Result.** NOAA NCA5 now completes under library defaults and is gated. Warren does not, and the
arithmetic says no encoding choice at default quality will make it fit.

## Where the two excluded books stood on this tip

Both books were re-measured before any change, because #151 (`b1c7043`) stopped annotations forcing
page images and #93 changed OCR for image-backed pages.

| Book | Last completed reconstruction page | Seconds | Peak RSS | Peak footprint |
| --- | --- | ---: | ---: | ---: |
| NOAA NCA5, #5 baseline (2a63b92) | 598 / 1,834 | 64.78 | 918,814,720 | — |
| NOAA NCA5, 7fb0e7b | 599 / 1,834 | 63.77 | 1,028,816,896 | — |
| **NOAA NCA5, 754eb7a** | **1,727 / 1,834** | 103.82 | 1,029,963,776 | 383,944,240 |
| Warren, #5 baseline (654dba9) | 390 / 920 | 203.44 | 2,112,585,728 | — |
| **Warren, 754eb7a** | **390 / 920** | 187.18 | 1,175,650,304 | 506,726,200 |

#151 moved NOAA from 33% to 94% of the book: its 15,098 links stopped adding 803 page images.
It moved Warren not at all, because Warren's one annotation is the GPO seal on page 1 and its
references come from `unverifiedTextLayer` on 903 scanned pages, which #151 does not touch.

Running each book again with `--maximum-output-bytes=unlimited --maximum-epub-bytes=unlimited`
shows where the remaining bytes are (`classify-images.py`, which reads each `<img>`'s alt text:
`Original page N` is a source-page reference, anything else a region crop):

| Book | Entry bytes | Source-page references | Region crops |
| --- | ---: | ---: | ---: |
| NOAA NCA5 | 588,490,848 (561.23 MiB) | 62, 216.42 MiB (mean 3,574 KiB) | 1,486, 338.26 MiB (mean 233 KiB) |
| Warren | 1,247,292,221 (1,189.51 MiB) | 910, 1,175.03 MiB (mean 1,322 KiB) | 22, 11.69 MiB |

NOAA was **49.23 MiB over** the 512 MiB default; Warren was **2.32× over**. NOAA's 62 remaining
references are all `unverifiedTextLayer` pages, and reading them against the source they are the
chapter covers and front matter, where a full-bleed painting fills the page (page 80, *Climate
Trends*, is a 6.46 MiB raster of the artwork). Those references are earned: the artwork exists
nowhere else in the EPUB.

## The alpha channel no reader needs

`PageRasterizer.image` draws every raster into a `premultipliedLast` RGBA context after filling it
opaque white, so the alpha channel is 255 in every pixel of every raster, and ImageIO writes that
constant plane into every PNG. Sampling the written assets with `recode-survey.py` (40 references
and 22–150 crops per book, decoded with Pillow and re-encoded at one compression level so the
comparison is between formats, not encoders):

| Sample | Fully opaque | R==G==B | PNG RGBA (written) | PNG RGB | PNG gray | JPEG 0.90 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Warren references | 40/40 | 0/40 | 100% | 74.5% | 26.9% | 31.1% |
| Warren crops | 22/22 | 0/22 | 100% | 76.7% | 27.6% | 20.5% |
| NOAA references | 40/40 | 0/40 | 100% | 81.8% | 29.1% | 19.2% |
| NOAA crops | 150/150 | 2/150 | 100% | 82.7% | 30.6% | 31.1% |

Grayscale is not available: the Warren scans are yellowed paper, whose channels differ by a mean of
26–55 levels over the whole page, and NOAA's covers are paintings. Dropping the alpha channel is,
by contrast, free — it carries no information at all.

### What was changed

`PageRasterizer.write` now hands `CGImageDestination` the raster relabelled opaque:

```swift
static func opaque(_ image: CGImage) -> CGImage      // premultipliedLast -> noneSkipLast
```

It builds a new `CGImage` over the raster's **own data provider**, with the same width, height,
bits, stride, colour space and intent, changing only the alpha description. Premultiplying by an
alpha of 1 changes nothing, so `premultipliedLast` and `noneSkipLast` describe the identical bytes;
no pixel is read, nothing is copied, and PNG then writes colour type 2 instead of 6.

**The raster itself is unchanged.** An earlier attempt built the *context* as `noneSkipLast`, which
also works and is 0.5% smaller again — but it changes the pixels Core Graphics produces, by one
level over 31% of channel samples and by up to 4 levels away from the raster's outer border
(`pixel-deltas.py`; every difference of 5 or more lay on the outer one-pixel row or column of a
full-bleed cover). That raster is also what Vision recognizes, and under the fresh Vision caches of
`--fresh-vision-cache` it cost the CDC comic a line: page 20's `I AGREE.` was read by the baseline
build and not by that candidate, stably across repeats. Relabelling at the moment of writing keeps
recognition, `TextLayerPlausibility` and `AnnotationEvidence` on exactly the bytes they have been
measured against, and confines the change to image output.

### That the output is the same picture

`compare-pixels.py` decodes every asset of both EPUBs and compares the RGB arrays. NOAA under
`--maximum-output-bytes=unlimited`, baseline against candidate:

- 1,548 of 1,548 assets **identical pixel for pixel**; baseline wrote RGBA with an all-opaque alpha
  channel in all 1,548, candidate wrote RGB in all 1,548;
- 127 markup, package and navigation files compared, and only `package.opf` differs — its random
  `dc:identifier` and modification date, which the writer generates per run;
- entry bytes 588,490,848 → 510,379,982, 13.3% smaller.

Warren, the same comparison at the earlier `noneSkipLast`-context build, was also 932 of 932
identical; its whole-book entry total is byte-for-byte the same under both builds
(1,114,310,156), so the relabelling and the opaque context write the same file for that book.

`PageRasterizerTests.writtenPNGDropsTheRastersConstantAlphaWithoutChangingAPixel` asserts the
raster stays `premultipliedLast`, that every fourth byte of it is 255, that `opaque` returns the
same provider data, that the PNG's IHDR colour type is 2, and that the decoded file still carries
the drawn rectangle at the same pixels. Negative control: against the pre-change source its first
three expectations fail.

## NOAA completes under library defaults

Candidate CLI, no converter options, load average 15–18:

| | Baseline | Candidate |
| --- | ---: | ---: |
| Outcome | fails after reconstruction page 1,727 / 1,834 | **completes 1,834 / 1,834** |
| Entry bytes | 588,490,848 (561.23 MiB) | 510,379,982 (486.74 MiB) |
| Headroom under the 512 MiB default | −49.23 MiB | **+25.26 MiB** |
| Final EPUB bytes | — | 502,665,496 |
| Images | — | 1,548 (62 references, 1,486 crops) |
| Seconds | 103.82 | 120.9–123.7 |
| Peak RSS | 1,029,963,776 | 965,214,208 – 1,025,523,712 |
| Peak physical footprint | 383,944,240 | 397,559,392 – 463,881,824 |

25 MiB is 4.9% of the budget. A change that adds image bytes to this book will put it back over;
that is a property of the book, not of this change, and the gate is what reports it.

## Warren still cannot fit, and the arithmetic says why

| Warren, candidate CLI | Entry bytes | Against the 512 MiB default |
| --- | ---: | --- |
| Library defaults (PNG) | 1,114,310,156 (1,062.69 MiB) | 2.08× over; fails after page **436 / 920** (was 390) |
| `--full-page-image-encoding smallest:0.9` | 537,220,320 (512.33 MiB) | **349,408 bytes over** (0.065%) |

`smallest` picks the smaller of PNG and JPEG per image, so it is the best any per-image encoding
choice can do at that quality: it chose JPEG for 920 of the 932 assets and PNG for 12. The
whole book is 910 full-page references of colour scans; 512 MiB over 920 pages is 583 KiB a page,
and a 180 DPI colour page will not go under that losslessly. The remaining 0.065% would close with
a slightly lower JPEG quality or DPI, which is tuning a quality knob to make a gate pass, so it is
not done here. Warren stays excluded, and the levers left — the default encoding for scanned
full pages, the raster DPI, or a reference policy for books where nearly every page is
unverified — are policy decisions recorded on #5, not measurements.

Peak RSS 1,185,447,936 and footprint 516,425,480 on the failing default run, against the
baseline's 1,175,650,304 and 506,726,200: unchanged within the run-to-run spread.

(An earlier `noneSkipLast`-*context* build raised Warren's resident size to 1,812,365,312 while its
footprint fell to 374,704,360 — resident, purgeable pages Core Graphics left mapped, the #140
effect. The relabelling build does not show it. Recorded because it is the reason RSS is worth
watching on a change that looks like it only touches a file format.)

## Every corpus book got smaller, and nothing else moved

`tools/run_corpus_regressions.py`, one lane per build, `--execution-context host-terminal`, EPUBCheck
`/opt/homebrew/bin/epubcheck`. Full per-case figures are in `lane-baseline.json` and
`lane-candidate.json`; `lane-stats.py` produces them.

All 21 shared cases pass both lanes. Entry bytes fall in every one of them, by 4.0% to 14.3%,
**11.5% over the lane** (876,869,619 → 776,323,224). The image count is identical in every case,
so nothing was dropped to get there, and peak RSS moves by at most 3% either way — within the
~100 MiB flap the corpus doc records. The largest savings: DGA 14.3%, USDA 13.6%, Our Flag 13.5%,
USGS and Census 13.2%, CDC and USCIS 13.1%, FAA 12.9% (32,258,250 bytes). The smallest: the 9/11
report 4.0% and NBS 5.0%, both mostly text. Loper Bright has no images and does not change.

## NOAA in the lane

`corpus/regressions.json` gains a `noaa-nca5-2023` contract and loses its
`excludedFullConversions` entry. Run alone, the case passes its contract, EPUBCheck, the progress
check and the memory gate: 28 content checks over review pages 1, 33, 48, 80, 139, 900, 1700 and
1834, EPUBCheck exit 0, `memoryGate` lowest peak RSS 965,214,208 against the 1,280 MiB ceiling,
123.72 seconds (`noaa-content-assessment.json`, `noaa-result.json.gz`,
`noaa-conversion-report.json.gz`). The full 22-case lane passes.

The eight pages were read against 70 DPI Poppler renders of the source before the contract was
written, and the contract holds only what that reading supports:

- **1, 33, 80, 139** — cover and chapter openings. Pages 80 and 139 reflow `Fifth National Climate
  Assessment: Chapter 2` and the titles *Climate Trends* and *Earth Systems Processes*, and keep
  the full-bleed cover painting as a source-page image, which is the only copy of that artwork.
  `pageReference: true` on all four.
- **48, 900, 1700** — ordinary illustrated pages, contracted `pageReference: false` so they cannot
  regress into whole-page images. Page 48's callout paragraph, page 900's *Climate Change
  Governance* heading with the Figure 20.2 caption after the crop, and page 1700's *Focus on
  Western Wildfires* title with its *Authors and Contributors* and *Recommended Citation* blocks
  and three named authors, all reflow and are named in the contract.
- **1834** — the back cover of agency seals, which the graphics reader refuses
  (`unsupportedGraphics`); contracted as an image under `pageImageFallback`.

The memory ceiling is **1,280 MiB**, over measured peaks of 920.5–978.0 MiB: the same ceiling the
FAA handbook carries, and about 30% of headroom over the highest peak seen here.

**Cost per full corpus run**: 120.9–123.7 seconds of conversion, and about 502 MB of EPUB plus its
staging, transient, deleted with the lane's output directory. The 22-case lane took 5 min 49 s
against 3 min 29 s for the 21 without it, under different machine load.

## What this does not establish

- Not whole-book fidelity for NOAA. Text still trapped inside region crops (page 48's left column
  and its Figure 1.5 caption) and page 1700's ten Technical Contributors lines run into one
  paragraph are visible in the reviewed pages, are not approved by the contract, and are filed as
  [#181](https://github.com/vocaro/PDFReflowLib/issues/181).
- Not a physical iPhone or iPad storage or memory budget. Every figure here is a Mac release CLI
  process under a shared machine's load.
- Not a claim about other PDF viewers' alpha handling, or about books whose rasters are genuinely
  transparent: `opaque` returns the image untouched unless it is 32-bit `premultipliedLast`.
- The NOAA headroom is 4.9%. It is a pass, not a comfortable one.
