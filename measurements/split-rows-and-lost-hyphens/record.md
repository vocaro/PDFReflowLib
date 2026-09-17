# Rows PDFKit splits outside mathematics, paragraphs a box cuts, and hyphens the extraction loses (#148, #157 item 1)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64 release CLIs, shared host
with other agents' conversions running. Work began on `b1c7043` and stayed there. Baseline is a
release CLI built from `b1c7043` (SHA-256 `e88e561b…`); candidate is `b1c7043` plus this working
tree (`73f3be69…`). One raster/Vision probe binary (`.build/raster-environment/probe`) served both
lanes. No public API or default changed.

## What was wrong

#131 left six kinds of word break and one kind of spaced hyphen in the corpus.

1. **A prose row PDFKit split opened two paragraphs.** `joinedRows` (#95) rejoined only rows
   carrying mathematics, so a prose row split at a raised note marker (9/11 page 220's
   `that al-Qida was responsible” for the Cole.` beside the 7.175-point
   `178 In March 2001, the CIA’s brief=`) or at a stretched word space of a justified line
   (page 438's `…to conduct oversight of` and `the intel-`, 4.2 points apart) became two
   paragraphs. Each cut a sentence, and the second stranded a word break at the row's end.
2. **A paragraph a tinted box cut kept its broken half.** The Fed sets a sidebar into its measure
   and its title and text are read between the two halves of one word, so `joinWordBreaks`, which
   joins adjacent blocks, never saw them (pages 22, 28, 56, 57 and 80: `…banking insti-`, the box,
   then `tutions. Stress tests are required…`).
3. **A cross-page word break was refused where the anchor line is mostly citations.** Loper Bright
   page 11 ends `§§1854(d)(2)(B), 1862(b)(2)(E). And in general, it author-` over page 12's
   `izes the Secretary…`; letters are under half that line's ink, so `readsAsProse` declined it.
4. **A compound the source set with a space after its hyphen.** No line ends there, so no line-end
   rule applies: the Fed's `check- collection` (95, 96) and `community- oriented` (118), the FAA's
   `low- wing` (364), `self- imposed` (447) and `Service- Broadcast` (12, 333).
5. **A hyphen set where the book's neighbours set an em dash.** FAA page 73's
   `Commuter Category Airplanes- 14 CFR part 23` stands among `Transport Category
   Airplanes—14 CFR part 25` and `Normal Category—14 CFR part 27`.
6. **A line-end hyphen the extraction lost** (#157). PDFKit drops the hyphen glyph from some of
   Our Flag's justified lines, and the line's rectangle loses the glyph's advance with it, so the
   break reads as a word space: `bom barded` (5), `fab rics` (27), `sym bolize` (46), `mean ing`
   (47), `alter nately` (9), `PEO PLE` (52) and seven more.

## What changed

`Sources/PDFReflowLib/LayoutReconstructor.swift` and `PDFReflowLibPipeline.swift`.

- **`joinedRows`: a second tier for a row outside mathematics.** Every joined row must still read
  as prose on its paragraph's measure; outside mathematics it must be a *full* line of it
  (`isProseRow(fillingItsMeasure:)`: at least three prose lines share both of its edges), because a
  short row that merely sits on a paragraph's edge is something set beside it (FAA page 367's
  heading `ATC Instructions—` and `“Hold Short”` over the body). Its text must also run on across
  each junction: no junction wider than half the type size — narrower than any gutter, and than the
  word spaces PDFKit itself keeps — and at each one the left piece leaves its sentence open or the
  right piece opens with a raised note marker. A marker closes the line it was raised over with no
  space, as a marker PDFKit detaches past a line's end already does; every other junction is a word
  space.
- **`typeSize`.** PDFKit measures a line from its first run, so a piece that opens with a raised
  note marker carries the marker's size (page 220's 7.175 points). A piece of that shape whose
  rectangle is the page's ordinary line at the body size is read as body type.
- **Nothing in a junction.** Where this reading admits a row #95's did not — outside mathematics,
  or through `typeSize` — no piece of the page may stand in one of the row's junctions. NOAA page
  145 sets `…–1.3 ± 0.7 W/m2`, `.` and the raised `2 Since NCA4, the` as three pieces, and joining
  the outer two would carry the period past the end of the line. A row of mathematics #95 already
  read joins as it always has, since a radical's pieces routinely overlap the terms beside them.
- **`joinWordBreaks` reaches past a box.** Where the next block is not the continuation, the first
  later block on the page that is, and whose first line is the next line of the anchor's own column
  (`nextLineInColumn`: directly beneath it, on its edge, in its type, with no line between), joins
  instead. The hyphen policy still decides, and the blocks still stay apart where it would warn
  `uncertainHyphen`. The box keeps its place and follows the joined paragraph, as a figure between
  a column's foot and the next column's head does.
- **`continuesWordBreak`,** used by `continuation`: a line-end hyphen after two letters, a lowercase
  continuation, and a hyphen policy that decides the break without warning. That is the evidence
  `joinWordBreaks` already requires of two blocks, and it is the same evidence wherever the halves
  ended up, so it stands in place of `readsAsProse` on a cross-page anchor line.
- **`closeSpacedCompounds`,** a pass-2 page rewrite beside `joinDropCapInitials`. A mid-line
  `x- y` whose left half opens its word (nothing but whitespace, a bracket or a quote before it)
  closes up when the book prints the compound as one word (`check-collection` 7 times,
  `low-wing` 6, `self-imposed` 6). Both halves are letters there, so word splitting — which reads
  letters and hyphens alone — can never record a number, and a suspended hyphen keeps its space
  because no book prints `low-and` or `consumer-and`. Failing that, the book's own em dash between
  the same two tokens replaces the hyphen and its space, but only before a digit or a capital,
  since a suspended hyphen always carries on in lower case.
- **`addDashVocabulary`.** Every `word—word` the book sets tight around an em dash, under a key no
  word can hold.
- **`justifiedMeasures`, `endsShortOfMeasure`, `lostLineEndHyphen`** (#157). A size's measure is the
  line end most of its lines share — the commonest, not the furthest, since a line ending in the
  book's own hyphen overhangs it (the 9/11 report's `=` is two-thirds of an em, half again what its
  longest line otherwise reaches) and a measure taken from such a line would read every ordinary
  line as short. At least three lines and a quarter of the size's lines must share the edge. A line
  that ends in a letter between a fifth and a half of its type size inside that measure lost a
  hyphen: that is where a hyphen's advance falls (0.33 em in Our Flag's Times) and no character
  else does. The book's words then decide as they decide a hyphen the source did print — only a
  break the policy resolves to `removeHyphen` closes up. A recognized or synthetic page has no such
  measure: a Vision quadrilateral is the ink it read, which says nothing about a dropped glyph's
  advance.
