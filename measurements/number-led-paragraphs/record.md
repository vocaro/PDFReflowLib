# Number-, year- and initial-led paragraphs, and a Word paper's titles and tags (#146 item 1, #154)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, Xcode 27, release CLIs.
Work started on `a23174a` and the tree was merged up to `b1c7043` (#151) before the lanes recorded
here; the baseline is `b1c7043` itself, so every difference below is this change alone.

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline | `b1c7043` | `2f80abb04bde12e7b7ee6d6380322598786cc62dc149b76e726e0f27e5606fee` |
| candidate | this tree on `b1c7043` | `8114b0319c474f79ee7b8e1a28c19440d4d6d6ed5c025415598b2ee23b751507` |
| probe | `tools/probe-raster-environment.swift` | `66eb96727ca992c6c50be629ad9534bb56c0a0499fd54955b0b8b1731399d4bd` |

No source PDF or EPUB is committed; each lane's EPUBs were deleted after its page diff. Nine source
fixtures were captured with `tools/capture-layout-fixture.swift` (`911-7`, `911-146`, `911-179`,
`911-288`, `fed-92`, `faa-18`, `flag-18`, `ntrs-2`, `ntrs-19`); no fixture was recaptured.

## Evidence

### Ordinary text read as a list item (#146 item 1)

`LayoutReconstructor.blocks` reads every line opening with a number or a single letter before a
period or parenthesis as a preformatted list item, unless `continuesParagraph` shows it wrapping the
open paragraph. Three gaps in that test made prose into list items:

1. **The column's right edge was its furthest line.** The 9/11 report justifies to 356.6 points but
   sets some lines 2.9 points past it (a hung closing quote or period). `continuesParagraph` asked
   the previous line to reach `max − 0.25 body` (2.5 points), so every wrapped line failed the test
   on those pages: `…first met at a mosque in Hamburg in` / `1995. The two men…` (179), `…in 1998
   and` / `1999. Although…` (206), `…sent to Clarke on December` / `29. The memo proposed` and
   `…renewed Predator flights in March` / `2001. A sentence called…` (215), `…in place by August` /
   `1. Rice told us…` (229).
2. **A ragged column could not join at all**, because only a justified measure was accepted: Fed
   page 92's `The U.S. payment system has evolved significantly since the Federal Reserve was
   established in` / `1913. At that time,…`.
3. **A marker that opens a paragraph had no test at all**: 9/11 page 288's `2000. They decided that
   if Mihdhar was in the United States, he should be` / `found.` (the page's first paragraph, which
   continues from page 287) and FAA page 18's `P. E. Fansler, a Florida businessman living in St.
   Petersburg,`. Both were split in two — a `<pre>` item plus the paragraph its own wrapped line
   opened — so the text was not only mislabelled but cut.

The same shape appears in Loper Bright (`v. NLRB, 522 U. S. 359, 374 (1998))…`, page 26; `M. Hale,
The History and Analysis…`, 49; `F. Bacon, The Lord Keeper's Speech…`, 51; `102. But, in truth,…`,
73; `p. 27; App. to id.,…`, 107), Replay Clocks (`6. Since this observation…`, page 7), the Warren
Commission report (33 lines), NOAA (reference author lists, `S. Martinuzzi, A.D. Syphard, …`) and
the two magazines added this week.

Real numbered lists wrap flush in the same books, so shape alone cannot separate them: the 9/11
report's Presidential Daily Brief items (`1.` on page 146, `2.` and `3.` on 147) and NOAA's numbered
references run on exactly like the prose above. What separates them is the sequence: a list has
another marker one or two values away (Wallace's answer keys print the odd exercises only), on the
page or on the page beside it.

### The NASA Word paper (#154)

- Section titles `2.`–`6.` are 12-point bold capitals over a 10-point body — 1.2 times the body, under
  the 1.25 heading threshold — so only `sectionLabels` could admit them, and it refuses every line
  with a list marker. `1. INTRODUCTION` is a heading only because page 1's abstract sets the body at
  9 points, which puts 12 over the threshold. The unnumbered `APPENDIX` and `BIOGRAPHY` are in the
  same 12-point bold style but were not admitted either, since the style was not yet recurring
  evidence.
- Page 19 tags eight references, a DOI line and one wrapped reference line `H1` (Word's heading
  style applied to reference paragraphs). The tags validate, so they became `<h5>` headings among
  the `<p>` references in the same 9-point type.

## Rules

`LayoutReconstructor.ListMarker(_:)` reads a line's numbered or lettered marker (kind, punctuation,
value) and `isSibling(of:)` accepts a marker of the same kind and punctuation one or two values
away. `listMarkers(on:)` collects a page's markers during extraction; the pipeline passes the
previous and next page's markers to `blocks` as `neighbouringMarkers`, so a list broken by the page
keeps its items. A marker with no sibling in the same type size is *lonely*.

