# The author's outline becomes the book's navigation, where it is one

Measured under [#249](https://github.com/vocaro/PDFReflowLib/issues/249), baseline `99804a2`,
2026-09-20, macOS 27 / Xcode 27, arm64, release CLI at library defaults.

`ChapterBoundaryReader` already opened `outlineRoot` and kept almost nothing from it: only a
root-level, consecutive `Chapter N Title` sequence, and only as split points. Navigation was
assembled entirely from headings the layout pass detected. The hierarchical contents the author
stated, with explicit destinations, was read and discarded.

## What the corpus states

Twelve of the twenty-one cached documents state an outline; `shapes.json` records every one.
Four of the twelve are not tables of contents:

| Document | Pages | Entries | Distinct titles | Depth | Used |
| --- | ---: | ---: | ---: | ---: | --- |
| arxiv-replay-clocks-2023 | 12 | 20 | 20 | 1 | yes |
| cia-blue-book-14-1955 | 312 | 313 | 2 | 1 | **no** |
| faa-phak-8083-25c | 522 | 7,689 | 6,442 | 11 | **no** |
| fed-explained-2021 | 135 | 40 | 36 | 1 | yes |
| gpo-911-2004 | 585 | 93 | 93 | 1 | yes |
| gpo-warren-1964 | 920 | 1 | 1 | 0 | **no** |
| irs-p596-zhs-2025 | 36 | 56 | 55 | 2 | yes |
| nbs-jres-geltman-1977 | 7 | 8 | 8 | 0 | yes |
| noaa-nca5-2023 | 1,834 | 303 | 211 | 1 | yes |
| usda-ars-agresearch-2012-11 | 24 | 11 | 11 | 0 | yes |
| uscis-m618-arabic-2015 | 116 | 49 | 49 | 1 | yes |
| usgs-mcs2025-copper | 2 | 1 | 1 | 0 | **no** |

The FAA handbook is the document the issue names as having the most to gain from an outline, and
its outline is a tagged-structure tree written out as bookmarks — eleven levels of
`Structure Bookmarks`, `Document`, `Article`, `1-1`, 14.7 entries for every page of the book.
The CIA report's 313 entries are one per page, 311 of them labeled `Figure`. The Warren report
states one entry, labeled `Test`. Taking any of these as navigation would have been a plain
regression, which is why the reader gates on shape: at least two entries, at most three per page
of the book, at most four levels, and more than half the titles distinct. Nothing in the gate
reads the pages.

## What changes for the eight admitted

| Document | Nav entries before (detected headings) | After (outline) |
| --- | ---: | ---: |
| arxiv-replay-clocks-2023 | 3 | 20 |
| fed-explained-2021 | 189 | 35 |
| gpo-911-2004 | 73 | 93 |
| irs-p596-zhs-2025 | 84 | 56 |
| nbs-jres-geltman-1977 | 0 | 7 |
| noaa-nca5-2023 | not converted in this lane (#242) | — |
| usda-ars-agresearch-2012-11 | 26 | 11 |
| uscis-m618-arabic-2015 | 102 | 47 |

Fewer entries is the improvement, not the cost. The Fed report's 189 detected headings open with
the cover's two halves, the contents page's dot-leader lines
(`1 Overview of the Federal Reserve System . . . . . . .`), a chapter title split across the two
lines it is set on, and body prose (`The Federal Reserve performs five key functions`). Its 35
outline entries are the seven chapters and their sections. The arXiv paper's three detected
headings were its title and its two authors' names; its outline is the paper's twenty numbered
sections. The magazine's 26 were fragments of cover type and a pull quote; its 11 are the
articles.

The weakest admitted case is the NBS paper, whose outline entries are named after the scan's page
images (`jresv82n3p_173` … `jresv82n3p_179`). The gate cannot tell those from titles, and the
alternative there is not better: that paper produced no detected heading at all, so its
navigation was a single entry naming the book. It is recorded here as a known limitation rather
than argued away.

## Resolution across spine documents

An entry read on page 12 may name page 400, whose spine document does not exist when the outline
is read. Resolution is therefore deferred to `EPUBWriter.finish`, where `SpinePacker.pages`
already holds the finished page-to-file map. The 9/11 report's 93 entries resolve across 23
spine documents, the Fed report's 35 across 5. [#247](https://github.com/vocaro/PDFReflowLib/issues/247)
needs the same map for internal links and should use this one.

## Validation

EPUBCheck 3.3 reports no errors or warnings on the Fed report (nested, five spine files), the
arXiv paper and the IRS publication (nested two deep, Chinese titles). The 9/11 report draws one
warning, NAV-011: its contents is not in reading order, because its list of illustrations comes
before the preface and points at pages 33 to 67 while the preface points back at page 11. That is
the contents the author printed, and reordering it would be a different book's navigation, so the
warning stands. EPUBCheck exits zero on it and the lane passes. 471 Swift tests pass,
five new, including the gate's decision on all twelve measured shapes. The corpus lane passes
16 of 18 with no content-contract failures.

Not measured: whether an outline entry's destination should also seed a chapter boundary, which
[#249](https://github.com/vocaro/PDFReflowLib/issues/249) raises and this leaves as it was.
