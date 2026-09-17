# A slide deck's titles, its per-slide note and text drawn twice in one place (#165)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, Xcode 27, release CLIs.
Work started on `56e70e2`; the tree was first measured on `0a3eec7` (#146/#154) and then rebased
onto `754eb7a`, over `2e18b31` (#14, the detached-show split) and `754eb7a` (#140, deterministic
body-size ties). Every lane below was re-run on that base, so the baseline is `754eb7a` itself and
every difference is this change alone.

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline | `754eb7a` | `6a6178277b56854a809fa5d965cfbf58bde3e958bc4ae981763ccffc3ac4d3bc` |
| candidate | this tree on `754eb7a` | `7c08ff1081f67956c305faec645665583b31d9452377bef45f63010afd37c45b` |
| probe | `tools/probe-raster-environment.swift` | `5f82c70d3561a5be248b19f0fd5c7e3115c04fb8d7cc6d345ccfbf6d69020961` |
| capture | `tools/capture-layout-fixture.swift` | `fc90d0bb418350c88e861420f06bdba15e450a4f24dc516fca9b105f3001e751` |

No source PDF or EPUB is committed; each lane's EPUBs were deleted after its page diff. The deck
commits no rasters either: the NASA insignia is on every slide (14 CFR 1221; see the manifest's
rights note), so this change is measured on text, heading and warning contracts only. Nine source
fixtures were captured with `tools/capture-layout-fixture.swift` (`slides-1`, `slides-3`,
`slides-10`, `slides-12`, `slides-13`, `slides-14`, `slides-19`, `slides-19-overprints` and
`noaa-100`); no existing fixture was recaptured.

## Evidence

`ntrs-20180003024-earthdata-slides-2018` is a 21-slide Google Slides export, 720 × 405 pt, one
slide to a physical page. Line geometry below is from the fixtures, read against 100 DPI Poppler
renders of the slides.

### Slide titles decided by type size (#165, titles)

`LayoutReconstructor.blocks` admits a heading at `max(body × 1.25, reflowBody × 1.1)`, where the
body is `bodySize`: the font size carrying the most *characters* on the page. A book page has
hundreds of body characters and a title of a few dozen, so the estimate is the body's. A slide has
neither:

| Slide | Title | pt | Other text | `bodySize` | Read as |
| --- | --- | --- | --- | --- | --- |
| 1 | `Earthdata Cloud Analytics Project` | 52 | byline, `NASA` at 28 | 28 | `<h2>` (correct) |
| 2 | `Earth Observing System Data and` / `Information System (EOSDIS)` | 30 | 9 diagram labels, 20–24 | 30 | paragraph |
| 3 | `Over time, EOSDIS archive volumes` / `increase exponentially` | 32 | `projected`, 16 | 32 | two paragraphs |
| 4 | `Distribution increases similarly to` / `cumulative volume` | 32 | none but the folio | 32 | two paragraphs |
| 6 | `Solution: Data-proximal Analysis` | 32 | 4 labels, 24 | 32 | paragraph |
| 7 | `Goals` | 28 | 5 list items, 20–24 | 24 | `<h3>` (`sectionLabels`) |
| 10 | `Architectural Concept` | 26 | 4 statement lines, 28 | 28 | paragraph |
| 19 | `Open Pipeline Provides Outputs…` | 28 | boxes 13–14, labels 10, note 8 | 10 | `<h3>` |
| 20 | `Open Pipeline Enables Integration…` | 26 | as 19 | 10 | `<h4>` |

On slides 2, 3, 4 and 6 the title's own characters outweigh the diagram's few words, so the title
*is* the page's body size and nothing on the page can reach 1.25 of it. On slide 10 the title is
set smaller than the statement beneath it, so no size rule could find it at all. On slides 19 and
20 the overprinted copies below put more 10-point characters on the page than 14-point ones, so
the estimate read 10 points as the body and the 13- and 14-point diagram boxes as 30–40% over it:
`Preprocessing as-a-service`, `AODS1 as-a-service`, `Analysis as-a-service` and `Cumulus Cumulus
Data Archive` became `<h5>` and 13-point `Visualization as-a-service` `<h6>`, beneath the real
title. The margin is the duplicates: with them slide 19 weighs 112 characters at 10 points against
92 at 14, and slide 20 weighs 127 against 92; without them both weigh 90 against 92, and 14 points
is the body again. No slide of the deck ties, so #140's deterministic tie-break (a tie takes the
smaller size) changes none of these readings.

