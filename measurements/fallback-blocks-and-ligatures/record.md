# Interleaved balloons, rotated OCR captions (#122); ligature hyphen evidence and spaced example lines (#123 items 1–2)

Tier: deterministic Apple PDF/OCR stack, library defaults, macOS 27.0 (26A428) arm64, Xcode 27.0
(27A266a), release CLIs, six-agent host load. Work began on `d35285f` and was carried by merge
(no commits) to `605d7e3`, `e949bea`, `9803329`, `e002972` and `458a2e9`. Every figure below compares
a release build of `git archive 458a2e9` (SHA-256 `65ac9c13…`) with `458a2e9` plus this working
tree (`a3bf6549…`). Both CLIs were installed as `pdf-reflow` in separate directories, so both runs
share one compiled Vision model cache: the comparator reports `sameVisionPrograms: true` and no OCR
caveat. Sources are the checksum-pinned corpus PDFs (CDC `d95e9ec2…`, Wallace `856bd81e…`). Renders
come from `pdftoppm` at 60–70 DPI. No public API or default changed. `TextLine.readingDirection` and
`OCRReader.Recognition.Line.topEdge` are internal.

## #122: a balloon beside a caption box alternates line by line (CDC pages 14, 23, 34)

**Cause.** The inherited text layer's rectangles overhang the lettering. Page 14's broadcast box
opens with a merged two-line rectangle from x 121 to 447, which reaches under the `Nothing but snow.`
balloon (x 62–159). Page 34's `in effect…` line (x 141–466) meets the `wow…` balloon (x 68–146).
So no vertical gutter separates the balloon from the box. No horizontal band separates them either,
and neither the text-measured gutter, `spanningFigures`, `headingRow` nor `bulletColumns` applies.
The region falls to the reading-order sort. Balloon lines sit about 10.6–11.3 points apart and box
lines about 9–10, so their mid-lines alternate. Before this change, page 34 read `.severe…`,
`wow... THAT o ld THINg STILL`, `in effect…`, `w o r k s !`.

**Rule (`interleavedBlocks`, tried just before the sort).**

- **Grouping.** Lines are taken from the top. Each joins the block whose lowest line it sits under
  at ordinary leading (the prose window, `-0.4…0.9` of the larger size) and overlaps horizontally.
  When several blocks qualify, it takes the one with the nearest centre.
