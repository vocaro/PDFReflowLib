# Image-only pages (#176): a page whose writing is drawn, and ink measured against the page's own background

Tier: deterministic Apple PDF/OCR stack, macOS 27.0 (26A428) arm64, Xcode 27.0 (27A266a), release
CLI, host terminal, library defaults unless stated. Date 2026-09-17. Built on `32c1f43` merged into
this branch: baseline CLI `11c50c31…8815` from `32c1f43`, candidate CLI `7d396fed…8269` (the deck and the
Swift gates; the other nineteen cases were compared against `8063df77…78aa`, which differs only in
the wording of one warning no corpus page reaches and in comments). Both run
under the name `pdf-reflow`, and every comparison below used one Vision compile
(`22614cb0…086d`, reported `sameVisionPrograms: true`, #94).

**Result.** Slide 5 of the Earthdata deck draws its only sentence as vector outlines; its text layer
holds the folio `5` and nothing else, so before this change the slide reflowed no text at all and
nothing said so. A page whose text layer holds **no letter** now counts as a page with no text
layer: it is rendered, and when at least two rows of text-shaped ink stand outside that layer and
outside the page's pictures, every automatic policy recognizes it. Slide 5's question,
*How do we support user analysis of very large data volumes?*, now reaches the reading text. Across
the 23 corpus books (5,145 pages in the 21 English ones), 60 pages hold a letter-less text layer,
43 of them are rendered, and exactly one — slide 5 — is recognized. Twenty-one of the twenty-two
corpus cases were run against the `32c1f43` baseline: only the deck changes, and only on page 5.

The ink measurement `OCRTextCoverage` counts components *darker* than an ink threshold, which is
blind to a slide printed white on dark blue (found by #164). It now reads ink against the page's own
background: when a measurement finds no text row at all and the darker side covers more than half
the page, the darker side is the background and the page is measured again inverted. A page whose
dark ink already forms rows is never inverted, so nothing the measurement can read today changes.

## Rule

Implemented in `Sources/PDFReflowLib/TextLayerPlausibility.swift` (`reflowsNoWords`,
`carriesDrawnText`, `judgeImageOnly`, `measureInk(excluding:)`), called from `extractPage` beside
the #93 judgment, and in `OCRTextCoverage.measure` / `GrayRaster.inkIsBackground`.

1. **The page reflows no word of its own.** Its text layer, after hidden-text removal, holds no
   letter: nothing, a folio (`5`, `4-10`), or bare symbols. A page with no text at all is already
   recognized under every automatic policy, and a folio, which furniture removal takes away, does
   not make the page any less text-less. A page holding one word is never rendered.
2. **Its art carries writing.** The page is rendered at 180 DPI (`TextLayerPlausibility.inkTestDPI`,
   independent of the client's `rasterDPI`) and its text-shaped ink found as in #93, ignoring every
   placed image and inline image. At least `minimumImageOnlyRows` = **2** rows must lie outside the
   layer's lines.

Pages already flagged `damagedTextEncoding`, pages that require a page image, pages whose text is
over a page-sized graphic (#93's question) and books not declared English are not judged. Every
automatic policy (`.automatic`, `.automaticIncludingImageBackedText`,
`.automaticKeepingImageBackedText`) recognizes a page that passes; `.never` does not, and `.always`
recognized it already. When recognition of such a page reads nothing, the page is left exactly as it
was extracted — with its crops, not as one page-sized image — and reports `ocrFailed`: "This page
reflows no text of its own and its artwork holds writing, but recognition of the page failed or found
no text; the artwork is preserved as images and its writing does not reflow."

### Why the pictures are set aside

The first rule counted every text-shaped row on the page, and the Arabic civics cards then
recognized two pages. Page 62 is a photograph of children at a blackboard, whose chalked
`TODAY'S LESSON: MATH` and sums read as four rows; page 88 is a photograph of Mount Rushmore, whose
strata and treeline read as seven. Neither is writing the page set, both already have a crop that
preserves them, and recognizing either replaced that crop with a page image and put the picture's
lettering into the reading order. Writing a page draws is content its producer typeset; writing
inside a picture belongs to the picture. With images excluded, every letter-less page in the corpus
reads **0** uncovered rows except slide 5, which reads 2.

### Why two rows

One row of ink outside the layer is a figure's label, an axis or a caption, which the figure's own
crop carries; recognizing the page on that evidence would trade every crop for a page image. Two
rows are a sentence the page never reflowed. Slide 5 reads 3 rows at 180 DPI before images are
excluded and 2 after (the third is the NASA insignia's wordmark). No other English page reaches 1.
Slide 5 is the only page the corpus constrains, and it constrains the threshold tightly: at 1 the
rule would still recognize nothing else in the corpus, and at 3 the deck's question would be lost
again.

## Ink polarity

`OCRTextCoverage.GrayRaster.inkIsBackground()` is true when more than half the page's pixels are
darker than `inkThreshold()`. `measure` re-measures an inverted copy only when the first measurement
found **no** text row, which is what makes the change safe: a page whose dark ink already forms rows
keeps exactly the reading it had.

At 72 DPI, 114 of the 5,145 English pages have more than half their pixels below the threshold, and
30 of those also find no text row as printed — the set that inverts. Their inverted readings are small:
the largest is NOAA page 1 (7 rows, 6 uncovered) and the CDC comic's pages 1, 13, 15 and 36 and
Warren page 1 (1–3 uncovered each), all below #93's seven-row bound and #116's eight. At the 180 DPI
the ink test actually uses, most of them are not inverted at all: NOAA 1 finds 3 rows as printed,
CDC 1 four, CDC 37 four, CDC 39 two, CDC 42 one. A plain majority-dark rule *without* the
no-row condition would have been unsafe: CDC page 27's uncovered rows would go 4 → 19 and page 32's
2 → 16, because a comic page is dark artwork on white paper, not white writing on a dark ground.

The candidate readings tried and rejected as the polarity signal, over the same survey (columns in
`survey-pages.swift`): the modal luminance over 16-wide bins, the median luminance, the dark share
of the page's outer 2% border ring, and the largest dark component's share of the page. None
separates the Earthdata slides (modal 72, the blue backdrop) from the CDC comic (modal 8–248 across
its pages) or the Fed's full-bleed chapter photographs (modal 56–104, 0.97–0.98 dark) with any
margin. "No row was found" is a better question than "which side is darker", because it asks
whether the reading failed rather than guessing at the page's design.

## Tools

- `survey-pages.swift` walks every page of one PDF, repeats the pipeline's extraction up to the OCR
  decision, and records the layer's letters, the page's ink threshold and dark share, the four
  rejected background readings, and `OCRTextCoverage` as rendered, inverted, and as the library
  reads it (background-corrected and ignoring placed images). Every page is measured at 72 DPI; a
  page whose layer holds no letter is also measured at 180 DPI. It compiles the library's own
  sources, so it moves with them.
- `survey-all.sh <dir> [book ...]` builds it and surveys all 23 corpus books (0–292 s per book,
  Warren the slowest; about 10 minutes in total).
- `summarize.py <dir> [tsv]` prints the table below and writes
  [letterless-pages.tsv](letterless-pages.tsv), one row per rendered letter-less page.

## Survey

Letter-less text layers per book, with what the 180 DPI ink test reads there. Books with none —
NOAA, the Blue Book, Census, DGA, USGS, Replay Clocks, Loper Bright, the pro se complaint, the three
NASA papers, *AgResearch* and the Chinese publication — are omitted. *Rendered* excludes blank pages,
which are never rendered.

| Book | Letter-less | Rendered | Rows outside the layer, ignoring pictures | Recognized |
| --- | ---: | ---: | --- | ---: |
| Warren | 11 | 11 | 0 on every page | 0 |
| CDC comic | 9 | 9 | 0 on every page (13, 15, 17 and 36 read 3–9 rows inside the comic's own scans) | 0 |
| FAA | 7 | 7 | 0 on every page (whole-page figures under a section folio) | 0 |
| Arabic civics cards | 11 | 8 | 0 on every page (62 and 88 read 4 and 7 rows inside their photographs) | 0 |
| *Algebra* | 4 | 4 | 0: pages 309 and 439 are answer keys of bare fractions and surds, whose 3 and 39 rows the layer covers | 0 |
| Our Flag | 2 | 2 | 0 | 0 |
| Fed Explained | 7 | 1 | 0 (six are blank) | 0 |
| 9/11 | 8 | 0 | all blank | 0 |
| Earthdata deck | 1 | 1 | **2 (slide 5)** | 1 |
| **Total** | **60** | **43** | | **1** |

The negative controls the corpus supplies are worth naming: *Algebra* 439 holds 169 lines and no
letter, and its 39 rows of ink are exactly the rows its layer already reflows; FAA 97, 244, 256,
310, 375, 387 and 452 are whole-page figures whose only text is a section folio, and their art forms
no glyph row at all.

## Review of the one changed page

Slide 5, read against a 100 DPI Poppler render. The slide paints a dark blue full-bleed background,
the NASA insignia (an image), the folio `5`, and the question in white italic outlines with no text
layer. Before: two crops (the insignia and the question's artwork, the latter clipping the second
line), no text, `furnitureRemoved` and `imageRegion`. After: `ocrUsed`, the question as a paragraph
reading exactly `How do we support user analysis of very large data volumes?`, and the source-page
reference recognition attaches, which carries both the artwork and the insignia. Wrong now, and not
pinned: recognition also reads the insignia's `NASA` wordmark and ranks it as an `h2` above the
question, the same OCR heading noise as the CDC comic's sound effects (#18). Heading levels
elsewhere in the deck are unchanged; only the document-wide heading *ordinals* shift, because one
heading joined the book.

## Default-lane comparison

`tools/run_corpus_regressions.py`, one case per call, with the capability probe
(`--environment-probe .build/raster-environment/probe --execution-context host-terminal`) and both
CLIs; `tools/compare_conversion_runs.py --allow-different-converters`.

| Case | Contract | Changed pages | Notes |
| --- | --- | --- | --- |
| Earthdata deck | pass (225 checks) | 5, plus heading ordinals on 6–21 | `recognizedPageCount` 0 → 1, `reflowedPageCount` 20 → 21, `imageCount` 22 → 21 (two crops become one source-page image); `ocrUsed` on 5, one fewer `furnitureRemoved` |
| CDC comic | pass | 0 | `recognizedPageCount` 36, 27 `implausibleTextLayer`, unchanged |
| Blue Book | pass | 0 | 312 `unverifiedTextLayer`, unchanged |
| Census | pass | 0 | 17 OCR pages, unchanged |
| NBS | pass | 0 | |
| DGA | pass | 0 | |
| FAA | pass | 0 | the seven folio-only figure pages are rendered and left alone |
| Fed Explained | pass | 0 | the seven full-bleed chapter photographs are unchanged |
| Our Flag | pass | 0 | |
| *Algebra* | pass | 0 | pages 309 and 439 are rendered and left alone |
| Arabic civics cards | pass | 0 | pages 62 and 88 are rendered and left alone |
| Chinese publication | pass | 0 | |
| 9/11 | pass | 0 | |
| Loper Bright | pass | 0 | |
| USGS | pass | 0 | |
| Replay Clocks | pass | 0 | |
| Pro se complaint | pass | 0 | |
| NASA GWL, DASC, TechPort | pass | 0 | |
| *AgResearch* | pass | 0 | |
| NOAA NCA5 | pass | 0 | 1,834 pages, 62 `unverifiedTextLayer`; its dark pages 1, 300, 342 and 1,560 are unchanged |

The deck's new contract fails on the baseline conversion with exactly two errors, both on page 5:
"missing text 'How do we support user analysis of very large data volumes?'" and "missing
source-page reference image".

Not run: Warren, which the default lane does not cover (its 920 colour scans exceed the default
image-output budget). It holds no letter-less page the rule would recognize — all eleven read 0 rows
— and its ink readings do not change: of its two pages the polarity rule would invert, page 1 reads
3 rows inverted and page 920 none, both far below #116's eight-row loss bound, and neither is
image-backed, so #93 never measures them.

## Cost

| Book | Baseline | Candidate | Change |
| --- | --- | --- | --- |
| Earthdata deck | 0.75 s, CPU 0.66 s, peak RSS 40.0 MiB | 0.86 s, CPU 0.80 s, peak RSS 85.6 MiB | +0.1 s and +45 MiB for one recognized page; the 128 MiB gate passes |
| Every other case | — | — | within run-to-run noise; no page renders that did not render before except the 12 English letter-less pages |

The new render is the whole cost on an unaffected book: twelve pages across the English corpus
(*Algebra* 175, 309, 437, 439; FAA 97, 244, 256, 310, 375, 387, 452; the deck's slide 5), about
70 ms each at 180 DPI. The polarity retry costs a second component pass only on a page that found no
row at all.

## Limits

- The rule reads the *declared* language, `ConversionOptions.language`, which defaults to `en`. The
  corpus lane converts every book with that default, so the Arabic and Chinese cases are judged as
  English; they are unchanged because their pages' writing is inside photographs, not because of the
  language gate. A client converting a non-English book with the correct tag skips the rule
  entirely, which loses drawn writing that could be recovered: the Arabic cards' pages 32, 52, 62
  and 88 are the corpus's examples, and none of them should be recognized anyway.
- A page whose layer holds one real word is never rendered, so a slide with a drawn sentence and a
  native label keeps neither the sentence nor a warning about it.
- Writing drawn at fewer than two rows, or in a hand or a face the glyph-row test does not see,
  still goes unrecognized; the page's `imageRegion` warning remains the only notice that its crops
  hold text that does not reflow.
- Recognition replaces the page's crops with a source-page reference, which is coarser than the
  crops (#164 chose them) and brings recognition's own errors and heading ranking. Slide 5's `NASA`
  heading is the corpus's one instance.
- The polarity retry asks only whether the first reading found nothing. A page that is white on dark
  *and* finds a stray row as printed keeps the stray row and stays blind to its writing.
