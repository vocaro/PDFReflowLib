# Table follow-ups: letter-spaced headings, same-size titles, FAA's NDB table, USGS tables (#198)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, Xcode 27, release CLIs.
Work on `07c1bbd` (branch `claude/fable-agents-coordination-d95da7`). Date 2026-09-18.

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline | `07c1bbd` | `1014a2ef0ea0b158a040da653d76c5dadec9ba882b3e72bacd868009ddd4c0e1` |
| candidate | this tree on `07c1bbd` | `6ba658468f15d13afe0ffd8363d535fdcfae43d1b05ade645086c1f69ddb7822` |
| final | this tree, comments reflowed since the candidate | `ba230215ac37c94cc62e493ee3ff78d4a11da56d1f9d15a5c57f0e2943155a13` |

Both converters ran as `pdf-reflow` from separate directories, so they shared one Vision model
cache name. No PDF, EPUB or lane output is committed. Only English sources were read.

Of #198's five points, 1 (letter-spaced `(Miles)`) and 2 (titles at cell size) are fixed. Points 3
(FAA's NDB table) and 5 (USGS) were measured; neither is read by a narrow change, and the evidence
below says why. Point 4 (Census page 14) was not in this work's scope.

## 1. Letter-spaced type PDFKit spells apart

**Evidence.** FAA page 410's distance heading is one show:
`[( )-578 (\()-192.7 (M)-192.7 (i)-192.6 (l)-192.5 (e)-192.5 (s)-192.9 (\))]TJ` at `0 Tc 0 Tw`,
0.19 em between every glyph. PDFKit returns the line as `( M i l e s )`, starting at the `(`
(268.6), 8.3 pt right of the show's origin (the space glyph and its 0.578-em adjustment, which PDFKit
leaves off the line). No existing repair applied: `extraSpaces` is Type3-only, and a show's origin
outside the line's rectangle gives the line no shows at all.

**Rule** (`NativeSpacingReader.letterSpacedRuns`, `letterSpaces`, `withoutLetterSpaces`). The reader
records each glyph's start and its gap after the glyph before (character and word spacing plus any
adjustment). A run is at least three glyphs of one show, most of them letters, none whitespace or a
mathematical operator, with gaps equal within 0.02 em and between 0.1 and 0.5 em (above 0.5 em is
#120's column gap), standing whole-word apart: each neighbour is a space, an operator, the show's
edge or at least 0.05 em further away. The line holding the run's first glyph (one line rectangle
only) loses the spaces PDFKit sets between the run's characters, when the run appears exactly once
in its text; the line's other repairs then read it with the run whole.

Each guard is from the corpus:

- **Whole words.** Wallace's justified TeX sets word spaces as adjustments, so a one-letter word
  between two equal spaces spaces three glyphs alike (`d|o a q|uick`, `b|e a r|eview`, `Algebr|a - I|n`).
  Without the neighbour test, Wallace pages 7 and 8 lost those spaces (`doaquick`,
  `Pre-Algebra-Integers`) and the #188 operator tests failed.
- **Most glyphs letters.** The 9/11 report spaces its ellipses the same way: a first candidate that
  asked for one letter joined them on pages 219, 347 and 506 (`need . . . a` into `need ...a`).
- **The line's other repairs still apply.** That candidate also returned as soon as it removed a
  run's spaces, so the same lines lost the space #128 restores before an opening quote
  (`paper.“We`, `us,“I`, `communication,“Summary`), and page 164's note references changed. Both
  were fixed before the final runs, which change no 9/11 page.

## 2. Titles set in the cells' size

