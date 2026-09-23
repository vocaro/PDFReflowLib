# Painted tables and repeated credit labels

Issue #215, measured 2026-09-23 against the current spatial reconstruction, not the
abandoned entry subsystem. Baseline is the #296 candidate `2dea39a`; this change is
based on `50e2598` (the equivalent of #296 follow-up `c33d96c`, which changes the DGA
control but leaves these NOAA pages unchanged). The source is the corpus-pinned NOAA
*Fifth National Climate Assessment*, 1,834 pages, SHA-256
`1942cbf346dc2c711fea413d6d6543edb8bc1e3a88d4c3a85e733c6b6d3577bf`.

Page 25 paints the individual cells of two shaded, two-column tables. The existing
numeric-column reader does not recover them; graphic clustering obscures their cell
boundaries. Preserve exact filled rectangles before clustering, including white fills
and compound rectangle paths. Admit adjacent grids only with at least three rows,
nonempty cells, a distinguishable header, and complete source-character ownership.
Existing numeric tables retain precedence. Tables without this geometric/header evidence
continue through the existing reconstruction. Nearby numbered table titles become headings.

Page 1738 currently joins all its short roles to the following names. The native source
exposes the same font/style for both, so bold detection cannot solve this. A repeated
same-column, same-size label/value geometry establishes the boundary: a short label,
longer value, larger separation above than below, and at least three matching pairs.
Flush the paragraph before the value without inventing headings or changing its style.
Ordinary prose and isolated pairs are negative controls. Page 6's two J. Michael Kuperberg
entries already are paragraphs; the contract preserves that previously fixed item.

Source pages 25, 27 and 1738 were rendered with Poppler and visually reviewed. The source
fixtures retain extracted geometry, attributed lines and (page 25) the exact painted cells
and native cell selections, not output tables. The opt-in live-source test verifies the
checksum, both page-25 grids and existing page-28 table ownership. Raw PDFs, rendered pages,
EPUBs, complete comparison and logs remain outside the repository under
`/tmp/issue-215-evidence`.

Reproduction from the repository root (Python 3.10 or later):

```sh
swift test
PDFREFLOW_NOAA_PDF=corpus/cache/noaa_61592_DS1.pdf swift test \
  --filter sourceNoaaPaintedTablesKeepBothTwoColumnGrids
swift build -c release
python3 tools/evaluate_real_document.py --case noaa-nca5-2023 \
  --pdf corpus/cache/noaa_61592_DS1.pdf --converter .build/release/pdf-reflow \
  --output /tmp/noaa-painted-tables --epubcheck /opt/homebrew/bin/epubcheck
python3 tools/check_corpus_content.py --case noaa-nca5-2023 \
  --evaluation /tmp/noaa-painted-tables
swiftc $(python3 tools/pdfreflow_tools/swift_sources.py capture-layout-fixture.swift) \
  -o /tmp/capture-layout-fixture
/tmp/capture-layout-fixture noaa-nca5-2023 25 /tmp/noaa-25-live.json
pdftoppm -f 25 -l 25 -scale-to 1600 -singlefile -png \
  corpus/cache/noaa_61592_DS1.pdf /tmp/noaa-25
```

Validation: all 729 Swift tests pass on the final change. The 67 focused table/layout
tests and the opt-in live source test also pass.
The PDFKit access gate passes. Of 250 Python tests, only the two generated-document-count
checks fail (counts intentionally deferred to integration); one unrelated test is skipped.
The final complete NOAA conversion passes all 92 content checks across 12 contract pages,
EPUBCheck with zero errors/warnings, structural validation, progress validation and the
1,280 MiB RSS gate. The baseline fails 16 new page-25 assertions: two titles, 13 table rows
and the uninterrupted adjacent prose paragraph.

`comparison.json` records the every-page semantic audit. All 1,834 page markers match and
all 1,609 image files are byte-identical. Exactly 49 pages change:

- Page 25 gains complete 5-by-2 and 8-by-2 tables, including header rows. The only heading
  promotions are `Table 1. Calibrated Language for Confidence Assessment` and
  `Table 2. Calibrated Language for Likelihood Assessment`, recorded
  exactly in the summary. The adjacent prose rejoins `observa- tions` as `observations`,
  accounting for its two-character decrease. Source line-end hyphens inside table cells
  remain literal, including `well-docu- mented`; no cell text is silently discarded.
- Page 27 additionally gains a complete 6-by-4 scenario table, adding 2,112 selectable text
  characters. Its header and all five scenario rows were compared with the rendered source
  (Very High through Very Low, with CMIP5/CMIP6 values and descriptions). Its source image
  remains. Pages 28, 405 and 1135 remain unchanged; partial grid fragments are not admitted.
- The other 47 pages change only paragraph boundaries, with identical full text. The audit
  reconstructs every old paragraph by joining its consecutive new paragraphs, and records
  each split label plus the start of its following value. Every split is a contributor role
  or credit label followed by names/affiliations; none splits ordinary prose. Labels include
  Chapter Authors, Technical Contributors, Review Editor, Cover Art and the equivalent
  editorial roles on page 1799. Page 1738 now has exact separate paragraphs `Cover Art` and
  `Diane Burko`; the citation remains intact. No headings change on these 47 pages.

The audit is not a visual review of every page or an image legibility qualification.
The receipt's `qualifiedForFidelity` remains false. This establishes these source-backed
repairs, not a general solution for borderless tables or all role/name arrangements.

| Measurement | Final candidate |
| --- | --- |
| Converter SHA-256 | `3e037b636aaa6bc80fcaaf26fd0d018745dbdf42183a869813508a8c76cd559e` |
| EPUB SHA-256 | `f49ee81e3caf7528e34ac07e9949d62c269cfd50687ba345054bd5ab08b16ce8` |
| EPUB bytes | 269,201,094 |
| Extracted text characters | 5,555,452 |
| Conversion seconds | 107.98 |
| Peak RSS bytes | 987,906,048 |
| Sampled peak physical footprint bytes | 373,900,944 |
| Lifetime maximum physical footprint bytes | 413,435,560 |

Baseline EPUB SHA-256 is
`5690ef45951d24c63efc9d1c6798cad1aa242b92d2e32cb43ddc123e9f009f23`.
Runs used macOS 27.0 arm64 and recorded three concurrent evaluations. Timing and memory
are observations under contention, not a performance comparison or a mobile-device budget.
