# Bounded paragraph and heading tags

PDFReflowLib consumes validated P and H1–H6 structure groups, retains heading levels in the
neutral model, and applies logical order inside uninterrupted runs of fully associated text.
This is the first phase of [#17](https://github.com/vocaro/PDFReflowLib/issues/17), not full
PDF structure reconstruction. Tables, figures/alternate text, links, generic H roles, Form text,
OCR semantics and arbitrary authoring defects remain outside this phase.

## Evidence and controls

Our Flag physical page 29 has two printed title lines in one H3 element: object 2403, MCID 0,
page object 103. The drawing stream labels it P, so drawing-stream names alone give the wrong
role. The unchanged decoded stream and independently captured native text/geometry are in
`Tests/PDFReflowLibTests/fixtures/our-flag-page-29-{tags,layout}.json`, with the original checksum.
The offline test wraps the stream in a minimal resource/structure dictionary; placeholder fonts
are not extraction evidence. Its spatial control produces two headings; validated association
produces one H3, “How to Obtain a Flag Flown Over the Capitol.” The complete original also runs
through the corpus gate, preserving its actual image resources.

Visual review of FAA physical pages 50, 191 and 325 confirms left-column content precedes the
right-column continuation. The baseline interleaves those columns. On page 191 each source item
remains a separate paragraph; this does not qualify semantic lists. FAA page 81 protects a figure
caption before the following prose. The Fed Explained cover uses one source H1 (object 4417)
for title/subtitle and P for the publication label. Existing Fed paragraph/heading/figure checks
remain controls. Our Flag page 30 confirms the line-ending flag-/pole join; FAA page 325 confirms
low-/level. Both use the existing vocabulary-based hyphen policy.

The initial unrestricted tag-order attempt moved FAA captions away from their figures and
promoted Our Flag's long Creed passage to a heading. It is rejected. The final implementation
keeps recognizable captions, list-like lines and heading groups of 200 or more characters in
spatial reconstruction. Images, unmapped lines, and incomplete groups form ordering barriers.
Generic semantic correctness cannot be inferred from syntactically valid tags.

Synthetic tests distinguish logical order from geometry and tree roles from font sizes/BDC
names. They cover Marked=false, RoleMap, inherited pages, MCR, ParentTree number-tree Kids,
named properties, wrong owners/pages, duplicate references and paint IDs, cycles, depth bounds,
empty page trees, cancellation, unknown text cursor advancement, unbalanced content, Form
namespaces, unmarked overlap, incomplete groups, captions/lists and heading serialization.

## Verification

Default-policy release CLI, macOS 27 arm64 / Xcode 27; exact source, fixture, tool and toolchain
identities are in `identity.json`. The comparison baseline is retained build `a9d8fd5`.

- 137 Swift tests pass on macOS and iOS 27 Simulator (iPhone 18 Pro).
- 62 Python tests, six fixture conversions, four policy conversions and ten rejection/cleanup
  cases pass.
- Eight complete PDFs, totaling 2,151 pages, pass EPUBCheck, navigation/progress checks and
  existing per-document memory gates.
- 221 content checks across 54 source-reviewed pages pass. Sixteen checks fail against the
  baseline output; `before-content.json` records those failures.
- All 3,922 image files and their page ownership are identical to the baseline. All
  superscript/subscript content is retained.
- FAA changes affect grouping on 47 pages; actual text-order changes are confined to reviewed
  pages 50/191/325. Our Flag grouping/heading changes affect 11 pages; the Fed cover changes one.
  The other five complete books have identical parsed text, paragraphs, headings and scripts.
  The only word edits are the reviewed low-/level and flag-/pole joins.

`collect.py` enforces the complete comparison and regenerates the per-book receipts, source
contract results and identity record. It rejects unreviewed word/order changes and image/script
loss. These checks establish bounded improvements and content preservation, not visual approval
of every paragraph. Full Warren and NOAA default conversions remain explicit exclusions under
#5; physical iPhone/iPad performance remains unqualified.

One preliminary concurrent synthetic run raised a PDFKit `NSInvalidArgumentException` from
`PDFSelection.createAttributedStringForCGSelection:scaled:` with an NSFont=nil diagnostic
(`test3.log.gz`). Its cause is unconfirmed and tracked in [#21](https://github.com/vocaro/PDFReflowLib/issues/21). Parser unit tests now use independent geometry and
Core Graphics; complete corpus runs still exercise native PDFKit extraction. This is not a fix
or a claim of resolution for a framework crash or the separate attributed-text leak.

## Memory

The rejected eager parser loads all sparse ParentTree arrays into one Core Graphics document.
On the pinned FAA PDF its standalone fresh-process peak RSS is 663,732,224 bytes (633.0 MiB).
`eager-structure-reader.swift` preserves that experimental implementation and `eager-index.log.gz`
records a fresh run; it is not part of any product target. Reproduce it with:

```sh
swiftc -O -swift-version 6 measurements/structure-tags/eager-structure-reader.swift \
  Sources/PDFReflowLib/DocumentModel.swift Sources/PDFReflowLib/ReflowDocument.swift \
  tools/inspect-structure.swift -o /tmp/eager-index
/usr/bin/time -l /tmp/eager-index corpus/cache/faa-h-8083-25c.pdf
```

The production parser retains value-only owner paths, then checks the relevant ParentTree array
through the existing eight-page document windows. The initial index has the same 39,198
candidate references on 510 pages; ownership validation and native association occur later.
The new `tools/check_structure_memory.py` gate measures 119,881,728 bytes (114.3 MiB) against a
192 MiB Mac RSS ceiling. It verifies the source checksum and runs the index in a fresh process,
excluding compiler memory. The gate is part of `scripts/check-all.sh --corpus`.

| Complete conversion | Seconds | Peak RSS MiB | Retained baseline RSS MiB |
| --- | ---: | ---: | ---: |
| FAA handbook | 37.5 | 828.1 | 759.2 |
| Algebra | 9.2 | 84.3 | 81.4 |
| 9/11 report | 10.1 | 124.3 | 121.3 |
| Fed Explained | 6.6 | 281.2 | 277.3 |
| Dietary Guidelines | 0.7 | 100.6 | 100.3 |
| Our Flag | 1.2 | 87.6 | 92.5 |
| CDC comic | 7.1 | 364.5 | 364.4 |
| Blue Book | 30.1 | 158.4 | 155.5 |

These are single process runs on this Mac, not a latency distribution or mobile-device budget.
FAA retains a roughly 69 MiB increase over the baseline even after the eager-parser regression
is removed. Its existing gate is unchanged. The new index gate protects that stage separately;
it does not bound every Apple allocation or resolve PDFKit leak report FB24783799.

## Contracts used

The implementation follows the PDF structure tree's page/MCID and ParentTree relationships,
not just the Marked flag or content-stream tag name. References:
[Adobe ISO 32000-1](https://developer.adobe.com/document-services/docs/assets/35e4369068f86065372c18787171a17e/PDF_ISO_32000-1.pdf),
[PDF Association clause 14 clarifications](https://pdf-issues.pdfa.org/32000-2-2020/clause14.html),
and [Apple CGPDFScanner](https://developer.apple.com/documentation/coregraphics/cgpdfscanner).
