# Preserved images: no converter caption, alternative text that names the content

[#187](https://github.com/vocaro/PDFReflowLib/issues/187). Every preserved image was written as
`<figure><img alt="Preserved region from page N"/><figcaption>Preserved region from page N</figcaption></figure>`
(a supplementary source-page image said `Original page N`). A page of *Beginning and Intermediate
Algebra* could carry a dozen identical visible captions repeating what the page marker already
says, and the alternative text told a screen reader only where a crop came from.

macOS 27.0, arm64; Python 3.14.6; EPUBCheck 5.3.0; Poppler 26.04 (source renders only). Baseline
converter `f3840f4` (SHA-256 `7aa07efe…c4fe`), candidate built from this change (SHA-256
`b972109f…adbc`), one raster-environment probe for both.

## What changed

- **No `<figcaption>`.** The converter has no caption of its own to print. A caption the source
  prints is already its own block beside the figure, which is where a sighted reader reads it and
  where #27's `captionedImages` checks it; lifting it into `<figcaption>` would either print it twice
  or assert a pairing the converter cannot prove (#27's record: adjacency proves the pairing
  survived, never that it is right). The `figcaption` CSS rule went with it.
- **`alt` names the content, `title` keeps the provenance.** `title="Preserved region from page N"`
  on a crop, `title="Source page N"` on a whole-page image. No image has empty `alt`: these are
  content, not decoration.
- **The source's caption, where the page leaves no doubt.** `LayoutReconstructor.sourceCaptions`
  takes a line opening with a printed label (`Figure 3.2`, `Fig. 1`, `TABLE I`, `Algorithm 2`,
  `Box 18.1`, `Plate`, `Chart`, `Exhibit`, `Map`, `Listing`; `captionLabel`) outside every crop,
  within 1.5 bodies above or below one crop and over its measure, and uses it only when exactly one
  such caption stands against the crop and that caption stands against no other crop. Its wrapped
  lines follow at its own tight leading (0.4 of its size), within a point of its size and never half
  a point smaller than the line before (PDFKit sizes the FAA's caption by its 8-point bold label over
  9-point wrapped lines; TechPort sets an 8.2-point credit under its 9-point caption). Over 200
  characters the alternative text keeps the sentences that fit, or the words and an ellipsis.
- **Otherwise a kind the evidence justifies.** `classifiedGraphics` is `graphicsWithLabels` with
  each crop's kind, read from the seeds the finished crop holds (their centres inside it):

  | Evidence in the crop | Kind | `alt` |
  | --- | --- | --- |
  | a table region (`TableRegionDetector`, underlined columns, a table Vision recognized) | table | `Table kept as an image` |
  | an algorithm float between its rules | listing | `Algorithm listing` |
  | painted art at least a body size wide and tall, or a rule over six bodies long | artwork | `Illustration` |
  | a displayed formula line, or a scan's evidence grown as a display row | equation | `Mathematical expression` |
  | only marks — a fraction bar, a rule inside a letter-free line, a free rule of at most six bodies, a paint smaller than the type — and at least half its lines prose of eight tokens | text | `Text kept as an image` |
  | only marks, and mostly terms | equation | `Mathematical expression` |
  | only marks and no text | artwork | `Illustration` |
  | a page that does not reflow | page | `Whole page kept as an image` |
  | a source-page reference beside reflowed text | sourcePage | `The printed page, for comparison` |

  Precedence is table, listing, art, formula: a table region's claim is the strongest evidence on
  a page, and a drawing routinely swallows one of its own formula labels.

`ScanEvidenceRegions.classifiedRegions` reports which grown regions are display rows rather than
figures over their captions, and the OCR path records Vision's tables; both reach the page as
`PageContent.graphicKinds`, because a scan's paints alone would call every one of them art.

## Survey by kind, before choosing the wording

`survey.swift` (built by `build.sh`) runs extraction, composition and `classifiedGraphics` over
every page of the twenty-one English corpus PDFs and prints one row per crop with its kind, whether
the page prints a caption for it, whether a placed raster inks a tenth of it, its size and the lines
it holds. `summarize.py` counts them (`survey-summary.md`, rows in `survey.tsv`). It sees crops as
layout makes them, before the pipeline's page fallbacks, OCR, backdrop and scan paths, so Warren
and Blue Book (scans) and the 9/11 report (whose `=` hyphens are repaired later) differ from their
EPUBs; the census below is exact.

| Document | equation | table | listing | artwork | text | unsupported page | captioned | art: raster | art: vector |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `arxiv-replay-clocks-2023` | 10 | 0 | 6 | 17 | 1 | 0 | 11 | 17 | 0 |
| `cdc-zombie-pandemic-2011` | 0 | 0 | 0 | 33 | 0 | 0 | 0 | 33 | 0 |
| `census-rrs2002-01` | 23 | 0 | 0 | 2 | 3 | 0 | 0 | 0 | 2 |
| `cia-blue-book-14-1955` | 9 | 0 | 0 | 256 | 0 | 0 | 0 | 256 | 0 |
| `dga-2025-2030` | 0 | 0 | 0 | 37 | 0 | 0 | 0 | 17 | 20 |
| `faa-phak-8083-25c` | 21 | 0 | 0 | 545 | 0 | 1 | 442 | 216 | 329 |
| `fed-explained-2021` | 0 | 0 | 0 | 49 | 0 | 0 | 2 | 7 | 42 |
| `gpo-911-2004` | 53 | 0 | 0 | 47 | 0 | 0 | 0 | 43 | 4 |
| `gpo-our-flag-2003` | 0 | 1 | 0 | 121 | 0 | 0 | 0 | 84 | 37 |
| `gpo-warren-1964` | 0 | 0 | 0 | 920 | 0 | 0 | 0 | 920 | 0 |
| `nbs-jres-geltman-1977` | 11 | 0 | 0 | 31 | 0 | 0 | 1 | 31 | 0 |
| `noaa-nca5-2023` | 31 | 1 | 0 | 1071 | 461 | 1 | 3 | 515 | 556 |
| `ntrs-20180003024-earthdata-slides-2018` | 0 | 0 | 0 | 21 | 0 | 0 | 0 | 2 | 19 |
| `ntrs-20190030725-dasc-2019` | 19 | 0 | 0 | 8 | 1 | 0 | 3 | 2 | 6 |
| `ntrs-20200002975-gwl-2020` | 1 | 0 | 0 | 30 | 0 | 0 | 23 | 30 | 0 |
| `ntrs-20210020887-techport-thm-2021` | 0 | 0 | 0 | 39 | 0 | 0 | 1 | 5 | 34 |
| `scotus-loper-bright-2024` | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `uscourts-pro-se-1-2016` | 0 | 0 | 0 | 16 | 5 | 0 | 0 | 0 | 16 |
| `usda-ars-agresearch-2012-11` | 0 | 0 | 0 | 64 | 0 | 0 | 0 | 32 | 32 |
| `usgs-mcs2025-copper` | 0 | 3 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `wallace-algebra-2010` | 1616 | 4 | 0 | 332 | 27 | 0 | 5 | 23 | 309 |
| **all** | **1794** | **9** | **6** | **3639** | **498** | **2** | **491** | **2233** | **1406** |

What the numbers decided:

- **Art is one kind.** 2,233 art crops are inked by a placed raster, but a raster is not a
  photograph: it holds the FAA's drawings (216), NOAA's charts and maps (515), the CDC comic's panels
  (33) and Warren's page scans (920). Nothing the converter reads tells a photograph from a chart, so
  `Photograph`, `Chart` or `Diagram` would claim more than it knows. `Illustration` is the umbrella
  a book uses for all of them.
- **Mathematics is the largest kind the issue names.** Wallace alone has 1,616 crops. The first
  cut called 966 Wallace crops art: a fraction bar under one digit is shorter than a 12-point rule,
  so it seeded as a painted graphic, and the underline under a worked step (`+ 7/2 + 7/2`, page 43)
  stood under no line. A mark smaller than the type, and a free rule of at most six bodies, now
  decide nothing on their own. `Mathematical expression` rather than the issue's `Displayed
  equation`: fractions, radicands and worked steps without `=` are not equations.
- **A text kind was needed.** 461 NOAA crops are reference-list entries: an underlined DOI fragment
  (`1029/2019GL082077`) passes both the fraction-bar and the letter-free-line tests, and the crop
  grows over the entry (#181's territory). 27 Wallace crops are word problems whose inline mixed
  number seeded a crop over the whole problem. Calling either `Mathematical expression` or
  `Illustration` would mislead; `Text kept as an image` says the words cannot be read out.
- **Captions are common only where the source sets them tight under one figure**: 442 of the FAA's
  567 crops, 23 of the Word paper's 31, 11 of Replay Clocks' 34. The magazine's photo credits and
  two FAA pages whose captions stand between two crops name nothing, as intended.
- **`kept as an image` only where a reader expects text.** A screen reader announces the image
  role itself (WCAG: do not write "image of"), so `Illustration` and `Mathematical expression`
  stay short; a table, running text and a whole page are things a reader would expect to read, and
  hearing that they cannot is the useful part.

## Accessibility guidance

- DAISY Accessible Publishing Knowledge Base, [Image descriptions](https://kb.daisy.org/publishing/docs/html/images-desc.html):
  every informative image needs alternative text; empty `alt` is for decoration only; alternative
  text should be brief and should not add what cannot be determined from the image. The kinds are
  brief and claim nothing beyond the converter's evidence; no image has empty `alt`.
- DAISY, [Figures](https://kb.daisy.org/publishing/docs/html/figures.html): a caption is no
  substitute for the image's own accessibility, and its examples keep `alt` and `figcaption`
  distinct. The source's caption is the best text the converter has, so it is used as `alt`, as the
  issue asks. **The cost:** the printed caption also stays in the reading text beside the figure,
  so a screen reader hears it twice (Wallace page 72: `[image: Table 6. Structure of Age Table]`
  then `Table 6. Structure of Age Table`). Moving the caption into `<figcaption>` would remove the
  repetition but needs the caption–figure identity #27 says the converter cannot prove; follow-up.
- `title` carries provenance: it is not read by default by VoiceOver or Books, so it adds nothing to
  the spoken text, and it is available as a tooltip where a reader shows one.
- EPUBCheck 5.3.0 passes on every candidate EPUB (the corpus runner's gate).

Reader review: the Browser pane could not open local EPUB files and importing into Books would
change the owner's library, so `linearize.py` prints what a screen reader reads for one page —
blocks in order, each image as its `alt`. Wallace page 343 now reads `Example 465.`,
`[image: Mathematical expression]` twice, then the prose; before, each crop read `Preserved region
from page 343` as its image and again as its caption. Page 96 reads its three graphs as
`Illustration` and its slope fractions as `Mathematical expression`.

## Every converted image, by alternative text

`census.py` over each candidate EPUB (`census-summary.md`; `caption` is a printed caption used as
`alt`):

| Document | images | caption | equation | table | listing | artwork | text | page | sourcePage | provenance | empty | figcaption |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `arxiv-replay-clocks-2023` | 34 | 11 | 10 | 0 | 0 | 12 | 1 | 0 | 0 | 0 | 0 | 0 |
| `cdc-zombie-pandemic-2011` | 42 | 0 | 0 | 0 | 0 | 0 | 0 | 4 | 38 | 0 | 0 | 0 |
| `census-rrs2002-01` | 51 | 1 | 27 | 6 | 0 | 0 | 0 | 0 | 17 | 0 | 0 | 0 |
| `cia-blue-book-14-1955` | 424 | 2 | 110 | 0 | 0 | 0 | 0 | 0 | 312 | 0 | 0 | 0 |
| `dga-2025-2030` | 37 | 0 | 0 | 0 | 0 | 36 | 0 | 0 | 1 | 0 | 0 | 0 |
| `faa-phak-8083-25c` | 567 | 442 | 21 | 0 | 0 | 85 | 0 | 1 | 18 | 0 | 0 | 0 |
| `fed-explained-2021` | 57 | 1 | 0 | 0 | 0 | 47 | 0 | 0 | 9 | 0 | 0 | 0 |
| `gpo-911-2004` | 50 | 0 | 0 | 0 | 0 | 47 | 0 | 0 | 3 | 0 | 0 | 0 |
| `gpo-our-flag-2003` | 123 | 0 | 0 | 1 | 0 | 118 | 0 | 1 | 3 | 0 | 0 | 0 |
| `nbs-jres-geltman-1977` | 42 | 3 | 24 | 0 | 0 | 8 | 0 | 0 | 7 | 0 | 0 | 0 |
| `noaa-nca5-2023` | 1544 | 3 | 29 | 1 | 0 | 987 | 461 | 1 | 62 | 0 | 0 | 0 |
| `ntrs-20180003024-earthdata-slides-2018` | 21 | 0 | 0 | 0 | 0 | 6 | 0 | 0 | 15 | 0 | 0 | 0 |
| `ntrs-20190030725-dasc-2019` | 28 | 3 | 19 | 0 | 0 | 5 | 1 | 0 | 0 | 0 | 0 | 0 |
| `ntrs-20200002975-gwl-2020` | 31 | 23 | 1 | 0 | 0 | 7 | 0 | 0 | 0 | 0 | 0 | 0 |
| `ntrs-20210020887-techport-thm-2021` | 39 | 1 | 0 | 0 | 0 | 38 | 0 | 0 | 0 | 0 | 0 | 0 |
| `scotus-loper-bright-2024` | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `uscourts-pro-se-1-2016` | 21 | 0 | 0 | 0 | 0 | 21 | 0 | 0 | 0 | 0 | 0 | 0 |
| `usda-ars-agresearch-2012-11` | 64 | 0 | 0 | 0 | 0 | 61 | 0 | 0 | 3 | 0 | 0 | 0 |
| `usgs-mcs2025-copper` | 3 | 0 | 0 | 3 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| `wallace-algebra-2010` | 1979 | 5 | 1613 | 4 | 0 | 330 | 27 | 0 | 0 | 0 | 0 | 0 |
| **all** | 5157 | 495 | 1854 | 15 | 0 | 1808 | 490 | 7 | 488 | 0 | 0 | 0 |

Every candidate has zero `figcaption` elements, zero empty `alt` and zero provenance in `alt`.

## Per-book results

`tools/run_corpus_regressions.py`, one case per call, baseline and candidate, EPUBCheck included;
`tools/compare_conversion_runs.py --allow-different-converters` between them.

| Document | contract (base / candidate) | EPUBCheck | pages changed | changed fields | images, report, navigation changed |
| --- | --- | --- | ---: | --- | --- |
| `arxiv-replay-clocks-2023` | pass / pass | pass | 10 | alternatives, markup | none |
| `cdc-zombie-pandemic-2011` | pass / pass | pass | 42 | alternatives, markup | none |
| `census-rrs2002-01` | pass / pass | pass | 17 | alternatives, markup | none |
| `cia-blue-book-14-1955` | pass / pass | pass | 312 | alternatives, markup | none |
| `dga-2025-2030` | pass / pass | pass | 10 | alternatives, markup | none |
| `faa-phak-8083-25c` | pass / pass | pass | 348 | alternatives, markup | none |
| `fed-explained-2021` | pass / pass | pass | 54 | alternatives, markup | none |
| `gpo-911-2004` | pass / pass | pass | 19 | alternatives, markup | none |
| `gpo-our-flag-2003` | pass / pass | pass | 47 | alternatives, markup | none |
| `nbs-jres-geltman-1977` | pass / pass | pass | 7 | alternatives, markup | none |
| `noaa-nca5-2023` | pass / pass | pass | 1118 | alternatives, markup | none |
| `ntrs-20180003024-earthdata-slides-2018` | pass / pass | pass | 21 | alternatives, markup | none |
| `ntrs-20190030725-dasc-2019` | pass / pass | pass | 9 | alternatives, markup | none |
| `ntrs-20200002975-gwl-2020` | pass / pass | pass | 16 | alternatives, markup | none |
| `ntrs-20210020887-techport-thm-2021` | pass / pass | pass | 5 | alternatives, markup | none |
| `scotus-loper-bright-2024` | pass / pass | pass | 0 | — | none |
| `uscourts-pro-se-1-2016` | pass / pass | pass | 5 | alternatives, markup | none |
| `usda-ars-agresearch-2012-11` | pass / pass | pass | 24 | alternatives, markup | none |
| `usgs-mcs2025-copper` | pass / pass | pass | 2 | alternatives, markup | none |
| `wallace-algebra-2010` | pass / pass | pass | 413 | alternatives, markup | none |

Baseline contract results are against the contracts before the `imageAlternatives` additions; the candidate results are against the final contracts (the nine cases that gained checks were rerun after the additions).

On every book the only changed page fields are `alternatives` (new: the reader now records each
image's `alt`) and `markup`; no text, block, image byte, warning, report field or navigation entry
changed. Loper Bright has no images and is unchanged. The two non-English documents (`uscis-m618-arabic-2015`,
`irs-p596-zhs-2025`) were not converted, per the brief; their contracts hold no `pageReference`,
`captionedImages` or `imageAlternatives` expectation that the change could affect, and their markup
changes the same way.

## Contracts

`imageAlternatives` (new check type, `tools/check_corpus_content.py`): each named text must be the
`alt` of some image on the page, and a page that names any fails if any image on it has empty `alt`
or provenance in it. 22 checks on 14 pages, each page's source rendered and reviewed: FAA 262
(Figure 11-5, Figure 11-6, the KE/PE display) and 288 (Figure 12-4, and Figure 12-5 with its
wrapped `the Earth.`); Wallace 96 (graphs and slope fractions), 343 (the quadratic-formula
derivation) and 427 (right-triangle drawings); USGS 1 and 2 and Census 12 (tables); the Word
paper's Figure 1 and Figure A1; Replay Clocks page 3 (Figure 1, `Algorithm 1 ReplayEvents
Operation`, a display); NBS 2 (a display and the source-page reference); Our Flag 27's flag-size
table; CDC page 2, a whole-page fallback (new review page: the all-black inside cover).

`pageReference` is unchanged in meaning; the reader now knows the reference by `title="Source page
N"` with `alt="The printed page, for comparison"` (a fallback shares the title only), and still by
the old `alt="Original page N"`, so f3840f4 baselines compare. No existing expectation pinned the old
caption text, so no contract had to change; all 102 `pageReference` and 44 `captionedImages` checks
pass unchanged.

## Controls

- **The new checks on the baseline EPUBs** (`baseline-controls.txt`): all nine cases fail, and every
  error is an alternative-text error (FAA 10, Wallace 16, USGS 5, Census 5, GWL 4, Replay Clocks 7,
  NBS 10, Our Flag 4, CDC 2); every other check still passes there.
- **Swift mutations**, each run against `PreservedImageAltTextTests` and `ScanEvidenceRegionTests`
  and reverted: every painted seed art (the one-digit fraction and Wallace 479 fail); the text rule
  removed (the word problem and NOAA 284 fail); caption leading widened to two sizes (the
  `Data Acquisition` control and GWL page 2 fail); caption uniqueness removed (the shared-caption
  and two-caption controls fail); a `figcaption` written again (the encoder and EPUB-writer tests
  fail); the scan's display kinds ignored (the scanned equation reads `Illustration`); free rules
  art again (Wallace 64's worked step fails); the running caption-size rule removed (the TechPort
  credit control fails).
- **Python** (`tools/test_corpus_content.py`): the reference is recognized by title and text or the
  legacy `alt`, never by a fallback's title, another page's title or a crop; `imageAlternatives`
  rejects a missing kind, provenance or empty text beside a correct one, and malformed expectations.

## Defects and limits

- **The caption is heard twice** where it is used as `alt` (above). Follow-up: move a paired
  caption into `<figcaption>` once pairing identity can be established.
- **NOAA's reference entries are cropped** (461 crops, `Text kept as an image`): underlined DOI
  fragments seed them. The alternative text is now honest; the crops are the defect (#181).
- **Blue Book's 110 `Mathematical expression` crops** are pieces of charts on scanned pages
  (`1501=`, `2199 =100%` on the page-17 pie chart): a formula line in the inherited OCR seeds them.
  The text is literally an equation, but the crop is part of a figure the source-page reference
  already carries. Follow-up.
- **Ruled tables drawn as art** (Wallace's age and mixture tables, the Fed's and DASC's image
  tables) read `Illustration`: long rules cannot tell a table grid from a figure frame.
- **Captions not paired**: FAA pages 341, 391, 397 and 401 and DASC's TABLE III, where a caption
  stands against two crops or beside one; the magazine's photo credits, which are credits.
- **Some of NOAA's 29 `Mathematical expression` crops are reference entries** too, where an
  address's `=` or a letter-free fragment reads as a formula line.

## Files

`survey.swift`, `build.sh`, `summarize.py`, `survey-summary.md`, `survey.tsv` (the survey);
`census.py`, `census-summary.md` (the EPUB census); `linearize.py` (screen-reader order);
`baseline-controls.txt`.
