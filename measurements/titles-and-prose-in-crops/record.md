# Titles over art, worked-example prose in formula crops and same-page column continuations (#111, #112)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 (26A428) arm64, Xcode 27.0 (27A266a),
release CLI. The work began on `de0df61` and was carried forward to `f15ab78`, `3f59dff`, `9bf4e76`,
`43b20aa` and `d35285f` by merging each tip and reapplying the uncommitted patch. At every tip the
patch applied cleanly; at `d35285f` the contract file was retaken from the tip and
[`tools/addcontract.py`](tools/addcontract.py) reapplied. Diagnosis, the source-strip review and the
first lanes ran on `3f59dff`/`9bf4e76`. The final lanes, survey, negative control and gates below
compare an unmodified `d35285f` release build with this tree; the page diffs are identical to the
reviewed runs at every tip (FAA's three extra joins on 226, 286 and 288 appeared at `9bf4e76`, when #13
let those pages reflow, and were reviewed then).

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline | `d35285f` | `8d1572ab…` |
| candidate | `d35285f` plus this change | `bf29cd65…` |

Corpus: `dga-2025-2030` (`c34f1bec…`) and `faa-phak-8083-25c` (`247929ca…`); controls
`fed-explained-2021`, `gpo-our-flag-2003` and `wallace-algebra-2010`. No PDF or EPUB is committed.

## Diagnosis

Layouts were captured with `tools/capture-layout-fixture.swift` (tags applied where they validate, paints
recorded) and replayed through `graphicsWithLabels` and `blocks` with a temporary test that printed every
graphic, every crop and the lines it takes. Pages were read against `pdftoppm` renders.

