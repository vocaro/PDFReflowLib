# Reachable backdrop separation and image padding (#182)

Measured 2026-09-23 on macOS arm64, release CLI, library defaults. Implementation commits
`638dbb7`, `dc85f8f`, `302c5ce`, `c0800ae`, `9afe18d`, and `0715442`; the preceding #192
implementation is the baseline.
[results.json](results.json) records binary identities, source identities and gate results.
The executable basename is `pdf-reflow` in both lanes. Raw logs, PDFs, EPUBs and rasters stay
outside the repository. The source-derived test captures contain only native text and geometry.

This supersedes the open implementation questions in
[the earlier alpha-padding experiment](../image-alpha-padding/record.md), without changing that
record. The three numbered items in #182 are addressed as follows.

1. **Make the image-padding correction reachable.** `GraphicsReader.Paint` retains individual
   paint evidence before clustering. A flat rectangular page ground and supported graphics
   without an invisible text layer admit `PageBackdrop`. Scans, full-page photos, frames, patterns, complex
   full-page silhouettes and invisible text layers do not. Individual text panels and proven
   connectors can then be separated from figures. A plain 8-bit DeviceGray soft mask supplies
   the image's nontransparent extent before page transforms, clipping and clustering. Unknown
   masks retain their complete placement. On real Earthdata slide 12, the full cloud-icon
   placement takes “Cumulus”; the actual mask extent does not. The fixture verifies both sides
   and verifies the native label in the resulting reading.
2. **Keep connectors outside text boxes from seeding figures.** A small arrowhead attached to
   a two-point shaft, or the conventional seven-corner straight arrow outline, establishes a
   connector independently of its position relative to text panels. A detached triangle,
   unmatched straight chart stroke and complex labeled vector figure remain artwork. The
   regression test for the last two failed both assertions on the first implementation and
   passes with the refinement. A connector that touches two distinct, nonoverlapping text
   panels states a visual relationship: its connecting paints and rectangular node outlines
   are retained together, while their labels also reflow. The two-node control failed both
   visual assertions on `9afe18d` and passes with the connected-panel guard; plain edges and
   arrowed edges are both tested. A lone decorative text box supplies no graph evidence.
3. **Measure light writing against a dark background.** The earlier #93 inversion remains in
   force. `aLightOnDarkPageIsJudgedForWritingAReadingLeftOut` still pins it, and the full deck
   still recognizes slide 5's question. Its full-page reference is intentional. This item did
   not require a new inversion algorithm.

Complex vector artwork is preserved. The cloud surrounding the real flowchart is a complex
silhouette, not a rectangular text box. It stays in a source crop. Only the native text inside
proven rectangular or short-corner rounded panels may also reflow; genuine raster lettering
still belongs to its picture. The rounded-panel path replay has bounded storage and requires
straight sides plus curves confined to all four small corner squares; an ellipse and a cloud
fail it. One immediate aligned continuation at the same font size can extend a source text
panel whose wrapped title exceeds its box. Crop expansion preserves the complete source
lettering, while native panel ownership keeps that writing in the reflowed reading as well.

A large cloud's bounding rectangle can barely overlap the corner insignia even though the
painted shapes are separate. Initial backdrop paint groups join only when their overlap is at
least one tenth of the smaller footprint. Keeping marginal overlaps separate prevents them from
masquerading as a page-sized image layer. Whole-label crop expansion may subsequently join
those regions to preserve complete lettering and shapes; it does not change the native source
text into an inherited scan layer. Slide 18 pins the cloud, the complete title and all rounded
panel outlines, while its actual paint seeds remain distinct from the corner image. A final
source control rejects any crop that intersects a rounded panel without containing it, which
keeps connected diagram components complete rather than slicing them between images. Slide 11
pins three circle diagrams whose labels account for most of the slide's words: those labels
stay safely in local diagrams rather than forcing a full-page reference. These source controls
failed admission on `dc85f8f` and passed admission on `302c5ce`; the complete-crop checks
were subsequently added with `c0800ae` and `9afe18d`.

## Memory and verification

The prior experiment decoded all image masks through a retained Core Graphics document, which
kept roughly 220 MB of DGA cover samples alive. The implementation here opens a short-lived
Core Graphics document for each mask, returns only its rectangle, and releases that document
before reading the next mask. The supported mask size is capped at 64 million samples; the
DGA 192 MiB budget has not changed. The final eligibility survey reads all 5,262 pages of the
20 reviewed corpus sources: only Earthdata slides 1–21 and Our Flag page 55 are eligible.
DGA therefore does not decode its cover masks through this path; its passing result is a
no-regression control, not a measurement of 45-mask decoder retention. Actual isolated mask
reads are exercised by the generated production-path fixture and the real Earthdata deck.
The affected lane measured these converter process RSS peaks, without raising any ceiling:

| Source | Before #182 | Final `0715442` | Existing ceiling |
| --- | ---: | ---: | ---: |
| Earthdata | 103,137,280 B | 101,040,128 B | 134,217,728 B |
| DGA | 114,098,176 B | 120,045,568 B | 201,326,592 B |
| Our Flag | — | 113,442,816 B | 201,326,592 B |

DGA's EPUB and conversion report are identical to the baseline after normalizing generated
identifier/date fields. Earthdata and Our Flag are likewise identical between `9afe18d` and
`0715442`; the final guard adds coverage for the new two-node control without changing their
reviewed output. These are process measurements under concurrent host work, not mobile-device
or latency qualifications.

The final full suite passes 733 tests. Operator fixtures cover admission, rejected backgrounds,
mask padding versus opaque/unknown masks, clipping, detached art, outside-box arrows, isolated
chart strokes and rounded panels. A generated PDF exercises the production isolated-document
mask path. Earthdata slides 11, 12 and 18 are replayed from the pinned source's actual paints,
native lines and image extents, with the source SHA-256 asserted in each test. All 21 real slides
are converted and covered by 68 content assertions; Cumulus/Data Archive are checked on slides
12–21. The broad 20-document corpus gate runs `9afe18d`. The final connected-panel guard `0715442`
is confined to `PageBackdrop`, so every eligible document (Earthdata and Our Flag), plus the
DGA control, is rerun with that exact final binary. Both coverage levels and their memory
results are explicit in the receipt. The integrated main corpus gate remains a separate check.

Visual inspection compared source slides 11, 12 and 18 against the output regions: the cloud
icon, flowchart panels and arrows remain intact, and the cloud crop preserves its full outline.
The deck's insignia remains a picture. Only slide 5 retains a full-page reference; native
backdrop slides no longer report `unverifiedTextLayer`.

This does not claim all seven items in #175. The drawn box lettering on slide 2 remains in its
crop, list nesting and diagram reading order remain separate issues, and repeated native
“Cumulus” copies in the source layer are not deduplicated by this change.

## Reproduction

Build `swift build -c release` at the implementation commit and keep a frozen copy with basename
`pdf-reflow`. Run `swift test`, then `tools/run_corpus_regressions.py --converter <frozen-path>
--epubcheck /opt/homebrew/bin/epubcheck --output <new-directory> --jobs 2 --memory-attempts 1
--settle-seconds 0` with `/opt/homebrew/bin/python3`. Source files come from the pinned corpus
cache. The additional affected-document lane uses the same command with `--jobs 1 --case
ntrs-20180003024-earthdata-slides-2018 --case dga-2025-2030 --case gpo-our-flag-2003`.
No memory ceiling is relaxed.
