# A drawing keeps its own vertex and side labels (#179)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 (26A428) arm64, release CLI,
host terminal. Baseline: `ce9e288` (`Sources/PDFReflowLib/LayoutReconstructor.swift` restored from
`ce9e288` in this worktree, converter `26ff9e71…`); candidate: `ce9e288` plus the working tree
(converter `fe74dba9…`). [identity.json](identity.json) pins both CLIs, the capability probe, the
sources, the fixtures and the commands. No PDF or EPUB is committed.

Scope: this record closes the label gap the [#46/#48 crop
work](../split-display-rows/record.md#remaining-gaps) left open. The answer-key ordering gap of the
same list is [#178](../answer-key-columns/record.md).

## What was wrong

Wallace's trigonometry sections draw a right triangle for each exercise and letter its vertices
`A`, `B` and `C` with a side length and an angle. The drawing is a preserved crop, and the labels
PDFKit returns as separate lines. #46/#48 admitted the labels whose rectangles all but touch the
crop — the piece-of-a-row rule reaches 0.75 pt, which took page 427's three `A` labels at 0.025 pt
and page 424's side length `13` at 0.074 pt — but the rest are a real word space away and reflowed
as one-character paragraphs around the image:

```
<p>37)</p> <p>C</p> <figure>…triangle…</figure> <p>B</p>
<p>39)</p> <p>C</p> <figure>…</figure> <p>B</p>
```

The exercise number `37)` is the page's own text and must stay; `A`, `B` and `C` are drawn on the
triangle, like the 65° label and the right-angle mark already inside the crop.

## The rule

`LayoutReconstructor.isDiagramLabel`, admitted in `expanded` after `adjoinsRow` and before the
trimming pass. A line joins a crop as its label when

- it is **one or two ASCII letters or digits** and not monospaced;
- its box **overlaps the crop's span in exactly one direction** and stands at most **one body
  size** clear in the other (never diagonally off a corner);
- a **painted region at least one body wide and one body tall** reaches into the crop; and
- the crop **holds nothing but labels itself**: at most eight lines, none over eight characters and
  none carrying a word of three letters or more.

Each guard answers a measured neighbour, not a hypothetical one. The distance is body-relative
because this is typography, not the extraction padding `adjoinsRow` measures in absolute points.

## Choosing the guards

`survey.swift` reports, for every line of every page of the 23 cached corpus sources that lies
outside every crop and within 14 pt of one, the distance to that crop in each direction, whether
the line stands inside the crop's span, the crop's size, how many lines it holds, the longest of
them, whether any of them carries a word, and whether a painted region of at least a body square
reaches into it. All 11,115 measurements are in
[label-distances.tsv](label-distances.tsv), measured on the baseline.

**197** of them are one or two ASCII letters or digits overlapping a crop's span in exactly one
direction — the population the rule could ever take. They separate completely:

| Outcome | Count | What they are |
| --- | ---: | --- |
| refused: no painted region a body square | 33 | Wallace's worked derivations and their folios (page 33's `33` 6.2 pt under the quadratic steps, page 198's `35`, page 294's `3` and `4`), the USDA magazine's folios beside its 544 × 4 pt running-foot rule, the FAA's `or` between the page-265 fractions, DASC's display equations |
| refused: the crop carries a word | 39 | NOAA's chart axis figures on pages 756 and 757 (crops of 15–166 lines), the USDA magazine's page images, Wallace page 423's `16` beside a crop that swallowed `7) sin θ`, pages 74 and 81 |
| **admitted** | **125** | vertex letters and side lengths on Wallace pages 422–436, at **0.279–11.153 pt** (0.02–0.93 of a body) |

No admitted line lies outside that Wallace range, and no refused line is a diagram's label. The
line-count and length tests refuse nothing the word test does not already refuse on this corpus;
they are kept so a chart or a table of short figures cannot qualify on a book the survey has not
seen.

The closing parenthesis is the fourth measure, and the sharpest. Ninety-two `N)` markers in the
survey stand beside a drawing and overlap its span, from **0.005 pt** (page 100's graph exercises)
to 13.9 pt: page 483's `5)` is 0.54 pt from its graph and page 447's `3)` 2.3 pt. No distance
separates an exercise number from a vertex letter; the punctuation does.

## What changed across the corpus

`page-comparison/wallace-algebra-2010.json`
(`compare_conversion_runs.py --allow-different-converters`, probe-backed runs of both CLIs) is
shared with [#178](../answer-key-columns/record.md); fourteen of its eighteen changed pages are
this issue's:

| Pages | Change | Reviewed |
| --- | --- | --- |
| 424, 425, 426, 427, 432, 433, 434, 435, 436 | every vertex letter and side length joins its triangle; the exercise numbers stay text | 424, 427, 432 against `pdftoppm` renders |
| 423 | the side lengths `5`, `8`, `15` and the vertex letters `B`, `C` join their figures | render |
| 422, 429, 430, 431 | a worked example's side length joins its triangle (page 429's `12`, page 430's two `5`s, page 431's `3`) | 429, 432 against renders |

Pages 424 and 427 now read exactly as the issue asks:

```
13) [triangle]  15) [triangle]  17) [triangle]  19) [triangle]
14) [triangle]  16) [triangle]  18) [triangle]  20) [triangle]
```

66 image assets change bytes — the crops that grew to take their labels. No text is lost from any
other page, page markers are equal, navigation is unchanged and the conversion report is unchanged.
**No other document changes**: the sweep in the [#178 record](../answer-key-columns/record.md#effect)
converts every cached corpus source with both CLIs and finds every other book identical page for
page.

## Regressions added

`Tests/PDFReflowLibTests/AnswerKeyColumnsAndDiagramLabelsTests.swift`, on checksum-pinned fixtures
(`algebra-427` is a new capture; `algebra-424` and `algebra-465` already existed):

- **page 427**: every `A`, `B` and `C` source line is inside a crop, no block is one of those
  letters or `x`, `11`, `1.4`, `13.1` or `18.1`, exercise numbers 37–40 are still text, and the
  page holds exactly four images.
- **page 424**: no vertex letter reflows, and exercise numbers 13–20 are still text (the #46/#48
  contract).
- **page 465** is the control: its crops are fractions, not drawings, so all 49 of its text answer
  entries keep their text.
- **the rule itself**, at page 427's measured geometry (a triangle 113.8 × 55.6 pt in a crop of
  138.3 × 88): `B` at 2.8 pt, `A` at 6.4 pt, `x` at 11.153 pt and a side length over the drawing
  join; 12.4 pt (past a body) does not; `5)` at 0.54 pt and `3)` at 2.3 pt do not; `7.1`, a
  monospaced piece and a label off a corner do not; with the drawing replaced by a 36 × 4 pt
  fraction bar neither `25` nor `or` joins, and with no painted region at all nothing joins; a
  crop that also holds `Multiply numerators across`, or nine lines, takes no label.

`RowPiecesAndSpacedParagraphTests.sourceExerciseColumnsKeepTheirRowPiecesApart` records page 424's
`withCrops` block count falling 28 → 16, its twelve labels having moved into their triangles; every
other page's counts are unchanged. `ColumnCutTests.workedExampleNotesAreNotColumnsUnderAFigure`
drops `12` from page 429's expected order for the same reason and still checks that the notes keep
their places beside their steps.

[../answer-key-columns/guard-mutations.log](../answer-key-columns/guard-mutations.log): each of the
five single-guard mutations of this rule — the character class, the one-direction test, the
distance, the painted region and the crop's own lines — fails at least one of the new tests, and
dropping the distance limit or the painted region also fails the source fixtures of pages 424, 429
and 465.

Against the baseline CLI the Wallace contract reports 30 errors; six of them are this issue's
(three on page 424 and three on page 427).

## Verification

- `swift test`: 834 tests pass (826 before, eight added across both issues).
- `scripts/check-all.sh --fast`: see the run below.
- `tools/run_corpus_regressions.py`, one case per call, probe-backed, on both CLIs:
  wallace-algebra-2010 (candidate PASS, baseline FAIL on the new checks only),
  faa-phak-8083-25c, gpo-911-2004, census-rrs2002-01, nbs-jres-geltman-1977,
  ntrs-20190030725-dasc-2019 and ntrs-20200002975-gwl-2020 all PASS on both, and
  `compare_conversion_runs.py` reports no changed page on any of them.

## What this does not prove

A crop is a fallback, not a transcription: a label taken into a triangle leaves the selectable
text, which is one representation per label but not reconstruction. The survey covers the cached
corpus only, and it measures the baseline's crops, so a book whose crops this change grows into new
labels would only show up as a conversion difference — none did outside Wallace. The painted-region
test asks for a body square, which is a property of these drawings and of this book's 12-point
body; a diagram drawn smaller than its own type would not qualify.

## Remaining

- Wallace page 423's `16` stays a paragraph: its triangle's crop also swallowed the exercise label
  `7) sin θ`, so the crop carries a word and is not judged a labelled drawing.
- Page 435's fourth triangle has no text of its own inside the crop; its labels still join, because
  a crop holding no line passes the label test vacuously.
- Labels of three characters or more (page 431's `9.5`, page 430's `7.1`) are left; they are a
  worked example's results set beside the derivation, not the drawing's own labels.

## Commands

```sh
# the label survey: every line outside every crop within 14 pt of one, with the crop's geometry
swiftc -swift-version 6 -O $(ls Sources/PDFReflowLib/*.swift | grep -v 'EPUBWriter\|PDFConverter\|PDFReflowLibPipeline\|EPUBTextEncoder') \
  measurements/figure-labels/survey.swift -o /tmp/label-survey
for pdf in corpus/cache/*.pdf; do /tmp/label-survey "$pdf" 14; done > label-distances.tsv
# the fixtures
swiftc Sources/PDFReflowLib/{NativeTextReader,ConversionTypes,DocumentModel,ReflowDocument,GraphicsReader,NativeSpacingReader,StructureTreeReader,MarkedTextReader,FontWeightReader,PrivateUseDecoder}.swift \
  tools/capture-layout-fixture.swift -o /tmp/capture-layout-fixture
/tmp/capture-layout-fixture wallace-algebra-2010 427 Tests/PDFReflowLibTests/fixtures/algebra-427-layout.json
```
