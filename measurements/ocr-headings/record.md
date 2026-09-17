# Rejected OCR-heading repair for the CDC comic

Investigation of [#18](https://github.com/vocaro/PDFReflowLib/issues/18) on 2026-09-15,
baseline `6992fb3`, macOS 27.0 (26A428), Xcode 27.0 (27A266a), arm64.
**No runtime repair is retained.** Issue #18 remains open for speech/panel order,
dialogue typography, transcription and readable fallback signaling.

## Source evidence and mechanism

The complete 42-page CDC *Preparedness 101: Zombie Pandemic* source is pinned to SHA-256
`d95e9ec2d8cf52cb8c218a6195e132ec140725018358fd2122928bab8a13efc3`.
Physical pages 13, 15 and 16 were visually reviewed. Page 13 has speech balloons, page 15
has the genuine Part 2 title, and page 16 depicts tilted building signs and logos.
See the [existing page-13 raster](../cdc-zombie-pandemic-2011/source-page-13.png),
`source-page-15.png` and `source-page-16.png`. These are source rasters, not expected
converter output. They establish semantic intent independently of extraction.

`OCRReader` stores each Vision text line's axis-aligned bounding-box height in `fontSize`.
`LayoutReconstructor` then uses the same relative-size heading heuristic as for native
typography. This promotes page-13 speech fragments `AND SEE WHAT'S HAPPENING...` and
`UН? WHД?` to headings. The latter contains inherited OCR substitutions; the source reads
`UH? WHA?`. No correction of those characters is proposed here.

## Rejected experiment

`prototype.patch` records the complete experimental runtime, test and corpus changes. It
excluded fresh OCR pages from the font-size heading heuristic. Three of four new test
functions failed before the change; all four passed afterward, including native heading
controls and a real scanned-page conversion. A source-reviewed paragraph assertion for
`AND SEE WHAT'S HAPPENING...` rejected the old full-book EPUB and passed the prototype.

The complete eight-book before/after comparison showed identical text, inline scripts,
page anchors and 3,922 image files over 2,151 pages. Exactly three source pages changed
heading/paragraph semantics, all in the CDC comic:

| Page | Removed heading | Source review |
| --- | --- | --- |
| 13 | `AND SEE WHAT'S HAPPENING...`, `UН? WHД?` | Speech fragments; desired demotion |
| 15 | `ZOMBIE PANDEMIC` | Genuine part-title; unacceptable regression |
| 16 | `JCDC` | Noisy transcription of a sign/logo; desired demotion |

The experiment passed all 152 Swift tests on macOS and iOS 27 Simulator, 69 Python tests,
fixture/policy/concurrency checks, EPUBCheck, progress and existing memory budgets, plus
222 content checks on 54 pages. **These passes did not make the change acceptable.**
The uncontracted page-15 title was lost from heading/navigation semantics. The synthetic
scan's real title also became a paragraph under the blanket rule. This approach was
rejected and all runtime, test-resource and passing-contract edits were removed.

## Bounded alternatives inspected

The retained `cdc-*-ocr-geometry.json` files capture native Vision line quadrilaterals and
title flags with the current OCR transcription. The capture tool makes a second equivalent
recognition request to retain raw Vision fields; this diagnostic does not change runtime
recognition or infer speaker identities. The default source-page raster scale is used.

Measuring mean quadrilateral side length in PDF points instead of axis-aligned box height
does not resolve the two page-13 false headings together:

| Text | Box height | Mean side height | Vision `isTitle` |
| --- | ---: | ---: | --- |
| `OKAY, OKAY... I'M COMING.` | 9.90 | 9.90 | true |
| `AND SEE WHAT'S HAPPENING...` | 13.28 | 11.53 | false |
| `UН? WHД?` | 13.61 | 13.20 | false |
| Page-15 `ZOMBIE PANDEMIC` | 87.49 | 83.78 | false |

Page-13's dominant height rounds to 10 points; its existing heading threshold is 12.5.
The quadrilateral refinement still promotes `UН? WHД?`. Vision's title flag independently
mislabels the first dialogue fragment and omits the genuine large page-15 title. These
observations rule out treating either signal alone as an established repair on this source.
No threshold adjustment, dictionary replacement or document-specific exception was shipped.

## Blocker and remaining work

A source-supported classifier or panel/balloon association is still needed to distinguish
dialogue, tilted sign text and real comic section titles. Page-level OCR geometry and the
inspected title flag are insufficient alone. The experiment was stopped at that boundary.
Panel order, speaker ownership, noisy characters and readable image fallback remain
unresolved under #18. Validated Vision title mapping is separately tracked in
[#24](https://github.com/vocaro/PDFReflowLib/issues/24); no such mapping is implemented here.

## Reproduction and receipts

The unchanged baseline completes all eight corpus conversions with 221 content checks.
`results.json` and `receipts.tar.gz` retain the **rejected prototype's** full gate and comparison;
the source hashes identify its temporary implementation. `prototype.patch` can restore that
experiment for investigation but must not be mistaken for an accepted fix. The compressed
before/after, full-gate and iOS logs are also experimental receipts. Fresh final baseline
Swift verification passes all 148 tests and is recorded separately in `restored-tests.log.gz`.

Capture source evidence without applying the prototype:

```sh
xcrun swiftc -parse-as-library Sources/PDFReflowLib/OCRReader.swift \
  Sources/PDFReflowLib/OCRTextCoverage.swift \
  Sources/PDFReflowLib/PageRasterizer.swift Sources/PDFReflowLib/ConversionTypes.swift \
  Sources/PDFReflowLib/DocumentModel.swift Sources/PDFReflowLib/ReflowDocument.swift \
  tools/capture-ocr-layout-fixture.swift -o /tmp/capture-ocr-layout-fixture
/tmp/capture-ocr-layout-fixture cdc-zombie-pandemic-2011 13 /tmp/cdc-13.json
```

The tool verifies the corpus checksum before reading the page. Repeat for pages 15 and 16.
It needs access to Vision's platform image services; a filesystem sandbox prevented
CVPixelBuffer creation in the initial capture, while the platform-enabled run succeeded.
These are Mac/Simulator observations, not physical iPhone/iPad qualification.
