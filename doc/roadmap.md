# Development priorities

The library converts PDFs to EPUB 3 on Apple platforms 27+. Synthetic regressions cover basic
layout, OCR, images, EPUB packaging, progress and cancellation. General textbook fidelity and
physical-device memory/performance remain unqualified.

- **First priority: regression coverage across document types.** Run
  `scripts/check-all.sh --corpus` for extraction, layout and rendering changes. The reviewed
  [content contracts](../corpus/regressions.json) protect text, selected reading order, images
  and warnings across eight complete PDFs; they do not qualify all pages. Every fidelity fix
  needs a failing source-derived case plus positive controls in other layouts. Expand checked
  table cells, equation structure, image appearance and chapter continuity as those issues are
  addressed. Keep known failures separate from passing baselines; never regenerate expected
  content from converter output alone. See [the regression workflow](regression-testing.md).
- Investigate [PDFKit attributed-text leaks](https://github.com/vocaro/PDFReflowLib/issues/4)
  without losing formatting; keep the
  fresh-process high-water-mark gate and establish physical iPhone/iPad memory budgets.
- Expand mathematical qualification beyond native inline scripts: review exercise/answer-key
  numbering, detached fractions and unsupported formula structures across the algebra book.
- Support the Warren Commission scanned report: [full conversion exhausts the image-output
  ceiling](https://github.com/vocaro/PDFReflowLib/issues/5), and general notes/index ownership
  remains unqualified. Exclusively invisible image-backed text no longer supplies font-based
  code or heading evidence. [Detect suspect inherited OCR](https://github.com/vocaro/PDFReflowLib/issues/7)
  beyond the conservative unverified-layer warning. Evidence: [Warren baseline](../measurements/gpo-warren-1964/record.md).
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
  section-local bullet order. See the
  [shading measurement](../measurements/shading-support/record.md).

- The NOAA Fifth National Climate Assessment adds a 1,834-page, 219.9 MB stress workload.
  It reaches the [image-output ceiling](https://github.com/vocaro/PDFReflowLib/issues/5) after
  reconstruction page 598. Establish full completion and memory budgets before qualification;
  use its 32 chapter bookmarks to investigate [chapter-aware splitting and bounded processing](https://github.com/vocaro/PDFReflowLib/issues/15).
  Evidence: [NOAA baseline](../measurements/noaa-nca5-2023/record.md).

- The 56-page Our Flag booklet supplies a quick illustrated baseline with ten checked table rows.
  Its populated structure tree has Marked=false and lacks table roles and figure alternate text.
  Implement [validated tag consumption with spatial fallback](https://github.com/vocaro/PDFReflowLib/issues/17)
  and general table semantics; correct drop-cap
  ordering and flag image/name/description groups. The [baseline](../measurements/gpo-our-flag-2003/record.md)
  passes validity, progress and the 192 MiB Mac RSS gate. Its page-27 numeric table is preserved
  as a warned image; tag consumption and drop-cap/figure ownership remain unqualified.

- The 42-page CDC Zombie Pandemic comic adds sparse/noisy text and image-only speech balloons.
  Detect suspect inherited dialogue and preserve [panel/balloon order](https://github.com/vocaro/PDFReflowLib/issues/18)
  or clearly signal readable image fallback. The [baseline](../measurements/cdc-zombie-pandemic-2011/record.md)
  passes validity, progress and the 512 MiB Mac RSS gate; dialogue quality remains unqualified.

- The 312-page Blue Book statistical scan supplies a warning/refusal contract. The converter
  reports unverified text layers and preserves source images; reliable scanned-table detection
  and reconstruction remain open under [suspect inherited OCR](https://github.com/vocaro/PDFReflowLib/issues/7)
  and general table reconstruction.
  Passing the signaling contract does not qualify table transcription.

Attachment-placeholder filtering, actionable source-layer warnings and correct whole-page raster
scaling are covered by [regressions and source-derived measurements](../measurements/quality-and-raster-fixes/record.md).

Merged-region clipping is covered by source-derived algebra geometry, formula/table pixel tests,
and a complete eight-document rerun; see [preserved-region regressions](../measurements/preserved-region-regressions/record.md).

Native inline superscripts/subscripts, FAA page-91/511 column order and Our Flag page-27 numeric
table preservation are covered by [source-derived regressions and full-corpus evidence](../measurements/three-fidelity-fixes/record.md).
Controls also protect 9/11 name/description rows and CDC OCR line spacing. These targeted fixes
resolve #1, #2 and #16; they do not qualify arbitrary math, table transcription or every column layout.

Bounded detached-fraction preservation (#20) and suppression of synthetic OCR font semantics
(#6) have enforced regressions, visible-typography controls and source review; see
[fraction and invisible-text measurements](../measurements/fractions-and-invisible-text/record.md).
Math outside the detector, mixed text layers, inherited OCR accuracy and full scanned-book
completion remain unqualified.
