# A bullet smaller than its item, and a line PDFKit split at its own word space (#180 items 1 and 3)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, Xcode 27, release CLIs,
shared host with other agents' work. Baseline `9ae452a` (the coordination branch's head, which
carries #162's academic titles and #148's split rows); candidate is this tree on it.

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline | `9ae452a` | `8dc8b1852a718dffbb1e386d61421e7958ef0b8d83aafb7ddd83bf170f223aa7` |
| candidate | this tree on `9ae452a` | `6491faf7d67a3ca52e1f309faf79ceab5e0883fd1cf9e0bea97b74d421497e16` |
| probe | `tools/probe-raster-environment.swift` | `21e5af2678db59077efbfd3dfb49996d3236214b33e108a2141938810e239965` |

No source PDF or EPUB is committed; every EPUB was deleted after its page diff. One fixture,
`dasc-6`, was captured with `tools/capture-layout-fixture.swift` built from the **baseline**
tree, so it records the sizes extraction gave before this change; no other fixture was
recaptured.

## What was wrong

**1. An itemize bullet drawn smaller than its item hid the item's type.** `TextLine.fontSize` is
the size of the line's *first* run, and TeX draws `\labelitemi` from a 7-point font over the
IEEEtran paper's 9.96-point text. So `• Controllability: By leaving node k at time Tk, flight f`
(page 5, x 58.93–298.95) reports 6.97 points, and `continuesListItem`'s size test
(`line.fontSize <= item.marker.fontSize + 0.5`) refuses the 9.96-point line that wraps under it.
Every such entry kept only its first line, and the rest opened paragraphs of its own. The Supreme
Court sets the same shape with Symbol bullets (pages 86 and 87: 7.98-point glyphs over 10.98-point
text), with the same result.

**2. A justified line PDFKit split at its own word space opened two paragraphs.** References [1]
and [7] on page 10 keep a detached piece (`CVXOPT: A` at x 518.03, `NASA` at x 544.21). #148's
prose-row tier cannot read either junction: they are 12.51 and 10.27 points wide — 1.57 and 1.29
ems of the 7.97-point bibliography, where that tier admits half a type size — and a reference's
fields all end in a period, so `endsSentence` refuses them too. The row is a full line of the
justified measure both ways (`isProseRow(fillingItsMeasure:)` already passes on both), so the
tier's *other* conditions were never the obstacle. **Its tiers cannot cover these.**

What can read them is the space itself. PDFKit keeps it in the left piece's own string —
`"[1] M. S. Andersen, J. Dahl, and L. Vandenberghe. "`, `"development: Sprint 2 toward technical
capability level 4. "` — which extraction then trims away. A piece PDFKit ended at a line break
carries no such space: over the whole English corpus the two never coincide on an unsplit line
end. That is the evidence this change keeps.

## Change

`NativeTextReader.swift`, `LayoutReconstructor.swift` and `DocumentModel.swift`.

