# A page that paints only its own backdrop (#164)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, Xcode 27, release CLIs,
host terminal. Date 2026-09-17. The work was done on `c64f637` (this worktree merged that
coordination tip before starting), and every measurement below is on that base.

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline | `c64f637` | `6e07d144dd45ec0f4df720a14196bd663af78722c09a1e999c57d96c676017c2` |
| candidate | `c64f637` plus this change | `44ff45f722b0f586c39b14a2900686c9ff22772554bb24ad58d199178207c94e` |
| probe | `tools/probe-raster-environment.swift` | `cbf9fabb801c2acd89433d713236eacac103824f3749e254b0b1ef15c4bc72e3` |

No source PDF or EPUB is committed. The deck commits no rasters either: the NASA insignia is on
every slide (14 CFR 1221; see the manifest's rights note), so this change is measured on text,
image-presence, page-reference and warning contracts only. Two source fixtures were captured with
`tools/capture-layout-fixture.swift` (`slides-5`, `dga-1-illustrated`); no existing fixture was
recaptured.

## Evidence

### What the deck paints

`ntrs-20180003024-earthdata-slides-2018` is a 21-slide Google Slides export, 720 × 405 pt. Read
with `GraphicsReader`, every slide paints exactly one page-sized footprint, and it is always a
**filled non-rectangle path** covering the whole slide — the slide's background colour, drawn as a
path rather than a `re`, so `TintDetector`'s rectangle rules (#54) never see it. Slide 13, for
example, holds 37 paints:

| Paint | What it is |
| --- | --- |
| 720 × 405 fill | the slide background |
| 639 × 49 fill at the head, 194 × 28 fill at the foot | the title and note placeholders |
| 672 × 287 and 612 × 235 fills, each with a stroked copy | the diagram's two panels |
| four 119 × 77 stroked boxes, one 93 × 61 fill | the pipeline boxes, each holding two label lines |
| eight small fills and strokes (4–7 pt tall) | the arrows between them |
| five image XObjects with their backing fills | the icons and the NASA insignia |

Every one of those vector paints *holds the lines drawn over it*. Clustered as `GraphicsReader`
clusters them, they are one region covering the slide, so the page-sized-graphic signal fired on
all 21 slides: `unverifiedTextLayer`, a cleared crop list and an `Original page N` image apiece.

### Why the existing exemptions could not fire

- #117's `layoutComesApart` refuses any page with one paint over 75% of it, and the background
  fill is such a paint on all 21 slides.
- With that guard lifted, the crop-outcome test still refuses: composing the slide's paints as any
  other page's leaves one crop over the whole slide holding every line (measured on all 21 slides;
  `cropOutcome(untouched).taken == .total`). The deck's art is full-bleed by design.
- #93's ink test cannot judge these pages at all: `OCRTextCoverage` counts *dark* components, and
  the deck sets white text on a dark blue ground, so every slide measures 0 text rows (defect 3).

### Which corpus pages paint only a backdrop

