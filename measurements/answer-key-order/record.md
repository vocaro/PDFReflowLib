# Every answer key reads in number order, titles first (#185)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 (26A428) arm64, release CLI,
host terminal. Baseline: `f90a567` (converter `9761431d…`); candidate: `f90a567` plus the working
tree (converter `945e7376…`). No PDF or EPUB is committed.

Scope: #185's two defects (page 486's first key read across its rows; the titles of pages 463,
465 and 482 read after the first column) and, since #195 makes reading order the prerequisite for
lists, every other answer key the same causes misordered. Items 3 and 4 of #185 (page 423's `16`,
a label left behind a diagram) are untouched.

## What was wrong

Four causes, each confirmed on the page geometry with `survey-order.swift` (the order `ordered`
gives a page, with each crop's held numbers) and `pdftoppm` renders:

| Cause | Pages | Read before |
| --- | --- | --- |
| A crop hides its entries' numbers. Where a key column is all fractions the crop *is* the column, so #178's `readsDownColumns` saw one column, and a 16.6-pt gutter beside 131.8-pt crops fails the prose test | 486 (first key), 450, 451, 466, 469 | 486: 3–9, crop 17–29, crop 10–16, crop 30–40; 466: 37, 38, 20…24, 39, 40, 25… |
| A title sits closer over its key than `headingBand`'s 0.8 body (line boxes raised by exponents, crops padded above their fractions), so the gutter cut takes it with the column under it | most of the 36 pages below: 438, 442, 443, 446, 454, 458, 463–465, 467, 470, 477, 481, 482, 487, 488… | 463: 1–14, `Answers - Trinomials where a 1`, 15–40; 482: `Answers - Simultaneous Product` before `9.9` (`bulletColumns` lifts only the line crossing its gutter) |
| Two keys stacked on the same gutters: the gutter or `bulletColumns` cut fires before `numberedKeyBand` is reached, and the band also needed the lower key to read down columns | 441, 445, 462 | 441: 1, 15, 29, 2, 16, 30… (the next key is one row, continued overleaf); 462: 6.2's left column, then 6.3's, then 6.2's other two |
| `rowMajorLabels` found rows by height, and page 447's right column drifts 4.4 pt a row | 447 | 3, 6, 9, 12, 4, 7… |

## What changed

`Sources/PDFReflowLib/LayoutReconstructor.swift` only. No public API, option or warning changed.

1. **`Element.held`**, set in `blocks` from `heldLines` (the page lines a crop intersects, each
   given to the crop it overlaps most), and **`numberedMarkers`**: the `N)` markers of text lines
   and of the lines under crops. `numberedKeyBand` now counts both.
2. **`keyHeading`**, first in `ordered`: when a region's markers read down their columns, the
   single-element rows standing wholly above every marker, walked upward from the key, are read
   top-down before it (whatever stands above them is ordered first); failing that, the single rows
   wholly below the key close it (463's `6.5`).
3. **`numberedKeyBand` before every column cut** (it was last, #178), accepting a band where only
   the key above reads down when the key below opens on the band (441), and taking the widest band
   between the same two markers (448's labels over their graphs over the next key).
4. **`numberedColumns`**, after `numberedKeyBand`'s old place: when the markers read down their
   columns, the leftmost vertical line no element crosses (wider than 0.75 body) with markers on
   both sides — the narrow gutter the prose test refused (486).
5. **`rowMajorLabels`** counts rows down the columns instead of by height.

## Effect

Wallace: 36 pages change, all in the answer section (438–488), each a pure reorder — the same
blocks with the same text (`pagediff`). No exercise page changes. Every other corpus source is
identical page by page (`sweep-corpus-pages.py`, both CLIs over each cached source):
FAA, 9/11, Warren, Fed, DGA, Our Flag, Blue Book, CDC, NBS, Replay Clocks, USGS, Loper Bright,
Census, Pro Se, GWL, USDA, DASC, Earthdata, TechPort and NOAA.

Reading order, measured on the whole-book EPUB (`marker_order.py`; crops without MathML carry no
number there and are skipped):

| | Baseline | Candidate |
| --- | ---: | ---: |
| Answer-key runs out of order | 8 of 123 (190 markers) | **0 of 98** |
| Answer-key runs continued across a title or label (a title read inside its key) | 28 | 4 |
| Answer-key runs in order and consecutive (#194's `<ol>` rule) | 90 | 76 |
| Exercise runs out of order | 62 of 114 (1,203 markers) | 62 of 114 (unchanged) |
| Exercise runs in order / consecutive | 52 / 30 | 52 / 30 |

Fewer runs means fewer keys split by a misplaced title, so the in-order and consecutive counts
fall with them; the 76 consecutive runs are whole keys, not halves. Of the four remaining
continuations, three are an entry's wrapped line emitted as a paragraph (447, 456, 459) and one
is page 475's title (see gaps). Counting the numbers under crops (`survey_descents.py`), one answer
page still steps back other than to restart: 478, whose crops each merge entries of two columns.

The exercise sets are numbered two to a row (`1)` | `2)`) and read column by column **by
contract** (`rowMajorLabels`' doc, `columnNumberedGridsAndExerciseSetsKeepColumnOrder`, the Wallace
basis: "Exercise sets numbered two to a row (pages 10, 26) keep their column order"), so 62 of 114
exercise runs step by two. This change leaves them alone; reordering them is an owner decision
(#195), not a defect of this rule.

## Regressions added

`Tests/PDFReflowLibTests/AnswerKeyColumnsAndDiagramLabelsTests.swift`, on checksum-pinned
fixtures (new captures `algebra-441`, `-444`, `-447`, `-462`, `-482`):

- **every key in number order** on 441, 444, 447, 462, 463, 465, 482 and 486, crops' held numbers
  included: the numbering only steps back to restart at 1;
- **page 486's first key** reads exactly 3–40;
- **titles head their keys** on 463, 465, 482 and 444, and 463's `6.5` follows its key;
- **page 447's graphs** read 3–14, each label followed by its graph;
- the rules at measured geometry: `numberedColumns` (and no cut where the numbers do not read
  down across the gutter, or where the crop holds none), `keyHeading` (refused when the title
  shares its row), `heldLines` (a line under two crops counts once), and `numberedKeyBand` resting
  on the key above (and refused under a key's upper rows though a later key restarts at 1).

`corpus/regressions.json`: pages 438, 463, 465 and 482 tightened, and 441, 444, 445, 447, 450, 451,
462, 466 and 469 added, all phrases read from the candidate's output. Against the baseline EPUB
the new checks fail on 13 of the 14 pages (486's fix is image order, which only the unit test
sees); against the candidate all pass.

[guard-mutations.log](guard-mutations.log): each of the eleven single-guard mutations fails at
least one test.

## Verification

- `swift build -c release`; `swift test`: 1028 tests pass (1022 before).
- `python3 -m unittest discover -s tools -p 'test_*.py'`: 249 pass; `update_doc_counts.py --check`.
- All 21 corpus lanes, one case per call, on the candidate: every case PASS.

## What this does not prove

The rules read `N)` markers. A key whose markers are in its crops' pixels only (a scan) or in
another form (`a.`, `30.`) carries no evidence and is unchanged, as are keys that do not read down
their columns. The held lines are the lines a crop intersects; a crop that merges two columns'
entries (page 478) gives them in its own order, not the page's.

## Remaining gaps

- Page 475's title `Answers - Rational Exponents` reads after the left column: the left column's
  first crop rises 6 pt into the title's row, so the title is not alone in it.
- Page 478's crops merge entries of two columns (10–12 with 18–19; the whole 9.3 key is one crop).
- Page 455's last key (`4.5`, one entry) and similar one-row keys at a page foot carry too few
  markers to read columns from; `4.5` and its title read correctly there only by the band.
- Page 486's `10.4` is inside the crop of 10–16 and is lost as text (#185 item 4's family).
- The exercise sets' column-major order (above).

## Commands

```sh
swift build -c release
.build/release/pdf-reflow corpus/cache/Beginning_and_Intermediate_Algebra.pdf <out>.epub \
  --package-identifier urn:uuid:00000000-0000-4000-8000-000000000000 --modification-date 2026-01-01T00:00:00Z
python3 measurements/answer-key-order/tools/marker_order.py <out>.epub --list
# the reading order `ordered` gives a page, crops listed with the numbers they hold
swiftc -swift-version 6 -O $(ls Sources/PDFReflowLib/*.swift | grep -v 'EPUBWriter\|PDFConverter\|PDFReflowLibPipeline\|EPUBTextEncoder') \
  measurements/answer-key-order/tools/survey-order.swift -o /tmp/survey-order
/tmp/survey-order corpus/cache/Beginning_and_Intermediate_Algebra.pdf 441 486
python3 measurements/answer-key-order/tools/survey_descents.py /tmp/survey-order \
  corpus/cache/Beginning_and_Intermediate_Algebra.pdf 438 489
# both CLIs over every cached source, page by page, deleting each output
python3 measurements/answer-key-order/tools/sweep-corpus-pages.py <baseline CLI> <candidate CLI> <scratch> <case-id> …
```
