# Paragraphs across source pages (#45)

Tier: deterministic Apple PDF stack, library defaults, macOS 27 arm64 release CLI.
Baseline: repository `c16ee67`, Xcode 27.0 (27A266a), macOS 27.0 (26A428). `identity.json` pins
both converter binaries, the six English corpus sources and the eight new fixtures.

## What was wrong

`LayoutReconstructor.appendPage` joined page N's *last block* to page N+1's *first block* only
when both were paragraphs in the same structure group, the next text started lowercase, the
previous text lacked terminal punctuation, page N's last *extracted* line lay in the bottom 20% of
the page and page N+1's first *extracted* line in the top 20%. Diagnosing the three listed cases
against the source (renders in `/private/tmp` during the run; strips of every reviewed pair were
read by hand):

- **FAA 24→25.** No tag groups are involved (both pages fall back to spatial order). Page 25's
  first block is the figure 1-14 image that fills the head of the left column, so the first block
  is not a paragraph and no line is in the top 20%; page 24's last extracted line is the left
  column's (y 254 of 774) while the paragraph ending "…flight" ends the right column.
- **Fed 11→12.** Page 11's last blocks are the figure 1.3 map and its caption bar (two images);
  page 12's first block is the running-header rule preserved as an image. Both ends are images.
- **Replay Clocks 1→2.** Page 1's last block is a preserved region; the right column ends "…it is"
  at y 99.6 of 792 and the left column ends lower, so the position tests were not the blocker,
  the trailing image was.
- **9/11 folios.** Pages 126, 192 and 357 open chapters with a bottom folio instead of the running
  header, so `FurnitureDetector` has no three-page run and keeps `108`, `174`, `339`; pages 13 and
  15 keep `xiii`/`xv` the same way, and the next pages' retained headers `xiv COMMISSION STAFF` /
  `xvi PREFACE` start lowercase. Every old condition passed for the folio, which became the anchor.

A prototype of the block-order rule alone over dumps of every transition in the six books showed
the classes of false join it must refuse: bold run-in headings and captions in body type at the
foot of a page (9/11 270, 306, 310, 315, 340, 257), body prose swallowed into preserved regions
whose real continuation is the next page's first line (9/11 314; Wallace 57, 129, 279, 288; FAA
165, 199, 262 through wrong column order), a stray figure label opening a page (Replay 7→8
"sages/second."), and a trailing superscript note marker hiding a full stop (9/11 314 "…impact
zone.94").

## What changed

`LayoutReconstructor.appendPage` (with a new private `continuation` and helpers) now uses the
reading-order anchors and geometric evidence. The join rule:

1. **Anchors.** From the end of the accumulated blocks, step back over blocks of page N that are
   preserved images, captions (`^(Figure|Table)\s+[0-9]`) or bare folios (Arabic, `n-n` or Roman
   numerals whose line sits in the outer 10% bands); the previous paragraph P is the next block
   and must begin on page N or span into it. From the start of page N+1's blocks, step over the
   same kinds; the next paragraph Q is the first remaining block. Headings, preformatted items and
   other paragraphs are never stepped over.
2. **Identity.** Two different validated structure groups refuse; an untagged side keeps the
   heuristic (FAA tagged page 52 continues on the untagged page 53, 34→35 likewise).
3. **Text.** Q starts lowercase; P does not end in `.!?:` looking past closing quotes/brackets
   and past superscript runs (note markers).
4. **Lines.** P's last line is the longest page line that is a suffix of its text (joins append
   the right-hand line verbatim); Q's first line is the longest prefix, allowing for a
   line-ending hyphen the following join removed.
5. **Header.** Q's first line is refused when it is in the top 10% band, under 100 characters,
   opens or closes with a folio-like word and is separated from the text below it (or alone).
6. **Prose and fill.** Q's first line has at least two alphabetic words. P's last line has at least
   three, is at least 12 body sizes wide and fills its column: the column is the same-size lines
   sharing its left edge within 0.5 body (widening to 1.5 body, then the page, until three lines
   exist); if at least 60% of those reach the widest edge within 0.5 body the column is justified
   and P's line must reach it too, otherwise the line must cover 75% of the measure to the
   third-widest line. A line ending in `-` or a soft hyphen fills by definition.
