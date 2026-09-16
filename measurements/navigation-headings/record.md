# Navigation headings: pull quotes, multi-line titles, contents entries, display numerals (#55)

Tier: deterministic Apple PDF stack, library defaults, macOS 27 arm64 release CLI.
Baseline: branch tip `dd4c326` (after #54, which reflows the Fed's sidebar boxes and shaded
tables), Xcode 27.0, macOS 27.0. `identity.json` records the baseline and changed converter
hashes and the five new fixture checksums. The work was first measured against `417edc7`
(`firstBaselineCommit`); the figures below are from the merged tree against `dd4c326`, and the
`417edc7` figures are given where they differ (the #54 box titles add headings to both sides).

Corpus: *The Fed Explained* (`corpus/cache/the-fed-explained.pdf`, SHA-256 `8db8fd9e…`), pages 5, 8,
14, 24 and 25 captured as pinned fixtures (`fed-5` … `fed-25-layout.json`), with the 9/11 report, the
FAA handbook, Our Flag, Replay Clocks and Wallace's algebra as controls.

## Diagnosis

Captured layouts (`tools/capture-layout-fixture.swift`) and a raw structure-tree probe over the
five pages:

- The book is tagged and every page carries a well-formed tree: page 8 has `H2` for the title
  (its numeral in a `Span` child), `P` for the pull quote and `TOC/TOCI/Reference/Link` for the
  chapter's own contents; page 25 has `H3` for the section title; page 5 is one `TOC`.
  `StructureTreeReader` accepts the `H2`/`H3`/`P` groups, `validates` passes, but
  `MarkedTextReader.apply` returns false on every one of these pages, so every line reaches
  `blocks()` untagged. The cause is the running head: `(vi)Tj EMC /Artifact <<>>BDC ( )Tj` shows
  a second string without a positioning operator, which `show()` treats as unknown cursor
  advancement ("deliberately not a second font decoder") and invalidates the whole page's
  association. The only tag that reaches the EPUB is the cover's H1. The Fed navigation is
  therefore entirely spatial; the tagged path is unchanged here (see gaps).
- Chapter openers (pages 8, 14, 24, 50, 66, 88, 116): PDFKit fuses the 70-point chapter numeral
  with the first title line (`1Overview of the Federal`, runs `1` at 70 pt with baseline offset
  −31.6 and `Overview of the Federal` at 24 pt), and `textLine()` takes the first run's size, so
  the line was a 70-point heading ranked above its own second line (`Reserve System`, 24 pt) and
  above every other title; `inlineText` classified the numeral's offset (within 0.75 × 70) as a
  subscript. The pull quote is 14-point display type over a 10-point body (the chapter's own
  contents list), so each printed line cleared the 12.5-point threshold as its own heading.
- Page 25's 16-point section title wraps onto two lines; each was a heading (the existing
  convention, listed as a gap in the #43 record).
- Page 5's seven chapter entries are 14-point dot-leader lines over the 10-point section
  entries; only the label rule (`sectionLabels`) knew about folio-ending contents lines.

## Changes

`NativeTextReader`:

- `displayNumeralTitleSize`: a first run of one to three digits at least twice the size of the
  title run that follows (consistent within 10%) gives the line the title's size; the rectangle
  and reading order are untouched, so the existing same-row heading join then joins the numeral
  line with `Reserve System` at 24/24 points.
- `inlineText` classifies runs in a second pass: a run at least twice the size of every run
  beside it is display type and never a script (the numeral, a drop cap); a digits-only run set
  on its own baseline (offset differing by more than 0.75 × the title's size) before a letter
  gains a word boundary (`1 Overview`). Real scripts (`H<sub>2</sub>O`, `x<sup>2</sup>`, raised
  note markers) are unchanged; the existing 0.75 × size layout-offset cap still applies.

`LayoutReconstructor`:

- `isContentsEntry`: a line ending in a dot leader of four or more dots, with or without a folio,
  is never a heading candidate (PDFKit split page 5's `vi` folio into its own same-row line, so
  the folio is optional).
- `stacksUnderHeading` / `continuesHeading`: a heading candidate directly beneath the open
  heading's last line at the same size (10%), ordinary heading leading (rectangles touch or
  overlap; baselines at most 2.2 sizes apart), sharing the left edge, centre or right edge, joins
  the heading when the heading so far does not end in `.!?` (a colon does not end it) and the line
  does not open a dotted section number or `Chapter/Part/Section/Appendix/Unit/Lesson N` heading.
  The same-row join keeps its first-line comparison; the stacked join uses the latest line.
- `pullQuoteLines`: a run of two or more stacked heading candidates whose last line ends in
  terminal punctuation and that carries at least eight words is prose. Its lines take the prose
  branch and join into one paragraph.
- A heading candidate is untagged, heading-size or a label, not a contents entry, and not a
  pull-quote line.

## Reproducer and controls

`NavigationHeadingTests.swift` (7 tests): pages 8, 14 and 24 each yield one heading with the
title's size and no subscript and their quote as one paragraph above the chapter contents; page
25 one heading; page 5 `Contents` only with the entries as paragraphs; `isContentsEntry`
positives and negatives and a lone heading-size entry; merge controls (left, centred and
right-aligned pairs, colon-ended first line; `Chapter 1` at another size, `1.1 …` beneath a title,
`Part II` / `Chapter 3`, `Summary.` then `Next Steps`, prose between, a three-size gap, a
different alignment stay separate; 9/11 page 19 merges `“WE HAVE SOME PLANES”` above `1.1 INSIDE
THE FOUR FLIGHTS`); pull-quote controls (a one-line and a two-short-line sentence stay headings, a
two-line title without punctuation merges, a title above a quote keeps its heading); the numeral
(Fed page 8's runs, real scripts, a same-baseline numeral, an under-twice numeral, a lettered
initial). Existing expectations updated for the new convention: `headingTiersRank…` (`Chapter
Title Continued Title` is one heading; levels `[2, 3, 4]`), `sectionLabelsNeed…` (`6
REPRESENTATION OF REPCL AND ITS OVERHEAD`), `ourFlagTwoLineTitleUsesSingleSourceH3` (the spatial
baseline now agrees with the tag: one heading), and `monospacedAndInsufficientGeometryRetainTheirLayout`
(the 44-point Courier initial keeps its size and no reading rectangle but is no longer a `<sub>`).

## Before/after: Fed navigation against the contents page

The contents page lists 7 chapters and 28 sections (3, 4, 4, 4, 3, 6, 4). Counts of `<hN>` in the
spine, which equal the navigation entries (`heading-counts.txt`, `fed-headings-before.txt`,
`fed-headings-after.txt`; identical with `--repeated-headers-and-footers keep` and with defaults):

| | `dd4c326` | this tree (merged) | `417edc7` → first measurement |
| --- | --- | --- | --- |
| Navigation entries | 228 | 161 | 200 → 142 |
| Levels | h1 1, h2 7, h3 1, h4 11, h5 36, h6 172 | h1 1, h2 1, h3 9, h4 28, h5 63, h6 59 | h1 1, h2 7, h3 1, h4 11, h5 36, h6 144 → h1 1, h2 1, h3 9, h4 28, h5 50, h6 53 |
| Entries starting lowercase or mid-phrase | 21 | 0 | 21 → 0 |
| Chapter titles | 7 numeral lines (h2) + 7–14 title fragments + 6 pull quotes of 3–5 lines each | 7, one entry each, `1 Overview of the Federal Reserve System` … `7 Promoting Consumer Protection and Community Development` (h3) | same |
| Contents-page sections | 28 across 13 split pairs and single lines | 28, one entry each (h4), matching the contents page's section titles word for word | same |
| Contents page (5) | `Contents` + 6 dot-leader chapter entries (page 6: 1 more) | `Contents` only | same |

The remaining entries are the cover (h1 tagged; page 3's `The Fed Explained` h2, `What the
Central Bank Does` h3, `PUBLIC EDUCATION & OUTREACH` h5), 103 subsection headings (h5/h6:
`Reserve Bank Leadership`, `Anticipated Factors`, `State Member Banks` …) that the contents page
does not list, and the 19 box titles that #54's reflowed sidebars add (`Box 3.2. The Fed's
Response to the COVID-19 Shock Is Reflected in Its Balance Sheet` …), nine of which were split
over two lines at `dd4c326` and are one heading each here. Chapter titles rank h3 because the
cover title on page 3 is larger (the #43 convention); all seven share one level. Page text
changes on one page only: page 8's `1Overview` becomes `1 Overview`. Image counts are unchanged
on every page (`page-comparison/`); heading sets change on 32 pages (23 before #54's boxes),
every one a chapter opener, a two-line section or box title, or the contents page.

## Control books (`page-comparison/`, `dd4c326` defaults → this tree's lane output; identical to the `417edc7` comparison)

Text edits are zero and image counts unchanged in every control book. Heading counts: Replay 24 →
24 and Our Flag 54 → 54 (identical page for page); 9/11 161 → 139 (17 pages), FAA 187 → 176 (11
pages), Wallace 226 → 217 (2 pages), all reviewed:

- 9/11: the cover (`THE 9/11 COMMISSION REPORT`; `Final Report of the National Commission on
  Terrorist Attacks Upon the United States`), `LIST OF ILLUSTRATIONS AND TABLES`, `COMMISSION
  MEMBERS`, `COMMISSION STAFF`, every two-line chapter title (`“WE HAVE SOME PLANES”`, `THE
  FOUNDATION OF THE NEW TERRORISM` … `HEROISM AND HORROR`), the two-line sections `12.3`, `12.4`,
  `13.1` and `HOW TO DO IT? …`, and page 357's chapter numeral `11` joining `FORESIGHT—AND
  HINDSIGHT` as the contents page prints it. Residue: page 13's three staff lines (`Philip
  Zelikow, Executive Director` …), already headings at the baseline, are now one heading.
- FAA: every two-line chapter title (`Aeronautical Decision-Making`, `Aircraft Construction`,
  `Aeromedical Factors` …) and section title (`History of the Federal Aviation Administration
  (FAA)`, `Air Carrier Obstacle Clearance Requirements` …); page 16 `Introduction To Flying` was
  previously split after `Introduction`; page 203's pre-existing fused `FlightChapter 8` now joins
  `Instruments`.
- Wallace: the answer-key fragments that were already headings on pages 210 and 468 (`2)`, `4)`,
  `11) 12a4b5` …) merge into fewer headings of the same wrong kind (the pre-existing gap of the
  #43 record); no new heading and no lost section title.

## Verification

- `swift test`: 288 tests pass (281 at `dd4c326` plus 7 new; 274 on the `417edc7` tree);
  `python3 -m unittest discover -s tools -p 'test_*.py'`: 160 OK.
- `scripts/check-all.sh --fast`: exit 0 (288 Swift, 160 Python, 6 fixture conversions, 13 policy
  conversions with 22 rejection/cleanup cases).
- `tools/run_corpus_regressions.py --converter .build/release/pdf-reflow --epubcheck
  /opt/homebrew/bin/epubcheck --output <new dir> --case …` (`lane-summaries/`): Fed 92 (81 at
  `dd4c326` plus 11 new checks on pages 5, 8 and 25), Replay 55, Our Flag 59, 9/11 71, Wallace 63
  and FAA 61 content checks pass with EPUBCheck, progress and memory gates. Negative control
  (`fed-explained-2021-negative-control-dd4c326.json`): the same contract against the `dd4c326`
  CLI fails on six of the new lines (page 5's two chapter entries as paragraphs, page 8's
  `1Overview` absent, its merged heading and its quote paragraph, page 25's merged heading); the
  other five (the `Contents` heading, page 8's chapter-contents paragraph, page 25's opening
  paragraph and figure) hold at the baseline and pin the surroundings. The same six lines failed
  against `417edc7` in the first measurement.
- EPUBCheck on the `--repeated-headers-and-footers keep` Fed EPUB: 0 errors (the one warning is the
  test run's non-UUID `--package-identifier`, present at the baseline too).

## Remaining gaps

- The Fed's tags never reach reconstruction: `MarkedTextReader` invalidates a page at the first
  text show without a positioning operator, and every Fed running head has one inside an
  `Artifact` sequence. Recording an unknown origin for such a show (rejecting only the group it
  belongs to, and nothing for an artifact) would let the validated `H2`/`H3`/`P` roles settle the
  title and quote directly; it changes the whole book's reconstruction and is not attempted here.
- Stacked same-size lines that are distinct headings without a number, chapter label or
  terminal punctuation merge (9/11 page 13's staff list, which should not be headings at all).
- A one-line pull quote at heading size, or a quote whose run ends without punctuation, stays a
  heading; a pull quote is emitted as an ordinary paragraph, not a styled block.
- Chapter titles rank h3 beneath the cover title's tier, as before (#43).