Where a title did qualify, `rankHeadingLevels` ranked it against the rest of the deck. The deck's
heading sizes were 52, 28, 26, 14 and 13 points — five tiers more than 7% apart — so one title
placeholder came out as `<h2>` (slide 1), `<h3>` (7–9, 11–19) and `<h4>` (20, 21), and the diagram
boxes that slipped in below them took levels 5 and 6.

What the deck *does* repeat is the place. Measured from the top of the page to the top of the
topmost line, the title band is 7.2–30.7 pt (1.8–7.6% of the page) on 19 of the 21 slides. The two
exceptions are slide 1, whose title is centred on the slide (101 pt down), and slide 5, whose only
extracted line is its slide number. Every slide carries at most 346 characters (median 202).

### The slide note removed as a repeated footer (#165, furniture)

`¹ Analytics Optimized Data Store` explains the `AODS¹` box on the same slide. It is printed on
nine slides at 8 points, in two positions:

| Slides | Note rectangle (x, y, top) | Footer band (top ≤ 28.35) | Baseline |
| --- | --- | --- | --- |
| 12, 13, 14, 16, 17 | 523.3, 14.7, top 27.6 | inside | removed, `furnitureRemoved` |
| 18, 19, 20, 21 | 79.2, 17.2, top 30.0 | outside | kept |

`FurnitureDetector.collect` admits a short, separated line in the outer 7% of the page and
`resolve` removes a run of three or more nearby pages carrying the same words at the same height:
12–14 and 16–17 qualify (slide 15 prints no note, which breaks nothing since a run tolerates a gap
of two). The four slides that set the note 2.4 pt higher fall outside the band and kept it, which
is how the same line survived on 18–21 and vanished on 12–17. Nothing in the repetition rule can
tell a per-page note from a running foot.

### Text drawn twice in one place (#165, duplicated labels)

`mutool draw -F trace` shows the deck drawing two text boxes with the same words at the same
transform. On slide 19, `.75 0 0 .75 47.696855 200.06694` draws `Cumulus`, then later `Cumulus ` /
`Data ` / `Archive` at the same transform, and `.75 0 0 .75 418.57917 329.42759` draws `End-User ` /
`Interpretation` twice over — a Google Slides export keeps each build step's boxes on the finished
slide. The second drawing lands glyph for glyph on the first, so the rendered slide shows nothing
unusual, but PDFKit returns a line for each with an identical rectangle:

```
size= 14.00 x=  62.12 y= 181.80 w=  59.84 h= 13.13  'Cumulus'
size= 14.00 x=  62.12 y= 181.80 w=  59.84 h= 13.13  'Cumulus'
```

Reflow then read `<p>Cumulus</p>` followed by `<p>Cumulus Data Archive</p>` on slides 13–21, and
`<p>End-User</p>` / `<p>End-User Interpretation</p>` / `<p>Interpretation</p>` (with `Data` /
`Data Exploration` / `Exploration` on slide 20). The same shape appears outside the deck: Blue Book
page 25 returns one inherited-OCR artefact (`I\n~`, 32.6 pt, at 12.48, 708.6) four times.

## Rules

`LayoutReconstructor.slideTitle(in:bounds:)` returns a slide's title lines: on a landscape page,
the topmost line, its top within the outer eighth of the page height, reading as a title (a capital
or digit first, two letters, under 200 characters, no list marker, no dot leader, no terminal
punctuation) with no other line on its row, plus the lines that stack under it as a heading's do
(`continuesHeading`), and only when the nearest text below the stack is at least half the title's
own height clear of it. `isSlide(_:)` is that title on a page of at most 600 characters whose
typography is not synthetic.

`PDFReflowLibPipeline.reconstruct` counts slides during the extraction pass, beside the label and
heading-style evidence, and reads the whole document as a deck when it has at least three pages,
every page shares one landscape size, and two thirds of the pages carrying text are slides. The
Earthdata deck scores 19 of 21.

