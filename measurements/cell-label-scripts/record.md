# Cell labels read as subscripts (#138)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, Xcode 27, release CLIs.
Work started on `ce2cf5b`; the tree was merged with `e8bc0c3` (#133), `96667ce` (#118), `4fc3115`
(#132/#135), `ec22aff` (#131), `a4b0f30` (#143) and `9ec0608` (#147) before the lanes recorded here, and
both binaries are built from `9ec0608`: the baseline from `git archive 9ec0608`, the candidate from that
archive with this change's `NativeTextReader.swift` hunks alone applied, so #134's change is not in it.
The same lanes on `96667ce`, `4fc3115`, `ec22aff` and `a4b0f30` gave identical changed pages and script
counts for the 13 books they covered:

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline | `git archive 9ec0608` | `bee5365c26775910e80ca36ea65be4b989aaa5898efd1d03eed2e72536228351` |
| candidate | `9ec0608` with #138's `NativeTextReader.swift` hunks | `8a05cf38230810040536d50562dfa35c9e4bea6e69b06812696208ed4c9d22a9` |
| probe | `tools/probe-raster-environment.swift` | `811ff4532a8e17a7baff435d07ac30f92d0fbdf5e3ac768b3ea11f79f67854dd` |

No source PDF or EPUB is committed; each lane's EPUBs were deleted after its comparison and script
review. No fixture was added or recaptured.

## Evidence

Fed pages 82 and 83 (Figure 5.7) set each regulation letter in a 12-point bold face in a narrow
first column, top-aligned with the 8-point regulation name beside it (300-DPI render of page 82). PDFKit
returns the letter and the name as one selection (`F ` 12 pt, then `Limitations on Interbank
Liabilities ` 8 pt) or, for two-letter regulations, the letter as a selection of its own (`KK `), and
reports the letter's Core Text baseline offset as −2.744 points in both cases. `inlineText` read any
run shifted by more than 0.12 of its size (and at most 0.75) as a script, so every letter became
`<sub>`: 13 cells on page 82, 15 on page 83. Page 109's table (Figure 6.11) sets its letters in the
names' own 8-point size at offset zero and was already plain.

The offset is measured from a common baseline of the selection, not from a base the letter hangs
from: nothing else in the selection is at least the letter's size.

## Survey (`script-survey.txt`, `tools/script-survey.swift`)

Every PDFKit line selection of the 13 English sources was read, and each run the rule marked a script
was classed by the largest other visible (non-whitespace) run of its selection:

| Source | larger than every other run | alone in its selection | what they are |
| --- | ---: | ---: | --- |
| Fed | 16 sub | 12 sub | exactly the 28 regulation letters on pages 82/83 |
| FAA | 2 sub | 1 sub, 2 sup | caption `Multi-engine airspeed indicator.` (9 pt beside an 8-pt figure number), `KE = ½ × m × v` beside its 7-pt exponent, wrapped caption lines `housing.`, `portions of propeller blade.`, a chart label |
| Wallace | 1141 sub, 224 sup | 140 sub, 13 sup | exercise numbers `48)` beside 8-pt fraction parts, the 12-pt base of `8x²` (PDFKit centres both offsets: `8x` −2.16, `2` +2.16), fraction numerators and denominators alone in their selections, `÷` |
| CIA Blue Book | 675 sub, 538 sup | 19 sub, 92 sup | OCR text of the scanned typescript (`I` rules, table numbers) |
| Census | 0 | 7 sup | unmapped-encoding glyphs |
| arXiv | 10 sub, 2 sup | 0 | proof symbols beside 7-pt math italic |
| CDC | 1 sup | 1 sub, 1 sup | comic lettering OCR (`DO ME A fAVOr AND`) |
| 9/11, DGA, Our Flag, USGS, Supreme Court, NBS | 0 | 0 | |

The two documents added at `9ec0608` (Pro Se 1 and the NASA GWL report) were not surveyed; their lanes
are below. No run in either class is a script: a superscript or subscript is set no larger than the text it is
raised or lowered from, and it has that text beside it in its selection. The smaller and same-size
scripts (9/11's 1,741 note markers, Supreme Court's 48, FAA's V-speed subscripts, Wallace's 5,011
smaller superscripts) all have such a base.

## Rule

`NativeTextReader.hasScriptBase`: a shifted run is read as a superscript or subscript only when its
selection holds another visible run (not whitespace-only) at least its size divided by 1.1. The
existing offset window, the drop-cap and display-type exclusions and the split-quote re-measurement
(#11) are unchanged; the check only removes script styles, and never changes text, spacing, weight or
slope.

## Content contract (`tools/table_cells.py`)

`tableCells` gains `scriptCells` (boolean): when false no cell of the matched table (header or body)
may contain a `<sup>` or `<sub>` element, when true some cell must. Grids record `scripts`, the number
of written cells holding one. Fed pages 82, 83 and 109 now carry `scriptCells: false` (109 as the
already-plain control). Against the baseline the Fed lane fails exactly the new checks (`script cells:
13 cells hold <sup>/<sub>, expected none` on page 82, 15 on page 83); the candidate passes.

Negative controls (`tools/test_table_cells.py`,
`test_script_cells_reject_sup_or_sub_markup_anywhere_in_the_table`): the #124 output (`<sub>F</sub>` in
the matched row), a script in a row the expectation does not name, one in a data cell, one nested in
emphasis; emphasis alone passes; `true` fails a plain table and passes a scripted one; without the
key markup is not judged; the USGS Salient Statistics table counts its 3 scripted cells; invalid
values are rejected. Run against the `ce2cf5b` checker the new test errors (unknown key) and the
other 18 pass (the USGS review test needs the repository root and was run in place).

## Tests (`Tests/PDFReflowLibTests/ScriptBaseTests.swift`)

| Test | Reproducer / control |
| --- | --- |
| `fedRegulationLettersAreCellTextNotSubscripts` | `fed-83` fixture: all 15 lowered 12-point letter runs read as plain text; through reconstruction the regulation table's markup holds `>Y Bank Holding Companies…` and `>LL ` and no `<sub>`/`<sup>`. |
| `shiftedRunsWithoutABaseOfTheirSizeAreNotScripts` | Synthetic: `F` beside its name, `KK` alone, a raised caption line alone, `8x` (−2.16) beside its exponent `3` (+2.16) gives `8x<sup>3</sup>`, whitespace is no base. |
| `scriptsBesideTheirBaseAreUnchanged` | `H<sub>2</sub>O and x<sup>2</sup>`, same-size raised/lowered runs, a script 1.05× its base stays and 1.15× does not; source controls 9/11 page 20 `7:45.<sup>4</sup>` and page 362's split quote `”<sup>12</sup>`. |

With `hasScriptBase` bypassed, the three tests fail with 23 issues (every Fed letter, the synthetic
negatives, the 1.15× limit). Existing script tests (`BaselineStyleTests`, `NativeLineBoundaryTests`,
`DropCapTests`, `EndnoteMarkerTests`, `NoteContinuationTests`, `PreformattedStyleTests` V-speeds and
exponents, `FootnoteTests`) pass unchanged.

## Corpus lanes

`tools/case.py` (`run_corpus_regressions.py --epubcheck /opt/homebrew/bin/epubcheck
--environment-probe <probe> --execution-context host-terminal`, then `compare_conversion_runs.py
--allow-different-converters`), one case per call; `tools/scriptdiff.py` lists every `<sup>`/`<sub>`
lost or gained per changed page and whether any other markup changed. 5.3–40 GB free (other agents' runs
shared the disk; no lane started under 5 GB). The lanes use the tree's `corpus/regressions.json`, which
also holds #134's new 9/11 checks: both 9/11 binaries fail exactly those (see
[the hanging-entries record](../hanging-entries/record.md)), and their output is identical.

| Case | Baseline | Candidate | Changed pages | Scripts (`scriptdiff-<case>.txt`) |
| --- | --- | --- | ---: | --- |
| fed-explained-2021 | fails the 2 new checks | pass | 82, 83 | 28 `<sub>` letters lost, nothing else |
| wallace-algebra-2010 | pass | pass | 35 | 56 `<sub>`, 6 `<sup>` lost, nothing else |
| faa-phak-8083-25c | pass | pass | 163, 165, 233 | 3 `<sub>`, 1 `<sup>` lost (caption text), nothing else |
| cdc-zombie-pandemic-2011 | pass | pass | 12, 18, 26 | OCR lettering: 2 `<sup>`, 1 `<sub>` lost; page 12's `<sup>...wArn/ngs havb</sup>` keeps only `havb` raised |
| uscourts-pro-se-1-2016 | pass | pass | 3 | 1 `<sub>` lost: the form's `.` after `(foreign nation)`, a 10.98-point period beside 9-point italic, is ordinary text |
| gpo-911-2004 | fails #134's checks | fails #134's checks, identically | 0 | none |
| ntrs-20200002975-gwl-2020, dga-2025-2030, gpo-our-flag-2003, cia-blue-book-14-1955, usgs-mcs2025-copper, scotus-loper-bright-2024, census-rrs2002-01, nbs-jres-geltman-1977, arxiv-replay-clocks-2023 | pass | pass | 0 | none |

No script was gained except CDC page 12's split (`...wArn/ngs <sup>havb</sup>`, where the lettering's
two OCR runs share one raise), and no page changed text, images, navigation or the report. All 62
Wallace losses are listed with their context in `scriptdiff-wallace-algebra-2010.txt`, and pages 23,
95, 177, 178, 192, 255, 270 and 484 were read in both EPUBs; every loss is base text: the base of an exponent (`<sub>8x</sub><sup>2</sup>` →
`8x<sup>2</sup>` on page 23, `<sub>3</sub>2` → `32` on 177 and 192, `<sub>a</sub>2` → `a2` on 178),
exercise numbers (`<sub>21)</sub>`, `<sub>39) 5</sub><sup>−3−x</sup>` → `39) 5<sup>−3−x</sup>` on 484),
comments beside worked steps (`<sup>Exponents first</sup>`, `<sup>FOIL</sup>`, `<sup>Our Solution</sup>`),
ratio labels (`shadow <sub>height</sub>` on 270) and a period (`run<sup>.</sup>` on 95). The survey's
other Wallace, CIA, Census and arXiv candidates changed no output: their lines are not emitted as text
(preserved regions, recognized or damaged-text pages).

