# Thin rules beside tightly leaded prose (#36)

Tier: deterministic Apple PDF/OCR stack, library defaults, macOS 27.0 (26A428) arm64,
Xcode 27.0 (27A266a), release CLI. Baseline: repository `56e70e2`; candidate: `56e70e2` plus the
working-tree changes described below. Executable SHA-256s are recorded in
[comparison receipts](comparison.md). No source PDF or full EPUB is committed.

## What was wrong

`LayoutReconstructor.graphicsWithLabels` grew every graphic region to whole intersecting text
lines and repeated that to a fixed point. PDFKit line rectangles on tight leading are taller than
the leading (USGS: 13.8 pt rectangles on 11.0 pt leading, so consecutive rectangles overlap by
2.7 pt before the extra 2 pt inset), so admitting one line admitted its neighbour, and the
region absorbed the whole block up to the next blank line.

The seeds differ per document, which is why the diagnosis was instrumented rather than assumed
(`Tests/PDFReflowLibTests/fixtures/{usgs-1,usgs-2,nbs-7}-layout.json` are the captured
extractions; a temporary test printed each region's absorbed lines):

- USGS copper pages 1–2: every graphic is a 1-pt rule (5 pt after the reader's padding). The
  seven page-1 and five page-2 crops each started from one section-label underline
  (`Domestic Production and Use:`, `Recycling:`, `Import Sources`, `Depletion Allowance:`,
  `Government Stockpile:`, `Events, Trends, and Issues:`, `World Resources:`, `Substitutes:`).
  The three borderless tables were preserved only because their column-header underlines
  (`2020 … 2024e`; `Salient Statistics—United States:`; `12–31–24`; `2023 2024e 2023 2024e`)
  started the same chain.
- NBS Geltman page 7: the only graphic is the page scan, which the pipeline already removes.
  The crop seed is the prose line `since the maximum driven velocity Uo = eEo/mw becomes`,
  which matches the displayed-formula heuristic (`=` and at most 12 words); its −8 pt vertical
  inset reached the neighbouring lines and the chain then absorbed 22 lines of the left
  column, stopping 0.02 pt short of `on neutral atoms.` (gap 2.02 pt against the 2 pt inset).

## What changed

`Sources/PDFReflowLib/LayoutReconstructor.swift`

- `isThinRule`: a painted rule is at most 6 pt tall and at least 12 pt and 3× its height wide.
- `isFractionBar`: a thin rule with a word-free term of at most 40 characters extending above
  it and a term of at most 40 characters starting beneath it is a fraction bar; its seed keeps
  the lines it touches. PDFKit merges denominators with trailing annotations ("8(2a + 1) Our
  Solution") and with the next numerator ("7 ÷ −9"), so terms are matched by extent rather
  than centre and need not end under the bar.
- `underlinedLine`: a thin rule inside one line's horizontal extent at or just below its
  baseline region underlines that line (used by the table detector).
- In `graphicsWithLabels`, a thin rule inside one line's box (within one body size
  horizontally, from 3 pt below the line to its top) keeps that line when the line is short
  and word-free (a radical's vinculum over "180x⁴y²z⁴", an exercise bar), and is decoration
  when the line is prose ("Recycling: Old (post-consumer) scrap, …", "Government Stockpile:
  None."). A rule outside every line's box stays an isolated graphic.
- `captures`: a thin rule captures a line only when its stroke crosses the line's inner 50%
  (a strikethrough), not when it merely touches the leading of the line above or below.
- `expanded`: whole-line expansion admits the lines a seed captures and the other pieces of
  their rows (`sameRow`, ≥50% vertical overlap: split rows, superscripts), never a line that
  only touches an already admitted line. The crop is then trimmed away from lines it merely
  touches, because `blocks` removes every intersecting line from prose; a line whose
  rectangle genuinely overlaps admitted text is admitted whole instead of being clipped, and a
  thin rule whose stroke lies inside text it does not strike is dropped. Regions carry their
  seed through `merged` (the former `clusters` pass) so re-expansion after a merge still
  reasons about graphic ink, not accumulated text.

`Sources/PDFReflowLib/TableRegionDetector.swift`

- `underlinedColumnRegions`: a row with at least three underlines, or a single short piece
  underlined whole and placed at least 30% of the page width from the left edge, is a column
  header. The table is the block of rows on at most 1.6× font-size leading around it, needs at
  least three rows below the header with at least half of them carrying digits, and becomes
  one region before expansion. A lone label underline followed by prose is not a table, and a
  row whose underlined line contains "=" (divisor bars beneath "8x = −24") is a worked
  example, not a header row.

## Before and after (release CLI, library defaults)

| Page | Before images / reflowed words | After images / reflowed words |
| --- | --- | --- |
| USGS page 1 | 7 crops / 20 words (unit note, author line) | 2 crops (statistics, tariff tables) / 354 words |
| USGS page 2 | 5 crops / 242 words | 1 crop (world production table) / 568 words |
| NBS page 7 | 1 crop 611×525 px + reference page / 639 words | 1 crop 611×78 px + reference page / 835 words |
| IRS page 1 (control only) | 5 images / 26 words | 6 images / 95 words |
| IRS page 3 (control only) | 4 images / 4 words | 4 images / 278 words |
| Our Flag page 27 (control) | 3 images / 243 words | 3 images / 243 words |

USGS page 1 now reflows the Domestic Production, Recycling, Import Sources, Depletion Allowance
and Government Stockpile sections; page 2 reflows Events, World Resources and Substitutes. The
three table crops (1301×678, 1264×209 and 1254×594 px) still pass the reviewed source-region
image checks (`corpus/references/usgs-mcs2025-copper`). NBS page 7 reflows the left column from
`equals the mean atomic field strength` through `on neutral atoms.`, with the closing paragraph
in one element; the remaining 31-pt crop is the inline-equation line with its two neighbours
(see remaining gaps). Paragraph grouping between adjacent USGS sections is decided by the
existing paragraph heuristic (the tall rectangles make the blank-line gap look like 8 pt) and is
not qualified here.

## Verification

- `swift test`: 201 tests pass (192 before, plus the ten in
  `Tests/PDFReflowLibTests/RuleAdjacentProseTests.swift`, minus a temporary diagnostic).
  Against the previous `LayoutReconstructor.swift`/`TableRegionDetector.swift`, seven of the
  first eight new tests fail with 73 issues; the Our Flag control passes on both
  ([negative log](negative-old-sources.log.gz)). The two fraction-bar tests added afterwards
  (synthetic bar and `algebra-16`) are controls that must keep passing.
- `scripts/check-all.sh --fast`: 201 Swift tests, 114 Python tests, the native-extraction
  concurrency gate (8/8 fresh processes), six fixture conversions and the policy checks pass.
- `python3 tools/run_corpus_regressions.py --converter <release pdf-reflow> --epubcheck
  /opt/homebrew/bin/epubcheck --output <new dir> --environment-probe
  .build/raster-environment/probe --execution-context host-terminal --case usgs-mcs2025-copper
  --case irs-p596-zhs-2025 --case nbs-jres-geltman-1977 --case gpo-our-flag-2003 --case
  faa-phak-8083-25c --case wallace-algebra-2010`: all six pass with the updated contracts
  (USGS 34 checks, NBS 13, IRS 12, Our Flag 58, FAA 57, Wallace 20; 382 checks in the file, up
  from 357). The baseline converter fails the new USGS and NBS contracts and passes the four
  others. An early candidate exposed a closed-range trap in the detector on Wallace page 97
  (a header row with no contiguous row below); the fix uses a half-open range.
- Strict comparison: [comparison receipts](comparison.md). Our Flag is byte-identical; no page
  of any book loses reflowed words; FAA and Wallace gain 8,464 and 1,280 words on 55 and 63
  pages where rule- or equation-adjacent prose used to be swept into crops.
- Intermediate candidates were compared the same way and drove two refinements: fraction bars
  (page-16 crops fell from 36 to 16 while their terms flattened into "42 12") and the table
  detector firing on rows of divisor bars beneath equations (Wallace pages 31 and 137 absorbed
  a caption and annotations). Both are covered by the tests above and by the final comparison.

## Remaining gaps

- FAA page 19 keeps 27 prose lines inside its figure crop because the illustration's Form
  XObject box (256.8–594 × 453.9–774 pt) extends 16 pt into the left column; with the whole
  page no longer chained into one crop, the remaining text reads with interleaved columns.
  This is the existing form-bounds behaviour in `GraphicsReader`, not rule handling.
- The displayed-formula heuristic still turns a prose line containing an inline `=` with at
  most 12 words into a crop, and its ±8 pt inset captures the immediately adjacent prose lines.
  On NBS page 7 that leaves a three-line crop (`the qualitative absorption characteristics …`
  / `since the maximum driven velocity Uo = eEo/mw becomes` / `equal to c at a Nd-glass laser
  intensity …`) inside the paragraph that precedes the closing prose. This is a separate
  formula-classification defect, not rule handling.
- When PDFKit rectangles of neighbouring lines genuinely overlap (USGS-style leading) and a
  non-rule seed captures one line, the overlapping neighbours are still admitted whole rather
  than clipped, so a figure or formula touching one line of such a paragraph can still absorb
  it. Rules no longer do this.
- A fraction whose numerator is merged into a prose line (Wallace page 137, "the slope
  rise/run") loses its bar: the numerator reflows with the sentence and the denominator on its
  own. A short underlined piece that is word-free (a page number, a date) keeps a crop of its
  own line, as before this change.
- An isolated rule that touches no text remains its own crop, as before (Our Flag page 27 keeps
  its two heading rules as images). A short heading underlined whole away from the left margin
  and followed directly by three or more tightly leaded numeric lines would still be treated as
  a table header; that was also rasterized before this change.
- The IRS Simplified Chinese publication was run only as a control and its CJK layout was not
  diagnosed or contracted.

## Post-merge gate on `c16ee67`

The change was rebased (local merge, then soft reset) onto the three later commits `3f7c23d`
(#39 citation continuations), `ad7dcf4` (#27 glyph-structure, image-appearance and
table-cell checks) and `c16ee67` (#29 exercise numbering). Conflicts were the USGS contract
`basis` sentence and the coverage count line; both sides were kept. Release CLI SHA-256
`b2f9db7729d9f8019d7f89182f0ee8ab895674514e59309f68b132bf4fe4e651`.

- `swift build`, `swift build -c release`: clean. `swift test`: 218 pass, including
  `exerciseAndAnswerNumbersCorrespondOneToOne`, `integerExercisesKeepAllFortyFourNumbersAsSeparateBlocks`,
  `squareRootExercisesStayInsidePreservedRegionsWithoutStrayText`,
  `algebraExercisesAndWarrenListsRemainPreformatted` and the four
  `loperBrightCitationLinesContinueTheirParagraphs` cases; no change was needed to them, so
  what reaches `blocks()` on Wallace pages 289/291/471 still satisfies their expectations
  (page 291's radical crops are the ones this record's fraction/short-line rules protect).
  `python3 -m unittest discover -s tools -p 'test_*.py'`: 142 pass.
- `scripts/check-all.sh --fast` on the merged tree: pass. `tools/check_structure_memory.py`:
  pass (119.7 MiB peak against the 192 MiB ceiling).
- Complete corpus lane (`tools/run_corpus_regressions.py` with the raster probe, split into
  six foreground invocations covering all 15 reviewed documents): every case passes with the
  merged contracts, 439 checks on 93 pages (414 from `c16ee67` plus this change's 25):
  arxiv 19, CDC 11, Census 6, Blue Book 9, DGA 14, FAA 58, Fed 43, 9/11 62, Our Flag 59,
  IRS 12, NBS 13, SCOTUS 25, USCIS 9, USGS 36 (including the new Salient Statistics
  `glyphRegions` and `imageAppearance` checks against this change's table crop), Wallace 63
  (including the page-343/347 `glyphRegions`). No contract threshold was changed.
