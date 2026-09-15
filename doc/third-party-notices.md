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

`Tests/PDFReflowLibTests/fixtures/algebra-{17,343,479}-layout.json` contains extracted text,
bounding geometry and attributed runs from those physical pages, transformed into test-only
JSON representations. Algebra source rasters and EPUB comparisons in
`measurements/preserved-region-regressions/`, `measurements/three-fidelity-fixes/` and
`measurements/fractions-and-invisible-text/` are rendered
and/or arranged review derivatives. These derivatives retain CC BY 3.0 attribution and are not
relicensed under MIT. They are not resources of the shipped library target.

## Government-document development fixtures

The `faa-91`, `faa-511`, `flag-27`, `911-451`, `cdc-5`, `warren-50` and `warren-910` layout JSONs under the test fixtures
contain extracted text and geometry from the corresponding U.S. government corpus documents.
Each records its publisher URL, title and pinned source checksum. The source and output renders
in `measurements/three-fidelity-fixes/`, `measurements/fractions-and-invisible-text/`,
`measurements/warren-image-encoding/` and `measurements/poppler-relative-images/` retain
the same provenance. These are development and
review resources, separate from the shipped library target; see `corpus/manifest.json`.
