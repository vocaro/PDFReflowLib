# Academic front matter, math-variable spacing and algorithm floats (#43)

Tier: deterministic Apple PDF stack, library defaults, macOS 27 arm64 release CLI.
Baseline: branch tip `20c78f3` (after #45 and #40), Xcode 27.0, macOS 27.0. `identity.json`
records the baseline and changed converter hashes and the fixture checksums. The work was first
measured against `95ff5b7`; the merged comparison in this record is identical except where noted.

Corpus: *Replay Clocks* (`corpus/cache/2311.07842v1.pdf`, SHA-256 `1e8172e4…`, arXiv:2311.07842v1,
CC BY 4.0, acmart two columns), with the FAA handbook, The Fed Explained, the 9/11 report, Our Flag
and Wallace's algebra as controls.

## Sub-problem 1: the rotated arXiv stamp was the first heading

Diagnosis. PDFKit returns the stamp as one selection whose bounds are 20 × 353 points at x = 17
(page 1 line 5 of `replay-1-layout.json`, 20-point Times-Roman drawn with `0 1 -1 0 32 232 Tm`).
Its font size clears the 25% heading threshold, so `blocks()` emitted it as the page's first `<h2>`.
`NativeTextReader` exposes no orientation; the line rectangle's aspect is the evidence.

Change. `LayoutReconstructor.rotatedMarginLines` removes, with a `furnitureRemoved` warning
("Rotated margin text is omitted from the reflowed text."), a line of three or more characters at
least three times taller than wide, spanning at least a quarter of the page height, lying in the
outer 12% of the page width, on a page whose horizontal text outweighs its vertical text three to
one. Rotated text elsewhere is never a heading (`isHeadingSize` needs width ≥ height unless the
line has one or two characters) and keeps its paragraph.

Reproducer and controls. `replayFrontMatterDropsTheStampAndRanksTitleAboveAuthorsAndLabels`
(pinned page 1); `rotatedMarginLinesAreStampsOnlyBesideHorizontalText` (left and right stamps,
an inner rotated label kept as a paragraph, a 60-point rotated photo credit kept, a rotated page
where every line is tall, a two-character mark). The `rotated.pdf` fixture still falls back to a
page image (`page.rotation % 360 != 0`) before `blocks()` runs. The first version without the
quarter-height requirement removed the 9/11 report's rotated photo credits (`© Reuters 2004`,
pages 67, 330, 331); the final rule keeps them as before.

Before/after. Page 1 headings `['arXiv:2311.07842v1 [cs.DC] 14 Nov 2023', 'Replay Clocks',
'Ishaan Lagwankar', 'Sandeep S Kulkarni']` → `['Replay Clocks', 'Ishaan Lagwankar', 'ABSTRACT',
'1 INTRODUCTION', 'Sandeep S Kulkarni']`; the stamp text is absent from the EPUB; page 1 gains one
`furnitureRemoved` warning (47 → 48 warnings for the book).

## Sub-problem 2: author names at the title's level

Diagnosis. The title is 17.22 pt, the author names 11.96 pt, the body 9 pt (threshold 11.25 pt);
every spatial heading was emitted at the flat model's level 2.

Change. A typographic heading block carries its font size (`ReflowBlock.headingSize`; tagged
headings carry none). After every page is reconstructed, `LayoutReconstructor.rankHeadingLevels`
sorts all sizes in the document into tiers 7% apart (`headingTiers`), gives the largest tier level
2 and each smaller tier one level deeper (capped at 6), so equal sizes get equal levels on every
page; tagged headings keep their validated level. A first version ranked per page, which gave the
same label style `<h4>` on Replay page 1 and `<h2>` elsewhere; the document pass replaces it. It is
one sort over the headings' sizes with no page geometry, so it is bounded on any book.

Reproducer and controls. Page 1 levels `[2, 3, 4, 4, 3]` (title, author, two labels, author);
`headingTiersRankDistinctSizesAndKeepCloseSizesTogether`: 17.22/17.3 share a tier; 24/14/12 over
10-point prose become 2/3/4 on the opening page, a second page carrying only the 12-point label
style gets level 4 in the document pass (level 2 alone), a tagged level-1 heading keeps its level
through the pass, and a document whose typographic headings share one size gets level 2 for all;
9/11 pages 19 and 65 rank `WE HAVE` / `SOME PLANES` and `THE FOUNDATION OF` above their `1.1` /
`2.1` labels; Fed page 32, Our Flag page 27 and Fed page 50's two-line title keep their headings.
The corpus checker treats every `h1`–`h6` alike, so no heading contract depends on the level.

