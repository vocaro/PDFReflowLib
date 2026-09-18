# Native Type3 label spacing — bounded follow-up to #14

The DGA cover now emits “Protein, Dairy” and “Vegetables”. This is a separate slice from the
previous [combined-line title repair](../native-line-boundaries/record.md). The existing coherent
title remains. Diagram-label ownership remains unresolved, so #14 stays open.

## Source evidence

The checksum-pinned DGA original is 3,422,452 bytes, SHA-256
`c34f1bec5c9416265670b7fcb24556bb8616ba95e8de2f2890460b6bbca1a472`.
Physical page 1 was rendered with Poppler and visually inspected. It shows intact Dairy and
Vegetables, and three distinct food-group label positions around the pyramid. The source title
and labels are vector outlines accompanied by Type3 text. Font object 703 has identity FontMatrix,
one-byte character codes and ToUnicode object 786. All 89 CharProcs (788–876) contain only a `d1`
metrics operation. Native text therefore represents the outlined words without painting them.

`Tests/PDFReflowLibTests/fixtures/dga-1-text-operators.json` retains the unmodified decoded
ToUnicode stream and complete BT/ET text objects from content streams 877–884. Its provenance
matches the earlier `dga-1-layout.json`, whose PDFKit selections contain “Protein, Dair y” and
“Ve getables” inside single runs. The source operators decode to “Protein, Dairy\n” and
“Vegetables”; the terminal newline is part of the source mapping for the final Dairy glyph.
The false native spaces occur at TJ adjustments of -5.6 and -5.7, respectively: positive gaps
of 0.0056/0.0057 em, approximately 0.101/0.102 points at the source size. The legitimate space
after the comma is an explicit character code mapped to U+0020.

The reader does not use PDFKit character-bound offsets: a probe of the original confirms that
those offsets diverge from string indices at synthesized newlines and spaces. It also uses no
dictionary, OCR spelling correction, PDF identity/title rule or hard-coded word replacement.

## Accepted policy and controls

`NativeSpacingReader` runs only for styled native extraction on pages with a Type3 font. It
accepts an identity FontMatrix, a bounded explicit one-byte bfchar map, horizontal positively
scaled placement and independently positioned text-show operations. It does not calculate glyph
advance or continue an unknown text cursor. Other fonts, ranges/inherited maps, ligatures,
non-ASCII shows, nondefault text spacing/rise/rendering mode, external graphics state, Forms,
rotation and malformed state fall back. Font selections, operations, map bytes, show strings,
array entries, saved state, anchors and matching work are bounded.

Repair requires exactly one source-show origin inside exactly one native line rectangle and a
complete text match. It can remove only an extra ASCII space between ASCII letters at a source
TJ adjustment in [-10, 0), at most 0.01 em. Explicit source spaces and larger or uncertain
adjustments remain. The native plain/attributed strings must agree before repair. Only the
identified space ranges are deleted from a copy of the attributed text, preserving styles and
geometry. A terminal source-mapped newline may be omitted when matching the selection.

Seven source/synthetic Swift tests cover the two source labels, unchanged cover title and
combined opposite-side labels, explicit spaces, large/zero/positive/consecutive adjustments,
wrong boundaries, incomplete/mismatched text, hyphens, punctuation, numbers, style retention,
duplicate/overlapping origins, unsupported fonts/Forms/transforms/state/maps and work limits.
The existing single-run test still preserves both malformed words without source evidence.
The existing combined-line title, inline-script and hyphen suites remain controls.

## Remaining diagram ownership

The first cover drawing paints a page-sized colored rectangle. GraphicsReader clusters that
rectangle with the other painted regions into the page bounds. The pipeline's existing
image-backed-text path then clears graphic regions and keeps a page reference plus an
`unverifiedTextLayer` warning. That leaves label text in ordinary reflow; PDFKit also combines
the separate left/right text-show origins into one “& Healthy Fats & Fruits” selection.

Removing the background region alone would expose outlined title/label glyphs as graphics too;
it does not establish which words belong to which food group. This slice does not change that
policy or claim semantic grouping. The exact malformed opposite-side label line, whole-grain
label grouping, source image, title and warnings are deliberately preserved in the comparison.
Broader word-spacing repair, arbitrary Type3/CMap support, and diagram-label ownership remain
unqualified. No unrelated issue was investigated or changed.

## Validation and retained evidence

The baseline is clean main `a78aa7d`. Baseline and final candidate are converted under the same
host environment on macOS 27, using the same raster/Vision probe executable immediately before
each complete document. Both sets of receipts bind input, converter, probe and EPUB identities.
The collector calls the strict comparator before accepting any content delta. Caller-supplied
context labels alone are insufficient.

`collect.py` requires exactly the two DGA literal replacements on physical page 1, and exact
equality of every other normalized page, source marker, conversion report and encoded image.
It additionally checks all XHTML bytes, including inline markup and navigation, with only the
same two text replacements allowed. The standard drift comparator correctly reports a DGA
change; the collector separately accepts that exact reviewed delta.

Receipts and final gate results are recorded in the adjacent compressed logs, comparison summary,
corpus summary and identity manifest. The per-case raw progress logs and memory-sample series
were dropped in #196; each case's `result.json.gz` keeps their summary (progress-check events and result, sampled
and converter peak memory). Full EPUBs remain local under `.build/issue14/`.
Final results: 180 Swift tests on macOS and iOS 27 Simulator; 102 Python tests; eight fresh native
extraction processes; six fixture conversions; eight policy conversions and twelve rejection/
cleanup cases. The complete corpus passes 262 content checks on 64 reviewed pages, EPUBCheck,
navigation/spine/progress checks and existing resource ceilings. The isolated structure index
uses 119,717,888 bytes RSS under its 192 MiB ceiling.

The exact comparison covers 2,151 parsed pages and 3,922 image assets. Only the two DGA page-1
spaces differ. All other XHTML, encoded images, markers and reports match. DGA still reports
zero OCR pages; its final candidate peak RSS is 105,791,488 bytes. Measurements are observations,
not new performance or device guarantees. `full-gate.log.gz` records the required corpus lane
before the final plain/attributed-agreement guard and font-selection bound; `final-fast-gate.log.gz`,
`swift-tests.log.gz`, `ios-tests.log.gz` and `final-corpus.log.gz` verify the final implementation.

Warren and NOAA retain the existing unsupported full-conversion exclusions at default storage
ceilings. Passing the corpus is not general fidelity or physical-device qualification.