In `blocks`, a deck's page computes its slide title and `headingTypography` answers from it first:
a line of the title stack is heading typography whatever its size, and a line set below 95% of the
title's size is not, whatever the page's estimate, its labels or its box titles make of it. A slide
with no title in the band (the deck's own title slide) keeps the ordinary rules unchanged.

`rankHeadingLevels(_:slideDeck:)` ranks every heading of a deck at level 2 instead of by size
tiers, because a slide carries one title and a deck sets each title to fit the words on it. A
validated tag level still holds, as it does for a book.

`FurnitureDetector.collect` refuses a candidate that explains a marker printed on its own page:
the line opens with a raised number (`LayoutReconstructor.raisedNoteNumber`) that another line of
the page carries raised inside its text. A folio is never raised and no running head's words are a
note's marker, so this touches nothing else.

`NativeTextReader.withoutOverprints` drops a line whose text and font size equal an earlier line's
and whose rectangle matches it within 0.05 pt. Fake bold drawn twice offsets its copy by a fraction
of an em, and a word repeated elsewhere on the page has its own rectangle; both keep two lines.
`capture-layout-fixture --keep-overprints` records PDFKit's lines before this step.

It runs directly after `extractLines`, before the detached-show split (#14) and before the
column-joint (#65) and borderless-table (#121) splits. Removing an overprint changes what the page
*holds*, while each split only divides a line the page already has, and each of them has to decide
which line a show or a rectangle belongs to. `splitDetachedShows` is explicit about it: it takes a
cut only where every matched show origin lies inside exactly one line rectangle, which two
identical rectangles can never satisfy, so an overprinted line left standing would refuse its own
split and the split of any other line its rectangle covers. Deduplicating first keeps that geometry
answerable. It costs nothing on the corpus as it stands — every overprinted line found (the deck's
14-point box labels, Blue Book's 10.9 pt artefact) is far narrower than the quarter-page the
detached split requires — and the DGA, Wallace and Our Flag lanes, which are where #14's four
splits live, are unchanged page for page.

`tools/check_corpus_content.py` gains a `headingLevels` expectation (`{"heading", "level"}`): every
heading of the page holding the phrase must be written at that level, and at least one must exist.

## Contracts (`corpus/regressions.json`)

| Case | Added |
| --- | --- |
| ntrs-20180003024-earthdata-slides-2018 | `headings` and `headingLevels` (level 2) for the 20 slide titles on pages 1–4 and 6–21; the note `1 Analytics Optimized Data Store` appended to `orderedText` on 12, 13, 14, 16 and 17 and to `text` on 19 and 20; `absentText` `Cumulus Cumulus` on 13–21, `End-User End-User` and `Interpretation Interpretation` on 19–20, `Data Data Exploration` and `Exploration Exploration` on 20; `absentHeadings` for `Cumulus Cumulus Data Archive`, `Preprocessing as-a-service`, `AODS1 as-a-service`, `Analysis as-a-service` and `Visualization as-a-service` on 19 and 20 |

The baseline fails exactly these: 54 errors (15 unwanted text, 14 wrong heading levels, 10 missing
headings, 10 unwanted headings and 5 missing notes); the candidate passes the case.

## Tests (`Tests/PDFReflowLibTests/SlideDeckTests.swift`)

| Test | Reproducer / control |
| --- | --- |
| `aSlideTitleIsAHeadingWhateverTheSlidesBodySizeSays` | `slides-3`: `bodySize` is the title's own 32 points; the two lines are one heading. Control: outside a deck the page has no heading and three paragraphs. |
| `aTitleSetSmallerThanTheSlidesBodyIsStillItsTitle` | `slides-10`: the 26-point title over a 28-point statement is the slide's heading; outside a deck the page has none. |
| `aSlidesDiagramLabelsAreItsBodyNotItsHeadings` | `slides-19`: one heading, the five box labels paragraphs. Reproducer: `slides-19-overprints` read as a book gives six headings, `Cumulus Cumulus Data Archive` among them. Either rule alone leaves one heading. |
| `aTitleSlideWithNoTitleInTheHeadBandKeepsTheOrdinaryRules` | `slides-1`: no slide title; the 52-point title is still the page's one heading and the byline stays prose, in a deck and out of one. |
| `everySlideTitleOfADeckRanksAlike` | Titles of 52, 32 and 28 points rank 2, 2, 2 as a deck; control: 2, 3, 4 by size tiers. |
| `aLandscapeBooksPagesAreNoSlides` | `noaa-100`: portrait in unrotated page space; turned on its side its running head *does* read as a slide title, and 2,781 characters still refuse it. Controls: six slides qualify, and slide 1 does not. |
| `aNoteExplainingAMarkerOnItsSlideIsNoFurniture` | `slides-12`/`13`/`14` through `FurnitureDetector.strip`: the note survives on all three with no warning. Control: with each slide's `AODS¹` marker written as ordinary text, all three lose it and report `furnitureRemoved`. |
| `aSlideTitleNeedsBothItsBandAndItsClearance` | Synthetic landscape pages: a title 20 pt down with 40 pt of air is a title; 51 and 60 pt down are not and 49 pt is; 14 pt of air under a 30-point title is not and 16 pt is; the same page portrait has none. |
| `aLineThatOnlyOverprintsAnotherIsReadOnce` | `slides-19-overprints`: 26 lines become 23, matching the deduplicated fixture line for line; `End-User`, printed three times, keeps the two that stand on different rectangles. Controls: a copy offset 0.3 pt (fake bold) or 60 pt, different text on one rectangle and a one-point size change all keep two lines. |

## Corpus lanes

`tools/run_corpus_regressions.py`, one case per call, with the compiled raster/Vision probe, then
`tools/compare_conversion_runs.py --allow-different-converters`. 38–42 GB free throughout.

On the `754eb7a` base, after the rebase over #14 and #140. These are the cases where those two
commits can interact with this one: the deck itself, Blue Book (whose page 25 holds the only other
overprints in the corpus), the three books that gained a detached-show split in #14, and the two
NASA papers whose headings #154 last moved.

| Case | Baseline | Candidate | Changed pages |
| --- | --- | --- | --- |
| ntrs-20180003024-earthdata-slides-2018 | fails the 54 new checks | pass | 19: 2–4, 6–21 |
| cia-blue-book-14-1955 | pass | pass | 137 |
| dga-2025-2030, wallace-algebra-2010, gpo-our-flag-2003, ntrs-20200002975-gwl-2020, ntrs-20190030725-dasc-2019 | pass | pass | none |

DGA, Wallace and Our Flag carry #14's four detached-show splits, and each is unchanged page for
page with overprint removal running ahead of that split, so the two passes do not interact.

The same lanes on the earlier `0a3eec7` base (binaries `a62e61df…` and `d90e8370…`) gave the same
result, and additionally covered ntrs-20210020887-techport-thm-2021,
usda-ars-agresearch-2012-11, fed-explained-2021, gpo-911-2004 and faa-phak-8083-25c: pass on both
sides, no page changed.

No image, report field, navigation entry or warning changed on any case but the deck, and no page
marker moved. The deck's own navigation goes from 25 entries to 20: the baseline listed 15 slide
titles at three levels with slides 19 and 20's five box labels nested under each of them (`Cumulus
Cumulus Data Archive`, `Preprocessing as-a-service`, `AODS1 as-a-service`, `Analysis as-a-service`,
`Visualization as-a-service`, twice over), and no entry at all for slides 2, 3, 4, 6 and 10; the
candidate lists one entry per slide that has a title, all at one level. The remaining corpus cases
(`uscourts-pro-se-1-2016`, `usgs-mcs2025-copper`, `nbs-jres-geltman-1977`,
`arxiv-replay-clocks-2023`, `census-rrs2002-01`, `scotus-loper-bright-2024`, `irs-p596-zhs-2025`,
`uscis-m618-arabic-2015`, `cdc-zombie-pandemic-2011`) were converted with both binaries on the
`0a3eec7` base and compared page by page: no page changed on any of them.

Every changed page was read against the source renders:

| Case | Pages | Change |
| --- | --- | --- |
| slides | 2, 3, 4, 6, 10 | The slide title becomes one `<h2>`; the two-line titles of 3 and 4 join. |
| slides | 7, 8, 9, 11–19 | The title's level goes from `<h3>` to `<h2>`. |
| slides | 20, 21 | The title's level goes from `<h4>` to `<h2>`. |
| slides | 12, 13, 14, 16, 17 | `¹ Analytics Optimized Data Store` is restored at the end of the slide, and `furnitureRemoved` no longer reports for those five pages. |
| slides | 13–21 | One `Cumulus` paragraph instead of two. |
| slides | 19, 20 | The five box labels are paragraphs, not `<h5>`/`<h6>`; the doubled `End-User`, `Interpretation` (and slide 20's `Data`, `Exploration`) paragraphs are gone. |
| cia-blue-book-14-1955 | 137 pages | 1,403 duplicate blocks of inherited-OCR scan noise are emitted once (83 distinct texts, the longest `:::.:::.:: ..:::: I \ I .,::..`); 13 blocks move in the reading order that leaves. Per-page word multisets lose 1,389 tokens and gain none, every one a single-character artefact (`~` 661, `J` 65, `0` 63, `I` 55, `✓` 46, `■` 42 and punctuation). No word is lost, no image, warning or navigation entry changed, and the case's content contract passes before and after. |

Warren and NOAA are outside the lane (#5), so both were converted directly with
`--maximum-output-bytes unlimited --no-ocr` and their blocks diffed, on the `0a3eec7` base:

| Book | Changed blocks |
| --- | --- |
| gpo-warren-1964 | none: 16,479 blocks before and after, block for block |
| noaa-nca5-2023 | none: 21,209 blocks before and after, block for block. Its 1,834 landscape letter pages are portrait in unrotated page space and average 2,800 characters, so no page of it is a slide, and none of its lines overprints another. |

Negative mutations (`measurements/slide-decks/tools/mutate.py`,
[`negative-mutations.txt`](negative-mutations.txt)), run over the slide-deck, furniture, heading,
navigation-heading and number-led suites; every mutation is caught. The band and clearance lines
were uncovered until `aSlideTitleNeedsBothItsBandAndItsClearance` was added: the deck's own slide 1
misses the head band by 50 pt *and* clears its byline by 24.3 pt against a 24.4 pt bar, so either
guard alone still refused it.

## Verification

- `swift test`: 784 pass (9 in `SlideDeckTests`).
- `python3 -m unittest test_corpus_content` from `tools/`: 37 pass (2 new, with the negative
  controls for a re-ranked heading, a flattened heading, the same text on another page, two
  headings at different levels and malformed entries).
- `scripts/check-all.sh --fast`: exit 0, including the generated doc counts and byte-identical
  repeat conversions.
- Corpus lanes above, and `tools/check_corpus_content.py` on each candidate evaluation.

## Remaining defects

1. **The deck's note reads in the middle of slides 19 and 20**, between `Analysis` and `AODS1
   as-a-service`, rather than at the end: on those two slides it is set at the lower left, where
   the reading-order sort reaches it before the boxes to its right. It reads last on 12–18 and 21.
2. **The lettered sub-items `a.` and `b.` on slide 7 are not nested** under item 3 (#165). The
   logical model has no nested lists — list items are `preformatted` blocks — so this needs model
   and writer work, not a heading decision.
3. **Slide 10's italic sentence splits at its line break** (`This approach produces key important
   benefits for` / `the user community and EOSDIS`): the deck sets the two 28-point lines 50 pt
   apart, nearly twice their height, so the paragraph rule reads no ordinary leading between them.
4. **Slide 2's diagram labels interleave** and `EOSDIS` merges with `distribute`; **slide 11's
   `Analyze` and `Visualize` circles come back as one PDFKit line**. Both are reading-order and
   extraction defects the deck's title rule does not touch (#153 and #165).
5. **Every slide still reports `unverifiedTextLayer` with a source-page image** because the
   full-bleed slide background counts as a page-sized graphic (#164).
6. **A deck stored rotated would not be recognized.** `slideTitle` reads unrotated page space, so a
   landscape deck written as portrait pages with `/Rotate 90` is not a deck. No corpus deck is.
7. **A deck's own sub-headings would be suppressed.** On a slide, nothing set smaller than the
   title is a heading. This deck has no slide with a second heading level; one that did would lose
   it.
