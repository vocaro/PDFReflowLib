# NOAA bibliography join on the complete report (#219)

Measured 2026-09-24 on macOS 27 arm64 with the default debug CLI at `f0ff96a38c7254e27566aa31c7690151cf6902592c631f45c7746c63ef9216ea`. The source is the cached Fifth National Climate Assessment PDF, 1,834 pages, SHA-256 `1942cbf346dc2c711fea413d6d6543edb8bc1e3a88d4c3a85e733c6b6d3577bf`. The one-page source regression for physical page 122 is `Tests/PDFReflowLibTests/fixtures/noaa-122-layout.json`; its entry 30 preserves `N. Viovy` and its DOI in one paragraph.

The full CLI conversion completed on defaults: 1,824 reflowed pages, no recognized pages, 1,618 images. Output EPUB SHA-256 was `063acf9be08b6db44e21dcd36be1815b5c161fd942286c758bf4aca99dd680c1`. EPUBCheck 3.3 reported zero errors and warnings.

A whole-EPUB XHTML census of `<p>` and `<pre>` whose text starts with `^[1-9][0-9]{0,3}\.\s+\S` found 9,448 numbered paragraphs and 189 numbered preformatted blocks. Of those, 9,434 paragraphs and 183 preformatted blocks contain a year followed by a colon, DOI, or HTTP address. These counts describe output shapes; they do not claim every citation is whole.

The residual matters. In `chapter-2.xhtml`, `2. USGCRP, 2018... C.W. Avery,` remains `<pre>` and its `D.R. Easterling...` continuation is a separate paragraph. `4. Mastrandrea... IPCC AR5` likewise splits from `guidance note...`, and a DOI continuation is its own `675. https://doi.org/...` preformatted block. By contrast, sampled entries 198–204 in `chapter-9.xhtml` are each whole; entry 200 remains `<pre>` but has no adjacent continuation. Thus the new detached-numbered-column rule fixes the pinned page-122 case without proving the full 599-page bibliography class. #219 stays open for entry boundaries across these layouts, Warren endnotes, and the other prerequisites it tracks.

The run's generated EPUB and log were kept under `/private/tmp` only during analysis; no NOAA pages, crops, or full XHTML are committed here.
