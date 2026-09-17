# Labels PDFKit joins across a page

[#14](https://github.com/vocaro/PDFReflowLib/issues/14), continuing from the title-boundary
repair (`measurements/native-line-boundaries/record.md`), the Type3 word-space repair and the
re-verification in `measurements/dga-and-fallback-reverify/record.md`.

## What was left of #14

On `e21ef31` the *Dietary Guidelines for Americans, 2025–2030* cover already read
`Dietary Guidelines For Americans`, `Protein, Dairy` and `Vegetables`: the three word-spacing
defects named in the issue are fixed and contract-protected, and nothing in this change touches
word spacing. What remained was the last item the issue lists, graphic-label ownership. Physical
page 1 converted:

```
Dietary Guidelines For Americans
Protein, Dairy
Vegetables
& Healthy Fats & Fruits
Whole Grains
realfood.gov 2025–2030
```

The source sets `Protein, Dairy` / `& Healthy Fats` against the left of the food pyramid and
`Vegetables` / `& Fruits` against its right, and `realfood.gov` and `2025–2030` in opposite
footer corners. Two labels from opposite sides of the page were reading as one phrase, and so
were the two footer items.

## Root cause

PDFKit returns those two rows as single lines. Its own character geometry cannot be walked to
find the cut: on this page `characterBounds` drifts away from the string (index 81 is reported
as `F` with a box 342.9 pt wide, the stretched space, while the glyph drawn there is `t`), which
is what the earlier note on this issue recorded as "character positions … misaligned with the
text".

The content stream still says exactly where each piece begins. `NativeSpacingReader` already
reads every upright text show for #119/#128, and on this page it reports

```
origin=(39.36,450.54) size=17.98 text="& Healthy Fats"
origin=(507.33,450.55) size=17.98 text="& Fruits"
```

PDFKit's *rectangle* selections are sound here even though its character bounds are not: a
selection of `x < 250` on that line returns `& Healthy Fats` with a box ending at 158.3, and one
of `x > 250` returns `& Fruits` starting at 507.3. So a show position proposes the cut and
PDFKit measures it.

## The rule

`NativeTextReader.splitDetachedShows` runs on every page's lines before the column-joint (#65)
and borderless-table (#121) splits. For a line that is not monospaced and is wider than a quarter
of the page, it takes the shows whose origin lies in that line's rectangle and in no other line's,
and proposes a cut at each show whose origin stands `least = max(8 ems, a quarter of the page)`
beyond the previous show's origin. That is a necessary condition for the gap, since neither show's
ink starts before its own origin, and it is cheap enough to leave prose alone. `piece` then
measures each resulting piece with PDFKit's rectangle selections — the same binary search
`splitAtColumnJoints` uses, which already shrinks a selection off a stretched space glyph — and
the split is taken only when

- the pieces spell the line exactly apart from the whitespace at the cuts;
- each piece stands on its own side of its cuts;
- every neighbouring pair stands `least` apart, with **more empty page between them than their
  own ink together**.

Any failure keeps the whole line, so a line that mixes a real gap with a doubtful one is never
taken apart.

## Choosing the thresholds

`survey-line-changes.swift` reports, for every page of the 21 corpus documents, each line PDFKit
returns that the reader reads differently. Running it with the distance threshold lowered to two
ems and no page share enumerates **87 gaps** the rule could ever take; `survey.txt` lists them
with the empty space between the pieces, the pieces' own ink, and the gap as a share of the page.

The population separates cleanly. Every gap a column, a cell or a graph label leaves reaches at
most **11.5 ems and 19.4% of the page** — Wallace's answer columns (`1)− 4` | `2) 7`, 9.6 ems),
its coordinate-plane labels (`B` | `A`, 9.9 ems), its worked-solution annotations
(`x = 1` | `First solution`, 9.0 ems), the FAA's beacon table (`H` | `50–1999`, 10.3 ems) and the
Census report's figures (`Difference` | `0.25`, 11.5 ems). Content set against the opposite side
of a page begins at **17.8 ems and 35.7%** — Wallace's two-graph exercise row (`9)` | `10)`), Our
Flag's signature block (`Chairman` | `Vice Chairman`, 20.6 ems) and the cover's own labels (19.4
ems) and footer (36.0 ems). Nothing at all lies between 11.5 and 17.8 ems, or between 19.4% and
35.7% of the page.

8 ems and a quarter of the page sit inside that empty band on both measures. The em threshold
alone would take the FAA's table row; the page share alone would let a small size on a large page
split at three ems. The ink test is the third, independent measure: it is what keeps a row whose
pieces carry more text than the space between them (Our Flag's committee entries) together.

## What changed across the corpus

Both survey runs, `e21ef31` and this change, over all 21 documents (`survey.txt`):

| Book | Lines split (added) | Word-space changes (added) |
| --- | --- | --- |
| *Dietary Guidelines* | 2 | 0 |
| *Beginning and Intermediate Algebra* | 1 | 0 |
| *Our Flag* | 1 | 0 |
| The other 18 documents | 0 | 0 |

The 7,627 lines whose characters the reader changes (#119/#128 word spaces, #143 index glyphs,
#155 symbol fonts) are identical in both runs, and no line that was split before is split
differently. **This change inserts and removes no word space anywhere**; the guards #119 and #128
put on spurious insertions are untouched, and their tests are unchanged.

Each of the four added splits was reviewed against the source raster:

- **DGA page 1** (`& Healthy Fats` | `& Fruits`): the two labels are 349 pt apart on either side
  of the pyramid. Correct.
- **DGA page 1** (`realfood.gov` | `2025–2030`): opposite footer corners, 414 pt apart. Correct.
- **Wallace page 101** (`9)` | `10)`): exercises 9 and 10 each head their own graph, side by side.
  Correct; each marker now reads immediately before its own graph.
- **Our Flag page 4** (`Chairman` | `Vice Chairman`): `Chairman` sits under Representative Ney in
  the left column and `Vice Chairman` under Senator Chambliss in the right. Correct.

## Converted output

`tools/compare_conversion_runs.py --allow-different-converters`, baseline `e21ef31` against this
change, one capability probe shared by both runs:

| Case | Changed pages | Fields | Images | Navigation |
| --- | --- | --- | --- | --- |
| `dga-2025-2030` | 1 | markup, paragraphs, text | none | unchanged |
| `wallace-algebra-2010` | 101 | markup, paragraphs, list items | none | unchanged |
| `gpo-our-flag-2003` | 4 | markup | none | unchanged |
| `gpo-911-2004`, `fed-explained-2021`, `faa-phak-8083-25c`, `arxiv-replay-clocks-2023` | none | — | none | unchanged |

DGA page 1 now reads:

```
Dietary Guidelines For Americans        (heading)
Protein, Dairy & Healthy Fats
realfood.gov
Whole Grains
Vegetables
& Fruits
2025–2030
[Original page 1]
```

Each label now belongs to its own side of the pyramid, and the left label's two lines join into
one paragraph. The source image and the `unverifiedTextLayer` warning are retained, as the
existing contract requires.

Wallace page 101 changes from

```
9) 10)
[graph] [graph]
```

to `9)`, its graph, `10)`, its graph. Our Flag page 4's text is byte-identical; only the italic
run splits into two, one for each column's label, because `joinedRows` puts the two pieces back
into one row paragraph.

## Known, not fixed

`Vegetables` and `& Fruits` stay two paragraphs, where `Protein, Dairy` and `& Healthy Fats` join
into one. The right label is set flush right, so its two lines share a right edge and not a left
one, and paragraph assembly joins stacked lines on a shared left edge. That is paragraph grouping,
not label ownership, and is left for a separate change; the contract asserts the two labels are
distinct paragraphs rather than blessing a join.

Splitting the footer puts `realfood.gov` and `2025–2030` into the cover's left and right reading
columns, so the page reads left column, centre, right column rather than row by row. On a cover
with no running text either order is defensible; the text is complete and each label is with its
own side.

## Tests and contracts

`Tests/PDFReflowLibTests/DetachedLabelTests.swift`, 11 tests on original in-memory PDFs, so they
run offline on macOS and iOS:

- the reproducer: two labels on one baseline 468 pt apart, which PDFKit returns as
  `& Healthy Fats & Fruits` and the reader returns as two lines whose boxes end at their own
  glyphs; a three-label row; the styled run surviving the split;
- controls that must keep PDFKit's line: a table row's column gap (the FAA's geometry), a row
  whose pieces carry more ink than the space between them (Our Flag's geometry), prose with
  ordinary word spaces, a line narrower than a quarter of the page, labels already on separate
  baselines, a page whose font has no widths (so the spacing reader supplies no shows at all —
  the state every ruled-table and prose fixture captured before #14 is in), and a page setting a
  text-rendering mode the spacing reader does not model;
- the thresholds themselves, pinned to the measured values.

Removing the page share fails `aTableRowsColumnGapDoesNotSplitItsCells` and
`aShortLineIsNotSplitHoweverItsShowsStand`; removing the ink test fails
`aGapNoWiderThanTheTextAroundItDoesNotSplitItsLine`.

Corpus contracts (`corpus/regressions.json`):

- `dga-2025-2030` page 1 requires `Protein, Dairy & Healthy Fats`, `Vegetables`, `& Fruits`,
  `realfood.gov` and `2025–2030`, forbids `& Healthy Fats & Fruits` and `realfood.gov 2025–2030`,
  and requires `& Healthy Fats`/`& Fruits` and `realfood.gov`/`2025–2030` to be distinct
  paragraphs. All five fail on the `e21ef31` output.
- `wallace-algebra-2010` page 101 requires `9)` and `10)` to be distinct paragraphs, in that order
  before `Find the slope of the line through each pair of points.`; the distinction fails on the
  `e21ef31` output, where the page has no `9)` paragraph at all.
- `gpo-our-flag-2003` page 4 is the control: the committee's two-column entries must keep their
  text whole and in column order. It passes on both outputs, and would fail if the rule took the
  rows apart.

## Receipts

- `survey-line-changes.swift` — the survey tool. Build it from the repository root with the
  reader's sources, as `doc/regression-testing.md` builds `capture-layout-fixture.swift`, then
  `survey-line-changes <case-id> …`.
- `survey.txt` — both survey runs' totals, the complete diff, and the 87 measured gaps.
- Environment: macOS 27.0 (Darwin 27.0.0), Xcode 27, release defaults, `--raster-dpi 180`,
  EPUBCheck 5.x. Baseline converter built from `e21ef31`.
