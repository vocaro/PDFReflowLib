# OCR retry side effects (#129)

Tier: Apple PDF stack plus Vision, macOS 27.0 (26A428), Apple M5 Max (36 GB), library defaults
(180 DPI). Six agents shared the Mac, so single-run memory and time figures are noisy (see
Memory). Baseline is tip `a295f33`, and the candidate is `a295f33` plus this change. Every converter
and Vision probe below was run under the executable name `pdf-reflow-i129`. All receipts record the
same compiled programs (`programsSHA256` `c4c51e08d27ae518…`), and the comparator reports
`sameVisionPrograms: true`, so no OCR difference below comes from a different compile (#94). No PDF,
EPUB or render is committed.

## Summary

- **Table policy.** A kept retry now keeps a table region only when it overlaps a table region of
  the first recognition (`OCRReader.retainedTables`). A retry can remove table images but never
  add them.
  - On Blue Book `--ocr always`, only the 41 retried table pages change. Every one of them reflows
    more words than both before the retry and at tip.
    - Pages 148 and 175: 0 → 451 and 0 → 431 words.
    - The 41 pages: 14,173 → 25,708 words and 108 → 55 images.
    - Whole book: 523 → 470 images and 307 → 309 reflowed pages.
  - The page reference image stays on every page.
  - The cost is that genuine handwritten tables reflow as noisy cell text, and headings and navigation
    entries from cells grow (#7).
- **Retry cost.** Blue Book `.always` (61 of 312 pages retried) took 206 s without the retry and
  295–351 s with it (candidate 300–302 s). That is about 46% more time and about 45% more CPU.
  - Peak RSS rose by about 100–130 MiB.
  - Peak physical footprint did not rise.
  - The extra resident memory is Vision's IOSurface buffers for the band images, which are
    purgeable once idle. Library code cannot bound them without giving up the retry. Defaults are
    unchanged.
- **Raster copy.** Drawing an image into a new gray bitmap context leaves up to 32 buffers held by
  Core Graphics, about 3.4 MiB each on these pages, even through a proxy image or an autorelease
  pool. The converter's RGBA rasters were already read directly (#116).
  - The coverage check's fallback for other pixel layouts drew. It now converts with
    `vImageBuffer_InitWithCGImage`, which leaves nothing behind.
  - No other library code draws an image; see Other raster code.
- **Documented commands.** The language-correction probe and the OCR-headings capture command
  now compile `OCRTextCoverage.swift` too. Their old commands fail with "cannot find
  'OCRTextCoverage' in scope", and all eight probe commands for these OCR files compile.

## 1. Table regions on retried pages

### Evidence

`probe-retry-effects.swift dump` runs the converter's recognition on pages 111 plus the 61
retried pages and records both recognitions (first read, and merged bands). It ran under the
converter's name. The recognition code it used (458a2e9) is unchanged in `a295f33` apart from
reading direction. The retry was kept on all 62 pages. `table_regions.py` and `policy_words.py`
summarize the dump. The two recognitions rarely agree on tables:

- The first recognition reported 41 table regions and the retry 72. Only 14 of the retry's regions
  overlap one of the first's.
- On 41 pages the retry reports a region that overlaps no first-recognition region. Those are
  exactly the 41 pages whose output changes below. On pages 148 and 168 the first reported no
  tables and the retry 2 and 4.
- On 22 pages the first recognition reports a region the retry does not. On pages 123, 125, 134,
  141, 206 and 260 the retry reports no table at all.
- The retry's text inside its new regions reads far better than the first's text there. The share
  of alphabetic words of 3+ letters found in `/usr/share/dict/words` is 0.56–0.80 for the retry
  against 0.12–0.50 for the first.
  - The retry's text is each table's caption and headings, then cells. Page 168 reads "TABLE A92
    EVALUATION DE UNIT S16ATINGS BY DURATION OF SIGHTING, 1950 5 SECONOS. AND LESS…".
  - The first recognition's text there was "O-Baltaca 3Aicuft SCrad, Dues Mlc…".

Recognized words outside table regions over the 62 pages, before layout:

| Policy for a kept retry | Words | Table regions |
| --- | ---: | ---: |
| First recognition alone (before #116) | 20,868 | 41 |
| Retry's lines and tables (tip) | 27,951 | 72 |
| Retry's lines, first recognition's tables | 34,323 | 41 |
| **Retry's lines, retry tables that overlap a first table (chosen)** | **39,326** | **14** |

Keeping the first recognition's tables would still put fewer words on 12 pages than tip (123,
124, 125, 134, 141, 198, 200, 206, 222, 232, 234 and 260). The chosen policy is lower than that
option only on pages 132, 140, 175, 207 and 236, by 3–17 words, where the retry's agreed region is
larger.

Renders of pages 123, 148, 157, 175, 206, 224 and 311 were reviewed. Blue Book pages 121–262
are whole pages of handwritten statistical tables, and page 311 is a rotated IBM-card exhibit.
Every region either recognition reports is part of a genuine table, so the choice is between table
images and noisy text for the same table, not between a table and prose.

### Decision

A retry exists to recover text. Table regions become images whose text does not reflow, and on
these pages Vision's table detection disagrees with itself between two reads of one raster. So a
region counts as a table only when both recognitions report it. The rule is general, not specific
to this book or to inherited text layers:

- a table found only by the retry reflows its recognized text;
- a table found only by the first recognition reflows the retry's text there, the better read;
- a table both found stays an image (the retry's region, which matches its lines).

The page's source reference image is kept on every OCR page by default, so the table's appearance
stays available.

### End to end: Blue Book `--ocr always`

Three converters ran under the same name: baseline, candidate, and candidate with the retry
disabled ("no retry", the first recognition plus the coverage check).

| Run | Retried | Images | Reflowed pages | Output characters | Navigation entries | Seconds | CPU s | Peak RSS | Sampled peak footprint |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| no retry | 0 (61 flagged) | 498 | 310 | 398,761 | 4,354 | 206 | 187 | 488 MiB | 556 MiB |
| tip `a295f33`, run 1 | 61 | 523 | 307 | 441,430 | 7,183 | 351 | 273 | 618 MiB | 441 MiB |
| tip `a295f33`, run 2 (with probe) | 61 | 523 | 307 | 441,430 | — | 295 | 270 | 598 MiB | 468 MiB |
| candidate, run 1 | 61 | 470 | 309 | 499,328 | 9,460 | 300 | 268 | 590 MiB | 477 MiB |
| candidate, run 2 (with probe) | 61 | 470 | 309 | 499,328 | — | 302 | 278 | 591 MiB | 514 MiB |

The same 61 pages were retried in all four retry runs. Run 2 of each passed EPUBCheck, structural
and progress checks with a 1,024 MiB ceiling (the case's 512 MiB ceiling is for default options).
`compare_conversion_runs.py` on run 2 reports:

- changed pages: exactly the 41 below;
- OCR words: 79,846 → 91,381;
- `pagesWithFewerWords`: 41 pages for the baseline, none for the candidate;
- page markers: equal.

It reports `passed: false`, as expected for an intended output change.

Per page, words and images (images include the page reference). The 20 other retried pages (123,
125, 134, 138, 141–143, 159, 166, 169, 171, 190, 194, 206, 227, 242, 244, 246, 260, 311) are
identical at tip and in the candidate: either the retry found no table, or both recognitions
agreed.

| Page | No retry | Tip | Candidate |
| ---: | --- | --- | --- |
| 121 | 242 w, 2 i | 203 w, 3 i | 604 w, 1 i |
| 124 | 236, 2 | 455, 2 | 650, 1 |
| 129 | 346, 1 | 427, 2 | 624, 1 |
| 130 | 320, 1 | 397, 2 | 578, 1 |
| 132 | 268, 2 | 232, 3 | 456, 2 |
| 136 | 221, 2 | 414, 2 | 612, 1 |
| 140 | 261, 2 | 207, 2 | 434, 2 |
| 148 | 284, 1 | **0, 3** | 451, 1 |
| 152 | 246, 3 | 130, 4 | 580, 2 |
| 156 | 366, 2 | 382, 3 | 630, 2 |
| 157 | 280, 3 | 327, 3 | 766, 1 |
| 160 | 375, 2 | 418, 2 | 634, 2 |
| 168 | 536, 1 | 49, 4 | 839, 1 |
| 172 | 475, 1 | 604, 2 | 802, 1 |
| 175 | 266, 2 | **0, 4** | 431, 2 |
| 198 | 221, 2 | 539, 2 | 769, 1 |
| 200 | 344, 2 | 607, 2 | 762, 1 |
| 202 | 389, 2 | 243, 4 | 622, 2 |
| 203 | 351, 2 | 563, 2 | 735, 1 |
| 205 | 252, 1 | 220, 2 | 381, 1 |
| 207 | 408, 2 | 322, 3 | 525, 2 |
| 210 | 401, 2 | 376, 3 | 765, 1 |
| 216 | 244, 3 | 166, 4 | 391, 3 |
| 218 | 403, 3 | 152, 4 | 547, 2 |
| 220 | 311, 1 | 416, 2 | 534, 1 |
| 222 | 216, 2 | 297, 2 | 467, 1 |
| 224 | 69, 3 | 282, 2 | 396, 1 |
| 225 | 306, 1 | 100, 3 | 408, 1 |
| 226 | 249, 1 | 243, 2 | 411, 1 |
| 230 | 508, 1 | 672, 2 | 895, 1 |
| 231 | 351, 2 | 417, 3 | 847, 1 |
| 232 | 264, 3 | 597, 2 | 805, 1 |
| 233 | 378, 2 | 234, 3 | 681, 2 |
| 234 | 360, 2 | 629, 2 | 833, 1 |
| 236 | 323, 2 | 424, 3 | 641, 2 |
| 238 | 234, 3 | 222, 3 | 656, 2 |
| 245 | 439, 2 | 400, 3 | 813, 1 |
| 248 | 482, 1 | 623, 2 | 832, 1 |
| 252 | 442, 1 | 468, 2 | 714, 1 |
| 254 | 336, 2 | 374, 3 | 687, 1 |
| 262 | 322, 1 | 342, 2 | 500, 1 |
| **41 pages** | | **14,173 w, 108 i** | **25,708 w, 55 i** |

On every retried page the candidate has more words than without the retry (+40 to +548). No page
became a page-image fallback in any run.

Other pages:

- Pages 119, 135, 137, 146, 147 and 180–189 differ by one word between the no-retry run and both
  retry runs. That is a printed page number ("137", "171", "179") removed as furniture once the
  retried pages' text shows the numbering. It is a retry effect that tip shares, not this policy.
- Page 188's only reflowed word was its page number, so its reflowed page is lost with the retry
  (310 → 309).

**Tradeoff by page.** The tables on the table-image pages in the per-page table are genuine and fully
legible, and each page keeps its reference image. The tradeoffs differ by group:

- **Pages 148 and 175** (the pages #129 names).
  - Tip reflowed nothing: two and three table images plus the reference.
  - The candidate reflows the tables' captions ("TABLE A58 EEALUATION DE HLL_ SGHTINGS 1952 BY
    SIGHTING…", "TABLE A102 EVALVATION OF ALL SIGHTINGS FOR ALL YEARS BY DURATION OF SIGHTING…"),
    headings and cells, one cell per paragraph with OCR noise ("REL14814179", "DomHul|Total").
  - Page 175 keeps one table image where both recognitions agreed.
- **Pages 140, 152, 168, 202, 207, 216, 218, 225 and 233** (the other pages #116 listed with
  fewer words).
  - Tip turned part of each page's tables into images.
  - The candidate reflows those tables' captions and cells instead: +203 to +790 words over tip,
    and 0–3 fewer images.
  - Pages 140, 152, 202, 207, 216, 218 and 233 keep images of tables both recognitions found.
- **The other 30 changed pages.** The same exchange: one or two table images at tip become
  reflowed cell text. Every page gains words over tip (+114 to +439).
- **Cost everywhere.** The retry's cell text inherits the book's known defect that damaged table
  OCR becomes prose and headings (#7, manifest page 150).
  - Headings on the 61 retried pages: 4,356 at tip, 6,633 in the candidate.
  - Navigation entries: 4,354 (no retry), 7,183 (tip), 9,460 (candidate).
  - A reader gains searchable captions and numbers but loses the tables' grid, except in the
    reference image.

The owner's stated priority is not losing readable text. The retry's captions and headings are
readable, and its numbers are unverified cells, not junk. So the candidate favours text. A client
that wants these pages as table images is better served by fixing #7's table handling than by a
recognition-dependent table choice.

### Default lanes (contracts)

| Case | Content checks (baseline / candidate) | Drift |
| --- | --- | --- |
| `cia-blue-book-14-1955` | 9 pass / 9 pass | none; no OCR pages under defaults; 33 s each |
| `census-rrs2002-01` | 54 pass / 54 pass | none; 19 OCR pages, 5,939 words each, no retries |
| `cdc-zombie-pandemic-2011` | 33 pass / 33 pass | none; 9 OCR pages, 56 words each, no retries |

All six runs passed EPUBCheck and the memory gate with the shared compiled programs. The Blue Book
contracts cover default-option runs only, and `corpus/regressions.json` has no field for converter
options. The policy changes no default-lane output, so no contract changed.

## 2. Time and memory of the retry

### Whole book

From the Blue Book `.always` table above, retry runs against no retry:

- Wall time: 206 s → 295–351 s (candidate 300–302 s), about +46%. CPU: 187 → 268–278 s,
  about +45%.
- Peak RSS: 488 → 590–618 MiB, about +100–130 MiB.
- Sampled peak physical footprint: 556 → 441–514 MiB, so not raised.

Peak RSS is noisy under this load. Two runs with identical recognition differed widely:

- Blue Book `.always` at 458a2e9 and be34d39 peaked at 621 and 515 MiB.
- CDC under defaults peaked at 376 and 268 MiB with identical output.

So a single-run difference of ~100 MiB is at the noise level. `trace_profile.py` on the 458a2e9
run shows resident size climbing through the book (213 MiB on pages 1–20, 615 MiB on 241–260)
while footprint stays at 236–484 MiB. The footprint maximum came at page 119, before any retried
page.

### Where it goes (probe, pages 121–175)

`probe-retry-effects.swift memory` opens pages as the converter does (`PDFPageSource`) and prints
`vmmap --summary` at the end. 26 of the 55 pages were retried under `read`.

| Variant | Seconds | Peak RSS | Peak footprint (vmmap) | IOSurface virtual / regions |
| --- | ---: | ---: | ---: | --- |
| `first`: one recognition plus check | 45–50 | 386–402 MiB | 494–510 MiB | 15.6 MiB / 99 |
| `read`: `OCRReader.read` (retry on flagged pages) | 90 | 450 MiB | 482 MiB | 80.9 MiB / 183 |
| `bands`: both bands on every page (`cropping(to:)`) | 134 | 508 MiB | 501 MiB | 124.7 MiB / 240 |
| `bands-copy`: bands copied into their own bitmaps | 129 | 533 MiB | 486 MiB | 124.7 MiB / 240 |

The retry's extra resident memory tracks the number of IOSurfaces Vision keeps for the band
images. At the end, 122.8 of their 124.7 MiB are empty volatile (purgeable) pages. Peak physical
footprint, which iOS memory limits count, is unchanged.

Repeating one retried page (148) 30 times gave 225 MiB with one recognition and 238 MiB with the
retry. The difference is a one-time step, not per-retry growth.

Why this was not reduced:

- Copying the bands instead of cropping made no difference.
- #116 found `regionOfInterest` no better (463 against 456 MB).
- Equal band heights would not bound the pool: 22 distinct raster heights (1956–1982 rows) occur
  in these 55 pages, so a first recognition already meets a new size on most pages.
- Library code cannot release Vision's buffers.

The remaining lever would be a retry policy change (fewer retries or no retry), which #129 leaves
to the defaults as they are. Device budgets were not measured (#28).

## 3. Raster copies kept alive

### Reproducer (Vision in the loop)

`probe-retry-effects.swift memory`, pages 121–175, recognizes each page and then applies one
operation to the recognized raster:

| Variant | Peak RSS | Live `Malloc Large` at end |
| --- | ---: | --- |
| `first`: direct byte read (converter since #116) | 386–402 MiB | none |
| `first-draw`: draw into an 8-bit gray bitmap context | 576 MiB | 32 regions, 189.1 MiB virtual, 79.4 resident |
| `first-draw-proxy`: draw a `CGImage` made on the same data provider | 576 MiB | 32 regions, 203.9 MiB |
| `first-draw-pool`: the draw inside `autoreleasepool` | 575 MiB | 32 regions, 209.2 MiB |
| `first-vimage`: `vImageBuffer_InitWithCGImage` to 8-bit gray | 415 MiB | none |

This is #116's +190 MB. The retained memory is not attached to the image, since a proxy image
retains the same, and it is not autoreleased. The count is capped at 32.

### Without Vision

`probe-raster-copies.swift`: 55 pages, rasters released after each page.

- `draw`, `draw-proxy` and `bgra-draw` each leave 32 live `Malloc Large` regions (184.9 MiB
  virtual, not resident when idle). So do `draw-buffer` and `bgra-draw-buffer`, which draw exactly
  as the removed fallback did, into a white-filled gray context over a caller-owned buffer.
- `none`, `gray` (the direct read), `vimage` and `bgra-gray` (the new fallback on a byte-swapped
  BGRA raster) leave none.

So Core Graphics holds on to buffers from drawing an image into a new bitmap context, whether or
not Vision read the image. Under Vision, those buffers stayed 79–134 MiB resident.

A second check held 20 rasters and read them directly (`HOLD=1`, `gray`):

- Footprint rose by the rasters' own size, because `CG Raster Data` went from 640 KiB to
  229.8 MiB resident.
- No new region appeared, so the direct read makes no copy. Vision's own read touches the same
  pages.

### Fix

`OCRTextCoverage.GrayRaster` still reads 8-bit RGBA bytes directly. Other layouts (the test's gray
image, BGRA, alpha-first, 16-bit) were drawn into a gray context; they are now converted with
`vImageBuffer_InitWithCGImage` into the raster's own buffer, flattened over white.

`coverageReadsOtherPixelFormatsLikeTheConvertersRaster` adds black text on a transparent,
alpha-first little-endian raster. It must measure like the converter's raster, and it fails with 4
issues when the conversion flattens over black instead. The converter itself only produces RGBA,
so the fix changes no conversion output (default lanes above).

### Other raster code

- `PageRasterizer.image` draws the PDF page and annotations into an RGBA context and hands its
  buffer to `makeImage()`. The `none` variant shows no live `Malloc Large`, only allocator free
  lists (`Malloc Large (empty)` 69.6 MiB after 55 pages; footprint grew 75 MiB after 5 pages and
  141 MiB after 55).
- `PageRasterizer.encode`/`write` use ImageIO. The retry's `cropping(to:)` bands cost the same as
  copied bands (table in section 2).
- No other library source draws an image.
- Tests draw images into caller-owned buffers (`PageRasterizerTests`, `ShadingTests`,
  `PreservedRegionTests`) or scale a small image into a `data: nil` context (`OCRLanguageTests`).
  These are short-lived test processes, so there is nothing to fix.
- `tools/probe-raster-sweep.swift` decodes with ImageIO.

## 4. Documented build commands

Each command was compiled at the candidate tree:

| Command | Result |
| --- | --- |
| `ocr-language-correction/probe-language-correction.swift` header, old | fails: cannot find 'OCRTextCoverage' in scope |
| same, updated (adds `OCRTextCoverage.swift`) | compiles |
| `ocr-headings/record.md` `capture-ocr-layout-fixture` command, old | fails: same error |
| same, updated | compiles |
| `ocr-text-loss/probe-ocr-lines.swift`, `probe-retry.swift`, `replay-coverage.swift` headers | compile |
| `ocr-location/probe-page-ocr.swift` header (no `OCRReader`) | compiles |
| `probe-retry-effects.swift`, `probe-raster-copies.swift` headers (this record) | compile |

`ocr-language-correction/record.md`'s file list notes the addition. `ocr-headings/collect.py`
names `OCRReader.swift` only to hash it.

## Limitations

- **Scope.** One book exercises the policy: Blue Book, 61 retried pages, all tables. Warren's
  retried pages (#116) had no table regions and were not rerun. On a page mixing prose with a real
  table found by only one recognition, that table will reflow as text.
- **Retry variance.** Which pages are retried can vary between processes sharing one compile.
  With the same programs, the be34d39 run also retried pages 6 and 111 (63 pages), and the dump
  probe retried 111. Every run compared here retried the same 61.
- **Memory.** Figures are Mac RSS and footprint under heavy shared load, with no device run.
- **Heading and navigation noise.** Table cells becoming headings is not addressed (#7).

## Defects noted for filing

1. **Scanned statistical tables reflow as headings and navigation entries.** On Blue Book
   `.always`, the retried table pages carry 6,633 headings and the book 9,460 navigation entries
   (4,354 without the retry). This extends #7 now that the retry recovers the table text.
2. **Retry decisions vary between processes with identical compiled programs.** Pages 6 and 111
   were retried in some Blue Book runs and not others. This is worth adding to #94: sharing a
   compile does not fix borderline coverage verdicts.
3. **Peak RSS varies by ~100 MiB between identical conversions under load.** Blue Book `.always`
   peaked at 515 and 621 MiB; CDC defaults at 268 and 376 MiB. Memory gates near a case's peak can
   flap on a shared machine.
4. **Core Graphics keeps up to 32 buffers after drawing an image into a new bitmap context.** This
   happens with or without Vision, through proxy images and autorelease pools. It may be worth an
   Apple Feedback report; the library no longer draws in the OCR path.
5. **Vision keeps IOSurface buffers per band image.** About 110 MiB, purgeable, which raises RSS
   but not footprint. Device impact is unmeasured (#28).

## Files

- `probe-retry-effects.swift`: recognition dumps (`dump`) and memory variants (`memory`) with the
  library's recognition code.
- `probe-raster-copies.swift`: raster operations without Vision.
- `table_regions.py`, `policy_words.py`: table agreement and policy word counts from a dump.
- `page_table.py`: per-page EPUB words and images of two evaluations.
- `trace_profile.py`: resident and footprint profile of an evaluation's memory samples.

Dumps, EPUBs, renders, probe binaries and the `pdf-reflow-i129` model cache were deleted after
recording.
