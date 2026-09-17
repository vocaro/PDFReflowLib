# Tall inline-expression lines and a minus sign read as a bullet (#109)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 (26A428) arm64, Xcode 27.0
(27A266a), release CLIs. Work began on `d333b4d` and was merged forward to `785a974`, `63680df` and
`de0df61`. Every figure below compares an unmodified `git archive de0df61` release build with
`de0df61` plus these changes. The lane also ran on `785a974` and `63680df` with the same result
(`identity.json`). Converter, probe, source and fixture hashes are in `identity.json`. No source PDF
or full EPUB is committed.

## What was wrong

**Tall lines.** Wallace sets 12-point prose at 14.4-point leading in 12-point rectangles, a box gap
of +2.4 points. Some inline glyphs make a line's rectangle taller:

- The book's minus and times glyphs drop the rectangle 8.5 points below the type (20.5 points tall).
- A radical's bar raises it (21.6 points).

That line then overlaps its neighbour by 6.1 points. The prose branch's lower bound, `-0.4 × body`
(4.8 points), treated this as a new block. Examples:

- page 180: `…This is shown in the next` / `example.`;
- page 318: `…both sides of the equa-` / `tion again…`, then `And if this` / `pattern continues…` and
  `4 diﬀerent possible` / `answers in this cycle…`;
- page 321: `If i is` / `√ , and it is…`.

The fixtures show the same geometry on page 9, where the closing sentence was cut into five paragraphs
(`multipli-` / `cation`, `sep-` / `arates`, `=−` / `10`, `=` / `21.`), and on page 120 (`less than
or` / `equal to`). It is not a baseline measure. The inflated edge is either one, and the type's own
edge stays at the ordinary line height.

**Minus.** `isList` reads `^− ` as a bullet. On page 321, PDFKit extracts the radicand `− 1` apart from
its radical piece `√ , and it is in the denominator…`. `joiningRowPieces` refused that row because the
joined text `− 1 √ , …` would become a list line its opening piece was not. The row stayed split, and
`− 1` became a `<pre>` list item.

**Where `isList`'s minus form is relied on.** `tools/minus-survey.swift` reads every PDFKit line of
13 English corpus PDFs (`survey/counts.tsv`, Wallace lines in `survey/wallace-lines.tsv`).

- Only Wallace opens a line with U+2212 plus whitespace: 1,618 lines.
  - 1,455 continue with a digit and 138 with a single-letter variable.
  - 12 continue with other characters (`− (− 8)· 3`).
  - 13 continue with a run of letters. Three of these are the license's bullets on page 2
    (`− Your fair dealing…`, `− The author’s moral rights;`, `− Rights other persons…`), the corpus's
    only U+2212 bullets. The other ten are mathematics (`− πr2`, `− mn− 30n2`).
- FAA, Fed, 9/11, USGS and Loper Bright have none. FAA bullets are `•`.
- DGA, Blue Book, CDC and NBS open lines only with hyphen-minus, which this change does not touch.

The 1,605 math lines are exercise, answer and derivation steps: `− 3x− 3y=26`, `− 24 Our Solution`,
`− 18 <− 12`. As list lines they stay separate `<pre>` blocks. The exercise-column counts in
`RowPiecesAndSpacedParagraphTests` rely on that. Narrowing `isList` itself would reflow those lines
into paragraphs, so the exemption is scoped to joined rows.

## What changed

`Sources/PDFReflowLib/LayoutReconstructor.swift` (no public API or default changes):

