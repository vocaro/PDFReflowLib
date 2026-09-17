# Split and tight list markers, line-ending slashes (#69, #70)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, Xcode 27.0 (27A266a),
release CLI. Baseline: repository `6a5d67f`, built from `git archive 6a5d67f` into a scratch tree
(binary SHA-256 `ed2be19e…`). Candidate: `6a5d67f` plus the working-tree changes below (binary
`16ed9773…`). The work was developed on `b339e39`, parked in a WIP commit, merged with `6a5d67f`
(no conflicts) and soft-reset onto it. Every figure here compares those two binaries. The first
comparison, against `b339e39`, produced the same candidate blocks on every changed page of 9/11,
Wallace and Loper Bright. FAA and Fed differ only where `6a5d67f` itself changed the baseline.
No source PDF or EPUB is committed.

## What was wrong

**#69, split markers.** PDFKit splits some list markers from their item's text at the gap after
the marker. On 9/11 page 365 (`corpus/cache/GPO-911REPORT.pdf`, SHA-256 `657d4147…`), `4.`
(x 56.72, width 7.6) and `Neither the intelligence community nor aviation security experts ana-`
(x 68.65) sit on one baseline (y 263.35) as two lines. `4.` does not match `isList`, which requires
whitespace after the marker, so it became a `<p>4.</p>` and the item's text became a separate
paragraph. The survey shows this is far more common than the one page reported. In the FAA handbook
(`faa-h-8083-25c.pdf`, `247929ca…`), 495 bullets on 100 pages are split the same way: `•` at x 45,
its text at x 63. Neither piece is a list line, and the prose branch joins the bullet into the
*previous* block (its left edge is within 1.5 bodies of that block's), then opens an unmarked
paragraph for the text, which is 18 pt from the bullet. Page 27 read `…Following are some of those
reasons: •` / `Hazards, such as air shows…` / `•` / `Flights by important people…`, with each
bullet on the end of the item before it. Page text was right and block membership was wrong.

**#69, tight markers.** On 9/11 page 374, item `10.August 2001: the CIA and FBI…` is extracted with
no space after the period, so `isList` declines it and it became a paragraph after four `<pre>`
items (6–9). The same extraction gap produces `5.This` note continuations, which #11's note run
owns, and `22)17280` in Wallace.

**#70.** `joinOperation` repaired line-ending hyphens only. Any other join inserted a space, so FAA
page 365's `• Review NOTAM for information on runway/` + `taxiway closures…` read `runway/ taxiway`.
The native lines carry no trailing space, so the source gives no word break there.

## What changed

`Sources/PDFReflowLib/LayoutReconstructor.swift` only. No public API or default changed. The tag,
`ordered()` and cross-page continuation code is untouched.

- **`joiningMarkerPieces`** runs on a page's free lines (after image, stamp and shaded-table lines
  are set aside, and before labels, reading order, notes and footnotes see them). A *marker piece*
  is a line whose whole text is `•`, a number of up to three digits followed by `.` or `)`, or a
  single letter followed by `.` or `)`. Minus, hyphen and asterisk are excluded: alone, they are
  signs or rules (Wallace's fraction minus signs, Blue Book's OCR dashes). A marker piece joins the
  piece beside it when all of these hold:
  - it opens its row: no same-row piece starts to its left and ends within one of its font sizes;
  - the neighbour starts to its right within two font sizes (−1 pt overlap allowed);
  - the neighbour is the same size within 10%, is not monospaced, is in the same structure group,
    and is not itself a marker piece;
  - where several pieces qualify, the nearest one joins.

  The joined line is `marker + " " + text`, spans both rectangles, and takes the text's size and
  wrap flag.