- **`NativeTextReader.bulletItemBodySize`**, a third branch of `textLine` beside `dropCapBodySize`
  and `displayNumeralTitleSize`. A first run of nothing but bullets and whitespace (the marker; the
  same reading `isBulletRun` already takes for scripts) before a larger, non-blank run, with
  substantial text after the marker — three words of two or more letters and fifteen letters in
  all — gives the line the size of that first text run, not of the whole rest: an item's text
  carries scripts as any other prose line does (page 5's entries hold `Tk` and `Tk−1`). The letter
  and word floor admits a short label opening a list (`• Units of measurement:`, 18 letters in
  three words) and refuses the glyph pairs a scan's text layer reads as `✓ 5 1/J.tJ RtJ.tJ`.
  A bullet drawn *larger* than its text is left alone: it overstates the line rather than hiding
  it, which is a different defect (see below).
- **`TextLine.trailingSpace`**, set in `textLine` from the extraction's own string before it is
  trimmed, and carried through the page's `Codable` workspace encoding so it survives extraction
  being held outside memory. It records only that PDFKit reported a word space at the line's end.
- **`joinedRows.stretchedWordSpace`**, a third tier of the row reading. A junction joins when the
  left piece carries that trailing space, the gap is at most two type sizes, both pieces stand in
  the page's ordinary line of their type (`ordinaryLineHeight` ±15%), the left piece ends on no
  edge the page's own text shares, the right piece begins on none, and the right piece reaches an
  edge at least three other lines reach. A column's line ends on its column's measure and a cell on
  its table's, so a two-column row and a table row are not one of these; Wallace page 189's
  `Positiveexponentmeansstandardnotation`, set beside its worked example in 21.8-point rows over an
  11.98-point page, is refused by the ordinary-line test. `candidate` admits such a pair (the
  1.5-size cap and the mathematics test do not apply to it) and `runsOn` accepts the junction
  whatever the punctuation, since the break is the line's own word space. Everything else stands:
  the row must still read as prose filling its measure, and nothing of the page may stand in the
  junction.
- **`continuesListItem` refuses a line that opens a nested item.** Once page 6's bullets read at
  their own size, `– Only four types of aircraft can appear in the problem` — the first line of a
  dash item nested under `• Parameters affecting air traffic:` — stands 1.76 bodies in, inside the
  width `continuesListItem` allows a marker, and wrapped into the bullet, while the item's own
  wrapped lines stand at 2.86 bodies and did not. `isList` reads a minus and a hyphen as markers
  but not a dash, and this paper's dash items are paragraphs the contract already pins, so the
  evidence is the page itself: `opensRepeatedDashItem` asks for another line on the same edge, in
  the same type, opening with the same dash and a space. It can only keep blocks apart.

Shared functions the hunks touch: `NativeTextReader.textLine` (extraction's line constructor, also
used by `capture-layout-fixture` and by `SplitRowsAndLostHyphensTests.nativePage`);
`LayoutReconstructor.joinedRows` / `joiningRowPieces` (#95, #109, #148) through the new
`sharedEdge` and `stretchedWordSpace` closures and one added clause in `candidate` and `runsOn`;
`LayoutReconstructor.blocks`'s `continuesListItem` (#50, #64, #115, #146); and `TextLine`'s stored
properties and `Codable` keys. No public API or default changed.

## Survey: every line whose size changes, and every row the new tier could join

Two survey-only tools, not in the library: `tools/survey-marker-sizes.swift` writes every PDFKit
line with more than one run (size of the first run, of the text after it, and the text);
`tools/survey-row-spaces.swift` writes every line's rectangle, size and whether the extraction
reported a word space at its end. Both were run over every English corpus document, including
Warren and NOAA, which are outside the lane. `survey/counts.tsv` holds the per-book counts,
`survey/bullet-lines.tsv` every line whose first run is a bullet, and
`survey/split-row-candidates.tsv` every row pair the geometric part of the new tier admits.

| Book | Lines | With a smaller first run | Bullet first run | **Line size changes** | Lines with a trailing space | Word-space candidates |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| ntrs-20190030725-dasc-2019 | 1,181 | 117 | 12 | **12** | 20 | 3 |
| scotus-loper-bright-2024 | 4,389 | 29 | 5 | **5** | 39 | 1 |
| gpo-warren-1964 (outside the lane) | 48,023 | 21,718 | 10 | **4** | 0 | 0 |
| arxiv-replay-clocks-2023 | 1,008 | 178 | 3 | **3** | 52 | 6 |
| cia-blue-book-14-1955 | 31,831 | 9,758 | 61 | **2** | 770 | 4 |
| faa-phak-8083-25c | 32,250 | 512 | 32 | 0 | 56 | 3 |
| fed-explained-2021 | 4,399 | 8 | 21 | 0 | 154 | 0 |
| wallace-algebra-2010 | 27,789 | 1,168 | 0 | 0 | 2,210 | 21 |
| gpo-911-2004 | 25,984 | 4 | 0 | 0 | 308 | 4 |
| noaa-nca5-2023 (outside the lane) | 77,882 | 58 | 0 | 0 | 9,775 | 1 |
| gpo-our-flag-2003 | 1,530 | 4 | 0 | 0 | 7 | 3 |
| ntrs-20200002975-gwl-2020 | 895 | 0 | 5 | 0 | 0 | 0 |
| census, CDC, USDA, NBS, USGS, DGA, the pro-se complaint, the slides, TechPort | 6,706 | 310 | 0 | 0 | 117 | 2 |

**26 lines in the corpus change size**, and no line changes by more than a third. The marker's own
size is never the line's again on those 26, and no other line's size moves. The 21,718 lines with a
smaller first run that the rule does not touch are almost all mathematics and raised note markers
(a piece PDFKit measured from a subscript, an OCR'd scan's debris); the bullet test is what keeps
them out.

### The 26 by class, each read against its rendered source page

- **IEEEtran paper, 12** (pages 5, 6, 10). All four page-5 entries, all five page-6 entries and the
  three inside page 10's Table III. Correct: the render shows one bulleted list at the body size.
- **Supreme Court, 5** (pages 86, 87). Kagan's five Chevron examples, Symbol bullets over 10.98-point
  text. Correct.
- **Replay Clocks, 3** (page 2). `•If 𝑒 and 𝑓 happened on the same process…` and two siblings, where
  the bullet is 8.97 and the text 9.04–9.06: a tenth of a point, the same glyph size drawn from a
  different face. Correct, and too small to change any size test.
- **Blue Book, 2** (pages 1, 22). `• Authorizati6n Ac-e' for Fiscal Year 2024` and `• identification
  as a common object or some` — a bullet the OCR read over a scan's own text. Both are genuine
  bulleted lines on the render; the correction is right and changes nothing downstream.
- **Warren, 4** (pages 148, 322, 546, 628, outside the lane). The same: the OCR layer's bullet over
  scanned prose. The book's EPUB is byte-identical either way.

Of the 26, **seven change the output**: the four page-5 entries of the paper and three of the
Supreme Court's five (the other two already kept their wrapped lines, for want of a size test on
their particular geometry). Page 6's five are held apart by the nested-dash rule, page 10's three
stand inside a preserved table image, and the remaining eleven leave their pages unchanged.

### The row tier: 48 candidates, 8 joins

The geometric part of the new tier admits 48 row pairs across the corpus. `isProseRow(filling
ItsMeasure:)`, the junction-clear test, the `aligned` test and the body-size filter reject 40 of
them — 20 of Wallace's table cells and derivation rows, 9/11's four (three of them rows #148's own
tier already joins, and the contents line `. . . and in the White House` beside its folio `98`),
Our Flag's three dot-leader table rows, three of the Blue Book's OCR lines, three of Replay Clocks'
formula rows, and the rest. **Eight join**, each read against its render:

| Book | Page | Join |
| --- | --- | --- |
| ntrs-20190030725-dasc-2019 | 10 | `… L. Vandenberghe. CVXOPT: A python package…` and `… level 4. NASA Technical Memorandum, 2018.` — references [1] and [7] whole |
| arxiv-replay-clocks-2023 | 4 | `Receive event. Next, we describe how RepCl is updated when…` — a bold run-in lead-in and its sentence |
| arxiv-replay-clocks-2023 | 6 | `Observation 1: Shift and MergeSameEpoch can be implemented using…` and Observation 2's, both whole |
| cia-blue-book-14-1955 | 109 | `Table Al06. Evaluation of All Sightings for All Years by Duration of Sighting for Months`, as its twenty-six siblings on that index page already read |
| wallace-algebra-2010 | 38 | `It doesn’t matter which term gets moved, 4x or 2x, however, it would be the author’s suggestion…` — one justified line of one paragraph |
| faa-phak-8083-25c | 510 | `VYSE. Best rate-of-climb speed with one engine inoperative.`, as the `VY.` entry above it already read |

All eight are correct. On page 6 of Replay Clocks the observation's own sentence is now whole
instead of split in two, but it stays attached to the paragraph above it: that merge is a
paragraph-boundary defect of its own and is unchanged either way.

## Contracts

`corpus/regressions.json` gains 15 checks on six cases — three new pages (Blue Book 109, Wallace 38,
FAA 510) and six pages already in the contract (531 → 534 pages). The basis of each case is extended.

- **Reproducers (14).** The paper's four page-5 list items and its two page-10 references; the
  Supreme Court's three items on pages 86 and 87; Replay Clocks' two run-in lead-ins; the Blue
  Book's index entry; Wallace page 38's paragraph; the FAA's `VYSE.` entry.
- **Control (1).** The paper's page 6: `– Only four types of aircraft can appear in the problem
  instance: [s]mall, [m]edium, [L]arge, [H]eavy.` must stay a paragraph of its own. It is the
  nested-dash rule's contract; with that rule stubbed out the bullet above it swallows the line.
  Page 6's existing checks (`– The route network for each problem is a tree weighted by…`,
  `– Each flight’s ETA at first node is chosen…`) are the same control and caught the over-reach
  before it was fixed.

Negative control, by running `tools/check_corpus_content.py` against the retained **baseline**
evaluations: the baseline fails exactly the 14 reproducers (paper 6, Supreme Court 3, Replay Clocks
2, Blue Book 1, Wallace 1, FAA 1), passes the control and every other check of all 21 cases. The
candidate passes all 21 with no errors (`lane-summaries/contract-results.json`).

## Tests

`Tests/PDFReflowLibTests/BulletItemSizeAndSplitReferencesTests.swift`, 5 tests.

1. `sourceItemizeBulletsKeepTheirWrappedLines` (`dasc-5`): the fixture records the line at the
   bullet's 6.97 points — the defect — extraction reads 9.96, and all four entries hold the lines
   that wrap under them; controls: no wrapped line stands alone and the paragraph above the list is
   untouched.
2. `sourceNestedDashItemsStayApartFromTheirBullet` (`dasc-6`): the three bullet labels are their own
   items and the dash items beneath them stay paragraphs.
3. `bulletItemSizeNeedsAMarkerBeforeSubstantialText`: the rule and nine controls — a larger bullet,
   an equal-size bullet, four first runs that are no marker (a letter, a digit, a raised note
   number, a dash), a short label that *does* qualify, two words and three short ones that do not,
   the Blue Book's three scan-mark pairs, a marker with nothing after it, and a monospaced line.
4. `sourceSplitReferenceRowsRejoinAtTheirWordSpace` (`dasc-10`): the trailing space is on the left
   piece and not the right, the junction is over 1.5 ems, references [1] and [7] are whole, no
   detached piece is left, and the entries PDFKit did not split are unchanged.
5. `stretchedWordSpaceRowsNeedTheSpaceTheMeasureAndAnOrdinaryLine`: a synthetic justified column
   joins, and six controls stay apart — no reported space, a row short of the measure, only two
   lines on that measure, a row taller than the page's ordinary line, a junction over two type
   sizes, a right-aligned label column, and a two-column page's row.

Updated test: `AcademicSectionTitleTests.sourceHangingEntriesKeepTheirWrappedLines`, whose
reference [7] now ends `… level 4. NASA Technical Memorandum, 2018.` (#162 recorded the detached
`NASA` as a leftover).

`SourceLayoutFixture.styledContent` replays from each line's own runs what `textLine` reads there
and the fixtures do not record — the bullet-item size and the word space PDFKit kept at the line's
end — so a fixture captured before either rule still shows the defect when the rule is stubbed out.

Negative mutations (`tools/mutate.py`, `negative-mutations.txt`), run over the new suite and the
split-row, row-piece, academic-title and list suites. All ten are caught, including the four that
only widen a rule (a bullet of any size, a marker before any text, a junction of any width, a row
that need not reach its measure).

## Verification

- `swift test`: 826 pass (821 on `9ae452a` plus 5).
- `python3 -m unittest discover -s tools -p 'test_*.py'`: 239 pass.
- `scripts/check-all.sh --fast`: exit 0.
- Corpus lane on both binaries, `tools/run_corpus_regressions.py` one case per call with the
  compiled probe and `--execution-context host-terminal`, then `tools/compare_conversion_runs.py
  --allow-different-converters --detail` (`lane-summaries/compare-<case>.json`). All 21 gated cases
  were run on both lanes:

  | Case | Baseline | Candidate | Changed pages |
  | --- | --- | --- | --- |
  | ntrs-20190030725-dasc-2019 | fails the 6 new checks | pass | 5, 10 |
  | scotus-loper-bright-2024 | fails the 3 new checks | pass | 86, 87 |
  | arxiv-replay-clocks-2023 | fails the 2 new checks | pass | 4, 6 |
  | cia-blue-book-14-1955 | fails the new check | pass | 109 |
  | wallace-algebra-2010 | fails the new check | pass | 38 |
  | faa-phak-8083-25c | fails the new check | pass | 510 |
  | gpo-911-2004, fed-explained-2021, dga-2025-2030, usda-ars-agresearch-2012-11, ntrs-20180003024-earthdata-slides-2018, gpo-our-flag-2003, census-rrs2002-01, nbs-jres-geltman-1977, cdc-zombie-pandemic-2011, usgs-mcs2025-copper, uscourts-pro-se-1-2016, ntrs-20200002975-gwl-2020, ntrs-20210020887-techport-thm-2021, uscis-m618-arabic-2015, irs-p596-zhs-2025 | pass | pass | none |

  - Every run passes EPUBCheck and the structural, progress and memory gates.
  - No image changed, no page marker moved, no report field changed, no navigation entry changed
    and no provenance error was raised, on any case. No page is an OCR page in both runs on any
    changed page (`changedOCRPages` is empty everywhere).
- Warren and NOAA are outside the lane (#5). Both were converted directly with both binaries
  (`--maximum-output-bytes unlimited --no-ocr`, pinned identifier and date): each book's two EPUBs
  are byte-identical (Warren `0fbc7797…`, NOAA `20180188…`). The EPUBs were deleted afterwards.
- Page markup for every changed page is in `pagediff-<case>.txt`; each was read against a 100–110
  DPI Poppler render of its source page.

## Defects to file

1. **A bullet drawn *larger* than its item overstates the line.** The Fed's page-58 list sets a
   10-point bullet over 8-point text (14 lines on pages 58 and 59), and 35 of the Blue Book's OCR
   bullets do the same. Nothing in the corpus depends on it today — a larger marker passes
   `continuesListItem`'s size test, which is an upper bound — but the line still reads as type it
   is not, which heading ranking and the body-size statistics both see. It is the mirror of this
   issue's item 1 and wants its own survey.
2. **The IEEEtran paper's page 6 sets a nested dash list that reads as paragraphs.** The dash items
   under each bullet are the bullet's own sub-items; they are separate paragraphs, not a nested
   list, because `isList` reads no dash as a marker and the contract pins them as paragraphs. The
   nested-dash rule added here only keeps them out of the bullet above.
3. **Replay Clocks pages 4 and 6 attach a run-in lead-in to the paragraph before it.** `Observation
   1:` and `Observation 2:` open their own paragraphs in the source; the text now joins them
   correctly, but the whole thing still hangs off the preceding paragraph.
4. **9/11 pages 254, 259 and 438 still show `arrived.Hawsawi`, `attack.At` and `agencies,to`.**
   Unchanged by this work; #148 recorded them as #119/#128's missing word spaces.
5. **The paper's page-10 appendix bullets are inside a preserved image.** Table III is a crop, so
   its three corrected bullet lines are not in the reflowed text at all.