- **Overlap tolerance.** The prose branch's lower gap bound grows by the extra height of either line.
  - Extra height is the rectangle's height over the page's ordinary line height at that size. That
    ordinary height is the median rectangle height at that size, now `ordinaryLineHeight`, shared
    with `joiningRowPieces`.
  - Extra height counts only when all of these hold:
    - it exceeds a quarter body size;
    - the rectangle is at most twice the ordinary height (taller is a display);
    - the line reads as prose on its paragraph's measure (`isProseRow`).
  - The upper bound (`< 0.9 × body`) stays on the raw rectangles.
  - A gap involving such a line is not recorded as the paragraph's leading. The leading measured
    before it carries over. Otherwise the -6.1-point gap would make the next ordinary line look like
    added space to `opensSpacedParagraph` (#71). Page 318's `Multiplying again…` would have opened a
    paragraph.
- **Minus rows.**
  - `joinedRows` (behind the unchanged `joiningRowPieces`) keeps a joined row that becomes a list line
    when two things hold. Its opening piece was not a list line. What reads as a marker is a minus
    before a number or single-letter variable (`opensWithMinusSign`: `^−\s+(?:[0-9]|[A-Za-z](?![A-Za-z]))`).
  - It returns those rows. In `blocks()`, the list branch and `continuesListItem` use `listLine`,
    which passes over them.
  - Every other joined row that would become a list line is still refused. `isList` is unchanged.

`doc/architecture.md` describes both rules.

## Tests

`Tests/PDFReflowLibTests/TallRowsAndMinusTests.swift` (6 tests). New fixture `algebra-2-layout.json`
comes from `tools/capture-layout-fixture.swift`. A recapture of `algebra-318` with the same build was
byte-identical to the committed fixture.

- `sourceTallInlineExpressionLinesKeepTheirParagraphs`: pages 180, 318, 9 and 120 in full reading
  order. Page 318's World View Note still opens its own paragraphs (#71).
- `sourceMinusRadicandRowReadsAsProse`: page 321's paragraph, exactly. A control swaps the radicand's
  text for `2) 1`, a numbered marker. That row is still refused and no list line appears.
- `sourceMinusLinesOutsideJoinedRowsStayListLines`: page 2's three minus bullets and seven `•` items.
  Page 9's `− 24 Our Solution`, `− 2(− 6)` and `− 5 Our Solution`, and page 120's `− 18 <− 12`.
- `minusSignBeforeANumberOrVariableIsNotABulletWord`: the text rule, including hyphen-minus, a tight
  `−1`, `− (` and words.
- `syntheticTallInlineLineKeepsItsParagraph`: Wallace geometry. The rectangle dropped or raised
  8.5 points joins. Controls: a 25-point rectangle (a display), an overlap past the extra height, and
  two ordinary rectangles overlapping by 6.1 points all stay apart.
- `syntheticTallLineGapIsNotTheParagraphLeading`: after a tall line, a sentence end over a capital at
  ordinary spacing stays one paragraph. Real added space still opens one.

`RowPiecesAndSpacedParagraphTests.sourceAlgebraRowsJoinOnlyWithinTheirRow` (#95) pinned the defects
this issue fixes: `21.` as its own paragraph, `tion again…` opening a paragraph, and the `√ , and it is…`
paragraph without its radicand. Those expectations now state the fixed reading. The row-joining
checks in the test are unchanged. The exercise-column block counts (with and without crops) are
unchanged too.

`corpus/regressions.json` adds 18 Wallace checks (138 → 156) with
`tools/addcontract.py`. Reproducers:

- `paragraphs` on pages 9, 90, 120, 180, 318, 321 and 401.

Controls:

- `distinctParagraphs` for page 90's B and C point descriptions and page 401's two paragraphs;
- `listItems` for page 2's minus bullets, page 9's `− 24 Our Solution` and page 120's `− 18 <− 12`.

Pages 90 and 401 were checked against 60-DPI source renders.

## Verification

- `swift test`: 506 tests pass (500 at `de0df61` + 6).
- Negative control (`before-tests.log.gz`, `tools/negative-control.sh`). The five affected suites ran
  against `de0df61`'s `LayoutReconstructor.swift`, with only the pure `opensWithMinusSign` helper
  grafted on so they compile. Result: 5 of 44 tests fail with 20 issues.
  - Failing: every reproducer, both synthetic positives and the leading test, and the three updated
    #95 expectations.
  - Passing: the minus-line controls, the text rule, the display, overlap and ordinary-overlap
    controls, and the exercise-column counts.
- Guard mutations (`guard-mutations.log`, `tools/mutate.py`):
  - Killed: recording the tall gap as leading, dropping the `isProseRow` guard (the exercise-column
    counts on pages 343, 186 and 424 without crops catch it), dropping the display cap, dropping the
    list exemption, and allowing any joined row that becomes a list line.
  - Survived: dropping the quarter-body minimum on extra height. It only matters for lines a point or
    two taller than ordinary (superscript rows, 13.3 points), whose overlaps stay under the old
    tolerance anyway; it is kept so their gaps still count as leading.
- `scripts/check-all.sh --fast`: 506 Swift tests, 204 Python tests, 8/8 concurrency trials,
  6 fixture conversions with identical repeat bytes, 13 policy conversions and 22 rejection/cleanup
  cases pass.

## Lane (`de0df61` vs candidate, `tools/compare_conversion_runs.py --allow-different-converters`)

One case per invocation (`tools/lane.sh`, `tools/compare.sh`), sharing one compiled raster probe
(`lane-summaries/`):

| Case | Checks | Baseline | Candidate | Changes |
| --- | ---: | --- | --- | --- |
| wallace-algebra-2010 | 156 | 12 fail (all new) | pass | 53 pages; `warnings`; no image, navigation, OCR or page-marker change |
| faa-phak-8083-25c | — | pass | pass | none |
| fed-explained-2021 | — | pass | pass | none |
| gpo-911-2004 | — | pass | pass | none |
| usgs-mcs2025-copper | — | pass | pass | none |
| scotus-loper-bright-2024 | — | pass | pass | none |

Every run passed EPUBCheck and the structural, progress and memory gates, with no memory-gate
failure. Before the contracts were added, both Wallace runs passed 138 checks. With them, the
baseline fails exactly the 12 new reproducer checks, and the candidate passes all 156.

**Wallace** (`block-diffs/wallace.diff`, every hunk reviewed). Changed pages: 9, 20, 23, 28, 29, 31,
47, 48, 54, 81, 89, 90, 91, 92, 104, 109, 119, 120, 124, 125, 128, 134, 140, 146, 147, 158, 180, 192,
198, 203, 217, 218, 219, 221, 223, 226, 237, 254, 290, 305, 318, 321, 322, 332, 333, 334, 335, 349,
382, 397, 401, 406, 428.

- Every change joins a paragraph that a line holding an inline minus, `×`, `±`, `∞`, `∪`, `∩` or
  radical had cut, usually mid-sentence or mid-word. Examples: `…(− 5)2 the negative is part of the
  number and` / `is also squared…` (page 20), `slope-` / `intercept form.` (page 109), `f−1(8) = (8)−` /
  `5= 3, …` (page 401).
- Paragraphs that are separate in the source stay separate, including the point descriptions beside
  page 90's graphs and page 401's `For example…` / `Often the functions…` (both render-checked).
- Page 321 is the only page whose list items changed: `− 1` leaves its `<pre>` and reads inside its
  sentence. So the minus exemption applies to exactly one row in the book.
- The page-text field changed on pages 9, 29, 31, 54, 90, 91, 109, 219, 318, 321, 382 and 401 because
  lines now join inside one paragraph. Words hyphenated across a former split are repaired by the
  usual vocabulary rule (`multiplication`, `following`, `outside`, `negative`, `equation`,
  `anything`), and compounds keep their hyphen (`slope-intercept`, `x-intercepts`). Page 321's
  radicand moves into its sentence.
- The `warnings` change is page 9's `sep-` + `arates`, now inside one paragraph: the hyphen is kept
  and warned, as for any unknown compound.
- No exercise, answer-key or derivation page changed (10, 26, 101, 186, 343, 424, 438, 471 among the
  controls), and page 2 is unchanged.

## Remaining gaps

- `continuesListItem` and `continuesParagraph` keep the plain `-0.4 × body` bound. On Wallace page 2,
  each tall bullet (17 points against 9.9) overlaps its wrapped second line by 4.7 points against
  4.0. So `licensor (but not…`, `right holder.`, `applicable law…`, `limitations;`, `such as
  publicity…` and `this work. The best way…` are paragraphs after their items. This is unchanged,
  and pinned as today's reading nowhere.
- A tall line whose rectangle hides added space (a blank line after the dropped edge) does not open a
  spaced paragraph. The raw gap is 8.5 points short.
- A tall line with no ordinary leading before it in its paragraph gives the next line no leading to
  compare, so the added-space rule cannot fire there.
- Row pieces keep PDFKit's order inside a row (`− 1 √` for √−1), as recorded for #95.
- `sep-arates` (page 9) keeps its hyphen: the vocabulary does not know `separates`.

## Defects to file

- **Wallace page 2: a tall bullet rectangle detaches its item's wrapped line.** Each license bullet
  line is 17 points tall against 9.9-point lines. It overlaps the wrapped line by 4.7 points, past
  `continuesListItem`'s 4.0-point bound, so the wrapped line becomes a paragraph after the item.
  Expected: one item per bullet. The same extra-height measure would apply, with the list-branch
  controls (FAA, Fed, 9/11 bullets).
- **Hyphen repair misses `sep-arates`** (Wallace page 9, now inside one paragraph). The hyphen is
  kept and warned.