- **`isTightMarker`**, a local test in `blocks`, lets the list branch accept a line
  `^[0-9]{1,3}\.\p{Lu}` only when at least two spaced numbered lines (`^[0-9]{1,3}\.\s`) on the page
  share its left edge (within half a body) and size (within 10%), and one of them is numbered one
  before or one after it. A digit after the period (a decimal, `1.1 INSIDE`, `10.30`) or a lowercase
  letter never qualifies. Notes the numbered-note run claims never reach the list branch. The
  marker is not rewritten: the item keeps `10.August`.
- **`joinOperation`** returns `.concatenate` when the left text ends in `/` preceded by a letter,
  digit or slash, and the right text starts with a letter or digit. A spaced slash (`China /`), a
  slash after other punctuation (only damaged OCR in the corpus) and a slash before punctuation keep
  the space.

`corpus/regressions.json` and `Tests/PDFReflowLibTests/TintedBoxTests.swift` had recorded the old
joins, and they now expect the new ones (details below).

## Corpus survey

`survey-markers.py` applies each rule to native line dumps (`dump-lines.swift`, the pipeline's
styled extraction) of the 15 English documents. It runs before furniture, image, table and note
handling, so its counts are upper bounds. Full listings: `survey-split.txt`, `survey-tight.txt`,
`survey-slash.txt` (NOAA and Blue Book detail truncated to 25 hits each).

| Document | Split-marker joins | Tight markers accepted | Line-ending slashes (join / keep space) |
| --- | --- | --- | --- |
| faa-phak-8083-25c | 529 on 100 pages (495 `•`) | 0 | 37 / 2 |
| wallace-algebra-2010 | 56 on 21 pages (`N)` + expression) | 0 | 0 |
| gpo-911-2004 | 1 (page 365) | 359 on 113 pages | 4 / 1 |
| scotus-loper-bright-2024 | 1 (page 5, `982.`) | 0 | 1 / 0 |
| cia-blue-book-14-1955 | 24 on 17 pages (OCR forms and tables) | 0 | 59 / 285 |
| fed-explained-2021 | 0 | 0 | 26 / 0 |
| noaa-nca5-2023 (outside the gate) | 9,714 on 632 pages | 0 | 1,764 / 6 |
| census-rrs2002-01 | 0 | 0 | 16 / 5 (damaged encoding; page images) |
| gpo-warren-1964 (outside the gate) | 0 | 0 | 2 / 1 (OCR) |
| dga, nbs, arxiv, usgs, cdc, our-flag | 0 | 0 | DGA 1 / 0, NBS 0 / 1, rest 0 |

Rejected by the split rule in the raw pattern survey: Warren's `36.`, `9.` and `•` beside
larger or smaller text (size), Wallace's `−` beside numerals (not a marker), Blue Book dashes. The
tight survey's other hits (Blue Book, Warren `45.W`, `5.S2.`) have fewer than two spaced siblings.
Of the 359 9/11 tight lines, all but page 374's sit on endnote pages. The note run owns them where
it validates a page, and elsewhere they become `<pre>` like their spaced siblings (below).

The slash rule's corpus cases are URLs (`www.faa.gov/` + `pilots/`, `https://` + `www.`),
`and/` + `or`, `AFM/` + `POH`, `L/` + `MF`, `turbojet/` + `turbopropeller`, and Fed's two-line table
labels (`Electronic Fund Transfer Act/` + `Regulation E*`). The spaced cases are `China /` +
`East Asia` (9/11 page 431, inside a preserved chart) and an NBS equation.

## Before and after

Release CLIs, library defaults, `tools/run_corpus_regressions.py` one case at a time, compared
with `measurements/list-continuations/compare-pages.py`
([page-comparison/](page-comparison/)) and a character-level page-text diff
([text-diffs.txt](text-diffs.txt)). **Every image in every book is byte-identical, and no heading
changed.**

