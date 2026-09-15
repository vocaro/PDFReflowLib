# Development priorities

The library converts PDFs to EPUB 3 on Apple platforms 27+. Synthetic regressions cover basic
layout, OCR, images, EPUB packaging, progress and cancellation. General textbook fidelity and
physical-device memory/performance remain unqualified.

- Correct FAA handbook [column order on physical pages 91 and 511](https://github.com/vocaro/PDFReflowLib/issues/2),
  and [whole-page fallback scaling on page 121](https://github.com/vocaro/PDFReflowLib/issues/3).
  Add source-derived regressions and compare against original pages.
- Investigate [PDFKit attributed-text leaks](https://github.com/vocaro/PDFReflowLib/issues/4)
  without losing formatting; keep the
  fresh-process high-water-mark gate and establish physical iPhone/iPad memory budgets.
- Preserve [inline mathematical superscripts](https://github.com/vocaro/PDFReflowLib/issues/1):
  the Wallace algebra corpus exposes a flattened
  squared exponent on page 343 despite preserved displayed formulas. Add a targeted regression
  when implementing the fix; review exercise and answer-key numbering across the book.
- Support the Warren Commission scanned report: [full conversion exhausts the image-output
  ceiling](https://github.com/vocaro/PDFReflowLib/issues/5); [invisible OCR fonts misclassify
  prose and headings](https://github.com/vocaro/PDFReflowLib/issues/6), and notes/index columns
  interleave. [Detect suspect inherited OCR](https://github.com/vocaro/PDFReflowLib/issues/7)
  and [exclude object placeholders](https://github.com/vocaro/PDFReflowLib/issues/8) from text/counts. Evidence: [Warren baseline](../measurements/gpo-warren-1964/record.md).
- Correct [absolute image URLs in the Poppler simple preview](https://github.com/vocaro/PDFReflowLib/issues/9) without weakening
  local server containment; retain raw Poppler output and a reproducible rendered comparison.
- Investigate [9/11 report header/heading confusion](https://github.com/vocaro/PDFReflowLib/issues/10),
  keeping the external ALL-CAPS prototype counts distinct from library measurements. Qualify
  [endnote markers/links](https://github.com/vocaro/PDFReflowLib/issues/11) and timeline-label ownership; retain the successful native word-spacing
  examples as positive review targets. See the [baseline](../measurements/gpo-911-2004/record.md).
- The development corpus includes the FAA handbook, Wallace algebra textbook, Warren
  Commission scanned report, 9/11 digital report, The Fed Explained and the illustrated Dietary
  Guidelines booklet, with identities, review
  points and baselines. Originals are fetched explicitly into a checksum-verified ignored cache.
  Correct [Fed prose classified as headings](https://github.com/vocaro/PDFReflowLib/issues/12);
  qualify tagged table/figure semantics and mixed diagram/prose pages; expand with borderless tables,
  footnotes, damaged encodings and non-Latin layouts. Measure coverage and reading order.
- Evaluate OS 27's native progress composition APIs while retaining ordered client reporting.
  The minimum deployment version remains 27.

- Improve [region preservation around shading/complex graphics](https://github.com/vocaro/PDFReflowLib/issues/13)
  and [native word boundaries/graphic labels](https://github.com/vocaro/PDFReflowLib/issues/14).
  Bounded shading is supported; the ten-page DGA case now reflows text on nine pages. Qualify
  section-local bullet order and remove object placeholders exposed by that reflow. See the
  [shading measurement](../measurements/shading-support/record.md).

- The NOAA Fifth National Climate Assessment adds a 1,834-page, 219.9 MB stress workload.
  It reaches the [image-output ceiling](https://github.com/vocaro/PDFReflowLib/issues/5) after
  reconstruction page 598. Establish full completion and memory budgets before qualification;
  use its 32 chapter bookmarks to investigate [chapter-aware splitting and bounded processing](https://github.com/vocaro/PDFReflowLib/issues/15).
  Evidence: [NOAA baseline](../measurements/noaa-nca5-2023/record.md).
