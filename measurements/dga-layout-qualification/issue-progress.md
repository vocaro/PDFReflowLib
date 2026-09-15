Investigated the remaining selective-preservation/full-layout scope on clean main `2233d5f`.
No safe bounded runtime change was established, so preservation policy remains unchanged and
#13 should stay open.

Fresh compatible-host DGA conversion passes EPUBCheck, progress, the unchanged 192 MiB RSS
gate and the existing 14 content checks. It still reports 9/10 reflowed pages, zero OCR pages,
zero unsupportedGraphics warnings and 27 images. Every XHTML file, encoded image, source
marker and report field matches the retained final #14 baseline. This investigation does not
claim a new eight-book run; the executable/runtime sources are unchanged.

All ten source pages were reviewed. Nineteen source-derived desired checks now expose six
passes and thirteen failures, retained as failures rather than passing golden expectations:
protein/infancy/childhood/adolescent/older-adult/chronic-disease/vegetarian text interleaves,
page 4 starts the healthy-fats section before the preceding right column finishes, and page 6
has no selectable body text. Complete source-composited Sodium and infancy-introduction
callouts remain visible in their images.

The per-footprint diagnostic gives a concrete next target: all 12 alcohol body lines on page 6
are disjoint from the 29 raw painted footprints. But the genuinely connected banner, narrow
connector, circle and heading bar form a wide rectangle whose bottom overlaps the first body
lines by 1.6645 points; whole-line crop expansion then absorbs both columns. Page 3's 47 raw
footprints form a connected lower-page hull covering 94.05% of the page. Clip intersection
cannot disconnect artwork that actually touches.

Retaining per-paint rectangles is feasible as evidence, but independent crops repeat overlapping
artwork and break the composite. Preventing merges based only on nearby text would also detach
diagram labels. A safe implementation still needs component/label ownership and a suitable
composite or mask representation, followed by section-local reading-order qualification and
a full compatible-corpus comparison. No tolerance was lowered and no paint was ignored.

Evidence and reproducible diagnostic patch, all ten native-layout captures, desired checks,
negative controls, exact comparison, source/output identities, and detailed rejected alternatives:
`measurements/dga-layout-qualification/record.md`. The roadmap now names this remaining scope.
The separate #2 FAA column fix, #8 placeholder fix, and #14 cover label behavior are unchanged;
no new independent issue or unrelated TODO was discovered or pursued.