Before/after (`heading-levels.txt`, counts of `<hN>` in the spine; the ranking changes no page
text, heading set or image — `after2` → `after3` differs on no page):

| Book | `20c78f3` CLI | this tree |
| --- | --- | --- |
| Replay Clocks | h2 4 | h2 1 (title), h3 2 (authors), h4 21 (every section label) |
| Fed Explained | h1 1, h2 152 | h1 1 (tagged), h2 7 (chapter numbers/titles), h3 1, h4 11, h5 36, h6 144 |
| Our Flag | h1 1, h2 48, h3 5 | h1 1, h2 24, h3 7, h4 4, h5 18 |
| 9/11 | h2 80 | h2 3 (cover `THE 9/11` / `COMMISSION` / `REPORT`), h3 54 (chapter numbers, titles, front and back matter), h4 1 (`official government edition`), h5 67 (`1.1`–`13.5` and appendix labels), h6 36 (note-page running heads, see gaps) |
| FAA | h2 42 | h2 1 (cover `2023`), h3 24 (chapter titles), h4 10 (`Chapter N`), h5 145 (section headings incl. seven `Chapter Summary`), h6 7 |
| Wallace | h2 222 | h2 5, h3 168 (section titles), h4 4, h5 48, h6 1 |
| `prose.pdf` | h2 3 | h2 1 (title), h3 2 (sections; two sizes) |
| `lists-code.pdf` | h2 1 | h2 1 (one size) |

