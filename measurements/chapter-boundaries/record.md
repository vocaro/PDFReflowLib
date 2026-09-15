# Validated numbered chapters start EPUB spine documents

Bounded implementation under [#15](https://github.com/vocaro/PDFReflowLib/issues/15), baseline
`2ea9065`, 2026-09-15, macOS 27 / Xcode 27, arm64. **Issue #15 remains open.** This adds chapter
file boundaries; whole-document extraction/reconstruction memory and oversized atomic blocks
are unchanged. The supported scheme is **English `Chapter 1...N`, consecutive Arabic numbers,
and root-level bookmarks**, with a matching native source title at each admitted destination.

## Source evidence and supported rule

The checksum-pinned 1,834-page NOAA report supplies 32 root-level numbered chapters. Physical
pages 33, 80, 139 and 1619 were visually reviewed: the chapter number and full title occupy
the top of each chapter cover, above artwork. Page 33 is landscape. The source titles are
“Overview: Understanding Risks, Impacts, and Responses,” “Climate Trends,” “Earth Systems
Processes,” and “Mitigation.” Four captured native-layout fixtures retain source identity,
geometry, attributed text and rights provenance; expectations derive from the source.

`noaa-source.json` records all 32 bookmark destinations and adjacent native title lines.
Every candidate matches the rule; the other eight corpus books produce no admitted root
chapter sequence. Their source diagnostics are retained as fallback controls. Visual review
is sampled, not a claim to have visually adjudicated all 32 covers or all chapter content.

The reader supports at least two root-level bookmarks named `Chapter 1 <title>` through
`Chapter N <title>` with consecutive Arabic numbers and strictly increasing local destination
pages. Direct, named and local GoTo destinations resolve through PDFKit. Invalid, remote,
duplicate and backward chapter destinations reject the sequence. Root traversal is capped at
10,000 entries and checks cancellation per entry. Nested, Roman-numbered, unnumbered and
other-language outlines retain ordinary byte-based packing.

Each candidate must independently match complete adjacent native lines among the first six
lines in the destination page's upper half. Matching normalizes case and whitespace, accepts
wrapped titles and a publication-name prefix before the chapter number, and requires both
number and full title. Fresh OCR and exclusively invisible image-backed text are ineligible.
This does not detect every inherited OCR layer or interpret arbitrary bookmarks.

## Implementation and controls

The logical document stores validated physical chapter-start pages. Reconstruction prevents
paragraph continuation across those boundaries and retains a standalone source-page marker.
The writer finishes preceding content before each such marker, then uses its existing
60,000-byte UTF-8 body target for subdivisions. Headings, inline styles, images and page anchors
keep their source order. Existing heading/page navigation targets the new filenames; bookmarks
do not create headings or new note/link semantics. Final/entry byte ceilings are unchanged.

Eight Swift tests cover local/direct/named/GoTo and rejected remote/missing/nested/duplicate/
backward destinations, source title/number mismatch, OCR, lower-page and prose false positives,
wrapped titles, invalid model boundaries, public PDF conversion, normal byte subdivisions,
exact-size/empty-page handling, and navigation. The two new public/writer integration tests
fail when the writer uses its previous byte-only behavior; `baseline-failures.log.gz` retains
the failed run. Three independent comparison-tool tests reject missing chapter splits,
changed text/images and broken navigation.

## Results

All **160 Swift tests pass on macOS and iOS 27 Simulator** (iPhone 18 Pro). All 77 Python
tool tests and three measurement-tool tests pass, as do the fixture/policy conversions,
rejection/cleanup and native-concurrency checks. The structure index peaks at 119,881,728
bytes RSS, below its unchanged 192 MiB ceiling. All eight complete corpus conversions pass
EPUBCheck, existing memory limits, progress and 221 content checks on 54 reviewed pages.
The independent before/after comparison retains every source page's text, inline styles,
block semantics, navigation destinations, warnings and all 3,922 images over 2,151 pages.

The complete **1,834-page NOAA output passes EPUBCheck** and the independent ZIP/XML/link/
navigation/spine-packing checks. All 32 chapter covers start spine documents; the retained
81-file baseline misses all 32 starts. The new output has **96 spine documents**, including
byte-size subdivisions inside large chapters; the largest body is **59,998 bytes**. Complete
concatenated body markup and page semantics remain identical, as do all **11,245 image files**,
all 4,918 warnings and the identities/text of existing navigation targets.

| Full NOAA PNG policy measurement | Result |
| --- | ---: |
| Final EPUB bytes | 1,466,261,501 |
| Uncompressed entry bytes | 1,516,411,937 |
| Converter seconds | 216.41 |
| Peak converter RSS bytes | 974,536,704 |
| Sampled peak physical footprint bytes | 450,758,240 |
| Monotonic CLI progress events, ending in completion | 15,348 |

This is one fresh Mac converter process with the established explicit 4 GiB storage policy;
no NOAA RSS ceiling is configured. RSS and sampled physical footprint are different metrics
and exclude separate Apple services. The retained PNG baseline took 131.74 seconds with
1,038,221,312 bytes RSS and 393,397,784 sampled footprint. The new run took longer and had
higher sampled footprint; it does not establish a memory or performance improvement. Timing
excludes validation; these observations are not a distribution or physical-device budget.

The retained full NOAA baseline was produced at `193f807` with the same runtime as the
starting `2ea9065` commit; the intervening NOAA-policy/large-inspector changes were measurement
and tooling work. The standard corpus comparison uses that same retained runtime baseline.

The existing public-API cancellation probe, linked against the new release library, extracts
and reconstructs every NOAA page before cancelling at the writing handoff. It throws
`CancellationError`, publishes no EPUB and leaves its output/staging directory empty.
Its JPEG 0.90 full-page policy and 4 GiB entry/final caps match the earlier cancellation
measurement; this verifies cleanup/completion semantics, not a device-latency guarantee.
Writer unit coverage additionally cancels during serialization, after input-block progress.

`results.json` records effective policies and source/executable/code identities; `receipts.tar.gz`
retains the complete corpus assessments and full NOAA evaluator logs, progress, memory samples
and validation output. Compressed local logs retain the baseline failure, platform gates and
full-source cancellation. Output EPUBs remain in ignored build/evaluation directories.

## Reproduction

```sh
scripts/check-all.sh --corpus
swiftc Sources/PDFReflowLib/ChapterBoundaryReader.swift Sources/PDFReflowLib/NativeTextReader.swift \
  Sources/PDFReflowLib/PDFPageSource.swift Sources/PDFReflowLib/DocumentModel.swift \
  Sources/PDFReflowLib/ReflowDocument.swift Sources/PDFReflowLib/ConversionTypes.swift \
  tools/inspect-chapter-boundaries.swift -o /tmp/inspect-chapter-boundaries
/tmp/inspect-chapter-boundaries noaa-nca5-2023
python3 tools/evaluate-real-document.py --case noaa-nca5-2023 \
  --pdf corpus/cache/noaa_61592_DS1.pdf --converter measurements/chapter-boundaries/noaa.sh \
  --epubcheck /opt/homebrew/bin/epubcheck --output /tmp/noaa-chapters
python3 measurements/chapter-boundaries/compare.py \
  .build/noaa-policy-review/full/png/noaa-nca5-2023.epub \
  /tmp/noaa-chapters/noaa-nca5-2023.epub --noaa
python3 -m unittest discover -s measurements/chapter-boundaries -p 'test_*.py' -v
```

The NOAA launcher uses the existing explicit 4 GiB entry/final caps, automatic references,
PNG full-page/cropped images, 180 DPI and otherwise unchanged defaults, matching the retained
full PNG baseline. The evaluator identifies a launcher rather than its effective CLI options;
the final evidence records those effective flags and executable identity separately. These
are experimental storage allowances, not device-memory budgets or changed recommendations.

## Remaining work

Broader bookmark schemes and hierarchy, subdivision of oversized atomic blocks, bounded
reconstruction, cross-chapter note/link reconstruction, and physical iPhone/iPad qualification
remain open. The default NOAA image-budget failure under #5 remains. Source-text equality
and valid file navigation do not establish whole-book fidelity or a memory improvement.
