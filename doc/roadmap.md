# Development priorities

The library converts PDFs to EPUB 3 on Apple platforms 27+. Synthetic regressions cover basic
layout, OCR, images, EPUB packaging, progress and cancellation. General textbook fidelity and
physical-device memory/performance remain unqualified.

- **First priority: regression coverage across document types.** Run
  `scripts/check-all.sh --corpus` for extraction, layout and rendering changes. The reviewed
  [content contracts](../corpus/regressions.json) protect text, selected reading order, images
  and warnings across eight complete PDFs; they do not qualify all pages. Every fidelity fix
  needs a failing source-derived case plus positive controls in other layouts. Expand checked
  table cells, equation structure, image appearance and chapter continuity as those issues are
  addressed. Keep known failures separate from passing baselines; never regenerate expected
  content from converter output alone. See [the regression workflow](regression-testing.md).
- Refine [recommended conversion settings](conversion-options.md#recommended-starting-settings)
  from cross-document measurements. JPEG 0.90 is the initial tinted/noisy-scan recommendation;
  0.90–0.95 is provisional from measured endpoints, with PNG for clean cropped regions.
  A [seven-page raster sweep](../measurements/raster-dpi/record.md) compares 120/180/240 DPI
  and PNG/JPEG 0.90 across six documents, including fine colored labels, scans, tables,
  photographs and equations. It supports retaining 180 DPI as the baseline and reviewing
  240 DPI for small detail, with measured storage costs and pixel-cap behavior. Qualify
  broader pages, full-book/OCR effects of changing DPI and physical-device raster budgets
  before changing defaults or recommending general ranges.
- Investigate [PDFKit attributed-text leaks](https://github.com/vocaro/PDFReflowLib/issues/4)
  without losing formatting; Apple report **FB24783799** has a
  [standalone reproducer and fresh diagnostics](../measurements/apple-feedback-pdfkit/record.md). Keep the
  fresh-process high-water-mark gate and establish physical iPhone/iPad memory budgets.
- Expand mathematical qualification beyond native inline scripts: review exercise/answer-key
  numbering, detached fractions and unsupported formula structures across the algebra book.
- Support the Warren Commission scanned report: [full conversion exhausts the image-output
  ceiling](https://github.com/vocaro/PDFReflowLib/issues/5), and general notes/index ownership
  remains unqualified. Exclusively invisible image-backed text no longer supplies font-based
  code or heading evidence. [Detect suspect inherited OCR](https://github.com/vocaro/PDFReflowLib/issues/7)
  beyond the conservative unverified-layer warning. An [opt-in selective retry policy](../measurements/selective-ocr/record.md)
  re-recognizes image-backed existing text and preserves native controls; it repairs the checked
  Warren phrase but introduces other errors, so broader accuracy/detection remains unqualified.
  Evidence: [Warren baseline](../measurements/gpo-warren-1964/record.md).
  The [full-book JPEG experiment](../measurements/warren-image-encoding/record.md) substantially
  reduces file size but both tested variants still exceed the default entry-byte budget.
  Clients now control reference inclusion, page/region encoding and independent entry/final-file
  budgets. [Production policy measurements](../measurements/client-options/record.md) complete all
  920 Warren pages with explicit policies; defaults remain unchanged. Qualify physical-device
  memory and broader long-book configurations before treating that evidence as general support.
- Qualify remaining margin layouts and timeline labels under
  [9/11 report header/heading confusion](https://github.com/vocaro/PDFReflowLib/issues/10).
  Chapter-local and alternating running headers have source-derived regressions and
  [complete corpus evidence](../measurements/local-header-regressions/record.md).
  Keep the external ALL-CAPS prototype counts distinct from library measurements. Qualify
  [endnote markers/links](https://github.com/vocaro/PDFReflowLib/issues/11) and timeline-label ownership; retain the successful native word-spacing
  examples as positive review targets. See the [baseline](../measurements/gpo-911-2004/record.md).
- The development corpus includes the FAA handbook, Wallace algebra textbook, Warren
  Commission scanned report, 9/11 digital report, The Fed Explained and the illustrated Dietary
  Guidelines booklet, with identities, review
  points and baselines. Originals are fetched explicitly into a checksum-verified ignored cache.
  Qualify tagged table/figure semantics and mixed diagram/prose pages; expand with borderless tables,
  footnotes, damaged encodings and non-Latin layouts. Measure coverage and reading order.

- Improve [region preservation around shading/complex graphics](https://github.com/vocaro/PDFReflowLib/issues/13)
  and [native word boundaries/graphic labels](https://github.com/vocaro/PDFReflowLib/issues/14).
  Bounded shading is supported; the ten-page DGA case still reflows text on nine pages. The
  [current layout audit](../measurements/dga-layout-qualification/record.md) records 13 failing
  desired checks: connected decoration creates large crop hulls, page 6 has no selectable
  prose, and section-local order/column continuity remain incorrect on pages 3–4 and 7–10.
  Raw painted footprints expose candidate prose but do not establish complete illustration/label
  ownership; qualify a selective composite representation before changing conservative crops.
  No runtime change or full-layout pass is claimed. See also the historical
  [shading measurement](../measurements/shading-support/record.md).

- The NOAA Fifth National Climate Assessment adds a 1,834-page, 219.9 MB stress workload.
  Default conversion still reaches the [image-output ceiling](https://github.com/vocaro/PDFReflowLib/issues/5).
  [Explicit-policy full-book measurements](../measurements/noaa-output-policies/record.md) complete
  all pages with PNG or JPEG full-page images under 4 GiB experimental storage caps, with
  identical text and cropped images. JPEG barely changes final size and increases entry bytes.
  Qualify broader content and physical-device memory/storage budgets before general support;
  extend the validated numbered-chapter splitting to broader bookmark schemes and
  [bounded processing](https://github.com/vocaro/PDFReflowLib/issues/15).
  The [original default failure](../measurements/noaa-nca5-2023/record.md) remains historical evidence.

- The 56-page Our Flag booklet supplies a quick illustrated baseline with ten checked table rows.
  Its populated structure tree has Marked=false and lacks table roles and figure alternate text.
  Extend [validated tag consumption with spatial fallback](https://github.com/vocaro/PDFReflowLib/issues/17)
  beyond the bounded paragraph/heading phase to table/figure semantics; qualify remaining drop-cap layouts
  and flag image/name/description groups. The [baseline](../measurements/gpo-our-flag-2003/record.md)
  passes validity, progress and the 192 MiB Mac RSS gate. Its page-27 numeric table is preserved
  as a warned image; full tag semantics and drop-cap/figure ownership remain unqualified.

- The 42-page CDC Zombie Pandemic comic adds sparse/noisy text and image-only speech balloons.
  Detect suspect inherited dialogue and preserve [panel/balloon order](https://github.com/vocaro/PDFReflowLib/issues/18)
  or clearly signal readable image fallback. The [baseline](../measurements/cdc-zombie-pandemic-2011/record.md)
  passes validity, progress and the 512 MiB Mac RSS gate; dialogue quality remains unqualified.
  The [OCR-heading investigation](../measurements/ocr-headings/record.md) rejects blanket
  suppression because it loses the genuine Part 2 title; quadrilateral height and Vision's
  title flag alone also fail source controls. No runtime repair is retained from that experiment.
  The separate [Vision container-title validation](../measurements/vision-titles/record.md)
  under [#24](https://github.com/vocaro/PDFReflowLib/issues/24) checks 14 source pages across
  five PDFs. Unique text/region ownership and agreement with the line title flag still admit
  prose, dialogue, sign and running-header false positives; recognized titles also omit genuine
  title continuations. Issue #24's validation is complete and closure is recommended with
  metadata-only mapping rejected. A source-supported semantic rule remains unqualified;
  no production title mapping or broader comic repair is claimed.

- The 312-page Blue Book statistical scan supplies a warning/refusal contract. The converter
  reports unverified text layers and preserves source images; reliable scanned-table detection
  and reconstruction remain open under [suspect inherited OCR](https://github.com/vocaro/PDFReflowLib/issues/7)
  and general table reconstruction.
  Passing the signaling contract does not qualify table transcription.

Attachment-placeholder filtering, actionable source-layer warnings and correct whole-page raster
scaling are covered by [regressions and source-derived measurements](../measurements/quality-and-raster-fixes/record.md).

Merged-region clipping is covered by source-derived algebra geometry, formula/table pixel tests,
and a complete eight-document rerun; see [preserved-region regressions](../measurements/preserved-region-regressions/record.md).

Native inline superscripts/subscripts, FAA page-91/511 column order and Our Flag page-27 numeric
table preservation are covered by [source-derived regressions and full-corpus evidence](../measurements/three-fidelity-fixes/record.md).
Controls also protect 9/11 name/description rows and CDC OCR line spacing. These targeted fixes
resolve #1, #2 and #16; they do not qualify arbitrary math, table transcription or every column layout.

Bounded detached-fraction preservation (#20) and suppression of synthetic OCR font semantics
(#6) have enforced regressions, visible-typography controls and source review; see
[fraction and invisible-text measurements](../measurements/fractions-and-invisible-text/record.md).
Math outside the detector, mixed text layers, inherited OCR accuracy and full scanned-book
completion remain unqualified.

Poppler preview image URLs (#9) are relative to each page bundle and have real-tool HTTP
regressions with server containment intact; see [the evidence](../measurements/poppler-relative-images/record.md).

Chapter-local and alternating margin removal is covered by 29 source-layout pages, body/caption/
folio controls, public-option tests, and 119 corpus content checks on 31 pages across eight PDFs.
The [header measurement](../measurements/local-header-regressions/record.md) records baseline
failures and image/text comparisons. The [follow-up qualification](../measurements/report-header-qualification/record.md)
combines leading/trailing folios without lowering the three-occurrence minimum: seven additional
9/11 notes headers disappear, and Fed page 50 retains its genuine chapter title. Source-derived
map-label controls cover 9/11 pages 33/50/51. A separately annotated Chapter 1 major-heading sample
finds three correct title fragments, no false heading elements, and three missed numbered sections;
this is not full-book or subordinate-heading recall. Multi-line headers, fewer than three occurrences,
the remaining native margin layouts, heading reconstruction and timeline row/column ownership
remain unqualified; #10 stays open.

Small-font labels inside preserved graphics no longer promote surrounding Fed prose into
headings (#12). Ten source-layout pages, seven Swift tests and paragraph/heading corpus contracts
protect body text and modest-size section titles. The [heading evidence](../measurements/heading-body-regressions/record.md)
includes the failing original case and a rejected threshold change that lost six genuine headings.
The complete corpus has 145 reviewed content checks across 40 pages. General heading precision,
broader tag semantics and table transcription remain unqualified.

EPUB spine packing under #15 counts complete UTF-8 markup before crossing its 60,000-byte body
target, keeps source-page markers with following content, and isolates oversized atomic blocks.
Serialization writes completed documents in one pass with ordered progress; six Swift regressions
and independent corpus size/navigation checks cover the policy. See [spine-packing evidence](../measurements/spine-packing/record.md).
Broader chapter schemes, subdivision within oversized blocks, bounded reconstruction and
broader NOAA content/device qualification remain open; this work does not close #15.

The supported English, Arabic-numbered, root-level chapter-bookmark sequence under #15 now
requires matching source chapter-number/title lines before starting a new spine document.
[Chapter-boundary evidence](../measurements/chapter-boundaries/record.md) includes four reviewed
NOAA covers, invalid/nested/remote and native/OCR controls, and full-book EPUB checks. All 32
NOAA chapter covers start spine files; 96 files retain the existing byte-size subdivisions
(largest body 59,998 bytes). All 1,834 pages' markup and 11,245 images match the explicit-policy
baseline. Broader chapter schemes, bounded reconstruction and physical-device budgets remain open.

Native combined-line extraction under #14 restores the missing DGA cover boundary between
“Guidelines” and “For Americans” using full-line baseline evidence. The Our Flag page-31 heading supplies a second source case. Seven Swift tests protect
both baseline keys, scripts, drop caps, existing whitespace and hyphens; the corpus title check
runs with the full document. See [native-line-boundary evidence](../measurements/native-line-boundaries/record.md).
That slice left single-run label spacing and diagram-label ownership open. The subsequent
[native label-spacing repair](../measurements/native-label-spacing/record.md) restores “Dairy”
and “Vegetables” only when a supported Type3 character map and tiny TJ adjustment contradict
the extra space in a uniquely matched native line. Explicit word spaces, other fonts, unsupported
text state, ambiguous placement and arbitrary spelling remain unchanged. Diagram-label ownership
still remains open: the cover retains its source image and review warning, and #14 is not closed.


Preformatted list/code blocks retain native inline styles instead of flattening them to strings.
Source-derived algebra exercise exponents and FAA V-speed subscripts, synthetic list/code controls,
and EPUB packing/navigation checks cover this additional script-loss path. See
[preformatted-style evidence](../measurements/preformatted-styles/record.md). Numbered exercise
layout, semantic lists and endnote ownership/links (#11) remain open; preserving styles does not
resolve those relationships.


Bounded native drop-cap layout under #17 keeps the first body line before its continuation,
uses body typography for heading classification and avoids styling the decorative initial as a
subscript. Full ink bounds remain available for preservation. Our Flag source regressions and
[complete corpus evidence](../measurements/drop-cap-order/record.md) cover the supported pattern;
initial-word spacing, broader paragraph grouping and figure ownership remain open.


Validated P/H1–H6 tag consumption under #17 has source-derived Our Flag/Fed/FAA checks,
neutral heading levels, exact page/MCID/ParentTree ownership checks and spatial fallback.
[The evidence](../measurements/structure-tags/record.md) includes 137 Swift tests on macOS/iOS
Simulator, 221 content checks on 54 pages, an eight-book comparison with identical images,
and the rejected caption-order/oversized-heading approach. Deferred ParentTree validation avoids
eager sparse-array retention; a separate 192 MiB fresh-process FAA index gate protects that stage.
The complete FAA conversion still has higher RSS than its retained baseline; existing memory
gates remain unchanged. Full table/figure/alternate-text semantics, Form text, link ownership,
malformed-authoring coverage and physical-device budgets remain open; #17 is not closed.


The [PDFKit NSFont exception under concurrent extraction](https://github.com/vocaro/PDFReflowLib/issues/21)
has an Apple-SDK-only reproduction and a library-local serialization mitigation. Fresh-process
stress gates retain crashes/timeouts and verify text/font positive controls; a public-API test
protects independent output, progress and cancellation. See [the evidence](../measurements/pdfkit-concurrency/record.md).
Physical-device concurrency and host PDFKit calls outside the library lock remain unqualified;
Apple's underlying exception and the separate attributed-text memory leak are not resolved.

Queued native extraction now checks cancellation between timed lock waits under #21.
Native-reader and public-conversion regressions require cancellation and staging cleanup while
another extraction still holds the lock, with a surviving waiter and styled-text controls.
See [contention cancellation evidence](../measurements/extraction-cancellation/record.md).
This does not interrupt a PDFKit call already executing or qualify physical-device latency.

The [endnote investigation](../measurements/numbered-notes/record.md) under #11 adds native and
full-corpus controls for the already-supported raised reference 4 on 9/11 page 20. After
[#26](https://github.com/vocaro/PDFReflowLib/issues/26) traced the unrelated rendering/OCR drift to
execution environment, the [compatible-environment recheck](../measurements/numbered-notes/recheck/record.md)
accepts a bounded page-local repair joining supported numbered-note source lines into ordinary
paragraphs. Multi-paragraph and cross-page note identity, chapter-scoped reference association,
links to notes and return navigation remain open under #11; this repair does not resolve the issue.
