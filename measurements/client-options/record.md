# Client-controlled output policies

> `tools/evaluate-real-document.py` is now `tools/evaluate_real_document.py` (`6e6ba6c`); the paths below are as measured.

The public API and developer CLI independently select supplementary references, page/region
encoding, JPEG quality, entry-byte budget and final EPUB cap. Defaults remain automatic
references, PNG assets and a 512 MiB entry budget, with no separate final-file cap.
[The option guide](../../doc/conversion-options.md) defines semantics and tradeoffs.

## Verified scope

[Implementation identities](identity.json) pin source bytes on base revision `b5f1937`, the
release converter and macOS 27.0 (26A428). The host is Mac17,6, using Xcode 27.0 (27A266a).
The [final fast gate](pdfreflow-policy-final-fast.log.gz) passes 72 Swift tests, 53 Python tests,
six default fixture conversions and four policy combinations with EPUBCheck/reader admission.
Ten invalid or over-budget CLI requests fail with no output or false completion.
[CLI receipts](cli-results.json) record the exact flags and diagnostics.

The [complete eight-document default-policy regression](corpus-summary.json) passes reviewed
text/order/image/warning contracts, EPUBCheck and configured resource gates. Per-book resource
receipts are under `corpus/`. This run precedes the reader-only changes; the final fast gate
includes those changes and the new integrated policy checks. Production Swift remains the same.
[The iOS simulator result](ios-summary.json) passes all 72 tests on iPhone 18 Pro, iOS 27.0
(24A434), with no skips. Simulator results do not qualify physical-device memory or speed.

## Complete Warren report

The checksum-verified source is all 920 pages of `gpo-warren-1964`, SHA-256
`341cc3471750c9c3be68b95a34b52f6cbdc86c4392427a8483ee1c6bc53cfc19` (81,216,909 bytes).
Both runs use the production CLI/API directly, JPEG 0.90 for full pages and PNG for cropped
regions. These are fresh converter processes; conversion time excludes independent validation.

| Reference policy | Final EPUB MiB | Entry MiB | Images | Conversion seconds | Peak RSS bytes | Sampled peak footprint bytes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Automatic | 507.67 | 512.18 | 931 | 382.34 | 1,085,325,312 | 353,060,544 |
| Never | 4.62 | 6.38 | 21 | 13.74 | 966,115,328 | 327,058,872 |

The automatic-reference run explicitly disables the entry budget (`Int64.max`) and caps the
final EPUB at 512 MiB. The no-reference run retains the default 512 MiB entry budget and caps
the final EPUB at 64 MiB. Both publish within their selected caps and pass EPUBCheck without
errors or warnings. No-reference output retains 10 required fallback page JPEGs and 11 cropped
PNGs. All retained images have byte-identical counterparts in the reference-bearing output.
These are single Mac measurements, not performance distributions or physical-device budgets;
no RSS gate is configured for the Warren case, and the PDFKit leak remains unresolved.

Both runs retain all 920 ordered page anchors, 910 reflowed pages and 10 pages sent to OCR.
Both retain the same 910 unverified-layer warnings; omission adds 910 `referenceImageOmitted`
warnings directing review to the PDF. Required fallback and annotation warnings remain.
The corresponding [derived receipts](jpeg-references/result.json) and
[no-reference receipt](no-references/result.json) record effective options, successful progress
checks (2,876 / 1,962 events) and resource measurements.

[Content checks](warren-summary.json) compare paragraph/preformatted/heading text excluding
figure captions and normalize whitespace, ASCII hyphens and soft hyphens to accommodate
cross-page joins. That canonical text is identical. This is not exact XHTML/body-byte equality:
removing references allows more cross-page paragraph joining, and uncertain-hyphen warnings
increase from 231 to 237. Neither configuration establishes inherited OCR accuracy or complete
visual fidelity. Clients choosing omission must retain access to the source for verification.

`collect.py` records these independent content/image checks. Each run retains compressed raw
reports and the exact exec launcher. The original evaluator labels its arguments as library
defaults because it cannot inspect launcher-added flags; the derived receipt explicitly records
the effective options, raw-receipt hash, launcher identity and underlying converter identity.
Use the derived receipt for configuration claims. Large PDFs/EPUBs remain outside Git.

## Reproduction

Run from the repository root with full Xcode selected and fresh output paths:

```sh
python3 tools/fetch_corpus.py --case gpo-warren-1964
swift build -c release
swift run -c release pdf-reflow corpus/cache/GPO-WARRENCOMMISSIONREPORT.pdf /tmp/warren-jpeg.epub \
  --full-page-image-encoding jpeg:0.9 \
  --maximum-output-bytes unlimited --maximum-epub-bytes 536870912
swift run -c release pdf-reflow corpus/cache/GPO-WARRENCOMMISSIONREPORT.pdf /tmp/warren-no-references.epub \
  --reference-images never --full-page-image-encoding jpeg:0.9 --maximum-epub-bytes 67108864
epubcheck /tmp/warren-jpeg.epub
epubcheck /tmp/warren-no-references.epub
scripts/check-all.sh --corpus
```

For resource measurements, run `tools/evaluate-real-document.py` with an exec launcher matching
the retained flags; update its binary path for the checkout. The runner verifies the cached
source before consumption and measures the exec-replaced converter through child rusage.
No quality or encoding is silently changed after a size failure. The NOAA complete-book workload
and general visual/transcription qualification remain outstanding under the long-book roadmap.