Chapter titles outrank section labels throughout (9/11 chapter titles h3 over `1.1`–`13.5` at h5;
FAA chapter titles h3 over sections at h5; Fed chapter titles h2 over subsections at h5/h6), and
each label style has one level across the book. The largest tier is the cover title where a
document has one (`THE 9/11 COMMISSION REPORT`, FAA's `2023`), so chapter titles are h3 rather
than h2 there; the rule was applied as specified without a cover exception. Beyond five tiers the
deepest sizes share h6 (Fed, 9/11). Author names remain headings (a byline is not distinguishable
from a subtitle by typography alone); "title outranks author names" holds.

## Sub-problem 3: run-in section labels

Diagnosis. `ABSTRACT` and `1 INTRODUCTION` are their own PDFKit lines (10.91 pt, 4.8 pt above the
first body line against 2.6 pt ordinary leading) but at 1.21× the 9-point body they sit below the
25% threshold, so the prose branch joined them to the following paragraph. PDFKit reports every
font on this page as Helvetica, so bold and small-caps names are unavailable; `3.1` and
`Limitations of Existing Clocks for Replay` are separate same-row lines split at the 10.9-point
gap, and `4 ALGORITHM FOR REPLAY CLOCK (REPCL)` is a full-measure line.

Change. `sectionLabels` promotes a line at least 15% over the *supported* reflowable body
(`headingBodySize`, the same base the threshold uses) and below the threshold when it starts with
a capital or digit, does not end in `.,;:`, contains letters or is a dotted section number, is not
a list item, has at least 0.8 body of clear space above it (or continues a label of the same size
directly above), and is set in capitals or is at most 90% as wide as the column's prose lines.
Three or more labels ending in a folio token on one page are a contents page and are dropped.
Recognized and synthetic pages are excluded. In `blocks()` a heading directly followed by a
same-row line of the same size joins it (`3.1 Limitations of Existing Clocks for Replay`).

Survey. Lines at 1.12–1.25× body across the 90 pinned fixtures: genuine section headings (9/11
`1.1 INSIDE THE FOUR FLIGHTS`, `2.1 A DECLARATION OF WAR`), 9/11 flight-table headers, the Census
cover, Fed page 13's 8-point lines over a 7-point body, and NBS page 7's inherited-OCR prose at
8.3–8.6 pt over a 7-point body. The shape, space-above and width tests keep the last three out.

Reproducer and controls. Pages 1 and 3 above; `sectionLabelsNeedSizeShapeAndClearSpaceAbove`
(capitals, numbered, mixed-case short titles; a full-measure mixed-case line, `The plasma.`,
lowercase, ordinary leading, body size, a recognized page, `Note:`, `A`, `1) 6p− 42`, a contents
entry, a bullet, `339`, one folio label kept, three dropped, a second label line continuing, a
split number joining); `sourceHeadingControlsKeepTheirSemanticsUnderRankingAndLabels` (NBS page 7
and Fed page 13 gain no headings; algebra page 10 keeps `0.1 Practice - Integers`).

Before/after (Replay Clocks). `ABSTRACT In this work …` → `<h4>ABSTRACT</h4>` + paragraph;
`1 INTRODUCTION According …` likewise; pages 2–11 gain their 16 section and appendix headings
(`2 PRELIMINARIES` … `B CLOCK SIZE`), including the split rows `3.1 …`, `3.2 …`, `7.4 Feasibility
Regions` and the two-line `6 REPRESENTATION OF REPCL AND ITS` / `OVERHEAD`.

Control books (see `page-comparison/`). Text edits are zero in Fed, 9/11, Our Flag and Wallace;
headings change on 34 Fed pages, 66 9/11 pages, 115 FAA pages and 4 Wallace pages, all reviewed:

- Fed: subsection titles (`Anticipated Factors`, `Demand Shocks`, `State Member Banks`, `Coin`,
  `Fedwire Funds Service` …). An intermediate version measured labels against the page body and
  promoted full-width prose on the graphic-dominated pages 46, 54, 75, 77, 103 and 109; measuring
  against the supported body removed every such case.
- 9/11: every numbered section label (`1.1` … `13.5`), the appendix and hearing titles, page 51's
  flight-table title, and page 5's `List of Illustrations and Tables`. An intermediate version
  also promoted the contents entries and a bare `339`; the folio and dotted-number rules removed
  them, and the label rule's list-marker exclusion removed the `1. “WE HAVE SOME PLANES” 1` entries.
- FAA: section headings such as `Wingtip Vortices`, `Chapter Summary` (seven pages), `Stalls`.
  In the merged comparison three FAA pages (33, 49, 201) also move text: on `20c78f3` alone the
  headings `Selecting a Flight School`, `Human Factors` and `Chapter Summary` are joined into the
  preceding figure-caption paragraph; with the label rule they are headings again, placed by their
  own position.
- Wallace: `Solving Linear Equations - Distance, Rate and Time` (page 79) and two `Rational
  Expressions` section titles; page 468's displaced `7.4` section number becomes a heading of its
  own beside the already-heading `Answers - Add and Subtract` (the displaced-heading defect of
  the numbering record). An intermediate version promoted answer-key entries on pages 459–460
  (`1) 6p− 42`); the list-marker exclusion removed them.
- Our Flag: identical page for page. Image counts are identical in every control book.

## Sub-problem 4: spaces after mathematical variables

Diagnosis (`replay-1-text-operators.json`, `dump-spacing` output). Each math variable is a
separate show in the `LibertineMathMI` font positioned by an absolute `Tm`, and the following word
restarts with another `Tm` (`/F182 8.9664 Tf 1 0 0 1 470.315 616.767 Tm [<16>]TJ /F169 8.9664 Tf
0.99 0 0 1 478.665 616.767 Tm [(and)]TJ`). With the glyph's advance from `/Widths` (697/1000 ×
8.9664 = 6.25 pt) the gap to `and` is 2.1 pt = 0.23 em, and for `𝑒` → `must` 2.70 pt = 0.30 em;
PDFKit synthesizes the space before the variable but not after it. The Unicode mathematical-italic
code points come from the fonts' `bfrange` ToUnicode maps (`<16> <49> <D835DC34>`).

Change. `NativeSpacingReader` now records, for every upright show, the decoded text through a
general one-byte ToUnicode map (`unicodeMap`: bfchar and bfrange, ligatures and surrogate pairs),
the measured end (simple-font Widths, font size, Tm/CTM scale and TJ adjustments), the page-space
size and the font identity. `missingSpaces` inserts a space at a boundary between two shows on
one baseline in different fonts, at least 0.15 em apart, with a letter or digit on both sides,
provided the shows spell PDFKit's line exactly apart from its own spaces. Rotated shows and Form
XObjects yield no evidence instead of disqualifying the page; parsed fonts are cached and the
selection bound is 10,000 (pdfTeX reselects a font at every symbol: 309–578 `Tf` per page here).
The Type3 removal path and its gates are unchanged.

Reproducer and controls. `sourceFontBoundariesRestoreReplayClocksWordSpaces` (187 upright shows
decoded and measured, the stamp without evidence, exactly the eight reviewed page-1 lines change,
`𝑓 then the replay clock …` unchanged); three synthetic tests and the CMap-parser test (see
`doc/regression-testing.md`); the seven existing Type3 tests pass with the `/Nested Do` and
selection-bound controls updated to the new semantics.

