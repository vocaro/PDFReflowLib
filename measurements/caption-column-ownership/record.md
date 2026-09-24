# Caption and body column ownership

Reviewed September 23, 2026 against base `4f301ca`. Source physical pages NOAA 56, 58, 67 and FAA 45, 216 were rendered and visually reviewed. The NOAA photographs/captions stand beside body columns; NOAA 58 has a map caption beside the map. FAA 45 and 216 have four-row captions below figures, followed by the continuation of the left body column. Figure 2-5's body ending has only two right-column rows.

Sources are the checksum-pinned corpus documents:

- NOAA NCA5: `1942cbf346dc2c711fea413d6d6543edb8bc1e3a88d4c3a85e733c6b6d3577bf`.
- FAA PHAK: `247929cace0ab56b376e683eba540cc4c8f39f199ab35414e8b604e24f395cb7`.

The five `*-caption-*-layout.json` fixtures contain schema 3 raw graphics and attributed extraction evidence from the existing capture probe, plus `nativeLines` captured through the actual PageReader with the full document StructureTreeReader index. These retain styles, links, and complete source tags; this matters because FAA's caption opening is 8pt and its continuation 9pt, within one source paragraph tag. The fixture tests remove the verified bottom furniture before reconstruction, as the real document pass does. Leaving FAA folios in place conceals the body/caption contamination regression.

The correction groups only geometrically continuous numbered captions or photograph captions carrying explicit credits next to a preserved figure. Complete, ordered same-group paragraph tags are accepted; partial, mixed, and heading tags are rejected. Caption type size need not be smaller than the page's modal body. Caption rows then supply column evidence; overlapping margins merge only for vertically disjoint measures with substantial horizontal overlap and proved caption ownership. Simultaneous columns remain separate. Vector figure crops supply adjacency evidence as well as raster images. Existing caption assembly preserves the original inline runs.

The column continuation path skips these independently proved caption units, checks their opening against the intervening figure, and also recognizes a two-row body ending when its final row is short and terminal. Full-width or unfinished two-row endings fail the new negative control. An initially considered NativeTextPanels exception was removed: source tests prove the caption/column correction suffices.

Validation:

- Full Swift suite: 826 tests passed in 24.002s before removal of the unnecessary panel exception and addition of the final two-row negative test.
- Final exact runtime: focused 7 tests passed in 0.271s, including five source cases, all prior interrupted-column safeguards, partial/foreign/heading-tag rejection, remote figure and broken-leading rejection, simultaneous/disjoint column controls, and short terminal-row controls. Every source crop remains emitted exactly once.
- Reverting all four runtime files to the base produces seven focused failures. Restoring caption/column changes while reverting only InterruptedColumnContinuation produces exactly the two FAA body-seam failures.
- New actual-EPUB contracts require complete captions and body continuity. Applied to the frozen pre-fix completed conversion (converter SHA `d7dc23e62c741e98c4529c1eeeaed2f31495175c18cc3013371bd33018c52eb2`), they fail seven NOAA and four FAA assertions at the reviewed defects.
- An independent read-only audit captured all 112 NOAA pages gaining at least 100 characters and checked adjacent stable native rows against the frozen final EPUB. Four pages flagged: 56 is the known caption/body interleave, 28 and 411 have the identical interleave already in the baseline, and 74 was a repeated-reference match (the complete bullet is unchanged and contiguous). No additional new native-row interleave was found. This check addresses retained native rows, not text intentionally preserved only in images. Page 67 is additionally covered by the direct source fixture despite its smaller net gain.

The root integration run owns the final full corpus conversion, EPUB/resource gates, and performance qualification. This record does not claim that run has completed for this patch.
