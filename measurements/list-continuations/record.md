# Wrapped list items and bulleted columns (#50, #64)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, Xcode 27, release CLI.
Baseline: repository `51d0b9e` (built from `git archive 51d0b9e` into a scratch tree with the same
`corpus/cache` symlink); candidate: `51d0b9e` plus the working-tree changes below. Both release
CLIs were built from those two trees and every figure here compares them. The work was developed on
`26d5209`, parked in a WIP commit, merged with `51d0b9e` (one conflict — the expectation-key list
in `tools/check_corpus_content.py`, where both sides add keys — resolved keeping both sides) and
soft-reset onto `51d0b9e`. Re-running the whole comparison against `51d0b9e` reproduced the
`26d5209` page comparisons byte for byte in all four changed books, so #62's furniture work and
these rules do not interact. No source PDF or EPUB is committed.

*Reproducibility.* Tagged books are reported to flip their `structureFallback` counts run to run on
this branch. Three baseline and three candidate Fed runs on this host each reported 118
`structureFallback` pages, and the three runs of each binary produced page-for-page identical
EPUBs — zero text, block or image differences. The Fed figures below therefore pair a baseline and
a candidate run that both report 118.

## What was wrong

`LayoutReconstructor.blocks` emitted one preformatted block per marker line and nothing else. A
line wrapped under a marker carries no marker of its own, so it fell to the prose branch and became
a paragraph beside the item it belongs to. `ordered()` separates columns by whitespace, and its
narrow-gutter guard demands two substantial prose lines on each side, so columns of short bulleted
entries never qualified; where a label spans the gutter there is no whitespace band to find at all.

Source review of the three reported pages, read against 80-DPI `pdftoppm` renders:

- **Wallace page 40** (`corpus/cache/Beginning_and_Intermediate_Algebra.pdf`, SHA-256
  `856bd81e…`). The 1.3 lesson's five-step list. Items sit at x 105.84 with 32.9 pt between them;
  item 4 wraps at `…then multiply or` and its continuation `divide)` sits at x 120.96 — 15.1 pt in,
  the width of `4. ` — only 2.7 pt below. The continuation became its own paragraph between items 4
  and 5.
- **Fed page 9** (`corpus/cache/the-fed-explained.pdf`, SHA-256 `8db8fd9e…`). The issue calls this
  a two-column list; it is not. It is one column: bullets at x 90, wrapped lines at x 103, all
  ~425 pt wide. The items are separated only by their markers (4.4 pt between an item's last line
  and the next bullet, the same as within an item), so nothing but the marker closes an item. All
  five bullets lost their continuations, the last one losing three lines.
- **Fed page 58**, the Box 4.2 panel that reflowed in #54. Three columns: bullets at x 106.75
  (continuations at 113.95) and x 236.70 (continuations at 243.90), then 8-pt prose at x 378.30.
  The label `Emergency lending facilities` runs 177.85–278.81, crossing the 215.55–236.70 gutter
  between the two bullet columns. `ordered()` cuts the wide gutter before the prose column, then
  finds neither a horizontal gap (the label spans it) nor a vertical one (the label sits 6.7 pt
  above the first bullet, under the 1.1-body threshold) and falls through to the reading-order
  sort, which interleaves the columns row by row. Items and their wrapped halves came out as
  `• Commercial Paper Funding`, `• Paycheck Protection Program`, `Facility`, `Lending Facility`, …

## What changed

`Sources/PDFReflowLib/LayoutReconstructor.swift` only. No public API or default changed; `isList`,
#39's `continuesParagraph`, #29's tight `N)−` markers, furniture, tags, notes and code handling are
untouched.

- `blocks` tracks the open list item (its marker line, its latest line, the hanging indent a
  wrapped line established, and the block holding it). Every other branch closes it, exactly as
  `codeOrigin` closes a code block, so a heading, image, table, box edge, tagged line, note group
  or ordinary paragraph ends the item.
- A new local `continuesListItem` joins a line into the open item when it carries no marker, is set
  no larger than the marker line, sits at ordinary line spacing (the same `-0.4…0.9` body window
  the prose branch uses) and starts more than a quarter body past the marker but within two and a
  half bodies of it — the width a marker occupies. The first wrapped line additionally requires the
  marker line to end mid-sentence: a marker line ending in `.`, `!` or `?` (past closing quotes and
  brackets) is as likely to be the whole item, and the indented line under it to open a paragraph.
  Once a wrapped line has established the item's indent, later lines join on that same edge within
  half a body, however their sentences fall. The join uses the ordinary `join`, so hyphen repair
  and its `uncertainHyphen` warning apply across the wrap.
