# Algebra exercise and answer-key numbering (#29)

Tier: deterministic Apple PDF stack, library defaults, macOS 27 arm64 release CLI.
Baseline: repository `3f7c23d` (after #39). `identity.json` pins both converter binaries, the
Wallace source (SHA-256 `856bd81e…`), the five new fixtures and the new source reference.
Coverage first: this record qualifies numbering and formula structures on reviewed pages, adds
regressions for what is right today, and lists what is wrong for filing. One bounded fix landed.

## Audit

Pages were rendered with `pdftoppm` at 70 DPI and read against the default release conversion
(`source-page-438.png` and `source-page-471.png` are retained; the others are reproducible).

| Page | Content | Numbering through reflow | Formula structures |
| --- | --- | --- | --- |
| 10 | 0.1 Practice, 44 integer exercises in two columns | All 44 numbers present, one `<pre>` block each, each column in order. Page order is column-major (1, 3, … 43, then 2, 4, … 44); `Find each product.` precedes only the left column | none |
| 438 | Answers – Chapter 0, section 0.1, 60 answers in three columns | All 60 present and in order within each column. **Before the fix** the 27 negative answers (`1)− 2`, no space after `)`) fell outside the list regex and consecutive ones merged into prose paragraphs such as `14)− 9 15)− 2 16)− 9 17)− 1 18)− 2 19)− 3`. The chapter heading `Answers - Chapter 0` is emitted after column 1 and the 0.2 label | 0.2 fraction answers preserved as images |
| 16 | 0.2 Practice, fractions | Numbers 1–20 live inside fraction crops; products 21–36 mix whole-entry crops with text stubs `22) (− 2)(−`, `23) (2)(−`, `27) (−`, `28) (−`, `30) (− 2)(−`, `32) (−` followed by the fraction image | fractions as images (#20) |
| 291 | 8.1 Practice, 42 square roots | All 42 exercises inside five preserved regions with `imageRegion`; no stray numbers. The instruction `Simplify.` is absorbed into a crop | radicals as images |
| 289 | 8.1 lesson, Examples 378–380 | Example labels reflow in order; each derivation is one image with `imageRegion`. The opening prose lines with inline `√180` / `√36·5` are absorbed into an image, so the paragraph starts at `fastest method` | multi-line radical derivations as images |
| 40 | 1.3 lesson, Example 66 | Five-step list retained; item 4's wrapped continuation `divide)` becomes a paragraph | aligned derivation as image; check lines reflow |
| 340 | 9.3 lesson, Examples 462–463 | – | derivations as images; a stray `x2` paragraph leaks between two crops |
| 471 | 7.7/7.8/8.1 answers | 7.8's thirty text answers present in column order (`21)17280 …` has no space and stays a lone paragraph). 7.7 entries 22 and 29 are split into `22)− 2,` / `29)−` stubs plus fraction images; 8.1 entries 1–2 are images. `Answers - Chapter 8` follows the 7.8 right column | fraction and radical answers as images |

Whole-book inventory (`numbering_regression.py` in the #39 scratch run, reproduced here): #39
changed no numbered block on any algebra page (only prose pages 67 and 161). Before the fix, 288
`N)−` lines on 37 pages were prose; on 21 of them (7 exercise pages, 14 answer pages) consecutive
entries had merged.

## Fix

`LayoutReconstructor.isList` also accepts a numeric parenthesis marker set tight against a minus
sign (`^[0-9]+\)−`). The period form is unchanged so 9/11 note continuations such as `5.This`
keep their handling; bullets and lettered markers are unchanged. A corpus scan of every gated
book found the tight `)−` form only in the algebra book.

## Regressions added

`ExerciseNumberingTests.swift` (7 tests): page 10 (44 separate numbered blocks, column order,
instruction lines in place, reviewed expressions), page 438 (60 separate entries, eleven reviewed
values, no merged pair, column order), the one-to-one exercise/answer correspondence with five
reviewed pairs, a synthetic control for tight markers versus `5.This` and `2)(3)` prose, page 291
(every exercise inside a crop, none as text), page 289 (derivation lines inside crops, labels in
order each followed by an image, prose retained, `Our Solution` not leaked) and page 471 (thirty
reviewed 7.8 answers in column order). `before-tests.log.gz`: against `3f7c23d` the three
answer-key tests fail with 24 issues; the four pinning tests pass.

`corpus/regressions.json` adds pages 10, 438, 289, 291 and 471 (wallace 20 → 61 checks before the
#27 glyph checks, 63 after merging them; 7 → 12 pages; lane 414 checks on 93 pages after the merge
with `ad7dcf4`) with ordered exercises and answers per column, headings,
`imageRegion` warnings, `absentText` for numbers that must not leak from crops, and a
source-rendered reference `page-289-example-378.png` (region 165,200–415,285 points from the
top-left) for the Example 378 derivation. Column-major page order and the displaced headings are
not pinned.

## Verification

- `swift test`: 208 tests pass.
- `scripts/check-all.sh --fast`: 208 Swift tests, 114 Python tests, 8/8 concurrency trials,
  6 fixture and 13 policy conversions pass.
- `tools/run_corpus_regressions.py --case wallace-algebra-2010 --case faa-phak-8083-25c
  --case gpo-911-2004`: all three pass EPUBCheck, progress, memory and content gates
  (`corpus-summary.json`).
- `page-comparison.json` (pre-fix lane versus this lane): algebra changes on exactly the 37
  pages that carry `N)−` lines, 365 lines move from `<p>` to `<pre>` (2,824 → 3,189), no page
  text or character changes, all images byte-identical; FAA and 9/11 are identical page for page.

## Defects to file (reproducers)

1. Answer-key reading order displaces section headings. Page 438: expected `Answers - Chapter 0`,
   `0.1`, `Answers - Integers`, entries, `0.2`, …; observed `0.1`, entries 1–21, `0.2`, fraction
   images, then the heading and columns 2–3. Page 471: `8.1` and its first two answers precede
   the 7.8 right column. Cause: `ordered()` cuts the wide left gutter before the centered title,
   which does not span it. Not bounded (touches every multi-column page).
2. Fraction answers and exercises split between a marker stub and an image. Page 471 entries 22
   (`22)− 2,` + image of `5/3`) and 29 (`29)−` + image of `2/3`); page 16 exercises 22, 23, 27,
   28, 30, 32. Expected: one representation per entry. `FractionRegionDetector` unions only a
   prefix ending in `=`; a marker-with-sign prefix within a few points of the bar is a candidate
   bounded extension but changes crops on many pages, so it was left for a separate change.
3. Page 340: a stray `x2` paragraph between the Example 462 crops (source `x² + 10x = −24`).
   Expected: the whole derivation in one image.
4. Instruction and prose lines absorbed into crops. Page 291 loses `Simplify.` from text; page
   289's opening sentence with inline radicals is inside an image, so the paragraph begins at
   `fastest method`. Expected: instructions and prose reflow.
5. Page 40: a wrapped numbered-list item (`4. Solve the remaining 2-step equation … multiply or`
   / `divide)`) emits the continuation as a paragraph. Expected: one item block.
6. Semantics (issue part b): exercises remain `<pre>` blocks in column-major order, not `<ol>`
   lists; instructions such as `Find each product.` apply visually to both columns but precede
   only the left one after reflow.

## Remaining gaps

Radicals, multi-line derivations and complex fractions are preserved as warned images, not
transcribed; the checks prove presence and alignment of reviewed crops, not every glyph. The
review covers sections 0.1, 0.2, 1.3, 7.8, 8.1 and 9.3 pages only; other sections were checked
only by the whole-book marker inventory.
