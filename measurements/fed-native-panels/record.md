# Native sidebar reading units

The independent #191 integration comparison used completed evaluator outputs from the
landed next-wave baseline and the combined candidate. All 135 Fed page markers survived
and no page lost letters, but that was insufficient: recovered sidebar rows interrupted
previously complete main paragraphs on physical pages 19, 34–37, 54, 56, 60, 63, 71,
73–74, 78–80, and 94–95. Page 35, for example, inserted “Regular congressional testimony”
between “In addition to” and “the regular FOMC statements”.

The source is the checksum-pinned `fed-explained-2021` government publication (SHA-256
`8db8fd9e1de63ac25a6f9585d78ded12f45ab56f0c14c52c199b36b368f84d60`). The 17 native-layout
captures include original styled runs, paint footprints and source identity; their
`baselineParagraphs` fields record the exact previously complete paragraph fragments
whose order the independent comparison found disturbed. No rendered assets are committed.

`NativeTextPanels` groups only native text inside rectangles independently proved to hold
wrapped prose. It declines panels intersecting images, semantic tables, quotations or asides,
and groups only inside uninterrupted untagged spans bounded by validated text groups. A panel beside a paragraph follows
that complete paragraph, including wider continuation rows above or below the panel.
Small final words do not have to extend to the panel's edge. Unrelated paragraph columns
cannot supply adjacency merely because their baselines coincide.

The panel uses its own body size and leading through the existing block reconstruction.
This preserves its smaller paragraphs instead of feeding 8-point sidebar text through the
surrounding 10-point paragraph metrics. Native line metadata, styles, links and heading roles
remain available to the existing readers. The panel's blocks are appended as one closed
reading unit, with no new EPUB model or styling policy.

Source tests pin page 35's complete adjacent paragraph, sidebar and following paragraph in
order. All seventeen affected pages preserve every previously complete paragraph fragment inside
one resulting block after combining the independent body-leading corrections (`b4b2adf` and
`e1e281d`). Page 95 needs both grouping and its document-corroborated 16-point body leading;
the combined source control pins that result. Synthetic controls preserve tagged/styled/linked lines, keep every line once,
cover mirrored geometry, and reject a figure, a semantic table, or a tag spanning the boundary.
All 793 Swift tests pass on this isolated candidate. Final full-source conversion comparison and the corpus gate belong to the integrated root run.


Independent review follow-up (2026-09-23): two generated controls reproduced valid tagged
order being reversed by geometric panel placement and duplicate heading IDs after panel
reconstruction started a fresh assembler. Panel grouping now respects retained tagged barriers, and
imported headings receive IDs from the surrounding page assembler. The packaged-EPUB test
contains a main heading and two styled, linked panel headings; every heading has one unique
XHTML anchor and one matching navigation target. Text, link targets and heading levels remain
unchanged. Mixed tagged/untagged and fully tagged controls retain their accepted order.

The focused panel, tag/order and spine/navigation selection passes 41 Swift tests, including
all 17 Fed source pages. Live extraction of pinned NOAA physical pages 1691, 1712 and 1730,
with `StructureTreeReader.read` supplied to `PageReader` exactly as in the conversion pipeline,
finds respectively 42, 26 and 36 native lines, zero retained tagged lines and one recovered
panel each. Their summary grouping and genuine headings therefore remain active under the
conservative tag guard. The three committed NOAA heading-size source controls also pass.


The final full-Fed check also exercises physical page 84. The source sets the left panel at
x=88.5–298.5, y=507.212–643.7. Its adjacent 10-point paragraph uses x=315 and 16-point
leading; `mini-` at y=492.0681 continues as `mum` at x=90, y=476.0681, then three more
full-width rows. A proved broken word can extend the panel's placement anchor into that wider
run only when size, leading, panel-bottom position, outer edge and column reach agree, the
continuation begins lowercase, and no unrelated element intervenes. Exactly one wider run
must qualify. The original text geometry remains unchanged; an exact predecessor marker
reuses the existing paragraph suspend/resume mechanism only for adjacent prose roles.

The ordered-range guard from the NOAA column fix remains the default. The source-proved
broken-word transition is its only exception. Seven generated controls cover the positive
transition, uppercase/new-sentence starts, extra leading, a displaced outer edge, an image
barrier and an unrelated text barrier. The five NOAA column source controls and all eighteen
Fed panel source controls pass together.

A whole-page tag veto was too broad: full extraction retains unrelated valid tags on many
Fed pages. The final implementation leaves tagged panels untouched and groups/places native
panels only within their uninterrupted untagged span. Permanent fixture metadata captures
16 actual tagged lines on page 35 and 35 on page 84 from `PageReader` with the real
`StructureTreeReader` index. Tests replay those assignments after backdrop composition,
covering both unrelated tags and the tagged main paragraph that must remain complete.
Native-only page 84 independently tests the explicit wider-run continuation. In full source
reading, tagged order places its sidebar after the preceding capital/liquidity discussion and
before the complete heightened-requirements paragraph; the content contract respects that
source order rather than demanding the native-only placement.

The final isolated run converts all 135 pages in 7.61 seconds at 273.02 MiB peak converter RSS;
EPUBCheck, structure, progress and memory checks pass. All 110 content checks pass when using
root's already-corrected page 79 `consolidated supervision` contract (that unrelated contract
edit is not duplicated here). The run did not collect an environment capability probe, so it
is a conversion/conformance and content check, not a capability-qualified attribution claim.
Compared with the previous integrated Fed output, all 135 page markers and all 320 encoded
images remain identical; no page loses letters or a previously complete paragraph. Fourteen
pages change paragraph grouping or order as the corrected tag/column boundaries take effect.
The root task owns the final combined full-suite and capability-qualified corpus gate.
