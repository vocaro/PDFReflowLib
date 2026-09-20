# DGA selective-preservation investigation and layout audit (#13)

> The Swift probes moved to `tools/probes/` and `tools/evaluate-real-document.py` is now `tools/evaluate_real_document.py` (`6e6ba6c`), which also gave each probe's library source list one home in `tools/pdfreflow_tools/swift_sources.py`; the paths and hand-copied source lists below are as measured.

**Keep #13 open. No production implementation change is retained.** This investigation starts
from clean main `2233d5f` and narrows the remaining work with fresh conversion evidence, all
ten source pages, source geometry, and explicit failing desired-layout checks. It does not
remove the roadmap item, weaken preservation, or claim full layout qualification.

## Current result

The checksum-pinned 3,422,452-byte source remains SHA-256
`c34f1bec5c9416265670b7fcb24556bb8616ba95e8de2f2890460b6bbca1a472`.
The release converter is SHA-256
`0b3b56eb12ad00a13c946f69743a25b2906214aa237fab603e834c50eeaec9c4`.
The fresh host run uses the same per-run raster/Vision probe executable as the retained
`measurements/native-label-spacing` final run. The strict comparator verifies compatible
capabilities, source/output receipts and complete report identities before comparing content.

There are **nine pages with reflowed text, zero OCR pages, zero unsupportedGraphics warnings,
and 27 images**. EPUBCheck, progress, existing DGA content checks (14 checks on pages 1–3),
and the unchanged 192 MiB RSS ceiling pass. Peak RSS is 105,758,720 bytes and conversion time
is 0.842 seconds; these are single-process Mac observations, not device guarantees.
`comparison.json` records equality of all parsed pages, markers, image bytes and reports.
The audit additionally verifies every XHTML file byte-for-byte, including inline markup and
navigation. All runtime files are unchanged. The previous eight-document compatible corpus
run in `measurements/native-label-spacing` remains applicable to the same executable; this
investigation reran DGA, not all eight books, and does not claim a new full-corpus run.

All ten source pages were rendered at a 1,200-pixel longest edge with Poppler and visually
reviewed. Their identities are retained; PNGs remain in ignored `.build/issue13/source`.
The EPUB's text records were inspected for all ten pages. Actual page-6 alcohol/sodium crops
and page-8 banner, callout and heading crops were also inspected. This is not a complete
browser-layout or image-pixel qualification of every emitted region.

## Full-document scope audit

`expectations.json` contains manually source-derived desired properties, not golden converter
text. `audit.json` records **6 passing and 13 failing checks** across all ten physical pages.
The collector never counts failed properties as passing baselines. `--check` exits 1 for these
failures. Missing phrases and reversed-order negative controls are exercised by the collector.

| Physical page | Source/output review and remaining qualification |
| --- | --- |
| 1 | Coherent title and repaired Dairy/Vegetables remain positive controls. Pyramid label grouping remains #14; the whole-page reference and review warning remain. |
| 2 | Letter prose and beginning-to-ending order pass the selected checks. Header/welcome text remains in the upper image. This is not a full signature/footnote ownership qualification. |
| 3 | Protein bullets interleave across columns. The dairy-to-Gut Health sequence passes. Connected graphics trigger a whole-page reference; selective preservation remains open. |
| 4 | “Incorporate Healthy Fats” occurs before the preceding vegetable section's right-column juice/servings text. Section-local ordering fails. |
| 5 | Both upper columns precede the Added Sugars callout in source order. This selected text-order check does not qualify separate bullet semantics or every style. |
| 6 | No selectable text. The alcohol section's two columns become one image; Sodium remains a complete source-composited image, including the three age/rate rows. The 9/10 count hides this page. |
| 7 | Infancy body columns interleave, including a continuation that crosses columns. Its section title stays in an image. |
| 8 | The full-width introduction callout remains readable in its image. Childhood and adolescence body columns interleave, including the adolescent continuation. |
| 9 | Young adulthood, pregnancy, lactation and older-adult body columns need section-local ownership/continuity. Selected first-sentence and continuation checks fail. |
| 10 | Chronic-disease and vegetarian/vegan columns interleave. Both source-derived first-bullet contiguity checks fail. |

The earlier shading record described #2 and #8 as then-existing dependencies. Their later
targeted fixes do not establish DGA section-local order: #2's FAA column controls and #8's
attachment-placeholder removal remain untouched. This investigation does not reopen those
issues, work on their mechanisms, or alter #14's cover behavior. The failing DGA checks here
are acceptance targets for #13's already-stated full layout qualification. No separate new
issue or unrelated TODO is proposed.

## Concrete geometry barrier

`page*-unclustered.json.gz` is obtained by changing only the diagnostic copy of
GraphicsReader's final return to expose rectangles **before clustering**. It retains image,
path and shading footprints plus conservative Form BBoxes; it is not exact per-pixel paint
geometry. The library source and executable are unchanged. `unclustered.patch` records that
one-line instrumentation. Paired captures verify identical native lines and source identity.

On page 3, 47 raw footprints become two clusters. The lower cluster is
`[0, 0, 612, 744.8955]`: 94.05% of the page area. Vertical decorative strokes genuinely connect
the illustrated section bars and footer; the enclosing rectangle spans ordinary prose too.
The existing image-backed-text policy then emits reflowed text plus a whole-page reference.
This is not an unsupported shading resource or evidence that an axial endpoint is a valid crop.

