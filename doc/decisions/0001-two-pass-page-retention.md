# 0001 Two passes over the pages, with a spill store between them

## Context

Reconstruction needs document-wide evidence that only a full pass over the pages can supply:
the hyphen-repair vocabulary, margin-furniture candidates, numbered-note heading pages, chapter
matches and the running character budget. Keeping every positioned `PageContent` resident until
that pass finished made peak memory scale with the book, and the 920-page Warren report and
1,834-page NOAA assessment were the cases that mattered. Bounded-memory work was tracked under
[#15](https://github.com/vocaro/PDFReflowLib/issues/15).

Three strategies bound per-page memory: spill each extracted page to the workspace and reload
it once; keep pages resident (the whole-document control); or repeat extraction in the second
pass. The measurement compared all three on every complete corpus book, on the Mac and on a
physical iPhone through a minimal host app (`measurements/page-retention/device/host/`), with
byte identity against the pre-change converter as the correctness gate.

## Decision

Extraction is one pass that keeps only document-wide evidence (`DocumentEvidence`) and hands
each extracted page to a `PageStore`, which encodes it as a binary property list in the
workspace. Reconstruction is a second pass that reloads one page at a time and needs only that
page and its stripped predecessor for cross-page continuation. `FurnitureDetector` is phased to
match (`collect`, `resolve`, `apply`), with `strip` running the same phases over an array so the
streamed and array paths cannot diverge. The two alternatives were retired after the
measurement: the `PDFREFLOW_PAGE_RETENTION` switch no longer exists, and their sources and
tests were kept as a patch beside the record, then removed from the tree (they remain at commit
`a28fb09`).

## Consequences

- All three strategies produced byte-identical output against the pre-change converter on the
  complete corpus; spilling had the lowest peak footprint on every book where retained pages
  matter, on the Mac and on the phone.
- The workspace holds spilled pages during reconstruction; each is deleted on reload and the
  directory when reconstruction finishes, so afterwards it holds only assets.
- Equal values share one slot in the property-list encoding, so a negative zero can reload as
  positive zero; no reconstruction step reads the sign of zero, and the tests pin exact reload
  of styles, inline markers, structure, drop-cap geometry, null rectangles and every flag.
- The logical block list still accumulates until writing finishes; streaming blocks to the
  writer is separate work, and #15 remains open for that and for physical-device measurement.
- Furniture warnings keep their position between extraction and reconstruction warnings;
  reconstruction reads only structure-fallback and hyphen warnings.

## Evidence

[measurements/page-retention/record.md](../../measurements/page-retention/record.md); the
runbook for re-measuring is in [memory testing](../memory-testing.md#page-retention-strategies).
