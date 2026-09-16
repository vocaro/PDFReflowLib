# Shaded sidebar boxes and text tables (#54)

Tier: deterministic Apple PDF/OCR stack, library defaults, macOS 27.0 arm64, Xcode 27, release CLI.
Baseline: repository `417edc7` (built from `git archive 417edc7`, SHA-256
`5da2f292ec9eb3504e54680a45bdda2aecbf59987d883074d4ba6b8943ff43c3`); candidate: `417edc7` plus the
working-tree changes described below (SHA-256
`690ca60bb54de785d9fa276f25b0d0c15828709929cd370b821c2bb4541c8017`). The work was developed on
`e1cbc0d`, parked in a WIP commit, merged with `417edc7` (conflicts in `ReflowDocument`,
`EPUBTextEncoder`, `EPUBWriter` and `LayoutReconstructor.blocks` resolved keeping both sides) and
soft-reset onto `417edc7`; every figure here is against the `417edc7` CLI. No source PDF or EPUB is
committed.

## What was wrong

In *The Fed Explained* every sidebar box and every text table became one preserved-region image.
The seeds are not figure ink. A diagnostic survey of all 135 pages (a throwaway tool that dumps
`GraphicsReader` footprints, text lines and the marked-content roles of each page) shows:

- Page 32 (Box 3.1, eight paragraphs of prose): two graphics, the running-header rule and one
  `90.5 204.5 431 497 re S`, a *stroked* frame painted as an `/Artifact`. Its path bounding box
  covers all 38 box lines, so whole-line expansion preserved the whole box. The box text is tagged
  `H4` and `P`.
- Page 58 (Box 4.2): the same stroked frame plus two small `re f` fills behind the two list
  headings; 61 of 63 lines inside.
- Page 40 (Box 3.3, prose above two line charts): the frame plus 32 chart paints, all inside
  `/Figure` marked content. The charts' tick labels and legends are not extractable text at all
  (PDFKit lists no lines for them), so any crop must keep the chart's surroundings, not just its ink.
- Pages 64, 83, 120 (text tables): row-shading `re f` bands (one path per row spanning both columns
  on 64; section bands and per-column tints on 83/120), 0.5-pt `m/l S` rules between rows and
  columns, and a box frame drawn either as `re S` or as four stroked lines whose sides are split
  per row. The cells are tagged `TH`/`TD`, which the structure reader does not consume.

`GraphicsReader` clustered all of these with everything inside them before layout saw any text,
so `graphicsWithLabels` had a single non-thin seed per box.

## What changed

`Sources/PDFReflowLib/GraphicsReader.swift`

