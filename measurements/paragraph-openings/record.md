# Paragraph openings set further out than their wrapped lines (#147)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 (26A428) arm64, release CLIs.
Baseline: `ec22aff` (#131's line-end compounds, over the #135 drop-cap join; converter `14e4014c…`);
candidate: that tree with this change (`cb2e0854…`). Corpus figures are `tools/run_corpus_regressions.py`, one case per call, with
the compiled raster/Vision probe and `--execution-context host-terminal`, then
`tools/compare_conversion_runs.py --allow-different-converters --detail` (summaries in `lane/`).
Paragraph counts per page are read from each EPUB with `check_corpus_content.read_pages`
(`paragraph-survey.json`). No PDF or EPUB is committed.

## Diagnosis

Our Flag's baseline EPUB has 487 paragraphs; about 50 of them end mid-sentence where the next one
opens in lowercase (`…the British fleet bom` / `barded Fort McHenry…`). Its body is 9-point
StoneSerif at 12-point leading on a justified measure, and three layouts break the spatial paragraph
rule, which attaches a line only on a left edge within one and a half bodies (13.5 points) of the line
above:

- **First-line indents of two ems.** Each paragraph opens 18 points in (`Strong evidence indicates
  that Francis Hopkinson of New Jersey, a` at x 82 over `signer of the Declaration…` at 64, page 7),
  so the opening line always stood alone.
- **Drop caps.** A section's first line carries the 43.5-point initial; its `rect` spans the initial's
  depth (y 498–543) and only its `readingRect` is the body row. The next two lines are set beside the
  initial, 45 points in (x 109.8), and the text returns to the edge below it. The vertical gap from
  the ink rectangle (−33 points) and both edge changes split the paragraph twice: `During the night…
  bom` / `barded…watched the` / `attack from the deck…`.
- **Tags one line per group.** Page 12's quotations are tagged as a paragraph per line. `wraps`, which
  rejoins groups split at a wrapped line (#89), asks for one left edge, so each quotation's indented
  first line stayed a paragraph of its own.

The book's reading list (pages 53 and 54) sets hanging-indent entries, 18 points in, with 4 points of
space between entries and none inside one; every wrapped line was its own paragraph too.

Nothing else in the per-book estimates misled it: the page body is 9 points, the leading is ordinary
(gap 3.1 points), and structure validates where tags exist. Books that joined correctly indent less
than 1.5 bodies (the Fed, FAA, Wallace) or mark paragraphs with space alone; 9/11's note pages indent
further paragraphs past that bound, and the note hand-off (#11) already joined those.

## Change

`LayoutReconstructor.blocks` records the open paragraph's opening line while it is the paragraph's
only line, and whether something other than its edge set it apart from the line above: a gap outside
ordinary leading, a line that does not reach the new line's right edge within a body, a sentence end,
a non-wrapping line, or no line above in the paragraph flow (a tag, heading, image or the top). A
line whose left edge differs by more than one and a half bodies still continues the paragraph, at
ordinary leading and in the same size, when the upper line reads as words (`isWordy`) across at least
twelve bodies and (`continuesOpening`):

- the paragraph opened on a drop-cap line (`readingRect`) that the upper line's right edge matches, and
  the line stands beside the initial (in from the drop-cap line's edge by more than 1.5 bodies and at
  most 1.5 times the line's full height, its middle within the initial's depth) or returns to the
  drop-cap line's edge from a line beside it; the gap under a drop-cap line is measured from its
  reading rectangle;
- or the upper line is an evidenced opening indented 1.5–3 bodies past the line, opens with a capital
  (past quotes and brackets), and at least three lines on the lower line's edge end where it does, the
  lower line not reaching further;
- or the upper line is an evidenced opening on the edge, the line hangs 1.5–3 bodies in, three lines
  on the upper line's edge end where it does, and the space above the upper line (to the nearest line
  over it) exceeds the leading beneath it by 0.4 body.

For tags, `wraps(_:onto:opening:)` accepts an upper line indented past the lower line by more than
half its size and at most three bodies when it is its block's only line (an untagged evidenced
opening, or a tagged block's first line), opens with a capital, reads as words, is no heading, the
lower line opens lowercase or follows a hyphen or slash, and at least three lines on the lower line's
edge end where the upper line does; the pair must otherwise wrap as two lines on one edge. The
converse path (a tagged group into an untagged line) hands its single-line opening to the spatial
rules. `structuredOrder` still calls `wraps` without `opening`, so reading order is unchanged.

## Survey

English lane cases (13; Warren and NOAA stay excluded, the Arabic and Chinese cases are out of scope):

| Book | Paragraphs before → after | Pages changed | Review (renders at 50–130 DPI and text diffs) |
| --- | --- | --- | --- |
| Our Flag | 487 → 417 | 5, 7, 8, 9, 10, 11, 12, 13, 14, 16, 26, 27, 28, 29, 30, 31, 46, 47, 48, 49, 50, 51, 52, 53, 54 | Every change joins a drop-cap opening, a two-em indented opening, a quotation's first line or a reading-list entry's hanging lines to the text it wraps onto; every remaining break on those pages is a source paragraph break. Pages 51 and 52 are the bold-capital pledge and creed openings; page 30's `…at the U.S. Capitol.` / `The present flag…` is one paragraph in the source. |
| FAA | 6545 → 6544 | 510 | Glossary `V_YSE.`: `Best rate-of-climb speed with one engine inoperative.` (after the split-off subscripted term, 27 points in) joins `This airspeed provides…`, as the source sets one entry. |
| Blue Book | 23262 → 23258 | 14, 102, 281 | Page 14's footnote (1) and page 102's items (5) and (8) join their hanging wrapped lines; page 281's form preamble joins its indented first line. |
| NBS | 135 → 133 | 1, 7 | The indented abstract and `Relativistic effects…` (page 7) join their first lines. |
| Census | 249 → 248 | 17 | Measured on `ec22aff`, where page 17 was OCR: reference [10]'s hanging line joined it. See the `a4b0f30` rebase below. |
| Fed (722), 9/11 (3625), Wallace (3638), DGA (95), CDC (254), USGS (24), SCOTUS (402), Replay Clocks (173) | unchanged | none | — |

Each comparison reports only these pages as changed (text, markup and paragraph ids), plus pages whose
paragraph ids shift after a removed paragraph (`idOnlyShifts`); no image, warning, navigation or
report change anywhere. Every case passes its lane.

The change was first measured on `4fc3115` against every English lane case with the same changed
pages and joins (Blue Book 23263 → 23259, Census 251 → 250, the rest as above); #131 changes the
baseline counts, not this change's pages.

Rebased onto `a4b0f30` (#143 decodes the Census glyph-index fonts, so pages 3 and 17 are native text), the
Our Flag, Census, Blue Book, NBS, FAA and 9/11 lanes were rerun against an `a4b0f30` baseline (converters
`eb16c05b…` and `5f8868ea…`). Our Flag, Blue Book, NBS, FAA and 9/11 change exactly as above. Census goes
249 → 247 on pages 3 and 17:

- page 3's paragraph after the income list opens on a first line indented past the list's edge
  (`The file also has match code…from the` / `public-use CPS file.…`) and now joins, as the source sets
  one paragraph;
- on page 17 the natively read references set the marker 21 points left of the text and their wrapped
  lines on the text's edge, with the same 11-point pitch between entries as within one. The first
  reference, under the `References` heading's space, joins `Incomplete Data via the EM Algorithm`;
  [10] (and [9], [11], [14]) have no space above them and stay split, as they were on the baseline. The
  earlier [10] join rested on OCR geometry and no longer applies.

A first `a4b0f30` baseline run also differed on Census page 4, where Vision failed on the baseline
(`ocrFailed`, page image fallback); a rerun of the baseline recognised it and the page matched.

Two intermediate candidates were rejected on review. A first cut without the prose guards joined Blue
Book page 70's scanned table header `Identification 1 2 3 4 5 6 7` (stretched to the page edge by a
margin mark) to its first row, and page 142/143/244's stub `Evaluation` to the labels below, which
happen to end together; `isWordy` and the twelve-body width exclude them. A character-density guard
copied from `wraps` also dropped the join on Our Flag page 51, whose bold capitals are loosely
justified, so the rule does not use it.

## Tests

`ParagraphOpeningTests.swift`, on Our Flag captures replayed through `NativeTextReader` with their
tags (`our-flag-page-5`, `-10`, `-12`, `-49`, `-54`, and the existing untagged `flag-7`) and Blue
Book captures (`blue-70`, `blue-142`):

- joins: page 7's indent and drop cap, pages 5, 10 and 49's drop caps (page 49's second line is
  listed before the drop-cap line), page 49's indented opening, page 12's quotations group to group
  and group to untagged line, page 54's entries;
- kept breaks: `…eight.` / `Strong evidence`, `…the poem.` / `Years later`, each quotation, and
  consecutive reading-list entries;
- controls: Blue Book's stub and header row; synthetic 9-point columns where the opening follows a
  full line that runs on, is indented past three bodies, stops short of the measure, opens in
  lowercase, is a narrow stub of words, or is a hanging line with no space above its entry.

Mutations, each run against these tests: disabling the indent rule fails 3 tests (4 expectations);
dropping the opening evidence, the three-body bound, the capital or the measure each fails the
matching synthetic control; disabling the drop-cap branch or measuring its gap from the ink rectangle
fails the Our Flag test (4 expectations); dropping the hanging rule's space test fails the unspaced
control, and disabling the hanging rule fails both hanging tests; dropping `isWordy` fails the Blue
Book header control, the twelve-body width the narrow stub; disabling the tagged opening fails the
quotation test (3 expectations), and dropping the converse path's opening fails it once.

`NoteContinuationTests.furtherParagraphAtTheIndentStaysItsOwnParagraphButKeepsItsWrappedLines` kept a
negative control showing 9/11 page 498's further note paragraph split after its first line without
the note hand-off (#11); that indented opening now joins without the hand-off too, and the control says so.

## Contracts

`corpus/regressions.json`, Our Flag: 14 paragraph phrases spanning the joins on pages 5, 7, 10, 12,
49, 51, 53 and 54, and four `distinctParagraphs` breaks (`…the poem.`/`Years later`, `Years later`/the
quotation, `…eight.`/`Strong evidence`, and two page-54 entries). The baseline fails the 14 phrases and
the page-54 break (whose phrase does not exist as one paragraph); the other three breaks pass on both.
The candidate passes all 104 Our Flag checks. Census adds the page 3 and page 17 joins as paragraph
phrases; the `a4b0f30` baseline fails both and the candidate passes all 73 Census checks.

## Limits and follow-ups

- The joins expose line-end hyphens PDFKit dropped (`bom barded`, `fab rics`, `sym bolize`, `mean ing`,
  already inside paragraphs as `alter nately`, `real ity`, `PEO PLE`): the hyphen policy (#131).
- Page 12's `…on the American flag,` / `stars and beams of many-colored light shine out together ....”`
  stays split because `wraps` rejects any line holding `...` (a leader guard), and the source tags that
  line with the next paragraph's `In a 1917 Flag Day message…`.
- Page 54's untagged entries on one edge (`Smith, Whitney…1975.` / `The Star-Spangled Banner.-…`,
  `Waller`/`Wannamaker`, `Weil`/`Werstein`, page 53's `Devine`/`Fradin`) remain joined: the 4-point space
  between them is under the ordinary threshold and a single-line paragraph has no leading of its own
  for the added-space rule (#71).
- The rules need an opening line that fills a justified measure; a two-line paragraph whose indented
  first line is short, or a ragged-right column, is not joined. An indented opening that fills the
  measure and ends a sentence before a new unindented paragraph at ordinary leading would be joined;
  no corpus page sets that.