- **Vocabulary.** `addVocabulary` carries the previous page's last line, so the word a page break
  cut in half is skipped as a word a line break cut in half is (#101). A page's head matter — a
  running head, an opinion line, a folio — stands outside the text stream, so the lines before the
  page's first body-sized line leave the carried line standing (page 12 sets two head lines over
  `izes the Secretary…`). The carried line is given the hyphen its page printed where
  `endsShortOfMeasure` says one was lost, so the fragment after a lost hyphen is skipped too.

Without that vocabulary change neither Loper Bright's `author-` + `izes` nor Our Flag's `alter` +
`nately` joins: `izes` and `nately` would be book words, which stops `inflectionVouches` (#115),
and neither `authorizes` nor `alternately` is printed anywhere in its book.

## Survey: every changed join and space

`tools/join-log.py` is survey-only instrumentation. It is not in the library. It adds five stderr
logs guarded by `PDFREFLOW_ROW_LOG`, and `--revert` takes them out again. The instrumented
candidate converted every English corpus document, and `survey/<file>.tsv.gz` holds the logs.

| Document | Prose rows | Box-cut joins | Cross-page breaks | Lost hyphens | Spaced compounds | Pages with changed text | Pages with changed blocks |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| gpo-911-2004 | 5 | 0 | 0 | 0 | 0 | 2 | 6 |
| fed-explained-2021 | 0 | 5 | 0 | 0 | 3 | 8 | 8 |
| gpo-our-flag-2003 | 0 | 0 | 0 | 13 | 0 | 11 | 11 |
| faa-phak-8083-25c | 0 | 0 | 0 | 0 | 5 | 5 | 5 |
| scotus-loper-bright-2024 | 0 | 0 | 1 | 0 | 0 | 1 | 2 |
| wallace-algebra-2010 | 2 | 0 | 0 | 0 | 0 | 1 | 2 |
| usda-ars-agresearch-2012-11 | 0 | 31 | 0 | 0 | 0 | 9 | 9 |
| arxiv-replay-clocks-2023 | 2 | 0 | 0 | 0 | 0 | 0 | 2 |
| nbs-jres-geltman-1977 | 1 | 0 | 0 | 0 | 0 | 0 | 1 |
| ntrs-20190030725-dasc-2019 | 1 | 0 | 0 | 0 | 0 | 0 | 1 |
| gpo-warren-1964 (outside the gate, OCR) | 56 | 0 | 0 | 0 | 1 | 1 | 55 |
| noaa-nca5-2023 (outside the gate) | 7 | 5 | 0 | 0 | 1 | 11 | 12 |
| census, dga, cdc, blue book, usgs, uscourts, and the other three NTRS documents | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

Word diffs of every page, and the ordered block lists, were read for each changed page. Every
logged decision is one change, and every change is one logged decision. The lane comparisons are
kept as `compare-<case>.json.gz` (`--allow-different-converters --detail`).

### Review by class

**Prose rows (74).** All correct.
- 9/11 (5): page 145 `…Washington Times.105 This made it…`, page 220 `…for the Cole.178 In March
  2001…` (both markers closing their line), page 254 `…each had arrived.Hawsawi told`, page 259
  `…what later became the 9/11 attack.At the time…`, page 438 `…oversight of the intel-` +
  `ligence establishment`. Pages 145, 220 and 438 merge three, two and two paragraphs.
- Wallace (2), NBS (1), Replay Clocks (2), NTRS DASC (1): a superscript term or a closing period
  PDFKit split off (`…in front of x2` + `. In all`, `…109 W/cm2` + `. The electrons scattered`,
  `…or if 𝑓` + `occurred far later than`, `…step V 3` + `.`). The text is unchanged; the pieces
  stop being paragraphs of their own.
- Warren (56, OCR, outside the gate). Every one is a row Vision split at a raised note marker
  (`…in Mexico City;` + `°^^ however, a Cuban visa…`), at a wide space (`Commander Humes stated ;`
  + `"* * * we concluded that the large`) or at a witness index's dot leader (`Botelho, James
  Anthony^` + `. . . . Acquaintance of Oswald in Vol. VIII, p. 315.`). The book's text is
  unchanged on 55 of the 56 pages; only the blocks merge.
- NOAA (7, outside the gate). All raised note markers closing their line (`…climate change.7
  Related term:`, `…Act (IQA),1 the Office of Management…`).

**Box-cut joins (41).** All correct.
- Fed (5): pages 22 `institutions`, 28 `previously`, 56 `asset-backed`, 57 `institutions`,
  80 `respond`.
- NOAA (5): pages 25 `well-documented`, 25 `observations`, 85 `deforestation`, 85
  `acidification`, 411 `disproportionately`. Four of these are the fragments #131 recorded as
  having no neighbour with evidence; the column geometry now finds the right one.
- USDA Agricultural Research (31): a two-column magazine whose reading order interleaves its
  columns (a separate defect). Every join is a word rejoined to the next line of its own column
  (`Oxford, Mis-` + `sissippi`, `ARS-devel-` + `oped miticidal mixture`, `avoid-` + `ing yield
  losses`).

**Cross-page word breaks (1).** Loper Bright 11→12 `it authorizes the Secretary`. The instrumented
run logs 38 anchor lines that do not read as prose across the corpus; 37 of them end in no word
break (Warren's press-run folios `730-900 0-64—18`, the Blue Book's OCR debris) and only this one
joins.

**Lost line-end hyphens (13), all in Our Flag, all correct.** `bombarded` (5), `following` (5),
`services` (7), `alternately` (9), `historic` (11), `banner` (13), `alternating` (16),
`projecting` (22), `suspended` (22), `fabrics` (27), `symbolize` (46), `meaning` (47), `PEOPLE`
(52). Each joined word is printed elsewhere in the book, or an inflected form of it is
(`alternate` on pages 7 and 13 for `alternately`). No other book has one: nothing else in the
corpus has a justified measure with a line ending a hyphen's width inside it whose halves make a
book word.

**Spaced compounds (10), all correct.** Fed `check-collection` (95, 96) and `community-oriented`
(118); FAA `Service-Broadcast` (12, 333), `low-wing` (364), `self-imposed` (447) and the em dash
`Airplanes—14 CFR part 23` (73); NOAA `recreation-related` (1183); Warren `Chiles-Stovall` (644,
where `Jaggers- Chiles` has no evidence and keeps its space).

### What still reads `x- y`

`x- y` inside one block, over the whole corpus, is now only:
- **Suspended hyphens, correct as printed.** 9/11 `ultra-high- and`, `second- or`, `30- to`,
  `airplane- and`, `Arab- and`, `intra- and`; Fed `low- and` ×7, `consumer- and` ×3, `medium- and`
  ×2, `micro- and`; FAA `two- or`, `high- and`, `36- and` and fifteen more.
- **Our Flag page 47's `real ity`**, where the book prints neither `reality` nor any inflected
  form of it, so no evidence closes the break.

## Contracts

`corpus/regressions.json` gains 58 checks on 19 new pages (2,581 → 2,639 checks, 491 → 510 pages).
The basis of each of the five cases is extended.

- **Reproducers (52).**
  - 9/11: 145, 220, 254, 259 and 438, each naming the joined paragraph and, for 145 and 220, the
    spaced marker as absent.
  - Fed: 22, 28, 56, 57 and 80 (the joined word and the box's own text as absent between the
    halves), 95, 96 and 118 (the closed compound and its spaced form as absent).
  - Loper Bright 11: `continuedParagraphs` from `…it author` to `izes the Secretary to impose`.
  - FAA: 12, 73, 333, 364 and 447.
  - Our Flag: 5, 9, 22, 27, 46, 47 and 52.
- **Controls (6).** 9/11 111's suspended hyphen; FAA 296's `low- and high-pressure` and 367's
  `“Hold Short”` distinct from the paragraph beneath it; Fed 22's box title, which keeps its own
  heading; Our Flag 47's `real ity`, which has no evidence and must not close; Loper Bright 11's
  absent `it author- izes`.

Negative control, by running the baseline CLI through the corpus lane against the new contract:
the baseline fails exactly the 52 reproducers (9/11 7, Fed 16, Loper Bright 1, FAA 10, Our Flag 18)
and passes the 6 controls and every other check. The candidate passes all 2,639.

## Tests

`Tests/PDFReflowLibTests/SplitRowsAndLostHyphensTests.swift`, 16 tests. New fixtures `911-145`,
`loper-11`, `loper-12`, `fed-22b`, `fed-95`, `faa-73`, `faa-367` and `our-flag-page-9` were
captured on `b1c7043` with `tools/capture-layout-fixture.swift`.

1. **Source prose rows** (9/11 145, 220, 438): the marker piece's size and position, the joined
   paragraphs, and controls — no block left holding a bare marker or a broken half, and page 220's
   `Starting a Review` section still opens its own block.
2. **A short split row is no prose row** (FAA 367): `ATC Instructions—` and `“Hold Short”` meet on
   one row, and the body paragraph beneath them stays its own block.
3. **Synthetic rows**: a word space with the sentence open joins; four controls stay apart (a gap
   wider than half the type size, a sentence end without a marker, a piece of the page in the
   junction, and a row too short to be a full line of the measure).
4. **A raised marker closes its row with no space**; the same piece in body type does not.
5. **Source box-cut join** (Fed 22), with `nextLineInColumn` asserted on the two lines, and the
   box's title and text kept.
6. **Synthetic distant blocks**: the join needs the next line of the column, and stays apart when
   the continuation is in the other column, when a line of the column is between, and when the
   book does not print the word.
7. **Source cross-page word break** (Loper Bright 11→12), with the anchor line's letters counted
   under half its ink and `izes` absent from the vocabulary.
8. **`continuesWordBreak`** and its controls (no hyphen, one letter, a capital continuation, a
   break the book vouches for neither way, a compound whose halves are both words).
9. **`closingSpacedCompounds`** and its controls (no evidence, a dash before a lowercase word,
   numbers, an address, a half that is not a word), and `addDashVocabulary`.
10. **Source spaced compound** (Fed 95): the mid-line break closes, the line-end `check-` does not.
11. **Source hyphen set for a dash** (FAA 73), with its neighbours untouched.
12. **`justifiedMeasures`**: the commonest end, not the furthest; a ragged column has none.
13. **`lostLineEndHyphen`**: the hyphen-width window, the book's evidence, and five controls.
14. **Source lost hyphens** (Our Flag 5 and 9), with `real ity`'s shape as the control.
15. **A broken word at a lost hyphen is no vocabulary**, and a recognized page's words all are.
16. **A page break inside a word carries past the running head**, and a page that opens after an
    unbroken line keeps its first word.

Updated tests: `LineEndCompoundTests.wordBreaksSplitAcrossBlocksJoinThroughTheHyphenPolicy` (page
438's break is now inside one paragraph rather than between two blocks) and
`RowPiecesAndSpacedParagraphTests.syntheticSplitRadicalRowJoinsOnlyAsProse` (its plain-piece
control is now a row, and a new control keeps a piece after a sentence end apart).

Negative control (`negative-tests.log.gz`, `tools/negative-stubs.py`). Eight stubs restore the
baseline: the math-only row gate, `typeSize`, the marker's spaceless close, adjacency in
`joinWordBreaks`, `readsAsProse` alone in `continuation`, `lostLineEndHyphen`,
`closeSpacedCompounds` and the vocabulary carry. With them, 13 tests fail with 27 issues: 11 of the
16 new tests and the two updated ones. The five new tests that still pass are the unit and control
tests whose subject the stubs do not remove (`justifiedMeasures`, `closingSpacedCompounds`,
`continuesWordBreak`, the distant-block controls and FAA 367's short row).

## Verification

- `swift test`: 755 tests pass (739 on `b1c7043` plus 16).
- `scripts/check-all.sh --fast`: exit 0.
- Corpus lane on both binaries, one case per call, eleven cases (the five the issue names, plus
  Wallace and Census as the gate requires and every other book whose output changed), compared with
  `tools/compare_conversion_runs.py --allow-different-converters --detail`:

  | Case | Baseline | Candidate | Changed pages |
  | --- | --- | --- | --- |
  | gpo-911-2004 | 291 pass / 7 fail | 298 pass | 145, 220, 254, 259, 438 |
  | fed-explained-2021 | 184 / 16 | 200 pass | 22, 28, 56, 57, 80, 95, 96, 118 |
  | scotus-loper-bright-2024 | 98 / 1 | 99 pass | 11, 12 |
  | faa-phak-8083-25c | 525 / 10 | 535 pass | 12, 73, 333, 364, 447 |
  | gpo-our-flag-2003 | 105 / 18 | 123 pass | 5, 7, 9, 11, 13, 16, 22, 27, 46, 47, 52 |
  | wallace-algebra-2010 | 182 pass | 182 pass | 223, 301 |
  | census-rrs2002-01 | 73 pass | 73 pass | identical |
  | nbs-jres-geltman-1977 | 52 pass | 52 pass | 5 |
  | arxiv-replay-clocks-2023 | 68 pass | 68 pass | 2, 10 |
  | ntrs-20190030725-dasc-2019 | 173 pass | 173 pass | 8 |
  | usda-ars-agresearch-2012-11 | 118 pass | 118 pass | 6, 8, 11, 12, 13, 15, 17, 18, 19 |

  - Every run passes EPUBCheck and the structural, progress and memory gates.
  - No image changed, no page marker moved, no report field changed, and no provenance error was
    raised, on any case.
  - Navigation changed only for FAA, where page 333's heading becomes
    `Flight Information Service-Broadcast (FIS-B)`.
  - Converter peak RSS: 9/11 84 → 79 MiB, FAA 819 → 789 MiB, Wallace 82 → 87 MiB, Census 253 → 268
    MiB, USDA 289 → 296 MiB; the rest within a megabyte.
- DGA, CDC, the Blue Book, USGS, the pro-se complaint, IRS, USCIS and three of the four NTRS
  documents convert identically, in text and in blocks.

## Defects to file

- **Fed pages 47→48 and 98→99: a paragraph a box cuts at the foot of a page.** `…The vast major-`
  ends page 47 above Box 3.5, and `ity of the Federal Reserve’s assets…` opens page 48; page 98's
  `…all institu-` stands above figure 6.6 and `tions dealing with…` opens page 99. The cross-page
  rule walks back over images, captions and folios, not over a box's own paragraphs, so the anchor
  it finds is the box.
- **Fed page 28: a paragraph a box cuts with no hyphen at the break.** `…Short-term interest` and
  `rates would decline…` are two blocks with the box between them. Only a word break carries
  evidence of its own; a break at a word boundary needs the column geometry the same way, which is
  out of this issue's scope.
- **Our Flag page 47: `real ity` keeps its space.** The book prints neither `reality` nor any
  inflected form of it, so the policy has no evidence and the conservative reading stands. Only a
  lexicon, or the glyph evidence a hyphen's outline would give, could close it.
- **The USDA magazine's two columns are read interleaved** (pages 6, 8, 11–13, 15, 17–19). The word
  breaks now join correctly inside each column, but the columns themselves still interleave.
- **9/11 page 259 shows `attack.At the time`, page 438 `agencies,to conduct`, page 254
  `arrived.Hawsawi`.** These missing word spaces are #119/#128's; the row joins only make them
  visible inside one paragraph instead of at a block boundary.
