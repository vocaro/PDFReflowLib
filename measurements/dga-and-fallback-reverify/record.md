# Whole-page fallback re-verification: DGA (#13, #14) and FAA pages 226, 286, 288, 302, 348, 448

Measured first on `785a974`, then re-based on `63680df`, `de0df61` (#98/#52 clip-bounded
footprints), `f15ab78` (#65/#66) and `3f59dff` (#109). The final comparison, contracts and tests
below use `3f59dff` as the baseline. The two cached PDFs are the checksum-pinned corpus sources
(`DGA.pdf` SHA-256 `c34f1bec…a472`, `faa-h-8083-25c.pdf` `247929ca…95cb7`).

## Runtime change

`GraphicsReader.operationBudget` goes from 100,000 to **250,000** scanned operators per page.
The budget only bounds scanning time: paints (10,000), text shows (50,000), covers (10,000)
and saved states (128) keep their own caps, so memory does not grow with it. Nothing else
changes: no public API, option or default. Pages over the budget still set `unsupported`, keep
the whole-page image and report `unsupportedGraphics` and `pageImageFallback`. Every other
unsupported condition (inline images `EI`, unreadable resources, malformed shading, the paint
cap) is untouched.

## Step 1: current state and causes

Diagnosis used an instrumented copy of GraphicsReader that records the source line of every
`unsupported = true` (`tools/instrument.py`, `tools/diagnose-main.swift`). Word counts compare
reflowed EPUB text between page markers with `pdftotext -layout` words (`tools/words.py`).

### DGA (10 pages)

No DGA page sets `unsupported`, and none is rotated. The report shows 10/10 reflowed pages, zero
`unsupportedGraphics`/`pageImageFallback` warnings, 28 images and zero OCR pages (identical at
`785a974`, `63680df`, `de0df61` and `3f59dff`). #13's original title ("rasterizes eight of ten
pages", 2/10 reflowed) no longer holds.

| Page | Whole-page fallback | Reflowed / pdftotext words | Why a full-page image remains |
| --- | --- | --- | --- |
| 1 | no | 16 / 16 | Painted cluster `[0,0,612,792]` (cover art) → `unverifiedTextLayer` + reference image |
| 2 | no | 492 / 536 | — (header/welcome text inside preserved upper region) |
| 3 | no | 277 / 284 | Connected graphics cluster `[0,0,612,744.9]` (94% of page) → `unverifiedTextLayer` + reference |
| 4 | no | 252 / 259 | Cluster `[0,0,612,792]` → `unverifiedTextLayer` + reference |
| 5 | no | 270 / 277 | Cluster `[0,0,612,792]` → `unverifiedTextLayer` + reference |
| 6 | no | 52 / 160 | — three regions; alcohol body columns and the Sodium callout stay inside crops |
| 7 | no | 366 / 379 | — (two-column infancy bullets interleave line by line) |
| 8 | no | 159 / 293 | — (introduction callout and section text inside crops) |
| 9 | no | 304 / 315 | — |
| 10 | no | 221 / 233 | — (chronic-disease / vegetarian columns interleave line by line) |

### DGA cover (#14)

Resolved, as retained by existing contracts: the title reads `Dietary Guidelines For Americans`
(0fd4728), and `Protein, Dairy` and `Vegetables` are intact (2233d5f).

Remaining: the label rows still emit `Protein, Dairy` / `Vegetables` / `& Healthy Fats & Fruits`
/ `Whole Grains`. The source sets two stacked two-line labels at opposite edges (x≈39 and
x≈479–507). This is not a reconstruction or graphics-ownership join. PDFKit's `selectionsByLine`
returns `& Healthy Fats & Fruits` as **one native line** spanning x 39–571. Its two source shows
lie on baselines 0.018 pt apart. `tools/cover-character-bounds.swift` shows the join is a
synthesized space whose character box is 342.9 pt wide (index 10). The line's character offsets
also disagree with its string: offsets 19–23 carry the geometry of the next line's `Ve g`. That is
the offset mismatch `NativeTextReader` already warns about. Splitting on character geometry is
therefore not reliable, and no change is proposed here.

### FAA

| Page | Cause at `785a974` | State at `3f59dff` before this change | After |
| --- | --- | --- | --- |
| 226 | operation budget: 183,417 ops (line `operations > 100_000`) | fallback, 0/704 words | reflows 469/704 |
| 286 | operation budget: 105,197 ops | fallback, 0/356 | 318/356 |
| 288 | operation budget: 166,179 ops | fallback, 0/597 | 567/597 |
| 302 | operation budget: 101,594 ops | fallback, 0/432 | 403/432 |
| 448 | operation budget (1,953,873 ops) **and** 10,000-paint cap | fallback, 0/579 | unchanged fallback |
| 348 | not a fallback: no `unsupported`, no `pageImageFallback`. Unclipped image/path footprints at x≈277–280 came within 4 pt of the left photos and merged them with the right-column diagram into one crop `[34,360,533,740]` that swallowed both titles (15/239 words) | **fixed by `de0df61`** (clip-bounded footprints): four crops, both two-line titles as headings, 197/239 words | unchanged |

The remaining words on the four pages are labels inside preserved illustrations (map
coordinates, contour values, figure labels).

## Why 250,000

`operation-survey.txt` counts operators per page, with the current reader, for every cached
corpus PDF (about 4,700 pages; `tools/survey.py`). Above 100,000 there are only FAA 226, 286,
288, 302 (101,594–183,417) and 448 (1,953,873), plus NOAA page 1834 (191,628). NOAA 1834 and
FAA 448 also reach the 10,000-paint cap, so they fall back regardless. The next highest page
anywhere is 25,736 (IRS p596). CDC, Our Flag and Fed peak at 155, 11,923 and 25,069, so a
budget change cannot affect them. Scanning the heaviest newly accepted page takes 0.03–0.15 s on
this loaded Mac across runs, and FAA 448's 1.95 million operators take 0.25–3 s. A 250,000
ceiling keeps the scan bounded at roughly 2.5× the old cost. It is a time limit, not a claim that
denser drawings are unsafe. The six `jresv82n3p173_A1b.pdf` pages fall back for inline images
(`EI`), not the budget.

## Tests and negative controls

`Tests/PDFReflowLibTests/OperationBudgetTests.swift` uses original minimal PDFs, where one
polyline of `l` operators costs exactly `segments + 2` operations:

- `denseDrawingWithinTheOperationBudgetIsAPaintedRegion`: 183,417 operations (FAA 226's count)
  give one bounded region.
- `operationBudgetIsExactAndExcessStillFallsBack`: exactly the budget is supported; one more is
  unsupported.
- `denseDrawingKeepsAdjacentProseReflowing` (pipeline): prose above and below reflows, with one
  preserved image and no fallback warnings.
- `drawingOverTheOperationBudgetStillKeepsThePageImage` (pipeline): `unsupportedGraphics` and
  `pageImageFallback` remain.

With the budget temporarily restored to 100,000, the first three fail (7 issues) and the
over-budget control still passes. The existing positive controls `rotatedAndOCRDisabledPagesAreExplicitImageFallbacks`
and the rotated policy fixture (exactly one `pageImageFallback`) pass unchanged.

Corpus contracts (`corpus/regressions.json`):

- **FAA**: pages 226, 286, 288 and 302 check headings, source order, list items (302), captions,
  minimum images and the absence of `pageImageFallback`/`unsupportedGraphics`. Pages 225, 287 and
  301 check that the sentence continues onto the next page. Page 348 checks both titles, their
  paragraphs and four images. Page 448 is a positive fallback control (`warningCodesAnyOf:
  pageImageFallback`). **Against the `3f59dff` baseline output the contract fails with 55 errors**,
  covering every new check on pages 225–302 (`faa-baseline-summary.json`). The candidate passes.
  Page 348's checks pass on the baseline because `de0df61` already fixed it; they guard that fix.
- **DGA**: page 3 gains `absentWarningCodes`, and pages 6, 7 and 10 get new entries
  (no fallback, a source-correct phrase or heading, one image). The interleaved bullets on pages
  7 and 10 are deliberately not asserted. Negative control: a mutant binary that restores #13's
  original trigger (`sh` sets `unsupported`) sends pages 3–10 back to page images (2 reflowed
  pages) and **fails 27 checks**, including every new DGA check (`dga-mutant-summary.json`).

## Corpus lane (baseline `3f59dff` vs candidate, shared capability probe)

| Case | Result | Changed pages | Notes |
| --- | --- | --- | --- |
| dga-2025-2030 | PASS / PASS | none | 10/10 reflowed, 28 images, EPUBCheck 0 |
| faa-phak-8083-25c | PASS / PASS | 225, 226, 286, 287, 288, 301, 302 | reflowed 500 → 504; images 595 → 597; 8 changed image bytes (new crops); fallback [226,286,288,302,448] → [448]; peak RSS 815 → 840 MB (limit 1,280 MiB), sampled footprint 539 → 542 MB |
| cdc-zombie-pandemic-2011 | PASS / PASS | none | fallback pages 2, 38, 40, 41 unchanged |
| gpo-our-flag-2003 | PASS / PASS | none | fallback page 55 unchanged |
| fed-explained-2021 | PASS / PASS | none | fallback pages 2, 23, 49, 65, 87, 134 unchanged |

`cmp-*.json` are the `compare_conversion_runs.py --allow-different-converters` outputs. Each
changed FAA page was reviewed by hand against a Poppler render of the source page and the
emitted crops:

- **226**: both columns in order; headings Magnetic Compass Induced Errors, Variation and
  Deviation; the complete isogonic map as one crop, then its caption.
- **286**: headings Atmosphere and Composition of the Atmosphere; complete Figure 12-1 and
  12-2 crops with captions.
- **288**: complete Figure 12-4 and 12-5 crops with captions; the Coriolis paragraphs, then
  the Measurement of Atmosphere Pressure heading and paragraph.
- **302**: columns in order; Fronts and Warm Front headings; the four front types as a list;
  the complete air-mass map with its caption.
- **225, 287, 301**: the last sentence now continues across the former fallback page instead
  of stopping mid-sentence.

On 286 and 288 a figure at the top of the right column is emitted inside the sentence that
crosses the column (`…spheres of the` / figure / `atmosphere have been…`). That is existing
figure-placement behaviour: `tools/midsentence.py` finds 90 such interruptions in the baseline
FAA EPUB, and the new pages add two of the same kind.

## Recommendations

- **#13**: the headline (DGA page-image fallback) is resolved: 0/10 pages fall back. The issue's
  remaining acceptance is selective preservation and section-local order, which stays open as
  recorded in `measurements/dga-layout-qualification`: reference images and `unverifiedTextLayer`
  on pages 1 and 3–5 from page-sized connected clusters, text inside crops on pages 6 and 8, and
  interleaved two-column bullets on pages 7 and 10. Retitle it or close it in favour of narrower
  issues.
- **#14**: title and native word spacing are resolved. Only the cover label association remains,
  and its cause is now pinned to PDFKit line grouping with unreliable character offsets rather
  than graphic ownership. Keep it open, narrowed to that, or refile.

## Distinct defects to file

1. PDFKit joins same-row labels at opposite page edges into one native line through a very wide
   synthesized space (DGA cover `& Healthy Fats & Fruits`). The line's character offsets are
   misaligned, so a fix needs a different geometry source, for example show origins from the
   content stream.
2. Inline images (`BI`/`ID`/`EI`) always force whole-page fallback (all six pages of
   `jresv82n3p173_A1b.pdf`). They could be painted regions like `Do` images, following the
   shading precedent.
3. Figures set at the top of a right column split the sentence that crosses the column (90 FAA
   occurrences before this change).
4. DGA pages 7 and 10 interleave two-column bullet lines (known #13 scope, still present at
   `3f59dff`).
