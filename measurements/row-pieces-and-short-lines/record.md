# Split radical rows and paragraphs set off by added space (#95, #71)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 (26A428) arm64, Xcode 27.0
(27A266a), release CLI. Work started on `213c944` and was merged forward to `0d4f24e`, `ffc45a4`,
`9884ed6`, `bc5eb8c` and `36c6265`. The six-case lane compares `9884ed6` with `9884ed6` plus
these changes. The survey of the other English cases compares `36c6265` with `36c6265` plus the
final changes. Converter, probe, source and fixture hashes are in `identity.json`. No source PDF
or full EPUB is committed.

## What was wrong

**#95, Wallace pages 288, 289, 299.** PDFKit splits a prose row at an inline radical, and since
`eb0197c` those pieces reflow as text. Each piece opened a paragraph of its own. A piece that
starts with the radical sign has a rectangle raised by the sign's bar, so it sorted a line early.
Page 288 carried 19 paragraphs where the source sets 9 (`√ on` before `Not all numbers…`,
`√ is currently undefined…` before `The final example,− 81`, `√ by spliting` / `We can use…` /
`36· 5` as three blocks). The fixtures show why rectangle overlap alone cannot rebuild a row. Radical
signs extend a 12-pt row's rectangle to 20–30 pt, so page 288's last two rows overlap by 14.4 pt,
more than `sameRow`'s half-height test needs. Pieces of one row meet in three ways:

- a gap (`because 52` + `= 25 we say…`, 2 pt; `…written as` + `25 √ .`, 13.9 pt);
- a staggered overlap where the sign sits at the join (`…if we found 8` + `√ on`, 16 pt;
  `…like 180 √ into 36· 5` + `√ . There are sev-`, 34.8 pt);
- a narrow radicand lying inside the span of its sign's piece (`x8` inside `√ = x4, because we`,
  page 290; `36· 5` inside `√ by spliting`, page 288).

**#71, USGS copper page 2.** The issue's premise is sub-threshold spacing. The fixture shows the
source actually leaves a full blank line: the baseline pitch is 22.1 pt against 11.04-pt leading.
Its line rectangles are 13.76 pt tall, though, so lines inside a paragraph report a box gap of
−2.72 pt and the blank line only 7.9 pt, under the prose branch's `body * 0.9` = 9.07 pt. (The
#60 record read this as "about 0.3 pt of paragraph spacing"; it is the rectangles' overhang.) The
column is ragged-right. Line ends run 524.6–565.7 pt, and `…by yearend 2024.` ends at 532.8 pt,
6% short of the widest line. The suggested justified-column test (a previous line more than 15%
short in a column whose lines reach the right edge) therefore cannot fire on the reproducer, and
ragged columns were to be excluded anyway. Added space measured against the paragraph's own
leading is the evidence the page carries.

## What changed

`Sources/PDFReflowLib/LayoutReconstructor.swift` (no public API or default changes):

