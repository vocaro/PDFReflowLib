# 0010 A destination that names a page is resolved after the last spine document closes

## Context

[Decision 0008](0008-streamed-blocks-to-the-writer.md) made the writer a consumer of a stream:
each block is serialized as it arrives and a spine document is written the moment the packer
closes it. Nothing afterwards amends a block, and nothing holds the document.

Two features need what that contract does not provide. The author's outline
([#249](https://github.com/vocaro/PDFReflowLib/issues/249)) points each entry at a page, and a
link inside the text ([#247](https://github.com/vocaro/PDFReflowLib/issues/247)) can point at any
page of the book: the 9/11 report links its notes across 23 spine documents. Which document holds
a page is decided when that page is packed, which for a forward reference is long after the
reference itself has been serialized and written to disk. A fragment-only `href="#page-400"`
resolves inside the current document in EPUB 3, so it would silently point at nothing.

## Decision

`SpinePacker.pages` — the page-list it already keeps, one entry per source page with the document
that holds it — is the page-to-file map, and both features read it in `EPUBWriter.finish`, after
the last document has closed.

Navigation is built in `finish` already, so the outline needs nothing more than the map. A link
is inside a body that has already been written, so the encoder writes a token,
`href="pdfreflow:page-400"`, and `finish` rewrites it. Only the documents that actually contain a
token are read back and rewritten; the writer records their names as it writes them. A book with
no internal link is written exactly as it was before, and no published book contains a token: an
unresolved one would be an `href` in an unknown scheme, which `tools/check_epubs.py` rejects and
EPUBCheck reports.

The alternative — hold every body in memory until the last page is packed, and patch before
writing — is the whole-document retention decision 0008 removed, for a feature that affects a
handful of documents in a book. The other alternative, a second pass that re-serializes the
blocks, needs the block list that the same decision stopped keeping.

## Consequences

- The streaming contract stands for producers: a block is still final when it is emitted, and the
  writer still holds one body. What is new is that `finish` may rewrite a file it has written,
  which is why this is recorded rather than slipped in.
- The rewrite is bounded by the documents that hold internal links, and each is read and written
  once. The rewritten text is counted against `maximumOutputBytes`.
- The token is padded to a fixed width wider than any href it can resolve to, so the rewrite can
  only shorten a body. Without that, it lengthened them: `SpinePacker` measures a body when the
  block is serialized, and four corpus books' first spine documents finished 12 to 275 bytes past
  the 60,000-byte target once their links resolved. A body the packer measured must not grow
  behind its back, which is the price of writing a document before its destinations are known.
- A page the map does not name resolves to the document the link is in, so a published book
  never carries an href that resolves to nothing. No conversion produces that case: every source
  page emits a marker, so every page is in the map.
- A second output format that resolves destinations gets the same map from the same place rather
  than inventing its own.

## Evidence

[outline-navigation](../../measurements/outline-navigation/record.md),
[converted-links](../../measurements/converted-links/record.md); the streaming contract is
[decision 0008](0008-streamed-blocks-to-the-writer.md).
