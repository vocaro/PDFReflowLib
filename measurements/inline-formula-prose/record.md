# Inline mathematics beside formula and figure crops (#51, #58, #49, #77)

Tier: deterministic Apple PDF/OCR stack, library defaults, macOS 27.0 (26A428) arm64,
Xcode 27.0 (27A266a), release CLI. Baseline: repository `394147f` (release SHA-256
`6769041a1b5c38e24b6783d9cbd3fd3a7ab2e5aac133a79ca48665a939fb974f`); candidate: `394147f` plus
these working-tree changes, merged forward onto `9cf6b85` (tooling only; release SHA-256
`df8d4d936705e1c449804a565d095ef9bc9977801ef888b85b6393467f9c2d35`, identical when rebuilt). No
source PDF or full EPUB is committed.

## What was wrong

Each page was diagnosed from its native extraction (`Tests/PDFReflowLibTests/fixtures/{nbs-7,
algebra-288,algebra-289,algebra-291,faa-227,faa-195}-layout.json`) with a temporary test that
printed every formula seed, graphic, fraction and table seed and the lines each final region
intersects.

- **NBS Geltman page 7 (#51).** The only seed is the formula heuristic on the justified prose
  line `since the maximum driven velocity Uo = eEo/mw becomes` (`=` and at most 12 words). Its
  −8 pt vertical inset reached the lines above and below, and a non-rule seed captures every
  line it touches, so a three-line 611×78 px crop sat mid-paragraph.
- **Wallace page 288 (#58).** Sixteen lines carry `√` or `=`. PDFKit splits each prose row at
  an inline radical (`The square root of 25 is written as` + `25 √ .`, `Not all numbers …
  if we found 8` + `√ on`, `We can use the product rule …` + `√ by spliting` + `36· 5`), and
  every piece carrying the symbol seeded a formula whose ±8 pt margin took the neighbouring
  prose. The radicals' bars are graphic seeds too: the 16-pt bar over `25` is a thin rule owned
  by the short word-free piece `25 √ .` and keeps that piece, and the 10-pt bar over `8` is too
  short to be a rule and seeds a crop of its own. Five crops held 13 prose lines; only the
  Example 377 table and the displayed product rule are displays.
- **Wallace page 289 (#49).** The opening row `process is being able to translate a problem
  like √180 into √36·5 . There are sev-` seeded two formulas that captured the next line,
  `eral ways this can be done …`, so the reflowed page began at `fastest method`.
- **Wallace page 291 (#49).** Exercise `1) √245` seeds a formula; its +8 pt margin reached
  `Simplify.` 3 pt above, so the instruction joined the column's exercise crop.
- **FAA page 227 (#77).** Not a formula: the compass-rose illustration is a transparency group
  whose Form XObject `BBox` (71–310 × 116.3–298.1 pt) overhangs the figure's own rounded clip
  (72–309 × 124.1–282.9 pt) by 13 pt into the column above. `GraphicsReader` recorded the whole
  box as figure ink, and the crop took `true course desired.` (294.6 pt). On the right column
  the word equations under `Step 1:`, `Step 2:` and `course is known:` seeded formula crops
  whose margins also took the step labels.

## What changed

`Sources/PDFReflowLib/GraphicsReader.swift`

- A Form XObject's bounding box is added as figure ink only where it intersects the clip in
  force when the form is drawn (the clip is already a conservative bounding rectangle).

`Sources/PDFReflowLib/LayoutReconstructor.swift`

- `isProseRow`: a line's visual row (the pieces PDFKit split it into, joined across gaps that
  text above or below spans) is prose when it reads as words (at least two words of three or
  more letters; words of two or more letters at least 40% of the tokens) and sits on its
  paragraph's measure: either at least three prose lines on the page share both of its edges
  (or two, one adjacent at ordinary leading), or an adjacent such full line shares its left or
  right edge (a paragraph's first or last line). A row whose pieces stand at least twice their
  type size stacks terms and must also contain a function word (`the`, `we`, `of`, …), so a
  stacked full-measure display such as Wallace page 428's `sin⁻¹(opposite/hypotenuse) = θ`
  stays a formula.
- The formula seed skips prose rows (the URL-query rule from #80 is kept), and its ±8 pt margin
  is cut short of any neighbouring line that is a prose row or, above the formula, a row of
  words alone (`Simplify.`). Lines with any term, number or operator, words sharing a row with
  other pieces (`Our Solution`) and words beneath a formula (`Infinite solutions Our Solution`)
  are still captured.
- A short painted bar (at most 6 pt tall) inside a prose row that carries a mathematical symbol
  is that row's decoration, as underlines beneath prose already were (#36).
- `expanded`: trimming accepts a cut within 0.01 pt of the kept ink. After the clip change the
  FAA page-195 figure box ended exactly at its crop edge and a cut rebuilt from origin and size
  fell 0.00001 pt short, so the crop absorbed the figure caption and the column's last line.

## Before and after (release CLI, library defaults)

| Page | Before crops / reflowed words | After crops / reflowed words |
| --- | --- | --- |
| NBS page 7 | 2 images (611×78 px crop + reference) / 835 | 1 (reference) / 876 |
| Wallace page 288 | 5 / 171 | 2 (Example 377 table, product rule) / 317 |
| Wallace page 289 | 4 / 73 | 3 (Examples 378–380) / 108 |
| Wallace page 291 | 5 / 5 | 5 (all 42 exercises) / 6 (`Simplify.`) |
| FAA page 227 | 5 / 544 | 2 (correction card, figure trimmed to its frame) / 593 |

Book totals from per-page digests of both EPUBs (reflowed words, preserved images), reviewed
page by page against source renders with the removed and added crops beside them:

| Case | Contract (checks) | Pages changed | Words | Images | Pages with a missing token |
| --- | --- | ---: | ---: | --- | ---: |
| Wallace algebra | base fails 8, candidate passes (104) | 61 | +1,747 | 2047 → 2026 | 4 |
| FAA handbook | base fails 7, candidate passes (211) | 62 | +1,663 | 598 → 581 | 1 |
| NBS Geltman | base fails 2, candidate passes (17) | 1 | +41 | 8 → 7 | 0 |
| USGS copper | both pass (49) | 0 (strict compare identical) | 0 | 3 → 3 | 0 |
| Our Flag | both pass (67) | 0 (strict compare identical) | 0 | 147 → 147 | 0 |
| 9/11 report (extra) | both pass (191) | 165 | +16,495 | 516 → 141 | 12 |
| arXiv Replay Clocks (extra) | both pass (59) | 8 | +668 | 61 → 45 | 0 |
| Census report (extra) | both pass (54) | 6 | +326 | 54 → 53 | 0 |
| Blue Book 14 (extra) | both pass (9) | 6 | +74 | 424 → 424 | 0 |
| Fed, DGA, CDC, Loper Bright (extra) | all pass | 0 (strict compare identical) | 0 | unchanged | 0 |

Every "missing token" is a hyphenated fragment that now joins the word it was split from at a
former crop edge (`hori-` → `horizontal`, `resents` → `represents`, `cals` → `radicals`,
`tion.` → `section.`; FAA `float-` + `type` → `float-type`; 9/11 `com-` → `commando`,
`raising` → `fund-raising`, `stair-` → `stairwell` and nine more). No page lost a word. The
9/11 report extracts line-end hyphens as `=` (`knowl=`, `pro=`), so short justified prose lines
seeded formula crops; they now reflow. Review notes:

- Wallace: every displayed derivation, table, exercise column and answer key reviewed stays
  whole; pages 391, 405 and 480 split one exercise or answer crop into two column crops with
  the same entries; page 293 and FAA pages 58, 106, 113, 121, 179, 184 re-cut a crop by a few
  pixels with the same content (FAA's figure crops lose the empty overhang above their frames).
  The page-121 figure region, image-appearance and all Wallace glyph and region checks pass.
- FAA page 227's word equations (`True Course (180°) ± Variation (+10°) = Magnetic Course
  (190°)`) are single-level body text set in the column's measure; they reflow in order after
  their step labels, joined to them in one paragraph. Page 102's displayed drag equation and
  every figure reviewed stay preserved.
- Census was measured with the candidate copied out of `.build/release` (see the defects below).

## Verification

- `swift test`: 410 tests pass (402 at `394147f`/`9cf6b85` plus the eight in
  `Tests/PDFReflowLibTests/InlineFormulaProseTests.swift`; `geltmanClosingProseReflowsAroundItsInlineEquation`
  now requires no crop and the inline line inside its paragraph).
- Negative control ([log](negative-old-sources.log.gz)): with the `LayoutReconstructor.swift`
  and `GraphicsReader.swift` of `7c46377` (the tip when it was run), seven of the nine tests
  fail with 36 issues; the two synthetic
  controls (a displayed equation between paragraphs, a stacked full-measure display) pass on
  both. Single-rule mutations ([log](mutants.log)): removing the prose-row test fails four tests,
  the margin trim one (`Simplify.`), the radical-bar rule one (page 288), the stacked-display
  sentence guard one, the 0.01-pt trimming tolerance one (page 195) and the form clip one.
- `scripts/check-all.sh --fast`: 410 Swift tests, 196 Python tests, six fixture conversions, 13
  policy conversions and 22 rejection/cleanup cases, and repeat-run identity on all six fixtures.
- Corpus lane: `tools/run_corpus_regressions.py --converter <CLI> --epubcheck
  /opt/homebrew/bin/epubcheck --environment-probe .build/raster-environment/probe
  --execution-context host-terminal --case <id>`, one case per invocation for the baseline and
  the candidate, then `tools/compare_conversion_runs.py --allow-different-converters` (no
  provenance errors in any case). Contract totals: 1041 checks on 218 pages (25 added).
- An intermediate candidate required a function word in every prose row. It cropped a
  justified FAA line mid-sentence (page 396 `variation (V) = magnetic heading (MH) ± deviation
  (D)`) and split page 227's second word equation between text and an image, so the sentence
  test applies to stacked rows only. Earlier candidates also trimmed derivation annotations
  (Wallace pages 49, 149, 207, 359) and are superseded.

## Remaining gaps

- PDFKit's separate radical pieces (`√ on`, `√ by spliting`, `√ . There are sev-`) reflow as
  blocks of their own, some a line out of place (Wallace pages 288, 289, 299). All words are
  present; joining a split row into its paragraph belongs to `blocks()`.
- A prose line cropped because it holds an inline stacked fraction or floor expression is not
  addressed (Wallace page 305 `Consider 2/(√3−5)`, arXiv page 5 `mx.f = ⌊mpt.f/I⌋`, Blue Book
  page 65 `Having found the angle ZS … from the formula:` above its display, Census page 19
  `θ₂ = −√(1−σ²). The mixture distribution`).
- 9/11 still crops an indented first line or bullet item whose `=`-hyphen right edge sits off
  the justified edge (pages 170 and 205 reviewed; 141 images remain in the book, not all classified).
- The overlapping-rectangle gap from #36 remains for seeds that are not prose rows: a formula
  whose tall pieces genuinely overlap a neighbouring line still admits that line whole.
- FAA's PAVE sub-headings are inconsistent: `P = Pilot in Command (PIC)` (page 47) and `E =
  External Pressures` (page 48) now reflow, while `A = Aircraft` (page 47) stays a smaller crop
  because its short line shares no edge with an adjacent full line; all were crops before.
- Blue Book page 245's `Number | Per Cent` table-header fragment now reflows beside its crop.

## Defects to file

- **Vision OCR output depends on the converter's location.** Census report
  (`census-rrs2002-01`), pages 2–20: the byte-identical `394147f` release binary run from
  `.build/release/pdf-reflow` transcribes `re-identilicatiou`, `rauk`, `uoise`, `(see |18))` and
  changes 17 pages (and one image) relative to the same binary copied to another directory,
  which reads `re-identification`, `rank`, `noise`, `(see [ 18])`. Each location is repeatable
  and CPU load does not change it; `OCRReader` in a test process also reads the clean text.
  Expected: OCR transcription independent of the executable's path.
- **Split radical rows reflow as separate, misordered blocks.** Wallace pages 288/289 (above).
  Expected: one paragraph in reading order.
