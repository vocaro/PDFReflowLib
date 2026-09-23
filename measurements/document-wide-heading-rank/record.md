# A page's tags cannot demote a heading the book's tags rank as one

Measured on top of `8faeaab` (the baseline binary, built from that commit before any change) against
the working tree that became the commit closing
[#294](https://github.com/vocaro/PDFReflowLib/issues/294) and
[#243](https://github.com/vocaro/PDFReflowLib/issues/243); macOS 27 arm64, release CLI, every
conversion at `--no-ocr --package-identifier urn:uuid:identity --modification-date 2026-01-01T00:00:00Z`
unless the corpus lane is named. The corpus sources are the checksum-pinned files under
`corpus/cache/`.

## The question

`main` believes a page's tag roles over visible typography wherever that page's tags name a heading
(#67), and reads a paragraph-tagged display line as a heading only where the same page's tags call
that exact size a heading (`contradictedHeadingGroups`, the Fed's page 21). IRS Publication 596's
cover tags `目录` a paragraph in fifteen-point type beside a seventeen-point `H1`, and nothing else on
the page is set in fifteen, so the per-page rule cannot reach it and the book reflows without its
contents heading (#243). #294 asks for the ranking to be document-wide.

## What the seven tagged books say about their own sizes

A survey probe (a temporary test, not committed) ran the real extraction pass — `PageReader`,
`StructureTreeReader`, `MarkedTextReader`, `PageDiagnosis.prepareExtracted` — over every page of
each corpus book with tagged pages, and for every line recorded its size, whether PDFKit reports it
wholly bold, its tag role, and whether its own page's typography reads it as heading-sized
(`isTitleSized`). Pages that are recognized, synthetic or preserved whole were left out, as
`DocumentEvidence.collect` leaves them out.

Sizes the tags call a heading on heading-sized lines, with the pages that do so and the levels given:

| book | sizes tagged a heading (pages, levels) | heading-sized lines tagged `P` on a page whose tags name a heading |
| --- | --- | --- |
| `irs-p596-zhs-2025` | 18 (6, `H1`), 17 (6, `H1`), 14 (5, `H2`) | `596 号刊物` and `目录`, both 15 pt, both on the cover |
| `fed-explained-2021` | 40 (1), 24 (1), 16 (26, `H3`), 14 (49, `H4` ×72, `H5` ×2, `H3` ×2), 12 (7, `H5`) | `PUBLIC EDUCATION & OUTREACH` (14 pt, cover), `Advisory Councils` (14 pt, page 21), and 27 ten-point prose lines on eight-point sidebar pages |
| `gpo-our-flag-2003` | 30 (1), 22 (21, `H2`), 21 (1), 20 (1), 18 (3, `H3`) | the title-page imprint: four lines at 9 pt, two at 12 pt |
| `scotus-loper-bright-2024` | 14.5 bold (5, `H3`) | none |
| `faa-phak-8083-25c` | none: every heading style maps to `P` | none reachable: no page's tags name a heading |
| `dga-2025-2030` | none | none |
| `uscis-m618-arabic-2015` | none | none |

Three things fall out of the table:

- **Fifteen points occurs nowhere else in the IRS book.** A rank keyed to the exact style, as the
  per-page rule is, has no opinion on `目录`; only a rank that orders sizes does. The book's tags
  rank fourteen an `H2` and seventeen an `H1`, so fifteen lies inside the range the book calls
  headings and takes the level of the largest ranked size not above it, `H2`.
- **Size ranks the two false candidates exactly as it ranks the two true ones.** `596 号刊物` is
  set in the same fifteen points as `目录`, on the same page, with the same tag; the Fed cover's
  `PUBLIC EDUCATION & OUTREACH` is set in the fourteen points the Fed tags `H4` on forty-nine pages.
  Rendered (`pdftoppm -f 1 -l 1 -r 60`), each is a label standing over a larger title: the
  publication number over the thirty-one-point title, the series name over the forty-point one.
  `目录` and `Advisory Councils` stand over their own ten-point text. So the rule reads what the
  nearest line beneath a candidate, in its own column, is set in: larger, and the candidate is a
  label and keeps its paragraph role. The Fed's reviewed contract already requires the series
  name to remain paragraph text.
- **A floor of three pages and heading-sized evidence only.** *Our Flag* tags nine-point lines
  `H` on two pages where nine is the body; its imprint is set in nine and twelve under an
  eighteen-point floor, and stays a paragraph. The Fed's ten-point prose lines on its eight-point
  sidebar pages read as heading-sized on their own pages and are tagged `P`; ten is under that
  book's twelve-point floor. Weight was recorded and separates nothing: every tagged heading in six
  of the seven books reaches PDFKit as regular (the IRS book's fonts all as plain `Helvetica`), and
  *Loper Bright*'s bold `H3` has no paragraph-tagged candidate beside it. The rank still keys a
  tier to its weight, so it speaks only to a line of the weight it ranked.

## Counts before and after

Heading elements (`<h1>`–`<h6>`) counted per spine document of each EPUB, listed and diffed:

| book | before (`8faeaab`) | after | what moved |
| --- | ---: | ---: | --- |
| `faa-phak-8083-25c` | 635 | 635 | nothing; the list is identical line for line, and the EPUB is byte-identical |
| `fed-explained-2021` | 189 | 189 | nothing; identical list, byte-identical EPUB; page 21 keeps `Advisory Councils` at `h4` from the per-page rule |
| `irs-p596-zhs-2025` | 85 | 86 | `目录` returns as `<h2 id="heading-1-3">`; `596 号刊物` stays `<p>`; every other block and id is unchanged |

The issue names 99 for this book at `7a4a5b3`. It is 85 today, at the identity options and at
library defaults alike, and the difference is on `main`'s own history between the two commits:
`91dd1ba` (#42) joined the split East Asian titles ("Heading elements go from 99 to 89" in its
message), `3ccb23e` (#254) took the five bulleted sentences whose oversized bullet had read as a
heading, and `7d6b0cd` (#256) took the wrapped starred footnotes. The gate this record measures is
therefore 85 → 86 with `目录` the one addition, which is what the issue asks for.

The one changed entry in the IRS archive, `EPUB/chapter-1.xhtml`, 59,823 → 59,842 bytes:

    -<p>目录</p>
    +<h2 id="heading-1-3">目录</h2>

## Byte identity (decision 0004)

Every cached source, converted one at a time with the baseline binary and with the built one and
compared with `tools/epub_identity.py` (archive entries and conversion reports), the pair deleted
before the next book. The eighteen manifest sources other than Warren and NOAA went first, as
the brief asked; the four cached files outside the manifest and NOAA followed once the gates had
run; Warren was attempted last under a 280-second watchdog and did not finish under either
binary (both runs were killed by their own PID at the deadline, the baseline while reconstructing
page 645 of 920 and the built binary page 622, each at 73–74% of its progress).

| verdict | books |
| --- | --- |
| identical (22) | `DGA`, `20180003024`, `2311.07842v1`, `rrs2002-01`, `jresv82n3p173_A1b`, `mcs2025-copper`, `warren-suspect-text-excerpt`, `November-December2012`, `cdc_6023_DS1`, `CDOC-108hdoc97`, `22-451_7m58`, `M-618_a`, `the-fed-explained`, `faa-h-8083-25c`, `Beginning_and_Intermediate_Algebra`, `GPO-911REPORT`, `CIA-UAP-015-Project_Blue_Book_Special_Report_No_14`; outside the manifest `20190030725`, `20200002975`, `complaint_for_a_civil_case`, `THM-Close-Out-Report-and-Exec-Summ-for-STI-Review`; and `noaa_61592_DS1` (1,834 pages, 1,783 reflowed, 1,609 images, converted whole in 114 and 111 seconds) |
| moved (1) | `p596zhs--2025`: one entry, the nineteen bytes above |
| not converted (1) | `GPO-WARRENCOMMISSIONREPORT`: identical by construction rather than by measurement — a 1964 scan with no structure tree, so no page's tags name a heading, `contradictedHeadingGroups` returns before the rank is consulted, and the rank's own tally reads pages without writing to them |

## Gates

- `scripts/check-all.sh --fast` on the finished tree: exit status 0, read directly from the run's
  own exit line; every gate `PASS` (python-tool-tests, measurements-policy, swift-tests,
  release-build, pdfkit-concurrency, documented-builds, doc-counts, issue-citations,
  closing-commits, fixture-epubs, conversion-policies). The Swift suite is 694 tests, the eight
  in `HeadingRankTests.swift` new, and none of the five host-sensitive Vision tests failed.
- The corpus lane, `tools/run_corpus_regressions.py` at library defaults with EPUBCheck, one
  case per invocation: 18 of 18 cases, each judged from its own `result.json` (`runPassed`
  true) and `content-assessment.json` (`passed` true, zero errors), 608 content checks in all.
  `irs-p596-zhs-2025`'s contract does not pin its heading count and passes with `目录` back;
  `fed-explained-2021`'s page-1 contract, which requires `PUBLIC EDUCATION & OUTREACH` as
  paragraph text, passes as before.
- `tools/check_issue_citations.py --refresh` then the check: the refreshed snapshot sees #291
  closed (by `235240e`, already on `main`), so it is entered in `ALLOWED` as historical; #294 and
  #243 are open in the snapshot and need no entry until the push closes them.

## Evidence

- `Tests/PDFReflowLibTests/fixtures/irs-1-layout.json` and `fed-1-layout.json`, the two covers'
  native extraction captured with `tools/probes/capture-layout-fixture.swift`. Their tag
  fixtures were captured too (`tools/capture_tag_fixture.py`) and not committed: 164 KB and
  150 KB, most of it the IRS cover's 440 contents-list elements and the Fed cover's figure
  stream. The tests state the roles from those captures by element number: IRS 6169 (`P`)
  `596 号刊物`, 6171 (`P`) `目录`, 6225 (`H1`) `未来进展`; Fed 4413 and 4414 (`P`), 4417 (`H1`).
- `Tests/PDFReflowLibTests/HeadingRankTests.swift`: the IRS cover with and without the book's
  rank; the Fed cover; Fed page 21 with the rank (the per-page rule's outcome unchanged); FAA
  page 81 with an empty rank and with an opinionated one (unchanged either way, and the FAA's
  own tally ranks nothing); the tally's three-page floor, commonest level and body-size
  exclusion; the rank's floor and weight; and `contradictedHeadingGroups` with a rank on a
  page whose tags name a heading, on one whose tags name none, on a label over a title, and on
  a group with one prose line.
- The survey numbers above; the probe that produced them ran the library's own readers and is
  reproduced by the description in the second section.
