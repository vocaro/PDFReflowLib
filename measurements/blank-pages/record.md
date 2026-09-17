# Blank pages (#132)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 (26A428) arm64, release CLIs.
Baseline: an unmodified release build of `96667ce` (converter `e299ef99…`); candidate: that tree
with this change (`43e0ea8e…`). 9/11, Fed, Our Flag, FAA and Wallace were run on that base. The
change was first measured on `ce2cf5b` against every English lane case with the same result; the
other eight cases' summaries in `lane/` are from that run. Every corpus figure below is
`tools/run_corpus_regressions.py`, one case per call, with the compiled raster/Vision probe and
`--execution-context host-terminal`, then `tools/compare_conversion_runs.py
--allow-different-converters --detail` (summaries without the rename pairs in `lane/`). No PDF or EPUB is committed.

## Diagnosis

9/11 pages 162 and 342 have empty content streams: `mutool draw -F trace` shows no operation at
all. PDFKit extracts no line, so under `automatic` OCR the page is recognized, recognition finds
nothing, and the pipeline's `content.lines.isEmpty → requiresPageImage` rule emits a full-page
white PNG with `ocrUsed` and `pageImageFallback`. Under `never` the same rule applies without OCR.

## Survey of the English corpus

`tools/survey.py` lists every page whose `pdftotext -layout` text holds at most six non-space
characters and renders it with Poppler at 36 DPI grayscale (`ink<250`: fraction of pixels darker
than 250; `min`: darkest pixel).

| Book | Pages with at most six characters | Rendered | Outcome |
| --- | --- | --- | --- |
| 9/11 | 2, 4, 8, 10, 12, 162, 342, 466 | all pure white (min 255), nothing painted | were white page images; now boundary only |
| Fed Explained | 2, 23, 49, 65, 87, 134 | pure white, nothing painted | were white page images; now boundary only |
| Fed Explained | 7 | full-page photograph (min 126, no pixel below 128 at 36 DPI) | image kept (control) |
| FAA | 97, 244, 256, 310, 375, 387, 452, 460 `A-8`, 512 `G-36` | folio only | text pages; #97 already empties 460/512 without an image; unchanged |
| Wallace | 175, 437 | folio only | #97 empties them; unchanged |
| Our Flag | 1, 55 | covers (ink 0.89, 0.95) | images kept |
| CDC | 2, 13, 15, 16, 17, 36, 38, 40, 41 | comic art | images kept |
| Warren (excluded from the lane) | 1–4, 10, 12, 20, 498, 917, 918, 920 | scans; 4, 498, 917 and 918 are near-empty sheets (min 184–204) | painted images, so never blank |
| DGA, NBS, Replay Clocks, USGS, SCOTUS, Census, Blue Book, NOAA | none | — | — |

The only blank pages in the corpus are the fourteen pages of 9/11 and the Fed whose streams paint
nothing. The issue named 162 and 342; the front-matter versos 2–12 and 466 behaved identically.

## Change

`BlankPageDetector` decides a page is blank only when two kinds of evidence agree, before OCR:

1. **Drawing.** No extracted line; no annotation; `GraphicsReader` reports nothing unsupported, no
   unplaceable text, no invisible text, no text show (upright or slanted), no painted footprint,
   region or inline image. White fills are not footprints in `GraphicsReader`, so a page that only
   paints white passes this step.
2. **Render.** The crop box drawn with `CGContext.drawPDFPage` at one pixel per point in 8-bit
   device RGB over white holds no pixel with any channel below **254**. The threshold is one level
   of rounding: a 0.9985 gray fill (254.6) passes, 0.99 gray (252) fails, as do a 0.1-point
   hairline, a 2×2 image of 251–252 samples scaled over the page, and a 1/0.98/0.98 pink tint.

Such a page keeps `requiresPageImage` false and returns before OCR: it contributes its
`sourcePage` boundary and nothing else, with no warning, exactly like the FAA/Wallace pages #97
emptied. A rotated empty page is blank too (the rotation only mattered for the image). Under
`referenceImages = .always` a blank page still gets its reference image, as any page does.

`tools/compare_conversion_runs.py` did not normalize the new `pageReferences` field (the
`Original page N` assets), so removing one early image reported every later reference page as
changed (9/11 28 pages, Fed 93, on the `277cbde` base) although only names moved. The field now maps names to bytes as
`images` does; a renamed reference is an id-only shift, a changed one still changes its page.

## Tests

`BlankPageTests.swift`, synthetic PDFs:

- an empty stream, a white fill and a rotated empty page keep only their boundaries (no image,
  no warning) under `never`, `automatic` and `always` OCR; `always` recognizes only the two text
  pages; the document validates;
- controls keep their images and warnings: a 0.97 gray tint, a quarter-point hairline, a near-white
  scan, a pure-white scan (painted, so not blank), a Square annotation; faint 0.99 gray text reflows;
- the detector: threshold 254, white/near-white renders versus 0.99 gray, hairline, faint scan and
  pink tint; drawing evidence for empty, white fill, tint, white scan, text and annotation;
- a two-page conversion writes `page-2` with no `<img>` and no warning.

Negative control: with the pipeline hook disabled, the policy test fails 7 expectations (images and
warnings on the three blank pages under each policy, assets under `.always`) and the EPUB test 3;
the detector tests are independent of the hook. `test_renamed_source_page_reference_is_an_id_only_shift`
fails without the comparison fix (`changedPages [1, 2]`).

## Contracts

`corpus/regressions.json`: 9/11 pages 162 and 342 and Fed pages 23 and 134 carry `maximumImages: 0`
and `absentWarningCodes: [pageImageFallback, ocrUsed]`; Fed page 7 (the photograph) keeps
`minimumImages: 1`. The `96667ce` baseline fails all eight new blank-page checks (4 per book); the
candidate passes.

## Corpus lane

| Case | Baseline | Candidate | Changed pages | Notes |
| --- | --- | --- | --- | --- |
| gpo-911-2004 | fail (new contracts only) | pass | 2, 4, 8, 10, 12, 162, 342, 466 | each loses its white image, `ocrUsed` and `pageImageFallback`; 8 images removed, 75 renamed, 44 id-only shifts; `recognizedPageCount` 8 → 0; markers and navigation equal |
| fed-explained-2021 | fail (new contracts only) | pass | 2, 23, 49, 65, 87, 134 | same; 6 images removed; `recognizedPageCount` 7 → 1 (page 7 still recognized) |
| gpo-our-flag-2003, faa-phak-8083-25c, wallace-algebra-2010 | pass | pass | none | identical pages, images and report |
| cdc-zombie-pandemic-2011, dga-2025-2030, cia-blue-book-14-1955, nbs-jres-geltman-1977, usgs-mcs2025-copper, scotus-loper-bright-2024, census-rrs2002-01, arxiv-replay-clocks-2023 (on `ce2cf5b`) | pass | pass | none | identical pages, images and report |

Warren and NOAA full conversions stay excluded (#5); the survey shows neither has a page this rule
would take (Warren's near-empty sheets are scans, NOAA has no textless page).

## Limits

A page whose only content is text PDFKit cannot extract but that paints no glyph the reader sees
(for example a Type3 font drawing nothing) is not reached: text shows alone make the page non-blank.
The render check is per page and costs one 1 px/pt raster only for pages with no line and no
painted mark.