| Book | `<pre>` before → after | Pages whose blocks change | Pages whose text changes |
| --- | --- | --- | --- |
| gpo-911-2004 | 294 → 323 | 13 | 4 |
| faa-phak-8083-25c | 510 → 1,022 | 113 | 30 |
| wallace-algebra-2010 | 3,278 → 3,285 | 6 | 0 |
| scotus-loper-bright-2024 | 7 → 7 | 2 | 1 |
| fed-explained-2021 | 111 → 111 | 11 | 14 |
| cia-blue-book-14-1955 | 666 → 687 | 14 | 3 |
| dga, our-flag, cdc, usgs, nbs, arxiv, census | unchanged | 0 | 0 |

**Every page-text change is the removal of the space after a line-ending slash (68 joins,
listed in `text-diffs.txt`).** No other text changed on any page, so reading order is unchanged
everywhere. All other differences are which block a marker or line belongs to.

The three reported pages, against 70-DPI `pdftoppm` renders:

| Page | `6a5d67f` | Candidate |
| --- | --- | --- |
| 9/11 365 | items 1–3, `<p>4.</p>`, then item 4's text as a paragraph | items 1–4, item 4 whole to `…for domestic vulnerabilities.`; its indented second paragraph `Richard Clarke told us…` follows as a paragraph |
| 9/11 374 | items 6–9, `10.August 2001…` a paragraph | items 6–10, item 10 holding its two wrapped lines |
| FAA 365 | `runway/ taxiway` | `runway/taxiway`; `and/or` inside a line unchanged |

Reviewed changes outside those pages:

- **FAA, 113 pages.** 88 pages keep exactly the same words, and each bullet moves from the end
  of the block above into its own item (23, 25–32, 35–39, 45, 47–49, 98, 99, 141, …; page 141
  confirms the old off-by-one: `The CG position influences…` is a bullet in the source). 6 pages
  (172, 190, 301, 319, 336, 425) change only from `<p>` to `<pre>` with identical text: lists the
  prose branch had already stitched together, now represented like every other list. On page 319,
  TAF items 1, 2, 5, 6, 8 and 9 join 3, 4 and 7 as items. The remaining 19 pages change only by
  slash joins, sometimes with a `<p>` to `<pre>` change; 11 of the 88 regrouped pages also carry
  one, making 30 slash pages in all. Page 28's FDC list reads `• Interim IFR flight procedures:`
  with its numbered sub-items and bullets in source order, checked against the render.
- **9/11.** Pages 484, 492, 519 and 528 rejoin URLs in the notes (`frontline/` + `shows/`,
  `dea/` + `agency/`, `releases/` + `2001/`). Pages 543, 571, 572, 578 and 581–583 are endnote pages
  the note run does not validate. There, spaced notes were already `<pre>` and tight notes (`101.Intelligence`,
  `194.For`, …) were paragraphs; now all are `<pre>`. On page 572, notes 4 and 5, which had been
  fused into one paragraph (`4.White House record… 2001. 5.White House transcript…`), are two items.
  No note page the run validates changed, and every `noteLinks` check passes.
- **Wallace 101, 132, 225, 323, 460, 481.** An exercise number PDFKit split from its expression
  (`17)` / `(− 16,− 14), (11,− 14)`) is one entry like its neighbours. Pages 10, 26, 438 and 471
  and the answer-key columns do not appear in the comparison. The survey's other split pieces
  (56 on 21 pages) change nothing in the output, because the pieces sit inside preserved regions
  or never reach a block of their own.
- **Loper Bright 5.** `982.` opens a justified line; the paragraph broke there and now continues
  (`…545 U. S. 967, 982. That regime is the antithesis of the time honored approach the APA
  prescribes.`), as the render shows. Page 57 rejoins a URL inside a page-bottom footnote, the
  only footnote change in any book.
- **Fed 27–125.** URLs and the page-120/121 regulation table labels (`Act/Regulation E*`), plus the
  page-64 header `International authority/deliberative body`.
