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
- The development corpus includes the FAA handbook, Wallace algebra textbook and Warren
  Commission scanned report, with source identities, review points and baseline measurements. Expand it with borderless tables,
  footnotes, damaged encodings and non-Latin layouts. Measure coverage and reading order.
- Evaluate OS 27's native progress composition APIs while retaining ordered client reporting.
  The minimum deployment version remains 27.
