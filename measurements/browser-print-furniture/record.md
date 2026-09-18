# Browser-print furniture, drawn bullets and bare-page titles (#167, #204)

Evidence for [#167](https://github.com/vocaro/PDFReflowLib/issues/167) on the TechPort web print
(`ntrs-20210020887-techport-thm-2021`, five pages, Chromium/Skia m92) and the probe-build doc fix
[#204](https://github.com/vocaro/PDFReflowLib/issues/204). Geometry below was read with
`tools/capture-layout-fixture.swift` (built with the corrected command in
[regression testing](../../doc/regression-testing.md)); no page raster is committed, since every
TechPort page carries the NASA insignia.

## Print footer

Every page ends with the same five lines, 8.2-point, in three rows closer together than a line:

| Line | Rect (x, y, w, h) |
| --- | --- |
| `For more information and an accessible alternative, please visit:` | 187.3, 54.5, 267.3, 10.0 |
| `Page N` | 547.9, 54.5, 28.1, 10.0 |
| `Printed on 08/24/2021` | 36.0, 47.0, 94.8, 10.0 |
| `https://techport.nasa.gov/view/97058` | 241.0, 44.0, 160.0, 10.0 |
| `03:51 PM CDT` | 36.0, 36.5, 59.7, 10.0 |

The TechPort logo is a vector region at 40.6, 60.0, 87.3 × 18.7 on every page.

**Root cause.** `FurnitureDetector` admits only the outermost row of the foot band (midpoint at
most 7% of the page height) and only when it is set apart from everything inward by a line height.
The outermost line, `03:51 PM CDT`, stands 0.5 points under `Printed on`, so nothing was a
candidate, and the rows above it lay outside the band anyway. A browser's or a site's print footer
is a block of rows, not one row.

**Fix.** Where a line of the outermost foot row is no candidate on its own, the rows stacked on it
(each nearer the stack than its own separation) form one block with it. A block within the outer
eighth of the page and of at most eight lines is set apart from the body as one row is; each line
is a candidate that goes only with all the others (a fixed-point pass in `apply`). Each line must
still repeat in its own three-page run, so a page's last lines never qualify, and a stack whose
outer row already qualifies (a bare folio, a ruled-off foot) is not formed. Art repeated in place
in the same margin on three nearby pages, level with a removed line and with no kept line between
it and the page edge, goes with the furniture (`marksBeside`). Separately, a boundary `N/M`
(Chromium's own footer count) is normalized like `Page N of M`.

## Drawn bullets

Pages 2 and 3 draw each `<ul>` marker as a 3 × 3-point path (7 × 7 with `GraphicsReader`'s
padding): squares at x = 77.25 before items whose text starts at 88.5, circles at 129.75 before
nested items at 141.0. Twelve markers on page 2 and six on page 3 became 17-pixel crops before
paragraph items. `DrawnBulletReader` turns a small, square, path-only region crossed by no text,
standing within 2.5 type sizes before a line on its row, into a `•` opening that line, when the
page has at least two of one size. The line then starts at the marker and records its text edge
(`TextLine.markerTextEdge`), because the nested markers stand 52.5 points (5.8 sizes) right of
their parents' markers, past `ListBuilder`'s five-size nesting bound, but 41 points (4.6 sizes)
past the parents' text: a browser indents a nested list from the item's text.

## Closeout Documentation and Images

Page 4's reflowable text is 190 characters of 9-point type (too little to establish a body), while
its three tables, kept as crops, set 9.7-point text, so the page estimate was 10 and the 10.5-point
titles were measured as sub-headings under it. `headingBodySize` now takes the document's body
where the page establishes none, the page estimate is larger, and the reflowable lines are
commonest in the document's body size; both titles become h3 like pages 1-3's.

## Wrapped URLs

`(https://techport.nasa.gov/imag` + `e/41317)`: Chromium breaks a long URL inside a word. A break
is inside an address when the address ends in a letter or digit, opens an unclosed bracket on its
line, and the next line's first word closes that bracket and holds an address separator.

## Results

TechPort before → after: images per page 3/15/10/6/5 → 2/2/3/5/4; no footer line on any page; lists
on pages 2-3 with the four nested items at level 1; both page-4 titles h3; four URLs whole. The
contract gains 45 checks (72 → 117); the baseline binary (`07c1bbd`) fails 44 of them.

All 20 gated lanes pass. Reading text of every lane EPUB was diffed against a `07c1bbd` conversion:
besides TechPort, 17 cases are identical and two lose only repeated margin crops through `marksBeside`:

- `dga-2025-2030`, pages 2-9: the running-foot band (the rule, the HHS and USDA logos and the
  already-removed `Dietary Guidelines for Americans, 2025–2030 | N` foot), one crop per page.
- `noaa-nca5-2023`, glossary pages 1806-1827: the glossary table's `Term | Definition` header band,
  repeated in place at the top of each page level with a removed running-head line (13 crops); the
  later chapter-file split moves with the smaller output, and no text changes.

## #204

The probe build in [corpus](../../doc/corpus.md) lacked `ImageContentClassifier.swift`, which
`PageRasterizer` uses since #193; with it the documented command compiles and the probe runs
(page 1 of the TechPort print: 1530 × 1980, Vision succeeds). No other source is missing. The same
list was stale in `tools/raster_sweep.py` and in the comments of `tools/probe-raster-environment.swift`
and `tools/probe-vision-titles.swift` (both verified to compile with it), and the layout-fixture
capture command in regression testing named `tools/capture-layout-fixture.swift` twice, which
`swiftc` rejects. `scripts/check-all.sh` now compiles the documented probe command as written.