A survey of every English book ([`tools/survey-backdrops.swift`](tools/survey-backdrops.swift) and
[`tools/sweep.sh`](tools/sweep.sh), built with [`tools/build-tool.sh`](tools/build-tool.sh): one
row per page whose painted regions cluster into a page-sized one, [sweep.tsv](sweep.tsv), 1,401
rows) finds 23 pages whose page-sized paints are all flat fills. Of the rest, 1,351 paint a
page-sized image, 3 a fill with an image over it (the Fed's chapter openers), 1 a fill with an
outline (Fed page 4), and 23 no page-sized paint at all — only a cluster of smaller art, which is
#117's case.

| Book | Pages | What the page-sized fill is |
| --- | ---: | --- |
| ntrs-20180003024-earthdata-slides-2018 | 21 | the slide background |
| dga-2025-2030 | 1 | the cover's cream fill under 45 images and its outlined lettering |
| gpo-our-flag-2003 | 1 | page 55, which carries no text (an image-only page either way) |

Everything else that takes the signal paints a page-sized **image** (Blue Book 312, Warren 920,
NOAA 62, CDC 42, FAA 18, NBS 7, Our Flag 3, the Fed's chapter openers) or, on Fed page 4, a
page-sized fill **and** a page-sized stroked rectangle: the colophon draws a border around its
tint, so it is not a backdrop-only page and keeps the signal #72 settled for it.

### The DGA cover, the one control

The cover is a backdrop page too, so it decides how strict the rule may be. Its title is drawn as
art over the fill and its text layer is a Type 3 transcription whose glyph procedures paint
nothing (#117 built and then dropped an undrawn-Type 3 detector as redundant). Composed without
its backdrops it keeps four crops — the outlined lettering and the 45 images — and they hold
**10 of its 16 words**. The busiest slide of the deck (slide 2, the EOSDIS diagram) reaches 5 of
20. Half the words separates them with a wide margin on both sides, and #117's tenth does not.

## Rule

No public API, option, default or warning code changed. All of it is in
`Sources/PDFReflowLib/PDFReflowLibPipeline.swift`.

- **`paintsOnlyItsBackdrop(_:bounds:)`** (new): the page paints at least one paint covering more
  than 75% of it, and every such paint is a flat fill (`filled`, not `image`). A scan, a
  photograph printed to the edges and a page-sized outline are pictures of the page; a background
  colour is not.
- **`artBesideBackdrops(_:lines:bounds:)`** (new): on such a page, the art beside its backdrops —
  everything except the page-sized fill, any other non-image paint holding a line the page
  reflows (placeholders, panels, boxes), and the non-image marks drawn inside one of those boxes
  (the connectors between them). Images always keep their crop; so does vector art that holds no
  text and stands on its own — slide 5's question, drawn as outlines with no text layer, and the
  DGA cover's lettering. Returns `nil` for any other page, which then composes exactly as before.
- **`cropOutcome(_:)`** (new): the words the page's crops (`graphicsWithLabels` after composition)
  would take, the words it carries, and whether a crop covers the page. `layoutComesApart` reads
  it, and so does the reference decision.
- **`layoutComesApart`**: the page-sized-paint guard now ignores a backdrop fill, and on a
  backdrop page the crops may hold up to **half** the page's words instead of a tenth, because
  those crops are the page's own figures and a figure may hold its label. Every other page keeps
  #117's rule unchanged.
- **`reconstruct`'s `extractPage`**: composes `artBesideBackdrops(…) ?? graphics.paints`, and,
  when a backdrop page comes apart but its own figures would still take a word of it, gives up its
  crops for a source-page reference (`preservePageReference`, cleared graphics, tints and
  separators) and reports **no** warning. The deck's pipeline icons are drawn in boxes whose
  bitmaps overlap their labels' boxes, so a crop grown from one takes `Cumulus` out of `Cumulus
  Data Archive`; the reference keeps both the art and the text.

### Designs measured and rejected

- **Dropping only the page-sized fill**: 19 of 21 slides still lost most of their text to a crop
  grown from the placeholders (slide 9: 28 of 33 words).
- **Seeding crops from images alone**: every slide's text reflowed, but slide 5's question, which
  is vector art and its only content, disappeared from the book.
- **Treating an image inside a dropped box as decoration too**: slide 3's chart raster (55% of the
  slide) is inside the body placeholder that holds `projected`, so the chart disappeared.
- **Keeping every vector mark that holds no text**: the deck's arrows became 8–13 image regions per
  slide, and the Cumulus icon still took its label (contract failure on slides 12–16 and 21).
- **An area bound on such marks** (art under a fiftieth of the page is decoration): the deck's
  connectors reach 0.0054 of a slide and its smallest figure covers 0.0115, but a synthetic page's
  30 × 30 icons are 0.0019, so the bound drops real figures. "Inside a box the page paints behind
  its own text" separates the deck's arrows from both without a threshold.

## Before and after (`c64f637` → candidate)

`tools/run_corpus_regressions.py`, one case per call, with the compiled probe, then
`tools/compare_conversion_runs.py --allow-different-converters`. 35–39 GB free throughout.

| Case | Contract | Changed pages | `unverifiedTextLayer` | Images | EPUB bytes | Peak RSS |
| --- | --- | --- | --- | --- | --- | --- |
| ntrs-20180003024-earthdata-slides-2018 | base fails 29 (exactly the new checks), cand passes 224 | 21 (warnings; 1 and 5–10 also images, markup and references) | 21 → 0 | 21 → 22 | 3,978,231 → 3,329,172 (−16%) | 50 → 40 MiB |
| dga-2025-2030 | both pass | none | 1 → 1 | 37 | 5,530,312 | 106 → 104 MiB |
| fed-explained-2021 | both pass | none | 8 → 8 | 57 | 31,540,293 | 269 → 270 MiB |
| cdc-zombie-pandemic-2011 | both pass | none | 6 → 6 | 42 | 149,719,382 | 427 → 423 MiB |
| cia-blue-book-14-1955 | both pass | none | 312 → 312 | 424 | 206,191,530 | 262 → 273 MiB |
| nbs-jres-geltman-1977 | both pass | none | 7 → 7 | 42 | 7,062,501 | 271 → 267 MiB |
| gpo-our-flag-2003 | both pass | none | 2 → 2 | 123 | 13,305,710 | 107 → 104 MiB |
| usda-ars-agresearch-2012-11 | both pass | none | 2 → 2 | 52 | 44,171,837 | 306 MiB |
| ntrs-20210020887-techport-thm-2021 | both pass | none | 0 → 0 | 37 | 1,102,329 | 41 → 42 MiB |

"Changed pages" is `compare_conversion_runs.py`'s page-by-page comparison: on every case but the
deck it is empty, with no changed image bytes, navigation entry, page marker or report field.

The deck per slide (`check_corpus_content.read_pages`; words are the page's reflowed text):

| Slide | Words (base = cand) | Images base → cand | Source-page image base → cand |
| --- | ---: | --- | --- |
| 1 | 13 | 1 → 1 | yes → no (the NASA insignia is the region) |
| 2, 3, 4 | 19, 8, 6 | 1 → 1 | yes → yes |
| 5 | 0 | 1 → 2 | yes → no (the question and the insignia are regions) |
| 6, 7, 8, 9, 10 | 7, 40, 42, 33, 25 | 1 → 1 | yes → no |
| 11–21 | 9, 24, 20, 18, 12, 31, 34, 36, 38, 35, 25 | 1 → 1 | yes → yes |

No slide's text changed: the candidate reflows the same words on every page, and the 14 slides
that keep a source-page image keep it without a review warning.

## Tests and contracts

- `swift test`: 820 pass (six new tests in `PageBackdropTests.swift`, two new end-to-end tests and
  two new background cases in `IllustratedPageTests.swift`).
- Negative mutations ([`tools/mutate.py`](tools/mutate.py),
  [negative-mutations.txt](negative-mutations.txt)): each of 12 single-guard mutations fails at
  least one test. The composition filter survived until the `.pathFill` case was added: the
  synthetic `.fill` page draws its ground as a rectangle, which `TintDetector` already removes, so
  only a path-drawn ground reproduces the deck.
- Contract (`corpus/regressions.json`): `absentWarningCodes: unverifiedTextLayer` on all 21
  slides, `pageReference: false` on 1 and 5–10, `minimumImages` 1 on slides 1 and 9 and 2 on slide
  5, and `pageReference: true` on 13 and 19. The baseline fails exactly those 29 checks; the
  candidate passes the case's 224.
- Docs: README, `doc/architecture.md`, `doc/regression-testing.md`, the deck's review file and the
  deck contract's basis.

## Cost

`paintsOnlyItsBackdrop` scans the page's paints once; `artBesideBackdrops` runs only on a page
that passes it and is quadratic in the paints of that page alone (the deck's densest slide holds
75). `cropOutcome` is `graphicsWithLabels`, which `layoutComesApart` already ran; the reference
decision runs it once more, on backdrop pages only (23 pages in the English corpus). The deck
converts *faster*: 0.58–0.60 s user time on the baseline against 0.35–0.36 s on the candidate
(two alternating pairs), and its lane's peak RSS falls from 50 to 40 MiB, because 14 fewer
full-page rasters are encoded. No control's conversion time or memory moved outside the
machine's run-to-run spread.

## Remaining gaps and defects to file

1. **Slides 2, 3, 4, 11–21 still carry a source-page image.** Their own figures overlap the
   boxes of their labels — the pipeline icons stand on `Cumulus`, the chart raster on `projected`
   — so a crop grown from one would take that word out of the slide. Expected: the icons, photos
   and chart rasters as regions of their own with the labels still reflowed. That needs a crop to
   stop capturing a line it meets only in the padding of an image's box (the cloud icon's bitmap
   ends where the label's box begins), which is `LayoutReconstructor.captures` for every document,
   not a backdrop decision.
2. **A backdrop page's connectors are decoration only inside a box.** The deck's arrows all lie
   inside a panel, so they are dropped; an arrow drawn outside every text box would still become a
   region of its own.
3. **The #93 ink test is blind to light-on-dark pages.** `OCRTextCoverage` counts components
   darker than the page's ink threshold, so a slide deck with white text on a dark ground measures
   zero text rows and no uncovered ink. Expected: ink measured against the page's own background,
   so the test can judge inverted pages (it would have judged slide 5 directly).
4. **Our Flag page 55** paints a backdrop fill and no text; it is an image-only page before and
   after, and nothing in this change touches it.
