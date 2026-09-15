# Preserved-region regression qualification

The macOS 27 arm64 release CLI, built from `716c107` plus the recorded layout change, passes all
eight complete corpus evaluations with library defaults. The executable SHA-256 is
`a0b41e852b61ffc49e5b0196d7256605465ee45ff5cbdeed08d887394540fce8`.
[Implementation identities](implementation-identities.json), [run metrics](runs.json),
[content summary](summary.json) and [gate log](corpus-gate.log.gz) identify the measured build.
All runs pass EPUBCheck, progress, existing peak-RSS budgets and the unchanged 55 content checks
on 18 reviewed pages across 2,151 source pages. These checks do not establish whole-book fidelity.

## Regression coverage and defect

Eight additional Swift tests cover preserved fraction/exponent pixels, six ruled-table cells,
neighboring prose, monospaced equations, unruled math symbols, transitive label grouping, page-edge
clipping, real algebra geometry, and an explicitly known detached-fraction failure. Two tests
run at both 72 and 144 DPI. The complete final suite executes 49 tests on macOS and the iOS 27
simulator: 48 pass without known issues; one reports the expected unresolved fidelity issue.
[Mac log](mac-tests.log.gz), [iOS log](ios-tests.log.gz). The corpus gate also passes 45 Python
tests and six small PDF-to-EPUB/EPUBCheck conversions. Its Swift count is 48 because the final
source-derived algebra test is added and run separately afterward; runtime bytes remain unchanged.

The pixel expectations come from original PDF drawing coordinates, not a converter-produced
golden image. They check numerator/denominator alignment and spacing, raised exponent placement,
fraction-bar ink, every table cell's row/column placement, crop extent and surrounding selectable
prose. They do not recognize arbitrary mathematical expressions or prove all table values correct.
Source renders are produced independently with Poppler and visually inspected:
[formula](synthetic-formula.png), [table](synthetic-table.png),
[detached fraction](synthetic-detached.png). The original synthetic PDFs accompany those renders.

Graphic clustering can introduce a new bounding rectangle that intersects a text line neither
component touched. Without another whole-line expansion, the image clips the line while layout
removes it from selectable text. Merging and label expansion now repeat until bounds stabilize.
The connected synthetic fraction retains its raised exponent; unrelated prose and code remain
selectable. This is a region-containment fix, not semantic math/table reconstruction.

Negative controls execute in a separate temporary Swift package with the same local ZIPFoundation
checkout. Restoring `LayoutReconstructor.swift` from `716c107` produces six assertion failures in
the synthetic pixel/merged-label tests ([log](negative-old-layout.log.gz)) and eight failures in
the real algebra layout test ([log](negative-old-algebra.log.gz)). Replacing
`context.drawPDFPage(reference)` with a no-op in `PageRasterizer.swift`, while retaining fixed
layout, produces four failures in the fraction/table pixel tests ([log](negative-blank-raster.log.gz)).
Those PNGs still exist and decode, so mere image presence cannot satisfy the new checks.

## Real-document review

The source-derived fixture contains text and geometry for physical page 17 of the pinned Wallace
algebra book. The source checksum is verified before capture. The documented capture command
reproduces the bundled JSON exactly. Its containment assertions reject partial text crops and
require exercise prefixes 60, 67 and 71 to remain with their mathematical regions, while both
instruction headings stay selectable. Review compares the [source](algebra-17-source.png) with
the [actual EPUB crops](algebra-17-after-contact.png); the contact sheet labels crop assets and
is not a rendering of EPUB flow. Instructions and the source page marker are outside the images.

Across complete output spines, selectable source text and image-byte multisets are unchanged
for 9/11, Fed, DGA, Our Flag, CDC and Blue Book. [Changed-page records](changed-pages.json)
compare the new run with the previous cross-corpus measurement, whose runtime is `305cb14`.
Nine FAA pages and 65 algebra pages have changed image pixels and/or source text. This list is
broader than the individually reviewed pages; it does not claim all changed pixels are qualified.

FAA retains 588 images. Reflowed pages decrease from 511 to 508: physical pages 19, 155 and 367
already have nearly page-sized images but previously leave detached caption/sentence fragments
outside them. The expanded images visibly retain those complete bottom lines. For page 155,
compare [source](faa-155-source.png), [previous crop](faa-155-before-0.png) and
[corrected crop](faa-155-after-0.png). The other two affected FAA page images are also inspected
locally. This preserves appearance at the cost of those fragments' selectability; recovering
properly bounded independent figures and full prose reflow remains unfinished work.

Algebra retains 481 reflowed pages, with image count decreasing from 2,077 to 2,052 as related
regions merge. Page 17's exercise prefixes are preserved in their complete crops. Existing inline
superscript and broader answer-key/reading-order defects remain unqualified. Counts alone are
not fidelity scores. The largest observed converter RSS is FAA's 782.1 MiB; timings and all other
budgets are in the run records, not a device guarantee or a comparative performance claim.

## Remaining failure and attribution

[Issue #20](https://github.com/vocaro/PDFReflowLib/issues/20) tracks the detached fraction. Its
conversion and PNG decoding run outside the known-issue wrapper; only the intact-fraction predicate
is expected to fail. An unexpected pass requires removing the wrapper. It is not included in the
48 passing tests' fidelity claims. Inline superscripts (#1), borderless tables (#16), physical-device
qualification and full Warren/NOAA completion remain open. Warren/NOAA are explicitly excluded
from the successful complete-conversion lane, never reported as passes.

Algebra excerpts and geometry derive from *Beginning and Intermediate Algebra*, copyright 2010
Tyler Wallace, [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/),
[source PDF](https://s3.amazonaws.com/myopenmath/cfiles/19515/Beginning_and_Intermediate_Algebra.pdf).
The derivatives are extracted geometry/text, scaled source renders and converter crop comparisons;
they are not relicensed under MIT. FAA material retains its government-document provenance.
