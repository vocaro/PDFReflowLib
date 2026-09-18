# Local running-header regressions

The converter removes chapter-local and alternating running headers without requiring repetition
on half the book. The inspected 9/11 running headers on physical pages 20, 21, 67 and 472 disappear;
chapter-title lines on pages 19 and 65 remain headings. This addresses the reproduced margin-text
part of [#10](https://github.com/vocaro/PDFReflowLib/issues/10), not general heading precision,
timeline label ownership or endnote reconstruction.

## Identity and scope

The run uses the macOS 27 arm64 release CLI, library defaults, and the eight complete pinned
corpus PDFs (2,151 pages). `identity.json` records the base revision, exact working-tree source,
test and fixture hashes, system and Xcode versions. Each case's compressed evaluator receipt
records the converter hash, input identity, resource measurements, progress and EPUB validation;
the raw progress logs and memory-sample series behind it were dropped in #196.
The comparison baseline is the retained default-policy corpus run documented in
[client-options](../client-options/record.md), not a newly timed old-build run. Timings are
observations, not a controlled performance comparison.

## Regression evidence

- The new EPUB assertions reject the old 9/11 output at all four reviewed running-header targets.
  `before-content.json.gz` retains those failures; genuine chapter-heading controls pass.
- The initial five header tests fail against the original detector (`before-tests.log.gz`).
  The current suite adds folio, client-option and source-layout controls; that initial log is
  not claimed to contain the final test suite.
- Twenty-one 9/11 extraction fixtures cover pages 19–26, 65–71 and 471–476. They require every
  non-header source line to survive and retain the two chapter openings. Captures come from
  the checksum-verifying `tools/capture-layout-fixture.swift`, independently of reconstruction.
- Six FAA source fixtures cover pages 363–365 and 437–439. They protect shifted numeric folios
  and changed page sizes while retaining every other source line. `shifted-folio-before.log.gz`
  shows this safeguard failing before the folio-specific tolerance change.
- Synthetic controls retain adjacent prose, captions, genuine body titles, isolated page content,
  sparse repetition, distinct typography and drifting textual headings. They cover alternating
  headers, chapter-local runs, physical-page offsets, fallback font estimates and client opt-out.
- The full-output comparison exposed an intermediate regression in Our Flag's illustrated-entry
  order after widening the footer band. The source-reviewed page-34/42/43 contracts accept the
  original order and reject that intermediate output (`flag-original-content.json.gz` and
  `flag-intermediate-content.json.gz`). The footer band remains at the existing 7%; only the top
  band widens to 10%. Wider footer removal needs separate layout work.

The Blue Book comparison also exposes reintroduced scan-border artifacts when synthetic text
uses the new native-typography rule. Its page-12 contract rejects that intermediate output and
accepts the established baseline (`blue-intermediate-content.json.gz`, `blue-original-content.json.gz`).
Synthetic layers retain the previous repeated-margin cleanup; two source-layout fixtures protect
that behavior. This does not remove every OCR artifact or verify transcription.

The corpus contains 119 selected assertions on 31 pages. New `absentText` and `headings` checks
have negative controls for reintroduced furniture, prose posing as headings, wrong-page headings
and empty expectations. Header parsing preserves inline styles and source-page boundaries.
These assertions are bounded regression contracts, not a whole-book fidelity score.

## Complete-book comparison

| Corpus group | Pages with semantic-text differences | Heading elements before → after |
| --- | ---: | ---: |
| 9/11 report | 531 | 191 → 87 |
| The Fed Explained | 115 | 260 → 240 |
| FAA, algebra, DGA, Our Flag, CDC comic, Blue Book | 0 | Unchanged |

All 3,922 image files match the baseline byte-for-byte as multisets. All eight complete
conversions pass EPUBCheck, ordered page-anchor/progress checks, configured memory gates and
119 content assertions. The Mac and iOS simulator suites each pass 82 Swift tests; 55 Python
tests pass. Runtime options and their defaults remain unchanged.

See `comparison-summary.json` for image-byte equality, semantic-text changes, heading counts and
reflow-page counts. `corpus-differences.json.gz` retains all page-level token differences, and
`reviewed-pages.json` preserves selected before/after 9/11 text, headings, script context and assets.
Image comparisons use SHA-256 multisets of uncompressed image file bytes, including duplicates; image counts
alone cannot establish byte equality.

Running-header removal permits existing cross-page paragraph and hyphen joining. Differences in
whitespace and hyphens are therefore expected beside the removed margin text. On some pages the
running header was the only selectable text outside a preserved image; removing it lowers the
reported reflowed-page count without removing the body image. Heading-count reductions are not
an independently annotated precision score.

## Validation and reproduction

`release-gate.log.gz` records Swift and Python tests, six default fixture conversions, four CLI
policy combinations, ten rejection/cleanup cases, and the complete eight-document corpus gate.
`release-ios-tests.log.gz` records the iOS 27 simulator suite. The simulator does not qualify
physical-device performance. Full Warren and NOAA remain explicitly excluded from this default
corpus lane; this change does not resolve the PDFKit leak or qualify their resource budgets.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer scripts/check-all.sh --corpus
```

For the retained before/after evaluator directories, regenerate this evidence with:

```sh
python3 measurements/local-header-regressions/collect.py \
  --before /path/to/baseline/corpus --after /path/to/current/corpus \
  --logs /path/to/run-logs --output /path/to/new-evidence
```

The collector requires successful corpus receipts, identical source-page sequences, identical
image bytes and unchanged semantic text in the six books outside the native-header improvement. Originals remain in the checksum-verified ignored cache. Source page renders were
reviewed locally; no additional full PDFs or EPUBs are committed.

Multi-line headers, runs shorter than three nearby occurrences, unusual margins, OCR header
corruption, general tag consumption and graphic-label ownership remain unqualified. Clients can
retain all margin text through `removeRepeatedHeadersAndFooters = false`.
