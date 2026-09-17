# A ruled running foot, first-line indents, small subheads and edge credits (#159)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, Xcode 27, release CLIs.
Baseline `730a4dd` (the coordination branch's head, which already carries #151's page images, #153's
column order, #148's hyphens, #162's academic titles, #165's overprints and #27's caption pairing),
candidate this tree on it.

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline | `730a4dd` | `5bf02b125d413b9b36ce571e9e7b36480e3421ed26d11f81e213b0fd67aff8f5` |
| candidate | this tree on `730a4dd` | `7ccec258b72f15ee1afcc933b3aae3377636f6d9f7b34cbd6c2be5aa2b6c960b` |
| probe | `tools/probe-raster-environment.swift` | `cbf9fabb801c2acd89433d713236eacac103824f3749e254b0b1ef15c4bc72e3` |

Python 3.14.6; EPUBCheck from `/opt/homebrew/bin/epubcheck`. No source PDF or EPUB is committed; each
evaluation was deleted once its result was recorded. Four source fixtures were captured with
`tools/capture-layout-fixture.swift` (`usda-9`, `usda-17`, `usda-19`, `flag-11`); `usda-15` was
already committed and was not recaptured.

## What the other fixes had already closed

On the baseline, USDA ARS *Agricultural Research*, November/December 2012
(`usda-ars-agresearch-2012-11`) still shows most of what #159 reports. Three of the issue's eight
items are already fixed and are not reopened here:

- **The end-of-story mark is no longer tripled** (item 2). Pages 15, 17 and 19 end their contact
  paragraph `…@ars.usda.gov.` and one bold `*`, not `***` and not `<sub>`. #165's overprint removal
  closed it: the magazine draws the red asterisk three times in one place.
- **Italic-led lines are no longer `<pre>`** (item 5). Page 19's `E. coli populations in agricultural
  runoff,”` and `E. coli isolates collected from water and` read inside their paragraphs (#146).
- **`Mis-` / `sissippi` is joined** (item 8, in part). Page 6 reads `Oxford, Mississippi, to find
  plant-derived compounds` as one line. `com-panies` (page 6) and `infec-tions` (page 19) still keep
  their line-end hyphen; see Remaining defects.

Everything else in items 1, 3, 4 and 6 reproduces on the baseline, and items 7 and 8 are untouched.

## Evidence

Geometry from `tools/capture-layout-fixture.swift` on all 24 pages, read against 60 DPI Poppler
renders. The magazine sets a 612×792 page: three 172-point columns at x 36, 220 and 404, a
10.5-point body at 12.5-point pitch, and a 9-point running foot and folio at y 24–36.6.

### The running foot (item 1)

The foot is on every page from 2 to 23 and is identical on all of them, alternating only between the
left corner (odd pages, x 36.0–238.2) and the right (even pages, x 373.7–576.0). Its position in the
page is 0.0383 and 0.0386 — inside the 7% footer band — and its type size is 9 points everywhere.
Nothing in the run rules objects to it. `FurnitureDetector.record` never saw it:

> the line must be separated from inward content by at least `max(line height, 1.2% of the page)` =
> 12 points, measured to the nearest line above it.

| Page | Nearest line above the foot | Gap | Recorded? |
| --- | --- | ---: | --- |
| 2, 3, 4, 5, 10, 13, 14, 16, 18, 22, 23 | body or caption | 14.3–181.3 | yes |
| 6, 7, 8, 9, 11, 12, 17, 19, 20, 21 | a 6-point photo credit at y 44.1–46.3 | 7.5–10.0 | no |
| 15 | the article's own last line `1624, dennis.obrien@ars.usda.gov.*` | 8.2 | no |

So eleven pages kept their foot, and the run over the eleven that were recorded broke twice more:
2–5 (removed), 10 alone, 13–18 (removed), 22–23 (two pages, under the three-page minimum).

The page prints the boundary the white space does not: **a 544×4-point rule at x 34.5, y 39–43.4 —
89% of the page's width — runs under the columns of every page from 2 to 23**, between the foot and
everything above it. It is the same rule `ColumnMarginOrderTests` already reads on page 15 (“the
running foot's rule crosses the third [column]”). On pages 2 and 23 the reader's clustering merges it
with the signature box and the index ornament, and both of those pages are separated by white space
anyway.

Two further pages broke the run for a second reason. Pages 20 and 21 draw graphics the reader cannot
reflow (`GraphicsReader.unsupported`), so `NativeTextReader.lines` is called with `includeStyle:
false` and every line's `fontSize` is its measured glyph height: the foot reports **11.979 points**
there against the **9.000** every other page reports. `resolve` compares those as type sizes, 33%
apart, and splits one run of twenty-two into 2–19, 20–21 and 22–23. `Candidate.fontSize` already
carries this workaround for bare folios (“fallback extraction estimates fontSize from that height”);
nothing carried it for a prose foot.

### First-line indents (item 4)

Every column opens its paragraphs **10.0 points in** (x 46.0 against the column edge 36.0, 0.95 em of
the 10.5-point body) and adds 2.1 points of space: a wrapped line reports a gap of −1.30 and an
opening line +0.86. Page 9's left column is the reproducer — `see which ones are more effective…`,
`Only a few studies…` and `Another laboratory…`, three source paragraphs — and every column of pages
6, 12, 15, 18 and 19 does the same.

`blocks`' same-column test allows a line to drift by **1.5 bodies = 15.75 points** before it opens a
paragraph, so a 10-point indent is invisible to it; `continuesOpening`'s own indent branch starts at
1.5 bodies too. The space is no help either: 2.1 points is well under `opensSpacedParagraph`'s half a
body.

This is not a magazine defect. Four other books indent their openings inside that tolerance and
merged the same way on the baseline:

| Book | Body | Indent | Indent in bodies |
| --- | ---: | ---: | ---: |
| `usda-ars-agresearch-2012-11` | 10.5 | 10.0 | 0.95 |
| `gpo-911-2004` | 10.25 | 12.0 | 1.17 |
| `scotus-loper-bright-2024` | 10.98 | 10.9 | 0.99 |
| `arxiv-replay-clocks-2023` | 9.06 | 10.0 | 1.10 |
| `ntrs-20190030725-dasc-2019` | 9.96 | 9.97 | 1.00 |

The 9/11 report's page 19 shows the size of it: `Boston: American 11 and United 175. Atta and Omari
boarded a 6:00 A.M. flight…1`, `When he checked in for his flight to Boston…` and `Atta and Omari
arrived in Boston at 6:45…` are three printed paragraphs and were one.

What a first-line indent cannot produce is two indented lines in a row: the paragraph returns to the
measure beneath its opening line. That is the same distinction `hangingRun` draws for #162's
spaceless hanging lists, read the other way round.

### Sub-headings under the body size (item 3)

The magazine heads its sections with **9-point bold** lines on the column's own edge, inside a
**10.5-point** body — smaller than the text they head. They carry 5.6–5.7 points of space above,
against the column's own −1.30, and the section's first paragraph opens directly beneath them on the
10-point indent, 0.1 points below the title's own descender.

| Page | Subhead | x | Size | Space above | Paragraph beneath |
| --- | --- | ---: | ---: | ---: | --- |
| 6 | `Unlocking the Chemistries of` / `Folk Remedies` | 220.2 | 9 | 5.69 | `Some of those discoveries…` at 230.2 |
| 12 | `Rounding Up the Best Equipment` | 36.1 | 9 | 5.63 | `Each year, ARS scientists…` at 46.1 |
| 13 | `Taking It to the Field` | 37.8 | 9 | 5.66 | `“Whenever you get a new compound…` |
| 17 | `How Much Pressure Can a` / `Leaf Take?` | 220.0 | 9 | 5.69 | `Another way to determine…` at 233.3 |
| 17 | `Sensing Trees’ Water Needs` | 36.0 | 9 | 5.66 | `Wang and Jim Gartung…` at 51.4 |
| 18 | `Sourcing Solutions` | 404.0 | 9 | 5.78 | `Ibekwe, California State…` at 414.0 |
| 19 | `A Range of Resistance` | 36.0 | 9 | 5.68 | `As part of the study…` at 46.0 |

Three tests in `sectionLabels` each refused them on their own:

1. the sub-heading floor is `body * 0.95` = 9.975 points, and the line is 9;
2. the clear space above must be `body * 0.8` = 8.4 points, and there are 5.7;
3. `opens(beneath:)` asks for the paragraph on the title's own left edge (within half a body), and
   the paragraph opens 10 points in.

Where the title and the paragraph fell in one reading order the merge showed as a run-in
(`<p><strong>Rounding Up the Best Equipment</strong> Each year, ARS scientists…`); where the column
interleaving of #153 separated them it showed as a bold paragraph.

### Photo credits (item 6)

Every photograph carries a **6-point** credit — the smallest type on its page — set 1.4 to 3 points
outside the picture at one corner, above it as often as below, and 58–76 points wide against
pictures 216 to 540 points wide.

| Page | Credit | Picture | Set |
| --- | --- | --- | --- |
| 4 | `STEPHEN AUSMUS (D2627-12)` | y 52.5–671.7 | 1.9 above |
| 6 | `PEGGY GREB (D2693-1)`, `(D2695-1)` | y 53.3–508.3, y 53.7–285.5 | 1.1, 1.5 below |
| 9 | `STEPHEN AUSMUS (D2619-4)` | y 55.5–487.5 | 3.1 below |
| 12 | `SETH BRITCH (D2643-1)` | y 53.9–459.0 | 1.4 below |
| 15 | `BRAD FRITz (D2697-1)` | the phone photograph | 1.8 above |
| 17 | `DONG WANG (D2686-1)` | y 485.9–755.9 | 1.7 above |
| 17 | `PEGGY GREB (D2680-1)` | y 54.6–324.6 | 2.8 below |
| 19 | `PEGGY GREB (D2687-1)` | y 53.9–583.8 | 2.5 below |

Read where it stands, a credit takes the place the page's reading order gives it, which on pages 13
and 17 is the top of the page while the picture is the last block: `DONG WANG (D2686-1)` opened page
17 and its photograph stood twenty-one blocks later. On page 17 the lower credit also landed on the
wrong side of its picture.

## Rules

**`FurnitureDetector.ruledOff(_:top:on:)`.** A margin candidate the separation rule would refuse is
admitted when a graphic rect lies wholly in the gap between it and the nearest line inward, is no
taller than the candidate's own line or 2% of the page, and spans at least 60% of the page's width.
It admits a candidate to the ledger; the band, outermost-row, run, position, size and repetition
rules still decide it.

**`FurnitureDetector.Candidate.height` / `.estimatedSize`.** A candidate records its measured glyph
height beside its type size, and whether its page reported no font attributes
(`PageContent.requiresPageImage`). When either end of a run comparison is such an estimate, `resolve`
compares the heights both pages do report instead of an estimate against an attribute.

**`LayoutReconstructor.firstLineIndentRun(in:step:size:)`.** Whether the page opens its paragraphs on
an indent of `step`, read as steps between neighbouring lines of one size so that every column of a
page supplies evidence: an opening line stands `step` inside the line above it and the line beneath
returns `step` outward, at least two such lines stand on the page, and no line beneath an indented
one shares its edge (which is what a hanging indent does). Only lines within a tenth of `size` are
read, and a neighbour must stand at ordinary leading, so a heading or a caption between two
paragraphs is neither a neighbour nor evidence.

**`opensIndentedParagraph`** (in `blocks`) breaks a paragraph at such an indent: the line stands half
a body to one and a half bodies inside the previous line, in the same type at ordinary leading, is
neither a list line nor a heading, opens with a capital and holds words, the line above ends a
sentence, and `firstLineIndentRun` confirms the page's pattern. Indents of one and a half bodies and
wider keep their existing path (`continuesOpening`, #147).

**Sub-headings under the body** (`sectionLabels`). The candidate floor drops from `body * 0.95` to
`body * 0.8`; a line under `body * 0.95` (`smaller`) must be wholly **bold** — the smaller type a
magazine sets beside its body is otherwise a caption or a credit — and its paragraph must open on the
page's own first-line indent rather than flush with it, which is the positional evidence that
replaces the size evidence a smaller line does not have. For such a line the clear space above is
measured against the column's own leading (`ordinaryLineGap(body, …) + body * 0.5`) instead of four
fifths of a body, capped at the old threshold so nothing larger is admitted more easily. Body-size
and larger labels keep every rule they had; the hanging-entry path (#134) stays closed to smaller
lines.

**`LayoutReconstructor.attachEdgeCredits(_:page:images:body:)`** runs after `joinWordBreaks`. A
paragraph holding one source line, set in the smallest type the page uses and smaller than the body,
standing within half a body of a preserved region's top or bottom edge, wholly inside that region's
width, no wider than half of it, outside every region, opening with no raised note marker, and with
no other line reaching the band between the picture and the credit's far side anywhere across the
picture, moves to the near side of that region's image — after it when the credit is set below the
picture, before it when above. A thin rule is no picture. A credit already beside its picture does
not move.

## Contracts (`corpus/regressions.json`)

49 checks added to `usda-ars-agresearch-2012-11` (164 → 213); the corpus total is 3,103 → 3,152 on the
same 539 reviewed pages.

| Type | Added | Where |
| --- | ---: | --- |
| absent-text | 11 | the running foot on pages 6–12, 15, 17, 19, 22 |
| warning | 10 | `furnitureRemoved` on those pages; page 22 already carried a `warningCodesAnyOf` check for `imageRegion`, so its code joins that one |
| heading | 6 | `Rounding Up the Best Equipment` (12), `Taking It to the Field` (13), `Sensing Trees’ Water Needs` and `How Much Pressure Can a Leaf Take?` (17), `Sourcing Solutions` (18), `A Range of Resistance` (19) |
| distinct-paragraph | 11 | pages 9, 12, 13, 15, 18, 19 |
| paragraph | 2 | page 9's first and third source paragraphs, whole |
| captioned-image | 9 | pages 4, 6 (two), 9, 12, 15, 17 (two), 19, with `before` on 4, 15 and 17's upper credit |

The baseline fails **30** of the 49 and passes the other 19: the ten `furnitureRemoved` checks (the
baseline already removed every page's *folio*, which raises the same warning), page 4's and page 6's
left credit and page 13's two checks (placements the baseline's reading order already produced), and
page 9's two whole-paragraph checks, which a containment check cannot fail on a merged paragraph —
the `distinctParagraphs` pairs beside them are what fail. The candidate passes all 213.

Two placements are deliberately **not** pinned, because they are still wrong:

- page 6's `Unlocking the Chemistries of` / `Folk Remedies` are two headings rather than one. #153
  still interleaves that page's three columns line by line, so the two lines of one title are not
  adjacent in the reading order.
- page 9's `Fighting Filth Flies` is still a bold paragraph. It is a sidebar title standing over the
  sidebar's photograph, 142 points above the sidebar's own first paragraph, so no paragraph opens
  beneath it.

## Tests (`Tests/PDFReflowLibTests/FootRulesIndentsAndCreditsTests.swift`)

| Test | Reproducer / control |
| --- | --- |
| `aRuleUnderTheColumnSeparatesTheFootFromTheCreditAboveIt` | Synthetic magazine pages: the ruled foot goes, the credit and the column stay. Control: with the rule removed the foot stays, as on the baseline. |
| `aSeparatingRuleMustBeThinPageWideAndInsideTheGap` | Four controls: a 20-point rule, a half-width rule, a rule above the credit and a rule overlapping the foot each keep the foot. |
| `anEstimatedTypeSizeDoesNotSplitAFootsRun` | Two `requiresPageImage` pages inside a six-page run keep it whole. Control: a page reporting a real 15-point foot still splits it. |
| `sourceMagazineFeetGoWhileTheCreditsAndProseStay` | `usda-15`, `usda-17`, `usda-19`: the run of three, whose feet are crowded by a credit (17, 19) or by the article's last line (15); every other line survives. |
| `sourceColumnsBreakAtTheirFirstLineIndent` | `usda-9`: three source paragraphs, each whole and each ending where the source does. |
| `anIndentOpensAParagraphOnlyWhereThePageRepeatsIt` | `firstLineIndentRun` in isolation: three indented openings qualify; a hanging indent, a single opening, another step and another size do not. |
| `anIndentedLineContinuesItsParagraphWithoutThePagesPattern` | One drifted line in a column that shows no other indent keeps its paragraph. |
| `sourceSubheadsSmallerThanTheBodyAreHeadings` | `usda-19`, `usda-17`: the 9/11 label style is the page's own evidence, and the subheads are headings. Control: without the recurring style the line stays a paragraph. |
| `aSubheadUnderTheBodySizeNeedsBoldAndAnIndentedParagraph` | `usda-19` with six mutations: plain type, italic type, 7-point type, a flush paragraph, a paragraph stepped 30 points, and the title set at the column's own leading. |
| `sourceCreditsReadBesideTheirPhotograph` | `usda-17`: the upper credit stands before its picture and the lower one after it. |
| `aCreditSharingItsRowWithACaptionStaysInReadingOrder` | `flag-11`: Our Flag sets `“Old Ironsides” in the War of 1812.` and `Courtesy U.S. Naval Academy Museum` on one row under the engraving; the row keeps its left-to-right order. |
| `onlyASmallTagAgainstAPicturesEdgeIsACredit` | `attachEdgeCredits` in isolation, with six controls: body-size type, a line over half the picture's width, a whole body of space, a line outside the picture's measure, a raised note marker, and a thin rule in place of the picture. |

Two existing suites changed:

- `HeadingPlacementTests.subheadingNeedsBoldStyleClearSpaceAndAParagraphBeneath` keeps its control
  that a 9-point bold line over FAA page 165's 10-point body is no sub-heading. It passes because the
  paragraph beneath it is flush with the title, not on a first-line indent — the extra evidence a
  smaller line now has to supply.
- `BoxTitlesAndTwoLineSubheadsTests.boxTitleNeedsSpaceBeneathItsEdgeAndNoSentenceEnd` asserted that
  the 9/11 report's page 348 sidebar reads as **one** paragraph from `FBI was aware of the flights` to
  `The FBI interviewed all persons`. The renders say otherwise: the sidebar ends
  `…allowed to depart.30` short of its measure and sets `The FBI interviewed…` one em in, over lines
  that return to the box's edge. The assertion now requires two paragraphs, each ending where the
  source ends it, and still requires that neither line is a heading, which is what the test was added
  for (#100).

## Corpus lanes

`tools/run_corpus_regressions.py`, one case per call, with the compiled raster/Vision probe and
`--execution-context host-terminal`. **All 21 cases pass.** Every case was also converted with both
binaries and its markup compared with page ids, hrefs and asset names stripped; five cases differ,
and `tools/compare_conversion_runs.py --allow-different-converters --detail` was run on each
(`lane-summaries/<case>-drift.json`).

| Case | Baseline | Candidate | Changed pages |
| --- | --- | --- | --- |
| usda-ars-agresearch-2012-11 | fails 30 of the 49 new checks | pass | 14: 6–13, 15, 17, 18, 19, 22, 24 |
| gpo-911-2004 | pass | pass | 336 |
| scotus-loper-bright-2024 | pass | pass | 35 |
| arxiv-replay-clocks-2023 | pass | pass | 8 |
| ntrs-20190030725-dasc-2019 | pass | pass | 4: 1, 2, 3, 5 |
| faa-phak-8083-25c, wallace-algebra-2010, fed-explained-2021, dga-2025-2030, gpo-our-flag-2003, cia-blue-book-14-1955, cdc-zombie-pandemic-2011, nbs-jres-geltman-1977, usgs-mcs2025-copper, census-rrs2002-01, uscourts-pro-se-1-2016, ntrs-20200002975-gwl-2020, ntrs-20180003024-earthdata-slides-2018, ntrs-20210020887-techport-thm-2021, uscis-m618-arabic-2015, irs-p596-zhs-2025 | pass | pass | none |

No image changed on any case (`imageRenames` 0, `changedImages` empty everywhere), and no report
field changed outside the magazine. The changed fields are `markup`, `paragraphs` and `paragraphIDs`
on every changed page, plus:

- `headings`, `headingLevels`, `headingRanks` and `anchors` on USDA 6, 12, 13, 17, 18 and 19, the six
  new subheads, and `headingRanks` alone on USDA 24, where the back cover's `<h5>`/`<h6>` shift tier
  because six more headings joined the document-wide ranking;
- `warnings` on USDA 17, which gains one `uncertainHyphen`. With page 17 reading column by column,
  `cal-` + `culated` and `cham-` + `ber` now meet their wrapped line; the magazine prints neither
  word whole anywhere, so the hyphen policy keeps the hyphen and warns, as it does for every join it
  cannot decide (#148). The page's `furnitureRemoved` was already there: the baseline removed every
  page's folio, so all 22 pages raised that warning before and after;
- the magazine's report: `reflowedPageCount` 18 → 17, because page 22's only reflowed text was its
  running foot and the index itself is inside a crop (#158); and one warning more, the page-17
  `uncertainHyphen`;
- `notes` and `anchors` on Loper Bright 24 and 26: footnote 4 was appended after the page markers a
  paragraph joined across pages 24, 25 and 26 carried inside it, and now follows the shorter join on
  page 24. Its text is unchanged;
- `text` on 9/11 pages 272 and 357 only. Both are chapter openings whose body had been absorbed into
  a paragraph opened on an earlier page, so the page marker stood inside it; with the paragraphs
  split, the page's own text is attributed to the page that prints it. No word is added or lost:
  the phrase appears exactly once in each run.

Every changed page was read against the source renders. Outside the magazine the change is one kind:
a printed paragraph that had been merged into the one above it now opens its own block. Examples read
on the renders: 9/11 page 19's three paragraphs of the Boston narrative and page 15's preface
paragraphs; Loper Bright page 6's `Finally, the view that interpretation…` and page 17's three New
Deal paragraphs; the Replay Clocks paper's page 1 introduction (five paragraphs) and page 2
definitions; the IEEEtran paper's page 1 introduction and page 3 constraint paragraphs.

Warren and NOAA are outside the lane (#5); both were converted directly with the screening harness
and their markup is unchanged.

Disk: 24–31 GB free throughout, checked before each conversion.

## Verification

- `swift test`: 838 pass (12 in `FootRulesIndentsAndCreditsTests`).
- `scripts/check-all.sh --fast`: exit 0, including the generated doc counts and byte-identical repeat
  conversions.
- `tools/check_corpus_content.py` on each candidate evaluation, and on the baseline magazine
  evaluation to record the 30 failures.
- Corpus lanes and drift comparisons above.

## Remaining defects

1. **The back cover's dingbat is still `<sup>l</sup>`.** Page 24 reads `Visit us at ars.usda.gov/ar
   <sup>l</sup> Follow us at twitter.com/USDA_ARS`. The separator is a bullet drawn from a
   MonotypeSorts-style font that is not embedded; PDFKit substitutes Helvetica and reports the
   character as a literal `l` at 6 points with a baseline offset of 1, so it is raised as a
   superscript and never decoded. It is not a private-use code point, so #155's `PrivateUseDecoder`
   does not see it: a dingbat font's ASCII codes need their own table. Furniture removal takes the
   other eleven occurrences with the running foot.
2. **`BRAD FRITz` (page 15).** The magazine sets `Brad Fritz` in small capitals; PDFKit reports the
   final small-cap `z` from a different font as lower case. An extraction/encoding defect.
3. **The mailing panel and two cover lines are still headings** (item 7). Page 24's return address,
   `Official Business` and the web line are `<h6>`/`<h5>`, and the cover's `pages 2, 4-14` and the
   `Agricultural Research Service • Solving Problems for the Growing World` tagline are `<h4>`; all
   of them enter the contents. Out of scope here: they are not sub-headings but display lines on
   pages that carry almost no body text, so the page has no body size to measure them against.
4. **`com-panies` (page 6), `infec-tions` (page 19) and `compli-ance` (page 15) keep their line-end
   hyphen** inside a joined paragraph (item 8).
5. **Page 6 still interleaves** (#153), so its two-line subhead is two headings and its columns read
   one paragraph per line.
6. **Page 9's `Fighting Filth Flies` is still a paragraph.** A sidebar title over the sidebar's
   photograph has no paragraph beneath it; `opens(beneath:)` reads one page's lines in place, not
   past a figure.
7. **Page 13's credit still reads first.** The page's photograph covers the page and is emitted as
   the `Original page 13` reference image, whose rect contains the credit, so the credit is inside
   every region and no picture edge is available to attach it to.
8. **Sub-headings and the cover's headings share tiers.** The six new `<h6>` subheads and the back
   cover's mailing panel rank by size alone, so the panel's 10–11 point lines outrank the 9-point
   section titles.
