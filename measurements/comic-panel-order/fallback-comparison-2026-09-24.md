# CDC comic page 13: OCR versus readable-image fallback

Issue [#18](https://github.com/vocaro/PDFReflowLib/issues/18), measured 2026-09-24 on macOS 27 arm64. This is a comparison, not an automatic comic detector or a fix. The [panel-order audit](record.md) supplies the broader 42-page controls.

The source is `corpus/cache/cdc_6023_DS1.pdf` (SHA-256 `d95e9ec2d8cf52cb8c218a6195e132ec140725018358fd2122928bab8a13efc3`). `pdfseparate -f 13 -l 13` produced a one-page PDF (SHA-256 `2d168f7ff588b41805b191b9d77a0c41b7ea162482119ba5b55974d62f6dbb1d`). The debug `pdf-reflow` executable was SHA-256 `fa866d450ed407f11ec066fd6724f1bad9899847f46c45526220e0552278fd65`. The one-page extraction is numbered page 1 in its EPUB.

| Conversion | Report | Page content |
| --- | --- | --- |
| `--ocr always`, with Vision available | 1 recognized, 1 reflowed; `ocrUsed` and source-reference `imageRegion` | Lower-left `OKAY, OKAY... I'M COMING.` is the first paragraph. Upper-right `UH? WHД?` appears later. `AND SEE WHAT'S HAPPENING...` is an h2, although it is part of a speech balloon. A page image follows the erroneous text. The earlier full-book audit found the same failure at defaults. |
| `--no-ocr` | 0 recognized, 0 reflowed; `pageImageFallback` | One image and no headings or uncertain OCR transcript. The extracted image is 1530 × 1980 pixels; visual inspection confirms the upper-right awakening exchange, lower-left response and lower-right reaction are legible in their printed panel order. |

The bounded commands were:

```sh
pdfseparate -f 13 -l 13 corpus/cache/cdc_6023_DS1.pdf /private/tmp/pdfreflow-cdc18-13.pdf
.build/debug/pdf-reflow /private/tmp/pdfreflow-cdc18-13.pdf /private/tmp/pdfreflow-cdc18-13-escalated.epub --ocr always
.build/debug/pdf-reflow /private/tmp/pdfreflow-cdc18-13.pdf /private/tmp/pdfreflow-cdc18-13-noocr.epub --no-ocr
```

The recorded OCR package was `/private/tmp/pdfreflow-cdc18-13-escalated.epub` (SHA-256 `8c11af81d909691b344310da8552fa779e263c3e87f882a0305177a33d3657a2`); the image-only package was `/private/tmp/pdfreflow-cdc18-13-noocr.epub` (SHA-256 `164b002cc664822f05d5fb7a965fe364ccced3dce2c20f9a4810627cec4af86b`). They are local captures, not committed artifacts. Vision failed in the restricted sandbox and emitted an image fallback; the OCR result above came from a normal-permission run. A Vision failure does not demonstrate an ordering repair.

The source-reviewed negative control from the [earlier audit](record.md) is CDC page 24 (wrong order) versus page 26 (correct order): both have comparable balloon layouts. Its geometry table also shows that wrong-order pages can resemble two-column prose. A text-only rule that changes page 24 need not preserve page 26, and a blanket fallback for fresh-OCR pages would degrade ordinary scanned books. The previous raster gutter prototype used seven thresholds calibrated to this one comic and was not retained; no second comic is present in the local corpus for calibration. A reviewed transcription has not been prepared. Thus the explicit `--no-ocr` image path is readable on page 13, but there is still no source-independent, validated trigger for applying it automatically. #18 remains open.
