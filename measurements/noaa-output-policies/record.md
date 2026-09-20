# Full NOAA conversion with explicit output policies

> `tools/evaluate-real-document.py` is now `tools/evaluate_real_document.py` (`6e6ba6c`); the paths below are as measured.

Bounded qualification under [#5](https://github.com/vocaro/PDFReflowLib/issues/5), baseline
`193f807be95937cb1ddbfc1783d8d4f4aac0108c`, 2026-09-15. All **1,834 pages** of the Fifth
National Climate Assessment complete using the existing production CLI with explicit larger
storage caps. **The default-budget failure remains, and #5 stays open.** No library code,
default, standard corpus budget or shared inspector limit changes in this work.

## Configuration and identity

The unchanged source has 219,876,258 bytes and SHA-256
`1942cbf346dc2c711fea413d6d6543edb8bc1e3a88d4c3a85e733c6b6d3577bf`.
The measurement verifies that identity and the manifest's publisher SHA-512 before use.
No derivative, page subset or download is involved. The production executable SHA-256 is
`fe37820016f2c33ed6d7854219ac958308346e4a53e472f01629a35d8e85aa8f`.
Environment: macOS 27.0 (26A428), Xcode 27.0 (27A266a), arm64.

Both successful runs retain automatic references, PNG cropped regions, automatic OCR,
180 DPI, the 12-million-pixel raster ceiling and all other defaults. Each explicitly sets
**4,294,967,296 bytes (4 GiB)** for both the entry budget and final EPUB cap. These caps were
selected before the trials as experimental storage allowances; they are not minimal required
caps, memory budgets or recommendations for a device. The second run changes only full-page
encoding from PNG to JPEG 0.90. The cap is never changed after a failed conversion.

The existing evaluator measures exec-replaced CLI processes. Its raw receipt assumes library
defaults because it cannot inspect a launcher's added arguments. `png-result.json` and
`jpeg-result.json` record the effective flags, launcher identity, actual executable identity
and hash of each preserved raw receipt. Use those derived receipts for configuration claims.

## Whole-book results

| Full-page policy | Final EPUB bytes | Uncompressed entry bytes | Conversion seconds | Peak converter RSS bytes | Sampled peak physical footprint bytes |
| --- | ---: | ---: | ---: | ---: | ---: |
| PNG | 1,466,266,570 | 1,516,406,112 | 131.74 | 1,038,221,312 | 393,397,784 |
| JPEG 0.90 | 1,461,859,121 | 1,522,700,828 | 120.13 | 1,031,471,104 | 392,398,384 |

Both outputs have 81 spine documents, 11,245 images, 1,823 pages containing reflowed text,
zero OCR pages and all 1,834 ordered source anchors. Both pass EPUBCheck with zero errors
or warnings and the independent ZIP/XML/link/navigation/spine-packing checks. Each has
15,317 monotonic CLI progress events ending at completion; staging is removed.

JPEG saves only **4.20 MiB (0.30%)** in the final archive while increasing entry bytes by
**6.00 MiB**. The 10,389 unchanged cropped PNGs account for 746,992,236 bytes; 856 full-page
assets change encoding. A JPEG recommendation based on scanned Warren pages does not imply
comparable savings on this illustrated digital report. These observations do not support
changing NOAA's default encoding or promising completion within the default 512 MiB budget.

The converter processes ran sequentially: default failure, PNG, then JPEG. Validation runs
between conversions. Timing excludes validation and is a single observation per policy,
not a speed distribution or an ordering-neutral comparison. RSS excludes separate Apple
services; physical footprint is a separately sampled metric. No case RSS ceiling or physical
iPhone/iPad budget is established. Large staging/storage needs and broad fidelity remain
unqualified.

## The default failure stays separate

A fresh default run extracts every page, then fails with `image output bytes` after the last
completed reconstruction page **599** (the historical run stopped after 598). It takes 63.77
seconds, peaks at 1,028,816,896 bytes RSS and 391,546,440 sampled footprint bytes, and publishes
no EPUB. Its raw successful-conversion assessment correctly remains false. The separate
`default-failure.json` verifies the expected failure, monotonic incomplete progress, no false
completion, and staging cleanup. This failure is not counted as a successful corpus conversion.

## Content and visual scope

The whole-book comparison requires every spine document's complete XHTML to remain identical
apart from PNG/JPEG image extensions. This protects all emitted text, inline styles, heading
levels, source markers, figure placement and internal anchors across the two policies, without
claiming the common output is correct everywhere. Every image keeps its page, order and raster
dimensions. All 10,389 cropped PNGs must be byte-identical. Warnings are exactly identical.

Source rasters were independently reviewed before evaluating the output: landscape page 48's
temperature chart and prose, page 80's Chapter 2 cover, page 1619's Chapter 32 cover, and the
final page 1834 with agency seals and publication information. See the
[existing page-48 source](../noaa-nca5-2023/source-page-48.png) and `review/source-*.png`.
Three source-derived text checks require the page-48 title, “Climate Trends” on 80 and
“Mitigation” on 1619. Four reviewed pages must retain images.

The final page's source phrases “nca2023.globalchange.gov” and “U.S. Global Change Research
Program” **do not reflow**. An initial text assertion rejected that page; the failed inspection
is retained. This remains explicit as `reviewedSourceTextPreservedOnlyAsImage`, not a passing
text expectation. The converter reports `pageImageFallback`, emits exactly one full-page
image, and preserves the source seals and readable text in the reviewed PNG and JPEG output.

The retained output samples are actual EPUB assets. Page 48's shaded summary, plotted lines,
axes, chart labels and surrounding prose are unchanged PNG crops. The three reviewed JPEG
full pages retain titles, artwork and final-page text; they show encoding differences, especially
in the Chapter 2 artwork. Sample PSNR values are 31.36, 42.50 and 35.76 dB for pages 80, 1619
and 1834. `image-review.json` reports numerical differences, not a visual pass threshold.
This is sampled readability review, not qualification of all charts, numerical values, chapter
boundaries, alt text, paragraph ownership or every preserved image.

The existing shared content inspector has 10,000-entry/512 MiB admission bounds, which reject
this large valid output. That separate limitation is tracked in
[#25](https://github.com/vocaro/PDFReflowLib/issues/25). This measurement uses a dedicated
20,000-entry/4 GiB bound, reads chapters individually and hashes images one at a time. The
shared inspector and routine default-policy corpus exclusions remain intact.

## Cancellation and regression checks

`cancel.swift` links the same release library objects and uses the public conversion API on
the complete checksum-pinned PDF with the explicit JPEG policy. It cancels once at reconstruction
page 900 and separately at the writing handoff after all 1,834 pages have reconstructed.
Both throw `CancellationError`, emit no completed/1.0 event and leave empty output directories.
`cancellation-checks.json` independently checks the trigger, page coverage, progress and cleanup.
The 69.44/99.88-second observations are total time until each cancelled call returns, not
cancellation latency or performance comparisons. In-progress platform calls remain cooperative.

Four measurement test functions pass, including negative controls for missing pages, wrong-page
phrases, captions masquerading as source text, altered markup/text/image ownership/pixels/size,
false completion, leftover staging and absent cancellation triggers. All 69 existing Python
tool tests pass after the manifest/documentation updates. The unchanged release library builds.
Both complete NOAA outputs supply fresh production conversion and EPUB validation evidence.
No runtime Swift or fixture change is made, so a new macOS/iOS Swift-suite or eight-book default
corpus run is not claimed for this measurement-only change.

## Reproduce

Use new directories, the pinned cache, full Xcode, Python with Pillow, and EPUBCheck. The runner
requires at least 12 GiB free for its two complete trials and leaves the large EPUBs local.

```sh
swift build -c release
python3 tools/evaluate-real-document.py --case noaa-nca5-2023 \
  --pdf corpus/cache/noaa_61592_DS1.pdf --converter .build/release/pdf-reflow \
  --output /tmp/noaa-default --timeout 900 --epubcheck /opt/homebrew/bin/epubcheck
# Expected nonzero default result; run the explicit trials separately.
python3 measurements/noaa-output-policies/measure.py \
  --converter .build/release/pdf-reflow --epubcheck /opt/homebrew/bin/epubcheck \
  --output /tmp/noaa-full --default-evaluation /tmp/noaa-default
python3 -m unittest discover -s measurements/noaa-output-policies -p 'test_*.py' -v
```

The macOS SwiftPM build on this host exposes release module/object files as follows. Other
SwiftPM build layouts may need the equivalent paths from `swift build --show-bin-path`.

```sh
swiftc -parse-as-library -O -swift-version 6 -I .build/release \
  measurements/noaa-output-policies/cancel.swift \
  .build/release/PDFReflowLib.o .build/release/ZIPFoundation.o -o /tmp/noaa-cancel
mkdir /tmp/noaa-cancellation
/tmp/noaa-cancel corpus/cache/noaa_61592_DS1.pdf \
  /tmp/noaa-cancellation/cancel-reconstructing reconstructing \
  > /tmp/noaa-cancellation/cancel-reconstructing.json 2> /tmp/noaa-cancellation/cancel-reconstructing.log
/tmp/noaa-cancel corpus/cache/noaa_61592_DS1.pdf \
  /tmp/noaa-cancellation/cancel-writing writing \
  > /tmp/noaa-cancellation/cancel-writing.json 2> /tmp/noaa-cancellation/cancel-writing.log
python3 measurements/noaa-output-policies/measure.py \
  --converter .build/release/pdf-reflow --epubcheck /opt/homebrew/bin/epubcheck \
  --output /tmp/noaa-full --inspect-only --default-evaluation /tmp/noaa-default \
  --cancellation-evaluation /tmp/noaa-cancellation
```

Render independent source pages with `pdftoppm -f 80 -l 80 -scale-to 1500 -png -singlefile
corpus/cache/noaa_61592_DS1.pdf /tmp/source-80`, repeating for 1619 and 1834. Compare with the
actual assets in the runner's `review/` directory; generated EPUBs and source PDFs stay ignored.

`receipts.tar.gz` contains exact reports, launchers, resource samples, progress/EPUBCheck logs,
full parsed inspections, cancellation logs and failed initial text-inspection evidence.
`implementation-sha256.txt` identifies unchanged runtime and measurement sources. The original
run identity in the archive predates the dedicated inspector's admission/last-page refinements;
final `--inspect-only` results and negative controls exercise the retained inspection code.
The fresh default failure, large archive sizes, missing final-page reflow, #25 inspection limit,
and unqualified physical-device/broader content scope remain visible. No issue is closed.