- `ordered()` gains `bulletColumns` as a last resort, tried only after both whitespace cuts fail
  and before the reading-order sort. It reads the markers: at least four list-marker lines forming
  two runs, each run on its own left edge (within half a body) and the runs at least two bodies
  apart; every element at or below the topmost marker wholly on one side of the gutter between the
  runs; and that gutter at least as wide as the whitespace test's own `0.75 × body`. Elements
  entirely above the first marker are the columns' label and read first, then the left column, then
  the right. Anything crossing the gutter below the first marker — a note, a rule, a spanning row —
  rejects the cut and leaves the group to the sort.
- `continuation`/`appendPage` accept a trailing list item as a join anchor, through a new
  `joinableText`: a `.paragraph`, or a `.preformatted` block whose text opens with a marker and
  holds no preserved line break. A joined item keeps its preformatted representation. Every other
  test the cross-page join already applies (terminal punctuation, `fillsColumn`, `endsColumn`,
  `opensColumn`, structure groups, running heads) is unchanged, and a monospaced last line is
  refused, so code blocks never absorb the next page. Without this, #50 would have *lost* the Fed
  page 21→22 sentence that the baseline joined: the item is now one block, so the paragraph anchor
  was gone.

`tools/check_corpus_content.py` learns to see `<pre>` blocks the way it sees `<p>`: every `<pre>`
gets a document-wide identity, pages carry `listItems` and `listItemIDs`, and two contract keys use
them — `listItems` (one `<pre>` holds the whole phrase) and `continuedListItems` (one `<pre>` ends
this page with the first phrase and carries the second on the next). `continuedParagraphs` still
sees only `<p>`, so moving Fed page 21 to the new key keeps, rather than weakens, that control.

## Before and after

Release CLIs, library defaults, `measurements/list-continuations/compare-pages.py` over every page
of both EPUBs ([page-comparison/](page-comparison/)). **Every image in every book is byte-identical,
and no heading or note block changed anywhere.**

| Book | `<pre>` before → after | Pages whose blocks change | Pages whose text changes |
| --- | --- | --- | --- |
| fed-explained-2021 | 109 → 111 | 25 | 14 |
| wallace-algebra-2010 | 3,273 → 3,278 | 51 | 21 |
| gpo-911-2004 | 289 → 294 | 59 | 22 |
| faa-phak-8083-25c | 505 → 510 | 81 | 3 |
| scotus-loper-bright-2024 | 7 → 7 | 0 | 0 |
| gpo-our-flag-2003 | 7 → 7 | 0 | 0 |

The `<pre>` counts barely move because items absorb their continuations rather than multiplying;
the growth is the handful of items whose continuation now opens a page. Page text changes only
where reading order changed or where hyphen repair now applies across a wrap
(`reinvest-`/`ment`, `communi-`/`ties`, `regard-`/`less`, `day-`/`light`, `consum-`/`er`).

The three reported pages:

| Page | `26d5209` | Candidate |
| --- | --- | --- |
| Wallace 40 | 5 items, `divide)` a paragraph between items 4 and 5 | 5 items; item 4 is `4. Solve the remaining 2-step equation (add or subtract then multiply or divide)` |
| Fed 9 | 5 items + 5 stray paragraphs | 5 items, each holding its wrapped lines |
| Fed 58 | label, 7 truncated items interleaved with 7 fragment paragraphs | label, left column's 5 whole items, right column's 5 whole items, then the third column |

Hand review against source renders (`pdftoppm -r 80`): Fed 58's panel reads exactly as the source
sets it, including the source's own repetition of "Commercial Paper Funding Facility" in the left
column, which reflow reproduces rather than corrects. Fed 9 is one hanging-indent column, as the
render shows. Wallace 40's `divide)` hangs under `Solve`.

Reviewed changes outside the three pages:

- **Fed 18, 19, 21, 22, 38, 52, 61, 70, 75, 78, 79, 81, 90, 91, 113, 114, 117, 118, 123, 124, 129,
  130, 132**: bulleted and numbered lists absorb their hanging-indent lines. Pages 21→22 and
  129→130 hold items that wrap across the page break and are now one block each, with the page
  marker inside them. Page 22's five council entries run to several sentences under one marker and
  are whole.
