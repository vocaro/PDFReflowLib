# Native styles in preformatted lists and code

> The Swift probes moved to `tools/probes/`, and `tools/pdfreflow_tools/swift_sources.py` now owns the library source list each one compiles with (`6e6ba6c`); the paths and hand-copied source lists below are as measured.

The release converter retains native superscripts, subscripts and emphasis in preformatted
blocks. Previously, reconstruction copied `line.text` into a plain `String`, losing the styles
already present in `line.content`. The internal model now stores `InlineText` for these blocks,
and the EPUB encoder emits escaped styled runs inside `<pre>`. Joined code lines receive
unstyled newline/indentation runs. Public APIs, list recognition, geometry, hyphen policy and
conversion defaults are unchanged.

## Source-reviewed cases

- Wallace algebra, physical page 26: exercise 80 visibly reads
  `(7a² + 7a) − (6a² + 4a)`. Both exponents are raised in native attributed runs but were flattened
  in the list block. The full-book contract now checks each exponent in its own context.
- FAA handbook, physical pages 211/212: bullet definitions use subscripted V-speed designators.
  Page 211 supplies S0 and FE checks; page 212 supplies YSE and MC checks. Source airspeed
  indicator illustrations remain preserved. Twelve additional native subscript spans reach
  these pages' EPUB text.

Source identities are pinned in `corpus/manifest.json`. The three new layout JSONs capture native
text, geometry and attributed runs, not converter output. Source pages were rendered in full
with Poppler and visually reviewed. Algebra material is copyright 2010 Tyler Wallace, used under
[CC BY 3.0](https://creativecommons.org/licenses/by/3.0/); see
[attribution and source](../../doc/third-party-notices.md#wallace-algebra-development-fixture).
PDFs remain in the ignored checksum-verified corpus cache.

## Regressions and evidence

`PreformattedStyleTests.swift` adds eight tests covering source exponents/subscripts, all existing
list-marker forms, monospaced emphasis and indentation, literal markup, block transitions,
unchanged hyphens, inline page navigation, model immutability and styled spine-size accounting.
The existing plain-code test asserts semantic text and encoding rather than a particular run
segmentation. Existing prose script, preserved fraction, source OCR, heading and list controls
remain enforced.

`before-tests.log.gz` records three failing tests on the original runtime: the synthetic list,
monospaced style and source exercise cases. Plain-list and block-transition controls pass.
`before-content.json.gz` and `before-faa-content.json.gz` reject the prior complete-book EPUBs
for flattened exponents/subscripts. One additional Python test proves the corpus checker rejects
flattened or wrongly associated scripts within preformatted text, including nested emphasis.

Final validation on macOS 27, Xcode 27, arm64, release CLI with default conversion policies:

- 110 Swift tests pass on macOS and iOS 27 Simulator (iPhone 18 Pro).
- 62 Python tests pass.
- Six fixture conversions and four client-policy conversions pass, with ten rejection/cleanup cases.
- Eight complete corpus PDFs pass EPUBCheck, source navigation, configured memory limits,
  ordered progress and 160 content checks across 45 reviewed pages.

The baseline is commit `0fd4728`, retained from the complete native-line-boundary measurement.
`identity.json` pins the final runtime/test/tool/fixture bytes and collector, plus OS/toolchain.
`corpus-summary.json` and the per-case compressed receipts retain exact results.

## Complete before/after comparison

`collect.py` checks every output block across the eight books. It permits inline style differences
only inside preformatted blocks, and requires their entire plain text to remain identical.
Every other serialized block remains identical. All parsed page text, heading/paragraph groups,
source-page order and existing script spans remain unchanged. All 3,922 image entries retain
identical bytes, names and page ownership.

The comparison detects 1,177 additional script spans on 69 algebra pages and 12 on two FAA pages;
these counts describe retained extraction evidence, **not 1,189 independently qualified notation
repairs**. Per-page new spans are retained in compressed `added-scripts.json.gz` files for review.
The other six books have no new script spans. Their preformatted emphasis can still be retained;
script counts alone do not count bold/italic changes.

This does not qualify arbitrary mathematical layout or script inference. In particular, algebra
page 26 has fragmented exercise grouping outside the reviewed example. Numbered note association,
chapter-scoped endnote links (#11), true list semantics and general exercise/answer-key ordering
remain open. Full Warren and NOAA default conversions remain explicitly excluded for their
known output-ceiling limitation; Simulator results are not physical-device qualification.

## Reproduce

With full Xcode selected and checksum-verified corpus originals cached:

```sh
scripts/check-all.sh --corpus
xcodebuild test -scheme PDFReflowLib-Package \
  -destination 'platform=iOS Simulator,id=<available-device-id>' CODE_SIGNING_ALLOWED=NO
python3 measurements/preformatted-styles/collect.py \
  --before <baseline-complete-corpus> --after <candidate-complete-corpus> \
  --logs <directory-with-baseline-and-final-logs> --output <new-evidence-directory>
```

Render the source examples with `pdftoppm -f 26 -l 26 -singlefile -png` for the algebra PDF,
and physical pages 211/212 for the FAA PDF. Recapture source fixtures with
`tools/capture-layout-fixture.swift` as documented in `doc/regression-testing.md`.