- Every painted footprint is recorded as a `Paint` with a `frame` flag: a path made only of `re`
  rectangles (filled or stroked) painted outside any `/Figure` marked content (BDC/BMC/EMC are now
  tracked, and a form inherits the caller's figure nesting). `regions` are still the clustered
  footprints, unchanged.

`Sources/PDFReflowLib/TintDetector.swift` (new; run from the pipeline once the page's lines are
known, and from `SourceLayoutFixture.content()` for fixtures that carry `paints`)

- Frame candidates are the non-thin frame paints plus closed boxes of four thin strokes (collinear
  segments joined, only the outermost box). A cluster of candidates is a tinted block when it
  holds at least three prose lines (four or more words, at least 40% of the block's width) that no
  solid ink touches, and those prose lines are at least a third of the lines inside it. Members
  holding text become tints and seed no crop.
- Thin ink groups that touch only each other inside a tinted block are separators (rows, columns,
  box borders) and seed no crop; a lone fraction bar keeps its terms. A grid of interior rules whose
  union the block's bands and cells shade by less than 80% is a ruled table this reader cannot
  parse: its rules and frame strokes stay a crop (Fed page 46, Table 3.1).
- Solid ink inside a tinted block keeps the block's full-width band between the prose above and
  below its core (border strokes along the block's edges excluded) as one crop, so a chart's
  raster-only labels, captions and notes stay with it while the prose reflows.
- `graphics` are re-clustered from the remaining paints exactly as the reader did (same distance,
  same order), so a page without tints composes identically.

`Sources/PDFReflowLib/ShadedTableDetector.swift` (new) and `ReflowBlock.Content.table`

- A cluster of tints (frames excluded) is read as a table: rows from band edges and from rule lines
  covering half the width, extended beyond the bands only where rules subdivide the rest of the
  box; columns from left edges shared by half the rows; one column pair merged when a body line
  spans exactly two (PDFKit merges "Y" with "Bank Holding Companies…"); section rows are single
  first-column lines that cross the columns or sit on a full-width band of their own, in the body's
  size; the header is the first grid row on its own band with two columns of text, its cells
  spanning empty columns; trailing one-column lines ("(continued on next page)") are notes. Any
  crossing body line, leading/trailing prose in the run, fewer than two columns or two body rows
  rejects the table. Cells join lines like paragraphs. `EPUBTextEncoder.table` serializes
  `<table><thead>…</thead><tbody>…</tbody></table>` with `colspan`; `EPUBWriter` adds table CSS.

`Sources/PDFReflowLib/LayoutReconstructor.swift`

- `blocks`: table lines leave the spatial elements as one `.table` element; each tinted box is read
  as one float (`boxed`): its elements are ordered among themselves, the box follows the lines
  beside it and precedes the lines below it (as its image did), and a boundary element flushes
  paragraphs at its edges. The heading body-size estimate and section labels are measured on lines
  outside boxes and tables, so a page whose sidebar outweighs its prose keeps that prose as
  paragraphs (page 46 otherwise turned every body line into a heading).
- `appendPage`: text inside tinted boxes competes with a cross-page join anchor only when body-sized,
  as text inside images does (page 11's Figure 1.3 title band otherwise blocked the page 11→12 join).

`PageContent` gains `tints` and `separators` (spilled and reloaded by `PageStore`); the pipeline
composes them after tags are applied and keeps the page-sized-graphic review signal on the
pre-tint regions. `tools/capture-layout-fixture.swift` records `paints`; `tools/check-epubs.py`
admits an oversized `table` block; `tools/check_corpus_content.py` separates cell text with spaces.

## Before and after (release CLIs, library defaults)

Fed, all 135 pages, `tools/check_corpus_content.read_pages` text and image sets
([page-comparison/fed-explained-2021.txt](page-comparison/fed-explained-2021.txt)): text changes on 77
pages, +10,677 words and no page losing a word; images 315 → 262; `<table>` elements 0 → 7 (pages
64, 82, 83, 97, 109, 120, 121). Word recall the way the issue measures it, with
`--repeated-headers-and-footers keep` ([recall.txt](recall.txt), [recall.py](recall.py)): 65.05%
(29,919 of 45,995 words) → 88.77% (40,830); pages below 0.95 recall or 0.85 order 89 → 72; pages
keeping under 5% of their words 7 → 0. The remaining recall gap is mostly hyphen repair, which the
word-multiset measure counts against ("guid-" + "ance" → "guidance" loses two source tokens), plus
figure pages that stay images.

| Page | 417edc7 | Candidate |
| --- | --- | --- |
| 32 Box 3.1 | 1087×1252 crop, 95 words | heading + 5 paragraphs, 587 words, only the header rule crop |
| 40 Box 3.3 | 1090×1186 crop, 115 words | title + 3 paragraphs, one 1090×562 band with both charts, captions and notes |
| 58 Box 4.2 | 1088×1531 crop, 0 words | heading + paragraphs + two bulleted columns + source note, 529 words |
| 64 Figure 4.6 | 1092×1393 crop, 0 words | heading, intro, 2-column `<table>` (header + 7 entities), 601 words |
| 83 Figure 5.7 | crop, 0 words | heading, 2-column `<table>` with header, 4 section rows, 16 regulations, note |
| 120 Figure 7.2 | crop, 0 words | heading, intro, 2-column `<table>` (3 section rows, 9 laws), note |
| 19, 22, 26–28, 33–37, 41–42, 56–57, 60–63, 71–74, 78–80, 84–85, 92, 94, 122, 125 | narrow sidebar crops | sidebars reflow as one float after the lines beside them |
| 9 Figure 1.1 | 1090×823 crop | title band and description reflow; figure 1090×710 |
| 46 Table 3.1 | table crop + sidebar crop | table crop unchanged; sidebar reflows |
| 77, 86, 103, 75 | figure boxes | unchanged or figure band only (short-fragment figures keep their images) |

Hand review against 60-DPI source renders of pages 9, 19, 32, 39, 40, 46, 58, 64, 75, 83, 120 and
126: the reflowed box text is in source order (page 32's run-in heads keep their bold runs inside
their paragraphs; page 58's two bulleted columns interleave line by line, see gaps); the page-40
band holds charts A and B with their axis labels, legends, captions and notes and nothing of the
box prose (checked against the source-rendered region reference
`corpus/references/fed-explained-2021/page-40-box-3-3-charts.png`); the table cells on 64, 83 and
120 match `pdftotext -layout` word for word after hyphen repair (transcribed into the contract);
page 83's letter and name read as one cell, which is the source's own header
("Regulation (by letter and name)"); page 46 keeps Table 3.1 as an image and reads its sidebar
after the line beside it, splitting the body paragraph once at the box edge (the image used to
split it at the same place).

Control books, same comparison ([page-comparison/controls.txt](page-comparison/controls.txt)):
DGA (10 pages), USGS copper (2), Our Flag (56), Wallace algebra (489) and FAA (522) have no text or
image change on any page; their EPUBs differ from the baseline only by the added table CSS. No
frame cluster in those books passes the prose test, so no tint is detected and composition is
identical. DGA's shaded section bands are ink footprints (vertical strokes and illustrations), not
`re` fills behind prose, and remain the #13 case.

## Verification

- `swift test`: 281 tests pass (267 at `417edc7` plus the 14 in
  `Tests/PDFReflowLibTests/TintedBoxTests.swift`). The fixture-derived tests use `content(tinted:
  false)` to prove each Fed fixture still reproduces the crop, and the synthetic controls (bar chart,
  flowchart, sparse frame, ratings grid, ruled table with a shaded header only) require
  `TintDetector.compose` to return the reader's clusters unchanged.
- `python3 -m unittest discover -s tools -p 'test_*.py'`: 160 tests OK (159 plus the reader's
  table-cell spacing/grid test).
- `scripts/check-all.sh --fast`: exit 0 (281 Swift, 160 Python, 8/8 concurrency trials, fixture and
  policy conversions).
- Corpus lane (`tools/run_corpus_regressions.py --converter .build/release/pdf-reflow --epubcheck
  /opt/homebrew/bin/epubcheck --execution-context host-terminal`, one output directory per run,
  [lane-summaries/](lane-summaries/)): Fed 81 checks pass (45 before; the contract adds headings,
  paragraphs and ordered text on pages 32, 40, 58, 64, 83 and 120, `tableCells` transcriptions on
  64 and 83, the Box 3.3 region reference on 40 and the reflowed sidebar on 46, and drops page 32's
  `minimumImages`, which only the running-header rule strip would satisfy; page 120 has no header
  row, so its rows are ordered text, not cells). DGA 14, USGS 36, Our Flag 59, Wallace 63 and FAA 61
  pass unchanged. The `417edc7` CLI against the new contract fails on exactly the 33 new
  expectations and nothing else ([negative control](lane-summaries/fed-417edc7-negative-control.json)).
- Contract totals: 621 checks on 129 pages (585 on 124 at `417edc7`), counted per expectation entry.

## Remaining gaps

- Two-column bulleted lists inside a box (page 58's "Emergency lending facilities") interleave
  line by line: the columns are too narrow for the whitespace-cut prose test, and their wrapped
  continuations become separate `<p>`/`<pre>` blocks (the page-9 `<pre>` fragments in the issue,
  #50). Not addressed here.
- Two-line box titles become two headings (page 40, "Box 3.3. Interest on Reserve Balances as a
  Key Tool of" / "Monetary Policy Implementation"); the spatial heading path emits one heading per
  line and structure tags fall back on 118 Fed pages.
- Figure boxes whose labels PDFKit merges into short fragments (page 77's ratings grid, page 86's
  Basel columns, page 103's banknote captions, page 75's LISCC diagram) stay images by design; their
  titles and introductions could reflow with a finer ownership rule.
- A ruled text table without row shading (page 46, Table 3.1) stays an image; reading it would need
  per-glyph geometry to split the header cells PDFKit merges into one line.
- Page 46's body paragraph is split once by the floated sidebar, where the image split it before.
- The running-header rule remains an isolated 4-pt crop on every Fed page, as before (#36 kept
  isolated rules).
- Tables that continue across pages (82→83, 120→121) are separate `<table>` elements.
- Untagged documents get the same rules; the `/Figure` evidence only protects rectangles inside
  tagged figures. A figure background rectangle holding three or more wide prose lines with no ink
  touching them in an untagged document would reflow that prose and keep the ink band.
