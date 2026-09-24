# Conservative ownership during magazine integration

The complete NOAA comparison exposed native-text regressions beyond the existing content
contract. Source inspection traced them to decomposing aggregate page-sized artwork and to
omitting ICC fills based only on nominal component values. The earlier converter preserved a
whole-page source reference and native text; local crops newly took titles, captions and prose.

The final rule retains that conservative handling when the original aggregate graphic covers
more than 75% of the page, unless every individually page-sized paint independently proves a
flat ground or background shading. A photograph mixed with a proved backdrop does not qualify.
ICCBased numeric paint is flat, but component count and Alternate do not establish actual white
without processing the embedded profile. Device-color handling remains unchanged.

Independent source audit found aggregate coverage above 75% and no individual page-sized paint
on NOAA pages 5, 25, 26, 34, 40, 41, 49, 52, 57, 62 and 76. The source controls retain the
previous reference/native behavior. USDA 20–21 each have a proved page-sized background shading;
other magazine controls and TechPort 1–5 have smaller aggregate bounds, so their improvements
remain eligible. Fixtures 52 and 62 capture the pre-omission source footprints and native text,
not converted EPUB output. No raster or PDF is committed.

Separate local ownership corrections preserve source-proved content when crops remain local:
known semantic tables retain their numbered titles and aligned introductions; a prose row split
at a small reference number can complete its width using the adjacent part at the same row
height. This requires a size ratio at most 0.75, at least 80% height overlap and at most 0.5em gap.
Existing paragraph length, leading, measure, language and numeric guards still apply. Up to two
immediately preceding, aligned larger native headings stay with a proved paragraph. Synthetic
and recognized typography cannot supply that heading evidence. Equal-size adjacent table cells
cannot complete a row, and duplicate knockout copies are removed only at the same position.

Thirteen focused tests passed, including two source fallback cases, native row/heading and
table-introduction cases, ICC state/unknown-color controls, and magazine controls. The separate
mixed full-page photograph/backdrop negative passed after adding native prose to ensure it
exercises the guard. Existing chart-axis, numeric-table, figure-legend and knockout-caption
controls passed. Independent review found no concrete blocker in the paragraph changes.

A complete 1,834-page intermediate NOAA run with this fallback preserved all page markers and
removed the eleven observed native-text loss cases. Remaining comparison differences and the
final integrated corpus qualification are recorded with the final integration, not asserted as
passed here. Raw audit and conversion artifacts remain outside version control.
