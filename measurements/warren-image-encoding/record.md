# Warren full-page image encoding experiment

This experiment measures all 920 pages of the pinned Warren Commission report on a Mac17,6,
macOS 27.0 (26A428), Xcode 27.0 (27A266a), release library revision
`774452a7c952f58b9cde0b35082900997b59589c`. [Identity](identity.json) records the source checksum,
producer hashes and SDK versions. No production conversion or reference-image policy changes.

## Results

| Encoding of full-page images | Complete EPUB, MiB | Entries before ZIP compression, MiB | EPUBCheck |
| --- | ---: | ---: | --- |
| PNG baseline | 1187.79 | 1189.19 | Pass |
| ImageIO JPEG 0.90 | 507.67 | 512.19 | Pass |
| ImageIO JPEG 0.95 | 534.21 | 539.69 | Pass |

MiB means 1,048,576 bytes. [Exact sizes and output hashes](package-results.json) retain all
931 image assets, 920 ordered page anchors and identical body text in every variant. All three
pass EPUBCheck 3.3 rules without errors or warnings. JPEG 0.90 reduces the complete file by
57.3%; 0.95 by 55.0%. The settings are encoder parameters, not percentages of fidelity.

The default 512 MiB guard counts **uncompressed entry bytes**, not the final ZIP length or RAM.
Consequently both JPEG variants still exceed it: 0.90 by 200,787 bytes. Issue #5 remains open.
The baseline runner explicitly overrides the public output budget to 2 GiB to collect the
complete book; this is experimental completion, not a passing default-budget conversion.
The 512 MiB default is an initial configurable engineering budget, not an EPUB or Apple limit.

The baseline conversion takes 357.07 seconds, with 1,096,941,568 bytes peak RSS and
398,132,712 bytes peak physical footprint reported by `time -l`. These are different metrics;
this single Mac run does not establish a mobile budget or resolve the PDFKit leak. The report
contains 910 reflowed pages and 10 recognized pages. All 2,876 progress events have valid bounds,
monotonic fractions and a final completion event; fractions measure work, not elapsed time.
[Progress checks](progress-check.json) and compressed raw logs preserve the evidence.

Re-encoding all 920 page images plus two independent controls at both settings takes 44.71
seconds, 282,296,320 bytes peak RSS and 131,417,000 bytes peak footprint. This is a separate
post-conversion pass, not a measurement of a production JPEG conversion pipeline.

## Image fidelity and scope

The encoder uses exactly the production PNG rasters at the default 180 DPI, without resizing.
Only the 920 full-page reference/fallback images change encoding in the experimental EPUBs;
all 11 cropped regions remain byte-identical PNGs. Text, source anchors and document structure
remain unchanged. Compression neither validates inherited OCR nor improves reconstruction.

The [local comparison](review/index.html) has matched pixel crops from physical pages 21, 50,
100, 890 and 910, plus a numeric table from Our Flag page 27 and a synthetic colored fraction.
Visual inspection of the PNG/0.90/0.95 crops finds no lost characters or reduced legibility at
native crop size. This is limited sample review, not a full-book visual qualification or a
reader study. Crop edges intentionally cut across the same source coordinates in all variants.

Across the 920 page images, pixel-weighted RGB PSNR is 43.39 dB for 0.90 and 43.87 dB for 0.95;
minimum page scores are 41.02 and 41.68 dB. These measure pixel differences, not semantic fidelity.
The per-image metrics retain errors and byte sizes, including less favorable controls.

In particular, the table grows from 29,258 PNG bytes to 49,792 / 52,357 JPEG bytes; the fraction
from 4,390 to 5,369 / 5,583 bytes. The fraction has substantially larger color-channel errors
than the scanned prose. These results support keeping equations and clean cropped diagrams
lossless; JPEG is not universally smaller or equally suitable for every image.

High-quality JPEG is a promising full-page scan option, but the default remains PNG pending a
product decision. Output-budget policy and whether references should accompany reflowed OCR
are separate decisions; neither changes in this experiment.

## Reproduction

The scripts preserve the exact measured producer bytes. Run from the repository root with
full Xcode selected, Python (Pillow for review crops), and EPUBCheck installed. The Python
producers intentionally use `/tmp/pdfreflow-encoding-experiment`; start with a new directory
at that location (move any existing results aside first). Large PDFs, images and EPUBs stay
outside Git. Fetch through the checksum-verifying corpus tool before consumption.

```sh
python3 tools/fetch_corpus.py --case gpo-warren-1964
swift build -c release
mkdir /tmp/pdfreflow-encoding-experiment
xcrun swiftc -O -parse-as-library -I .build/release -L .build/release -lPDFReflowLib \
  measurements/warren-image-encoding/convert.swift -o /tmp/pdfreflow-encoding-experiment/convert
/usr/bin/time -l /tmp/pdfreflow-encoding-experiment/convert \
  corpus/cache/GPO-WARRENCOMMISSIONREPORT.pdf /tmp/pdfreflow-encoding-experiment/warren-png.epub \
  > /tmp/pdfreflow-encoding-experiment/conversion-report.json \
  2> /tmp/pdfreflow-encoding-experiment/conversion-progress.log
python3 measurements/warren-image-encoding/prepare.py
xcrun swiftc -O -parse-as-library measurements/warren-image-encoding/encode.swift \
  -o /tmp/pdfreflow-encoding-experiment/encode
/usr/bin/time -l /tmp/pdfreflow-encoding-experiment/encode /tmp/pdfreflow-encoding-experiment \
  > /tmp/pdfreflow-encoding-experiment/image-metrics.jsonl \
  2> /tmp/pdfreflow-encoding-experiment/encoding-progress.log
python3 measurements/warren-image-encoding/package.py
python3 measurements/warren-image-encoding/review.py
epubcheck /tmp/pdfreflow-encoding-experiment/warren-png.epub
epubcheck /tmp/pdfreflow-encoding-experiment/warren-q90.epub
epubcheck /tmp/pdfreflow-encoding-experiment/warren-q95.epub
```

The package producer asserts ordered anchors, identical text and untouched crop bytes, and
checks that all manifest resources exist. ZIP timestamps may differ on reproduction; content
checks and size comparisons are more useful than requiring a new ZIP to have the same hash.
The committed gate log records 65 Swift tests, 51 Python tests and six small PDF conversions
with EPUBCheck. The complete eight-document regression lane is not rerun: production Swift
code is unchanged. The JPEG experiment is not part of that lane and does not qualify NOAA.
