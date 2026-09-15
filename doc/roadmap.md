# Development priorities

The library converts PDFs to EPUB 3 on Apple platforms 27+. Synthetic regressions cover basic
layout, OCR, images, EPUB packaging, progress and cancellation. General textbook fidelity and
physical-device memory/performance remain unqualified.

- Correct FAA handbook column order on physical pages 91 and 511, and whole-page fallback
  scaling on page 121. Add source-derived regressions and compare against original pages.
- Investigate PDFKit attributed-text memory growth without losing formatting; keep the
  fresh-process high-water-mark gate and establish physical iPhone/iPad memory budgets.
- Expand the corpus with redistribution-cleared documents covering borderless tables, math,
  footnotes, damaged encodings and non-Latin layouts. Measure coverage and reading order.
- Evaluate OS 27's native progress composition APIs while retaining ordered client reporting.
  The minimum deployment version remains 27.
