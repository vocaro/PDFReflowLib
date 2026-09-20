# Stacked margin blocks at both page edges

`FurnitureDetector` weighed only the outermost margin row. Where a running head or foot sets its
rows closer together than a line height, no row of it is set apart from the next, so none was a
candidate and the whole band stayed in the reading flow. The detector now grows a block inward
from an outermost row that is no candidate on its own, at either edge, and removes the block only
when every line of it repeats. This addresses the header half of
[#205](https://github.com/vocaro/PDFReflowLib/issues/205), the follow-up to
[#167](https://github.com/vocaro/PDFReflowLib/issues/167); it is not a general multi-line header
classifier, and it changes nothing about how a single row is weighed.

## Scope and method

The survey compares the detector before and after the change over native extraction only: each
page's lines are read with `NativeTextReader`, `FurnitureDetector.strip` runs over the whole
document, and the removed lines of both versions are diffed. No conversion, reconstruction or OCR
is involved, and no correctness label is attached to a line by the survey itself. Every pinned
corpus document was scanned, the four books over 400 pages to physical page 400. The base revision
is `e00432b`; the probes are the throwaway diagnostics described below, not committed tooling.

## What changes, and what does not

Seventeen of the twenty pinned documents remove exactly the same lines as before. Nothing that the
old detector removed is retained by the new one, in any document. Two documents gain removals:

- **IRS Publication 596 (Simplified Chinese), physical pages 25–33.** The running foot
  `596 号刊物 (2025)` with its boundary folio stands 28 points below the EIC table's `(继续)`
  continuation marker, closer than either row's line height, so neither row was set apart and the
  foot survived on those nine pages; the same foot was already removed on pages 34–36, where no
  marker stands above it. Both rows now go as one block. Physical page 24 is the control: a table
  footnote printed only there joins that page's block, does not repeat, and the whole block stays.
- **Agricultural Research, November/December 2012, physical pages 10 and 22.** The magazine's
  running foot is removed on two more pages. On page 9 the foot stands under a photo credit and
  becomes a block candidate; that lengthens the foot's run of nearby pages to three, so page 10's
  foot, already a candidate on its own, qualifies. Page 9's own block keeps its credit and
  therefore stays whole.

No pinned document gains or loses a removal at the head edge. A separate survey of the blocks a
head band could form finds candidates in most books — 48 pages of the FAA handbook and 62 of the
Warren report among the scanned pages — but they are body prose running to the top of the page,
and no two nearby pages word one the same way, so none reaches the three-page minimum. A run of
nearby pages whose head band repeats two or more rows exists nowhere in the pinned corpus: the
only one the survey finds is the IRS EIC table's head, which the line ceiling rejects.

## Negative controls on real pages

- **Earthdata Cloud Analytics Project, slides 16–19.** Four consecutive slides print the same
  two-line title, `Open Pipeline Provides Outputs at Different / Stages Appropriate for a Diverse
  User Base`. The two lines stand closer than a line height and do form a block, but it reaches to
  0.819 of the page. The outer-eighth bound rejects it; without that bound a genuine heading would
  be removed from four slides. Slides 16–18 are captured as fixtures for the test.
- **IRS Publication 596, physical pages 25–34, head band.** The EIC table's head repeats
  unchanged on ten pages: `低收入家庭福利优惠（EIC）表 - 继续` over eight rows of column titles.
  It grows past the eight-line ceiling and forms no block, so the table keeps its column titles.
- **Fifth National Climate Assessment, physical pages 265–285.** The one-line running head
  `Fifth National Climate Assessment` is removed on every one of them, before and after: the head
  stands clear of the Key Message headings beneath it on pages 275 and 279, so it is still a
  candidate on its own and no block forms above it. Nothing about how a separated single row is
  weighed changes.

## The unpinned header case

`corpus/cache` also holds the NASA TechPort *Tank Health Monitoring* close-out data sheet
(NTRS 20210020887, the document of #167), which is not a pinned corpus source on `main`. Its five
printed pages carry the same two-row head, `Advanced Exploration Systems Division` over
`Tank Health Monitoring`, whose block reaches 0.899 of the page. The new rule removes that head on
all five pages, and leaves the third head row, `Completed Technology Project (2015 - 2020)`, which
stands 23 points lower and is set apart on its own. This is the only repeating stacked head in any
book on hand, and the only measured evidence for the head edge; pinning the document would give
the rule a corpus case.

## Reproduction

Compile `FurnitureDetector.swift` with the extraction sources
(`python3 tools/pdfreflow_tools/swift_sources.py audit-report-margins.swift` lists them) against a
throwaway `main` that reads each page with `NativeTextReader`, runs `FurnitureDetector.strip` over
the document and prints every removed line with its page and position; build the same probe once
against `git show e00432b:Sources/PDFReflowLib/FurnitureDetector.swift` and diff the two outputs
over `corpus/manifest.json`. The head-band and block surveys quoted above use the same shape,
printing the block each page would form instead of the lines removed.
