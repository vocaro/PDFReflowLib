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
and cannot split a tagged text group across its border. A panel beside a paragraph follows
that complete paragraph, including wider continuation rows above or below the panel.
Small final words do not have to extend to the panel's edge. Unrelated paragraph columns
cannot supply adjacency merely because their baselines coincide.

The panel uses its own body size and leading through the existing block reconstruction.
This preserves its smaller paragraphs instead of feeding 8-point sidebar text through the
surrounding 10-point paragraph metrics. Native line metadata, styles, links and heading roles
remain available to the existing readers. The panel's blocks are appended as one closed
reading unit, with no new EPUB model or styling policy.

Source tests pin page 35's complete adjacent paragraph, sidebar and following paragraph in
order. Sixteen affected pages preserve every previously complete paragraph fragment inside
one resulting block. Page 95's ordering is pinned separately while the independent typography
follow-up restores its 10-point body's leading; the sidebar fix does not claim to solve that
second defect. Synthetic controls preserve tagged/styled/linked lines, keep every line once,
cover mirrored geometry, and reject a figure, a semantic table, or a tag spanning the boundary.
All 793 Swift tests pass on this isolated candidate. Final full-source conversion comparison and the corpus gate belong to the integrated root run.