**Evidence.** Census sets each title one line above its table in the cells' 9-point type:
`Table 2. Domingo Data Reidentification Rates` at 631.3 over a header at 601.4–611.8 (its bottom
19.5 pt, 2.2 body sizes, above the header's top), 210.4–401.9 over a table at 244.6–370.3 (wider
than the table and centred on it); Tables 3, 7 and 8 the same way (Table 8's title 163.2–449.0).
`ShadedTableDetector.caption` needs a title at least 15% larger than the cells, so the #150 tables
had none, and the titles stayed paragraphs before them.

**Rule** (`BorderlessTableDetector.title`, used by both borderless readers). The lines directly above
the table within its width widened by an em: the nearest within three body sizes of its top, each
higher one within two of the line beneath, each alone on its baseline in that band, untagged or
tagged as text, within 15% of the cells' size, sharing a left edge or a centre within half an em,
up to a line that opens with a table label closed by a period, a colon, a dash or a capital, or
standing alone (`Table 2.`, `TABLE III`); three lines at most. The label is the evidence: FAA page
410's `VOR/VORTAC NAVAIDS` and `Normal Usable Altitudes and Radius Distances` have the form of a
title and stay paragraphs, and a sentence that names a table (`Table 2 shows…`) is no title.

## 3. FAA page 416's NDB table (not read; measured)

Extraction's words on the table's baselines (`dbg` driver over `NativeTextReader.lines`, x ranges in
points):

| Baseline | Words |
| --- | --- |
| 394.3 | `Power` 434.0–461.2, `Distance` 503.2–539.8 |
| 381.8 | `Class` 321.0–343.8, `(Watts)` 431.5–463.7, `(Miles)` 507.8–537.8 |
| 369.6 | `Compass Locator` 321.0–391.3, `Under 25` 431.5–469.0, `15` 547.1–558.0 |
| 357.1 | `MH` 321.0–337.1, `Under 50` 431.5–469.0, `25` 546.6–558.0 (PDFKit's text `2 5`) |
| 344.6 | `H` 321.0–328.2, `50–1999` 431.5–466.5, `*50` 542.6–558.0 (a line of its own, **7 pt**) |
| 332.1 | `HH` 321.0–335.4, `2000 or more` 420.9–494.3, `75` 546.7–558.0 |

Four things keep it from the aligned-column rule, not only the `*50`:

1. `*50` is a PDFKit line of its own reported at 7 pt, the size of its raised `*` (`7 0 0 7 542.55
   350.40 Tm (*)Tj`, then `50` at 10 pt with `0.115 Tc`), so the `H` baseline is not in the body's
   size and the body stops above it.
2. `*50` is not a number (`ColumnGrid.isNumber`), so the distance column would hold a number in
   three rows of four.
3. **The power column is neither flush nor centred.** `2000 or more` is set at `0.13 Tc 0.259 Tw`
   from 420.9, 1.06 em left of the other cells' shared left edge (431.5); the column's left edges
   spread 1.06 em, its right edges 2.8 em and its centres 0.86 em (450.3, 450.3, 449.0, 457.6). The
   rule's flush test (a quarter em) is what keeps worked examples, glossaries and rosters out
   (#150's prototype survey), so accepting this column means accepting ragged ones.
4. PDFKit reads `25` as `2 5`: `(       2)Tj` with `0.402 Tw` ends the `2` at 551.64 and
   `23.198 0 Td (5)Tj` starts the `5` at 552.98, 0.134 em apart (`15` is `(1)-85.7 (5)`, 0.086 em,
   and reads whole). The cell would split into two pieces.

Fixing 1 and 2 alone reads nothing, so no partial change was made.

## 5. USGS's statistics tables (not read; measured)

The same driver over `mcs2025-copper.pdf`. The three tables are also preserved as images before
layout reads text (#36's underlined-column regions in `TableRegionDetector`, which the contract
pins), so a text reading needs both a grid and a change to that preservation.

**Page 1, Salient Statistics.** Extraction's candidate region spans the table (a stack of numbers in
each year column); the body fails on:

- the label column, 46.3–323.0 pt, 27.7 ems wide (the cap is fifteen; `Apparent, primary refined
  copper and copper from old scrap3`);
- group rows holding a label alone (`Production:`, `Refinery:`, `Imports for consumption:`,
  `Exports:`, `Consumption:`, `Price, annual average, cents per pound:`), which leave the row unfilled
  (`[[1,0,0,0,0,0],[1,1,1,1,1,1],…]`); their members are indented 0.8–1.7 em;
- a wrapped label whose first line has no values (`Stocks, refined, held by U.S. producers,
  consumers, and metal` / `exchanges, yearend 118 117 84 127 70`), which reads the same as a group row;
- and, once a body reads, its header row `Salient Statistics—United States: 2020 … 2024e` holds
  first-column text over a year in every numeric column, which the header rule takes for a body row
  (years head their columns only over an empty label heading).

**Page 1, Tariff.** PDFKit returns each row as one line ending in its trade-relations text
(`Unrefined copper anodes 7402.00.0000 Free.`), so no three lines end in a number at one right edge and
extraction finds no candidate region at all; split, its label column (`Copper ore and concentrates,
copper content`, 201.4 pt at 10.1 pt) would be 19.9 ems wide and its third column is centred, not flush.

**Page 2, World Mine and Refinery Production.** Extraction reads rows `United States` to `Other
countries` as a grid (18 rows, 6 columns; `World total (rounded)` is indented 0.79 em, so the label
column is not flush with it), but layout reads a different one and the cut is dropped: layout's
candidate windows come from stacks of numbers at one right edge, and the `—` cells (Germany, Japan,
Korea) and the estimates marked with a raised `e` (`e740`, `e890`, `e1,000`) break those stacks, so
layout's regions cover 13 and 10 baselines of the table rather than all of it. Australia's reserves
also read `7100,000`: the raised note mark 7 joins the number as a digit.

Reading these tables needs wide label columns, label-only group rows (and telling them from wrapped
labels), a titled header, dash and marked cells, and the #36 preservation to yield to a read table.
That is a new table reader across `ColumnGrid`, extraction's split, `TableRegionDetector` and the
USGS contract, not a narrow change; a follow-up is proposed below.

## Before and after

`tools/run_corpus_regressions.py --case <id>` (EPUBCheck, probe, `--execution-context host-terminal`),
one case per call for each binary, then `tools/compare_conversion_runs.py --allow-different-converters`.
The contracts below were updated first, so the baseline fails them. Wall times include EPUBCheck and
the content contract; other agents' lanes shared the machine. 73–82 GB free throughout.

| Case | Baseline | Candidate (content checks) | Wall time, base → cand (s) | Changed pages |
| --- | --- | --- | --- | --- |
| census-rrs2002-01 | fails its 4 new checks | pass (86) | 8 → 8 | 12, 15 (tables) |
| faa-phak-8083-25c | fails its 1 new check | pass (579) | 71 → 59 | 410 (table, text) |
| wallace-algebra-2010 | pass | pass (317) | 39 → 38 | none |
| gpo-911-2004 | pass | pass (372) | 19 → 18 | none |
| fed-explained-2021 | pass | pass (227) | 9 → 9 | none |
| dga-2025-2030 | pass | pass (103) | 4 → 4 | none |
| noaa-nca5-2023 | pass | pass (42) | 133 → 170 | none |
| gpo-our-flag-2003 | pass | pass (151) | 5 → 5 | none |
| cdc-zombie-pandemic-2011 | pass | pass (62) | 17 → 17 | none |
| cia-blue-book-14-1955 | pass | pass (10) | 58 → 109 | none |
| usgs-mcs2025-copper | pass | pass (53) | 4 → 4 | none |
| scotus-loper-bright-2024 | pass | pass (116) | 4 → 4 | none |
| nbs-jres-geltman-1977 | pass | pass (66) | 5 → 6 | none |
| arxiv-replay-clocks-2023 | pass | pass (76) | 4 → 4 | none |
| uscourts-pro-se-1-2016 | pass | pass (219) | 2 → 3 | none |
| ntrs-20200002975-gwl-2020 | pass | pass (289) | 3 → 4 | none |
| ntrs-20190030725-dasc-2019 | pass | pass (247) | 3 → 4 | none |
| usda-ars-agresearch-2012-11 | pass | pass (268) | 7 → 10 | none |
| ntrs-20180003024-earthdata-slides-2018 | pass | pass (228) | 3 → 5 | none |
| ntrs-20210020887-techport-thm-2021 | pass | pass (72) | 2 → 4 | none |

No page changed images, OCR, navigation or the conversion report.

**Census review** (candidate EPUB against 150-dpi renders of pages 12 and 15). Each of Tables 2, 3,
7 and 8 opens with `<caption><p><strong>Table N. </strong>…</p></caption>`, the title exactly as
printed (`Table 8. S4 Return Type Information Loss, 8 Variables, 5885 Records`), and the paragraph
that held it before is gone; headers, rows and cells are unchanged. The pages' text is unchanged,
since a caption is read where the paragraph was.

**FAA review** (page 410 against its render). The table's third heading reads `Distance (Miles)`
(`Distance ( M i l e s )` before); every cell and the surrounding prose are unchanged, and
`VOR/VORTAC NAVAIDS` and `Normal Usable Altitudes and Radius Distances` stay paragraphs. No other
FAA page changed.

## Contracts

`corpus/regressions.json`:

- `census-rrs2002-01` pages 12 and 15: each `tableCells` entry gains `caption` (its title), replacing
  the page's `paragraphs` check for the titles, which the caption check implies (a caption paragraph
  is also a page paragraph) and a title set as prose now fails.
- `faa-phak-8083-25c` page 410: `tableCells` names the third column `Distance (Miles)` and adds the
  six distances (`25`, `40`, `40`, `100`, `130`, `100`), read from the render.

The baseline fails exactly the new checks (Census 4: on each page the first table's caption and
the second table's columns; FAA 1: page 410's columns); the candidate passes.

## Tests

- `NativeSpacingTests.letterSpacedTypeThatPDFKitSpellsApartReadsWhole`: FAA's show rebuilt as a PDF
  reads `(Miles)` whole (all spaces, some, inside a longer line); character-spaced capitals keep
  their word space (`MILES AWAY`); controls: kerning, uneven gaps, column gaps, digits alone, two
  glyphs, operators' thin spaces, Wallace's one-letter words, a spaced ellipsis before a one-letter
  word, a run PDFKit's text holds twice or not at all, a run inside two line rectangles; a font-change
  space on the same line is still restored.
- `AlignedColumnTablesTests.aTableTitleInTheCellsSizeIsTheCaptionOnlyUnderItsLabel`: the synthetic
  Census table with a one-line title, `TABLE III`, a wrapped centred title and a title with a
  description; controls: no label, a sentence naming the table, too far above, a larger size, a
  heading tag, a line sharing the baseline, unaligned lines, four lines; the caption is written as
  `<caption>` and reads nowhere else.
- `censusPage12…`, `censusPage15…`: each title is its table's caption and no paragraph.
- `faa410ServiceVolumesReadAsAThreeColumnTable`: the heading `Distance (Miles)`; no caption, the
  lines above stay paragraphs. The `faa-410` fixture was recaptured on this tree; the only change is
  the heading line's text, `( M i l e s )` to `(Miles)`.

Negative mutations (each part disabled by a one-line source edit, then `swift test --filter` over the
spacing and table suites: NativeSpacing, AlignedColumnTables, TableHeadersAndBorderless,
TableCaption, TableLeftovers):

| Part disabled | Failing tests |
| --- | --- |
| letter-spacing from zero | `letterSpacedTypeThatPDFKitSpellsApartReadsWhole` |
| runs need not be whole words | `letterSpacedType…`, `sourceFontBoundariesRestoreReplayClocksWordSpaces`, `wallaceWorkedExamplesSpaceEveryOperatorAsTheSourceSetsIt` |
| operators letter-space | `letterSpacedType…` |
| ellipses letter-spaced (one letter suffices) | `letterSpacedType…` |
| a whole run ends the line's repairs | `letterSpacedType…` |
| ambiguous runs repaired | `letterSpacedType…` |
| runs found by any line | `letterSpacedType…` |
| titles need no label | `aTableTitleInTheCellsSizeIsTheCaptionOnlyUnderItsLabel`, `faa131LoadFactorTableReadsAsATable`, `faa410ServiceVolumesReadAsAThreeColumnTable` |
| a sentence opens a title | `aTableTitle…` |
| titles farther above | `aTableTitle…` |
| titles share their baseline | `aTableTitle…` |
| titles in any size | `aTableTitle…` |
| heading-tagged titles | `aTableTitle…` |
| title lines unaligned | `aTableTitle…` |
| four title lines | `aTableTitle…` |
| no titles | `aTableTitle…`, `censusPage12TablesReadWithTheirHeadersAndRowLabels`, `censusPage15TablesReadIncludingNumbersAWordSpaceApart` |

## Verification

- `swift build -c release`: clean (the candidate binary above). `swift test`: 1004 pass (1002 on `07c1bbd`, and the two new tests).
- `python3 -m unittest discover -s tools -p 'test_*.py'`: 248 pass; `python3 tools/update_doc_counts.py --check`: current.
- Corpus lanes above, all 20 cases; each lane's outputs deleted after review. The final binary,
  whose source differs from the candidate's only in comments (which move line numbers), passes the
  Census (86), FAA (579) and 9/11 (372) lanes again.

## Follow-ups

1. **USGS statistics tables as text**: wide label columns, label-only group rows (told from wrapped
   labels), a titled header over years, `—` and estimate-marked cells (`e740`) in layout's candidate
   stacks, raised note marks kept out of numbers (`7100,000`), and `underlinedColumnRegions` yielding
   to a table read as text (section 5).
2. **FAA page 416's NDB table**: a column whose one letter-spaced cell (`2000 or more`) breaks its
   alignment, a note-marked number PDFKit reports as a 7-point line (`*50`), and a number PDFKit
   splits between two shows 0.134 em apart (`2 5`) (section 3).
3. **Census page 14** (#198 point 4) is unchanged by this work.
