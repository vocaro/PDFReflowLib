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
and defers to retained tagged reading order on pages carrying validated text groups. A panel beside a paragraph follows
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
reconstruction started a fresh assembler. Panel grouping now defers to retained tags, and
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