Before/after. 62 boundaries on 10 of 12 pages, every one after a math variable and confirmed
against Poppler's text layer where checked (`if event 𝑒 must occur before`, `two drones 𝐴 and 𝐵
that`, `where 𝑛 is the number`, `𝑙.𝑒 to every event`, `E is enforced`); no other change in the
page text. Pages 2–5, 10 and 12 were unrepaired until the Form-XObject and selection-bound
changes. Nothing changes in any control book (no font-change gap ≥ 0.15 em between letters that
PDFKit had not already spaced). Residual: `𝐵 before𝐶 even` on page 3 keeps `before𝐶`, a 0.98 pt =
0.11 em gap that Poppler (0.1 em threshold) splits; the threshold stays at 0.15 em to leave kerns
and italic corrections alone.

## Algorithm floats (pages 3–5)

Diagnosis. Each listing is set between three thin full-column rules: caption `Algorithm N …`
directly beneath the top rule, a second rule directly beneath the caption, a closing rule below
the last line. The rules were decoration or isolated crops, the `=` lines became formula crops,
the `2: while 𝑆 ≠ 𝜙 do` line a list item and the rest prose, so lines were spread over text and
crops.

Change. `algorithmFloats` seeds one region from the second rule to the closing rule (same
x-extent within 3 pt, ink midlines ± 1 pt) for each caption in that geometry, and drops the top
rule as the caption's decoration. The caption stays text.

Reproducer and controls. Page 3 (one region, nine listing lines inside a crop under 90 pt tall,
caption outside); page 4 (three regions, all 32 numbered lines inside, captions and the prose
`… in Algorithm 2.` outside); synthetic controls (no closing rule → lines reflow, caption not
under its rule, `Table` caption, mismatched extent); algebra pages 16/289, Our Flag 27, USGS 1 and
NBS 7 have no floats; Wallace's derivation crops and every control book's image counts are
unchanged.

Before/after. Page 3 images 9 → 8, page 4 14 → 7, page 5 17 → 14; the listing lines leave the
page text (`1: Input: Message 𝑚 2: …` gone) and appear once each inside their float's image.

## Verification (merged build, HEAD `20c78f3` plus this working tree)

- `swift test`: 267 tests pass (253 at the tip plus 14 new; `NativeSpacingTests` 11,
  `AcademicFrontMatterTests` 10).
- `python3 -m unittest discover -s tools -p 'test_*.py'`: 159 tests OK.
- `scripts/check-all.sh --fast`: exit 0 (267 Swift, 159 Python, 8/8 concurrency trials, 6 fixture
  conversions, 13 policy conversions with 22 rejection/cleanup cases).
- `tools/run_corpus_regressions.py --converter .build/release/pdf-reflow --epubcheck
  /opt/homebrew/bin/epubcheck --output <new dir> --case …`: Replay 55, Fed 45, Our Flag 59, 9/11 71,
  Wallace 63 and FAA 61 content checks pass with EPUBCheck, progress and memory gates
  (`lane-summaries/`, all rerun on the document-wide ranking build; `replay-fed-flag-first-run.json`
  is the first run, in which Fed and Our Flag passed and Replay failed on four since-removed
  `absentText` entries that the checker's flattened page text could not distinguish from a heading
  followed by its paragraph). The Replay contract grows from 20 to 55 checks; the lane now has 585 checks
  on 124 pages (the tip's documentation said 549 on 123; counting every expectation entry at
  `20c78f3` gives 550 on 124, so the tip's figures were already one page and one paragraph short).
- `page-comparison/`: `tools/check_corpus_content.read_pages` text, heading, paragraph and image
  comparison of every page of the six books between the `20c78f3` CLI and this tree's CLI.

## Remaining gaps

- Heading levels rank sizes document-wide, so a cover title takes h2 and chapter titles h3 in
  9/11 and FAA; with more than five tiers the smallest sizes share h6 (Fed, 9/11). Author names
  stay headings (h3). 9/11 note-page running heads that furniture removal leaves on isolated
  pages (`554 NOTES TO CHAPTERS 9-10`, `NOTES TO CHAPTER 11 561`) now become h6 labels instead
  of paragraphs.
- A 0.11 em gap after prose before a math variable (`before𝐶`) stays joined; consecutive shows
  without a positioning operator still disqualify a page for both spacing repairs, as before.
- Contents pages are recognized only through folio-ending labels; `List of Illustrations and
  Tables` and `CONTENTS` on 9/11 page 5 remain headings. A displaced dotted section number
  (Wallace 468's `7.4`) is a heading on its own when reading order separates it from its title.
- Two-line headings remain two heading blocks (the existing convention). Algorithm floats are
  recognized by the `algorithm` package's three-rule geometry only; `algorithm2e` boxes and
  captions above a single rule are not covered.
