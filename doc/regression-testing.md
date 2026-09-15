# Regression testing

Regression coverage across PDF types is the first development priority. Fixes to extraction,
layout or rendering require both a reproducer and positive controls from other layouts.
A valid EPUB can still contain incorrect text, wrong reading order or unreadable images.

## Gates

- `scripts/check-all.sh --fast`: Swift extraction/model/raster/EPUB tests, Python tool tests,
  and six small fixture conversions. No external PDFs are required. The raster tests inspect
  pixels, including crop origins, rotations, annotations and resource ceilings. Preserved-region
  tests also inspect fraction bars, raised exponents and all six cells of a ruled table in actual
  EPUB images at 72/144 DPI, with surrounding-prose and code controls.
- `scripts/check-all.sh --corpus`: the same checks plus eight complete PDF conversions,
  sequentially, with EPUBCheck, monotonic progress, pinned source identities, memory budgets
  and reviewed page-specific content contracts. All selected cached sources and EPUBCheck
  are required; missing data fails explicitly. The evaluator does not download anything.
- `tools/check_corpus_content.py --case <id> --evaluation <directory>`: run the content contract
  against an existing complete evaluation without reconverting. This is an additional content
  check, not a replacement for the evaluator's EPUB/resource checks.
- `tools/run_corpus_regressions.py --converter <CLI> --epubcheck <executable> --output <new-directory>`:
  run the corpus lane directly. Repeat `--case <id>` to narrow a debugging run; the summary
  lists omitted cases explicitly. A failing case does not hide subsequent results.

Fetch originals explicitly with `tools/fetch_corpus.py --case <id>`. Downloads are cached and
checksum-verified. Publisher-blocked downloads require an owner-supplied matching original;
see [corpus instructions](corpus.md). Large originals and output EPUBs remain gitignored.

## Current content coverage

[corpus/regressions.json](../corpus/regressions.json) has 77 targeted checks on 22 reviewed pages
across eight books: FAA, algebra, 9/11, The Fed Explained, Dietary Guidelines, Our Flag, the CDC
comic and Blue Book. All source-page anchors must also remain complete and ordered, and semantic
text must contain no image attachment placeholders.

The checks preserve selected correct words, paragraph/list order, license attribution, image
presence and explicit transcription/fallback warnings. They read the actual EPUB spine, track
page boundaries inside styled text, preserve ownership across chapter-file continuations, and
exclude navigation/captions from source-text matching. They do not freeze serialization details
or broken output such as interleaved columns and flattened exponents.

The checker has negative controls for deleted text, text moved to the wrong page, reversed order,
missing images, flattened or misplaced superscripts/subscripts, missing/wrong-page warnings, changed source identity, failed conversion, missing
or duplicate page markers, and captions masquerading as source text. A list of assertions without
such controls could silently pass despite a broken checker.

Image-presence checks are weaker than visual fidelity checks. They cannot prove a flag's colors,
a diagram's arrows or mathematical notation is correct. Unit pixel checks and source-image review
cover selected rendering behavior; robust visual/semantic contracts need expansion. The corpus
lane does not supply a whole-book quality score or physical-device performance qualification.

