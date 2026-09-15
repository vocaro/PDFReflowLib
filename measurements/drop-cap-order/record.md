# Drop-cap opening order and semantics

Native decorative initials no longer turn their body line into a heading, move that line after
its continuation, or acquire a spurious subscript. This is a bounded spatial/typographic fix
under #17; it does not implement PDF logical structure tags.

## Mechanism and source evidence

Our Flag physical page 7 combines a 43.523-point initial T and a 9-point body line into a single
44.716-point-tall PDFKit selection. The initial has a -24-point baseline offset. Using its font
and the selection's vertical midpoint misclassifies the opening as a heading and orders the
next line first. Page 31 has the same pattern with an initial A.

`NativeTextReader` recognizes an oversized, lowered single uppercase initial followed by at
least 20 letters of consistently sized, normal-baseline prose beginning with lowercase text.
The size ratio is bounded; inconsistent evidence and monospaced initials are rejected. With
sufficient selection geometry, its body font supplies heading evidence and an optional
body-height `readingRect` at the selection's top supplies reading order. The full ink `rect`
remains unchanged for graphic intersections and crop expansion. Paragraph-join geometry is
unchanged. The initial's large baseline offset describes layout, not an inline subscript.

Source review and regression targets:

- Page 7: the Stars and Stripes opening precedes the Marine Committee/Continental Congress
  continuation and remains prose. The genuine chapter heading remains.
- Page 31: the burial-flag opening precedes the funeral-director continuation and remains prose.
  The genuine heading and photograph remain.
- Page 9: the mid-page opening follows the flag image and precedes its continuation. The restored
  adjacency lets the existing vocabulary-based hyphen policy join source `some-` / `times` to
  `sometimes`. This is the only changed word join in the complete comparison.
- Page 27: both drop caps cease to be headings; the two real section headings and the previously
  preserved ten-row numeric table remain. The existing table regression covers all ten pairs.
- Page 30: genuine superscript numerators in two 2½-inch measurements survive beside a drop cap.

Pages 7/9/30/31 were rendered in full with Poppler and visually reviewed. Page 27 has retained
source review and a bundled layout fixture from the table work. Three new layout fixtures capture
pages 7/9/30; pages 27/31 reuse existing source captures. These are native text/geometry/attribute
records from the checksum-pinned Our Flag PDF, not generated expected converter output. Source
SHA-256: `a47a3153b649022a52b53e7b0c40b55bfea24e7980bbe32fe6fee0cf1936bbd8`.

## Verification

Ten `DropCapTests.swift` tests cover the source cases, complete ink bounds, offset page coordinates,
ordinary initials/scripts, multi-letter labels, short/uppercase continuations, inconsistent
font/baseline runs, missing attributes, monospaced text and insufficient geometry. Existing
cross-document script, heading, table, list, figure and reading-order controls remain enforced.
`before-tests.log.gz` captures failures of the two original source openings with the ink-bound
and ordinary-typography controls passing. `before-content.json.gz` rejects the prior complete
Our Flag EPUB for the new paragraph/order requirements.

Final default-policy release CLI validation, macOS 27 / Xcode 27 arm64:

- 120 Swift tests pass on macOS and iOS 27 Simulator, iPhone 18 Pro.
- 62 Python tests pass.
- Six fixture conversions and four policy conversions pass, with ten rejection/cleanup cases.
- Eight complete corpus PDFs pass EPUBCheck, navigation, ordered progress, configured memory
  gates and 186 content checks across 48 reviewed pages.

`identity.json` pins runtime/test/tool/fixture bytes and toolchain; the baseline is `bd62936`,
retained from the complete preformatted-style run. The compressed logs and per-case receipts
record the final run. Physical-device performance remains unqualified. Full Warren and NOAA
default conversions remain explicit exclusions, not passing cases.

## Complete comparison

`collect.py` requires every parsed page in the other seven books to remain identical. In Our Flag,
19 opening headings on 18 pages become paragraphs and their initial-letter subscripts disappear.
Genuine headings and all other script spans retain their text/context. Removing just those opening
phrases from the before/after text leaves all remaining prose in exactly the same order, with the
single source-reviewed `sometimes` repair on page 9. All 3,922 image files retain identical bytes,
names and page ownership. `comparison-summary.json` identifies every affected opening;
`flag-page-comparison.json.gz` retains all changed page content for further review.

The 18-page count measures the effect of the bounded rule, not comprehensive human qualification
of all those pages. Initial-word spaces such as `T he` and `A ny`, complete paragraph grouping,
other drop-cap layouts, flag figure/text ownership and actual structure-tree consumption remain
open. No dictionary or title-specific replacement is introduced; #17 stays open.

## Reproduce

With full Xcode selected and the checksum-verified corpus cache available:

```sh
scripts/check-all.sh --corpus
xcodebuild test -scheme PDFReflowLib-Package \
  -destination 'platform=iOS Simulator,id=<available-device-id>' CODE_SIGNING_ALLOWED=NO
python3 measurements/drop-cap-order/collect.py \
  --before <baseline-complete-corpus> --after <candidate-complete-corpus> \
  --logs <directory-with-baseline-and-final-logs> --output <new-evidence-directory>
```

Render source pages using `pdftoppm -f <page> -l <page> -singlefile -png` and recapture native
layout with `tools/capture-layout-fixture.swift`, as documented in `doc/regression-testing.md`.
