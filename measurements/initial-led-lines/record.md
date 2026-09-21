# Initial-led lines with nothing running on, and a coincidence read as a table (#171)

Tier: deterministic Apple PDF stack, library defaults, macOS 27 arm64 release CLI.
Baseline: repository `4d5d86d` ("Re-measure #130 over the two merges taken since, and spell
center"), the tree this change is measured against and the commit the baseline release binary was
built from. `corpus-blocks.json` holds the per-case numbers quoted below, both lanes.

## What was wrong

#39 gave a marker-leading line a reading only when a paragraph was already open above it:
`continuesWrapped` decides whether `U. S. 967, 982–983 (2005).` wraps into the sentence before it.
The line that arrives with **nothing running on** had no reading at all. Every such line — every
match of `^(?:[0-9]+|[A-Za-z])[.)]\s` that `continuesWrapped` refused, and every one that had no
paragraph to be refused from — went straight into a standalone `.preformatted` block, so a name's
initial, a page reference and a citation came out as list markers, in monospace, and the lines the
page wrapped under them were stranded in a paragraph of their own.

Four of the issue's cases are that one mechanism, read on four books:

- the 9/11 report's staff pages (physical 13 and 14) stand twenty-five names on one edge and open
  four of them with an initial: `T. Graham Giusti`, `L. Christine Healey`, `C. Michael Hurley`,
  `R. William Johnstone`;
- the FAA handbook's page 18 opens a paragraph on `P. E. Fansler, a Florida businessman living in
  St. Petersburg,` and wraps two more lines under it, which became a separate block;
- Loper Bright's page 64 opens on `U. S. 134 (1944), the Court returned to its time-worn path.`,
  the end of a sentence page 63 began;
- the 9/11 report's notes run `p. 11; Peter Zalewski interview (Sept. 23, 2003).`,
  `v. Enaam Arnaout, No. 02-CR-892 (N.D. Ill. filed Jan. 6, 2003).` and
  `2001. For the Vice President's statement, …` as items, most of them cut from their own wraps.

A second, unrelated reading produced the same symptom on the FAA handbook's acknowledgments
(page 5). `TableRegionDetector.rowBlocks` reads a run of at least three rows on one edge, at one
size, at one leading, as a table the page set without rules, where the page also states a column
boundary. One of the two things it accepts as that boundary is "a column of numbers on a common
right edge": at least three rows ending within half a body of one edge, with two rows in three
ending in a digit. That page names a chapter at the end of every credit — `(Chapter 1)`,
`(Chapter 3)`, `(Chapter 8)` — so every row ends in a digit, and of its twenty ragged right edges
three (543.5, 546.0, 550.4) fall within half a body of one another. Three rows out of twenty are
a coincidence, not a column, and the whole credits list came out as `<pre>` rows with the two
credits that wrap split from their second lines.

## What changed

**One reading, from the page's own edge.** `MarkerColumn` gains `setsAList`, measured where the
rest of it is measured, in `LayoutReconstructor.markerColumn`. A list marks its items and its
markers advance, so the page has set no list on a line's own edge when all of:

- it stands at least eight lines of that line's size within half a body of that edge
  (`MarkerColumn.shortestUnmarkedRun`); below eight the edge states too little either way — a
  list of one item and a marker introduced by two lines of prose look alike;
- fewer than a quarter of them open with a marker at all;
- and the markers of the line's own kind, read top down, do not run on: fewer than half of the
  steps between them increase.

The 9/11 staff column marks four lines in twenty-five and numbers them `T`, `L`, `C`, `R`, which
run in no order. The Fed book's page 19 sets three of a bank's duties among its prose on one edge
and numbers them 2, 3, 4, which do; it keeps its items. Where the page set no list,
`BlockAssembler` opens a paragraph on the line instead of a preformatted item. That paragraph
takes only the wraps standing on its opening line's own edge, within half a body: the one and a
half bodies the ordinary column test allows would swallow the next paragraph's first-line indent,
which is exactly what Loper Bright's page 64 sets eleven points of under `U. S. 134 (1944), …`.

**A column of numbers is a column.** `TableRegionDetector.statesAColumn` now asks the numeric
right edge to hold for most of the run rather than for three rows of it. Nothing else about the
row reading changes: the cell the extractor kept apart, which is what reads the 9/11 report's
flight timelines and its list of illustrations, is untouched.

Over every layout fixture in the suite, that second change moves exactly one page — `faa-5` — and
leaves the row blocks of `911-9`, `911-50`, `911-51`, `911-451`, `algebra-17`, `algebra-479`,
`blue-5`, `faa-459`, `flag-27`, `noaa-1053`, `noaa-1054`, `p596-24`, `p596-25`, `p596-26`,
`p596-27`, `usgs-1` and `usgs-2` exactly as they were.

## What moved, per book

Whole corpus, library defaults, both lanes run on this host: 18 of 18 cases pass in each,
`runPassed` read from every case's own `result.json`, with EPUBCheck 5.3.0 and the reviewed
content contracts. Preformatted blocks fall from 7,049 to 6,875 across the eighteen books; the
total block count moves by one, from 57,551 to 57,552.

| case | blocks | `<pre>` | words |
| --- | --- | --- | --- |
| arxiv-replay-clocks-2023 | 261 → 260 | 6 → 5 | same |
| cdc-zombie-pandemic-2011 | 523 → 523 | 1 → 1 | same |
| census-rrs2002-01 | 412 → 412 | 139 → 138 | same |
| cia-blue-book-14-1955 | 25,429 → 25,429 | 799 → 730 | same |
| dga-2025-2030 | 161 → 161 | 8 → 8 | same |
| faa-phak-8083-25c | 9,163 → 9,161 | 1,342 → 1,316 | same |
| fed-explained-2021 | 1,095 → 1,094 | 120 → 116 | same |
| gpo-911-2004 | 5,146 → 5,125 | 1,427 → 1,397 | 298,730 → 298,728 |
| gpo-our-flag-2003 | 693 → 693 | 13 → 13 | same |
| gpo-warren-1964-suspect-text-excerpt | 23 → 22 | 2 → 1 | same |
| irs-p596-zhs-2025 | 1,176 → 1,176 | 65 → 65 | same |
| nbs-jres-geltman-1977 | 46 → 46 | 1 → 1 | same |
| ntrs-20180003024-earthdata-slides-2018 | 191 → 191 | 14 → 14 | same |
| scotus-loper-bright-2024 | 734 → 731 | 7 → 3 | same |
| uscis-m618-arabic-2015 | 1,408 → 1,408 | 53 → 53 | same |
| usda-ars-agresearch-2012-11 | 1,167 → 1,198 | 39 → 7 | same |
| usgs-mcs2025-copper | 24 → 24 | 0 → 0 | same |
| wallace-algebra-2010 | 9,899 → 9,898 | 3,013 → 3,007 | 83,138 → 83,137 |

No book's words change except by hyphen repair, which is what joining a broken line is for. The
three the 9/11 report gains are `command-and-` / `control`, `inter-` / `rogation` and `mate-` /
`rials,`; Wallace's one is `com-` / `plete`. Every other book is word for word identical.

*Agricultural Research* moves most: its index sets three columns of entries whose baselines the
extractor shares, so the numeric right-edge coincidence held over the whole index and every
printed "row" joined entries from different columns —
`no-till spring cereal rotations reduce, Jul-19 ARS methods for food analysis, Mar-4, 8` is two
entries of two columns. Thirty-two of its `<pre>` blocks become 63 paragraphs, one per entry.
The interleaved reading order of that index is #174's and is unchanged.

The CIA report's 69 released blocks are the OCR of handwriting inside its questionnaires
(`0. 0`, `2. I _? 10.D 5./J`), which were never items of a list. Loper Bright's four are
citations opening a page: `M. Hale, The History and Analysis of the Common Law of`,
`F. Bacon, The Lord Keeper's Speech in the Exchequer`, `102. But, in truth, the Constitution,`
and `U. S. 134 (1944), …`, the first three of which now carry the wraps beneath them.

## What this cost

Two lists lose their consistency where the page break falls inside them, and the record names
them rather than rounding them off:

- The Fed book splits a four-item list over source pages 18 and 19. Item 1 stands alone on
  page 18, where it is the only marker on its edge, so it reads as a paragraph; items 2, 3 and 4
  advance on page 19 and keep their blocks. The same happens to the advisory-council list, whose item 1 ends source page 21 and
  whose item 2 opens page 22.
- The Census paper's page 5 prints `3. If R < Tx, then designate pair as a nonlink.` with items
  1 and 2 inside a preserved equation region, so the page hands over one marker with nothing to
  advance from, and it reads as a paragraph.

A page-crossing list is what an unported cross-page join would settle
([#231](https://github.com/vocaro/PDFReflowLib/issues/231) holds that reconciliation); nothing
about the marker's own edge can see the page before it.

## What this does not fix

Replay Clocks' page 10 keeps `[8] D. L. Mills. Network time protocol (ntp). RFC 958, RFC Editor,
September 1985.` and its four neighbours as preformatted rows. Those entries are not marker-led
at all — they open with `[8]`, which no marker pattern matches — and they are rows because the
page outdents each citation number and sets the entry at a hanging indent, which has exactly the
shape of a two-column table: three of the eleven rows hand back a first cell the extractor kept
apart, and merged rows reach across the boundary. Two guards were tried and measured and both
were dropped: requiring the split rows to be most of the run, and requiring most of the run's
rows to open on the run's own edge. Each released the references, and each also released the 9/11
report's flight timelines on pages 50 and 51 (`8:19 Flight attendant notifies AA of hijacking`
shatters into seven fragments), the Blue Book's contents, the FAA handbook's cruise table and the
USGS copper statistics. Reading a hanging indent apart from a two-column table needs its own
evidence, and this change does not have it; it is filed afresh as
[#268](https://github.com/vocaro/PDFReflowLib/issues/268).

The rest of #171 is reported on the issue: items 2, 3, 4, 5, 6 and 7, with the mechanism found
for each.

## Re-measured over the merge taken since

`main` moved to `fbc5e1f` ("Place a box a cross-page join steps over on its own side of the page
marker") between the measurement above and the merge, taking #203's printed-row markers with it.
Both lanes were run again on the merged tree, against a release binary built from `fbc5e1f`.
Every book moves the same way, book for book, and no book that was untouched is touched now; only
the absolute counts move, because #203 had already released 380 of Wallace's preformatted blocks
and 19 of the CIA report's. Preformatted blocks fall from 6,650 to 6,476 on that baseline, the
same 174, and the total block count again moves by one, 57,369 to 57,370. The 9/11 report gains
two hyphen repairs rather than three — `command-and-` / `control` was already closed on the new
baseline — and Wallace's one is unchanged; every other book is still word for word identical.
All 18 cases pass in each lane. `corpus-blocks.json` holds these numbers, the post-merge ones.

## Gates

`scripts/check-all.sh --fast` on the merged tree: 526 Swift tests, 227 Python tests, eight
fixture conversions, the documented builds, the measurements policy, the issue citations and the
PDFKit concurrency smoke gate. Then the corpus lane, 18 of 18 in both lanes, with the reviewed
content contracts and EPUBCheck 5.3.0, `runPassed` read from every case's own `result.json`.