- **Blue Book, 14 pages, all `unverifiedTextLayer` with the source image retained.** Questionnaire
  pages 266, 267, 272, 273, 275, 276, 284 and 285 improve (`1.` + `Date`, `12.` + `Describe what you
  saw…`). Two regress slightly: on page 276, item 22's wrapped line (`on the curved line…`) is now a
  paragraph instead of part of the prose block holding the question, and on page 275 `16.1 Sound`
  splits from question 16. Pages 158, 226 and 252 join an OCR table's `2.` / `J.` to its row junk.
  Pages 134, 147 and 169 join OCR junk across a slash after a letter or digit (`N,'R('h/Number`).
  Requiring a letter, digit or slash before the slash cut the Blue Book slash pages from 12 to 3.

## Contracts

`corpus/regressions.json`:

- FAA 191: the four bullets move from `paragraphs` to `listItems` and the ammeter paragraph reads
  `alternator/generator`. New pages: 27 (three bullets as `listItems`, the introducing paragraph)
  and 365 (`runway/taxiway` item, `Read back… and/or` control, `absentText` `runway/ taxiway`).
- Fed 64 table header and page-120 `orderedText` read `authority/deliberative` and
  `Act/Regulation`. New page 37 (`https://www.federalreserve.gov/monetarypolicy/bst_`).
- 9/11: new page 365 (item 4 whole; item 3 and the `Richard Clarke` paragraph as controls), 374
  (item 10 verbatim; item 9 as a control) and 492 (rejoined URL).
- Loper Bright: new page 5 (the paragraph through `982. That regime…`).
- Wallace: new page 101 (exercises 17 and 28; exercise 18 as a control).

