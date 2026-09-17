# Silent OCR text loss (#116)

Tier: Apple PDF stack plus Vision, macOS 27.0 (26A428) arm64, library defaults (180 DPI). Probes built
from the library's own sources; lanes and end-to-end runs use release converters from tip `9803329`
(baseline) and `9803329` plus this change (candidate). Six agents shared the Mac (one-minute load
5–9 during compiles). No PDF, EPUB, render or transcription is committed.

## Summary

- **The #108 lossy compile did not reproduce.** Ten fresh compiles in this session (six distinct
  program fingerprints) all read Census pages 2–20 as 923 lines. With #108's three compiles, one
  lossy draw in 13 has been seen.
- **Silent loss is not rare, though.** Compiles that read Census cleanly still dropped text.
  - The reference compile (`22614cb0…`, #108's clean set) kept 11 of about 64 lines on Warren
    page 100, only the sentence tails after note markers.
  - It dropped the top half of page 138 and about half of the dense note pages 858 and 873.
  - It left most handwritten-table cells out on 61 of 312 Blue Book pages.
  - The lane converter's compile (`c28e7928…`) read page 100 fully but lost text on 138, 858 and
    873.
  - Nothing reports any of this.
- **Detector.** `OCRTextCoverage` reuses the raster Vision read, with no second recognition. It
  finds rows of glyph-sized ink standing on clear background and measures how much of that ink lies
  outside every recognized line box, ignoring Vision's table regions. A page is flagged when at
  least 8 such rows, holding at least 20% of that ink, are uncovered.
  - Cost: 9 ms median per page (17 ms max, 505 pages).
  - Clean flags: none on Census, CDC (all 42 pages), NBS JRES or Our Flag.
  - Every Warren and Blue Book page it flags was checked and holds real missing text.
- **One bounded retry recovers the text.** A flagged page is recognized again as two overlapping
  bands (top and bottom 60%). The banded result is kept when its lines leave less text-shaped ink
  uncovered.
  - On the flagged probe pages, bands took Warren 100/138/858/873 from 307 to 612 lines and cut
    uncovered rows from 239 to 23.
  - Blue Book went from 14,802 to 32,432 lines, with uncovered rows from 1,089 to 25.
  - Changing the raster DPI fixed only page 100.
  - The `ocrUsed` message says a retry happened; it warns if loss remains.
- **Default lanes are unchanged.** Census, CDC and Blue Book show no drift against tip, with shared
  compiled models. None of their default-policy OCR pages trips the check.
- **Tooling.** `compare_conversion_runs.py` now reports `ocrTextVolume` and an `ocrTextLoss` note.
  They name OCR pages where one run has under 80% of the other's words (and at least 25 fewer), so
  the #94 compile caveat no longer hides a dropped paragraph.

## Reproduction attempts

`probe-ocr-lines.swift` (built with the command in its header) rasterizes each page as the converter
does and prints the converter request's `document.text.lines` with boxes. `run-compile.sh` copies it
to a never-used executable name, which forces a fresh compile into `~/Library/Caches/<name>`, and
records `conversion_provenance.vision_model_cache` after each book.

| Name | Fingerprint (`programsSHA256`) | Census 2–20 lines / tokens / Vision words / transcript characters |
| --- | --- | --- |
| `tl116a` | `22614cb0d67a8299…` | 923 / 6,794 / 6,488 / 41,175 |
| `tl116b` | `1d83732cbc871b3f…` | same |
| `tl116c` | `2dda869df5640452…` | same |
| `tl116d` | `2dda869df5640452…` | same |
| `tl116e` | `22614cb0d67a8299…` | same |
| `tl116f` | `d9be3b4e37db05be…` | same |
| `tl116g` | `c4c51e08d27ae518…` | same |
| `tl116h` | `068626d5f2c55c8c…` | same |
| `tl116ref` (all survey books) | `22614cb0d67a8299…` | same |
| `tl116retry` (retry probe) | `22614cb0d67a8299…` | 923 lines (base variant) |
| `pdf-reflow-i116` (lane converters) | `c28e79286f04ee8f…` | 19 OCR pages, 5,939 EPUB words in both builds |

The cap was eight screening compiles, and none dropped Census text. `tl116ref` then recorded the
survey books; its totals equal #108's clean sets (Warren excerpt 518 lines, Blue Book 42,579).
Because the #108 draw could not be recreated, the detector was first built against simulated loss:
recorded line boxes are removed after recognition (`replay-coverage.swift`). The real losses
described below turned up while surveying false positives.

## Signal

`Sources/PDFReflowLib/OCRTextCoverage.swift`, applied in `OCRReader.read` to the image just
recognized:

1. **Luminance.** Read from the converter's 8-bit RGBA raster bytes, or drawn into a gray context for
   other formats. Ink is darker than an Otsu threshold clamped to 96–170.
2. **Components.** Eight-connected components come from run-length labeling. A glyph is a component
   2.5–40 pt tall, at most 12 times as wide as tall, with fill density 0.08–0.9, whose center lies
   outside Vision's table regions (those become images).
3. **Rows.** Glyphs join into rows when they overlap vertically by half the smaller height, differ
   in height by at most 2.5×, and lie within 1.5× the taller height of each other.
4. **Text rows.** A row counts when it has at least 5 glyphs and its box holds at most 1.5× its
   glyph ink in dark pixels. Printed text stands on clear paper; window grids, crowds and hatching
   do not.
5. **Coverage.** Recognized line boxes are grown by half their height sideways and a third
   vertically. A glyph is covered when its center falls inside one. A row is uncovered when most
   of its ink is uncovered.
6. **Verdict.** `indicatesLoss` requires at least 8 uncovered rows and an uncovered share of at
   least 20% of text-row ink.

How the parameters were chosen, all with the replay on `tl116ref` recognition:

- **Background filter.** Added after overlays of flagged CDC pages showed photo window grids
  (p17, p28) and sky speckle (p1) forming rows.
- **Minimum glyphs.** Raised from 3 to 5 because 3 still flagged CDC pages 1, 17, 20 and 28.
  With 5, CDC flags nothing at any tested threshold.
- **Thresholds.** From `sweep.py`: 5–16 rows × 0.20–0.70.
- **Direct byte read.** Replaced drawing into a gray context after that draw was found to raise the
  converter's peak RSS by about 190 MB on 55 Blue Book pages (see Cost).

### Distributions on clean recognition (`tl116ref`, final parameters)

| Book | Pages | Uncovered fraction median / p90 / max | Uncovered rows max | Flagged |
| --- | ---: | --- | ---: | --- |
| Census 2–20 | 19 | 0.000 / 0.008 / 0.011 | 3 | 0 |
| CDC, all pages (comic) | 42 | 0.006 / 0.487 / 1.000 | 4 | 0 |
| NBS JRES (born-digital journal) | 7 | 0.014 / 0.021 / 0.098 | 24 | 0 |
| Our Flag (illustrated) | 56 | 0.000 / 0.000 / 0.063 | 1 | 0 |
| Warren excerpt pages | 9 | 0.000 / 0.081 / 0.830 | 53 | 1: p100 (53/63 rows, 0.83) |
| Warren sample (pages 3, 18, …, 888) | 60 | 0.000 / 0.254 / 0.757 | 92 | 3: p138 (22/62, 0.41), p858 (92/277, 0.31), p873 (74/277, 0.26) |
| Blue Book (`.always`) | 312 | 0.067 / 0.384 / 1.000 | 34 | 61 (pages 121–262 and 311) |

CDC's high fractions come from pages with 1–4 text rows, such as a cover title, where the 8-row
minimum keeps them quiet. Every flagged Warren and Blue Book page was checked, either with overlays
(green recognized lines, red uncovered rows) or with the retry below. All hold real printed or typed
text that the recognition left out:

- **Warren 100 and 138:** whole body paragraphs, with only the fragments after note markers kept.
- **Warren 858 and 873:** note lines.
- **Blue Book:** row labels, headers and cells of the statistical tables.

None of the flags was artwork.

### Detection of simulated loss (lines removed from the clean recognition)

Pages whose recognition has lines. "Block" removes a contiguous run from the middle of Vision's line
order, and "scattered" removes the same share at seeded positions.

| Book | Block 35% | Block 50% | Block 80% | Scattered 35% | Scattered 50% | Scattered 80% |
| --- | --- | --- | --- | --- | --- | --- |
| Census | 13/19 | 16/19 | 16/19 | 15/19 | 16/19 | 16/19 |
| CDC | 15/36 | 25/38 | 25/38 | 13/36 | 22/38 | 25/38 |
| JRES | 7/7 | 7/7 | 7/7 | 4/7 | 7/7 | 7/7 |
| Our Flag | 42/54 | 46/55 | 48/55 | 26/54 | 38/55 | 48/55 |
| Warren excerpt | 5/7 | 5/7 | 6/7 | 4/7 | 5/7 | 6/7 |
| Warren sample | 51/57 | 52/57 | 54/57 | 26/57 | 50/57 | 53/57 |
| Blue Book | 199/310 | 230/312 | 272/312 | 202/310 | 247/312 | 271/312 |

Pooled over pages not already flagged when clean, 50% losses are detected on 316/430 (block) and
320/430 (scattered) pages, and 80% losses on 363/430 and 361/430. The misses are pages without
enough printed rows to judge:

- Census 12 and 15 are tables, whose ink is excluded.
- Census 20 has 6 lines.
- Most CDC pages carry a few balloons.
- Loss inside a Vision table region is not measured, because those regions are preserved as images.

The #108 lossy page 2 (5 of 33 lines kept) matches the 80% block case, which is detected on Census
page 2 (29 uncovered rows, fraction 0.79).

## Retry or warn

`probe-retry.swift` recognizes each page under several variants and measures each with the library
check:

- **base:** 180 DPI;
- **dpi240** and **dpi150;**
- **tiles:** the 180 DPI raster cropped to the top and bottom 60%, each recognized separately and
  merged by line center;
- **roi:** the same bands via `regionOfInterest`. Vision returns boxes relative to the region, so
  `roi-relative` maps them back; `roi` reads them as full-image boxes to show the difference.

Results with compile `22614cb0…`. Cells give lines and uncovered rows / text rows. Probe
measurements do not exclude tables.

| Page | base | dpi240 | dpi150 | tiles | roi-relative |
| --- | --- | --- | --- | --- | --- |
| Warren 100 | 11, 53/63 | 57, 0/61 | 60, 0/65 | 51, 0/63 | 51, 0/63 |
| Warren 138 | 38, 22/62 | 37, 21/62 | 36, 22/64 | 49, 0/62 | 49, 0/62 |
| Warren 858 | 128, 90/275 | 101, 109/285 | 109, 118/276 | 232, 17/275 | 244, 12/275 |
| Warren 873 | 130, 74/277 | 150, 57/269 | 111, 116/284 | 280, 6/277 | 247, 11/277 |
| Blue Book, 61 flagged pages | 14,802 lines, 1,089 uncovered rows | — | — | 32,432 lines, 25 uncovered rows | — |
| Census 2–20 (controls) | 923 lines, 8 uncovered rows | 903, 22 | 906, 22 | 1,036, 3 | 1,038, 3 |
| CDC OCR pages (controls) | 20 lines, 6 | 19, 5 | 21, 4 | 19, 6 | 18, 6 |

- **Bands recover the dropped text.** Changing resolution does not.
- **Warren recovered text** (`retry_summary.py --diff`) is the missing body: page 100's tiles add
  "motorcade reached the intersection of Elm and Houston Streets, there…". Page 138 adds the
  Zapruder paragraph.
- **Census controls.** On clean Census pages, bands usually read as well or better ("Bureau" for
  "Buresu", "IL3, IL4, and IL5" for "IL3,I14, and 115", "Winkler" for "Wiukler"). One table page (13)
  lost about 300 characters, so the retry runs only on flagged pages and is kept only when it covers
  more.
- **Decision: retry once, warn only if loss remains.** The retry is kept when its lines, measured
  without table exclusion, leave less text-shaped ink uncovered. Measuring without exclusion keeps a
  retry from winning just by reporting a larger table. The final page is then measured again with
  the kept tables excluded, and `uncoveredTextFraction` is reported if it still indicates loss.
- **Messages.** No new warning code. The `ocrUsed` message adds "The first recognition left
  text-shaped ink outside every recognized line, so the page was recognized again in two overlapping
  bands." and, when needed, "About N% of the page's text-shaped ink is still outside every
  recognized line, so some text may be missing; compare the original page image." ("compare the
  source PDF." without references).

## End-to-end

### Lanes

One case per invocation. Baseline and candidate converters were both copied to the file name
`pdf-reflow-i116`, so they share one compiled model set, and both used one compiled raster probe.

| Case | Baseline checks | Candidate checks | Drift (`--allow-different-converters`) |
| --- | --- | --- | --- |
| `census-rrs2002-01` | 54 pass | 54 pass | none; same programs `c28e7928…`; 19 OCR pages, 5,939 words each |
| `cdc-zombie-pandemic-2011` | 11 pass | 11 pass | none; 9 OCR pages, 56 words each; 7.0 s each, RSS 367 / 371 MiB |
| `cia-blue-book-14-1955` | 9 pass | 9 pass | none; no OCR pages under defaults |

### Blue Book with `--ocr always`

Same converters and name, evaluator with the raster probe:

| Run | Retried pages | Still flagged | EPUB words on OCR pages | Output characters | Images | Reflowed pages | Seconds | Peak RSS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| tip | 0 | 0 | 72,882 | 397,839 | 498 | 310 | 201 | 486 MiB |
| candidate | 62 | 0 | 79,832 | 441,344 | 523 | 307 | 297 | 600 MiB |

The candidate retried the 61 pages flagged under the reference compile plus page 111. Under the
reference compile, page 111 has 9 uncovered rows at 0.14, below the threshold.

The comparator lists 34 pages where the tip has under 80% of the candidate's words. Samples read far
better in the candidate:

- p140 "TABLE A 29 EVALVATION ALL SIGHTINGS SIGNTING RELIAGILITY GROUPS, 1950 … Number Per Cent",
  where the tip had "T86L€ 2 29 EVALURTION DE AU- SI6ATINES BY SIGNTING RELIRGILITY … วตลา";
- p224 table headings and row labels, where the tip had "LII CAR BONTRAARS LIY DLANE +W BLDG";
- p111 "INDEX OF TABLES (Continued) Table A133. Evaluation of Unit Sightings…".

It also lists 11 pages where the candidate has fewer reflowed words: 140, 148, 152, 168, 175, 202,
207, 216, 218, 225 and 233.

- **Cause.** The banded recognition reports table regions the first pass missed, and the converter
  preserves table regions as images. Pages 148 and 175 become table images with no reflowed text,
  and the tip's reflowed text on them was junk ("EYALURTION ALL S/GHTINGS … Hreter Per Cest").
- **Retry winner.** The retry won by line coverage alone on every one of these pages. An earlier
  candidate that compared coverage with table exclusion produced byte-identical output.
- **Table policy.** Whether a scanned table page should reflow as recognized cells is a table policy
  question, not a recognition question.

### Warren pages 100, 138, 858 and 873

A four-page PDF was cut from the corpus copy and converted with `--ocr always` by both builds
(compile `c28e7928…`).

| Page | Tip words | Candidate words | Candidate `ocrUsed` note |
| --- | ---: | ---: | --- |
| 100 | 522 | 522 | none (this compile reads it fully) |
| 138 | 307 | 527 | retried in bands |
| 858 | 317 | 774 | retried in bands |
| 873 | 317 | 914 | retried in bands |

## Cost

- **Check.** 9 ms median per recognized page (17 ms max over 505 pages), with no recognition.
- **Retry.** Two more recognitions on flagged pages only. Blue Book `.always` took 201 → 297 s.
- **Memory.**
  - The first implementation drew the raster into a gray `CGContext`. On Blue Book pages 121–175
    (`--ocr always`), that alone raised peak RSS from 371 MB to 563 MB, even with the retry
    disabled. Core Graphics keeps a converted copy with the image, which recognition keeps alive.
  - Reading the RGBA bytes directly brought it back to 372 MB.
  - With the retry, peak RSS is 456 MB (463 MB using `regionOfInterest` instead of crops), so about
    90 MB belongs to Vision's two extra recognitions.
  - Whole Blue Book: 486 → 600 MiB (781 MiB before the fix).
  - Under default OCR policy the lanes show no retry and no measurable change.

## Tooling

`tools/compare_conversion_runs.py` adds `ocr_text_volume`. For pages that are OCR pages in both
runs, it counts EPUB words and reports `ocrTextVolume` (pages, words per run, and pages where one run
has under 80% of the other's words and at least 25 fewer). When any page is listed, it adds an
`ocrTextLoss` note naming the run with less text (#116). This is diagnostic like `ocrCaveat` and
does not change `passed`.

It was not run on the #108 lossy set, whose recognition was deleted. That set's Census volume
(2,213 raw tokens against 6,794, page 2 keeping 5 of 33 lines) is far past both limits.

In #108, the changes between compiles, and even language correction, moved Census tokens by under
1% (6,794 → 6,753). In the Blue Book comparison above the check lists pages in both directions,
including the table-image pages, so a listed page still needs review. `check_reproducibility.py` was not
changed: both of its runs share one executable name and therefore one compiled model set.

## Limitations

- The #108 lossy compile was not recreated, so the detector and retry are verified on simulated
  loss and on the real clean-compile losses above, not on `6c271c61…` itself. Whether bands recover
  that compile's loss is unknown.
- **Sources.** English only, one SDK, no iOS device run. The survey covers 505 pages from seven
  sources, and the thresholds were chosen on them.
- **Blind spots.** The check cannot see:
  - text drawn as artwork (comic lettering, text in photographs);
  - glyphs under 2.5 pt, or merged into components more than 12 times wider than tall;
  - loss inside Vision table regions;
  - loss on pages with fewer than 8 uncovered text rows.
- **Reverse video.** White-on-dark text is not a text row, because its ink is the background. Loss
  there is not measured.
- **Compile variance.** The retry is itself a recognition by the same compiled models and can vary
  between compiles like any other.

## Defects noted for filing

1. **Vision `RecognizeDocumentsRequest` drops text on clean compiles** (worth adding to the #94
   Apple Feedback report). Warren pages with note markers lose whole body paragraphs, and handwritten
   Blue Book tables lose most cells. The same image cut into two bands is read fully. Which pages
   lose text depends on the compile: page 100 under `22614cb0…` but not `c28e7928…`.
2. **Retry exposes table regions on scanned statistical tables.** On Blue Book pages 148 and 175 the
   whole page becomes table images, and nine other pages reflow fewer words. This is a table-policy
   follow-up: whether recognized cells of scanned tables should reflow.
3. **The retry costs about 90 MB of peak RSS and about 50% more time** on retry-heavy `.always`
   books on the Mac. Device budgets were not measured.
4. **Drawing a converter raster into another bitmap context keeps a converted copy alive** while
   Vision holds the image (about 3.5 MB per page, about 190 MB over 55 pages). Other code that draws
   `PageRasterizer` images during recognition should read bytes instead. None was found in the OCR
   path after this change.
5. **The language-correction probe's build command no longer builds at this tree.**
   `measurements/ocr-language-correction/probe-language-correction.swift` compiles `OCRReader.swift`
   without `OCRTextCoverage.swift`. Its record is pinned to `63680df`.

## Files

- `probe-ocr-lines.swift`, `run-compile.sh`: fresh-compile recognition dumps.
- `volume.py`: per-compile line, token, word and transcript volume.
- `replay-coverage.swift`, `replay-all.sh`: the library check over recorded recognition, with
  simulated losses and optional overlays. Vision is never run.
- `summarize.py`, `sweep.py`: distributions, flagged pages and threshold sweep.
- `probe-retry.swift`, `retry_summary.py`: retry variants and their text differences.
- `page_volume.py`: per-page EPUB words, images and warnings of two evaluations.

Recognition dumps, replays, overlays, EPUBs, the excerpt PDFs and every model cache named above
(`tl116*`, `pdf-reflow-i116`) were deleted after recording.
