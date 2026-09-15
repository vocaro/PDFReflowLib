# Issue #11: bounded numbered paragraphs accepted after compatible-environment recheck

This work starts from clean main `b82dbe7` and re-evaluates the
[retained prototype and evidence](../record.md) after #26 established that the historical
CDC/DGA drift followed execution environment. The live issue body and comment were read.
Issue #11 remains open: this is a page-local paragraph repair, not complete endnote semantics.

## Source and implementation

The pinned 585-page 9/11 report has SHA-256
`657d41475eb3a9a5e3e87a6c7c51ac1dfbe1af7566d1abff7bf7286e7e1c0e1b`.
Physical pages 472, 473 and 532 were rendered with Poppler and visually reviewed again.
Page 472 has indented starts 38–54 and dedented wrapped lines; page 473 has a distinct
second paragraph within note 66. Page 532's indented note 5 is separate from the dedented
`5.This` inside note 9: the latter continues the phrase “in chapter 5.”

The runtime restores the refined prototype with an additional conservative image barrier:
any image element refuses note grouping for the page, including images before the first note.
It requires native text, a top-margin `NOTES TO CHAPTER N` heading, at least three consecutive
aligned note starts, matching typography, close line spacing, and consistent dedented
continuations. The heading evidence is retained before furniture removal, after extraction/OCR.
Accepted lines join through the existing styled-text/hyphen policy into ordinary paragraphs.
There is no public API, reference-link, raster, OCR, or output-policy change.

The source-derived page-472 test fails on all 17 starts in main; the current corpus contract
fails five paragraph assertions against the complete baseline EPUB. The new source fixture
for page 532 is the retained native extraction, with its source identity and provenance intact.
Its test compares all lines of notes 3–13 using source geometry and explicitly rejects
transferring the dedented `5.This` text to note 5.

Nine added Swift tests cover the source note paragraphs, styles, citation-year continuations,
images before/inside notes, tagged text, OCR/synthetic fonts, missing/low headings, short or
gapped number sequences, conflicting geometry, repeated numbering under different chapter
headings, public header-removal options, and page anchors. Page 473 is refused because of
its extra indented paragraph; a text/order conservation test preserves that paragraph and
the 54/55 page transition. A synthetic case exercises the existing lowercase cross-page
continuation heuristic and verifies that the next numbered note is kept separate.

## Complete corpus comparison

Fresh sequential baseline and candidate evaluations ran on the host with the same executable
capability probe immediately before each conversion. All sixteen conversion/resource/progress/
EPUBCheck/capability receipts pass. Each pair passes the current comparison tool's provenance
and artifact-identity checks; no context label is used as a substitute for measured capability.

- Baseline converter: `3698a8220cde5b578ccc5d9a5dc94a023d500351872d6f38cc06ae8897a7a2f5`
- Candidate converter: `873b740697a1b000d194677cdbc2d0e48cad9d6d759eeac5ca3b6f3d67ca026c`
- Shared probe: `91fe500a1eec1f1e5c361f1191e8d2fe4131b7ad46907cac67a097a17b4f73d1`

| Scope | Result |
| --- | --- |
| FAA, algebra, Fed, DGA, Our Flag, CDC, Blue Book | Exact normalized pages, page markers, image bytes and reports agree |
| 9/11 report | Exactly 48 numbered-note pages change; 537 other pages agree |
| All 3,922 corpus image assets | Encoded bytes agree |
| 9/11 content and navigation anchors | All page text/order survives established whitespace/hyphen normalization; all heading text, inline script values/order and page markers agree |
| Number/text ownership audit | 712 page-local numbered paragraphs match their complete consecutive native source-line spans |
| Reports | All report fields agree, excluding output paths |

The geometry-aware audit resolves the earlier text-only checker ambiguity on page 532.
The 712 count includes page-local fragments of notes that continue elsewhere; it is not a
count of fully reconstructed endnotes or matched references. The strict comparator correctly
reports `passed: false` for 9/11 because intended paragraph records differ; the separate
source audit verifies those changes without weakening the comparator.

The initial candidate corpus summary reported two failures caused by newly written expectation
errors: “Bureau” instead of source “FBI,” and spacing across `24,2003);Linda`. They were corrected
against the visually reviewed source/native capture. All eight current contracts were then
reassessed against the same complete, successful conversion artifacts: **232 checks pass**,
including **41** on 9/11. Original per-run content assessments are preserved, including those
two failures; `final-content-assessment.json.gz`, `content-assessments.json` and `summary.json`
record the final assessments. No converter or source changed between those assessments.

## Validation

- 170 Swift tests pass on macOS and iOS 27 Simulator.
- 102 Python tests pass.
- `scripts/check-all.sh --fast` passes the release build, native-process concurrency checks,
  six fixture conversions, eight policy conversions and twelve rejection/cleanup cases.
- The isolated structure-index memory gate passes at 119,750,656 bytes (192 MiB ceiling).
- All eight full candidate conversions pass their existing memory ceilings; 9/11 peaks at
  131,596,288 bytes. These are local process measurements, not physical-device budgets.
- `git diff --check` passes.

Warren and NOAA retain their existing default-budget full-conversion exclusions. Their
absence is not counted as a pass. No broad document-fidelity or image-legibility claim is made.

## Remaining issue scope

The detector deliberately refuses multi-paragraph pages such as 473. It does not assign a
durable note identity across paragraphs or pages. The numeric-leading continuation of note 54
on page 473 remains separate; its text and page provenance survive. The existing lowercase
cross-page join remains heuristic. Chapter-scoped reference association, multiple-reference
relationships, links to notes and return navigation are unimplemented. The existing superscript
4 after `7:45.` remains protected by the native test and full-book contextual assertion.

## Reproduction and retained artifacts

Large PDFs/EPUBs and binaries remain ignored under the corpus cache and
`.build/numbered-notes-recheck`. The collector preserves compressed receipts, probes, progress,
memory samples, EPUBCheck results and test logs here, without replacing historical evidence.
`identity.json` binds the implementation, new fixture, contract, collector and converter hashes.
The source audit reuses `../source-layouts.json.gz` for the 48 admitted pages.

From clean main, save its release executable before applying the repair. For each binary run:

```sh
python3 tools/run_corpus_regressions.py --converter <saved-converter> \
  --epubcheck /opt/homebrew/bin/epubcheck \
  --output .build/numbered-notes-recheck/<baseline-or-candidate> \
  --environment-probe .build/raster-drift-investigation/probe-v1 --execution-context host
```

Use the exact same compiled probe for both sides; see
[the capability procedure](../../../doc/corpus.md#comparing-conversion-runs).
The directories must be new, and both processes must run in compatible measured host conditions.
Afterward, run `python3 measurements/numbered-notes/recheck/collect.py`.
It refuses incompatible receipts, any control drift, image/report drift, lost source text/scripts,
and mismatched source-line ownership; it independently re-runs all current content contracts.
