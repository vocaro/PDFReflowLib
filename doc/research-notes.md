# Research notes and ruled-out approaches

This document collects experiments and investigations that produced useful findings but are not
themselves open tasks: approaches that were tried and rejected, and measurements whose conclusions
already inform current defaults or documentation. See the linked measurement records for full
evidence. Open follow-up work belongs in GitHub issues, not here.

## Warren Commission (scanned OCR)

- **Selective OCR retry policy (opt-in).** Re-recognizing image-backed existing text with an
  opt-in selective retry policy repairs the checked Warren phrase (page 50, "his known contacts
  with the Soviet Embassy") while preserving native controls elsewhere. It also introduces other
  errors, so broader accuracy/detection was not adopted as a default. See
  [selective-ocr evidence](../measurements/selective-ocr/record.md). Follow-up detection work is
  tracked in [#7](https://github.com/vocaro/PDFReflowLib/issues/7).
- **Full-book JPEG re-encoding.** Re-encoding the full 920-page Warren report as JPEG
  substantially reduces file size but both tested quality variants still exceed the default
  entry-byte budget, so this was not adopted as a general fix for the image-output ceiling. See
  [warren-image-encoding evidence](../measurements/warren-image-encoding/record.md). Taking the
  smaller of PNG and JPEG 0.90 per image, the best a per-image encoding choice can do at that
  quality, still leaves the book 349,408 bytes over the 512 MiB default
  ([opaque-page-rasters evidence](../measurements/opaque-page-rasters/record.md)). The
  underlying ceiling is tracked in [#5](https://github.com/vocaro/PDFReflowLib/issues/5).
- **Grayscale page rasters.** Rewriting the scans as 8-bit gray would cost about 73% of their
  bytes, but the pages are yellowed paper whose channels differ by a mean of 26–55 levels, so it
  is a quality change, not a free one, and was not taken.

## Raster DPI and encoding defaults

A seven-page, six-document raster sweep (fine colored labels, scans, tables, photographs and
equations) compared 120/180/240 DPI and PNG/JPEG at quality 0.90. The results support retaining
180 DPI as the baseline and reviewing 240 DPI for small detail, with measured storage costs and
pixel-cap behavior. This conclusion is already reflected in the [recommended conversion
settings](conversion-options.md#recommended-starting-settings). See
[raster-dpi evidence](../measurements/raster-dpi/record.md).

## CDC Zombie Pandemic comic (OCR headings)

- **Blanket OCR-heading suppression.** Rejected: it loses the genuine "Part 2" title. Quadrilateral
  height and Vision's title flag used alone also fail source controls. No runtime repair was
  retained from this experiment. See
  [ocr-headings evidence](../measurements/ocr-headings/record.md).
- **Vision container-title metadata mapping.** The separate container-title validation under
  [#24](https://github.com/vocaro/PDFReflowLib/issues/24) checked 14 source pages across five
  PDFs. Unique text/region ownership and agreement with the line-title flag still admit prose,
  dialogue, sign and running-header false positives, and recognized titles omit genuine title
  continuations. Metadata-only mapping was rejected; #24 was closed with no production title
  mapping adopted. See [vision-titles evidence](../measurements/vision-titles/record.md).

## Fed report (heading/body distinction)

A threshold change intended to sharpen the heading/body-text boundary was rejected because it
lost six genuine headings. The retained heuristic and its evidence are recorded in
[heading-body-regressions](../measurements/heading-body-regressions/record.md), which also
includes the original failing case for [#12](https://github.com/vocaro/PDFReflowLib/issues/12)
(closed).

## Structure-tag consumption

A caption-order/oversized-heading approach considered while validating structure-tag consumption
under [#17](https://github.com/vocaro/PDFReflowLib/issues/17) was rejected in favor of the
retained spatial-fallback design. See
[structure-tags evidence](../measurements/structure-tags/record.md).
