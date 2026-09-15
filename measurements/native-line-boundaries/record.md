# Native combined-line word boundaries

Native extraction restores two missing title boundaries using PDFKit's existing baseline metadata:
DGA page 1 reads “Guidelines For Americans” and Our Flag page 31 reads “Burial Flag for a Veteran”.
This is a bounded part of #14. No dictionary, OCR correction, PDF-specific title replacement or
new dependency participates in the runtime repair.

## Source evidence and scope

On the DGA cover, PDFKit reports “GuidelinesFor Americans” in one line selection, with two
56.3566-point runs at baseline offsets 50.7209 and 0. The source visibly places “Guidelines”
and “For Americans” on separate lines. Our Flag supplies the opposite offset direction: its
18-point heading runs have offsets 0 and -18, but the extracted text is “Burial Flagfor a Veteran”.
Both source pages are visually reviewed; checksum-pinned native extraction JSONs are committed
under the test fixtures, not generated from EPUB output.

The detector requires similarly sized fonts, finite baseline evidence, a jump exceeding the
existing inline-script range, and at least one full-line offset. It adds a space only where neither
run already supplies whitespace. Line-ending hyphens and soft hyphens retain existing joins.
Unequal-size drop caps, ordinary same-baseline style runs and opposite superscripts/subscripts
do not qualify. A standalone large offset does not add text or imply an inline script.

DGA's “Dair y” and “Ve getables” occur inside single runs and remain unchanged. Our Flag's
separate drop-cap reading-order defect remains unchanged. No diagram-label ownership, arbitrary
word-spacing or OCR spelling-repair claim is made.

## Validation and comparison

The production CLI uses default options on macOS 27.0 (26A428), arm64, Xcode 27.0 (27A266a).
`identity.json` pins runtime, tests, tools and corpus identities against base `ff334ce`. The before
comparison uses retained complete outputs from [spine packing](../spine-packing/record.md), not
fresh timing measurements of the old implementation.

The complete eight-document comparison permits only the two exact reviewed word-boundary
changes. It rejects any other per-page text, paragraph/heading grouping, inline-script observation
or image-order change. All image bytes and page ownership/order must remain identical.
`comparison-summary.json` records EPUB hashes, page coverage and image counts; the two
`*-reviewed-title.json` files retain parsed before/after content and semantics.

Final gates pass 102 Swift tests on macOS and iOS 27 Simulator, 61 Python tests, six fixture
conversions, four client-policy conversions and ten rejection/cleanup cases. All eight complete
PDFs pass EPUBCheck, spine/navigation checks, progress, source anchors and configured memory
gates. The verified comparison contains exactly two inserted word boundaries, with all 3,922
image bytes and page ownership/order unchanged. The six other books' parsed pages are identical.

The expanded corpus contains 151 assertions across 42 reviewed pages. The title contracts require
the corrected text (and heading semantics for Our Flag), reject the former concatenations, and
retain source images. The remaining corpus checks continue to protect known-good text, ordering,
inline scripts and explicit warnings across the other layouts.

`before-tests.log.gz` captures the first six test functions on the original implementation: the
DGA source title and both baseline-key cases fail, while whitespace/hyphen, script, drop-cap and
single-run controls pass. The additional Our Flag source case has its own regression, and
`before-flag-content.json.gz` shows its final EPUB contract rejecting the retained original output.
`before-content.json.gz` does the same for DGA. Neither expected title comes from converter output.

## Reproduction

With the checksum-verified corpus cache and full Xcode:

```sh
PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer scripts/check-all.sh --corpus

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -scheme PDFReflowLib-Package \
  -destination 'platform=iOS Simulator,id=C4966BA9-56CD-4F21-9829-68567AAE8E6F' \
  -derivedDataPath /tmp/pdfreflow-boundary-ios CODE_SIGNING_ALLOWED=NO

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 \
  measurements/native-line-boundaries/collect.py --before /path/to/baseline/corpus \
  --after /path/to/new-gate/corpus --logs /path/to/boundary-test-logs --output /path/to/evidence
```

The Simulator identifier and temporary paths are host-specific. The collector requires eight
passing complete evaluations and rejects changes outside the two reviewed titles. Permanent
regression gates do not require the retained old EPUBs. Compressed per-case receipts contain
conversion/content results, progress, memory samples and EPUBCheck; platform gate logs are
retained separately.

Full Warren/NOAA default conversions remain explicitly excluded from the successful-conversion
corpus lane. Physical-device qualification, PDFKit leaks, arbitrary mathematical layout and
inherited OCR accuracy remain outside this measurement. Public API and defaults are unchanged.
