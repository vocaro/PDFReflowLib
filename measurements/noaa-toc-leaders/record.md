# Painted contents leaders and detached locators

The #191 integration audit found genuine contents locators lost or detached on
NOAA physical pages 8, 19 and 20. The source is the 1,834-page Fifth National Climate
Assessment, `noaa-nca5-2023`, SHA-256
`1942cbf346dc2c711fea413d6d6543edb8bc1e3a88d4c3a85e733c6b6d3577bf`.
The manifest records its publisher-declared public-domain provenance. No source
PDF, rendering, converted book, or machine log is committed.

The complete source pages were rendered and inspected against the prior landed
and #191 integration EPUBs. Page 8 visibly pairs About This Report with xx,
Guide to the Report with xxi, and the chapter 1 subsections with 1-5, 1-16 and
1-23. Page 19 pairs its focus entries with F3/F4/F5 locators; page 20 pairs the
Indicators and Glossary entries with A4/A5 locators. Every such row has a painted
horizontal leader. The corner drawing's raster canvas begins at x=358.5 and
extends over the locator column even where its visible artwork does not.
Separating the paints exposed this conservative image footprint: short entries
stand entirely to its left, so the existing straddling-row test could no longer
release their detached locators. Longer rows happened to remain readable.

`LeaderRows` joins only native upright untagged entry/locator pairs linked by an
explicit horizontal stroke, repeated at least three times in an aligned locator
column. Roman or chapter-qualified locators are bounded in length and width;
font size and baseline must agree, and both leader endpoints must meet their
text pieces. Semantic table cells are excluded. It carries both original inline
contents, including links and styles, into one row. The existing crop-straddling
and reading-order rules then preserve that complete row. No crop, alpha-mask,
page-reference fallback, or general numeric-table rule changes.

`noaa-toc-{8,19,20}-layout.json` contain raw schema-3 captures made with
`tools/probes/capture-layout-fixture.swift` on the pinned source, plus `nativeLines`
encoded from the native reader with the same source rules, text-show evidence
and link annotations as `PageReader`. These extra lines preserve the actual
split entry/locator geometry and inline metadata; the ordinary capture omits
annotation input and can merge a short entry with its locator. Tests replay the
individual paints through `TextBackdrop`, then crop ownership and reconstruction.
They require all 25 + 28 + 15 entry/locator pairs in their printed order, unchanged
source characters/link counts, and retained artwork. Disabling the join causes
68 source assertions to fail; restoring it passes all source controls.

The full Swift suite passes all 813 tests on the isolated candidate.

Negative controls preserve semantic tables, tagged rows, rotated rows, recognition,
synthetic typography, fewer than three proved rows, non-stroked paint, and diagonal
strokes. Inline bold text and source links survive the positive control.

The corpus contract now requires all 68 complete entry/locator phrases in source
order, while retaining prior image and credit checks. Full integrated NOAA and
21-document qualification is pending the root task's final conversion; this
bounded change does not claim a new whole-book run.