## Verification

On the merged tree (`f8a0a7a` with #138 and #134):

- `swift test`: 707 pass (3 in `ScriptBaseTests`).
- `python3 -m unittest discover -s tools -p 'test_*.py'`: 231 pass (1 new).
- `scripts/check-all.sh --fast`: exit 0, including the generated doc counts
  (`tools/update_doc_counts.py`) and byte-identical repeat conversions.
- Corpus lanes above: the Fed lane fails the baseline on exactly the new checks and passes the candidate.

## Not fixed here

- **#144** has a different cause. Supreme Court pages 86–87's bullet is a 7.98-point private-use glyph
  raised 1.02 points beside 10.98-point text: it has a base, and its misread is the unmapped glyph and
  a raise just past the 0.12-em tolerance. Wallace page 255's `6a2b` denominator sits on its own
  baseline (−7.8 points) beside `First identify LCD` (0): `6a` has same-size bases in `b` and the
  comment, so it still reads as a subscript, and its exponent (−4.32) as one too. Reading offsets
  relative to the base run would need the neighbouring comment to be told apart from the formula.
- Wallace exponents PDFKit returns as a separate selection (`32`, `a2` above) stay unraised.
- FAA page 262's `v2` (the `2` at −1.67 beside `KE = ½ × m × v` at −5.00) would still read as a
  subscript; the line is not emitted as text (page 262 is unchanged in the lane).
