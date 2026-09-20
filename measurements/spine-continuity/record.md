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

## Contracts over the written spine

The work above changed where boundaries fall and added `continuedParagraphs` for source-page
boundaries. Neither asserts what a reader sees at a spine-document seam, so on top of `e00432b`
`tools/check_corpus_content.py` gained `spineContinuity`, a case-level expectation checked over
the written spine rather than over one page. `read_spine` now returns one record per spine
document — its archive name, its text with captions excluded, and the source pages it carries,
including the page still open when the document starts. An expectation names the source pages on
both sides of one boundary and the phrases the source sets before and after it; every phrase must
occur exactly once in the whole book, the earlier ones in order inside one document and the later
ones in order inside the very next one, both documents must carry the reviewed pages, and
`contiguous` forbids any word between the two sides.

Four boundaries are pinned, read from the source pages rendered at 100–110 DPI:

| Case | Boundary | What crosses it |
| --- | --- | --- |
| `fed-explained-2021` | page 33, documents 1→2 | the press-conference paragraph, then the "Communicating Policy Regularly and Clearly" heading and its opening paragraph |
| `fed-explained-2021` | pages 122→123, documents 4→5 | the consumer-compliance paragraph ending page 122, then "Interagency Initiatives" and its FFIEC paragraph |
| `wallace-algebra-2010` | pages 155→156, documents 4→5 | the three-variable summary, then the "4.4 Practice - Three Variables" heading and its instruction |
| `wallace-algebra-2010` | page 290, documents 8→9 | one sentence, mid-sentence: "…the larger perfect square is more" / "than it would take to simplify in several steps." |

The page-290 pair is the strongest of the four because the join falls inside a sentence, so any
repetition or loss at the seam is visible in the text itself. It exists only because that sentence
is already split into two paragraphs before the writer runs ([#230](https://github.com/vocaro/PDFReflowLib/issues/230));
the expectation pins the reading order across the seam and the basis records that it does not
bless the split.

Controls, all failing as they should: over built archives, both sides in one document, the reverse
order, a boundary two documents away, a repeated tail, a dropped opening, an inserted sentence,
source pages the surrounding documents do not carry, and nine malformed expectations. Over the
real Fed EPUB, moving the heading and its paragraph back into the previous document scores as no
boundary; repeating the previous document's closing sentence at the head of the next is caught as
duplication; inserting a sentence into the join is caught by `contiguous`; and deleting the
opening paragraph is caught as missing text.

Reviewing the Fed boundaries also found a new instance of the writer class this record describes,
which the carried-heading rule cannot reach: page 94's "Electronic Check Processing" is a genuine
12-point sub-heading that the converter leaves as a paragraph, so it ends one spine document while
its content opens the next ([#228](https://github.com/vocaro/PDFReflowLib/issues/228)).
