# Report header follow-up (#10)

Boundary folios now share header evidence when the page number switches sides. Seven additional
9/11 notes headers disappear; no body text, images or genuine headings are lost. This is a bounded
repair and qualification of [issue #10](https://github.com/vocaro/PDFReflowLib/issues/10), which
**remains open** for the scope below.

## Source, repair and negative controls

The source is the pinned **full report**: 585 pages, 2,475,163 bytes, SHA-256
`657d41475eb3a9a5e3e87a6c7c51ac1dfbe1af7566d1abff7bf7286e7e1c0e1b`.
Base revision is `49b964b8f93976aa8addf2a6cfa01e077f3df2d5`; `identity.json` records source,
test, fixture and tool hashes. This does not reproduce the external 850,415-byte Chapter 1
granule or the discarded prototype's 46/54 recurring-header and 50/54 overall non-heading counts.

Physical pages 581–583 have three successive `NOTES TO CHAPTER 12` headers with printed folios
563–565. Previously, leading and trailing folios created separate two-occurrence/one-occurrence
groups. The new signature removes only the boundary folio, retaining its physical-page offset
and all internal chapter digits. Existing native margin, separation, style, position and minimum
three-occurrence requirements still apply. It also completes two five-page runs: chapter 2,
485–489, and chapter 10, 573–577. Changed output pages are **486, 488, 574, 576, 581, 582, 583**.

Seven new source fixtures cover 579–585, requiring every non-header line to survive while the
adjacent two-page chapter 11/13 runs remain unchanged. The source case and synthetic mirrored
folio case fail before the change (`before-tests.log.gz`). Controls reject inconsistent page
offsets, different internal chapter numbers and internal sequential digits. Existing tests also
retain sparse/duplicate pages, adjacent prose, drifting styles/positions, genuine body titles,
numeric folios, OCR-layer behavior and the public opt-out. New EPUB contracts reject all seven
old headers; body phrases, retained images and the genuine chapter-13 notes title supply controls.

The complete corpus also removes the extracted `46 Promoting Financial System Stability` margin
line on **Fed page 50**. The source render has the separate genuine chapter title on its colored
cover; that title, subtitle, contents entries and image remain unchanged. The added contract
rejects the old duplicate line and protects the title and contents. This is the independent
document-layout control for the same normalization, not a separate issue repair.

## Independently annotated heading sample

`annotations.json` records source-render observations, independently of reconstructed output.
The recall denominator is explicitly the chapter title plus the three numbered sections in
full-report physical pages **19–64**. It excludes subordinate bold/run-in headings. Every emitted
heading element in those 46 pages is classified against the source; this is a single-reviewer
sample, not inter-rater validation or full-book precision/recall.

| Observation | Current result |
| --- | --- |
| Emitted heading elements | 3 |
| Elements matching genuine source title lines | 3 |
| False heading elements in the sample | 0 |
| Major logical headings with every line detected | 1 of 4 |
| Major logical headings reconstructed as one element | 0 of 4 |

All three elements belong to the chapter title (`1`, `“WE HAVE`, `SOME PLANES”`). The title is
still fragmented. Sections **1.1 (page 19), 1.2 (32), 1.3 (53)** remain prose, so reporting only
100% element precision would obscure poor recall and fragmentation. These failures remain
explicit in `heading-audit.json`; they are not accepted as desired golden output. Audit controls
inject a spurious map heading and remove a true title line, verifying both change the measures.

## Map and timeline labels

Source and final-output image review covers physical **33, 50, 51**. Page 33's native extraction
contains fragments such as `BOST` and `ORK`, but its two preserved map images visibly retain
`BOSTON`, `NEW YORK`, `INDIANAPOLIS` and their geographic relationships. Pages 50/51 each retain
one combined image of the two flight maps with Boston/New York City and
Dulles/Pentagon/Newark/Shanksville labels. None becomes an emitted heading.

Three new source fixtures require the reviewed detached label lines to be fully contained in
the preserved regions and absent as standalone prose/heading blocks. The four exact final EPUB
assets are retained as `map-region-22.png` through `map-region-25.png` (two from page 33, then one
each from 50/51). Image hashes and page ownership/order match baseline. This qualifies readable
image ownership for these maps, **not semantic label reconstruction or timeline row/column order**.
Geographic words also appear legitimately in timeline prose; blanket word deletion is not used.

## Remaining margins and disposition

The reproducible native-only top-band inventory scans all 585 source pages before reconstruction.
It finds 624 native line objects in the outer top 10% on 550 pages; all objects on each such page
share one vertical row. It therefore supplies **no source-backed multi-line running-header case**.
Absence from this band/extractor is not proof that arbitrary multi-line margins are supported.

After the fix, retained top-band rows remain on **14, 16, 17, 18, 257, 468, 572, 578, 579, 580,
584, 585**. The inventory records extracted rows and decisions, not an independent correctness
label for every margin. Examples include Roman-numbered front matter, the separately extracted
title/folio on 257, transition titles and the adjacent two-page notes runs. No removal threshold
was lowered to absorb these cases. Multi-line headers, fewer than three occurrences, unusual
margins, OCR corruption, broader heading reconstruction/recall and timeline ownership remain
unqualified. Endnote links and general semantic figure reconstruction are outside this change.

**Update (#62).** All twelve pages were re-audited on branch tip `26d5209` with the same tool and
all twelve still reproduced there. Eleven are now removed on the folio-offset evidence recorded
in [margin-folios](../margin-folios/record.md): the four Roman front-matter heads keep offset 0
from the physical page and the seven Arabic notes heads keep offset −18, each with three or more
nearby pages agreeing in offset, height in the band and type size. The head text itself still
needs three occurrences; only the folio evidence was added. **Page 257 is the one remaining
case**: its band row extracts as a title with no page number plus a separate `239`, so neither
the text rule nor the folio rule reaches it. It stays two paragraphs and is not a heading. The
same change closes #40's retained Loper Thomas-concurrence heads (pages 44–47), so *short runs*
is qualified for heads that carry a folio and remains open for those that do not. Broader
heading precision and timeline row/column ownership are unchanged by that work.

## Validation and compatible comparison

- 173 Swift tests pass on macOS and iOS 27 Simulator; 102 Python tests pass in the fast gate.
  The final added map test also passes in both complete Swift suites.
- Fast-gate fixture/EPUB checks, eight policy conversions, twelve rejection/cleanup cases and
  native concurrency smoke pass. The isolated structure-index gate passes at 119,734,272 bytes
  against its 192 MiB ceiling.
- Both eight-book complete corpus evaluations pass EPUBCheck, ordered anchors/progress and
  configured memory gates. All **257 content checks across 64 pages** pass when final contracts
  are separately rechecked by the collector.
- Every before/after case has matching #26 raster/Vision capability receipts from the same
  launch environment, plus source, executable, report and output identities. The earlier
  exploratory no-probe run is not used for a compatibility claim.
- All **3,922** image files and their page order/ownership match. Six books have identical parsed
  page records and conversion reports. Only the seven 9/11 pages and Fed page 50 change; the
  collector requires exact body-text conservation after removing each reviewed margin prefix,
  unchanged remaining headings, script content and images. The 9/11 heading count is **87 → 80**.
- Reflowed-page count changes **496 → 494** because pages 581/582 had only their header outside
  preserved body images. Both pages' two image assets are unchanged; this is not lost body content.

`comparison-summary.json` retains the strict comparison's `passed: false` for the two intentionally
changed books; `reviewedChangeBoundaryPassed: true` records their narrower successful checks.
This keeps drift detection separate from correctness adjudication. `before-content.json` retains
the eight expected old-output header failures; all candidate contracts pass. Complete receipts,
logs and selected parsed pages are compressed without modifying their contents. The per-case raw
progress logs and memory-sample series were dropped in #196; each case's `result.json.gz` keeps their summary (progress-check events and result, sampled
and converter peak memory).

Full Warren/NOAA remain excluded from the default corpus lane for the previously recorded image
budget failures. No PDFKit leak, physical-device performance or full-book fidelity claim is made.

## Reproduction

Compile `tools/audit-report-margins.swift` with `NativeTextReader.swift`, `ConversionTypes.swift`,
`DocumentModel.swift`, `ReflowDocument.swift`, and `FurnitureDetector.swift`; run it against the
pinned full report and a fresh JSON output path. It records extraction and detector decisions
only, without OCR or reconstruction. Capture the ten new layout fixtures with the existing
checksum-verifying `tools/capture-layout-fixture.swift`.

Build baseline and candidate release CLIs separately. Compile `tools/probe-raster-environment.swift`
using its documented source dependencies. Run `tools/run_corpus_regressions.py` for each CLI with
`--environment-probe <same-probe>` and the same execution context. Run `scripts/check-all.sh --fast`,
the final `swift test`, the iOS Simulator suite and `tools/check_structure_memory.py`.

With the retained run directories/logs arranged as in `.build/issue-10`, reproduce the checks with:

```sh
python3 measurements/report-header-qualification/collect.py \
  --run .build/issue-10 --output measurements/report-header-qualification
```

The ignored full PDFs/EPUBs are required to regenerate comparison evidence, but permanent Swift
regressions use bundled extracted fixtures and run offline. No source PDF or full EPUB is committed.