Negative control, the content checker against the `6a5d67f` evaluations: 9/11, FAA, Wallace, Loper
Bright and Fed fail on exactly the new or changed expectations (3, 10, 2, 1 and 4 respectively) and
on nothing else. Every control phrase in those entries passes on both builds. Check counts grow
from 133 to 139 (9/11), 61 to 68 (FAA), 71 to 74 (Wallace), 90 to 91 (Loper Bright) and 110 to 111
(Fed, before #72's pages 4, 14 and 116 took it to 127 on `6c1ca16`). Merged with `6c1ca16`, the
file holds 792 checks on 167 pages, counted as `tools/check_corpus_content.py` counts them (one
check per listed phrase, one per `minimumImages`, `warningCodesAnyOf` or `absentWarningCodes`
entry). The per-case totals agree with the checker's own `contentChecks` on all 13 English cases.
`doc/regression-testing.md` quoted 621 on 129, stale since well before this change. Its count
sentence, per-type breakdown and test counts now reflect the merged tree.

Merged again onto `b9efcc9` (#47/#56 column cuts, which add 48 checks on 5 FAA and Wallace
pages): `b9efcc9` holds 822 checks on 164 pages and this change adds 18 on 8, so the file holds
840 on 172 (FAA 98, Wallace 92). The only conflict was the end of FAA's page list; both sides'
pages are kept. A three-way structural comparison against `6c1ca16` finds every case field and
page entry equal to the side that changed it, and no entry changed on both sides.

## Verification

- `swift test`: 336 tests pass (327 at `6a5d67f` plus 9 in `MarkerPieceTests.swift`); merged with
  `6c1ca16`, 342 pass (333 plus the same 9); merged with `b9efcc9`, 349 pass (340 plus 9). In one full
  run under a load average of 9 (the other agents' runs), `damagedEncodingIsFlaggedRetainedOrRecognizedByPolicy`
  failed on its Vision OCR expectations after 47 s and `spilledReconstructionIsRepeatableAndLeavesOnlyAssets`
  failed on repeatability. Both passed alone in 0.4 s and 75 s, and both passed in the
  `check-all` run below.
- `scripts/check-all.sh --fast`: exit 0 (336 Swift, 166 Python, 13 policy conversions and 22
  rejection cases, fixture conversions); merged with `6c1ca16`, exit 0 with 342 Swift; merged
  with `b9efcc9`, exit 0 with 349 Swift and the rest unchanged.
- Corpus lane, `tools/run_corpus_regressions.py --converter <CLI> --epubcheck
  /opt/homebrew/bin/epubcheck --execution-context host-terminal --case <id>`, both binaries:
  gpo-911-2004, faa-phak-8083-25c, wallace-algebra-2010, scotus-loper-bright-2024,
  fed-explained-2021, cia-blue-book-14-1955, dga-2025-2030, gpo-our-flag-2003,
  cdc-zombie-pandemic-2011, usgs-mcs2025-copper, nbs-jres-geltman-1977, arxiv-replay-clocks-2023
  and census-rrs2002-01. All pass EPUBCheck, progress and memory gates on both. Before the contract
  update the candidate failed only FAA 191 and Fed 64/120 (the old joins). After it, all pass with
  `tools/check_corpus_content.py`. That lane ran against `6a5d67f`.
- Corpus lane on the merged tree (this change on `6c1ca16`), the same command against the merged
  release CLI and a `6c1ca16` release CLI, for the cases whose contracts either side changed:
  - fed-explained-2021: merged passes every gate and all 127 content checks (peak RSS 292 MiB,
    37.7 s, 528 warnings). `6c1ca16` passes EPUBCheck, structure, progress and memory (297 MiB,
    31.9 s, the same 528 warnings) and fails exactly the four expectations this change edits:
    page 37's `bst_` line, page 64's two table headers and page 120's two `Act/Regulation`
    phrases. Output text is 25 characters shorter on merged (283,637 against 283,662), the joins.
  - faa-phak-8083-25c: merged passes every gate and all 68 content checks (peak RSS 790 MiB of
    its 1,280 MiB budget, 38.1 s). `6c1ca16` passes every gate (797 MiB, 37.7 s) and fails exactly
    the ten expectations this change adds or edits on pages 27, 191 and 365. Merged reports 1,473
    warnings against 1,450: 24 more `structureFallback` ("Caption, list or oversized heading
    tags…") on pages 29–436, and one fewer ("Tagged groups intersect…", page 191). A `•` rejoined
    to its item makes that tagged group hold a list line, which `structuredOrder` does not
    reorder, so those pages keep spatial order. A word-level diff of the two EPUBs has 65 hunks:
    33 slash joins (`AFM/ POH` → `AFM/POH`, `faa.gov/ pilots/`), 25 moves of the running
    `PHAK Front Matter` line within its page (the fallback pages), and three block moves, each
    now in reading order: the `Accountability Location` bullet beside its `•`, the `Crew Resource
    Management…` heading before its section instead of at the end of the previous page, and the
    glossary's `Instrument flight rules (IFR)` entry before `Instrument meteorological conditions`.
- Corpus lane on the tree merged with `b9efcc9`, against the merged release CLI and a `b9efcc9`
  release CLI built from `git archive b9efcc9`. The host load average was 18–33 (other agents'
  runs), so time and RSS vary between runs by more than the builds differ:
  - faa-phak-8083-25c: merged passes every gate and all 98 content checks (764 MiB, 66.2 s).
    `b9efcc9` passes every gate (669 MiB, 51.7 s) and all 30 of its own new column-cut checks, and
    fails exactly this change's ten expectations on pages 27, 191 and 365. Warnings are again
    1,473 against 1,450 and the text 33 characters shorter. The EPUB word diff has 41 hunks: the
    same 33 slash joins, 4 moves of the running footer, and two block moves, each now in reading
    order: the `Accountability Location` bullet beside its `•` and the `Crew Resource
    Management…` heading before its section. The glossary move and the other footer moves seen
    against `6c1ca16` no longer differ; the column cuts already order those pages.
  - wallace-algebra-2010: merged passes every gate and all 92 content checks (76 MiB, 21.5 s).
    `b9efcc9` passes every gate (77 MiB, 19.9 s) and its own 18 new column-cut checks, and fails
    exactly this change's two expectations: page 101's exercises 17 and 28. Both report 913
    warnings and the same 82,315 words in the same order; the change only regroups the split
    exercise entries.
  - gpo-911-2004 (its runs against `6c1ca16` stopped on a full disk and are not results): merged passes every
    gate and all 139 content checks (110 MiB, 13.5 s). `b9efcc9` passes every gate (113 MiB,
    15.2 s) and fails exactly this change's three expectations: page 365 item 4, page 374 item 10
    and page 492's URL. The 945 warnings are identical. The EPUB word diff has 6 hunks: 4 URLs
    rejoined after a line-ending slash (`frontline/ shows/`, `dea/ agency/`, `pages/ frontline/`,
    `releases/ 2001/`), and the print-job slug `201-635.job` in the chapter-39 endnotes, which
    moves from before note 53 to before note 52. It is furniture in both builds.
  - fed-explained-2021: merged passes every gate and all 127 content checks (189 MiB, 8.6 s).
    `b9efcc9` passes every gate (241 MiB, 8.3 s) and fails the same four expectations as
    `6c1ca16` did (page 37, page 64's headers, page 120's two phrases). Warnings (528) and
    output text lengths (283,637 against 283,662) are unchanged from the `6c1ca16` comparison.
- Negative control for the suite, [before-tests.log.gz](before-tests.log.gz): the new tests and
  the updated Fed-64 test compiled against the `6a5d67f` reconstructor, with a pass-through
  `joiningMarkerPieces` stub (it has no such member). All 10 fail with 33 issues, every one a
  reproducer expectation. The controls in the same tests pass on both trees: the four slash controls,
  seven marker-piece controls, six tight-marker controls, exercise 18 and FAA's `and/or` bullet.

Fixtures captured with `tools/capture-layout-fixture.swift` (recompiled at `6a5d67f`) from the
checksum-pinned sources: `911-365`, `911-374`, `faa-27`, `loper-5`, `algebra-101`. Captures of 9/11
374 and FAA 365 repeated byte for byte. The committed `faa-365` fixture differs from a fresh capture
only in lacking the newer `paints` key, so it is reused.

## Remaining gaps

- NOAA NCA5 is outside the gate: it fails the default output ceiling. The survey predicts 9,714
  split-marker joins there, almost all numbered reference entries (`1.` + `Canadell, J.G., …`) and
  bullets, and 1,764 slash joins. None was measured through a conversion.
- An item's indented second paragraph (9/11 365, `Richard Clarke told us…`) is a paragraph after
  the item, not part of it. The rules join lines; they do not build `<ol>`/`<ul>` semantics.
- A tight marker needs two spaced siblings on its edge. A list whose items are all tight, or whose
  only neighbours are also tight, stays prose. Wallace's `22)17280` form (`N)` + digit) is not
  covered.
- A slash after punctuation keeps its space even when the source means a join. The corpus has no
  such case outside damaged OCR.

## Defects to file

1. **Line-ending underscore in a URL joins with a space.** Fed page 37: `https://www.federalreserve.gov/monetarypolicy/bst_`
   / `openmarketops.htm.` reads `bst_ openmarketops.htm`. Expected `bst_openmarketops.htm`. The same
   policy question as #70, with a different character.
2. **Unvalidated 9/11 endnote pages lose their wrapped lines.** 9/11 pages 543, 571, 572, 578 and
   581–583 (for example 571's notes 194–208): each note is a `<pre>` holding only its first line,
   and the dedented wrapped lines are separate paragraphs after all the notes (`Report,” appendix 1,
   p. 1-1; Schwartz and Combs,…`). This predates this change, which only made the tight notes
   consistent with the spaced ones. Expected: each note whole, as on the pages the note run
   validates.
3. **Blue Book questionnaire item loses its wrapped line.** Blue Book page 276 (inherited OCR,
   source image retained): `22. In the fol:!.owing sketch, … Place an 11 A11` and its wrapped
   `on the curved line to show how high…` are now an item and a paragraph. Expected: one item.
   The wrapped line sits more than 2.5 bodies right of the marker, outside `continuesListItem`'s band.
