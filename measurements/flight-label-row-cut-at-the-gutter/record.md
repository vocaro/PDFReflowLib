# A row of two columns PDFKit merged across the gutter

Measured under [#270](https://github.com/vocaro/PDFReflowLib/issues/270), baselines `18c8cc3` and,
after merging, `f2a10fd`,
2026-09-22, macOS 27 (Darwin 27.0.0) / Swift 6.2 toolchain, arm64, release CLI at library
defaults. The source is `corpus/cache/GPO-911REPORT.pdf` as the corpus manifest pins it, physical
pages 50, 51 and 451. Page geometry is what `PDFPage.selection(for:)`, `selectionsByLine()` and
`PDFPage.characterBounds(at:)` return for the page, captured with a probe compiled from the
library's own extraction sources; block counts and character counts of a converted book are read
by the corpus lane's own spine reader.

## 1. The facility the issue says is missing, and which change landed it

#270 was filed while closing [#207](https://github.com/vocaro/PDFReflowLib/issues/207), and says
the fix needs a line cut, "which `main` has no facility for". Two changes have landed since, and
only one of them supplies it.

**[#210](https://github.com/vocaro/PDFReflowLib/issues/210)'s `TableReader` does not reach this
row.** Its columns are the corridors down a block of rows, and a row's ink is its content-stream
shows merged where they touch. On page 50 `NativeSpacingReader.read` returns **one show per
heading row**, the gutter inside its own glyph advances:

```
show y=539.75  x=39.66  end=325.68  size=11.0  'American Airlines Flight 11 United Airlines Flight 175'
show y=528.50  x=39.66  end=242.95  size=11.0  '(AA 11)             (UA 175)'
show y=517.25  x=39.66  end=286.81  size=10.2  'Boston to Los Angeles Boston to Los Angeles'
```

Every row's ink is therefore one unbroken range across the gutter, `corridors` finds nothing, and
the block would be declined at the three-column condition even if it did. Page 51 is the same: 53
shows, one per row over the headings.

**[#264](https://github.com/vocaro/PDFReflowLib/issues/264)'s margin rule landed it.** That change
reads `PDFPage.characterBounds(at:)` for every character of every line — indexed over the page's
characters without the separators the reading synthesizes between rows, the relation
`NativeTextReader.lineRanges` already read in the other direction — and cuts a line's plain and
styled text positionally, re-measuring the row from the characters that remain. That is exactly a
cut, and it is where this fix is made. The measurement it hands over is this, character by
character, on page 50's merged line:

```
( [40.40..43.46]  A [43.46..51.69]  A [51.69..59.78]  _ [59.78..64.28]   1 [64.28..68.97]
1 [68.97..74.23]  ) [74.23..78.02]  _ [78.02..196.39]                    ( [196.39..199.43] …
```

One space, 118.37 points across, against the 4.50-point space the same line sets between its own
words, and the right column's pieces above and below it begin at 195.67 — inside that space.

## 2. What the page states, and what the reading made of it

Physical page 50 sets two flight timelines side by side, each under three heading rows. PDFKit
reads the first and third as two lines and merges the second:

| y | x | width | text |
| ---: | ---: | ---: | --- |
| 537.25 | 39.66 | 136.12 | `American Airlines Flight 11` |
| 537.25 | 195.67 | 126.35 | `United Airlines Flight 175` |
| 526.00 | 39.66 | **199.63** | `(AA 11) (UA 175)` — one line, both columns |
| 514.92 | 39.66 | 88.30 | `Boston to Los Angeles` |
| 514.92 | 195.67 | 88.30 | `Boston to Los Angeles` |

Page 51 is the same shape at its own measure: the rows state 44.70 and 200.71 above, 44.70 and
200.69 below, and `(AA 77) (UA 93)` merged at 44.70 over 194.14.

Reflowed at the baseline, page 50's head reads

```
American Airlines Flight 11
United Airlines Flight 175
(AA 11) (UA 175) Boston to Los Angeles
Boston to Los Angeles
```

— two cells of two different columns run together, and the right column's route stranded. With the
cut it reads

```
American Airlines Flight 11 (AA 11) Boston to Los Angeles
United Airlines Flight 175 (UA 175) Boston to Los Angeles
```

which is what the page prints.

Page 51 loses the same defect but does not group as far. Its heading rows read

```
American Airlines Flight 77
United Airlines Flight 93
(AA 77)
(UA 93)
Washington, D.C., to Los Angeles
Newark to San Francisco
```

against the baseline's `(AA 77) (UA 93) Washington, D.C., to Los Angeles` followed by a stranded
`Newark to San Francisco`. No block holds two columns' cells, and no route is stranded; the six
rows are read row by row rather than column by column because page 51 draws **two** map pictures,
one per flight, where page 50 draws one across both columns, and the column reading divides each
page at what its pictures state. That is the reading rule's own business and not this change's:
this change is the line, and the line is right on both pages.

## 3. The rule

`ColumnGutterCut` decides everything from the page's own reading, as `MarginRuleMarks` does, and
the correction is made where the box is formed, because nothing downstream can divide a line.

**Three rows agree on two edges.** A line standing alone in its printed row, whose printed rows
directly above and below each hold exactly two pieces; the two rows state the same two left edges
to within a point; the line begins on the first edge and reaches past the second. Each step between
the three rows is a leading, at most twice the taller row's own height. This is the whole of
`suspected`, so a page that merges no row pays one pass over its line rectangles and asks PDFKit
for no character box at all.

**The three rows are the whole of it.** Neither the row two above nor the row two below may stand
on the same pair of edges. This condition was added after measuring what it costs to leave it out,
which is section 4's second finding: where a page states its columns over four rows or more, the
reading already holds divided pieces for them and the ordering rules can see those columns, and
dividing one more row there changes how the whole page is read.

**The white decides.** A line the page genuinely sets across both columns has the same shape, and
must keep its reading. What separates the two is that a spanning line runs its words *through* the
gutter, so the white at the column edge is the space it sets everywhere else, while a merged row
leaves the gutter empty. The second edge must fall in white at least twice as wide as the line's
own characters are tall and at least three times the widest white elsewhere in the line. On page 50
that is 118.37 against 4.50 (26×) and against 14.02 (twice the 7.01-point median character).

The white is read from the line's **ink**: a character inks when it is not whitespace and PDFKit
gives it a box with width. Page 20 of the climate assessment carries a `U+0008` between a contents
entry and its page number, with the box `[193.90..193.90]`; it stands nowhere and is not type.

**What is refused.** A line whose inking characters PDFKit reports out of the order they stand in
states nothing about its columns. A line with anything printed in the white between the two pieces
is left alone, so nothing that prints is ever cut away — only spaces and characters the page gives
no width are dropped. A line the margin rule of #264 also reached keeps that reading, since its box
is already being re-measured.

**What each piece carries.** PDFKit's own outer edge, its own inner edge — the only edge the merge
got wrong — the row's baseline and height, and its own half of the styled text, cut positionally.
A line a repair rewrote between the reading and the cut is not cut, because the offsets no longer
mean what the boxes measured.

Measured as unit tests in `Tests/PDFReflowLibTests/ColumnGutterCutTests.swift`, over page 50's own
geometry: the cut itself; page 51's edges agreeing only to a twentieth of a point; the styled text
following the cut; **a headline set across both columns, with a word space at the column edge**;
**a line whose type runs through the gutter with its one wide gap elsewhere**; neighbors that state
no second column; neighbors that disagree on where it opens; three rows too far apart to be a
group; **the same pair of edges running on above or below the group**; characters reported out of
order; a printed character inside the white; and a line whose character boxes the page does not
supply.

## 4. Every line the rule reaches, over all twenty-four cached sources

The rule was run over every page of every PDF in `corpus/cache` — 5,302 pages — reporting both the
lines it cuts and the lines whose shape it offers and whose white refuses.

| Source | Pages | Cut | Offered and refused |
| --- | ---: | ---: | ---: |
| gpo-911-2004 | 585 | **2** | 0 |
| wallace-algebra-2010 | 489 | 0 | 1 |
| the other twenty-two sources | — | 0 | 0 |

```
gpo-911-2004 p50  '(AA 11) (UA 175)'  ->  '(AA 11)'  |  '(UA 175)'
gpo-911-2004 p51  '(AA 77) (UA 93)'   ->  '(AA 77)'  |  '(UA 93)'
```

The one refusal is a line whose characters run backwards: the algebra book's answer key on page 453
hands back `28) a 1or a 19 : ( − ∞, 1] [19, ∞)` whose fifth character stands at 175.91 and whose
sixth stands at 85.52 — a wrapped row PDFKit returned as one line.

### What the group condition costs, and what it buys

Without it the rule cut two further lines, and one of them is a regression. This was measured on a
full corpus lane before the condition was added.

```
gpo-911-2004 p451  'Janet Reno Attorney General, 1993–2001'  -> 'Janet Reno' | 'Attorney General, 1993–2001'
noaa-nca5-2023 p20 'A4.6. Health Indicators  A4-29'          -> 'A4.6. Health Indicators' | 'A4-29'
```

Page 451 is Appendix B's table of names: twenty-three rows, a name at 44.70 and an office at
152.70, of which PDFKit merges exactly one. That one undivided line is the only thing making the
page read row by row. Divided, `columnRuns` (#174) sees twenty-three two-piece rows on one pair of
edges and reads the page column by column: `chapter-22.xhtml` goes from 489 blocks to 474 and
every name loses its office —

```
baseline   <pre>Thomas Pickering Under Secretary of State, 1997–2000</pre>
           <pre>Colin Powell Secretary of State, 2001–</pre>
divided    <p>Thomas Pickering Colin Powell Ronald Reagan Janet Reno Condoleezza Rice …</p>
           <p>Under Secretary of State, 1997–2000 Secretary of State, 2001– …</p>
```

The corpus lane passes both readings, so nothing catches it. The cut of that line is right on its
own evidence; what it exposes is a reading defect underneath, filed as
[#283](https://github.com/vocaro/PDFReflowLib/issues/283). The group condition declines the page
and leaves it exactly as it is today.

Page 20 of the climate assessment is a contents page of the same shape — entries at 90.00 and page
numbers at about 530.4 over many rows — and the same condition declines it. `noaa-nca5-2023` is not
covered by the corpus lane (its default image output exceeds the budget), so nothing there could
have been measured for regressions; declining it is also what keeps this change inside what the
lane can see. Its merged row carries a `U+0008` between the entry and the number, which is the
character that made "the white is read from the line's ink" the right reading rather than a
convenience.

## 5. What moved, per book

Both lanes ran over the same eighteen covered cases, `--jobs 4`, EPUBCheck 5.x at
`/opt/homebrew/bin/epubcheck`. The baseline binary is built from `f2a10fd`, the `main` this branch
is merged to; the candidate is that tree plus this commit and nothing else. Every case of **both**
lanes passes on its own `runPassed`, `memoryGate.status`, `epubcheckExitCode`, `structuralCheck`
*and* its `content-assessment.json`, read case by case.

Compared entry by entry with `tools/epub_identity.py`, **seventeen of the eighteen books are
byte-identical**, and every book's character count and image count is unchanged to the unit. The
one book that moves is `gpo-911-2004`, in one entry: `EPUB/chapter-2.xhtml`, which holds physical
pages 50 and 51. Its block count is 162 in both, its character count is unchanged, and the diff is
the whole of it:

```
-<p>American Airlines Flight 11</p>
-<p>United Airlines Flight 175</p>
-<p>(AA 11) (UA 175) Boston to Los Angeles</p>
-<p>Boston to Los Angeles</p>
+<p>American Airlines Flight 11 (AA 11) Boston to Los Angeles</p>
+<p>United Airlines Flight 175 (UA 175) Boston to Los Angeles</p>
…
-<p>(AA 77) (UA 93) Washington, D.C., to Los Angeles</p>
+<p>(AA 77)</p>
+<p>(UA 93)</p>
+<p>Washington, D.C., to Los Angeles</p>
```

`EPUB/chapter-22.xhtml`, which holds page 451, is **byte-identical**, which is the group condition
doing what section 4 says it does. No page of the book loses a character, and the whole book's
character count is unchanged, because the cut moves no character: it divides a line.

### Two recognition cases, and why their earlier lanes are not this change

An earlier pair of lanes over `86193ac` recorded two differences that are the lane's own variance
and not this change. They are named here because they were measured, not because anything moved.

- `cdc-zombie-pandemic-2011` came out 159 characters apart over its 33 recognized pages. This
  change cuts nothing anywhere in that source — no page of it even offers the shape — and run on
  its own *both* binaries produce 16,114 characters, twice each. That is
  [#284](https://github.com/vocaro/PDFReflowLib/issues/284). On the lanes recorded above the two
  books are byte-identical.
- `gpo-warren-1964-suspect-text-excerpt` failed its content assessment in one baseline lane. Run on
  its own it fails identically on this tree, on `86193ac` and on `18c8cc3` — `Page 4: unwanted text
  'ftboot'` and two missing lines — so it is one instability across all three, already filed as
  [#269](https://github.com/vocaro/PDFReflowLib/issues/269) and
  [#281](https://github.com/vocaro/PDFReflowLib/issues/281). It passes in both lanes recorded above.

## 6. Gates

`scripts/check-all.sh --fast` passes all ten gates on the merged tree, read from its own exit
status: python-tool-tests, measurements-policy, swift-tests, release-build, pdfkit-concurrency,
documented-builds, doc-counts, issue-citations, fixture-epubs, conversion-policies. 642 Swift tests
and 231 Python tests pass. EPUBCheck reports exit 0 on every corpus book of both lanes.

## Reproducing

```sh
ln -s "$PWD/corpus/cache" <worktree>/corpus/cache
swift build -c release
python3 tools/run_corpus_regressions.py \
  --converter "$(swift build -c release --show-bin-path)/pdf-reflow" \
  --epubcheck "$(command -v epubcheck)" --output /tmp/corpus-270 --jobs 4
python3 tools/epub_identity.py \
  --baseline-epub /tmp/corpus-270-baseline/gpo-911-2004/gpo-911-2004.epub \
  --candidate-epub /tmp/corpus-270/gpo-911-2004/gpo-911-2004.epub
```

The page traces above were taken with a probe compiled from
`python3 tools/pdfreflow_tools/swift_sources.py capture-layout-fixture.swift`'s source list, which
prints `NativeSpacingReader.read`, `selectionsByLine()` and `characterBounds(at:)` for a page, and
`ColumnGutterCut.edges` and `.read` over every page of a source.

## The fixtures

`Tests/PDFReflowLibTests/fixtures/911-50-layout.json` and `911-51-layout.json` are captures of the
reading, so the line this change cuts is two lines in them now. Both were recaptured whole rather
than patched, because a capture that carries the new reading of one line and a stale reading of the
rest would make a test's page differ from the book's. Each capture's `attributedLines` — PDFKit's
own selections, which the cut does not touch — come back identical to the committed ones, and the
whole diff is: the merged line becoming two, the schema version and its `pictures` array, which the
committed captures predate, and page 51's graphics.

That last one is a correction the recapture surfaced and this change did not cause.
`GraphicsReader` returns **two** regions for page 51 — `[47.13, 395.30, 155.13, 111.84]` and
`[206.96, 396.57, 153.88, 110.57]`, the two maps the page draws, one per flight — where the
committed capture carried one region spanning both. It returns two on `18c8cc3` as well, so the
capture had simply fallen behind. `reportMapLabelsRemainInsidePreservedGraphics` pinned the stale
count for page 51 and now pins the page's own: one region on page 50, which draws a single map
across both columns, and two on pages 33 and 51. Every map label still lands inside a region, and
the test's other assertions are unchanged.
