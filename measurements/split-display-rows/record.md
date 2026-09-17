# A crop takes the piece of a display row its edge left outside (#46, #48)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 (26A428) arm64, release CLI,
host terminal. Baseline: `58a2ddd` (`Sources/PDFReflowLib/LayoutReconstructor.swift` restored from
`58a2ddd` in this worktree); candidate: `58a2ddd` plus the working tree.
[identity.json](identity.json) pins both CLIs, the capability probe, the sources, the fixtures and
the commands. No PDF or EPUB is committed.

Scope: this record closes the two crop defects filed from the [#29 numbering
audit](../exercise-numbering/record.md). Semantic exercise lists (`<ol>`) and answer-key reading
order remain open; see [Remaining gaps](#remaining-gaps).

## What was wrong

PDFKit returns a displayed row in pieces: a raised exponent, a fraction's numerator, denominator
and bar, and the terms between them are separate `TextLine` values. `LayoutReconstructor.expanded`
grows a crop to every line its bounds already touch and to the other pieces of those lines' rows,
then trims the bounds away from lines it merely grazes. A piece the trimmed edge left outside was
never reconsidered, so the crop kept part of a row and the rest reflowed beside it as flattened
text.

| Page | Source row | Reflowed before |
| --- | --- | --- |
| 343 | `x² + (b/a)x + b²/4a² = (b² − 4ac)/4a²`, the derivation's "Factor" line | `Example 465.`, a crop, then a paragraph `x2 +`, then a crop (#46) |
| 340 | `x² − 3x + 9/4 = 8/4 + 9/4`, Example 463 | a crop, a paragraph `x2`, a crop |
| 339, 341 | Examples 462 and 464 | paragraphs `x2 +` and `−` between two crops |
| 16 | exercises 22, 23, 27, 28, 30 and 32, e.g. `22) (−2)(−5/6)` | `22) (− 2)(−` as a `<pre>` line, then the fraction's crop (#48) |
| 471 | 7.7 answers 22, 29 and 30 | `22)− 2,`, `29)−`, `30)− 1` before their fraction crops |
| 252 | exercises 41–44, four rows of fractions joined by `·` and `÷` | six crops with two `·` **headings** between them, which also entered the navigation |
| 424 | triangle 13, side length `13` beside vertex `C` | the diagram's crop, with `13` and `C` as paragraphs beside it |

The gap is extraction padding, not typography. Measured on the baseline over every cached corpus
source (`survey.swift`, reproduced in the commands below: for each line outside every crop that
shares a row with a line inside one, the distance from the line's rectangle to the crop's edge).
All 1,547 measurements are in [row-piece-distances.tsv](row-piece-distances.tsv):

| Distance | Pieces | What they are |
| --- | ---: | --- |
| 0.008–0.650 pt | 141 lines on 40 Wallace pages, 3 on Census pages 8 and 19 | pieces of one display row PDFKit broke |
| 0.759–0.881 pt | 8: five Census `[` and `4 FFFFFFFD`, NOAA's `396.`, Wallace's `Quotient Rule of Exponents:` | the band where broken rows stop and separated pieces begin |
| 0.948–23.4 pt | the rest | entry numbers (`21)` at 1.97, `2)`/`40)` at 2.57, `1)`–`22)` at 4.25), NOAA index references (`13-12`, `9-22`) and diagram labels at 0.95–6.4, and explanations set beside a derivation (`Separate constant term from varaibles`, 11.6 pt on page 339) |

So three quarters of a point separates a broken row from a word space, with 0.65 pt of positive
evidence below it and the nearest true negative at 0.87 pt (NOAA's reference number `396.`, 9 pt
type). Two more qualifiers keep that margin from carrying anything else: a piece holding a word of
three letters or more is an explanation beside the derivation, and a bare list marker
(`isMarkerPiece`: a bullet, or up to three digits or one letter with `.` or `)`) is a separable
entry number whose item happens to begin at the crop's edge.

## What changed

`Sources/PDFReflowLib/LayoutReconstructor.swift` only (+28 lines). No public API, option, default,
warning or other call site changed. The two hunks are inside `expanded`, which only
`graphicsWithLabels` calls:

1. **`adjoinsRow(_:bounds:admitted:)`**, new: a line is the remaining piece of a row the crop holds
   when it is not monospaced, is at most 40 characters, holds no word of three letters or more, is
   not a bare marker piece, shares a row (`sameRow`) with a rectangle already admitted, and its
   rectangle stands between 0 and 0.75 pt clear of the crop's near edge.
2. **The admission loop in `expanded`** runs once the existing whole-line pass has settled: any
   line outside the bounds that `adjoinsRow` accepts is admitted, and the fixpoint then re-expands
   and re-merges as it does for any admitted line.

## Effect

`page-comparison.json` (`compare_conversion_runs.py --allow-different-converters`, probe-backed
runs of both CLIs):

| Case | Changed pages | Notes |
| --- | --- | --- |
| wallace-algebra-2010 | 40 of 489 | 2025 → 1975 images, 480 → 479 reflowed pages, one navigation entry |
| census-rrs2002-01 | 1 of 20 (page 8) | the garbled bracket piece `V2S;` joins its equation crop; the page still reports `damagedTextEncoding` and keeps its source-page image |
| faa-phak-8083-25c, gpo-911-2004, arxiv-replay-clocks-2023, ntrs-20190030725-dasc-2019, nbs-jres-geltman-1977 | none | page for page identical, images byte-identical |

Every Wallace change removes a fragment from prose and puts it in the crop that holds the rest of
its row. No prose line, heading, list item or image moved otherwise. Reviewed by class against
`pdftoppm` renders of the source pages:

| Class | Pages | Reviewed |
| --- | ---: | --- |
| A displayed equation's leading term rejoins its crop | 13 (21, 95, 197, 205, 208, 249, 250, 252, 339, 340, 341, 343, 365) | 339, 340, 343 and 252 against renders: `x2 +`, `x2`, `−`, `+`, `·`, `÷`, `3x2 + 7x− 4−` are the first terms and the operators of rows whose remainder was already cropped |
| An exercise or answer entry rejoins its fraction | 23 (16, 17, 351, 439, 443, 444, 448, 450, 453, 461, 465, 466, 469, 470, 471, 475, 478, 479, 482, 484, 485, 486, 487) | 16, 465 and 471 against renders: each stub was a marker and a sign whose value is the fraction beside it (`33) −5/2, −8` on page 465). Every such entry is now one region; whole text entries beside them (`21) 0, 5`, `28) 1`, `33)− 10`, the thirty 7.8 answers) are untouched |
| A diagram's own label rejoins its diagram | 4 (424, 427, 433, 435) | 424 and 427 against renders: the side length `13` and the vertex letters are drawn on the triangles. Exercise numbers `13)`–`20)` stay text |

Two further effects, both reviewed:

- **Page 16 reads in numbering order.** Its exercises are set two to a row (1, 2 / 3, 4 / …). Before,
  the page read the first set's left column, then `Find each product.`, then the second set's left
  column, then both right columns. With the markers inside their crops the element grid no longer
  offers the column cut that split the instruction from the right column, and the page reads 1–20,
  `Find each product.`, 21–36, which is the printed order. The contract pins the instruction after
  all twenty crops of the first set; the order of the crops themselves is not pinned.
- **Page 252 holds only images.** All four of its exercises are fractions; its two `·` operators
  were the page's only "text", and one heading level had ranked them into the navigation. The page
  now reflows no text and keeps its `imageRegion` warning. This is the one page of the book whose
  reflowed-text count fell.

## Regressions added

`Tests/PDFReflowLibTests/SplitDisplayRowTests.swift`, five tests on checksum-pinned fixtures:

- **page 343** (#46): `x2 +` is inside a crop and no block is that text; the introductory sentence
  with its superscript, `Example 465.` and the closing prose still reflow; the `Our Solution` line
  stays inside a region, as the #27 glyph contract requires.
- **page 16** (#48): the six marker-and-sign stubs are inside crops, both instructions reflow, the
  instruction for the products follows exactly twenty crops and precedes sixteen, and no block
  matches `^[0-9]+\)\s*\(?\s*−?\s*$`.
- **page 471** (#48): entries 22 and 29 are inside crops while `21) 0, 5`, `23) 4, 7`, `28) 1`,
  `33)− 10` and the 7.8 answers stay text.
- **page 424**: the side length `13` is inside its diagram's crop and every exercise number
  `13)`–`20)` stays text.
- **controls on the rule**, at page 340's measured geometry: page 340's 0.008 pt, page 343's
  0.53 pt and page 471's 0.628 pt join; 0.87 pt (NOAA's `396.` distance) and 1.965 pt (page 21's
  `21)`) do not; a bare marker (`41)`, `396.`), a worded piece (`Factor`, `Separate constant from
  variables`), a monospaced piece, a piece on another row, a piece inside the crop's own span and a
  crop with nothing of the row admitted do not; a piece 0.2 pt off the crop's right edge does.

`before-tests.log.gz`: with the admission loop removed (the `58a2ddd` behaviour) the four source
tests fail with 24 issues and the rule's controls still pass.

`Tests/PDFReflowLibTests/RowPiecesAndSpacedParagraphTests.swift`: the `withCrops` block counts of
`sourceExerciseColumnsKeepTheirRowPiecesApart` fall on the seven affected fixtures (471 52 → 49,
343 9 → 8, 16 45 → 39, 479 14 → 12, 424 30 → 28, 448 48 → 44, 487 64 → 49). The `withoutCrops`
counts, the eight unaffected pages and every other test are unchanged.

`corpus/regressions.json` adds Wallace pages 16, 252, 340 and 424 and extends pages 343 and 471:
`absentText` for each fragment that must no longer leak (`Example 465. x2 +`, `22)− 2,`, `29)−`,
page 16's four stubs, page 340's `x2`, page 424's `B 13 A`, page 252's `·`), an `absentHeadings`
for page 252's `·`, the instruction order on page 16, the text that must stay, and exact image
counts where the source establishes them (36 exercises on page 16, 8 triangles on page 424, 4
exercises on page 252). Against the baseline evaluation the contract reports twelve errors; against
the candidate it passes. Column-major answer-key order, page 424's remaining label placement and
page 16's crop order are stated as not blessed.

## Verification

- `swift test`: 792 tests pass (787 before, five added).
- `scripts/check-all.sh --fast`: see the run below.
- `tools/run_corpus_regressions.py`, one case per call, probe-backed: wallace-algebra-2010,
  census-rrs2002-01, faa-phak-8083-25c, gpo-911-2004, arxiv-replay-clocks-2023,
  ntrs-20190030725-dasc-2019 and nbs-jres-geltman-1977 all PASS on both CLIs.
- `tools/check_corpus_content.py --case wallace-algebra-2010`: 219 checks pass on the candidate
  evaluation and report twelve errors on the baseline one.

## What this does not prove

The crop is a fallback, not a transcription: a rejoined row is preserved as pixels, so its exercise
or answer number leaves the selectable text. That is one representation per entry, which is what
#48 asks for, but it is not reconstruction. The 0.75 pt threshold is a property of this PDFKit on
this OS; a build whose line rectangles are padded differently would need the survey run again. The
survey covers the cached corpus only, and it measures the baseline's crops, so a book whose crops
this change grows into new rows would only show up as a conversion difference — none did outside
Wallace and Census.

## Remaining gaps

- Exercises are still `<pre>` blocks, not `<ol>` items (#29 part b).
- Answer keys set in three columns numbered down each column read across the rows (pages 443, 444,
  465, 486, 487's lower key). Filed as #178; unchanged by this work.
- Pages 423–436 keep triangle vertex letters and side lengths 0.95–6.4 pt clear of their diagrams
  as one-character paragraphs; only the labels that adjoin the crop join it. Filed as #179.
- Crops are not transcribed: a rejoined entry's number is pixels, not selectable text.

## Commands

```sh
swift build -c release
xcrun swiftc -parse-as-library -O -module-cache-path .build/raster-environment/module-cache \
  Sources/PDFReflowLib/{PageRasterizer,ConversionTypes,DocumentModel,ReflowDocument}.swift \
  tools/probe-raster-environment.swift -o .build/raster-environment/probe
python3 tools/run_corpus_regressions.py --converter <CLI> --epubcheck /opt/homebrew/bin/epubcheck \
  --output <dir> --case <id> --environment-probe .build/raster-environment/probe \
  --execution-context host-terminal
python3 tools/compare_conversion_runs.py --allow-different-converters \
  --baseline <base>/<id> --candidate <cand>/<id> --output page-comparison/<id>.json
python3 tools/check_corpus_content.py --case wallace-algebra-2010 --evaluation <dir>/wallace-algebra-2010
# the distance survey: graphicsWithLabels over every cached source, printing each line outside
# every crop that shares a row with a line inside one, with its distance to that crop's edge
swiftc -swift-version 6 $(ls Sources/PDFReflowLib/*.swift | grep -v 'EPUBWriter\|PDFConverter\|PDFReflowLibPipeline\|EPUBTextEncoder') \
  measurements/split-display-rows/survey.swift -o /tmp/survey
for pdf in corpus/cache/*.pdf; do /tmp/survey "$pdf" 24; done
```
