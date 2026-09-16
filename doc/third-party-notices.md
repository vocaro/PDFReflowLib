# Third-party notices

## ZIPFoundation 0.9.20

Source: https://github.com/weichsel/ZIPFoundation/tree/0.9.20

MIT License

Copyright (c) 2017-2025 Thomas Zoechling (https://www.peakstep.com)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## foliate-js (optional development reader)

Source: https://github.com/johnfactotum/foliate-js/tree/78914aef4466eb960965702401634c2cb348e9b1

Used by the standalone test viewer only; not linked into the PDFReflowLib Swift library.
The pinned files and hashes are recorded in `tools/epub-reader/assets.json`.

MIT License

Copyright (c) 2022 John Factotum

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Wallace algebra development fixture

*Beginning and Intermediate Algebra*, copyright 2010 Tyler Wallace.
[Source PDF](https://s3.amazonaws.com/myopenmath/cfiles/19515/Beginning_and_Intermediate_Algebra.pdf),
[author's site](http://wallace.ccfaculty.org/book/book.html),
[Creative Commons Attribution 3.0 Unported](https://creativecommons.org/licenses/by/3.0/).

`Tests/PDFReflowLibTests/fixtures/algebra-{16,17,26,343,479}-layout.json` contains extracted text,
bounding geometry and attributed runs from those physical pages, transformed into test-only
JSON representations. Algebra source rasters and EPUB comparisons in
`measurements/preserved-region-regressions/`, `measurements/three-fidelity-fixes/` and
`measurements/fractions-and-invisible-text/` and `measurements/raster-dpi/` are rendered
and/or arranged review derivatives, as is the region reference
`corpus/references/wallace-algebra-2010/page-347-exercise-35.png`. These derivatives retain CC BY 3.0
attribution and are not relicensed under MIT. They are not resources of the shipped library target.

## Replay Clocks review derivatives

*Replay Clocks* by Ishaan Lagwankar and Sandeep S Kulkarni, arXiv:2311.07842v1 (2023).
[Source](https://arxiv.org/abs/2311.07842v1),
[Creative Commons Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0/).

`measurements/arxiv-replay-clocks-2023/source-page-1.png` is a rendered source page, and
`source-inspection.json` and `selected-page-xhtml.json` there contain extracted and converted
text from pages 1, 3 and 4. These derivatives retain CC BY 4.0 attribution, are not relicensed
under MIT and are not resources of the shipped library target.

## Government-document development fixtures

The `faa-{91,363…365,437…439,511}`, `fed-{13,32,45,46,54,75,77,103,109,123}`, `flag-{27,31}`, `911-{19…26,33,50,51,65…71,451,471…476,579…585}`, `cdc-5`, `dga-1`, `warren-50`, `warren-910`, `blue-5`, `blue-12`, `noaa-{33,80,139,1619}`, `usgs-{1,2}` and `nbs-7` layout JSONs under the test fixtures
contain extracted text and geometry from the corresponding U.S. government corpus documents.
Each records its publisher URL, title and pinned source checksum. The source and output renders
in `measurements/three-fidelity-fixes/`, `measurements/fractions-and-invisible-text/`,
`measurements/warren-image-encoding/`, `measurements/poppler-relative-images/` and
`measurements/raster-dpi/` retain
the same provenance. These are development and
review resources, separate from the shipped library target; see `corpus/manifest.json`.

Grayscale region references under `corpus/references/` for the Our Flag, USGS, FAA, NBS and CDC
cases are low-resolution renders of U.S. government works, with provenance in each JSON sidecar.

Review rasters, Poppler text inspections and selected converted XHTML under
`measurements/{usgs-mcs2025-copper,scotus-loper-bright-2024,census-rrs2002-01,irs-p596-zhs-2025,nbs-jres-geltman-1977,uscis-m618-arabic-2015}/`
derive from U.S. government works (USGS, the Supreme Court, the Census Bureau, the IRS, NBS/NIST
and USCIS). Their rights evidence is recorded per case in `corpus/manifest.json`; USCIS states
some guide images are licensed, so no USCIS rasters are committed. These review resources are
not relicensed under MIT.

The four `map-region-*.png` review crops in `measurements/report-header-qualification/` come
from the 9/11 report's physical pages 33/50/51. Page 33 credits its graphics to ESRI. These
source-derived review images retain the report's provenance and are not relicensed under MIT.
