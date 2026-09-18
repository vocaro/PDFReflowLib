# Endnote investigation: marker coverage retained, paragraph prototype rejected

Historical record: the runtime rejection below predates the resolution of #26.
The [compatible-environment recheck](recheck/record.md) now supports a bounded paragraph repair.
The original evidence and rejected files remain intact; #11 still has unresolved note semantics.

Issue [#11](https://github.com/vocaro/PDFReflowLib/issues/11) remains open. The retained change
adds a native-source test and a full-book corpus assertion for the raised reference **4** after
`7:45.` on physical page 20 of the 9/11 report. This already works in baseline `0eba8d4` through
the existing baseline-offset repair. No conversion runtime, default, model or API change is
retained. Note paragraph ownership, chapter-scoped links and return navigation remain unresolved.

## Source evidence and rejected proposal

The checksum-pinned source is `gpo-911-2004`, 585 pages, SHA-256
`657d41475eb3a9a5e3e87a6c7c51ac1dfbe1af7566d1abff7bf7286e7e1c0e1b`.
Physical pages 20, 472 and 473 were rendered with Poppler and visually reviewed. Page 20's
marker is visibly raised; its attributed run has font size 7.175 and baseline offset 2.2558.
Page 472 has indented note starts 38–54 with dedented continuations. Several markers omit
following whitespace (`40.The`, `41.FAA`). Page 473 includes a second indented paragraph
inside note 66, which is outside the proposed single-paragraph pattern.

The existing layout emits whitespace-followed numbered starts as standalone preformatted
blocks and splits other first-line indents into ordinary paragraphs. The candidate required a
native top-margin `NOTES TO CHAPTER` heading, at least three consecutive aligned note numbers,
matching typography and consistent dedented continuations. Images, tags, OCR/synthetic styles,
monospace, numbering gaps and conflicting geometry refused the page. It emitted one ordinary
paragraph per supported note and preserved inline styles, without adding reference links.

`before-tests.log.gz` records the original runtime failing all 17 note-start cases on page 472;
the marker test already passes. `before-content.json.gz` separately records failed paragraph
assertions for notes 38/39 and note 40's first-line continuation. Those assertions are **not**
in the retained passing corpus contract. `rejected-tests.swift` preserves the proposed tests
outside the active target. It is experiment evidence, not an expected-failure wrapper.

## Why the runtime was reverted

The initial candidate passed 167 Swift tests on macOS and iOS 27 Simulator, 77 Python tests,
the fixture/policy/concurrency/index checks and eight complete corpus conversions with EPUBCheck,
progress/resource gates and 231 content checks. That was insufficient to accept the change:
a stricter comparison found differences outside the intended note pages.

| Document | Changed parsed pages | Changed image bytes |
| --- | --- | --- |
| 9/11 report | 48 endnote pages | 0 of 331 |
| CDC comic | 13, 15, 16, 17, 36 | 36 of 42 |
| Dietary Guidelines | none | 1 of 27 |
| FAA handbook | none | 1 of 588 |
| The Fed Explained | 7 | 5 of 315 |
| Our Flag | 1 | 0 of 147 |
| Algebra and Blue Book | none | 0 of 2,472 |

All image inventories and page anchors remain identical. The differing PNGs include actual
RGB pixel changes, not just timestamps or compression metadata. The sampled CDC first image
has mean absolute channel differences of approximately 0.37/0.36/0.64 on a 0–255 scale; the
DGA third image has approximately 0.40/0.21/0.29. These small averages do not prove equivalent
appearance or OCR quality. No global content/image identity claim is made.

The 9/11 comparison preserves every page's text/order when ignoring whitespace and hard/soft
hyphens, all inline script values/order, heading text and image bytes. It mechanically matches
711 candidate note paragraphs against consecutive native source lines. A text-only ownership
check for note 5 on page 532 remains ambiguous because a dedented continuation also starts
`5.This`; the prototype used indentation to distinguish them. These counts are neither a
full visual review nor proof of reference ownership. `changed-pages.json.gz` retains this
checker limitation explicitly instead of silently counting it as a pass.

Bounded controls investigated the unrelated differences:

1. Repeating the **same original binary** for CDC/DGA produces identical baseline text and
   images. Its hash matches the retained chapter-boundary build; that commit's runtime sources
   match `0eba8d4`.
2. A fresh build of exact `0eba8d4` agrees with those original CDC/DGA outputs.
3. A clean candidate build agrees with the candidate outputs, including their differences.
4. A refinement moves note-heading detection after all extraction/OCR, leaves `PageContent`
   and the extraction loop unchanged, and uses Swift token parsing for the heading. Its CDC/DGA
   outputs still agree with the candidate and differ from the baseline.

The cause is unresolved; these controls do **not** establish nondeterminism. The runtime was
reverted rather than expanding this issue into raster/OCR diagnosis. The separate problem is
tracked in [#26](https://github.com/vocaro/PDFReflowLib/issues/26). `rejected-runtime.patch`
contains the final refinement, not an accepted fix; the full candidate gate predates that
refinement. No experiment changed `PageRasterizer.swift` or `OCRReader.swift`.

## Retained validation

After reverting all runtime and note-paragraph contract changes:

- 161 Swift tests pass on macOS and iOS 27 Simulator, including the new native marker test.
- 77 Python tests pass, including existing flattened/wrong-context script rejection controls.
- The retained 9/11 contract passes 31 checks on its complete baseline EPUB, including marker 4
  with preceding and following source context. The eight-book default baseline had already
  passed all conversion, EPUBCheck, progress and configured Mac memory gates.

The full candidate logs are explicitly separate from `retained-*` logs. Warren and NOAA remain
excluded from the default successful-conversion corpus for their known output ceiling. Simulator
results do not establish physical-device budgets. The rejected prototype does not resolve #11.

## Evidence and reproduction

`comparison-summary.json` records complete-book EPUB hashes, changed pages and image identities.
`control-comparison.json` records repeated-baseline, clean-baseline, clean-candidate and refined-
candidate comparisons. Per-case directories retain compressed results, reports, content assessments and EPUBCheck
receipts for the baseline, candidate and controls. Their raw progress logs and memory-sample
series were dropped in #196; each case's `result.json.gz` keeps their summary (progress-check events and result, sampled
and converter peak memory). `source-layouts.json.gz` contains
native extraction evidence for the 48 changed 9/11 pages; these are government-report excerpts,
not newly authored library text. Originals and complete EPUBs stay in the ignored cache/build
directories. `identity.json` pins the collector, rejected refinement/tests and retained contract.

Run the retained checks normally with `swift test` and the complete 9/11 corpus contract. To
study the rejected prototype, use a separate checkout of `0eba8d4`, apply `rejected-runtime.patch`
and copy `rejected-tests.swift` into its test target. Do not apply it over the retained marker
test without removing the duplicate test function. Run `scripts/check-all.sh --corpus` and compare
complete outputs, not just the passing spot checks. Build `tools/capture-layout-fixture.swift`
as documented in `doc/regression-testing.md`; then `collect.py --help` lists the required baseline,
candidate, source-capture and output locations. Pass repeated `--control name=directory` flags
to retain the bounded build/repeat controls. The collector reports unexplained differences;
its completion is not an acceptance gate for the prototype.
