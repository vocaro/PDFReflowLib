# Body-size section titles and spaceless hanging entries (#162)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, Xcode 27, release CLIs.
Baseline `2e18b31` (the coordination branch's head, which already carries #146/#154's number-led
paragraph work and #134's hanging entries), candidate this tree on it.

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline | `2e18b31` | `d254f1c3a95988dad3b663281d6592024edf5d1d4cf387b236a6459490557c04` |
| candidate | this tree on `2e18b31` | `b7555c392409656c9e14263a8b4cfd476cda7431ccd0c2a413a007ba16c5afec` |
| probe | `tools/probe-raster-environment.swift` | `cbf9fabb801c2acd89433d713236eacac103824f3749e254b0b1ef15c4bc72e3` |

No source PDF or EPUB is committed; each lane's EPUBs were deleted after its page diff. Six source
fixtures were captured with `tools/capture-layout-fixture.swift` (`dasc-1`, `dasc-2`, `dasc-5`,
`dasc-7`, `dasc-9`, `dasc-10`); no fixture was recaptured.

## What #146/#154 had already fixed

On the baseline the IEEEtran paper (`ntrs-20190030725-dasc-2019`) still shows every defect #162
reports, with two exceptions, both from #146/#154 (`0a3eec7`):

- the numbered requirements `1)`–`4)` on page 7 are whole `<pre>` items, marker line and wrapped
  lines together, instead of holding only their first line;
- reference [7]'s author line `S. M. Jurcak, S. K. Iyer, and P. Verma…` is a paragraph rather than a
  `<pre>` list item under its `S.` marker (the lonely-marker rule).

`isNumberedTitle`, #154's one admitted marked line, reaches neither level of this paper: it asks for
a one- or two-digit number, and the sections are numbered `I.`–`VIII.` while the subsections are
lettered `A.`–`C.`. Nothing else changed.

## Evidence

Geometry from the captured fixtures, read against 60 DPI Poppler renders of all ten pages.

**Section titles.** `I. INTRODUCTION` stands at x 135.62–213.37 in a left column whose justified
measure is 48.96–300.02: its centre, 174.50, is the measure's centre to a fiftieth of a point, and it
is 9.96 points — the page's body size. Every section title is set the same way (`II. PROBLEM INPUT
AND OUTPUT` at 102.74–246.25, `REFERENCES` at 409.61–465.41 over a 7.97-point bibliography). PDFKit
reports one size a line, taken from its first run, so the small capitals show only in the runs: `I. I`
at 9.96 then `NTRODUCTION` at 7.97; `A`, `PPENDIX `, `A`; `R`, `EFERENCES`. A title's second line
carries no full-size initial at all (`MANAGING ARRIVAL AIR TRAFFIC`, `ALGORITHM`, both 7.97), so
PDFKit measures it a fifth smaller than the line above it and `stacksUnderHeading` reads the pair as
two sizes.

Three gaps kept these lines out of `sectionLabels`:

1. they are at the body size, under the 1.15-body label threshold and the 1.25-body heading one;
2. they carry neither bold nor italic, so the `subheading` branch refuses them whatever style the
   book repeats — and `LabelStyle` cannot tell them from body prose, both being `10/10` upright;
3. `I.` and `V.` are one-letter list markers, so those two also became `<pre>` items, while `IV. THE
   INTERDEPENDENCE OF THE CONSTRAINTS` at the head of a column simply attached to the paragraph
   beneath it (its edge is 6.88 points from the column's, inside the 1.5-body column test).

**Subsection titles.** `A. Input data` is 9.96-point italic on the column's own edge (48.96), 55.79
points wide, 12.51 points clear of the line above and 10.05 clear of the paragraph beneath, which
opens on the column's one-em first-line indent (58.93). The lettered marker is a list marker, so the
line became a `<pre>` item and `continuesListItem` then pulled the paragraph's first line into it
(`<pre><em>A. The algorithm invariants</em> Assume the first (f−1) flights have been scheduled;
i.e.,</pre>`). `isTitleCase` is no help here: IEEEtran sets these titles in sentence case
(`B. The generic step: scheduling the next flight`).

**Hanging entries.** The bibliography sets each entry's first line at 315.96 and its wrapped lines at
330.24 — 14.28 points, 1.79 ems of the 7.97-point type — with no space between entries (the leading
inside an entry, 1.84 points, equals the leading between them, 1.83). The algorithm steps hang 33.65
points, 3.38 ems, under `Step 10.`'s text. Both fail every existing join:

- the spatial rule attaches a line only on a left edge within 1.5 bodies, and the page body is 9;
- #147's hanging branch asks for space above the entry's first line exceeding the leading beneath it
  by 0.4 body, and there is none; its indent is also capped at three bodies, under the steps' 3.38;
- #134's `hangingEntryEdges` disqualifies an edge that shows any *opening* — an indented line under a
  line that ends a sentence — and a reference's first line routinely ends in a full stop or semicolon
  (`[4] L. Meyn. A closed-form solution to multi-point scheduling problems.`, `[6] … Combinatorial
  Optimization;`), so the whole edge is refused.

What a first-line indent cannot produce is a **run**: two lines in a row at the indent. Entry [5]
sets four, entry [7] three, step 5 four; a first-line-indented paragraph returns to the edge beneath
its opening line every time.

## Rules

`LayoutReconstructor.academicSectionTitles(in:body:page:)` returns the page's academic titles, which
`blocks` adds to `labels` beside `sectionLabels` and `boxTitles`. `columnMeasure(of:)` gives the
column's dominant size and the left and right edges at least three of its lines in that size share;
`isCentred(_:in:)` asks for insets from both edges that agree within three quarters of that size,
each at least 0.4 of it, so a justified line (both insets zero), a first-line indent and a ragged last
line all fail.

A **section title** is a line at 0.9–1.25 of the page body, wholly in capitals, not bold, centred in
the measure, set off above by half a body or standing under another such title, and over text no
larger than the body on the measure's own edge or up to 1.5 sizes inside it. The line beneath is
sought past any further centred capital lines of the title itself, so a title over a table's own
centred subtitle is refused (FAA page 416). It must take its place in the paper's section sequence:
`opensWithRomanNumeral` (a Roman numeral and a period, which also admits the one-letter markers `I.`
and `V.`) or `isUnnumberedSectionHead` (`APPENDIX`, `APPENDICES`, `REFERENCES`, `BIBLIOGRAPHY`,
`NOMENCLATURE`, `ACKNOWLEDG(E)MENT(S)`). `continuesCentredTitle` stacks a following line on the
title's centre at 0.65–0.95 of its size — the small capitals alone — and `blocks` joins such a line
to the open heading beside `continuesHeading` and `continuesHangingTitle`; a same-size line stacked
on the centre continues the title in `academicSectionTitles` itself.

A **subsection title** is a single capital letter and period before a capital, at the body size,
wholly italic, on the measure's left edge, an em clear of its right, half a body to two bodies clear
above and below, with the section's paragraph beneath it: body-size, neither italic nor bold, no list
line, at least eight sizes wide, on the measure's edge or its first-line indent.

`hangingRun(in:edge:indent:size:)` reads a spaceless hanging list: at least two lines at `indent`
whose nearest line above stands on `edge`, at least one whose nearest line above is itself at
`indent`, and an indented line reaching the edge lines' own right margin. In `blocks`,
`continuesOpening`'s hanging branch takes that as its evidence in place of the space above, allows
the indent to reach four bodies, and accepts an opening line of three real words rather than
`isWordy` (a reference opens on initials).

## Contracts (`corpus/regressions.json`)

| Case | Added |
| --- | --- |
| ntrs-20190030725-dasc-2019 | headings `I.`–`VIII.`, `APPENDIX A …`, `APPENDIX B …`, `REFERENCES` and the six italic subsection titles on pages 1, 2, 3, 5, 6, 7, 9 and 10; paragraphs for the two subsection openings, steps 4 and 8, the page-3 constraint item `(c)`, section IV's opening and references [3], [4] and [7]; controls: the page-1 `Index Terms` line and the page-10 table caption are not headings |
| ntrs-20200002975-gwl-2020 | page 19's reference [14] whole |
| arxiv-replay-clocks-2023 | page 10's reference [11] whole |
| census-rrs2002-01 | page 17's reference [11] whole |
| nbs-jres-geltman-1977 | page 7's reference [9] whole |
| gpo-911-2004 | page 50's timeline entry `9:24 NEADS scrambles Langley fighter jets in search of AA 11` whole |
| gpo-our-flag-2003 | control: `BENNINGTON FLAG` (page 15) is not a heading |
| scotus-loper-bright-2024 | controls: `RELENTLESS, INC., ET AL., PETITIONERS` (page 9) and `III` (page 26) are not headings |

34 positive checks (19 headings and 15 paragraphs) and 5 absent-heading controls. The baseline fails
33 of the positives — 28 on the IEEEtran paper and one on each of the other five books — and passes
the five controls; the candidate passes every case. The 34th, section IV's opening paragraph on page
3, also passes on the baseline, because the phrase sits inside the paragraph the section title ran
into and a paragraph check is a containment check; the missing heading beside it is what fails.

## Tests (`Tests/PDFReflowLibTests/AcademicSectionTitleTests.swift`)

| Test | Reproducer / control |
| --- | --- |
| `sourceNumberedSectionTitlesAreHeadingsAtTheBodySize` | `dasc-1`, `dasc-2`, `dasc-5`: `I.`, `II.`, `III.` and `V.` are headings, in no `<pre>` and in no paragraph. |
| `sourceTitlesSetOverTwoOrThreeLinesAreOneHeading` | `dasc-7`, `dasc-9`: the small-capital second line, the same-size appendix titles and the third line `ALGORITHM` join one heading each. |
| `sourceUnnumberedReferencesHeadIsAHeadingOverSmallerEntries` | `dasc-10`: `REFERENCES` over a 7.97-point bibliography is a heading; the `TABLE III` caption is not. |
| `sourceItalicSubsectionTitlesStandApartFromTheirParagraph` | `dasc-2`, `dasc-5`: four italic titles are headings and their first paragraphs are whole. |
| `sourceHangingEntriesKeepTheirWrappedLines` | `dasc-10`, `dasc-5`: references [3], [4] and [7] and step 4 are one paragraph each. |
| `centredTitlesNeedTheirPlaceInTheSectionSequence` | Synthetic: a numeral, an appendix and `REFERENCES` qualify; a caption line, a bare numeral, a bold label, a line filling the measure and a lower-case title do not. |
| `aCentredTitleOverCentredTextIsATableTitleNotASection` | Synthetic (FAA page 416's shape): a centred title over centred text is refused, over column text admitted. |
| `italicSubsectionTitlesNeedTheirMarkerStyleAndSpacing` | Synthetic: roman and bold type, a missing marker, the column's leading and italic text beneath each refuse. |
| `hangingRunsNeedTwoOpeningsAndAWrappedRun` | Synthetic: two openings with a wrapped run qualify; one opening, three single-wrap entries and a first-line indent do not. |

Negative mutations (`tools/mutate.py`, `negative-mutations.txt`), run over the academic-title,
hanging-entry, number-led, heading, tagged-title, list-continuation, citation-continuation,
page-continuation, FAA-heading and box-title suites. All twelve are caught.

## Corpus lanes

`tools/run_corpus_regressions.py`, one case per call, with the compiled raster/Vision probe and
`--execution-context host-terminal`, then `tools/compare_conversion_runs.py
--allow-different-converters` (`lane-summaries/<case>.json`). Page markup for every changed page is
in `pagediff-<case>.txt`. 34–42 GB free throughout.

| Case | Baseline | Candidate | Changed pages |
| --- | --- | --- | --- |
| ntrs-20190030725-dasc-2019 | fails the 28 new checks | pass | 8: 1, 2, 3, 5, 6, 7, 9, 10 |
| ntrs-20200002975-gwl-2020 | fails the new check | pass | 1: 19 |
| arxiv-replay-clocks-2023 | fails the new check | pass | 1: 10 |
| census-rrs2002-01 | fails the new check | pass | 1: 17 |
| nbs-jres-geltman-1977 | fails the new check | pass | 1: 7 |
| gpo-911-2004 | fails the new check | pass | 1: 50 |
| faa-phak-8083-25c, wallace-algebra-2010, fed-explained-2021, dga-2025-2030, gpo-our-flag-2003, cdc-zombie-pandemic-2011, cia-blue-book-14-1955, usgs-mcs2025-copper, scotus-loper-bright-2024, uscourts-pro-se-1-2016, usda-ars-agresearch-2012-11, ntrs-20180003024-earthdata-slides-2018, ntrs-20210020887-techport-thm-2021, uscis-m618-arabic-2015, irs-p596-zhs-2025 | pass | pass | none |

No image or report field changed on any case but the IEEEtran paper, which gains one
`uncertainHyphen` on page 10: reference [2]'s `system specifi-` + `cation document (SSD)` now meets
its wrapped line, and the paper prints `specification` nowhere else, so the hyphen policy keeps the
hyphen and warns, as it does for every join it cannot decide. Navigation changed only on that paper,
which gains its 19 section and subsection titles.

Every changed page was read against the source renders:

| Case | Page | Change |
| --- | --- | --- |
| ntrs-20190030725-dasc-2019 | 1, 2, 3, 5, 6, 7, 9, 10 | 19 titles become `<h3>` (58 blocks removed, 39 added); the four subsection openings, section IV's paragraph, the page-3 constraint items `(b)` and `(c)`, steps 4–10 and references [2]–[6] and [8]–[10] are whole. |
| ntrs-20200002975-gwl-2020 | 19 | References [13] and [14] keep their wrapped author lines. |
| arxiv-replay-clocks-2023 | 10 | Reference [11] keeps its wrapped line. |
| census-rrs2002-01 | 17 | References [9], [10], [11] and [14] keep their wrapped lines. |
| nbs-jres-geltman-1977 | 7 | Six OCR'd references ([6], [8], [9], [16], [25], [26], [33]) keep their wrapped lines; no text changed. |
| gpo-911-2004 | 50 | The two timeline entries whose text wraps into the box's four-em hanging indent (`9:21 Boston Center advises NEADS that AA 11 is airborne heading for Washington`, `9:24 NEADS scrambles Langley fighter jets in search of AA 11`) are one paragraph each. |

Warren and NOAA are outside the lane (#5), so both were converted directly with
`--maximum-output-bytes unlimited --no-ocr` and their blocks diffed: no page of either changed.

Two over-reaches were found in these lanes and closed, each now a contract control:

- Our Flag page 15 sets six all-capital flag labels over their paragraphs; `BENNINGTON FLAG` happens
  to fall symmetrically inside the measure and became an `<h6>` while its five siblings stayed
  paragraphs. Small capitals are set in the text face, so the rule now refuses a bold line, which is
  `sectionLabels`' recurring-style evidence anyway (#76).
- Loper Bright gained seven headings: four case-caption lines (`RELENTLESS, INC., ET AL.,
  PETITIONERS`) and three bare part numerals `III` — the numerals `I` and `II` have fewer than three
  letters, so even that was inconsistent. Requiring a place in the section sequence closes both.

## Verification

- `swift test`: 780 pass (9 in `AcademicSectionTitleTests`).
- `python3 -m unittest discover -s tools -p 'test_*.py'`: 233 pass.
- `scripts/check-all.sh --fast`: exit 0, including the generated doc counts and byte-identical repeat
  conversions.
- `tools/check_reproducibility.py` on the IEEEtran paper, Census and NBS: identical bytes.
- Corpus lanes above, and `tools/check_corpus_content.py` on each candidate evaluation.

## Remaining defects

1. **`A. ETAs, schedule-frozen nodes, no-passing edges` (page 2) is still a `<pre>` item that
   swallows its first paragraph line.** The line's single run carries no italic flag, although the
   page's other three subsection titles do, so #133's font-style evidence is missing for it alone;
   without the style there is nothing to tell the line from a lettered list item. This is a font-style
   gap, not a heading one.
2. **The itemize bullets on pages 5 and 6 still hold only their first line.** `TextLine.fontSize` is
   the size of the line's *first* run, and TeX draws `\labelitemi` from a 7-point font over 9.96-point
   text, so `• Controllability: …` reports 6.97 points and `continuesListItem` refuses a 9.96-point
   wrapped line (`line.fontSize <= item.marker.fontSize + 0.5`). The fix belongs in extraction, beside
   `dropCapBodySize` and `displayNumeralTitleSize`, and would change every book whose bullet glyph is
   drawn smaller than its item.
3. **References [1] and [7] keep a detached piece.** PDFKit splits those rows at `CVXOPT: A` (x 518)
   and `NASA` (x 544), and a row piece is not a wrapped line; [1]'s first line therefore does not fill
   the measure and its wrapped line cannot join it.
4. **Section and subsection titles rank at the same level.** Both are 9.96 points, so
   `rankHeadingLevels` puts them in one tier under the 23.91-point paper title: every section and
   subsection is `<h3>`. The document-wide ranking has no evidence but size.
5. **Paragraph boundaries are unchanged** (#162 item 5): page 1's introduction still splits at the
   column break, because the author block above the right column's head line blocks the column join;
   paragraphs indented one em still merge, because the spatial rule attaches any line on a left edge
   within 1.5 bodies; and section III's paragraph still does not join page 3 across footnote 1.
6. **`APPENDIX A` and its title read as one heading** (`APPENDIX A A HIGH-LEVEL DESCRIPTION OF THE
   SCHEDULING ALGORITHM`), as a numbered chapter opener's number and title do. The model has no way
   to express a heading's own number separately.