In `blocks`:

- `continuesParagraph` measures the column's right edge as the edge most lines share within a
  quarter body, among the lines within half a body of the furthest, instead of the furthest line.
- A lonely marker also continues the open paragraph where the column is ragged: every other test is
  unchanged and the previous line need only run three quarters of the column's widest line.
- `runsOnFlush`: a lonely marker line opens a paragraph when it leaves its sentence open, reads as
  at least three words, runs three quarters of the measure its edge shares, and the line directly
  beneath it sits on its own left edge at ordinary leading (−0.4 to 0.9 body) in its type and opens
  no list of its own.
- `continuesListItem` accepts a lonely marker line as an open item's wrapped line, so NOAA's
  reference author lists join their reference at its hanging indent.

`sectionLabels` admits one kind of marked line: `isNumberedTitle`, a one- or two-digit number and
period before a title wholly in capitals or wholly bold, not ending in a folio, when no other line
on the page opens a marker continuing its number (the 9/11 contents entries `10.`–`13.` do).

`blocks` demotes a validated heading tag to a paragraph when the page's own tags and typography
contradict it: every line of the group is no larger than the page's body and set in a `LabelStyle`
that a `P` group on the page also uses, and the group's text closes a sentence past closing quotes
over 40 characters, or opens lowercase.

## Contracts (`corpus/regressions.json`)

| Case | Added |
| --- | --- |
| gpo-911-2004 | paragraphs on 179, 206, 215 (two), 229, 288; list item `1. Reporting [—] suggests Bin Ladin…` on 146 (control: the PDB list keeps its first item) |
| fed-explained-2021 | paragraph on 92 |
| faa-phak-8083-25c | paragraph on 18 |
| scotus-loper-bright-2024 | paragraphs on 51 and 73 |
| ntrs-20200002975-gwl-2020 | headings `2.`–`6.`, `APPENDIX` and `BIOGRAPHY` on 2, 3, 6, 8, 12, 13 and 20; page 19 references `[16]` and the DOI line as paragraphs and not headings |

The baseline fails all five cases on exactly these checks (`errors` lists 6, 1, 1, 2 and 11
failures respectively: 9/11's six paragraphs, Fed's, FAA's, Loper Bright's two and the NASA paper's
seven missing headings, two unwanted headings and two missing paragraphs); the candidate passes every case in the lane.

## Tests (`Tests/PDFReflowLibTests/NumberLedParagraphTests.swift`)