- **FAA 48, 212**: bullets absorb their continuations; the only text change is hyphen repair
  (`get-`/`home-itis`, `equip-`/`ment`). Page 212's V-speed subscripts survive (the existing
  `PreformattedStyleTests` control still passes).
- **FAA 365**: a two-column page that interleaved line by line now reads left column then right,
  with whole paragraphs and whole bullets. Verified against the source render: three bullets and
  prose on the left, nine bullets on the right, in that order.
- **Wallace 62, 63, 69–71, 73, 76–78, 84–87, 94, 101, 123, 164–166, 172–174, 187, 191, 272, 273,
  286, 362, 363, 368, 369, 378, 379, 419**: word-problem exercise pages. Each numbered exercise is
  now one block holding its whole question instead of a marker line plus a stray paragraph. Every
  exercise is still its own block.
- **Wallace 440, 442, 443, 445, 446, 455–458, 464, 470, 477, 484, 487, 488**: answer-key pages
  whose columns interleaved (`10)− 6 19) 3 11)− 10 20) 0 …`) now read column by column
  (`10)− 6 11)− 10 … 18)− 15 19) 3 20) 0 …`). Verified against the page-440 render: three
  columns, 1–18, 19–36, 37–53. This is the interleaving half of defect 1 in
  [the #29 record](../exercise-numbering/record.md); the displaced section heading is unchanged.
- **Wallace 16**: six marker stubs left behind by the fraction crops reorder from 22, 23, 27, 28,
  30, 32 to 23, 27, 22, 28, 30, 32 — the book's own column-major order, matching page 10. The
  entries themselves remain split between a stub and an image (#29 defect 2, unchanged).
- **9/11 pages 5, 6, 36, 147, 182–190, 204, 205, 215, 270, 303, 344–356, 365, 373, 374, 383–389,
  395, 396, 405–445, 544, 583**: bulleted and numbered recommendation lists absorb their
  continuations; pages 543→544 and 129→130-style page-crossing items stay whole. No numbered-note
  page changed and every `noteLinks` check still passes.
- **Loper Bright and Our Flag**: not one block changed. Loper Bright page 64 is the control that
  shaped the terminal-punctuation guard (below).

## Verification

- `swift test`: 314 tests pass (305 at `51d0b9e` plus the 9 in
  `Tests/PDFReflowLibTests/ListContinuationTests.swift`). One run showed a `selectiveOCR…` failure
  that reproduced neither alone nor on re-run and took 76 s instead of 0.4 s — a Vision flake under
  concurrent load, not a change in behaviour.
- `python3 -m unittest discover -s tools -p 'test_*.py'`: 165 tests OK.
- `scripts/check-all.sh --fast`: exit 0 (314 Swift, 165 Python, 8/8 concurrency trials, 6 fixture
  and 13 policy conversions with 22 rejection cases).
- Corpus lane, `tools/run_corpus_regressions.py --converter .build/release/pdf-reflow --epubcheck
  /opt/homebrew/bin/epubcheck --execution-context host-terminal`, one output directory per run:
  fed-explained-2021, wallace-algebra-2010, gpo-911-2004, scotus-loper-bright-2024,
  gpo-our-flag-2003 and faa-phak-8083-25c all pass EPUBCheck, progress, memory and content gates.
  Fed grows 81 → 108 checks and Wallace 63 → 71; 9/11 (133), Loper Bright (90), Our Flag (67) and
  FAA (61) are unchanged from `51d0b9e`.
- Negative control, the `51d0b9e` CLI against the new contract: fed-explained-2021 and
  wallace-algebra-2010 fail on exactly the 16 new expectations (five page-9 items, the page-21
  continued item, four page-58 items and five page-58 ordered phrases, the Wallace page-40 item)
  and nothing else; 9/11, Loper Bright and Our Flag pass unchanged.
- Negative control for the suite, the new tests compiled against the `51d0b9e` reconstructor with
  the `bulletColumns` calls removed (it has no such member):
  [before-tests.log.gz](before-tests.log.gz). Five tests fail with 21 issues — the Wallace, Fed 9,
  Fed 58 and Fed 21/22 source tests and the synthetic wrapped-item case. The four controls
  (`loperWrappedCitation…`, `warrenSyntheticTextLists…`, `narrowGutterControls…` and the
  `ordered()` half of `bulletColumnCut…`) pass on both trees.

Fixtures captured with `tools/capture-layout-fixture.swift` from the checksum-pinned sources:
`algebra-40`, `fed-9`, `fed-21`, `fed-22`, `loper-64`. Re-capturing the existing `fed-58` fixture
reproduced the committed file byte for byte.

## Controls the rules had to satisfy

- **Loper Bright page 64** shaped the first-wrapped-line rule. `U. S. 134 (1944), the Court
  returned to its time-worn path.` is a wrapped citation #39 leaves preformatted; the paragraph
  under it opens on a first-line indent of exactly one body at ordinary spacing — geometrically
  identical to a hanging indent. Without the terminal-punctuation guard the rule swallowed
  `Echoing themes that had run throughout our law from its` into the `<pre>`. With it, the page is
  untouched, and so is the whole book.
- **Fed page 22** shaped the rest. Its council entries run to several sentences on one hanging
  indent, so applying the guard to every line truncated item 4 at `…members of the Board of
  Governors.` and left `The 15 CAC members…` behind. The guard now applies only to the line that
  establishes the indent.
- **Wallace pages 63 and 16** set the edge tolerance. PDFKit reports this book's left edges with
  about 3.5 pt of jitter (101.04, 104.52, 105.48, 108.48 within one item), so a quarter-body
  tolerance dropped the last line of exercises 33 and 38. The edge is measured once, from the first
  wrapped line, with a half-body tolerance, so jitter cannot accumulate.
- **9/11 page 451** (name/description rows), **the FAA page 91 and 511 columns**, **Our Flag page
  27**, the 9/11 contents page and the Wallace exercise and answer pages 10, 26, 438 and 471 are
  unchanged; 10, 26, 438 and 471 do not appear in the comparison at all. `bulletColumns` declines
  the 9/11 rows because they carry no markers, and the FAA columns are cut by whitespace long
  before the fallback is reached.

## Defects to file (reproducers)

1. **A list marker split from its own text at the same baseline.** 9/11 page 365: PDFKit extracts
   `4.` (x 56.72, width 7.6) and `Neither the intelligence community nor aviation security experts
   ana-` (x 68.65) as two lines on one baseline (y 263.35). Observed: a `<p>4.</p>` block followed
   by the item's text as a separate paragraph. Expected: one list item `4. Neither the intelligence
   community…`. The baseline glued the stray `4.` onto the end of the previous paragraph instead;
   neither reading is right. `sameRow` already recognizes this geometry for headings.
2. **A marker with no space after it is not a list.** 9/11 page 374 item `10.August 2001: the CIA
   and FBI do not connect…` extracts without the space, so `isList` declines it and the item is a
   paragraph among ten `<pre>` siblings. Expected: one item block. The same extraction gap produces
   `5.This` (which #39 deliberately protects) and `22)17280` in Wallace.
3. **A slash at a line end joins with a space.** FAA page 365: `• Review NOTAM for information on
   runway/` + `taxiway closures and construction areas.` now reads `runway/ taxiway`. Expected:
   `runway/taxiway`. `joinOperation` repairs line-ending hyphens only; a line-ending `/` inside a
   word is a second case.
4. **Hyphen repair misses a word the book uses once.** Fed page 19 item 3 now reads
   `including distribut-ing the nation's currency`, with an `uncertainHyphen` warning, because
   `distributing` appears nowhere else to vouch for the join. The halves were in separate blocks
   before, so no join was attempted; the policy itself is unchanged.

## Remaining gaps

- The rules join lines into one preformatted block; they do not build `<ol>`/`<ul>` semantics.
  That is the other half of the issues' intent and is untouched.
- A list item whose first line ends a sentence keeps its wrapped line as a paragraph. Without
  per-glyph geometry the marker's true text start cannot be measured, so the indent band and this
  guard are the available evidence; Loper Bright page 64 shows what the guard buys.
- `bulletColumns` needs two marker runs. A single bulleted column set beside a prose column that no
  whitespace cut separates still interleaves, and a spanning note *below* the columns rejects the
  cut entirely rather than being read after them.
- The cross-page join carries a list item, but only into a following `<p>`; an item split across a
  page where the next page's opening is itself a marker line is still two items, correctly.
- Fed page 58's blue label bands remain paragraphs rather than headings (#54's gap, unchanged), and
  Wallace's answer-key section headings are still displaced (#29 defect 1, unchanged).
