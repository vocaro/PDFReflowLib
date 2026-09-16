# Spine and paragraph continuity

Part of [#27](https://github.com/vocaro/PDFReflowLib/issues/27): chapter continuity across
spine-file boundaries. macOS 27.0 (26A428), arm64, Xcode 27.0 (27A266a), release CLI, library
defaults. Before = the complete corpus gate at `29ca743`; after = the complete gate with this
change. Both ran `scripts/check-all.sh --corpus` on the same checksum-pinned sources.

## What the boundaries showed

Spine files in the gated corpus are split by the 60,000-byte body target (only the excluded NOAA
report has validated chapter starts). Reviewing every boundary in the 15 converted documents
found two different classes of discontinuity:

- **Writer:** a spine document could end with a heading whose content began the next document.
  The Fed report (page 33, "Communicating Policy Regularly and Clearly"), the USCIS Arabic guide
  (page 30) and Wallace algebra (page 343, "Quadratics - Quadratic Formula") did. In a reading
  system the heading sits alone at the end of one document.
- **Reconstruction:** paragraphs that continue onto the next source page are often split before
  the writer runs, and printed folios can absorb continuation text. These are tracked in
  [#45](https://github.com/vocaro/PDFReflowLib/issues/45) with visually confirmed pages (FAA
  24→25, Fed 11→12, Replay Clocks 1→2; 9/11 folio `108` on pages 126→127). A paragraph never
  crosses spine files, so a spine split can only land where reconstruction already ended one.

## Change

On a size split, `EPUBWriter` carries a trailing run of headings (with standalone page markers
among them) into the next document, and moves their page-list and contents entries with them.
A document that holds only such headings stays open for their content, so a heading followed by
an oversized block shares its document. Only runs of at most 6,000 bytes (a tenth of the target)
are kept; longer heading runs pack normally. Validated chapter starts are unchanged.

`tools/check-epubs.py` now rejects any non-final spine document ending with such a heading run,
and allows those headings (and one source marker) before a single oversized block. Heading sizes
are measured in the exact serialized markup, like the body target.

`tools/check_corpus_content.py` gains `continuedParagraphs`: `{"end", "next"}` phrases must be in
the same paragraph element on page N and page N+1. Six source-reviewed checks protect correct
joins: FAA 35→36 and 116→117, Wallace 18→19 and 43→44, 9/11 20→21 and 24→25 (strip renders of
each page edge were compared against the source).

## Evidence

- All 191 Swift tests also pass on the iOS 27 Simulator (iPhone 18 Pro, `xcodebuild test`).
- Four new Swift tests (`SpineWriterTests.swift`). Three fail on the previous writer (carried
  heading and navigation, heading exactly filling a document, heading before an oversized block);
  the long-heading-run control passes before and after.
- Python negative controls: separated headings (including across a page marker and with an
  earlier heading in the document) fail; the final document, long heading runs and headings
  opening a document pass; oversized headings or non-heading blocks before an oversized block
  fail. Paragraph continuation rejects split paragraphs, continuation outside the element, phrases
  on the wrong side of the marker and malformed expectations.
- On the *before* outputs, the new spine check fails exactly Fed, USCIS and Wallace, and passes
  the other twelve documents.
- `comparison.json`: for all 15 documents, concatenated spine bodies, navigation (ignoring file
  names) and image entries are identical before and after. Only Fed (documents 1-2), USCIS (1-4)
  and Wallace (9-14) change boundaries; every document count is unchanged. All pass the new
  spine check after the change.
- `release-gate.log.gz` / `corpus-summary.json`: 191 Swift tests, 106 Python tool tests, fixture
  and policy conversions, the structure-memory gate, and all 15 complete corpus conversions pass
  (Warren and NOAA remain excluded under #5). The runner loaded contracts before the six
  continuity checks were added (341 checks); re-running `check_evaluation` on the same outputs
  with the final contracts passes all 347 checks on 85 pages.

The #30 case baselines under `measurements/<case>/` are historical receipts from `29ca743`; the
USCIS guide's EPUB identity changes here because of the moved heading, with identical text.
