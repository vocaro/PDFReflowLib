# Table of Names rows PDFKit merges, and a word broken without a hyphen (#199)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, release CLIs, EPUBCheck from
`/opt/homebrew/bin/epubcheck`. Baseline `07c1bbd` (the coordination branch's head); candidate this tree
on it.

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline | `07c1bbd` | `0c6ec51d0a947918258161b26096ea5846950b36872ffac5e816750318262c10` |
| candidate | this tree on `07c1bbd` | `456ebf351a0b96c60b8b005bfa03e2c56035f85c5da296cba8de236758fd27aa` |

No source PDF or EPUB is committed; each lane's EPUBs were deleted once its page diff was written.
Fixtures `911-449` and `911-453` were captured with this tree's `tools/capture-layout-fixture.swift`;
`911-451` was recaptured with it, which changes only the Reno row (now two lines).

## State on the baseline

1. Page 449 read `John Ashcroft Attorney General, 2001– Monte Belger` and page 451 `Janet Reno Attorney
   General, 1993–2001 Condoleezza Rice` as one paragraph each; page 454's `Khallad see Tawfiq bin
   Attash` stayed one paragraph too, contrary to #161's record, which had it standing apart.
2. Page 453 read `(a.k.a. Abu Zubaydah) Palestinian; al Qaeda asso ciate; currently in U.S. custody`.
3. `J. Cofer Black` on page 449 is a preformatted list line (#194's territory; not changed here).

## Evidence

**Merged rows.** The Table of Names sets names at x 44.7 (39.7 verso) and descriptions on the same
baseline at 152.7 (147.7). The page draws each row as one text show (`Zakariya Essabar Moroccan;
Hamburg cell associate ` on page 453, read with `NativeSpacingReader`), and PDFKit still returns most
rows as two lines, but a few as one: `John Ashcroft Attorney General, 2001–` (44.7–253.6, page 449),
`Janet Reno Attorney General, 1993–2001` (44.7–273.7, page 451), `Khallad see Tawfiq bin Attash`
(page 454). Their gaps are 5.2, 6.1 and 7.6 ems; the width of the name does not predict which rows
PDFKit merges (Colin Powell's row, gap 5.4 ems, is read apart). Layout then reads a name line with
no partner, and the next name joins it.

**The lost hyphen.** Page 453's show is `ydah) Palestinian; al Qaeda asso ` and the next line's
`Mohamed Hussein ciate; curr`: the page draws no hyphen at all, and a 150-DPI Poppler render shows
none. The issue's premise (a hyphen lost at extraction) does not hold; the source breaks the word
without printing one. The description column is ragged, so #157's justified-measure test has nothing
to measure. The same page prints `Hamburg cell associate`; the system English lexicon
(`NLEmbedding`) holds `associate` and neither `asso` nor `ciate`.

## Rules

**`NativeTextReader.rowEdges`, `splitAtRowEdges`** (extraction, native pages only: the pipeline passes
`borderlessTableInk` only there). Each line is paired with the nearest line before it on its baseline
(1.5 points), in its size (5%); pairs two ems or more apart whose two left edges agree within a point
on at least four rows are a row edge. A line starting on an edge's left edge and crossing its second is
cut at the second edge (`cut`: glyphs two ems apart, pieces spelling the line) when the right piece
begins on the edge within a point and is not a page number (`isFolio`, moved here from
`LayoutReconstructor`, which now calls it). An edge is used only when fewer lines cross it than rows
PDFKit read apart.

Two guards came from the lanes, each read against the candidate's output:

- *Nearest partner, both edges.* A first version paired a line with any line two ems before it and
  checked only the second edge. On 9/11 page 51 the right-hand flight timeline's events stand beside
  the left timeline's lines, so its event edge (245.7) qualified and every merged `8:42 Takeoff` row was
  cut; layout then read the two timelines row by row, interleaved. With the nearest partner and its
  edge, only two rows qualify there (`9:36`, `10:03:11`) and the page is unchanged.
- *Page numbers, and native pages.* The next version cut the CIA report's contents entries (`for Each
  Segregation 26`, pages 5, 108, 110; invisible text over scans) and NOAA's (`Future Land-Use Options
  6-17`, pages 9–18), which moved folios away from their entries and, on NOAA, turned the contents
  pages' remaining text into crops. A folio is no second column, and a synthetic-text page is not cut.

**`LayoutReconstructor.unprintedLineEndHyphen`** (paragraph joins, native pages). A line ending in a
lowercase run of letters and a line opening with one, in the same size (10%), close up with no space
when the document is declared English, neither half is a lexicon word, the joined word is, and the
book prints it; #186's lengths (two letters a side, six in all).

## Contracts (`corpus/regressions.json`, gpo-911-2004)

- Page 449 (new): ordered `John Ashcroft`, `Attorney General, 2001–`, `Monte Belger`, `Acting Deputy
  Administrator, Federal Aviation`; distinct Ashcroft/office, office/Belger, and (control)
  Albright/her office.
- Page 451: distinct Reno/office, office/Rice and (control) Powell/his office.
- Page 453 (new): paragraphs `(a.k.a. Abu Zubaydah) Palestinian; al Qaeda associate; currently in U.S.
  custody` and (control) `Moroccan; Hamburg cell associate`; absent `asso ciate`.
- Page 454: distinct `Khallad`/`see Tawfiq bin Attash`.

The baseline fails 7 of the 14 new checks (the rest are controls or order it already held); the
candidate passes the case.

## Tests (`Tests/PDFReflowLibTests/TableOfNamesRowsTests.swift`)

| Test | Reproducer / control |
| --- | --- |
| `aRowPDFKitMergesWhereItReadsTheOthersApartIsCutAtTheirEdge` | Synthetic PDF: ten rows read apart, one merged by a TJ adjustment, cut at 153; without native ink it stays whole; three rows, a folio (`Janet Reno 433`) and five merged rows beside four read apart stay whole. |
| `aProseLineCrossingARowEdgeKeepsItsWordSpaces` | Prose across the edge stays one line. |
| `rowEdgesPairEachLineWithTheNearestLineBeforeIt` | Table of Names edge found; page 51's two timelines, lines a word space apart and another size give none. |
| `source911TableOfNamesRowsPDFKitMergedReadAsNameAndDescription` | `911-449`, `911-451`: Ashcroft and Reno beside their offices. |
| `aWordBrokenWithoutAPrintedHyphenClosesOnTheBooksWordAndTheLexicon` | `asso`/`ciate` closes; no English key, an unprinted joined word, `real`/`ity`, `on`/`going`, another size, a capital and a comma keep the space; `911-453` joins only with the lexicon key. |

## Corpus lanes

`run_corpus_regressions.py` one case per call for each side, and a block-per-line page diff of the two
EPUBs (`pagediff-gpo-911-2004.txt`). 71–81 GB free throughout.

| Case | Baseline | Candidate | Changed pages |
| --- | --- | --- | --- |
| gpo-911-2004 | pass (fails the 7 new checks) | pass | 9, 449, 451, 453, 454 |
| noaa-nca5-2023 | pass | pass | 594 (`fac tors` → `factors`) |
| cia-blue-book-14-1955 | pass | pass | none |
| the other 17 cases | pass | pass | none |

`gpo-warren-1964` is not covered by the lane (#5). The final binary's lanes were rerun for all 20
cases (all pass). The page diffs for the 17 other cases were taken with the earlier candidate (before
the native and folio guards, which only narrow the cut; the layout rule is unchanged since); the 9/11,
CIA and NOAA diffs were retaken with the final rules.

**Page 9** (list of illustrations): `p. 49 Usama Bin Ladin`, `p. 64 Map of Afghanistan` and `p. 148
Khalid Sheikh Mohammed` were three of the four rows PDFKit merged; they now read as the page's other
rows do, the reference and the caption apart. `p. 238–239 The 9/11 hijackers` is not cut and stays one
line. No image changed on any page.

## Remaining

- Page 448's abbreviation list (`NTSB National Transportation Safety Board NSA …`) still runs its
  entries together: PDFKit merges most of its rows, so no edge qualifies.
- `J. Cofer Black` on page 449 is still a preformatted list line (#194).