- `joiningRowPieces(_:images:body:)` runs in `blocks()` right after `joiningMarkerPieces`, before
  classification. Candidate pairs are untagged, non-monospaced, at body size (±15%), and overlap as
  `sameRow` does. They must also meet in one of three ways:
  - A gap of at most 1.5 font sizes, where the right piece does not start on an edge two other
    lines share (a column or table cell). A gap wider than a font size also needs a mathematical
    sign in the left piece's last two tokens or the right piece's first two, or a piece that is
    mathematics alone.
  - A staggered overlap of at most four font sizes, each piece extending more than half a font
    size past the other.
  - A radicand lying within the span of its sign's piece: narrow, without words, clear of the
    container's left edge, and chosen from the radicand's side only.

  No preserved image may stand between the pieces. Each piece proposes the candidates it overlaps
  most vertically, and proposals merge strongest first. A merge is refused when every piece of the
  growing row no longer shares a vertical band at least half a font size tall.

  A joined row is kept only when:
  - it carries a sign from `∫∑∏√∂∇≈≠≤≥∞=·×÷±−`;
  - it reads as prose on its paragraph's measure (`isProseRow`, now also callable with explicit
    pieces);
  - it does not turn into a list line that its opening piece was not.

  The joined line concatenates the pieces by centre with their styles. Its rectangle spans the
  pieces horizontally and runs from the highest bottom edge up one ordinary line height (the
  median height of the page's lines at that size), so the paragraph rules see the row's leading.
- `opensSpacedParagraph` in the prose branch opens a paragraph when all of these hold:
  - the gap exceeds the gap the open paragraph's last line was attached at by at least half the
    body size;
  - the previous line ends a sentence;
  - this line opens with a capital, on the same left edge within half a body size, in the same
    type within 10%.

  The right edge is never consulted. The sentence-ending test (past closing quotes and a raised
  reference marker) is factored out of `opensSection` as `endsSentence` and shared.

## Tests

`Tests/PDFReflowLibTests/RowPiecesAndSpacedParagraphTests.swift` (8 tests; 13 new fixtures from
the pinned Wallace source, all reviewed against renders):

- `sourceRadicalRowPiecesJoinTheirParagraphsInOrder` (288),
  `sourceOpeningRadicalRowJoinsTheParagraphBeneathIt` (289), `sourceRadicalRowClosesItsNoteParagraph`
  (299).
- `sourceAlgebraRowsJoinOnlyWithinTheirRow`. Rows that must not join: pages 9, 120, 180 (a short
  next-row line inside a tall full line), 189 (an annotation beside its step) and 321 (a join that
  would read as a list). Rows that must join: 198 and 212 (chains refused by the band), 185, 290,
  292 and 305 (the other guards' allowances), and 318.
- `sourceExerciseColumnsKeepTheirRowPiecesApart`: block counts of 15 exercise, answer, derivation
  and grid pages, with and without crops, equal to the reconstruction at `0d4f24e` (unchanged at
  `ffc45a4`).
- `syntheticSplitRadicalRowJoinsOnlyAsProse`: a join and its twin across a crop; no sign; a
  column edge; a wordless next-row line at the left edge; exercise answers.
- `sourceUSGSCOMEXParagraphOpensUnderTightBoxSpacing`, `syntheticBlankLineOpensAParagraphOnlyAfterASentence`
  (justified and ragged previous lines; controls: no added space, less than half a body size, no
  sentence end, lower-case opening, indent).

Updated expectations:

- `SectionLeadInTests`: COMEX is now distinct from the Events section. The bold-emphasis controls
  now add 4 pt of space (4 pt over the leading, the lead-in rule's regime, under this rule's half
  body size), because at 8 pt they described a blank line. `leadInPage(spacing: 4)` is added as a
  positive lead-in case. The control-page counts change for `fed-32` (11, 9 → 12, 10: the box's
  `For more information…` paragraph, confirmed on the render) and `algebra-289` without crops
  (36 → 34: the opening sentence).
- `InlineFormulaProseTests`: comment only.

`corpus/regressions.json`: USGS page 2 `distinctParagraphs` (Events / COMEX), and Wallace
`paragraphs` on pages 288, 289 and 299 plus `distinctParagraphs` on page 429, each with its basis
sentence updated.

## Survey and before/after

Every gated English case was converted with both converters, one case per call, and compared with
`compare_conversion_runs.py --allow-different-converters`. No provenance errors and no OCR-page
differences. Every changed page was compared paragraph by paragraph, and its non-space characters
checked as a multiset (none lost or gained anywhere). The pages were reviewed against Poppler
renders.

| Case | Pages | Changed | Review |
| --- | --- | --- | --- |
| wallace-algebra-2010 | 489 | 35 | below |
| usgs-mcs2025-copper | 2 | 1 | page 2: COMEX paragraph split from Events (15 → 16 paragraphs) |
| fed-explained-2021 | 135 | 3 | 47 `Assets (billions of dollars)` split from the table title; 58 `For a fuller discussion…` its own paragraph; 91 the 1913 timeline entry split from 1918 (later entries still share a paragraph) |
| gpo-911-2004 | 585 | 2 | 190 `Requirements for a Successful Attack` split from the paragraph above; 300 the bold run-ins `The New York Police Department.` and `The Fire Department of New York.` open paragraphs |
| scotus-loper-bright-2024 | 114 | 0 | justified control |
| faa-phak-8083-25c | 522 | 0 | |
| dga, our-flag, cdc, blue-book, census, nbs, arxiv | 10, 56, 42, 312, 20, 7, 12 | 0 | `survey/` |

Wallace. Every change is character-preserving; no image, navigation or report field changes:

- **#95 row joins** (21 pages): 178, 185, 192, 202, 203, 212, 264, 288, 289, 290, 292, 295, 299,
  305, 322, 337, 366, 388, 406, 410, 430. Page 288 goes from 19 to 9 paragraphs and page 289's
  opening now joins `several ways…`. Page 337's `− 2x− 7 = 0…` piece is no longer a false list
  line.
- **#71 splits** (12 pages): 7, 43, 48, 64, 67, 196, 231, 253, 255, 376, 383, 429. These are World
  View Notes, `Objective:` lines and paragraphs set off by half-line spacing; 48, 255 and 429 were
  confirmed on renders.
- **Both** (2 pages): 198, 318.

**Controls.** Our Flag's table rows, 9/11 page 451 and FAA's multi-column rows are unchanged
page for page. So are the algebra exercise columns (10, 26, 438), list-marker pieces (#69) and
heading row pieces (#55, #76), whose tests pass unchanged. No ragged or justified continuation
line (#39, #45) was split: Loper Bright, FAA and the citation and continuation tests are
unchanged.

**A first candidate joined across rows.** It produced order regressions on pages 9, 120, 180,
189, 198 and 212, and a cross-row join on 321. Those pages were captured, diagnosed and turned
into the "must not join" checks above. The shared band, the sign-at-join condition, the
left-edge and wordless radicand condition, the list-line guard and the half-em stagger came from
that review.

## Verification

- `swift test`: 471 tests pass on the final tree (463 at `36c6265` + 8).
- Negative control ([log](before-tests.log.gz)): the new and changed suites run against
  `bc5eb8c`'s `LayoutReconstructor.swift`. 9 of 21 tests fail with 37 issues. Every reproducer,
  the synthetic positives, the COMEX checks and the positive algebra joins fail. The baseline-count
  and do-not-join controls pass.
- Guard mutations ([log](guard-mutations.log)): each of the 18 guards is killed by at least one
  test. The left-edge radicand guard first survived (page 9 is also refused by the list-line
  guard); a synthetic control was added and the mutant rerun.
- `scripts/check-all.sh --fast` on the final tree: 471 Swift tests, 204 Python tests, 8/8
  concurrency trials, 6 fixture conversions with identical repeat bytes, 13 policy conversions and
  22 rejection/cleanup cases pass.
- Corpus lane: all six cases pass gates and contracts with the candidate (USGS 50 checks, Wallace
  136). With the baseline converter, USGS fails only the new COMEX check and Wallace only its six
  new checks. The final converter (`36c6265` + changes) also passes Wallace and USGS.

## Remaining gaps

- Row pieces keep PDFKit's own order inside a row (`36· 5 √` for √36·5, `25 √ .` for √25.); the
  joined text is in reading order by piece, not by glyph.
- A line whose tall rectangle overlaps the next row by more than `0.4 × body` still breaks the
  paragraph after it: Wallace 180 `…This is shown in the next` / `example.`, 318 `…equa-` /
  `tion again…`, 321 `If i is` / `√ , and it is…`. Row joining does not change such a line's
  rectangle unless it was split.
- Page 321's radicand `− 1` stays apart because joining it would open its row with a list
  marker (`isList` reads `− ` as a bullet).
- A paragraph set off by added space whose first line follows a one-line paragraph, or a line
  not ending in `.`, `!` or `?`, is not covered: the rule needs the open paragraph's leading and a
  sentence end.
- A heading that shares its paragraph with the text below it (9/11 page 190 `Requirements for a
  Successful Attack As some of…`, Wallace 198 `Multiplying in rows A third method…`) is split from
  the paragraph above only.
- Fed page 91's timeline entries after 1913 still share one paragraph; the entries' years are
  elsewhere in reading order.

## Defects to file

- **A tall inline radical or superscript rectangle breaks the paragraph at the next line.**
  Wallace pages 180 and 321 (also seen on 318): the paragraph gap is measured between rectangles,
  and the line holding the inline expression overlaps the next line by 6.1 and 6.2 pt, past the
  `0.4 × body` (4.8 pt) tolerance. Expected: the continuation stays in its paragraph.
- **A leading minus sign reads as a list bullet.** `isList` matches `− ` (U+2212 followed by a
  space) at the start of a line, so a split mathematical row such as Wallace 321's `− 1 √ , and it
  is…` would be preserved as a list line. Expected: a minus followed by a digit or variable is
  not a list marker.