7. **Neighbours.** No other prose lies below P's last line in its horizontal span or entirely to
   its right, and none above Q's first line in its span or entirely to its left. A competing line
   counts when it is at least half as wide as the anchor (90% for the beside tests, so a name
   column beside a hanging-indent entry does not count), is not a caption or margin folio, and,
   when it lies inside a preserved region, is the anchor's font size (labels do not count;
   swallowed body text does).

On a join the stepped-over blocks of page N (folio, figure, caption) are placed *before* the
joined paragraph so they keep their page; the inline source marker stays at the text boundary.
Page N+1's stepped-over leading blocks follow the paragraph as before. `PDFReflowLibPipeline`
passes each page's preserved-region rectangles (and the previous page's) to `appendPage`; the two
new parameters default to empty for existing callers. No public API or default changed.

`tools/check_corpus_content.py` gains `separateParagraphs` (`{"end", "next"}` that must both exist
as paragraph text and must *not* share one element across the marker), with negative controls in
`tools/test_corpus_content.py` (absorbed folio fails, folio moved after the marker fails, missing
phrases fail, malformed expectations raise).

## Source evidence

Eight layout fixtures were captured from the checksum-pinned sources with
`tools/capture-layout-fixture.swift` and read against the rendered pages: FAA 24/25 (right column
"…health and medical facts, flight" / left column "safety, a pilot/controller glossary…" under
figure 1-14; both printed folios kept), Fed 11/12 ("…the effective conduct of monetary" above
figure 1.3 / "policy began to require…"), Replay Clocks 1/2 ("…when we replay the log, it is" /
"possible that the white LED event…") and 9/11 126/127 (folio `108` below "…in aid to
theYemeni terrorists who" / "set a bomb in an attempt to kill…"). Fixtures keep every line; the
tests drop the running headers the pipeline removes.

`Tests/PDFReflowLibTests/PageContinuationTests.swift`, eleven tests: the four source pairs (one
paragraph across the marker, `page` on the first page and `sourcePages == [next]`, figures and
folios kept on their page ahead of the paragraph, the folio never absorbing text, neighbouring
paragraphs intact); synthetic justified columns where figure labels and a caption between the
halves join while two swallowed prose lines refuse (and join without the region), a short run-in
heading and a numbered item at the foot stay separate, a retained `xiv PREFACE` refuses while a
short final line at the head of the page joins, a hyphenated last line and a 75%-measure ragged
line join while a 65% line refuses, a superscript marker after a full stop refuses while the same
marker after an open sentence joins, one untagged side joins while two identities refuse, and a
left-column anchor beside right-column prose refuses.

## Verification

- `swift test`: 220 tests pass (3 suites). Existing continuation tests
  (`pageContinuationIsTestableWithoutPDFOrEPUB`, the numbered-note cross-page test,
  `proseReflowsAndHealsOnlySupportedHyphens`, `explicitParagraphBoundariesPreventHeuristicPageJoin`)
  pass unchanged.
- `scripts/check-all.sh --fast`: 220 Swift tests, 143 Python tests, 8/8 concurrency trials, the
  fixture and policy conversions pass (0:56).
- `python3 tools/run_corpus_regressions.py … --case` for arxiv-replay-clocks-2023,
  scotus-loper-bright-2024, fed-explained-2021, wallace-algebra-2010, gpo-911-2004 and
  faa-phak-8083-25c: all six pass EPUBCheck, progress, memory and content gates
  (`corpus-summary-five.json`, `corpus-summary-faa.json`; 20/25/45/63/71/61 content checks).
- New contracts (`corpus/regressions.json`): `continuedParagraphs` on FAA 22, 24 and 52, Fed 11
  and 21, Replay 1, 9/11 126, 192 and 357; `separateParagraphs` on 9/11 13, 15, 126, 192 and 357;
  `paragraphs` on 9/11 127. The six existing continuation checks are the controls. The lane now has
  435 checks on 103 pages (15 continuation, 5 separation). Against the *before* outputs the same
  contracts fail exactly on the new pairs (`before-contracts.json`: FAA 3 errors, Fed 2, Replay 1,
  9/11 8, including "paragraph wrongly continues" for `108`, `174`, `339`, `xiii`, `xv`).
- `tools/compare_conversion_runs.py` still refuses these runs (no capability probe);
  `compare_joins.py` instead lists every cross-page paragraph per book through
  `tools/check_corpus_content.read_pages` (`joins-before-after.txt`) and `text-changes.txt`
  classifies every page whose paragraph list changed.

## Before and after

| Book | Cross-page paragraphs before → after | Gained | Lost | Page text changes |
| --- | --- | --- | --- | --- |
| faa-phak-8083-25c | 10 → 122 | 112 | 0 | 88 pages: caption/folio blocks now precede the joined paragraph (same texts) |
| fed-explained-2021 | 0 → 30 | 30 | 0 | 4 pages: line-ending hyphen removed at the join |
| arxiv-replay-clocks-2023 | 0 → 3 | 3 | 0 | none |
| gpo-911-2004 | 170 → 171 | 4 | 3 | 4 reorders, 3 hyphen removals |
| wallace-algebra-2010 | 17 → 22 | 5 | 0 | 1 hyphen removal |
| scotus-loper-bright-2024 | 0 → 0 | 0 | 0 | none |

Image lists are identical on every page of every book. Every gained join (154) was reviewed
against half-page strips of the source foot and head: each is a mid-sentence continuation whose
anchor is the last body text of its page and whose continuation is the first body text of the
next, with only figures, captions, boxes, folios or a removed header between them. The three
lost 9/11 joins are the intended refusals: `xiii` no longer absorbs `xiv COMMISSION STAFF`, `xv`
no longer absorbs `xvi PREFACE`, and page 17's body paragraph no longer absorbs the header
`xviii PREFACE` (its true continuation stays split behind the retained header, #40). On pages
126, 192 and 357 the folio is a separate paragraph on its own page and the body paragraph is the
one that continues; the FAA and Wallace joins that an interim rule lost (435→436, 152→153; 9/11
335→336, 365→366, 452→453) are all restored.

## Remaining gaps

- Continuations across a page that holds no body text (9/11 256→258 around the photo insert) are
  not joined; the rule only looks at adjacent pages.
- A genuine continuation whose first body line sits behind a retained running header stays
  split (Loper Bright 64, 107; 9/11 17→18); removing headers is #40.
- Ragged-right columns join only when the last line covers 75% of the measure; a shorter
  ragged last line is a missed join, not a false one.
- Reading-order defects and preserved regions that swallow prose now *refuse* the join rather than
  corrupt it (FAA 165/199/262, 9/11 270/306/314/315/340/373, Wallace 57/129/279/288), so those
  paragraphs stay split until the underlying defects are fixed.
- Paragraph starts marked only by indentation (Replay, 9/11) are still merged by the existing
  per-page segmentation; the join does not change that.

## Defects observed, not fixed

- gpo-911-2004 pages 270, 306, 314, 315, 340 (and, by page-text length, most of 147–347): body
  prose is preserved inside image regions. Page 314's only image is the lower two-thirds of the
  page's text ("North Tower." through "…in stair-"); page 270 loses the three paragraphs after
  "Moving to Departure Positions"; page 306 loses the whole body below the figure. Expected: the
  prose reflows as text with the figure alone preserved. The `imageRegion` warning fires but calls
  it a graphical region.
- faa-phak-8083-25c page 199: the two body columns are interleaved line by line (each line its own
  paragraph, alternating columns), like the known page-91 defect. Expected: complete left column,
  then right.
- faa-phak-8083-25c pages 165 and 262: when a figure occupies the head of the left column, the
  right column's first paragraphs are ordered before the left column's text. Expected: left column
  (figure, caption, text), then right.
- faa-phak-8083-25c page 165: the five-line paragraph above figure 7-8 ("When operating altitude
  increases, the tachometer may not…") is swallowed into the figure's region by whole-line
  expansion. Expected: text.
- wallace-algebra-2010 pages 57, 129, 279, 288: example/formula regions swallow adjacent prose
  lines (page 279 loses "…The trick for conversions will", the sentence that page 280 completes).
  Expected: only the formula lines are preserved.
- arxiv-replay-clocks-2023 page 8: the axis label of figure 5 splits across the region boundary,
  leaving "sages/second." as a stray paragraph. Expected: the label stays inside the figure.

## Post-merge results (branch tip 95ff5b7)

The work was merged onto dc81a78 (#36 region rewrite, #28 raster tooling) and then 95ff5b7
(#38 encoding check) with temporary WIP commits and `git reset --soft`; conflicts were only in
the doc counts, the third-party fixture list and the checker's expectation-key list, resolved by
keeping both sides. The baseline for this section is a dc81a78 build (`identity.json`,
`postMerge`). Counting the way the checker counts (one check per `warningCodesAnyOf` /
`absentWarningCodes` expectation), this change adds 15 contract checks (9 continuation, 5
separation, 1 paragraph) on 10 pages: 502 checks on 122 pages after the merge. The "21 new
checks / 435" figures above counted warning lists by length and are superseded.

One guard was added after the merge review: both anchor lines must be at least half letters
(`readsAsProse`), because the dc81a78 build's rule joined an inherited-OCR table row on Blue
Book page 232 (`0 6 lip&,, tJ.() w. a,g …` onto `rt,- Pa Cent Numbet …`). With it, no other join
in any book changed.

Gates on the final tree: `swift test` 238 pass; Python tool tests 157 pass;
`scripts/check-all.sh --fast` exit 0; the complete corpus lane passes all 13 gated cases
(`corpus-summary-*.json`: FAA 61, Wallace 63, 9/11 71, Fed 45, Replay 20, Loper 25, DGA 14,
Our Flag 59, CDC 11, Blue Book 9, USGS 36, Census 54, USCIS 9, IRS 12, NBS 13 checks).

| Book | Cross-page paragraphs dc81a78 → final | Gained | Lost | Page text changes |
| --- | --- | --- | --- | --- |
| faa-phak-8083-25c | 10 → 129 | 119 | 0 | 95 pages: caption/folio blocks precede the joined paragraph |
| fed-explained-2021 | 0 → 30 | 30 | 0 | 4 hyphen removals |
| arxiv-replay-clocks-2023 | 0 → 3 | 3 | 0 | none |
| gpo-911-2004 | 240 → 240 | 5 | 5 | 4 reorders, 4 hyphen removals |
| wallace-algebra-2010 | 18 → 24 | 6 | 0 | 1 hyphen removal |
| gpo-our-flag-2003 | 0 → 3 | 3 | 0 | 3 reorders |
| cia-blue-book-14-1955 | 0 → 2 | 2 | 0 | 4 reorders |
| census-rrs2002-01 | 5 → 3 | 1 | 3 | 19 pages, 18 image changes: all from #38 (the baseline lacks it) |
| scotus, dga, cdc, usgs, uscis, irs, nbs | unchanged | 0 | 0 | none |

Image lists are identical on every page of every book except Census, where #38 changes the
pages themselves. #36 raised the 9/11 baseline from 170 to 240 joins by freeing swallowed prose.
Joins new since the c16ee67 review were read against source strips: FAA 100, 130, 152, 154, 194,
195 and 279 (all mid-sentence continuations, page 279's foot "…would subtract these" / "two sets
of numbers"), Wallace 279 ("The trick for conversions will" / "be to use the correct fractions",
now unswallowed by #36), 9/11 582 ("per-" / "haps"), Our Flag 10, 22, 23, Blue Book 21 and 87
(typed OCR prose), and Census 9→10 on #38's recovered text ("…if one cares" / "how much
individual data records are perturbed"). The Census losses are garbage-encoding pages that #38
now recognizes. 9/11 loses two more baseline joins beyond the three intended folio/header
refusals: 331→332 was a false join of the photo caption "United Airlines Flight 93 crash site,
Shanksville, Pennsylvania" onto "sons in integrating…" (the real "les-/sons" continuation spans
the photo page 331, a known gap), and 254→255 where extraction isolates the final word "told" of
page 254 as its own line and block, so neither the baseline ("told the muscle hijackers…"
without "Hawsawi") nor the final output ("told" alone) is right; the new rule refuses the
one-word anchor.

Listed defects re-verified on the merged output (`defects-after-merge.txt`):

- Fixed by #36: 9/11 270, 314, 315, 340 (prose present); Wallace 57, 129, 279 (prose present);
  FAA 165's tachometer paragraph is present.
- Still reproduce: 9/11 306 (the body below the stairwell figure still ends before "beyond the
  contemplation"; 724 characters, 2 images); FAA 199 (columns interleaved line by line); FAA 165
  and 262 (right column ordered before a left column whose head is a figure); Wallace 288 ("We
  can use the product rule…" and "The trick in this" still inside regions); Replay 8 ("sages/
  second." stray label); 9/11 254 (final word "told" extracted as its own line).
