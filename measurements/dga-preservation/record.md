# Born-digital illustrated pages: review signal, callouts, bands and icons (#117)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, Xcode 27.0, release CLI. Work began on
`e949bea` and was carried to `9803329`, `458a2e9`, `be34d39`, `a295f33`, `0fa3057`, `bfe0476` and `277cbde` by
fast-forwarding each tip and reapplying the uncommitted patch (it applied cleanly through `bfe0476`; at `277cbde`
the README paragraph and the extraction closure's return, which now hands back `graphics`, were merged by hand).
Diagnosis ran on `e949bea`–`458a2e9`; the surveys, scans and first lanes on `458a2e9`–`a295f33`; the mutation
run on `a295f33`; the full control lanes and page review on `0fa3057`. The cost bounds (see Cost) were added on
`bfe0476`; the gates and the DGA, NBS, FAA, Fed and CDC lanes were then rerun against an unmodified `277cbde`.

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline | `0fa3057` | `8377a379…` |
| candidate (reviewed, unbounded) | `0fa3057` plus this change | `4bbb9919…` |
| baseline | `277cbde` | `666bd3be…` |
| candidate (bounded) | `277cbde` plus this change | `972d3799…` |

Corpus: `dga-2025-2030` (`c34f1bec…`); controls `cdc-zombie-pandemic-2011`, `cia-blue-book-14-1955`,
`nbs-jres-geltman-1977`, `gpo-our-flag-2003`, `faa-phak-8083-25c` and `fed-explained-2021`. No PDF or EPUB is
committed. Tools in [`tools/`](tools/) ran from a scratch directory; paths inside them are those of the run.

## State on the tip before the change

EPUB words per page between page markers (`tools/pagedump.py`, the e949bea record's `pagediff.py` counting);
the issue's pdftotext counts differ in method.

| Page | Words | Images | Warnings | Problem |
| --- | --- | --- | --- | --- |
| 1 | 16 | 1 (reference) | unverifiedTextLayer | full-page cluster |
| 2 | 457 | 3 | — | header title and welcome line in the header crop; footnotes 2 and 4 in the footer crop |
| 3, 4, 5 | 274, 255, 263 | 1 (reference) each | unverifiedTextLayer | page-sized cluster (94–100%) |
| 6 | 53 | 3 | — | Limit Alcoholic Beverages title, first bullet row and the Sodium callout in crops |
| 7, 9, 10 | unchanged | | — | the two-column bullets already read whole since `e949bea` (#111 column join, band rule) |
| 8 | 167 | 5 | — | the infant-feeding callout and its title in a crop |

## Diagnosis

`tools/survey.swift` (the library compiled with a paint-kind tag on `GraphicsReader.Paint`) lists every page with a
painted region over 75% and native lines, with the largest single paint and image coverage
([`survey/`](survey/)). `tools/diag.swift` prints a page's paints, composed graphics, crops and the lines each
takes; `tools/instrument.py` traced `ordered()`'s branches.

| Book | Pages on the path | What the page-sized region is |
| --- | --- | --- |
| Blue Book | 312 | one image covering the page, invisible text |
| NBS | 7 | one image, invisible text (1–6 also unsupported) |
| CDC | 33 | one image covering the page, visible text |
| Our Flag | 2 | one image (99.8%, 100%) |
| FAA | 18 | one image covering the page |
| Fed | 8 | one image (chapter openers) or one full-page rectangle tint (page 4) |
| NOAA | 64 | mostly one image; 13 pages are photos and charts clustering to 75–95% with no paint over 49% |
| DGA 1 | 1 | a full-page cream fill (non-rectangle path) under 45 small images and outlined lettering |
| DGA 3, 4, 5 | 3 | 31–45 paints; largest 9–18% of the page, images at most 4.7% |

- **Pages 3–5.** A 4-pt vertical timeline stroked in the left margin (x 64–68) runs from the footer band through
  each section's circular photo icon; each icon abuts its section's gradient title band (3.5 pt apart); `clusters`
  grows hulls, so once the hull spans the page every other paint (the `Gut Health`/`Added Sugars` callout) joins.
  The pipeline read the 94–100% region as a picture of the page.
- **Pages 3, 5, 6, 8 callouts.** Each is an `/Artifact` transparency-group form filling a rounded rectangle, plus
  a tab holding the title. `TintDetector` only admits rectangle-only paths (`frame`), so the box seeded a crop
  and took its prose (page 6: 9 lines, 86 words; page 8: 11 lines, 126 words).
- **Page 6 top.** Banner photo, icon, a 21-pt connector stroke from the icon to the banner and the title band
  clustered into `[0 676.6 612 792]`; expansion took the title and the first bullet row of both columns. The
  band rule of `e949bea` never saw the band alone.
- **Page 5 title.** Two stacked 18-pt title lines on one band; the band rule accepts one title line.
- **Page 1 (kept).** The visible title and labels are filled outlines over a full-page fill; the extracted text is
  a Type3 font whose CharProcs contain only `d1` (glyph metrics, no painting). That is an inherited transcription
  laid over art, and the reviewed contract's warning is right. It stays on the path through the single
  full-page paint; an undrawn-Type3 detector was built, confirmed page 1, and removed as redundant.
- **Page 2 header (not changed).** `Message from the Secretaries` is set on a dark tab painted over the header
  photograph, above a light band holding the welcome line. A rectangular crop containing the whole photograph
  contains the title; freeing it needs a policy for text painted over a photo (defect 1).
- **Page 2 footnotes.** Link underlines 4 pt tall sit 2 pt above the footer band, joining footnotes 2 and 4 to it.
- **Reading order with icons.** Once pages 3–5 reflow beside their icons, each 62-pt icon reaches past its 24-pt
  title into the last line of the section above and the first bullets below, closing the whitespace cuts; page 4's
  columns interleaved (`- Vegetables` / `+ If preferred` / `- Fruits`) and page 5's title split around its icon.

## Change

No public API, option, default or warning code changed.

- **`GraphicsReader`**: `Paint` gains `image` (image XObject footprints) and `filled` (paths painted by `f`, `F`,
  `f*`, `B`, `B*`, `b`, `b*`).
- **`PDFReflowLibPipeline.layoutComesApart`**: a page-sized region still marks image-backed text when the page
  requires its image, any text is invisible, or one paint covers over 75% of the page; otherwise only when the
  page's own crops (`graphicsWithLabels` of the composed page) cover over 75% of it or take more than a tenth of
  its words. OCR selection shares the same signal as before.
- **`TintDetector.compose`**, three rules before clustering:
  - *Shape backdrops*: a filled non-rectangle, non-image shape holding no other paint is a tint candidate on the
    existing prose evidence (≥3 prose lines, a third of those inside); a filled shape touching such a box and
    holding only lines that fit inside it is its tab.
  - *`withoutTitleBackdrops`*: each non-rectangle, non-image vector paint, with the non-image paints it touches
    inside its own height, is judged by `titleArt(…, stacked: true)` and removed or trimmed; rows inside another
    paint (a boxed figure's title bar) are not judged.
  - *`seedClusters`*: a thin rule more than two bodies from every line, or a horizontal rule underlining exactly
    one line, is dropped from a cluster whose hull meets at least two prose lines no other part meets.
- **`LayoutReconstructor`**: `titleArt` is internal and takes `stacked` (one title wrapped onto stacked lines of one
  size and left edge, per-paint only; the cluster rule is unchanged). In `blocks`, a text-free region within two
  bodies left of a heading-size line whose middle it spans, no taller than three such lines, is ordered at that
  line's height; `trailingHeading` (#103) keeps such an icon with its heading.
- Tests: `IllustratedPageTests.swift` (17 tests, 21 cases), six `dga-*-illustrated` fixtures, the fixture decoder
  and `tools/capture-layout-fixture.swift` record `image`/`filled`; `sectionBandsKeepOnlyTheirPartBesideTheTitle`
  reads untrimmed bands from the reader's regions. Docs: README, `doc/architecture.md`, `doc/regression-testing.md`.

A rectangle-union helper that served the rejected image-coverage signal was removed after the lanes; the rebuilt
candidate's DGA EPUB is byte-identical to the lane candidate's with pinned identifiers (see Tests).

### Designs measured and rejected

- **Image coverage** (page-sized only when images cover 75%): Fed page 4's colophon (a full-page rectangle tint)
  lost all 115 words to a crop, and on a NOAA pages 1–80 excerpt (`tools/excerpt.swift`) 16 pages lost 21–100% of
  their words. **Adding the single-paint test** fixed Fed; NOAA still lost text.
- **Composed seeds under 75%**: 9 NOAA pages still lost text through label expansion (page 49: 342 → 0 words).
  The crop-outcome test leaves the excerpt byte-identical.
- **Relaxing #103's `headingRow`** (grazing lines, icon-led rows): fixed page 5 but split page 4's columns across
  sections and page 3's section 2; reverted in favour of the icon's reading rectangle.
- **Callout shapes without the fill and holds-only-text guards**: FAA's synthetic unclipped streamlines (stroked)
  and Fed page 130's boxed map (its title bar and description reflowed and `development programs.` was cut in the
  crop) regressed; both guards added. The per-paint title rule also first dropped the Fed table title bands
  (frames), hence the frame and containment exclusions.

## Before and after (`0fa3057` → candidate)

`tools/lane.sh <case> <label>` (`run_corpus_regressions.py` with EPUBCheck, the environment probe and the memory gate,
one case per call), then `tools/cmp.py` (`compare_conversion_runs.py --allow-different-converters` and a block diff).
Summaries and comparisons are in [lane/0fa3057/](lane/0fa3057/).

| Case | Contract | Changed pages | Warnings (base → cand) | Peak RSS (base → cand) |
| --- | --- | --- | --- | --- |
| dga-2025-2030 | base fails 17 (exactly the new checks), cand passes 78 | 2, 3, 4, 5, 6, 8 | unverifiedTextLayer 4 → 1; structureFallback 8 → 9 (page 8's callout reflows) | 107 → 104 MB |
| cdc-zombie-pandemic-2011 | both pass 33 | none (strict comparison passes) | identical, unverifiedTextLayer 33 | 395 → 388 MB |
| cia-blue-book-14-1955 | both pass 9 | none | identical, 312 | 166 → 256, rerun 188 MB (limit 512; variance, no new work on these pages) |
| nbs-jres-geltman-1977 | both pass 17 | none | identical, 1 | 266 → 266 MB |
| gpo-our-flag-2003 | both pass 72 | none | identical, 2 | 102 → 107 MB |
| faa-phak-8083-25c | both pass 487 | none (no changed image bytes) | identical, 18 | 823 → 816 MB |
| fed-explained-2021 | both pass 166 | none | identical, 8 | 297 → 299 MB |

The `a295f33` lanes (same results) are superseded. Rerun on `277cbde` with the bounded build
([lane/](lane/) holds these summaries):

| Case | Contract | Changed pages | Warnings | Peak RSS (base → cand) |
| --- | --- | --- | --- | --- |
| dga-2025-2030 | base fails the same 17, cand passes 78 | 2, 3, 4, 5, 6, 8; block diff byte-identical to the `0fa3057` review | as above | 108 → 104 MB |
| nbs-jres-geltman-1977 | both pass 52 | none, no changed image bytes (Figures 1–5 and the equation crops of #37 unchanged) | identical, unverifiedTextLayer 7 | 274 → 276 MB |
| faa-phak-8083-25c | both pass 487 | none | identical | 836 → 866 MB |
| fed-explained-2021 | both pass 167 | none | identical | 302 → 305 MB |
| cdc-zombie-pandemic-2011 | both pass 33 | none | identical | 395 → 398 MB |

`277cbde` also records inline images (`BI … EI`) as paints; they are marked `image`, so no title-backdrop or
callout rule can judge or remove them.

DGA per page after the change:

| Page | Words | Images | Warnings |
| --- | --- | --- | --- |
| 1 | 16 | 1 (reference) | unverifiedTextLayer (kept) |
| 2 | 461 (footnotes 2 and 4) | 3 | — |
| 3 | 274 | 5: banner, three icons, footer; no reference | none |
| 4 | 255 | 5: banner, three icons, footer | none |
| 5 | 263 | 3: banner, icon, footer | none |
| 6 | 154 | 3 | — |
| 8 | 293 | 4 (callout crop gone) | structureFallback (layout-stage list notice) |

**Hand review** against 60-dpi `pdftoppm` renders and a contact sheet of every changed crop (`tools/sheet.py`):
every icon crop holds its whole circular photo (the nubs at its edges are the timeline and band connector stubs),
the banners and footers are unchanged, page 8's band remainders are `e949bea`'s. Page 3 reads banner, then per
section icon, title, both columns' bullets, and the `Gut Health` tab title with its paragraph; page 4 its three
sections in column order with `+ If preferred, flavor with salt, spices, and herbs.` whole; page 5 its two-line
title as one heading, both columns, `Added Sugars` and its three bullets; page 6 the title, both bullets (the
second joined across its columns), `Sodium`, its bullets and three age items; page 8 `Introducing Food to Infants
& Toddlers`, its two bullets and seven sub-items before `Middle Childhood`; page 2's footnotes follow 1 and 3.

**Other books** (`--ocr never`, base against candidate at `458a2e9`–`a295f33`): Wallace algebra, 9/11, Loper
Bright, arXiv, USGS copper, RRS and a Warren pages 1–30 excerpt are byte-identical; Blue Book and CDC byte-identical;
NOAA pages 1–80 excerpt byte-identical with the final rule. The Arabic USCIS M-618 changed page 53 (a crop now
reflows a heading and three paragraphs); it is outside this English-only review and was not assessed.

## Tests and contracts

- `swift test`: 641 pass on `277cbde` (624 plus 17). `scripts/check-all.sh --fast`: exit 0 (641 Swift, 217 Python,
  fixture and 13 policy conversions with 22 rejection/cleanup cases, repeat-run identity). The contracts hold 1,599
  checks on 363 pages of 15 documents (1,576 at `277cbde`, counted with `tools/countchecks.py`, which mirrors
  `check_corpus_content.assess` and reproduces each lane's count); README and `doc/regression-testing.md` updated.
- Mutations ([mutants.log](mutants.log), `tools/mutate.py`, on `a295f33`): 23 of 24 single-guard mutations fail at
  least one test. Two survived the first pass (the page-sized-crop and word-share guards, which every control
  tripped together) until `aLayoutComesApartOnlyWhenItsCropsLeaveTheText` isolated them; the reader's image flag
  survived until `readerMarksImagesAndFills`. The icon distance guard survives: on DGA-like pages any icon more than
  1.5 bodies from its title is already set apart by the column cut (moved 8–30 pt, the icons read at the page top
  either way), so it only bounds regions the cut cannot divide.
- Contract (`tools/addcontract.py`): pages 3–5 absent `unverifiedTextLayer`, preserved images (4, 4, 2) and
  headings; page 4's whole bullet; page 6 headings, first bullets and age items; page 8 heading, bullet and
  sub-item; page 2 footnotes 2 and 4; the basis explains page 1's retained warning. The CDC page 5 warning
  contract is unchanged and passes. Negative control: the baseline EPUB fails exactly the 17 new checks.

## Cost

The reviewed rules scanned paints quadratically or worse: `withoutTitleBackdrops` filtered every paint for each
candidate's row and then scanned every paint again for a containing box; `seedClusters` filtered every seed per
hull and tested membership by value; `shapeBackdrops` scanned every paint per filled shape. `compose` runs on
every supported page.

**Survey** (`tools/paintcount.swift`, every page of each English book, the reader's paints): FAA peaks at 10,000
(page 448, over the operator budget, so never composed), 5,130 (226), 4,136 (67), 3,763 (288) and ~2,100 (393, 181,
286, 87) with 315–2,084 non-rectangle vector candidates; NOAA 10,000 on page 1834 (also over budget) and at most 214
elsewhere; Our Flag 1,247 (page 48); Fed 857 (page 67); Wallace 354; DGA 106 (candidates at most 25); USGS 13; CDC 1.

**Composition time per page** (release, `tools/parts.swift`), 0fa3057 → reviewed → bounded:

| Page | Paints | compose |
| --- | --- | --- |
| FAA 448 | 10,000 | 1 ms → 144 ms (title backdrops 60, seedClusters 81) → 10 ms |
| FAA 226 | 5,130 | 2 ms → 109 ms → 6 ms |
| FAA 67 | 4,136 | 1 ms → 92 ms → 1 ms |
| FAA 288 | 3,763 | 1 ms → 34 ms → 3 ms |
| NOAA 1834 | 10,000 | 91 ms → 247 ms → 90 ms (the 91 ms is pre-existing composition) |

**Synthetic worst case** (`tools/stress.swift`, the unit test's page scaled): overlapping filled marks with a title
band take 20 ms, 80 ms, 331 ms and 1.96 s at 1,006, 2,011, 4,021 and 9,901 marks unbounded, and at most 1 ms
bounded; 600–9,600 isolated strokes take 2–26 ms in `seedClusters` either way, dominated by `clusters` itself.

**Whole conversions** (`tools/timing.py`, `--ocr never`, base `bfe0476` / bounded / unbounded back to back, minimum
of two alternating rounds; excerpts built with `tools/pick.swift`): DGA 0.70 / 0.55 / 0.55 s (three fewer page
references); FAA 45.9 / 41.7 / 44.3 s; Fed 6.82 / 6.80 / 6.62 s; Wallace 20.7 / 20.4 / 21.1 s; Our Flag 1.39 /
1.31 / 1.36 s; USGS 0.16 s each; CDC 6.10 / 6.01 / 6.03 s; FAA's eight densest pages 2.39 / 2.43 / 2.71 s; NOAA's six
densest pages 0.60 s each; NOAA pages 1–80 9.9 / 9.6 / 9.4 s; Fed pages 67, 39, 59 and 130 0.23 s each. Differences
other than the FAA dense-page excerpt are within this loaded machine's run-to-run spread.

**Bounds** (DGA byte-identical before and after, and the lanes above unchanged):

- `withoutTitleBackdrops` returns the paints unchanged above `titleBackdropCandidateLimit` = 500 non-rectangle,
  non-image candidates (DGA's densest page has 25; FAA's pages over 500 never changed under the rule). A paint is
  judged only when a title-size line reaches into its height ±2 pt (the row's hull lies there, and `titleArt` needs
  such a line); its row comes from the paints sorted by lower edge with a binary search; row membership is a `Set`.
- `seedClusters` finds the page's prose and qualifying rules once and returns the plain clustering when either is
  missing; maps rules to hulls only when rules × hulls ≤ `seedClusterWorkLimit` (2,000,000), examines only
  rule-bearing hulls when their count × seeds is within the same limit, and tracks dropped seeds by index.
- `shapeBackdrops` checks a shape's prose evidence before scanning every paint for art inside it.

`vectorDensePagesStayBoundedAndKeepTheirClustering` checks 4,021 marks and 2,400 strokes against the reader's
clustering within 3 s (0.23 s in a debug build); with the candidate limit raised to `Int.max` the unchanged-paints
and clustering expectations fail. The two work limits change cost only, not output, so they are checked by the
timings above rather than by a failing expectation.

## Remaining gaps

- Page 1 keeps its reference and warning by design (see diagnosis).
- Page 2's title and welcome line stay in the header crop (defect 1).
- Page 2's footnotes read 1, 3, 2, 4: two columns of notes are read in rows (defect 2).
- The review signal's exemption is outcome-based: a born-digital page whose crops still hold more than a tenth of
  its words (NOAA's photo spreads) keeps the reference rather than reflowing partially.

## Defects to file

1. **Text painted over a photograph stays in its crop.** DGA page 2 sets `Message from the Secretaries` on a tab
   over the header photo and the welcome line on a band beneath it; both are inside the preserved header image
   and absent from the text. Expected: the title as a heading and the welcome line as prose, with the photograph
   preserved (a text-over-image policy; paint order is not in the page model, e949bea defect 3).
2. **Two columns of footnotes read row by row.** DGA page 2's notes 1 and 3 (left) and 2 and 4 (right) reflow as
   1, 3, 2, 4. Expected: 1, 2, 3, 4 (column order or note-number order).
3. **NOAA photo-and-chart pages keep the review signal.** 13 NOAA pages cluster photographs and charts into a
   page-sized region with no single paint over half the page; their crops would hold most of the text, so they
   keep the reference and warning. Expected: reflowed text beside preserved figures once crop bounds separate
   their labels from body prose.
