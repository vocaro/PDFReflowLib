# Predictable EPUB spine packing

The EPUB writer packs complete serialized blocks before crossing its 60,000-byte body target,
counts UTF-8/XML expansion and wrappers, and writes each completed document in one pass.
A standalone source-page marker travels with the following content. Oversized atomic blocks
occupy their own document, preserving text, inline styles and interior source boundaries.
This resolves a bounded part of #15; it does not implement semantic chapter boundaries or
memory-bounded PDF reconstruction.

## Evidence

Measured on macOS 27.0 (26A428), arm64, Xcode 27.0 (27A266a), release CLI, default conversion
options. `identity.json` pins source, test, tool and corpus identities against base `294d0cd`.
The comparison baseline is the retained complete corpus output from
[the heading measurement](../heading-body-regressions/record.md), not a fresh timing run of the
old writer. No timing or peak-memory improvement is inferred from this comparison.

| Complete PDF | Spine documents before → after | Largest serialized body before → after (bytes) |
| --- | --- | --- |
| FAA handbook | 30 → 31 | 63,816 → 60,000 |
| Wallace algebra | 12 → 14 | 77,152 → 59,997 |
| 9/11 report | 26 → 27 | 64,300 → 59,977 |
| The Fed Explained | 5 → 5 | 63,657 → 60,000 |
| Dietary Guidelines | 1 → 1 | 21,617 → 21,617 |
| Our Flag | 2 → 2 | 64,421 → 59,943 |
| CDC comic | 1 → 1 | 31,318 → 31,318 |
| Blue Book | 15 → 18 | 78,706 → 60,000 |

The original 92 spine documents include 84 multi-block target overshoots. The new 99 have none;
no corpus block requires the oversized-atomic exception in this run. Across all eight books,
parsed source pages are exactly equal: normalized text, paragraph/heading groups, inline-script
observations, image references and order. All 3,922 image files have identical bytes and page
ownership/order. The independent checker resolves every heading/page navigation target after
repacking. `comparison-summary.json` retains per-document violations in the original output,
counts, limits, EPUB hashes and passing content/image comparisons.

## Regression gates

- 95 Swift tests pass on macOS and iOS 27 Simulator (iPhone 18 Pro), including six new writer tests.
- 61 Python tests pass, including four new size-contract rejection controls.
- Six fixture conversions, four client-policy conversions and ten rejection/cleanup cases pass.
- All eight complete corpus conversions pass EPUBCheck, navigation/size rules, monotonic progress,
  source anchors, configured memory gates and 145 content assertions across 40 reviewed pages.

The new Swift controls cover exact size boundaries, markup overhead from thousands of tiny
paragraphs, escaped Unicode, oversized indivisible paragraphs, page/heading links after splitting,
inline style/page markers, trailing empty pages, model immutability, progress and cancellation.
The Python checker counts the original serialized bytes, not XML reserialization. Negative
controls reject multi-block overflow, extra page markers around an oversized block, unwrapped
body text and unexpected oversized elements. These checks run for every corpus/fixture EPUB.

`before-tests.log.gz` records four original packing/navigation failures, the newly required
initial progress update, and the passing trailing-page control. Large Unicode comparisons are
retained verbatim in the compressed log. `progress-handoff-failure.log.gz` records an existing
public progress test rejecting the initial implementation: rounding allowed reconstruction's
last fraction to slightly exceed 0.82 before writing started at 0.82. Clamping reconstruction to
its allocated endpoint fixes the handoff; the final suite passes that original test.

## Implementation boundaries

`EPUBWriter` keeps one current body string and compact filename/navigation lists, rather than
prebuilding chapter block arrays and serializing every payload twice. It still receives the full
logical model. Serialization progress counts processed input blocks, then metadata and archive
entries; cancellation checks remain at block/write/archive boundaries. The final publication
and cleanup remain the converter's responsibility.

The 60,000-byte value is an internal soft **body-markup target**, not a final file-size cap: XHTML
metadata wrappers are additional, and a single oversized paragraph, heading, preformatted block
or figure remains intact. Its optional preceding source-page marker stays with it. This preserves
paragraph semantics and Unicode rather than inserting arbitrary text breaks. Existing total-entry
and final-EPUB budgets still apply. No API, dependency, image policy or storage-budget default changes.

## Reproduction and receipts

With checksum-verified corpus caches and full Xcode:

```sh
PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer scripts/check-all.sh --corpus

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -scheme PDFReflowLib-Package \
  -destination 'platform=iOS Simulator,id=C4966BA9-56CD-4F21-9829-68567AAE8E6F' \
  -derivedDataPath /tmp/pdfreflow-spine-ios CODE_SIGNING_ALLOWED=NO

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 \
  measurements/spine-packing/collect.py --before /path/to/baseline/corpus \
  --after /path/to/new-gate/corpus --logs /path/to/spine-test-logs --output /path/to/evidence
```

The Simulator identifier is host-specific. The collector requires eight passing evaluations,
unchanged per-page semantics and image bytes/order, valid new packing, and resolved navigation.
The permanent test gates do not require the old EPUBs. Per-case compressed receipts retain
conversion/content results and EPUBCheck; final macOS/Python/corpus and iOS logs are retained
separately. The raw progress logs and memory-sample series were dropped in #196;
each case's `result.json.gz` keeps their summary (progress-check events and result, sampled
and converter peak memory).

Full Warren and NOAA remain explicitly excluded from the default successful-conversion corpus
lane because of the image-output ceiling. Chapter-bookmark validation, safe subdivision within
oversized blocks, bounded extraction/reconstruction and physical-device qualification remain open
under #15 and related issues. This work does not resolve the PDFKit leak.