Full Warren and NOAA conversions remain explicitly excluded from this successful-conversion lane
because of the known image-output ceiling failure (#5). The pinned Warren excerpt separately
checks its two textless pages. These exclusions are listed in output, never counted as passes.
The manifest consistency test requires every corpus document to be covered or explicitly excluded.

## Adding or changing a regression

1. Reproduce the defect using a pinned source. Add a small original synthetic PDF/operator
   fixture when that isolates the mechanism, and retain a source-derived real-document target.
2. Read the source visually before writing expected text, order, cell values or image properties.
   Do not derive expected correctness from the converter being tested.
3. Prove the test fails on the old behavior. Keep known unresolved defects in the roadmap/issues,
   rather than blessing them as golden output or disguising them as passing tests.
4. Add positive controls for neighboring behaviors and another document type. For example,
   attachment filtering must retain mixed styled text, blank scans, recoverable OCR and images.
5. Run the synthetic and corpus lanes. Review changed content/image counts; increases and decreases
   can both be suspicious. Update expectations only after reviewing the source and explaining
   the intended behavior change. Preserve historical measurement receipts.

[Issue-fix measurements](../measurements/quality-and-raster-fixes/record.md) and the
[cross-corpus content run](../measurements/cross-corpus-regressions/record.md) document current evidence.

## Preserved-region fixtures

`PreservedRegionTests.swift` includes original in-memory PDFs and a small, attributed extraction
of algebra page 17. The JSON fixture contains source text and geometry, not the original PDF or
font programs. It runs offline on both platforms and checks whole-line crop containment, exercise
prefix ownership and selectable instructions. It is an internal test schema, not a public
intermediate-format contract. See [evidence and negative controls](../measurements/preserved-region-regressions/record.md).

The detached-fraction regression is enforced normally: its numerator, exponent and denominator
must share one image, surrounding prose stays selectable and the conversion reports image
preservation. The known-failure wrapper is removed. Ordinary rules, underlines, code, connected
table grids and nearby prose supply negative controls; algebra page 479 supplies source-derived
answer-key fraction checks. See [fraction and OCR-typography evidence](../measurements/fractions-and-invisible-text/record.md).
Future unresolved cases must stay explicit rather than becoming passing golden output.

To recapture the algebra geometry with full Xcode selected:

```sh
swiftc Sources/PDFReflowLib/NativeTextReader.swift Sources/PDFReflowLib/ConversionTypes.swift \
  Sources/PDFReflowLib/DocumentModel.swift Sources/PDFReflowLib/ReflowDocument.swift \
  Sources/PDFReflowLib/GraphicsReader.swift tools/capture-algebra-layout.swift \
  -o /tmp/capture-algebra-layout
/tmp/capture-algebra-layout corpus/cache/Beginning_and_Intermediate_Algebra.pdf /tmp/algebra-17-layout.json
```

The capture tool rejects any source checksum other than the pinned book. Review source and
geometry changes before replacing the bundled fixture; never regenerate it merely to make a test
pass. The extracted text remains Tyler Wallace's CC BY 3.0 material, with attribution in the
fixture and [third-party notices](third-party-notices.md).

## Source-derived fidelity controls

`FidelityIssueTests.swift` checks the FAA page-91/511 columns, all ten Our Flag page-27 table
pairs and both headers, and algebra page-343's inline exponent. Positive controls cover spanning
headings/figures, ordinary prose, dot-leader contents entries, code, ellipses and sparse numeric
rows. The 9/11 page-451 name/description fixture protects row associations from narrow-column
cuts. `BaselineStyleTests.swift` checks both native baseline-attribute keys, unchanged small
fonts and noisy positioning, a real PDF-to-EPUB superscript/subscript path, and CDC page-5 OCR
line spacing that must not become inline scripts.

These small JSONs capture native extraction from checksum-pinned sources, not converter output.
They run offline on macOS and iOS. Capture another page with full Xcode selected:

```sh
swiftc Sources/PDFReflowLib/NativeTextReader.swift Sources/PDFReflowLib/ConversionTypes.swift \
  Sources/PDFReflowLib/DocumentModel.swift Sources/PDFReflowLib/ReflowDocument.swift \
  Sources/PDFReflowLib/GraphicsReader.swift tools/capture-layout-fixture.swift \
  -o /tmp/capture-layout-fixture
/tmp/capture-layout-fixture faa-phak-8083-25c 91 /tmp/faa-91-layout.json
```

Run from the repository root. The tool verifies the cached PDF against the manifest SHA-256.
Source review, baseline failures, cross-document safeguards and full-run evidence are retained
in [the three-fix measurement](../measurements/three-fidelity-fixes/record.md). The suite contains
65 Swift tests with no known-issue wrappers, and 49 Python tests.

`InvisibleTextTests.swift` covers exclusively hidden OCR text, visible Courier and genuine
font-size headings, mixed text modes, saved graphics state, nested forms and malformed modes.
Warren pages 50/910 supply pinned source geometry; ordinary prose/index entries must not become
code/headings, while source points 10/11 retain list formatting. The nine-page real Warren excerpt
is evaluated separately because the full 920-page conversion remains outside the successful
complete-conversion gate. A passing excerpt does not qualify the complete book.
