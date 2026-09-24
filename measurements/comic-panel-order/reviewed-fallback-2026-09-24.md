# Reviewed comic-page image fallback (#18)

Source review on 2026-09-24 compared three routes allowed by the owner. The pinned CDC source is
`corpus/cache/cdc_6023_DS1.pdf` (SHA-256
`d95e9ec2d8cf52cb8c218a6195e132ec140725018358fd2122928bab8a13efc3`).
The independent comic is the CDC's public-domain [*Coyote and the Turtle's Dream*, volume 1](https://stacks.cdc.gov/view/cdc/44241),
downloaded as `cdc_44241_DS1.pdf` (SHA-256
`40b162990643bcf55092cff79b976012364b9b5f1801fdebeebc3f33ae04ce38`, 56 physical pages).
The ordinary scanned-prose control is the corpus's Census report `rrs2002-01.pdf`.

| Route | Source result | Fidelity and cost |
| --- | --- | --- |
| Raster panel/balloon detection | The earlier [panel audit](record.md) found 15 wrong-order CDC dialogue pages, but a seven-threshold gutter prototype found panels on only 10 pages and rows on four more; an estimated nine of the 15 would improve. CDC pages 24 (wrong order) and 26 (correct order) both print a two-by-two panel grid. *Coyote* p11 sets two irregular bordered comic rows above narration, not CDC's regular dark grid. | No tested detector covers all CDC pages or the independent style; tuning to the first book and relying on environment-dependent decoded pixels is not a safe default. |
| Reviewed per-book transcription | A transcript could preserve every balloon and its speaker if each page were read against the artwork. None is checked in. CDC p13's default OCR still emits the lower-left response before the upper-right awakening and makes speech an `h2`; p24 emits the whole left column before the upper-right balloon and promotes three more speech fragments. | Requires reviewing and maintaining dialogue, panel order, speaker ownership and navigation over 42 CDC pages, plus controls for later OCR/model changes. No partial transcript is treated as a verified book. |
| Reviewer-selected image fallback | `--reviewed-panel-pages` now bypasses OCR on selected one-based physical pages, writes a full-page image and reports `reviewedPanelImage` and `pageImageFallback`. On CDC p13, the 1530 × 1980 image visibly keeps the upper-right exchange before the lower-left response, and the EPUB contains no false dialogue heading. On p24 the image preserves its four panels. In a two-page p24/p26 excerpt selecting only p24, p26 remains recognized and reflowed with its existing correct source order. | Requires a human to identify uncertain pages; selected dialogue does not reflow or become a screen-reader transcript. Both p13 and p24 selected EPUBs and the p24/p26 excerpt pass EPUBCheck 3.3 with zero errors or warnings. |

The independent comic is a useful negative control: its p11 already has a native text layer.
With OCR disabled, the current converter reflows its opening left/right dialogue in source order,
though several balloon wraps are separate paragraphs. A blanket comic fallback would remove that
usable text. The ordinary Census scan is another negative control: the quiet corpus receipt for
`census-rrs2002-01` records ten recognized, twenty reflowed pages, and its physical p4 has
meaningful recognized section headings and prose. A blanket fallback for fresh OCR would discard
them. A page-specific reviewed selection changes neither source.

Two same-environment `--no-ocr` CDC p13 conversions produced byte-identical image assets and
XHTML. That says nothing about pixel identity across operating systems; the separate
[raster-environment measurements](../raster-environment/record.md) and Vision run variation remain
limits. The reviewer-selected route does not depend on image pixels to *choose* pages, and the
page image remains inspectable even if its encoded bytes differ. Page 13's reviewed output image
was inspected at its written resolution, not inferred from the conversion warning.

The default CDC conversion still has wrong dialogue order. This opt-in path gives a reliable,
explicitly limited result for pages a reviewer identifies, but it does not close #18: automatic
selection or a complete reviewed page map/transcript still needs evidence and qualification.
