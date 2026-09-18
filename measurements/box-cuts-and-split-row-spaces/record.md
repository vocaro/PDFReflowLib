# Paragraphs a box cuts, rows PDFKit splits, and the soft hyphen it drops (#177)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 (26A428) arm64, Xcode 27.0 (27A266a),
release CLIs, shared host with other agents' conversions running. Work began on `4568b8e` (merged from
the coordination branch) and stayed there. Every number below was measured on that tree (baseline) and
on this change (candidate).

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline CLI | `4568b8e`, `swift build -c release`, launched as `pdf-reflow-base` | `276d6100…` |
| candidate CLI, second build | this change without the whitespace rule in `spells` or the row span | `ab44b89e…` |
| candidate CLI, third build | this change without the row span (a show measured across a wide gap) | `275372c2…` |
| candidate CLI, final | this change | `3b252da9…` |
| `survey-lines` (base, cand) | `missing-spaces-survey/tools/build.sh <tree>` | — |

One capability probe (`.build/raster-environment/probe`) served every lane. The third build differs
from the second only in `NativeSpacingReader.spells` accepting PDFKit whitespace for a space glyph,
and the final build from the third only in `rowPieceSpaces` accepting a wider gap that a show
measures across. Product-line surveys of all 21 English documents with consecutive builds differ on
5 lines (all Our Flag's) and then on 171 lines (9/11 12, Wallace 159), so the second build's lanes
stand for the final binary on every other book; Fed and Our Flag were rerun on the third build and
9/11 and Wallace on the final one. No source PDF or EPUB is committed; lane outputs
were deleted after review. `tools/` holds every script used, with the paths of the run.

## The state on `4568b8e`

None of the four items was fixed by #189, #188, #159 or #158. On the baseline EPUBs:

- **Fed 47→48 and 98→99:** `…The vast major-` ends page 47's paragraph and `ity of the Federal Reserve’s
  assets…` opens page 48 as a paragraph of its own; `…That is, all institu-` / `tions dealing with…` the
  same on 98→99.
- **Fed 28:** worse than #148 recorded. The paragraph is three blocks: `Short-term interest rates.
  …Short-term interest`, `rates would decline … previously expected. Conversely, short-term interest`
  (#148's word-break join), and `rates would rise … anticipated.`, with the sidebar between.
- **Our Flag 47:** `did not become a real ity until June 20, 1782.`
- **9/11:** `arrived.Hawsawi told` (254), `attack.At the time` (259), `agencies,to conduct` (438), and the
  contract pinned the first two as they were.

## Root causes

1. **The cross-page walk stops at a box's last block.** `continuation` steps back over images,
   captions, folios and footnotes. Box 3.5's heading, paragraphs, Table A and note, and figure 6.6's
   `Source:` note, are none of those, so the anchor it found was the box's `Note: …/h41/.` or `Source:
   ….htm).`, which ends a sentence.
2. **A paragraph wrapped around an inset box has no geometric continuation.** `nextLineInColumn` asks
   for one left edge. The sidebar on page 28 sits inside the column's left, so the narrowed lines start
   226 points right of the full-measure lines above and below them. No hyphen is involved at either
   junction, so #148's word-break reach (`joinWordBreaks`) does not apply.
3. **Our Flag's line-end hyphen is U+00AD, and PDFKit drops the character.** The show on page 47 is
   `beliefs, values, and sovereignty of the new Nation, did not become a real­` (the last glyph maps to
   U+00AD). PDFKit's line ends at `real`, and its rectangle 3 points short of the show's measured end.
   #157 recovered 13 such lines from the rectangle's shortfall and the book's words; `reality` is
   printed nowhere, so the words could not decide page 47. The 300-dpi render shows the hyphen.
4. **The three 9/11 fusions are not #128's rule missing them.** Each line's word space is already in the
   reader's evidence (`wordSpaces`: `arrived.|Hawsawi` at offset 66, `attack.|At` at 43, `agencies,|to`
   at 46; `agencies,to` is #119's comma class, not #128's). PDFKit splits one justified show's row
   into two lines (`…each had arrived.Hawsawi ` and `told`, 4.2 points apart; `ning for what later became `
   and `the 9/11 attack.At…`; `…agencies,to conduct oversight of ` and `the intel-`). The show's origin
   lies in the first piece, so the first piece's shows spell more than the piece, and the second piece
   owns no show. The exact-line rule refuses both. #148's `joinedRows` rejoins the pieces later, which is
   why the fusion became visible inside one paragraph.

## What changed

`Sources/PDFReflowLib/LayoutReconstructor.swift`, `NativeSpacingReader.swift`, `NativeTextReader.swift`.
No public API, option, default or warning changed.

Shared functions touched (for the agents working on #181, #193, #194, #161 and #186):
`LayoutReconstructor.continuation` (now a wrapper over a second overload), `continuesColumn`,
`joinColumnContinuations`, `joinWordBreaks` (gains `insets:`), `blocks(page:…)` (passes the insets to
`joinWordBreaks`); new `nextLineAroundInset`, `continuationPastBox`. `NativeSpacingReader.apply` (gains
`allTexts:`); new `spells`, `droppedSoftHyphen`, `rowPieceSpaces`. `NativeTextReader.extractLines`
(reads each line's text once into `textsByLine` and passes it on).

- **Foot boxes (item 1).** `continuation` tries its reading first; failing that, it walks back again
  and also steps over blocks lying in one of the previous page's tinted boxes (first and last lines
  inside one hull). The join then requires that at least one box was stepped over, that each such box
  lies beneath the anchor's last line and over its measure, that the anchor is in no box, and that the
  next page's first line is in none. The stepped boxes' lines are removed from the page before
  `endsColumn` asks what lies below the anchor. The box's blocks keep their place ahead of the joined
  paragraph on their own page, as a figure's do; `appendPage` needed no change for that. Trying the
  first reading first keeps a sidebar that continues onto the next page continuing there.
- **Insets (item 2).** `nextLineAroundInset`: same size, directly beneath at no more than 1.5 line
  heights, no line between, right edges within two bodies, left edges more than half a body apart,
  and an inset (a crop or a tinted box) that starts at the wider line's edge, ends at the narrower
  line's (half a body of slack), fills at least half the indent, stands within a pitch of the narrower
  line and does not touch the wider one. `continuesColumn` accepts it beside `nextLineInColumn`, and
  `joinWordBreaks` accepts it for its reach past a box (page 84's `…maintain a mini-` / `mum
  liquidity…`, which the inset join on the line above would otherwise have separated).
- **Word-boundary reach past a box (item 2, general).** `continuationPastBox`: where the adjacent
  block does not continue a column paragraph, the first block past a run of box blocks (tinted boxes
  the anchor's last line is not in) may, when its first line is the anchor's next line in the column
  or around the inset and `continuesColumn` holds. A broken word is left to `joinWordBreaks`.
- **Soft hyphen (item 3).** `droppedSoftHyphen`: the line's last show ends in U+00AD after a letter,
  PDFKit's text lacks it, and the shows otherwise spell the line. `apply` then inserts U+00AD before
  the line's trailing whitespace and reads the line's spaces with it. `joinOperation` already removes a
  soft hyphen unconditionally, which is the documented meaning of the character, so `real­` + `ity`
  becomes `reality` with no vocabulary involved. `spells` accepts PDFKit whitespace for a source space
  glyph, because PDFKit sets a newline where the page draws the space after the rest of a broken word
  (page 25's `ner\nwhatsoever.`); `missingSpaces` keeps its strict comparison.
- **Split rows (item 4).** `rowPieceSpaces`, used by `apply` only where the line's own shows do not spell
  it (or it owns none): the row is the lines on the piece's baseline (middles within a quarter of its
  height, heights within a quarter) chained left to right with gaps of −0.75 point to one line height.
  Every show whose origin lies in a row piece must lie in that piece alone among the page's lines, and
  the shows must spell the pieces joined by a space. A gap wider than the line's height is accepted
  only where a show that starts in the left piece measures past the right piece's start by more than
  that height (the 9/11 appendix sets each name and its description as one show). `missingSpaces`
  then reads the row as one line, and the piece takes only the insertions strictly inside its own
  text; the joining space means none can fall at a junction.

Why item 4 does not reintroduce #119's or #128's spurious insertions: it adds no word-space
threshold and no character rule. The boundaries are the ones #119, #128, #43 and #188 already decide
for a line whose shows spell it; the row reading only admits lines PDFKit cut through a show, under
the same ownership and spelling conditions, widened from one rectangle to the pieces of its row.

## Survey: every changed product line, all English books

`tools/survey-all.sh` runs `survey-lines` for the baseline and candidate trees on all 21 English
documents; `tools/difflines.py` classifies every changed line (`line-changes.tsv.gz`).

| Book | Lines changed | Change |
| --- | ---: | --- |
| 9/11 | 16 (17 spaces) | a word space: `arrived. Hawsawi` (254), `attack. At` (259), `agencies, to` (438), and 13 in the appendix's name lists (450–456: `(a.k.a. Abu Musab)`, `Jordanian; Virginia`, `Director, Federal Bureau of Investigation, 1993–2001`, `U.S. Ambassador`, `Khallad, Waleed`) |
| Wallace | 324 on 99 pages | 643 spaces, all of #188's operator class or #43's font change, on rows PDFKit split |
| Our Flag | 72 | a restored soft hyphen at the line's end |
| the other 18 | 0 | — |

No other book's shows end a line in a soft hyphen PDFKit dropped, and only 9/11 and Wallace have rows
whose pieces a show spans. On the 9/11 EPUB, #128's fused class (a word, sentence punctuation, a
capital, excluding initials and `U.S.`) falls from 30 to 16 runs: the note numbers #128 keeps closed
by design (`10.August`, `158.The`) and two web addresses.

## Lanes

`tools/lane.sh` (`run_corpus_regressions.py`, one case per call, `--environment-probe`) on both
binaries for every case in the lane except the Arabic and Chinese documents; `tools/compare.py`
(`compare_conversion_runs.py --allow-different-converters --detail`, kept as `lane/*.json.gz` for the
cases that changed). Every run passed EPUBCheck, the structural, progress and memory gates. No page
marker moved, navigation did not change, no provenance error or OCR page change occurred.

| Case | Baseline | Candidate | Changed pages |
| --- | --- | --- | --- |
| fed-explained-2021 | pass (old contract) | pass | 20, 28, 34, 40, 41, 46, 47, 48, 55, 56, 60, 84, 92, 93, 94, 97, 98, 99, 100, 101, 105, 106, 122 |
| gpo-911-2004 | pass | pass | 254, 259, 438, 450, 452–456 |
| gpo-our-flag-2003 | pass | pass | 30 pages, 5–53 |
| wallace-algebra-2010 | pass | pass | 14, 24, 41, 120, 160, 171, 197–199, 221–224, 226, 229, 235, 253, 276, 283; `imageCount` −1 |
| ntrs-20200002975-gwl-2020 | pass | pass | 20 |
| usda-ars-agresearch-2012-11 | pass | pass | 16 |
| noaa-nca5-2023 | pass | pass | 50 |
| faa-phak-8083-25c, dga, cdc, blue book, usgs, loper bright, census, nbs, replay clocks, pro-se complaint, three NTRS | pass | pass | identical |

Converter peak RSS, baseline → candidate: Fed 282 → 272 MiB, 9/11 83 → 83 MiB, Our Flag 106 → 103 MiB,
Wallace 89 → 90 MiB (sampling on a loaded host).

### Review

Every changed page was read against its source render; `tools/pagediff.py` lists each page's word
changes and paragraphs, `tools/crossjoins.py` every paragraph that newly crosses a page marker, and
`tools/junctions.py` the words around each new same-page join.

- **Fed, 9 cross-page joins, all correct.** 47→48 `The vast major` | `ity of…`, 98→99 `all institu` |
  `tions dealing…`, and seven more of the same shape the issue did not list, each a paragraph over a
  tinted box or figure box at the page's foot: 40→41 `When the` | `securities are bought`, 46→47
  `the level of reserves` | `in the banking system`, 55→56 `for large banking` | `institutions`,
  93→94 `(interbank transactions)` | `and between businesses`, 97→98 `Much of the recent` | `growth in
  ACH payments`, 100→101 `the night before a business` | `day and closes`, 105→106 `help finance the` |
  `United States’ World War I effort`. The boxes stay on their pages, ahead of the paragraph.
- **Fed, 8 same-page joins around a box, all correct.** 28 (both junctions), 20 `At` | `times…` |
  `FOMC has used`, 34 `the outlook,` | `and the reasons` (a box on the right, read between; the
  word-boundary reach), 60 `of distress` | `at or between` | `those institutions`, 84 `These standards`
  | `require…`, with `mini-` | `mum` still joined, 92 `supervisory,` | `and lending`, 94 `less than their`
  | `full face value`, 122 `consumer` | `compliance culture…` | `to tailor`. Each box's blocks follow
  the paragraph.
- **9/11, 17 spaces on 16 lines, all correct.** The three the issue names; and 14 on 13 lines of
  the appendix's lists of names (pages 450–456), where one show runs from the name column into the
  description column 38 points to its right: eight `(a.k.a. Abu …` style openings, `Jordanian; Virginia`, `Khallad, Waleed`,
  `Joe the Moroccan, Abu Talal`, `Director, Federal Bureau of Investigation, 1993–2001` (two) and
  `U.S. Ambassador`. These are the lines #128 listed as refused by the exact-line rule (`(a.k.a.Abu`,
  `Jordanian;Virginia`, `Director,Federal`); like the rest of #128's class the source sets them
  visually closed, and each separates two words. Page 456 is inside the pages #161 is working on.
- **Our Flag, 64 words rejoined, all correct.** `appro priate`, `forma tion`, `pub lic`, `mes sage`,
  `princi ples`, `majes tic`, `regi mental`, `magnanimi ty`, `bat tle`, `uni form` ×3, `orig inal`,
  `Independ ence`, `ren der`, `estab lished`, `holi days`, `adminis tration`, `dis play`, `con tinuance`,
  `dis played`, `accor dance`, `govern ment`, `build ing`, `drap ery`, `pic ture`, `hold ing`, `man ner`,
  `hal yard`, `organiza tions`, `addi tional`, `rec ommended`, `organ ized`, `symbol izes`, `con sisting`,
  `incor porates`, `repre senting`, `symbol ized`, `fami lies`, `togeth er`, `liber ty`, `adopt ed`,
  `com merce`, `independ ent`, `min ing`, `tradi tional`, `surround ed`, `territo rial`, `pop ular`,
  `obser vance`, `real ity`, `inno cence`, `offi cial`, `pub lished`, `CONSTITU TION`, `occu pied`,
  `procla mations`, `ex uberant`, `posi tion`, `interna tional`, `cush ions`, `liv ing`, `anoth er`. Eight
  of the 72 restored soft hyphens were already joined by #157. The candidate EPUB holds no U+00AD, and
  `tools/splitwords.py` (a pair whose join the book prints and whose second half it never prints alone)
  finds 24 such pairs in the baseline and none in the candidate.
- **Wallace, whitespace only on 18 pages, one crop released.** Every text change is a space beside an
  operator or after a digit set in its own font, on a row PDFKit split (`5+ 6x− 12` → `5 + 6x − 12`,
  `Distribute 3through` → `Distribute 3 through`, `Find the LCD of 8and 12` → `8 and 12`, `Convert
  3Rx` → `3 Rx`). 48 randomly chosen changed product lines (seeds 177, 1177 and 4177, the last drawn
  from the lines only the final build changes; `wallace-reviewed-lines.tsv`) were read on 200-dpi
  strips: every inserted space is visible in the ink. Page 226's Example 295 now reads
  as text rather than a formula crop, as #188's spacing did for thirteen pages: its signs become
  tokens of their own, which `isWordy` does not count (#188), so its annotation lines
  (`Multiply to ac or (8)( − 15) = − 120, add to − 2`) read as prose. Its `8x²` / `− 2x − 15` row then
  splits into a paragraph and a `<pre>` item, the shape 27 rows already have on the baseline
  (`tools/prerows.py`; 29 now). Page 276's crop holds the same derivation, 5 pixels narrower and 15
  shorter; both images were compared side by side.
- **GWL page 20, USDA page 16, NOAA page 50, all correct.** GWL's three author biographies wrap
  around portrait photographs (`Virginia. He` | `has been a researcher…`); USDA's `designed to ensure`
  | `continued productivity` is the next line of its column past the photo; NOAA's figure 1.7 caption
  `While similar data are` | `not available for the US-Affiliated Pacific Islands`.

## Contracts

`corpus/regressions.json`: 3,422 → 3,472 checks, 560 → 573 pages (`tools/contract-edit.py`,
`tools/contract-fix.py`, `tools/contract-fix2.py`; each page keeps one entry).

- **Fed.** `continuedParagraphs` on 40, 46, 47, 55, 93, 97, 98, 100 and 105; `paragraphs` across each
  same-page junction on 20, 28 (two), 34, 60, 84, 92, 94 and 122; page 28's paragraph distinct from the
  sidebar's; page 84's `mini- mum` absent (a control the baseline also passes).
- **9/11.** Pages 254 and 259's pinned fusions replaced by the spaced paragraphs, with the fused forms
  absent; page 438 `the agencies, to conduct oversight` and `agencies,to` absent; pages 450
  (`Director, Federal…, 1993–2001`), 452 (`(a.k.a. Abu Hafs al Masri)…`) and 455 (`(a.k.a. Abu
  Musab)`, `Jordanian; Virginia resident…`) with their fused forms absent. Page 456 has no new check,
  to leave #161's pages alone.
- **Our Flag.** Page 47's `did not become a real ity` (the #148 control) replaced by `did not become
  a reality until June 20, 1782.` with `real ity` absent, and `innocence`; pages 8, 15, 25 and 52 add
  rejoined words with their split forms absent.
- **Wallace.** Page 120's list item `− 18 <− 12` (the minus-row check from `3f59dff`, which also
  pinned PDFKit's spacing) becomes `− 18 < − 12`; page 24 adds `Combine like terms 10x − 24x and
  − 16 − 18` with the unspaced form absent.

Negative control: the baseline EPUBs against the new contract fail exactly the new reproducers (Fed
19, 9/11 14, Our Flag 17, Wallace 3) and pass the control; the final candidate passes every check.

## Tests

`Tests/PDFReflowLibTests/BoxCutParagraphTests.swift` (6) and three in `NativeSpacingTests.swift`. New
fixtures `fed-28`, `fed-48`, `fed-84`, `fed-98`, `fed-99` (captured on `4568b8e` with
`tools/capture-layout-fixture.swift`) and `911-split-row-operators.json` (9/11 pages 254, 259, 438 and
455, captured with `same-font-word-spaces/tools/fixture.py` and `native-lines.swift`).

1. `sourceParagraphContinuesPastABoxAtThePageFoot`: Fed 47→48 and 98→99 joined, the box's heading,
   table and note on their page ahead of the paragraph.
2. `onlyABoxBeneathTheParagraphAtThePageFootIsSteppedOver`: a synthetic foot box, with controls for
   no tint, a box beside the paragraph's foot, prose below the box, and a next page that opens in a box.
3. `sourceParagraphWrapsAroundAnInsetBox`: Fed 28, one paragraph, `nextLineAroundInset` on both
   junctions and not without the inset.
4. `aWordBrokenAroundAnInsetBoxJoinsPastIt`: Fed 84's `mini-` / `mum`.
5. `nextLineAroundAnInsetNeedsTheInsetToFillTheIndent`: eight controls on the predicate.
6. `aWordBoundaryBreakReachesPastABoxToTheColumnsNextLine`: Fed 34, with a closed sentence and a
   moved continuation as controls.
7. `nineElevenSplitRowsTakeTheirRowsWordSpaces`: each page gains exactly its reviewed spaces (one on
   254, 259 and 438, four on 455), the pieces alone gain none, every other line is unchanged, and
   `told` stays as read.
8. `rowPieceSpacesNeedTheWholeRowSpelledByShowsItOwns`: controls for no texts, a gap wider than a
   line (and the same gap joined when the show measures across it), another baseline, another
   spelling, and a show two rectangles hold.
9. `aSoftHyphenPDFKitDropsAtTheLineEndIsRestored`: restoration, the whitespace case, four controls, and
   the layout join to `reality` without an `uncertainHyphen` warning.

`nineElevenRepairs` and `NineElevenSource.load` gain optional parameters; the existing test is
unchanged.

Negative controls (`mutants.log`, `tools/mutate.py`; sources restored and checked after each run): each
of ten mutations fails at least one test — box stepping off (2 tests), the inset predicate off (3),
the word-boundary reach off (2), the inset in `joinWordBreaks` off (1), the box-beneath guard off (1),
the next-page box guard off (1), row pieces off (2), the row span off (2), soft hyphens off (1), and
`spells` strict (1).

## Verification

- `swift test`: 953 tests pass (944 on `4568b8e` plus 9).
- `scripts/check-all.sh --fast`: exit 0.
- `python3 tools/update_doc_counts.py`: counts regenerated.
- Lanes and contracts: above.

## Follow-ups

- **Wallace rows split after an exponent read as list items** (27 on the baseline, 29 now: `x2` then
  `<pre>− 8x− 20</pre>` on page 222, and page 226's Example 295). The minus that opens the second
  piece reads as a list marker.
- **A cross-page box stepped over is placed ahead of the paragraph it interrupts**, as a figure is.
  Page 47's Box 3.5 now reads before `Finally, the Federal Reserve’s actions…`, which refers to it. A
  box after the paragraph would put page-47 content past the page-48 marker; changing that needs a
  placement rule for boxes and figures alike.
- **Our Flag's other lost hyphens:** five of #157's thirteen lines carry no soft hyphen in their shows;
  they stay on #157's evidence.
