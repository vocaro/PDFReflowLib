# 0008 Reconstruction streams its blocks to the writer

## Context

[Decision 0001](0001-two-pass-page-retention.md) bounded the page model by spilling each
extracted page to the workspace between the two passes, and left the logical block list
accumulating until writing finished: `reconstruct` returned one whole `ReflowDocument` and
`EPUBWriter.write` consumed it afterwards. That was the remaining whole-document retention in
the converter, and the writing-phase footprint the page-retention record measured on NOAA was
attributed to it ([#33](https://github.com/vocaro/PDFReflowLib/issues/33)).

The writer already kept only one body string plus the navigation lists and emitted each spine
document as it closed, so nothing in it needed the whole document — only the handoff did.

## Decision

Reconstruction emits the document as a stream of `ReflowPart`s: the metadata and validated
chapter starts once, then each asset and each block in the order it makes them, an asset always
before the block that names it. `EPUBWriter` is an actor that consumes that stream, serializing
each block as it arrives and writing spine documents as the packer closes them, and builds
navigation, package metadata and the archive in `finish`. Reconstruction holds back only its
trailing block, because `LayoutReconstructor.appendPage` can still join a continued paragraph to
it; everything before it is final.

Model validation moved with the handoff. `ReflowDocument.Validation` accepts one part at a time —
duplicate assets, heading levels and an image's asset as each arrives — and checks at the end
that the document had blocks and that every chapter boundary reached a standalone page marker.
`ReflowDocument.validate()` runs that same validation over `parts`, so there is one
implementation of the rules. A caller that takes no stream gets the document collected from the
same stream, which is how the tests read a whole document, so the streamed and collected forms
cannot diverge either.

Serializing a block is counted as the work of the pass that produces it, so the pipeline's
shares are unchanged and the writing stage is navigation, package metadata and the archive
alone. `ProgressBudget` lost its serialization share; the writer's own fraction is now the
archive entries, and it starts at the same 0.82 the clamped pipeline end already reported.

## Consequences

- The converter never holds the block list. The ten complete corpus books convert
  byte-identically against the pre-change binary, with identical reports.
- The lifetime peak does not move. On NOAA it stays near 950 MiB, set during extraction by
  PDFKit and rasterization transients, hundreds of mebibytes above anything the writing phase
  reaches. The writing-phase footprint is lower in every pair measured, but by 6 to 18 MiB on
  the two undisturbed NOAA pairs: the block list is a much smaller share of that phase than #33
  assumed, which was mostly the asset registry, the ZIP machinery and framework residue.
- No progress event is reported between the last block and the first archive entry. The
  sequence stays monotonic and the writing stage still exists, so a client that waits for
  `.writing` still sees it.
- `EPUBWriter` being an actor is what lets the closure the pipeline calls cross the isolation
  boundary; blocks arrive one at a time and never concurrently.
- A writer for another format consumes `ReflowPart`s; nothing forces it to hold a document.
- No physical-device measurement exists for this change, so #33's device acceptance is open.

## Evidence

[measurements/streamed-blocks](../../measurements/streamed-blocks/record.md); the identity gate
is [decision 0004](0004-byte-identity-gate.md).