| Test | Reproducer / control |
| --- | --- |
| `yearAfterAnOpenRaggedLineContinuesItsParagraph` | `fed-92`: `1913.` joins its ragged paragraph; a neighbouring page's `1912.` item in the same type makes it a list item again, and `1912.` in another type does not. |
| `yearInAJustifiedColumnContinuesItsParagraph` | `911-179`: `1995.` joins; the page emits no `<pre>`. |
| `justifiedEdgeIsTheSharedEdgeNotTheFurthestLine` | Synthetic justified column with two lines past the shared edge and a real `1.`/`3.` list on the page (so the marker has siblings): the marker joins; with the previous line short of the edge it stays an item. |
| `yearOpeningAFlushParagraphIsNoListItem` | `911-288`: `2000. They decided …` and `found.` are one paragraph. |
| `initialsOpeningAParagraphAreNoListMarker` | `faa-18`: `P. E. Fansler…` is a paragraph; a neighbouring `O.` item makes it a lettered item. |
| `aListBrokenByThePageKeepsItsFirstItem` | `911-146` with `911-147`'s markers: item `1.` stays a list item; without the next page it reads as a paragraph. |
| `markerValuesAndSiblings` | Marker parsing and sequence: `12.` with `13.`/`14.` but not `15.`, `11)` or itself; `b)` with `a)` but not `A)`; bullets, `1)− 2`, `3.5 percent`, `10.August 2001` and plain text carry no marker. |
| `numberedSectionTitleIsAHeading` | `ntrs-2`: `2. TEST DESCRIPTION` is a heading, not `<pre>`. |
| `numberedContentsEntriesAreNoHeadings` | `911-7`: the contents entries `11.` and `13.` are no headings and keep their list representation. |
| `numberedTitleNeedsCapitalsOrBold` | Capitals or bold required; an answer-key entry, a year-led capital line and a folio-ending contents entry are refused. |
| `headingTagOnReferenceTextIsAParagraph` | `ntrs-19`: the `H1`-tagged references and DOI line are paragraphs; without the page's `P`-tagged references in the same type the tags stand. |
| `bodySizeTaggedTitleStaysAHeading` | `flag-18`: body-size `§174. Time and occasions for display` stays a heading; the same line given a closing sentence does not. |

Negative mutations (`tools/mutate.py`, `negative-mutations.txt`), run over the number-led,
citation-continuation, list, academic-front-matter, page-continuation, exercise, note, heading and
structure suites; every mutation is caught, including reverting the sequence and edge rules
together, which fails all six source reproducers.

## Corpus lanes

`tools/run_corpus_regressions.py`, one case per call, with the compiled raster/Vision probe, then
`tools/compare_conversion_runs.py --allow-different-converters` (`lane-summaries/<case>.json`).
Page markup for every changed page is in `pagediff-<case>.txt`
(`measurements/hanging-entries/tools/pagediff.py`). 32–41 GB free throughout.

| Case | Baseline | Candidate | Changed pages |
| --- | --- | --- | --- |
| gpo-911-2004 | fails the 6 new checks | pass | 6: 14, 179, 206, 215, 229, 288 |
| fed-explained-2021 | fails the new check | pass | 1: 92 |
| faa-phak-8083-25c | fails the new check | pass | 1: 18 |
| scotus-loper-bright-2024 | fails the 2 new checks | pass | 7: 26, 49, 50, 51, 73, 106, 107 |
| ntrs-20200002975-gwl-2020 | fails the 11 new checks | pass | 8: 2, 3, 6, 8, 12, 13, 19, 20 |
| arxiv-replay-clocks-2023 | pass | pass | 1: 7 |
| cia-blue-book-14-1955 | pass | pass | 8: 168, 176, 206, 221, 230, 234, 245, 248 |
| ntrs-20190030725-dasc-2019 | pass | pass | 1: 10 |
| usda-ars-agresearch-2012-11 | pass | pass | 1: 19 |
| wallace-algebra-2010, dga-2025-2030, gpo-our-flag-2003, cdc-zombie-pandemic-2011, usgs-mcs2025-copper, census-rrs2002-01, nbs-jres-geltman-1977, uscourts-pro-se-1-2016 | pass | pass | none |

No image, report field or warning changed on any case; navigation changed only on the NASA paper,
which gains its seven section titles. Every changed page was read against the source renders:

| Case | Page | Change |
| --- | --- | --- |
| gpo-911-2004 | 14 | Two staff names (`L. Christine Healey`, `C. Michael Hurley`) join the surrounding staff-list paragraph, as the page's other names already did. |
| gpo-911-2004 | 179, 206, 215, 229 | The year- or number-led line joins the paragraph it wraps; `29. The memo proposed` closes the `Blue Sky` sentence. |
| gpo-911-2004 | 288 | `2000. They decided … he should be found.` is one paragraph again (`<pre>` plus a split paragraph before). |
| fed-explained-2021 | 92 | `…established in 1913. At that time,…` is one paragraph. |
| faa-phak-8083-25c | 18 | `P. E. Fansler…` is a paragraph. |
| scotus-loper-bright-2024 | 26, 49/50, 51, 73, 106/107 | Each citation line joins its paragraph; on 49/50 and 106/107 the paragraph now continues across the page as well. |
| arxiv-replay-clocks-2023 | 7 | The footnote line `6. Since this observation…` is a paragraph (the page's columns still interleave, #153). |
| cia-blue-book-14-1955 | 168, 176, 206, 221, 230, 234, 245, 248 | Eight inherited-OCR table rows (`t) lj 0 eJ.O ()_0 (JL)`) read as paragraphs instead of list items; both are wrong for a scanned table, and no text changed. |
| ntrs-20190030725-dasc-2019 | 10 | The author line `S. M. Jurcak, S. K. Iyer, and P. Verma…` of reference [7] is a paragraph. |
| usda-ars-agresearch-2012-11 | 19 | Two `E. coli` lines are paragraphs. |
| ntrs-20200002975-gwl-2020 | 2, 3, 6, 8, 12 | `2.`–`6.` are `<h3>`. |
| ntrs-20200002975-gwl-2020 | 13, 20 | `APPENDIX` and `BIOGRAPHY` become `<h3>` as well: the numbered titles make their 12-point bold style recurring label evidence. |
| ntrs-20200002975-gwl-2020 | 19 | Ten `<h5>` references, DOI and wrapped lines are paragraphs; reference [10]'s wrapped line rejoins its entry. |

Warren and NOAA are outside the lane (#5), so both were converted directly with
`--maximum-output-bytes unlimited --no-ocr` and their blocks diffed:

| Book | Changed blocks |
| --- | --- |
| gpo-warren-1964 | 33 `<pre>` items become prose on 33 pages: 21 join the paragraph above, 8 open a paragraph that runs on, 3 stand alone (inherited-OCR fragments) and 1 wraps a list item. No new item. |
| noaa-nca5-2023 | 381 `<pre>` items removed, 151 added: 262 reference continuation lines rejoin their numbered reference (`36. Zhou, S., … and` + `P. Gentine, 2021: …`), 101 join a paragraph, and 18 stand as paragraphs or items of their own. Every added item extends one removed line, so no prose became an item. |

## Verification

- `swift test`: 751 pass (12 in `NumberLedParagraphTests`).
- `scripts/check-all.sh --fast`: exit 0, including the generated doc counts and byte-identical repeat
  conversions.
- Corpus lanes above, and `tools/check_corpus_content.py` on each candidate evaluation.

## Remaining defects

1. **Single-line entries that open with an initial stay list items** where nothing runs on: the 9/11
   report's illustration credits (`p. 15`, page 9) and staff names (`T. Graham Giusti`, `J. Cofer
   Black`), FAA page 5's `M. van Leeuwen (www.zap16.com)…` and Replay Clocks page 10's `D. L. Mills.
   Network time protocol (ntp)…`. Expected: paragraphs or entries of their lists.
2. **Loper Bright page 64's `U. S. 134 (1944), the Court returned…`** opens a page, closes its
   sentence and runs on to nothing, so it keeps its list representation and does not join page 63.
3. **The Pro Se 1 form's `V. Certification and Closing` and `B. For Attorneys`** are still `<pre>`
   list items rather than headings (#152); they are single lines that neither continue nor run on.
4. **NASA paper folios** (#154 item 2) are unchanged: furniture removal keeps them, so page 1's
   12-point `1` is still a heading (it is heading-size against the page's 9-point abstract body) and
   pages 2, 5 and 8 still append their folio to the last paragraph.
5. **NASA paper references still split after their first line** (#154 item 3): the entries are set
   ragged with a hanging indent, and the wrapped line is a separate `P` group that the tagged-wrap
   rule does not join. `ACKNOWLEDGEMENTS` and `REFERENCES`, set in small capitals (a 12-point
   initial before 9.6-point letters), remain bold paragraphs rather than headings.
6. **FAA page 18's paragraph does not continue into the next column** (`…from St.` / `Petersburg
   across the waterway`): the column-join rule sees an abbreviation's period as a closed sentence.
7. **NOAA reference wrapped lines that stand flush with their marker** (not in the hanging indent)
   become paragraphs of their own rather than joining their entry.