On page 6, 29 raw footprints become three clusters. The banner, short connector, circular
illustration and gradient heading form `[0, 676.6, 612, 115.4]`. Both first body lines end at
678.2645, so the cluster hull overlaps them by 1.6645 points. Whole-line preservation then
expands through the densely spaced lines. **All 12 alcohol body lines are disjoint from every
raw footprint.** This supplies a useful future selective-reflow target. It does not prove that
all text outside raw footprints is prose in an arbitrary diagram.

Inspection of page-6 stream object 58 and heading Form 62 confirms that the connector touches
the circle/banner and the circle touches the heading bar. The banner clip is y=755–792; the
short connector reaches y=755. Intersecting footprints with existing clip bounds therefore
cannot separate this composite. The Sodium callout is intentionally painted behind its text;
its whole source-composited image is a preservation control, not a missing-text defect.

## Bounded implementation alternatives evaluated

1. **Keep raw rectangles instead of their cluster hulls.** The diagnostic proves this would
   expose candidate body lines on pages 3/6. But the source has overlapping circle, pointer,
   connector, heading and Form footprints. Emitting each rectangle separately repeats paint
   and breaks the connected illustration. Reapplying the existing label/region merger restores
   the original large hull. Raw rectangle retention alone does not provide a usable replacement.
2. **Refuse a merge whenever it newly intersects native text.** This avoids the page-6 false
   prose overlap but cannot distinguish that prose from a detached diagram label enclosed by
   a connected chart. Such labels are exactly why current merging expands crops. A threshold,
   font-size guess or whitespace test without ownership evidence would weaken preservation.
3. **Keep the large image and additionally reflow raw-disjoint lines.** This could increase
   selectable text on page 6, but duplicates prose already in that image and does not preserve
   only the difficult region. Existing DGA output demonstrates that the exposed two-column
   text can interleave. It is not sufficient evidence for a safe selective-preservation fix.
4. **Retain nonrectangular paint/component geometry and render composite masks.** This is a
   plausible implementation direction, not ruled out as impossible. It requires retaining
   geometry through path/clip/Form transforms, grouping complete illustrations and labels,
   defining which text belongs inside each component, and emitting a composited asset while
   reflowing the proven external prose in section order. The current PageContent carries only
   `[CGRect]`; PageRasterizer renders the original page into a rectangle. Masking arbitrary
   rectangular unions still includes the body's false-overlap area or splits the illustration.
   Source text cannot be erased from a composite merely from its rectangle without proving
   that background paint and overlapping labels remain intact. A single change to clustering
   cannot supply these missing ownership/rendering contracts.

The investigation stops here because no safe bounded runtime implementation was established.
The per-footprint evidence advances the diagnosis and identifies a concrete page-6 acceptance
case, but is insufficient to accept a new ownership policy. No experimental runtime change,
ignored paint, reduced tolerance, changed fallback threshold, or new passing corpus expectation
is retained. Completing #13 requires an ownership-aware selective representation, complete
illustration/callout controls, section-local body order/continuity on pages 3–4 and 7–10, and a
fresh full compatible-corpus comparison after any runtime implementation.

## Reproduction

From the repository root with Xcode 27 and cached pinned DGA:

```sh
mkdir -p .build/issue13/source
pdftoppm -scale-to 1200 -png corpus/cache/DGA.pdf .build/issue13/source/dga
xcrun swiftc -parse-as-library -O -module-cache-path .build/issue13/module-cache \
  Sources/PDFReflowLib/NativeTextReader.swift Sources/PDFReflowLib/NativeSpacingReader.swift \
  Sources/PDFReflowLib/ConversionTypes.swift Sources/PDFReflowLib/DocumentModel.swift \
  Sources/PDFReflowLib/ReflowDocument.swift Sources/PDFReflowLib/GraphicsReader.swift \
  tools/capture-layout-fixture.swift -o .build/issue13/capture
for page in {1..10}; do
  .build/issue13/capture dga-2025-2030 "$page" ".build/issue13/source/page$page.json"
done
cp Sources/PDFReflowLib/GraphicsReader.swift .build/issue13/UnclusteredGraphicsReader.swift
patch .build/issue13/UnclusteredGraphicsReader.swift measurements/dga-layout-qualification/unclustered.patch
```

Compile the same command as above with `.build/issue13/UnclusteredGraphicsReader.swift` in
place of `Sources/PDFReflowLib/GraphicsReader.swift` and output `capture-unclustered`; capture
pages 3 and 6 to `page3-unclustered.json` and `page6-unclustered.json`. Run the converter through
`tools/evaluate-real-document.py` with the same probe as the baseline and a new output directory,
following `doc/corpus.md`'s compatible-environment procedure. Then:

```sh
python3 measurements/dga-layout-qualification/audit.py \
  --baseline .build/issue14/after/dga-2025-2030 \
  --evaluation .build/issue13/evaluation --source .build/issue13/source \
  --output measurements/dga-layout-qualification --check
```

The expected exit is **1**, reporting 13 failed desired-layout checks. Omit `--check` to capture
the same explicit failed assessment without a failing process status. The comparison requires
the unchanged baseline output; after implementing a fix, review intended changes separately
before adapting this collector. Do not replace the source-derived expectations with output.
Full EPUBs and rendered PNGs remain ignored. Compressed source-layout captures, baseline/current
receipts, reports/progress/capabilities, parsed pages and XHTML/image identities are retained here.
