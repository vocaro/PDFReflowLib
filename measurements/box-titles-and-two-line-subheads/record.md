# Sidebar box titles and two-line sub-headings (#100, #102)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, release CLIs. Work began on
`ffc45a4` and was carried onto each tip as it landed (`9884ed6`, `bc5eb8c`, `36c6265`, `d333b4d`) by
re-applying the same patch; every figure below compares an unmodified `git archive d333b4d` release
build (converter `8277e555…`) with this tree (`0435ffa3…`), except where a figure says otherwise.
Pinned conversions use `--package-identifier urn:uuid:00000000-0000-4000-8000-000000000001
--modification-date 2026-01-01T00:00:00Z`; EPUBs were deleted after dumping
(`measurements/heading-placement/block-dump.py`). No PDF or EPUB is committed.

## #100: sidebar titles

### Diagnosis

Page 27 was captured with `tools/capture-layout-fixture.swift` and read against a `mutool draw` render.
The sidebar is one stroked `re` frame (a #54 tint) of nine untagged lines; the page's body text around
it is tagged. `mutool trace` shows the title in `FranklinGothicLTPro-Dm` (demibold) at 8 points over
`FranklinGothicLTPro-Bk` at 8 points, but PDFKit's attributed runs name every font on the page
`Helvetica`, so no run is bold. The title is:

- below the heading threshold (8 points on a 10-point page body) and below the label band, which
  starts at 0.95 × body;
- not bold, so no label style applies;
- one line, 166.6 points wide in a 211-point box, with no tag.

Only the spacing sets it apart: 15.6-point pitch to the box's first text line against a 12-point
pitch between text lines. A two-line title (page 72, `Finding data on institutions supervised by
the` / `Federal Reserve`) sets its own lines at a 10-point pitch.

The issue's premise was narrower than the defect. The `Box N.N.` titles that were headings are
14-point lines over 9-point box text, headings by size. A survey of every frame on all 135 pages
(`survey/fed-framed-boxes.txt`, `tools/boxes.py`) found 39 narrow sidebars on 34 pages whose 8-point
title ran into the first paragraph, or on page 95 stood as a paragraph of its own. Page 27 was one of them.

### Rule

`LayoutReconstructor.boxTitles(in:page:)` adds each title to the page's labels:

- **Stack.** For each tint cluster, take the box's lines top to bottom, one line per row. The top one or two
  lines are the title. The next line and the one after it continue at the title's size, and the
  next line is on the title's left edge.
- **Space.** The gap beneath the title is at least that text's own leading plus 0.25 em, and at
  most 2.5 em. A two-line title's lines are no further apart than that leading plus 0.1 em.
- **Reads as a title.** A capital, digit or opening quote first. No closing `.`, `,`, `;` or `:`
  before a raised note marker; a question mark is allowed. No list marker or leader. No line wider
  than the box's text measure.
- **Pages.** Recognized and synthetic-style pages are skipped.

The existing heading flow then emits the lines as a heading, and #55's `continuesHeading` joins a
two-line title. Headings keep their typographic size, so the titles rank h6. The `Box N.N.` titles
are h5 because they are 14-point.

Two corrections came from measurement:

1. The first draft compared the title's width with the line directly beneath it. That missed page
   19 (`Want to learn more about Reserve Bank directors?`, 182.6 points over a 175.4-point ragged
   line) and page 26's `FOMC composition helps ensure broad perspective`. The rule now uses the
   box's widest text line.
2. The first draft read the box's column on the title's edge only. On 9/11 page 348 it skipped a
   paragraph set on a first-line indent and measured a false gap, which made `FBI was aware of
   the flights … depart.30` a heading. The rule now takes the box's lines as they stand and reads
   the ending past a raised marker. The 9/11 output is again byte-identical to baseline.

### Before and after (Fed)

Navigation 164 → 203 (`block-diffs/fed-navigation.txt`): 39 added, none removed, no level change
(on `ffc45a4` and `36c6265` too). Text is identical apart from whitespace. Each change splits a fused
paragraph into heading and paragraph, except page 95, where a paragraph is retagged. The added
headings, all h6:

19 `Want to learn more about Reserve Bank directors?`; 20 `Want to learn more about the FOMC?`; 22
`More on Federal Reserve Advisory Councils`; 26 `FOMC composition helps ensure broad perspective`,
`Fed Chair on accountability and transparency`; 27 `A fresh look at the monetary policy framework`;
28 `Monetary policy: Easing and tightening defined`; 33 `Learn more about the context for monetary
policy decisions`; 34 `The Fed’s commitment to its goals`; 35 `Regular congressional testimony and
reporting promote accountability and transparency`; 36 `Unprecedented actions to foster maximum
employment and stable prices`, `Clear usage of forward guidance`; 37 `Large-Scale Asset Purchase
(LSAP) programs supported credit for households and businesses`; 41 `Interest on reserve balances`;
42 `Learn more about the Fed’s toolkit`; 46 `Learn more about how the Fed uses “ample reserves”`; 54
`Assessing resilience of the U.S. financial system`; 56 `Monitoring leverage in the nonbank sector`;
57 `Microprudential supervision and regulation`; 60 `Countercyclical Capital Buffer`, `“Stress
testing” of large financial institutions`; 61 `Financial stability policy and research`; 63 `Regular
reporting on FSOC activities`, `Central banks around the world`; 71 `Bank charters affect which agency
supervises`; 72 `Finding data on institutions supervised by the Federal Reserve`; 73 `What does
“systemically important” mean?`; 74 `Who conducts examinations and inspections?`; 78 `How the Federal
Reserve enforces consumer- and community-oriented laws and regulations`; 79 `Financial Sector
Monitoring`; 80 `Finding orders and agreements online`; 84 `How do capital and liquidity differ?`; 85
`Financial disclosures by state member banks`; 92 `Federal Reserve Bank service fees`; 94 `What is the
automated clearinghouse (ACH)?`, `What are “clearing” and “settlement”?`; 95 `What is check
truncation?`; 122 `Consumer Affairs (CA) letters`; 125 `CRA history, public input, and resources`.

Review: each added heading was checked against the frame survey, which records the title's
typography and pitch. Renders of pages 27, 54 and 95 were read. Each heading is the demibold first
line of a framed sidebar, and the paragraph after it is that box's text. No frame's text is left
fused (`survey/fed-framed-boxes.txt`). The remaining non-heading frames are figure title bands,
shaded tables and page 54's chart boxes.

## #102: two-line sub-headings and plain mnemonic contents entries

### Survey

`tools/survey.py` looked for two consecutive lines, each wholly bold or wholly italic in one style
at 0.95–1.25 × body, stacked within 0.8 em on one edge, directly above a plain body-size line. It ran
over captures of every page of FAA (521 of 524 pages; pages 4, 522 and 524 abort in the capture
tool, the #99 class), 9/11 (585) and Wallace (489). Fed has no style names.

- **FAA** (`survey/faa-two-line-runs.txt`): 57 runs.
  - Already one heading: 12-point titles and tagged two-line sub-headings (#55, #73, #90), for
    example `Hazardous Inflight Weather Advisory Service (HIWAS)`.
  - Contents and index entries with leaders (pages 6–14, 514–520): not titles.
  - Page 348: `Holding Position Markings for Taxiway/Taxiway` / `Intersections` and `Marking and
    Lighting of Permanently Closed` / `Runways and Taxiways` lie inside a whole-page preserved region
    (853 paints) and never reach heading detection. See defects.
  - **Two instances, both untagged and bold:**
    - Page 21, `The Professional Air Traffic Controllers` / `Organization (PATCO) Strike` (10-point
      Helvetica-Bold). The paragraph beneath is tagged, so the pair was already a paragraph of its own.
    - Page 404, `Use of Chart Supplement U.S. (formerly Airport/` / `Facility Directory)`, which ran
      into `Study available information…`.
  - No untagged two-line italic title exists.
- **9/11 and Wallace**: PDFKit names every font `Helvetica`, so neither book has a bold or italic
  sub-heading style to survey (0 runs).

Why neither line was a label: the first line's line beneath is bold, which #76 refuses, and the
second line has no clear space above it.

### Rule (`sectionLabels`)

When a body-size line in a recurring bold or italic style fails the single-line test, it is a label
together with the line beneath it when:

- the second line is in the same `LabelStyle` and size, on the first line's edge, and no wider than
  90% of the column's prose;
- `stacksUnderHeading` holds, the second line opens no numbered heading, and it is no list or
  contents line;
- neither line ends in `.,;:`, and an italic pair is in title case and no caption;
- the paragraph opens beneath the second line by #76/#97's test;
- the first line has clear space above it (the existing test). It may run the full column measure,
  as a wrapping title does.

Only a style the book already repeats counts. The pair is recorded as no style evidence of its own,
so `labelEvidence` is unchanged. `continuesHeading` (#55) joins the two lines into one heading.

### Plain-type `X = Word`

The corpus has an instance, but in contents entries. FAA page 6 lists `A = Aircraft ……2-8`,
`V = EnVironment ……2-9` and `E = External Pressures ……2-9` in plain Times-Roman. These lines seeded
a formula crop that took the column's last four entries, through `Human Factors ……2-10`, out of the
text (render-checked). Page 14 lost `Time T = D/GS`, `Distance D = GS X T` and `GS GS = D/T` the
same way, and Wallace's contents pages 5 and 211 lost `6.3 Trinomials where a =1 ……221`.

A leader line is a contents entry and never a displayed equation, so `graphicsWithLabels` no longer
seeds a formula crop from a line `isContentsEntry` accepts. A plain-type `X = Word` title outside a
contents page has no corpus instance and is left as filed.

### Before and after

**FAA** navigation 906 → 908 (`block-diffs/faa-navigation.txt`), 2 added, none removed, both h6:

| Page | Added heading | Review |
| --- | --- | --- |
| 21 | `The Professional Air Traffic Controllers Organization (PATCO) Strike` | Capture typography: two 10-point Helvetica-Bold lines over the paragraph, which previously stood as a paragraph. |
| 404 | `Use of Chart Supplement U.S. (formerly Airport/Facility Directory)` | Render and capture: bold two-line title, now split from `Study available information…`. |

Crops and text (`block-diffs/faa.diff`):

- Page 6 regains its four contents entries.
- Page 14 regains five: `Converting Minutes to Equivalent Hours`, the three formula entries and
  `Converting Knots to Miles Per Hour`. Render-checked.
- `imageCount` drops by 2.
- Page 6's folio `vii` (a tagged `P`) now reads in tag order, after `Table of Contents……vii`. The
  crop had forced spatial order; page 7 already reads `viii` first.

**Wallace** (`block-diffs/wallace.diff`): pages 5 and 211 regain `6.3 Trinomials where a =1……221`
(render-checked); `imageCount` drops by 2; navigation is unchanged.

**9/11 and Our Flag**: byte-identical EPUBs.

## Lane (`d333b4d` vs candidate, `tools/compare_conversion_runs.py --allow-different-converters`)

One case per invocation, sharing one compiled raster probe (`lane-summaries/`):

| Case | Checks | Baseline | Candidate | Changes |
| --- | ---: | --- | --- | --- |
| fed-explained-2021 | 160 | 8 fail (all new) | pass | 34 pages (the added headings); navigation on those pages; no image, report field or page-marker change |
| faa-phak-8083-25c | 349 | 6 fail (all new) | pass | pages 6, 14, 21, 404; navigation on 21 and 404; 2 images; `imageCount`, `warnings`; markers equal |
| gpo-911-2004 | 193 | pass | pass | none |
| wallace-algebra-2010 | 138 | 2 fail (new) | pass | pages 5 and 211; 2 images; `imageCount`, `warnings`; navigation unchanged |
| gpo-our-flag-2003 | 70 | pass | pass | none |

No OCR page changed in any case. Every run passed EPUBCheck and the lane's structural, progress and
memory gates; no memory-gate failure occurred. The Wallace comparison ran before its two checks were
added, and the check rerun gave the same pass/fail split.

## Tests and contracts

**Fixtures**, captured with the capture tool built at `bc5eb8c` (MarkedTextReader as of #91): `fed-27-tagged`, `fed-63-tagged`,
`911-348`, `faa-21-tagged`, `faa-404-tagged`. The tests also use the existing `fed-22`, `fed-32`,
`fed-36`, `fed-37` and `faa-6-tagged`.

**`BoxTitlesAndTwoLineSubheadsTests.swift`** (7 tests):

- Page 27's title is a heading over `In 2019…`. Neither the size rule nor the label rule sees it,
  and without a tint there is no box title.
- One- and two-line titles on pages 22, 36, 37 and 63.
- Box title controls:
  - page 63's paragraph break inside its box;
  - 9/11 page 348's marker-ended paragraph over an indented one;
  - Box 3.1's 14-point title;
  - a line set at the box's leading;
  - sentence punctuation, lowercase and a list marker;
  - an indented or larger line beneath;
  - a ragged line beneath (still a title) and a title wider than the measure;
  - a two-line title spread past the leading;
  - recognized and synthetic pages.
- The FAA pairs on 21 and 404 with the book's styles, and their previous reading without them. The
  pair is not recorded as evidence.
- Pair controls:
  - a style the book does not repeat;
  - sentence end, plain second line, another style, indent, another size, list marker;
  - bold line beneath, paragraph off the edge;
  - lines apart, and no clear space above.
- Italic pairs: title case accepted; lowercase, caption and italic body refused.
- FAA page 6's contents entries stay text, and a displayed `A = πr²` keeps its crop.

**Existing test updated.** `HeadingTests.fedTableTypographyDoesNotPromoteSurroundingProse` expected
no heading on Fed page 46. The page's sidebar title is now its only heading; the prose checks are
unchanged.

**Negative control and mutations.** On unmodified `36c6265` sources, with a shim supplying an empty
`boxTitles`, all 7 new tests fail. `mutations.txt`: each of 15 parts, disabled in turn, fails a test.

**`corpus/regressions.json`** (`tools/addcontract.py`):

- Fed headings on 19, 26, 27, 37, 63 and 95; ordered text on 27; absent split halves on 37 and 63's
  paragraph.
- FAA headings on 21 and 404; absent halves on 21; ordered text on 404; page 6 text.
- Wallace page 5 and 211 text.
- 9/11 page 348: absent heading and paragraph (control).

On `d333b4d` the baseline fails exactly the new Fed (8), FAA (6) and Wallace (2) checks. The 9/11
control passes on both sides; the intermediate candidate with the column-only reading made it a
heading.

**Suites.** `swift test`: 481 tests pass (474 at `d333b4d`). `scripts/check-all.sh --fast`: exit 0
(481 Swift, 204 Python, fixture repeats byte-identical, 8/8 concurrency processes).

## Remaining and defects to file

1. **FAA page 348 is a whole-page preserved region.** 853 paints; its two bold-italic two-line titles
   and their paragraphs are an image. This is the crop/figure path, not headings.
2. **Sidebar titles rank h6, box titles h5.** The level follows type size. Ranking the Fed's 8-point
   sidebar titles with the 14-point `Box N.N.` titles would need a level that is not size-ranked.
   The issue asked for the same level; this is a question for the navigation model.
3. **Plain-type `X = Word` titles outside contents pages** would still seed a formula crop. There is
   no corpus instance.
4. **Tagged two-line italic titles.** #90's tagged rule (`setsItalicTitle`) accepts one line only.
   There is no corpus instance.
5. **FAA contents folios** (`vii`, `viii`) are tagged paragraphs kept in tag order mid-page; they are
   not furniture.
