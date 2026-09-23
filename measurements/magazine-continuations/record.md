# Magazine paragraph continuations — #214

Source: USDA Agricultural Research, November/December 2012, physical pages 12
and 17. SHA-256 `2673d1fded74ad89c8b5c59dc325c7884601e1aca5b5755b15a105c1f5b0d761`.
Both complete original pages were rendered and reviewed on 2026-09-23. Page 17's
native text/style/geometry capture is committed under the corpus's owner-approved
2026-09-17 derivative scope; no source PDF, raster, crop, or EPUB is committed.
The page-12 capture and quotation/caption/column-order prerequisites belong to #191.

Page 12 ends its first column with `Areawide Pest Management Research` (10.5 pt,
x=36.06, y=526.19, width=172.07), resumes beneath the middle-column pull quote at
`Unit’s Aerial Application Technology` (x=220.02, y=548.91, width=171.94), then
continues `truck-` (middle column, y=523.92) / `mounted,` (right column, y=745.84).
The Dan Kline quotation and its picture retain distinct units. Page 17 ends its
left column with `postharvest were in the 10˚ to 15˚F range,` (x=36, y=59.19,
width=172.02), then resumes `consistently higher than the 3˚` (x=219.96, y=745.64,
width=127.07). The infrared thermometer photograph, DONG WANG credit and caption
retain their own blocks.

`InterruptedColumnContinuation` proves a full column's last body row, matching
type/structure, a neighboring column's flush opening with two following body rows,
and ownership of every intervening image, quote and smaller caption/credit. It
declines a completed sentence, an indented opening, an intervening body paragraph,
an unrelated credit, a heading, and a distant or spanning image. An adjacent-column
join with no display interruption requires an explicit broken-word hyphen. It uses
the existing paragraph suspension handles and joins the original inline content;
it does not reorder or absorb the intervening units. Recognized/synthetic pages
do not enter this new planner.

Page 17's following heading is two Helvetica-Bold 9 pt rows, `How Much Pressure
Can a` / `Leaf Take?`, above an indented Times 10.5 pt paragraph. The existing
section-label proof is applied to their combined candidate: recurring style,
clearance and first-line-indent evidence remain required. Only proven components
are emitted as one heading, preserving their bold text and making one navigation
entry. Unseen style, no indent, a non-bold second row, excess leading and recognition
all have negative source controls.

Focused validation: seven Swift tests pass (including two parameterized source
tests), covering both complete reconstructed source pages with captured styles,
all three requested joins, one complete page-17 heading, distinct quotation and
credit blocks, rejection controls, and the existing FAA continuation/style tests.
The 33 Python corpus-content tests also pass.
The planner and stacked-label integration were independently reviewed by the
coordinating agent; the image ownership guard was tightened after review.

Full-source comparison: both otherwise identical release binaries converted all 24
pages using the normal `pdf-reflow` basename. The parent disables only this change's
layout hooks. Both EPUBs pass EPUBCheck 3.3 with zero errors/warnings. All 24 source
markers and all 84 image assets are byte-identical between outputs. Every page's
non-whitespace character multiset is identical (including punctuation and hyphens).
Only pages 12 and 17 change text order; the completed paragraphs put their resumed
words before the separately retained displays. Quotations and asides are identical
on every page. The heading rule additionally promotes the source's two-line
`Unlocking the Chemistries of Folk Remedies` on page 6 and `Learning How Repellents
Hinder Mosquito Attacks` on page 7. Both complete source pages were rendered and
reviewed; these are real subheadings, and both now have corpus heading checks.
The only pages changing heading/paragraph blocks are 6, 7, 12 and 17. All seven
new or corrected semantic assertions fail against the exact parent and pass against
the candidate; see `results.json` for hashes and individual results.

Raw evidence remains under `/tmp/pdfreflow-214-parent` and
`/tmp/pdfreflow-214-candidate`. These direct conversions provide source/EPUB evidence,
not a new device-memory qualification or a full-corpus measurement. Existing paragraph
boundaries within the right-column page-12 prose remain governed by the assembler;
this change qualifies the three explicit continuation joins, not all article paragraphs.

This change depends on #191's `Element.quotation` / `Element.caption`, whole-caption
ownership and source-verified column ordering. Its code commit does not include
copied #191 implementation files. The coordinator runs the integrated full-corpus
qualification before closure; this bounded commit does not close #214.
