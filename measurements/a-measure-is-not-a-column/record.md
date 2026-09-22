# A measure is not a column (#268)

Measured under [#268](https://github.com/vocaro/PDFReflowLib/issues/268), baseline `2511584`
("A numbered item the page broke mid-word keeps the rest of its word"), 2026-09-22, macOS 27.0
(26A425) / Xcode 27.0, arm64, release CLI at library defaults. Baseline converter SHA-256
`8c03a6a0abd563811e7da5185f5bcbe7e0535f8722cb2fdd596f9bd85841f95f`, built from `2511584`; this
change's converter `c6ae5dd206e163fba3c32a30dec786100e5d206055e1735d8f98bf41a536b96b`. Source
`corpus/cache/2311.07842v1.pdf` SHA-256
`1e8172e4a347bdf6722dacc38755f6fb3299866336b8153f51b2c13f3ac6109a`, page 10.

## Where the defect is, on current main

#268 was filed on `4d5d86d`, before [#210](https://github.com/vocaro/PDFReflowLib/issues/210)
landed `TableReader` and the document model's `.table` case, so the first question was which
reader is wrong now. Converted on `2511584`, Replay Clocks emits **no table at all** — zero
`<table>`, zero `<tr>` — and the last five references of page 10 are still the same five `<pre>`
rows the issue quotes. `TableReader` declines the page, which is right: those references are not
a table and it should not read one. The defect is exactly where the issue puts it, in
`TableRegionDetector.rowBlocks`, and it has not changed shape.

## What the page states

Extraction of page 10 (`tools/probes/capture-layout-fixture.swift`, committed as
`Tests/PDFReflowLibTests/fixtures/replay-10-layout.json`) returns the reference column as eleven
printed rows at 7 points, stepping down at 7.97, on the run that `rowBlocks` anchors at `[8]`:

| Row | Pieces | Ends at |
| --- | --- | ---: |
| `[8]` | 321.20–329.41 **+** 333.39–558.42 | 558.42 |
| `[9] David L Mills. …` | 321.20–558.20 | 558.20 |
| `Transactions on communications, …` | 333.39–493.45 | 493.45 |
| `[10]` | 317.95–329.40 **+** 333.39–558.20 | 558.20 |
| `Plakal, Donald Beaver, …` | 333.39–558.20 | 558.20 |
| `distributed systems tracing infrastructure. 2010.` | 333.39–470.06 | 470.06 |
| `[11] Mukesh Singhal …` | 317.96–558.20 | 558.20 |
| `vector clocks. Inf. Process. Lett., …` | 333.22–473.96 | 473.96 |
| `[12]` | 317.95–329.40 **+** 333.39–558.20 | 558.20 |
| `Murat Demirbas. Analysis of bounds …` | 333.39–558.20 | 558.20 |
| `on Parallel and Distributed Systems, …` | 333.39–497.92 | 497.92 |

Three rows hand back the citation number as a cell of its own on one edge (333.39), and eight
merged rows reach across it. That is precisely the evidence `statesAColumn` accepts, and it is
why references 8 to 12 came out as rows while 1 to 7 did not: the run anchored on `[1]` breaks at
its second row, because `[2]`'s entry begins past the width `[1]` alone reaches, whereas `[9]`
arrives merged and opens the run's reach to the whole column.

## Why the two guards #171 measured cannot work

The 9/11 report's flight timelines are set the same way, and the fixtures say so. Page 50's
second block:

```
  [39.66..102.07] 7:59 Takeoff
  [39.66..138.34] 8:14 Last routine radio
  [75.66..186.85] communication; likely takeover
  [39.66..55.23] 8:19   ~~   [75.66..183.67] Flight attendant notifies AA of
  [75.66..108.10] hijacking
  [39.66..166.06] 8:21 Transponder is turned off
```

The time is outdented, the entry is hung at 75.66, the extractor keeps some rows apart and merges
others — the same shape, and it *is* a table. Requiring the split rows to be most of the run
fails because only 4 of 26 rows are split here; requiring most rows to open on the run's own left
edge fails because 13 of 26 open at 75.66. Both guards were measured under #171 and both released
the references together with the timelines, the Blue Book's contents, the FAA cruise table and
the USGS statistics.

## The mechanism: the other edge

A cell is set to its content; a paragraph is set to a measure. So the evidence is where the rows
*end*, not where they begin. Over every layout fixture in the suite, the twelve blocks `rowBlocks`
accepts on the split-cell evidence, with the share of rows ending within a fifth of a body of the
block's own far edge:

| Block | Rows | On the far edge | Also numeric |
| --- | ---: | ---: | --- |
| `noaa-9` contents ×3 | 4, 6, 6 | 4/4, 6/6, 6/6 | yes |
| **`replay-10` references** | **11** | **7/11 = 0.64** | no |
| `911-9` list of illustrations | 15 | 4/15 = 0.27 | no |
| `algebra-479` | 4 | 1/4 = 0.25 | no |
| `911-50` UA 175 timeline | 19 | 2/19 = 0.11 | no |
| `911-451` | 30 | 2/30 = 0.07 | no |
| `911-448` | 20 | 1/20 = 0.05 | no |
| `911-51` AA 77 timeline | 20 | 1/20 = 0.05 | no |
| `911-51` UA 93 timeline | 24 | 1/24 = 0.04 | no |
| `911-50` AA 11 timeline | 26 | 1/26 = 0.04 | no |

The references are the only block above a quarter, and the only one above a half. Seven of their
eleven rows end within 0.22 points of 558.2, and the four that fall short are each entry's closing
line; the timelines are ragged, because each cell ends where its words end.

`isSetToAMeasure` is therefore: **most of the run's rows, and at least three of them, end within a
fifth of a body of the run's own far edge, and that edge is not carried by numbers.** A run with
that shape states no cell boundary, and `statesAColumn`'s split-cell branch declines it. The
numeric proviso is what keeps the NOAA chapter contents, whose rows all reach the measure because
the page right-aligns `4-16`, `5-9` and `7-20` against it: an edge carried by numbers is the
column `statesAColumn`'s other branch already reads, and an edge carried by words is a measure.

The tolerance is stable. At 0.1, 0.15, 0.2 and 0.3 of a body the ordering above is identical; only
at 0.5 does `algebra-479` climb to 3/4 on a four-row block, which is why a fifth was taken rather
than the half a body the numeric branch uses.

**Over every layout fixture in the suite, exactly one block moves.** 426 blocks become 425:
`replay-10`'s reference run, and nothing else. The 9/11 timelines, the list of illustrations, the
NOAA contents, the Blue Book contents (`blue-5`), the FAA cruise table (`faa-459`), the USGS
statistics (`usgs-1`, `usgs-2`) and all 412 blocks accepted on the numeric evidence are bit for bit
as they were.

## What moved, per book

Both lanes ran on this host, 18 cases each, `--jobs 4`, EPUBCheck 5.3.0 at
`/opt/homebrew/bin/epubcheck`, library defaults. Every case of both lanes passes on its own
`result.json` — `runPassed`, `memoryGate.status`, `epubcheckExitCode`, `structuralCheck`,
`gatesPassedApartFromMemory` — and on its own `content-assessment.json`, whose check counts and
zero error lists are identical book for book (FAA 87, 9/11 95, USGS 30, Wallace 30, Census 58).

**No book's table count moves.** `usgs-mcs2025-copper` emits 3 tables, 51 rows and 283 cells in
both lanes; `wallace-algebra-2010` 30 tables, 134 rows and 510 cells; the other sixteen emit none,
before and after. The USGS contract's twenty cell-by-cell pinned rows pass unchanged.

| Book | `<pre>` | `<p>` | Characters | Words |
| --- | ---: | ---: | ---: | --- |
| `arxiv-replay-clocks-2023` | 5 → 0 | 186 → 192 | 50,119 → 50,119 | identical |
| `census-rrs2002-01` | 138 → 124 | 208 → 235 | 41,206 → 41,208 | one word, below |
| `faa-phak-8083-25c` | 1,316 → 1,308 | 6,423 → 6,438 | 1,681,892 → 1,681,892 | identical |
| the other fifteen | unchanged | unchanged | unchanged | identical |

Three books, three pages each named by their source page.

**`arxiv-replay-clocks-2023`, page 10.** The five `<pre>` rows the issue quotes are gone and the
book emits no preformatted block at all. Entries 9, 10 and 12 are each one reflowing paragraph.
Every word of the book is identical.

**`census-rrs2002-01`, page 17.** The same defect, in a second book, settled by the same rule: the
paper's own reference list sets `[ 1]` to `[ 14]` outdented with the entry hung, and all fourteen
were `<pre>` rows. They now read as paragraphs, exactly as the list's continuation on page 18
already did on the baseline.

**`faa-phak-8083-25c`, the pages the book labels 28, 48 and 446.** Not a reference list: three columns of
ordinary body prose whose lines fill the measure, which the split-cell evidence had been reading
as rows. `FDC NOTAMs are issued by the National Flight Data` / `Center and contain information
that is regulatory in nature` / `pertaining to flight including, …` was four monospace rows and is
now one paragraph, and the bullet list crammed into the last of those rows
(`• Airfield lighting should be reduced to the lowest usable intensity. • Maintenance personnel
should practice light discipline …`) is now one paragraph per bullet. The handbook's 87 content
checks pass unchanged and `rowBlocks` still keeps page 416's printed rows.

## What this cost

One word, in one book, and it is [#282](https://github.com/vocaro/PDFReflowLib/issues/282)'s.

The Census paper breaks `Microdata` across the hang of its thirteenth entry. On the baseline the
row reading joined the entry's two printed lines into one `<pre>` and the hyphen was repaired; as
paragraphs they are two blocks, the join is refused, and the book reads `… Public Use Mi-` /
`crodata, U.S. Bureau of the Census, …`. This is the whole word-level cost of the change across
all eighteen books; every other book is word for word identical, and the FAA's one apparent move
is a spine boundary falling between `<p>•</p>` and the bullet's text rather than after it, with
the reading order unchanged and `spineBoundariesCrossed` zero in both lanes.

## What this does not fix

A hanging-indent entry still does not take every line the page hangs under it, so page 10 gives
one paragraph per reference for entries 9, 10 and 12 but not for 8 (whose `[8]` joins the
paragraph above it) or 11 (whose hang of 15.26 points exceeds the 1.5 bodies the column test
allows, and whose wrap `hangingEntries` accepts but cannot believe alone, that rule needing three
candidates on one edge). That is a different mechanism — #39's column test and #160's hanging
entries, not the table reading — and it is filed as
[#282](https://github.com/vocaro/PDFReflowLib/issues/282), which also carries the Census hyphen
above and the NOAA and NASA cases #171 items 6 and 4 report.

## Gates

`scripts/check-all.sh --fast` passes all ten gates (python-tool-tests, measurements-policy,
swift-tests, release-build, pdfkit-concurrency, documented-builds, doc-counts, issue-citations,
fixture-epubs, conversion-policies), exit status 0, read directly. 625 Swift tests and 231 Python
tests pass. Then both corpus lanes, 18 of 18 each, with EPUBCheck 5.3.0 reporting 0 errors on
every book.

## Re-measured over the merge taken since

`main` moved to `86193ac` ("Merge main 18c8cc3 into the #261 branch") between the measurement
above and the merge, taking #261's bullets-alone-on-their-line reading and #262's spoiled column
labels with it. Both lanes were run again on the merged tree, against a release binary built from
`86193ac` itself (SHA-256 `54c6b2760557e2103c9f9403f233f621a033493e74dd6e8471937453c3eb0ea3`;
this change's converter `88b522eb852e3caae3e40acfcb831ca1f0a3c402563d11f6b18c780a124c44be`), and
18 of 18 pass in each, every `runPassed`, `memoryGate.status`, `epubcheckExitCode`,
`structuralCheck` and `content-assessment.json` read case by case.

The same three books move, the same way. Table counts are again identical book for book: the USGS
summaries 3 tables, 51 rows, 283 cells; Wallace 30 tables, 134 rows, 510 cells; the other sixteen
none. Only the absolute `<pre>` totals move with main, 6,542 to 6,516 over the eighteen books.

| Book | `<pre>` | `<p>` | Words |
| --- | ---: | ---: | --- |
| `arxiv-replay-clocks-2023` | 5 → 0 | 186 → 192 | identical |
| `census-rrs2002-01` | 138 → 124 | 208 → 235 | `Microdata`, as above |
| `faa-phak-8083-25c` | 1,391 → 1,384 | 6,364 → 6,377 | identical |
| the other fifteen | unchanged | unchanged | identical |

The pages that move are the same, except that the FAA handbook's page 28 no longer does: #261
had already released its bullets on the new baseline, so only the pages labeled 48 and 446 move
here. `scripts/check-all.sh --fast` passes all ten gates on the merged tree, exit status 0 read
directly, with 629 Swift tests and 231 Python tests.

**One flaky finding, and what it was.** The first run of the `86193ac` baseline lane failed
`gpo-warren-1964-suspect-text-excerpt` on its content assessment — page 4 read from the suspect
text layer (`BS3d v^.ere his things ci^ht be kept`) at 5,067 characters instead of recognized at
5,496 — and a second run of that case alone reproduced it. Three further runs of the same case
against the same binary all passed at 5,496, and the re-run of the whole baseline lane passed 18
of 18. It is the Vision non-determinism `measurements/apple-feedback-vision-determinism/record.md`
records, not a difference between the two binaries: the recognition decision is made in
`PageDiagnosis.assess` during extraction, and `rowBlocks` is read afterwards, in reconstruction.
The numbers above are from the passing baseline lane.
