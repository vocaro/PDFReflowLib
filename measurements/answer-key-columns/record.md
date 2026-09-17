# An answer key numbered down its columns reads down them (#178)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 (26A428) arm64, release CLI,
host terminal. Baseline: `ce9e288` (`Sources/PDFReflowLib/LayoutReconstructor.swift` restored from
`ce9e288` in this worktree, converter `26ff9e71…`); candidate: `ce9e288` plus the working tree
(converter `fe74dba9…`). [identity.json](identity.json) pins both CLIs, the capability probe, the
sources, the fixtures and the commands. No PDF or EPUB is committed.

Scope: this record closes the answer-key ordering gap the [#46/#48 crop
work](../split-display-rows/record.md#remaining-gaps) left open. The exercise `<ol>` semantics of
#29 and page 486's first key remain open; see [Remaining gaps](#remaining-gaps).

## What was wrong

Wallace's answer sections set short numeric entries in two or three columns **numbered down each
column**, one key under the next, each under a title centred across the measure. Three properties
of that layout defeat every cut `LayoutReconstructor.ordered` has:

| Property | The cut it defeats |
| --- | --- |
| The key's title runs across every gutter (page 486's `Answers - Exponential Functions` spans x 212.6–382.5, both gutters) | the whitespace gutter, and with it `headingBand`, `stackedBlocks` and `bulletColumns`, which all need a gutter first |
| An entry is a number and a value (`15) 1`, 26 pt wide against a 144-pt prose test) | the narrow-gutter prose test (#47/#56) and `marginBands`/`proseBesideProse` (#153) |
| A key sits 4.6–9.6 pt under the key above it | the horizontal cut, which asks 1.1 bodies (13.2 pt) |

So the page fell through to `sortedByRows`, which reads along the rows:

| Page | Key | Reflowed before |
| --- | --- | --- |
| 486 | `Answers - Exponential Functions`, 1–14 \| 15–28 \| 29–40 | `1) 0`, `15) 1`, `29) 0`, `2)− 1`, `16)− 1`, `30) No solution`, `3) 0`… |
| 465 | 6.6 answers, 11–26 \| 27–42 | `11)`, `27)`, `12)`, `28)`, `13)`, `29)`… |
| 465 | `Answers - Solve by Factoring`, 1–12 \| 13–24 \| 25–34 | `7) 2,− 7`, `30) 2,− 3`, `31)− 7, 7`, `21)− 4,− 3`, `32)− 4,− 6`, `22) 8,− 4` |
| 463 | 6.3, 6.4 and 6.5 answers | `7)`, `17)`, `27)`, `8)`, `18)`, `28)`… |
| 482 | 9.9 and 9.10 answers | `10) (20, 3), (5, 12)`, `4) (8, 15), (− 10,− 12)`; `1) 12`, `9) 60 mph, 80 mph`, `2) S4` |

A fraction answer is a preserved crop, so a row can mix text entries and images; the defect is the
order, not the representation. `rowMajorLabels` (#78) correctly declines these pages — their
sequence is not consecutive along a row — so nothing reordered them.

## What changed

`Sources/PDFReflowLib/LayoutReconstructor.swift` only (+56 lines for this issue). No public API,
option, default, warning or other call site changed. The hunks:

1. **`readsDownColumns(_:bodySize:)`**, new: markers grouped into columns at their own left edges
   (edges 1.5 bodies apart, each marker taken to the last edge at or left of it, as
   `noteColumnsInNumberOrder` groups note markers) read down their columns when there are at least
   two columns of at least two markers each, every column counts up from its top, and every
   column's numbers stand wholly below the column to its left.
2. **`numberedKeyBand(_:bodySize:)`**, new: the region's highest whitespace band — a line no
   element crosses, from `horizontalBands` — whose `N)` markers below it `readsDownColumns` and
   open at a number no higher than any number above the band.
3. **One step in `ordered`**, after `marginBands` and before `interleavedBlocks`: the region is
   cut at that band and each part ordered on its own.

The restart is the whole of the evidence for a boundary. A band inside one key leaves that key's
own first entry above it, so what is below opens higher and is refused; a key the entries above
continue (1–7 over 8–11) opens higher still. Only the band is new: each part is then cut by the
gutters it already had, and `headingBand` still lifts a key's `6.7` label and its title off the top
of its part.

The step is placed last on purpose. On every page reported it is reached because no earlier cut
fires; placing it earlier would have let it take pages whose geometry already reads correctly.

## Effect

`page-comparison/wallace-algebra-2010.json`
(`compare_conversion_runs.py --allow-different-converters`, probe-backed runs of both CLIs). Only
four of the changed pages belong to this issue; the other fourteen are [#179](../figure-labels/record.md).

| Page | Read before | Reads now | Reviewed against |
| --- | --- | --- | --- |
| 463 | 7, 17, 27, 8, 18, 28 …; 1, 15, 29, 2, 16, 30 … | 7–34; `6.4`; 1–14, title, 15–28, 29–40; `6.5`, title, 1–4 | `pdftoppm` render |
| 465 | 11, 27, 12, 28 …; 7, 30, 31, 21, 32, 22 … | 11–26, 27–42; `6.7`; 1–12, title, 13–24, 25–34 | `pdftoppm` render |
| 482 | 7, 8, 9, 10, 4, 5, 12; 1, 9, 2, 10, 18, 3 … | title, `9.9`, 4–12; `9.10`, 1–8, title, 9–22 | `pdftoppm` render |
| 486 | 1, 15, 29, 2, 16, 30 … | title, 1–14, 15–28, 29–40 | `pdftoppm` render |

Every entry of every key on those pages is in printed order. No text is lost, no image count
changes on them, page markers are equal, navigation is unchanged and the conversion report is
unchanged.

**No other document changes.** `sweep-corpus-pages.py` converts each cached corpus source with both
CLIs and compares every page's blocks: `fed-explained-2021`, `dga-2025-2030`, `gpo-our-flag-2003`,
`cdc-zombie-pandemic-2011`, `usgs-mcs2025-copper`, `scotus-loper-bright-2024`,
`arxiv-replay-clocks-2023`, `uscourts-pro-se-1-2016`, `cia-blue-book-14-1955`,
`usda-ars-agresearch-2012-11`, `ntrs-20180003024-earthdata-slides-2018`,
`ntrs-20210020887-techport-thm-2021`, `uscis-m618-arabic-2015` and `irs-p596-zhs-2025` are all
identical, and the lane cases below are identical page for page.

## Regressions added

`Tests/PDFReflowLibTests/AnswerKeyColumnsAndDiagramLabelsTests.swift`, on checksum-pinned fixtures
`algebra-463`, `algebra-465` and `algebra-486` (new captures):

- **page 465**: the first key's thirty-two entries read 11–42 in order, the second key's entries
  count up, entry 22's second line stays with its first, and the title is on the page.
- **page 486**: from `Answers - Exponential Functions` the entries count up from 1 to 40, the
  title heads the key, and only the first key's 3–9 read before it.
- **page 463**: each of the three keys is cut on its own — 7–34, 1–40 and 1–4.
- **`readsDownColumns`**, at page 486's measured geometry: three columns of 1–14, 15–28 and 29–40
  read down; #78's row-numbered grids (15, 18, 21 \| 16, 19, 22 \| 17, 20, 23) and the
  two-to-a-row exercise sets (1, 3, 5 \| 2, 4, 6) do not, nor does a column counting down, a
  repeated number, a single column, a column of one entry, or two runs half a body apart.
- **`numberedKeyBand`**, at the same geometry: a key of 3–9 over a key of three columns gives a
  band; one key alone, a key the entries above continue, a grid numbered along its rows, a figure
  spanning the whitespace between the keys, a part below too small to be columns and a region
  carrying fewer than six markers give none.

[guard-mutations.log](guard-mutations.log): each of the eleven single-guard mutations of both
rules — six on this one, five on #179's — fails at least one of the new tests.

Against the baseline CLI the Wallace contract reports 30 errors and 252 passes; against the
candidate all 282 pass. Twenty-four of the thirty are this issue's (pages 463, 465, 482 and 486);
the other six are #179's.

## Verification

- `swift test`: 834 tests pass (826 before, eight added across both issues).
- `scripts/check-all.sh --fast`: see the run below.
- `tools/run_corpus_regressions.py`, one case per call, probe-backed, on both CLIs:
  wallace-algebra-2010 (candidate PASS, baseline FAIL on the new checks only),
  faa-phak-8083-25c, gpo-911-2004, census-rrs2002-01, nbs-jres-geltman-1977,
  ntrs-20190030725-dasc-2019 and ntrs-20200002975-gwl-2020 all PASS on both, and
  `compare_conversion_runs.py` reports no changed page on any of them.

## What this does not prove

The rule reads `N)` markers only, so a key whose entries are all crops carries no evidence: page
486's first key, whose middle and right columns are entirely preserved fractions, still reads
across its rows. The band is a property of this book's spacing only in the sense that
`horizontalBands` must report one between the keys; where a figure or a crop spans the whitespace
between two keys there is no band and nothing changes. Column-major reading is now blessed for the
keys listed above, not for the page order of any other Wallace page.

## Remaining gaps

- Page 486's first key (3–40 over three columns whose other two are crops) still reads across its
  rows; the narrow 16.6-pt gutter beside a 131.8-pt crop fails the prose test a narrow gutter asks.
- A key's title reads after the first column where a crop's top stands within 0.8 body of the
  title's foot (pages 463, 465 and 482), because `headingBand` cannot find its band there. The
  contract states this is not blessed.
- Entries are still `<pre>` blocks, not `<ol>` items (#29 part b).

## Commands

```sh
swift build -c release
xcrun swiftc -parse-as-library -O -module-cache-path .build/raster-environment/module-cache \
  Sources/PDFReflowLib/{PageRasterizer,ConversionTypes,DocumentModel,ReflowDocument}.swift \
  tools/probe-raster-environment.swift -o .build/raster-environment/probe
python3 tools/run_corpus_regressions.py --converter <CLI> --epubcheck /opt/homebrew/bin/epubcheck \
  --output <dir> --case <id> --environment-probe .build/raster-environment/probe \
  --execution-context host-terminal
python3 tools/compare_conversion_runs.py --allow-different-converters \
  --baseline <base>/<id> --candidate <cand>/<id> --output page-comparison/<id>.json
python3 tools/check_corpus_content.py --case wallace-algebra-2010 --evaluation <dir>/wallace-algebra-2010
# the reading-order survey: the order `ordered` gives a page, with every element's rectangle
swiftc -swift-version 6 -O $(ls Sources/PDFReflowLib/*.swift | grep -v 'EPUBWriter\|PDFConverter\|PDFReflowLibPipeline\|EPUBTextEncoder') \
  measurements/answer-key-columns/survey-order.swift -o /tmp/survey-order
/tmp/survey-order corpus/cache/Beginning_and_Intermediate_Algebra.pdf 443 465 486
# the corpus sweep: both CLIs over every cached source, page by page, deleting each output
python3 measurements/answer-key-columns/sweep-corpus-pages.py <case-id> …
```