- **FAA 3, 453, 461, 473, 477 (#112).** Each title's drop shadow is a transparency group recorded as a
  duplicate frame and non-frame paint forming one cluster, offset and blurred from the 48-pt title: page 3's
  shadow (76.5–198.5 × 670.8–718.3) lies within `Preface`'s line rectangle (72–188.8 × 673.5–730.3) but
  for 10 pt, covering 87% of it. Expansion admits every line the seed touches, so the title went into the
  crop. On page 461 the shadow's foot reaches 2 pt into `This is a list of common acronyms…` (11.5 pt tall),
  which was admitted too and took the paragraph's first line out of the text. On page 453 the shadow's crop
  merged with the performance figure, taking `Appendix A` with it. Page 473's title rectangle is PDFKit's
  merge of the title with `Appendix C` (x −18.7 to 456.2), 27 pt short of the shadow's right end.
- **DGA 9 (#111, first item), and 7, 8, 10.** Each section band is a 32.7-pt strip starting 55–68 pt inside
  its 18-pt title's line (x 36–159 over a band from x 103.9); the title lies level inside the band's
  height, so the band seed captured it. `Older Adults` ends 0.9 pt clear of its band. The same bands carry
  `Infancy & Early Childhood (Birth–4 Years)` (page 7), `Middle Childhood` and `Adolescence` (page 8) and
  `Individuals with Chronic Disease` and `Vegetarians & Vegans` (page 10). With the band in the way those
  pages also lost their column reading: pages 7 and 10 read one line per paragraph alternating columns.
- **FAA 251 (#112).** `“weight x arm = moment.”` (an `=` and at most 12 words, not a prose row) seeded a
  formula; it is the quoted end of step 2, set on the step's hanging indent under `2. Enter the moment for
  each item listed. Remember`. Its ±8 pt margin took step 2 and step 3 (`3. Find the total weight…`, below,
  where only prose rows stop the margin).
- **FAA 298 (#112).** The display's last row `3.18 × 1,000 = 3,180 feet AGL` has a lower margin reaching
  `The height of the cloud base is 3,180 feet AGL.`, which is not a prose row (it shares no edge with a full
  line), so the sentence stayed in the crop.
- **DGA 9 (#111, second item).** `blocks()` starts a paragraph whenever a line leaves its column, and only
  tags or `appendPage`'s cross-page rule join paragraphs. `Older Adults` is untagged (#91's rejected
  group), so `…dairy, meats, seafood,` / `eggs, legumes…` stayed two paragraphs. The same holds for every
  untagged two-column page: FAA's handbook, whose tags mostly fall back, never joined a sentence across its
  columns.
- **DGA 7, once its section title reflowed.** `Special Populations & Considerations` is a tagged `P` group
  in heading type. #67's rule reads such a group as a title only when the next text in its column is
  ordinary, or the style recurs on three pages; the next text is now the 18-pt section title, so the
  page title became a paragraph (and the book's 18-pt headings were re-ranked h4 → h3). This was found on
  the first candidate lane and is fixed below.

Paint order is not in the page model (`PageContent.graphics` are clusters), and `GraphicsReader` records
text/paint sequence only for opaque rectangular covers, which neither the shadow groups nor the gradient
bands are. The rule therefore uses the art's shape relative to the title, not paint order.

## Change

`Sources/PDFReflowLib/LayoutReconstructor.swift` only. No public API, option, default or warning changed.

- **`titleArt`** (in `graphicsWithLabels`, before the thin-rule handling). The lines a non-rule graphic
  touches that are at least 1.25 body, not monospaced and carry a word of three letters are its titles.
  - *Shadow*: the titles' rectangles cover at least 60% of the graphic (overlap between stacked title lines
    counted once), the graphic reaches no further than one title type size beyond them, and every other line
    touching it overlaps it by at most a quarter of its height. The graphic is decoration and seeds nothing.
  - *Band*: exactly one title and no other line; the graphic is at most twice the title line's height, at
    least three times as wide as tall, and level with the title (±2 pt). A title overhanging one end leaves
    the band's part beyond it (0.5 pt clear) as the crop; a band holding the whole title, or leaving less
    than its own height, is dropped.
- **`continuesSentenceAbove`** (formula seeds). A candidate whose row has no other pieces, that is not
  stacked, reads as words and opens with a lowercase word of at least three letters (past opening quotes)
  is the end of a sentence when the one line directly above it (within 0.9 body, overlapping it, same
  size, at least four words, no operator) ends without `.!?:;`, and the candidate starts within
  −0.5…+2.5 body of that line's left edge and ends within its right edge.
- **`isSentenceRow`** (formula margins, both sides). A line alone on its row that opens with a capital,
  ends with a full stop, has at least four words, reads as a sentence (function words) and carries no
  operator or `=` stops a formula's margin, as prose rows already did.
- **`joinColumnContinuations`** (end of `blocks()`, before footnotes). A paragraph (or a list item with no
  preserved line break, as #45 allows) and the next paragraph, adjacent apart from images, captions and margin folios, join when:
  neither carries a different validated group; the next text starts lowercase and the previous one
  does not end a sentence; both anchor lines read as prose and the next has two words; the last line fills
  its column (`fillsColumn`, #45); the first line starts right of the last line's end (−0.5 body) and is
  higher; and no prose (`isProse`, #45's shares) lies below the last line in its span, between the two
  columns, or above the first line in its span. The search is bounded above by the lowest line, preserved
  region or tint box above the first line that crosses the gutter (DGA's section band), so stacked
  sections above do not compete. Stepped-over blocks follow the joined paragraph. When that paragraph then
  continues onto the next page, #45 places them ahead of it and its heading (FAA page 199).
- **`introduces`** (#67's title rule). The next line in the group's column may be heading type when it is
  at most 90% of the group's smallest size and starts within one body of the group's left edge: a page title
  over the section title it introduces. The Fed cover's label over a larger title is still refused.

Designs considered and not built: dropping bands outright (inconsistent with `Older Adults`' kept band);
using `GraphicsReader`'s cover sequence for paint order (these paints are not covers, and the reader is out
of scope); and joining columns only when both paragraphs are untagged (the FAA's partially tagged pages join
correctly under #45's one-untagged-side rule).

## Before and after (`d35285f` → candidate)

`tools/run_corpus_regressions.py --converter <CLI> --epubcheck /opt/homebrew/bin/epubcheck
--environment-probe .build/raster-environment/probe --execution-context host-terminal --case <id>`, one case
per call ([`tools/lane.sh`](tools/lane.sh), [`tools/case.sh`](tools/case.sh)), then
`tools/compare_conversion_runs.py --allow-different-converters` and a per-page block diff
([`tools/pagediff.py`](tools/pagediff.py), [lane/](lane/)). Every run passed EPUBCheck, resource, progress and
memory gates; no memory-gate failure occurred.

| Case | Contract (new expectations) | Changed pages | Images | Navigation |
| --- | --- | --- | --- | --- |
| dga-2025-2030 | base fails 11, candidate passes | 7, 8, 9, 10 | same count; 8 band crops trimmed | +8 headings |
| faa-phak-8083-25c | base fails 20, candidate passes | 99 | 9 fewer (2, 3, 5, 6, 251, 461, 473, 477, 513 each lose a title or step crop) | +9 headings (page 2's title is a paragraph, see defects) |
| fed-explained-2021 | both pass | none (strict comparison passes) | unchanged | unchanged |
| gpo-our-flag-2003 | both pass | none (strict comparison passes) | unchanged | unchanged |
| wallace-algebra-2010 | both pass | none (strict comparison passes; glyph checks 343/347 pass) | unchanged | unchanged |

**Missing-text survey** (`measurements/figure-crop-bounds/tools/survey.swift` rebuilt from each tree,
[`tools/analyze.py`](tools/analyze.py); lists in [lane/](lane/)):

| Cause | Baseline lines / words / pages | Candidate lines / words / pages |
| --- | --- | --- |
| Inside a figure crop | 150 / 737 / 17 | 140 / 692 / 13 |
| Inside a formula or table crop | 47 / 280 / 11 | 43 / 248 / 10 |
| Hidden by design | 1 / 11 / 1 | same |
| Whole-page image fallback | 64 / 562 / 1 | same |

The survey diff only removes lines: the titles and `Appendix A`/`Appendix B` labels of 3, 453, 461, 473 and
477, page 461's first body line, page 251's steps 2 and 3 with the quoted formula line, and page 298's
closing sentence. No line entered a crop. What remains is figure-internal text (159, 401, 457–459, 475), the
three captions of #98's record (25, 185, 374), the in-frame table titles of 453–456, and displayed
calculations (101, 102, 136, 208, 254, 262, 265, 266, 298, 398).

**Review.** Every changed page was read:

- *Images, reviewed as before/after sheets* ([`tools/sheet.py`](tools/sheet.py)): FAA 2, 3, 5, 461 and 477
  lose their title image; 6 and 513 lose the title crop and keep their contents/index reference images;
  453 and 473 keep the figure crop without the title (453's figure keeps its in-frame table title); 251
  keeps the loading table and the sample problem without the step text; 298's crop ends above the closing
  sentence with every display row inside. DGA 7–10 bands are cut 0.5 pt right of each title and otherwise
  unchanged; page 9's `Older Adults` band crop is unchanged (asserted in the unit test).
- *Headings*: DGA `Infancy & Early Childhood (Birth–4 Years)`, `Middle Childhood (5–10 Years)`,
  `Adolescence (11–18 Years)`, `Young Adulthood`, `Pregnant Women`, `Lactating Women`, `Individuals with
  Chronic Disease`, `Vegetarians & Vegans`; the book's heading levels are unchanged (the page-7 fix keeps
  the 22-pt tier). FAA `Preface`, `Acknowledgments`, `Table of Contents`, `Performance Data for Cessna Model
  172R and Challenger 605`, `Appendix B`, `Acronyms, Abbreviations, and NOTAM Contractions`, `Airport Signs
  and MarkingsAppendix C` (see defects), `Glossary`, `Index`.
- *Column joins*: 83 FAA paragraph joins on 83 pages, 5 FAA list items continued into the next column
  (211, 334, 362, 413, 436), and DGA pages 7 (`…peanut introduction as early` / `as 4 to 6 months…`), 9 and
  10 ([lane/joins-faa-phak-8083-25c.txt](lane/joins-faa-phak-8083-25c.txt)). Each FAA join was reviewed on
  a source strip with both anchor lines marked ([`tools/joinsheet.py`](tools/joinsheet.py)): in every case
  the anchor is the last text line of its column (figures, captions or the folio beneath it), and the
  continuation is the first text line of the column to its right (below that column's figure and caption),
  mid-sentence (`…rejoins downstream. Form` / `drag is the easiest…`, `…the lowest reportable` /
  `altitude is 6,000 feet…`). No false join was found. DGA pages 7 and 10 now read whole bullets in
  column order, matching the renders.
- *Controls with no change*: Fed chart boxes and every Fed page; Our Flag flags with titles; Wallace
  derivations, graphs and the 343/347 glyph regions; DGA pages 1–6; FAA page 121's three figures and their labels (the page changes only by a column join).
  NBS figure crops go through the scan path this change does not touch and were not rerun.

## Tests and contracts

`Tests/PDFReflowLibTests/TitlesAndProseInCropsTests.swift`, ten tests. New fixtures captured from the
checksum-pinned sources with the merged `tools/capture-layout-fixture.swift`:
`faa-{3,453,461,473,477}-title-art`, `faa-{251,298}-worked-example` and `dga-7`; `dga-9` is existing.

- Reproducers: `titleShadowIsDecoration` (3, 461, 473, 477), `titleShadowBesideAFigureLeavesTheFigureWhole`
  (453), `sectionBandsKeepOnlyTheirPartBesideTheTitle` (DGA 9, with `Older Adults` as control),
  `pageTitleOverASmallerSectionTitleStaysAHeading` (DGA 7), `wrappedSentenceEndIsNotAFormula` (251),
  `sentenceBeneathADisplayIsNotItsMargin` (298, displays stay cropped), `columnContinuationJoinsBelowASectionBand`
  (DGA 9; refused without the bands' crops).
- Synthetic controls: `titleArtRequiresAShadowOrABandShape`, `formulaMarginSentenceAndWrappedEndControls` and
  `columnContinuationGuards` (each refusal listed in `doc/regression-testing.md`).

Five existing tests encoded the split at a column break and were updated narrowly:
`figureOverhangingTheGutterJoinsItsColumn` (165, 199, 262) and `fullMeasureFigureReadsApartFromTheColumns`
(108) move the caption after the joined continuation; `captionOfAColumnFigureStaysInItsColumn` (194)
likewise; `sourceControlPagesKeepEveryBlockBoundary` loses one block on `faa-211` (the `White arc` item
continuing into the right column) and `faa-212` (`…pitot system. Air` / `already in the system…`, read on
the render); `dgaOlderAdultsReadsEachColumnWhole` now requires one bullet.

- Negative control ([log](negative-old-source.log.gz)): with `d35285f`'s `LayoutReconstructor.swift`, all
  fifteen new and updated tests fail (50 issues).
- Mutations ([mutants.log](mutants.log), [`tools/mutate.py`](tools/mutate.py), run on the `43b20aa` merge,
  where the rules were already final): each of 23 single-guard mutations fails at least one test. Six
  survived the first pass for want of isolating controls (shadow coverage, extent bound and grazing
  allowance; the formula sentence's operator test, whose control was itself a formula seed; the
  opening-term guard, whose control was not wordy; the identity guard, whose synthetic tagged columns
  shared order numbers); the controls were fixed and the full set rerun.
- Contracts ([`tools/addcontract.py`](tools/addcontract.py), checked with [`tools/recheck.py`](tools/recheck.py)):
  FAA headings on 3, 453, 461, 473 and 477, `maximumImages` 0 on 3, 461 and 477, page 461's opening
  paragraph, page 251's steps as list items, page 298's sentence, joined phrases on 17, 103, 211 and 350,
  and the three `orderedText` checks on 165, 199 and 262 re-expressed with the joined text (they pinned a
  caption between a column's foot and the next column's head). DGA headings on pages 7–10, joined phrases on
  7, 9 and 10; page 9's two column-paragraph phrases are replaced by one joined phrase. The baseline EPUB
  fails exactly the 20 FAA and 11 DGA new expectations and nothing else.

## Verification

- `swift build`, `swift build -c release`: clean.
- `swift test`: 545 tests pass (535 at `d35285f` plus 10).
- `scripts/check-all.sh --fast` on the final tree: exit 0 (545 Swift, 211 Python, fixture conversions,
  13 policy conversions and 22 rejection/cleanup cases, repeat-run identity on the six fixtures).
- Corpus lane: the table above.

The tools in `tools/` were run from a scratch directory; paths inside them are those of the run.

## Remaining gaps

- The column join is conservative: it needs an element crossing the gutter above the continuation's head to
  set stacked sections apart, and adjacency in reading order, so a continuation behind a heading or in a
  section with no band stays split (a missed join, never a false one).
- FAA page 298's `Given:` and `Example:` labels stay inside the merged display crop (words beneath a formula
  are still captured by design, #51); only the closing sentence was defective.
- FAA pages 453–456: each figure's in-frame table title (`Short Field Takeoff Distance…`) stays inside its
  figure crop, as before.

## Defects to file

1. **PDFKit merges a title with the label above it into one line.** FAA page 473: `Airport Signs and
   Markings` (48 pt) and `Appendix C` (16 pt) extract as one line `Airport Signs and MarkingsAppendix C`
   with a rectangle from x −18.7. The heading reads that way now that it reflows. Expected: `Appendix C` and
   `Airport Signs and Markings` as separate lines (native line boundaries).
2. **Appendix labels and the handbook's cover title are read inconsistently.** FAA page 453's `Appendix A`
   is a paragraph while page 461's `Appendix B` is a heading; page 2's cover title `Pilot's Handbook of
   Aeronautical Knowledge` reflows as a paragraph. Expected: consistent title treatment (heading
   classification).
3. **Paint order is not available to layout.** `PageContent.graphics` are clusters without paint sequence,
   and `GraphicsReader` sequences text only against opaque rectangular covers, so art behind a title is
   judged by shape. Expected: a text-over-art signal from the reader for transparency groups and shadings
   (GraphicsReader).