- **Row pieces.** A line sharing at least half of the taller line's height, and set 0 to 1 body
  beside the lowest line, continues that row (page 34's `L o o k in g` + `f o r ?`).
  - With `sameRow`'s smaller-height test, `haven't le f t the` joined page 23's merged
    `cdc is ure/Ne…` rectangle, and `wow...` joined page 34's `in effect…`.
  - Overlapping pieces are refused.
- **When it applies.** Every condition must hold:
  - the region holds only plain lines, with no list line, image, table, box or boundary;
  - the lines form exactly two blocks;
  - the blocks' centres are more than a quarter of the wider measure apart;
  - both blocks are set centred, meaning their line centres spread less than half as far as their
    left edges (page 14's box: 21 against 116 points);
  - at most a third of the smaller block's baselines fall within 0.2 body of the other's;
  - the row sort alternates between the blocks at least three times.
- **Order.** The left block reads first, as a column cut would read it. Each block reads in row order.

A "share part of their height" guard and an "at least two lines each" guard were drafted and removed.
Both follow from three alternations in the row sort: the shared-height mutant survived every test,
and a block of one line cannot alternate three times.

**Survey before shipping.** A temporary trace (`PDFREFLOW_ORDER_TRACE`, since removed) logged every
call that reached the sort, and whether the step fired, over all fifteen English corpus books
([fallback-survey.tsv](fallback-survey.tsv), [fires](fallback-survey-fires.txt)).

| Case | Sorts reached | Pages | Fires |
| --- | ---: | ---: | --- |
| cdc-zombie-pandemic-2011 | 118 | 33 | 14, 23, 34 |
| wallace-algebra-2010 | 1,810 | 470 | 0 |
| fed-explained-2021 | 549 | 125 | 0 |
| faa-phak-8083-25c | 4,162 | 502 | 0 |
| gpo-911-2004 | 1,085 | 577 | 0 |
| cia-blue-book-14-1955 | 1,299 | 312 | 0 |
| gpo-warren-1964 (unlimited output, no references) | 1,965 | 887 | 0 |
| noaa-nca5-2023 (the same) | 3,859 | 1,817 | 0 |
| Loper Bright, Our Flag, DGA, arXiv, NBS, USGS, Census | 500 | 211 | 0 |

The guards came from the survey, each fixing a set of false fires:

1. The first draft required only two interleaving blocks of two or more lines with at most a third
   of shared baselines. It fired on 37 Wallace regions, mostly one paragraph split around formula
   pieces and answer-key grids, and also on CDC pages 5 and 12.
2. Requiring the centres apart, three alternations and no list line removed all of those. 9/11
   page 452's glossary still fired: names beside descriptions formed about 30 blocks.
3. Requiring exactly two blocks removed 9/11 page 452. CIA pages 203 and 258 still fired: scanned
   statistics tables whose row labels sit a few points off their figures' baselines.
4. Requiring both blocks centred removed the CIA pages. That left CDC 14, 23 and 34.

The trace ran at `e949bea`. The later merges changed only notes, word spaces and OCR retry, and
the two guard removals are logically implied. The lane below, at `458a2e9`, shows the same pages.

**Before/after** (checked against renders):

| Page | Before | After |
| --- | --- | --- |
| 14 | `sray in your Homes…`, `Nothing eut snow .`, `slow bo…`, `le t 's tr y`, `o r viOLenr…`, `the radio...`, `thbm…`, `sray runed…` | `Nothing eut snow .` / `le t 's tr y the radio...`, then the broadcast's four paragraphs, then `uhm.. todd...` |
| 23 | the left-panel balloon's lines alternate with the right-panel broadcast | the balloon (`w e're aLmosT…` through `H o u s e !`), then the broadcast |
| 34 | `.severe…` / `wow... THAT o ld THINg STILL` / `in effect…` / `w o r k s !` | `wow... THAT o ld THINg STILL` / `w o r k s !` / `.severe…` / `in effect…` |

The CDC 26 balloon control (`speechBalloonsAreNotHeadingBands`) and every other CDC page are unchanged.

## #122: the rotated OCR caption reads its last line first (CDC page 17)

**How Vision returns it.** Page 17 is recognized. Vision returns the sideways caption's three lines
in reading order. Each line's quadrilateral top edge runs down the page: `SEVERAL…` has top-left
(0.928, 0.406) and top-right (0.928, 0.040). `OCRReader` kept only the axis-aligned box, 9 points
wide and 106–225 tall (with `fontSize` equal to that height). No cut separates the three narrow
rectangles, and the row sort read them left to right: `ATLANTA`, `DISEASE`, `SEVERAL`.

**Rule.**

- `OCRReader` records each line's top edge in the recognized image's normalized coordinates. A
  banded retry (#116) scales the edge's vertical component by the band's height.
- A line whose edge runs more than 45° from left to right gets `TextLine.readingDirection`, a unit
  vector in page space. Upright lines keep nil, as does all native text.
- `ordered()` first checks whether a region consists only of lines rotated the same way (within 20°).
  If it does, it sorts them by the direction a new line advances (the reading direction turned a
  quarter clockwise), then along the text.
- Pages that mix rotated and upright lines are cut as before.

**Before/after.**

- **Page 17:** `SEVERAL DAYS LATER AT THE CENTERS FOR` / `DISEASE CONTROL AND PREVENTION IN` /
  `ATLANTA, GEORGIA...`, as rendered.
- **Page 16** (the rotated CDC building sign) also changes, from `УďпG`, `CONTROL ARD PREVE`,
  `CERTERG`, `FOE`, `JCDC` to `JCDC`, `CERTERG`, `FOE`, `CONTROL ARD PREVE`, `УďпG`. That is the
  sign's order (CDC, CENTERS FOR, CONTROL AND PREVENTION), with the seal's stray fragment last. This
  is an improvement.
- With shared Vision programs, both pages' recognized text is identical in both runs; only the
  order changed.

## #123 item 1: `dif-` + `ferent` (Wallace pages 50, 218)

**Cause.** Wallace prints the whole word `diﬀerent` with U+FB00, and `addVocabulary` recorded it
that way. At a line break, PDFKit extracts plain letters (`dif-` + `ferent`), so the lookup for
`different` failed and the hyphen stayed with `uncertainHyphen`.

**Rule.** `addVocabulary` records a word holding a Latin ligature (U+FB00–U+FB06) both as printed and
with the ligatures spelled out (`ff fi fl ffi ffl st st`). No other compatibility mapping is applied.

- The join lookups (`joinOperation`, `addressHyphenOperation`, `inflectionVouches`) are unchanged.
  A first version folded inside them too. It was reverted so that the parallel #126/#127 work in
  `joinOperation` merges cleanly.
- A break inside a ligature word (`oﬃ-` + `cial`) still finds the printed form.
- Emitted text keeps its ligatures.

**Survey** (`LigatureSurvey.swift`, [ligature-survey.txt](ligature-survey.txt)). It lists every
line-end hyphen decision, prose and address, with its warning, over all fifteen English books. It
ran in a `git archive 9803329` tree and in the candidate merged to `9803329` (no later merge touches
vocabulary or joins), and the outputs were diffed.

- Only Wallace has ligature words: 210 lines and 24 vocabulary words. NOAA has one line, whose
  spelled-out word was already known.
- Of 11,237 breaks, exactly two decisions change. Both are Wallace `dif-ferent` → `different`, on
  pages 50 and 218, and each page loses its only `uncertainHyphen`. Both were checked against the
  renders.

## #123 item 2: a spaced example line runs into its list item (Wallace page 64)

**Cause.** `Three more than a number becomes x + 3` sits 9.7 points under the item's wrapped line
`writing the second part plus the first`. The page's wrapped lines stand 2.4 points apart.
`continuesListItem` accepted any gap under 0.9 body once the hanging indent was established, so the
example ran on into the item. `Four less than…` did the same.

**Rule.** A line opening with a capital (past opening quotes and brackets) ends the item when its
gap is at least the page's ordinary wrapped-line gap at its size plus half a body.
`ordinaryLineGap` measures that ordinary gap: over lines of that size and ordinary height, it takes
the lower quartile of each line's gap to the nearest line directly beneath it on the same left edge,
inside the prose window.

- The median was tried first. Paragraph spacing (9.7 points) falls inside the prose window and on
  page 64 is nearly as common as the wrapped gap, so without crops the median landed on 9.7 and the
  rule did not fire.
- With no measurable gap, the rule does not apply.
- The sentence-end test of `opensSpacedParagraph` is not required, because Wallace's items carry no
  final period.

**Before/after.**

- **Wallace page 64:** the `More than` and `Less than` items end at their wrapped lines, and each
  example line is its own paragraph. This holds with and without crops.
- **CIA Blue Book pages 272 and 273** (outside the lane, reviewed against renders): the questionnaire's
  spaced answer rows leave their questions.
  - Page 272 is improved: `3. Where were you located when you saw the object:` no longer ends in
    `(Circle One): a.`.
  - Page 273 is mixed: `Yes or No` leaves question 7 correctly, but the paragraph branch then joins it
    to the following `IF you answered YES…` instruction (defect 2).
- No other page in any English contract book changed.

## Tests

`Tests/PDFReflowLibTests/FallbackBlocksAndLigaturesTests.swift`, 9 tests.

**New fixtures.**
- `cdc-14`, `cdc-23`, `cdc-34`, `algebra-50`, `algebra-64`, `algebra-218` were captured with
  `tools/capture-layout-fixture.swift`. Recaptures at `d35285f`, `e949bea` and `e002972` were
  byte-identical, and `cdc-26` recaptured identical to the committed fixture.
- `cdc-17-ocr` was captured with `tools/capture-ocr-layout-fixture.swift`, which now writes
  `readingDirection`. `SourceLayoutFixture` reads the new field. A recapture after merging `458a2e9`
  was byte-identical.

**The tests.**
- **`sourceBalloonBesideACaptionBoxReadsWhole`** (14, 34) and **`sourceFoodBalloonReadsBeforeTheBroadcast`**
  (23): exact block text in order, with characters conserved.
- **`interleavedBlocksNeedTwoCentredUnitsSideBySide`:** a synthetic balloon beside a box whose first
  rectangle overhangs it. The row sort alternates them, `ordered()` reads them whole, and one control
  isolates each guard:
  - a name beside its description;
  - left-aligned columns off each other's baselines;
  - uncentred units;
  - a third unit;
  - a box that starts beside the balloon's last line;
  - units stacked apart;
  - close centres;
  - a list line;
  - shared baselines;
  - an overhanging row piece.
- **`sourceRotatedOCRCaptionReadsInLineOrder`:** page 17.
- **`rotatedLinesReadAlongTheirAdvance`:**
  - both rotations;
  - controls: mixed directions, upright text, and a rotated line among upright ones;
  - `OCRReader.readingDirection` thresholds;
  - band scaling in `mergeBands`;
  - `TextLine` encoding.
- **`sourceDifferentJoinsOnTheBooksLigatureSpelling`:** pages 50 and 218 join with no warning and keep
  `diﬀerent` elsewhere. The negative control, without the spelled-out word, keeps the hyphen and warns.
- **`vocabularyRecordsLigatureWordsSpelledOut`:**
  - both forms are recorded, and no other compatibility form is folded;
  - joins across plain halves and across ligature halves;
  - control: an unseen word keeps its hyphen and warns.
- **`sourceSpacedExampleLinesStandApartFromTheirItems`:** page 64 with and without crops.
- **`addedSpaceUnderAWrappedItemOpensALine`:**
  - the Wallace geometry opens the example line;
  - controls: the ordinary gap, a lowercase opening, and no measurable gap.

**Contracts** (`tools/addcontract.py`).
- **CDC** (11 → 33 checks):
  - pages 14, 23 and 34 get `paragraphs` and `orderedText`;
  - page 17 gets `orderedText` on the lines' opening words only, because OCR text depends on the
    compiled models (#94).
- **Wallace** (172 → 178):
  - pages 50 and 218 get `paragraphs` plus `absentText` `dif-ferent`;
  - page 64 gets two `paragraphs`.
- The `basis` strings record the review.

## Verification

- **`swift test`:** 583 tests pass (574 at `458a2e9` plus 9).
- **`scripts/check-all.sh --fast`:** exit 0 on the final tree (583 Swift tests, 214 Python tests,
  8/8 concurrency trials, 6 fixture conversions, 13 policy conversions and 22 rejection/cleanup cases,
  with repeat identity).
- **Negative control, contracts.** The `458a2e9` baseline fails exactly the new expectations and
  nothing else: CDC 10 (page 14 ×3, 23 ×3, 34 ×2, 17 ×2) and Wallace 6. Page 14's opening line and
  page 34's `wow…` paragraph pass on both sides; they are the order anchors. The candidate passes.
- **Negative control and guard mutations, Swift** (`tools/mutate.py`, [guard-mutations.log](guard-mutations.log)).
  All 19 mutants are killed.
  - Removing each change kills exactly that change's reproducers: the block step, the rotated order,
    the ligature entries and the spaced-line rule.
  - Weakening each guard kills its control. `spaced-no-added-space` also kills #64's
    `fedAdvisoryCouncilItems…`.
- **Lane** (`tools/run_corpus_regressions.py` one case per call, `compare_conversion_runs.py
  --allow-different-converters --detail`, summaries in [lane/](lane/)). Every run passed EPUBCheck
  and the progress, memory and content gates. No image, navigation, marker or OCR text changed.

| Case | Checks | Changed pages | Review |
| --- | ---: | --- | --- |
| cdc-zombie-pandemic-2011 | 33 | 14, 16, 17, 23, 34 | fixed 14, 17, 23, 34; improved 16 |
| wallace-algebra-2010 | 178 | 50, 64, 218 | fixed; `warnings` loses two `uncertainHyphen` |
| faa-phak-8083-25c | 487 | none | |
| fed-explained-2021 | 166 | none | |
| gpo-911-2004 | 209 | none | |
| cia-blue-book-14-1955 | 9 | 272, 273 | improved 272; mixed 273 |
| Loper Bright, Our Flag, DGA, USGS, NBS, arXiv, Census | 91, 72, 55, 50, 17, 59, 54 | none | |

The lane was also run at `9803329` and `e002972`, with the same changed pages.

## Remaining gaps

- #123 item 3 is untouched: page 64's `• Is` bullet and its example are inside a formula crop.
  Without the crop, `x is 5 becomes x =5` still joins that item. It sits 1.2 points under the item's
  17-point marker rectangle, so the rectangle hides the added space.
- The block step reads two centred units only. A balloon beside two boxes, or beside uncentred
  lettering, keeps the row sort. Panel order across the page (#18) is unchanged.
- Warren and NOAA were traced but not converted by the lane. They are not contract cases.

## Defects to file

1. **A rotated OCR line's `fontSize` is its length.** On CDC page 17 it is 224.8 points, so the
   page's body size is 225. `OCRReader` sets `fontSize` to the box height. For a line with a
   `readingDirection`, that is the length along the text. Expected: the line's thickness. Nothing on
   page 17 depends on it today, but size-based rules (headings, joins, gaps) read the page wrongly.
2. **A spaced answer row joins the instruction beneath it.** CIA page 273's `Yes or No`, now out of
   question 7, runs into `IF you answered YES, then complete the following questions: 7.1 What
   direction…`. Expected: the answer row as its own paragraph. `opensSpacedParagraph` requires the
   previous line to end a sentence.
3. **Centred balloon and caption lines stay separate paragraphs.** CDC page 23's broadcast reads as
   `...coNr/Nues ro spreAd.` / `cdc is ure/Ne everyone…` / `stay in your Homes.` / `if you must…`, and
   page 34's `what Are you L o o k in g` / `f o r ?`. Expected: one paragraph per unit. The paragraph
   join requires a shared left edge.
