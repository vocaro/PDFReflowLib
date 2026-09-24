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

Independent review added two adversarial controls. A leader cannot jump over a
third native text rectangle in its row corridor; moving that obstruction outside
the corridor restores the otherwise identical positive case. All multiplicative
table, candidate, rule, obstruction and aligned-row comparisons share a 2,000,000
comparison budget. Exhaustion returns the exact original line array, including
when some valid pairs have already been found. A 200-line/8,000-rule input that
previously required 80 million rule checks is covered at the default limit;
the focused test completed in 0.232 seconds on the review host. Low injected
budgets additionally verify unchanged fallback rather than partial association.
All four focused tests (including the three source pages and all 68 pairs) pass.
The root task owns the final integrated suite and whole-conversion gates.

## Complete contents-page qualification

The final whole-book comparison exposed seven further missing locators on physical
pages 9, 10, 12, 13, 15 and 16. Complete renders of all six pages confirm ordinary
wrapped entries ending in 4-16, 9-5, 15-17, 18-11, 24-21, 27-8 and 27-21. The
preceding row has 11pt baseline leading but a 13.27pt PDFKit rectangle. Its extra
leading therefore overlaps the last row's rectangle by 2.27pt, while its actual
text does not cross the last row's leader. The initial full-row obstruction box
incorrectly treated this as intervening text.

The obstruction corridor now takes the vertical band of the proved horizontal
stroke, retaining the same entry-to-locator horizontal interval. Text intersecting
that stroke band still rejects the join. A generated control distinguishes an
overlapping preceding row from the same row lowered onto the painted leader.
No evidence thresholds, comparison limits, crop fallback or numeric interpretation
change.

Fresh native captures extend coverage to all thirteen contents pages, 8–20. The
ten added fixtures carry source lines extracted with native rules, links and text
shows, plus their encoded inline metadata and original paint operations. They
were captured with the same unchanged NativeTextReader/NativeSpacingReader and
GraphicsReader versions as integrated revision 4f301ca. Existing fixtures for
8/19/20 remain unchanged. No reconstruction output becomes fixture evidence.

All 272 complete entry/locator phrases are asserted in printed order. Wrapped
prefixes are read from the preceding source rows' matching margins, sizes and
leading. Existing paragraph boundaries are not pinned; the original 68 single-row
block checks remain, and each of the seven newly restored locators must join its
actual final source row. Source characters, links and retained artwork remain
checked on every page. The corpus contract replaces shorter contents prefixes
with these complete entries to avoid duplicate forward-order searches.

On exact integrated 4f301ca, the expanded tests report 16 failures: seven missing
complete source entries, seven missing native row associations and two generated
leading controls. The existing final NOAA EPUB fails precisely the seven new
complete-entry contracts; all other checks in the expanded 411-check NOAA contract
pass. Restoring the stroke-band correction passes all five focused tests, including
all thirteen source pages and the existing budget/obstruction negatives. All 33
Python corpus-content tests pass. Final corrected whole-book conversion remains
with the coordinator; no new conversion is claimed by this bounded fix.
