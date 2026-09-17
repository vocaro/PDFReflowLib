# The last sentences split around figures: caption wraps, short comma lines, open parentheses, tagged paragraphs (#145)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 (26A428) arm64, Xcode 27.0 (27A266a),
release CLI. Measured on `ec22aff` (#131 merged over #132/#135 and #118) with this change applied
uncommitted. No PDF or EPUB is committed.

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline | `ec22aff` | `276f8cf1…` |
| candidate | `ec22aff` plus this change | `dbf75c1f…` (FAA, Loper Bright, Census); `e88b19ca…` (the other ten cases) |

`e88b19ca` found the last sentence end with a backwards regular-expression search that Foundation ignores (it
found the first); `dbf75c1f` takes the last match. The fix can only remove parenthesis joins, and the only ones in
the corpus are in the three cases rerun on `dbf75c1f`, whose joins are identical.

Corpus: every English case (`faa-phak-8083-25c`, `wallace-algebra-2010`, `gpo-911-2004`, `fed-explained-2021`,
`dga-2025-2030`, `gpo-our-flag-2003`, `cdc-zombie-pandemic-2011`, `cia-blue-book-14-1955`,
`usgs-mcs2025-copper`, `scotus-loper-bright-2024`, `census-rrs2002-01`, `nbs-jres-geltman-1977`,
`arxiv-replay-clocks-2023`).

## The six FAA splits

[#118's record](../column-continuation-recount/record.md) left six sentences split. Each was traced on a
source-derived fixture through `LayoutReconstructor.blocks` and read on a `pdftoppm` render.

### 341→342 and 391→392: a caption's wrapped line read apart from the caption

FAA page 391 sets figure 16-4's two-line caption at the left column's foot, under the globe, beside the right
column's last three lines. The left side holds one wide text line, so the narrow gutter (12 pt) is no prose-column
evidence and the lower part of the page falls to the row sort, which reads `…during long flights eastward—` /
`Figure 16-4. Meridians and parallels—the basis of measuring time,` / `be completed before dark. Remember, an hour
is lost when` / `distance, and direction.`. The paragraph rule sets each line apart from its neighbour in the other
column; #118's next-line rule rejoins the body, but the caption's second line stays a body paragraph and, as the
page's last paragraph, blocks the join to page 392. Page 341 is the same interleave twice (`…marking located` /
`on Taxiway Kilo.` beside `thresholds. Figure 14-10…`; `…takeoff end of Runway` / `14 with collocated Taxiway Alpha
location sign.` with figure 14-7's caption read between), and page 397 once (`…and compass` / `headings for a
particular instance.`, which also held the list item `• GS—rate of the aircraft’s inflight progress over` apart
from `the ground.`).

**Rule** (`joinWrappedCaptionLines`, before the column joins): a `Figure|Table N` paragraph that leaves its sentence
open takes a later paragraph of the page whose first line lies directly beneath the caption's last line
(`wrapsCaption`): on its left edge or centre (half a body), at ordinary leading (gap −0.4…0.9 of the larger size),
less than 15% larger (the caption rule's own limit, #63) and smaller than 95% of the page's body size, with no
line between them. The body-type guard came from the rebase lane on `9ec0608`: the new NASA paper
(`ntrs-20200002975-gwl-2020`) wraps a 10-point body sentence onto `Figure 14. These peak values acquired in
uniform flow and`, which reads as a caption, and its columns interleave, so the rule took the body lines beneath
and the page 9→10 join (`…static loads resulting` / `from drag`) broke its contract. At least one block must stand
between the two: where the paragraph rule read the lines in sequence and still set them apart, that decision stands.
That guard came from the lane: without it the Fed's 10-point bold `Figure N.` titles took the 8-point description
beneath (pages 13, 54, 75, 128: `…paid to the U.S. Treasury` / `The Federal Reserve transfers its net earnings…`).

### 221→222 and 438→439: short last lines, not narrow rectangles

The issue asked for widths measured from the page's text shows, on the premise that PDFKit reports these lines
narrower than they print. Measurement contradicts the premise. [`tools/measure.py`](tools/measure.py) interprets the
page content streams (`Tm`/`Td`/`TD`/`T*`, `Tc`, `Tw`, `Tz`, TJ adjustments, CIDFontType2 `W`/`DW` widths for the
Identity-H Times New Roman both lines use, and simple-font `Widths`) and prints each show's start and advance end
(the end includes the trailing space glyph each FAA word string carries):

| Page | Line | Show end (with trailing space) | PDFKit maxX | Column's full lines: show end / PDFKit |
| --- | --- | --- | --- | --- |
| 221 | `compass. Errors in the magnetic compass are numerous,` | 537.99 | 535.7 | 564.6 / 562.3 |
| 438 | `list, states have taken steps to allow the possession, sale,` | 513.04 | 510.5 | 524.64 / 522.1 |

The differences (2.3 and 2.5 pt) are the trailing space's advance, the same on the full lines. The renders agree:
both lines end short in print, the last line of a text frame the producer did not justify. PDFKit's rectangles are
right, so no width scan was added and `fillsColumn` is unchanged.

**Rule** (`endsOnAComma`, both join rules): before a lowercase opening, a last line that ends on a comma after a
word, in the page's body size, with at least three words and twelve bodies wide need not fill its column. A comma
leaves the sentence open whatever the line's width. The body-size guard came from the lane: NBS page 1's 3-point
footnote `I Figures ill brackets indicllLe the literature references al the end of thi s paper,` (OCR read the
period as a comma) joined the right column's `where u (t) = Uo sinwt…`.

### 24: one tagged paragraph

Page 24's `…through training, outreach, and education. The FAA` (left column foot, over figure 1-13) and `Safety Team
(FAASTeam) exemplifies this commitment.` (right column head) are one `P` in the structure tree (group 1004 on both
lines). The figure and its caption interrupt the group, so it falls back to spatial reading and the blocks carry no
identity; `FAA` can end a sentence, and without vocabulary nothing else separates the proper noun from a new
sentence. The tag is the author's evidence.

**Rule** (`sameParagraphTag`, both join rules): a capital, digit or quote continues after any word when the anchor's
last line and the continuation's first line carry the same validated paragraph group (heading level 0). Every other
guard still applies (the text leaves its sentence open, the anchor fills its column, the opening is in the anchor's
type on a full line or closes its sentence, no prose competes). Different groups already refuse.

### 169→170: an open parenthesis

Page 169 ends `…(versus relative) Fahrenheit degrees (70 x 100/180 = 38.89`; page 170 opens `Celsius degrees)
(Remember there are 180 Fahrenheit degrees`. `38.89` is not a word that cannot end a sentence.

**Rule** (`leavesParenthesisOpen`, in `continuesSentence`): a capital, digit or quote also continues when the text
after the last sentence end (terminal punctuation, closing quotes or brackets, then a space) opens more parentheses
than it closes. A paragraph does not end inside an open parenthesis; the other guards still apply.

## Lane (`ec22aff` → candidate)

`tools/run_corpus_regressions.py --converter <CLI> --epubcheck /opt/homebrew/bin/epubcheck --environment-probe
.build/raster-environment/probe --execution-context host-terminal --case <id>`, one case per call
([`tools/lane.py`](tools/lane.py)), then `tools/compare_conversion_runs.py --allow-different-converters`
(`lane/cmp-<case>.json`), #118's per-page block diff and recount
([`pagediff.py`, `recount.py`](../column-continuation-recount/tools)). Every run passed EPUBCheck, resource,
progress and memory gates. In every comparison images, navigation, page markers and report fields are unchanged.
The contract column uses the final `corpus/regressions.json` (`lane/contract-*.json`).

| Case | Changed pages | Joins gained / lost | Contract (base → candidate) |
| --- | --- | --- | --- |
| faa-phak-8083-25c | 20–22, 24, 169–170, 221–222, 320–321, 341–342, 391–392, 397, 438–439 | 11 body joins and 4 caption wraps / 0 ([joins](lane/joins-faa.diff), [pages](lane/pagediff-faa.txt)) | fails exactly the 14 new expectations (516 checks) → pass |
| scotus-loper-bright-2024 | 3–4, 34–35 | 2 / 0 ([joins](lane/joins-scotus.diff)) | fails exactly the 2 new expectations (97 checks) → pass |
| census-rrs2002-01 | 2 (and OCR page 8, see below) | 1 / 0 ([joins](lane/joins-census.diff), [pages](lane/pagediff-census.txt)) | pass → pass (no expectation added, see below) |
| fed-explained-2021, gpo-911-2004, wallace-algebra-2010, dga-2025-2030, gpo-our-flag-2003, cdc-zombie-pandemic-2011, cia-blue-book-14-1955, usgs-mcs2025-copper, nbs-jres-geltman-1977, arxiv-replay-clocks-2023 | none (strict comparison passes) | 0 / 0 | pass → pass |

**Review of every change.** Each was read on a source render.

- *FAA, caption wraps (4 captions, 3 pages)*: 341 `Figure 14-8. …marking located on Taxiway Kilo.` and `Figure 14-9.
  …takeoff end of Runway 14 with collocated Taxiway Alpha location sign.`; 391 `Figure 16-4. Meridians and
  parallels—the basis of measuring time, distance, and direction.`; 397 `Figure 16-16. Relationship between true,
  magnetic, and compass headings for a particular instance.`, which also lets the list item join `the ground.`
  (#118's next-line rule).
- *FAA, joins released by the captions*: 341 `…“18-36” to indicate the` / `threshold for Runway 18 is to the left
  and the threshold for` (next line of the column) and on to 342's `Runway 36 is to the right.`; 391 `…an hour is
  lost when` / 392 `flying eastward from one time zone to another`.
- *FAA, comma lines*: 221 `…are numerous,` / `making straight flight and precision turns to headings difficult`;
  438 `…the possession, sale,` / `and use of marijuana withing their border.` (the source's spelling).
- *FAA, tags*: 24 `…education. The FAA` / `Safety Team (FAASTeam)`, and three cross-page joins the issue did not
  list, each one tagged paragraph with only the page break between: 20 `…administering the Federal Aid` / 21
  `Airport Program.`, 21 `…the Professional Air` / 22 `Traffic Controllers Organization (PATCO) culminated…`, 320
  `…10,000 feet AGL. After` / 321 `2000Z, the forecast calls for scattered thunderstorms`.
- *FAA, parenthesis*: 169 `(70 x 100/180 = 38.89` / 170 `Celsius degrees)`.
- *Loper Bright, parenthesis*: syllabus 3 `…(quoting Allentown Mack Sales &` / 4 `Service, Inc. v. NLRB, 522 U. S.
  359, 374).`; opinion 34 `…(2022) (GORSUCH,` / 35 `J., dissenting from denial of certiorari)`.
- *Census, parenthesis*: page 2's abstract `…The masking methods are rank swapping (` / `13], also [ 5]), additive
  noise…`, the next line of the column. Correct, but the line's text (`( 13]` for `[13]`) is the font-decoding
  defect #143 works on, so no expectation pins it. The final Census comparison also lists page 8 and its
  navigation: an OCR page whose text differs because the two binaries' compiled Vision programs differ
  (`ocrCaveat` in [the comparison](lane/cmp-census-rrs2002-01.json), #94); the `e88b19ca` run of the same change
  left page 8 unchanged.

FAA recount ([before](lane/recount-faa-before.txt), [after](lane/recount-faa-after.txt), #118's method): 81 → 75
candidates past figures, captions and headings; the six #145 splits are gone and nothing new appears.

**Caption survey.** Every changed caption in every English book is listed above (FAA only). Open-ended captions
that remain, from the candidate EPUBs ([`tools/captions.py`](tools/captions.py)): FAA none (its three hits are body
paragraphs opening `Figure N shows`, or the `.` fragment on page 136 #118 set aside); the Fed's 13 are `Figure N.`
titles over a description, `Note:` or `Source:` paragraph, correctly separate; Wallace's five `Table N.` titles over
their tables; Census's seven table titles over OCR table rows; and Blue Book pages 5–7, the list of illustrations,
where most of its 30 open-ended entries are titles set over two lines and split at the wrap (see below). No other book has one.

### Rebase check (`f8a0a7a`)

After rebasing onto `f8a0a7a` (#143 native Census decoding, the two new corpus documents, #147 paragraph openings,
generated doc counts), the lane was rerun with one executable name for both sides (`base/pdf-reflow`
`0c944338…` built from `9ec0608`, whose sources `f8a0a7a` leaves unchanged; `cand/pdf-reflow` `9c8346b1…`) on
FAA, Loper Bright, Census, Fed, NBS, Our Flag, `uscourts-pro-se-1-2016` and `ntrs-20200002975-gwl-2020`. The first
candidate broke the NASA paper's contract (the body-type guard above); with the guard, the join lists of FAA, Loper
Bright and Census equal the reviewed ones line for line, the Census page 2 join is unchanged (that page is still
read by OCR), and Fed, NBS, Our Flag and both new documents are unchanged with their contracts passing.

## Cost

No per-line width scan was added. The new passes are string and rectangle tests over a page's blocks and lines;
`joinWrappedCaptionLines` first finds the lines beneath an open caption's last line, and the join rules test
`endsSentence` before looking up anchor lines. A reconstruction micro-benchmark (every fixture in
`Tests/PDFReflowLibTests/fixtures`, 316 pages chained through `blocks` and `appendPage`, best of seven, `swift test -c
release`, on the `4fc3115` merge): baseline 1.826, 1.810, 1.743 s; candidate 1.813, 1.793 s. A first candidate that
looked up the anchor lines before the sentence test, and compiled the parenthesis expression for every capital
opening, measured 1.962 s; both were fixed. Converter CPU in the lane (base → candidate): FAA 46.23 → 46.50 s,
9/11 11.75 → 12.06 s, Wallace 23.87 → 23.19 s, Blue Book 43.21 → 42.54 s; peak RSS within ±20 MiB, all within
run-to-run noise (the `4fc3115` baseline binary measured 45.05 and 47.14 s on two FAA runs).

## Tests and contracts

`Tests/PDFReflowLibTests/CaptionWrapsAndOpenSentencesTests.swift`, twelve tests. New fixtures captured with
`tools/capture-layout-fixture.swift` as merged at `ec22aff` (recaptured byte-identical from the merged tree):
`faa-{169,170,221,222,342,391}`, `faa-20-tagged`, `faa-24-tagged`, `fed-13-tagged`, `nbs-1`; existing
`faa-341`, `faa-392`, `faa-438`, `faa-439`, `faa-21-tagged` are reused.

- Reproducers: `captionKeepsTheLineItWrapsOntoAcrossTheOtherColumn` (391–392),
  `wrappedCaptionLinesRejoinTheirCaptionsAndReleaseTheColumnJoin` (341–342), `lineEndingOnACommaContinuesAcrossThePage`
  (221–222, 438–439), `openParenthesisContinuesBeforeACapital` (169–170), `oneTaggedParagraphContinuesBeforeACapital`
  (24, with untagged and retagged controls), `oneTaggedParagraphContinuesAcrossThePage` (20–21).
- Source negative controls: `captionLineReadInSequenceKeepsTheParagraphRulesBreak` (Fed 13) and
  `commaEndingInOtherTypeDoesNotContinueAColumn` (NBS 1).
- Synthetic controls: `captionWrapNeedsTheNextLineOnTheCaptionsEdgeAtItsLeading`,
  `onlyAnOpenCaptionTakesALineReadApartFromIt`, `shortCommaLineNeedsProseAndALowercaseOpening` (across pages and
  between columns), `parenthesisIsOpenOnlyInTheLastSentence`.
- Existing test: `noteContinuationsOpeningWithDigitsBracketsAndCapitalsJoin`'s control chain, which converts 9/11
  pages 579–582 without the note hand-off, now joins `(Wail al Shehri,` / `Waleed al Shehri, Mohand` as body text
  through the open parenthesis; the control expects that join and keeps the other two openings apart. The real lane
  (with the hand-off) is unchanged for 9/11.
- Mutations ([mutants.log](mutants.log), [`tools/mutate.py`](tools/mutate.py), on `ec22aff`): all 29 fail at least
  one test (each rule switched off, and every single guard: the caption's open sentence, a block between, the
  candidate not a caption, the line beneath, size, both leading bounds, edge, centre, a line between; comma, letter,
  words, width, body size and the lowercase opening on each join rule; tag group, tag heading level, each rule's
  tag lookup; the parenthesis, its sentence bound and taking the last sentence end). A first pass left five alive for want of isolating controls
  (the block-between guard, whose first Fed fixture had no bold runs; the line-between guard, whose control failed
  the leading bound first; the comma rule between columns and the lowercase requirement on both rules, which had no
  same-page or capital controls); controls were added and the set rerun.
- Contracts ([`tools/addcontract.py`](tools/addcontract.py)): FAA `continuedParagraphs` on 20, 21, 169, 221, 320,
  341, 391 and 438, `paragraphs` on 24, 341 (two captions), 391 and 397, `listItems` on 397; Loper Bright
  `continuedParagraphs` on 3 and 34. The baselines fail exactly these 16 and nothing else.

## Verification (on `ec22aff`)

- `swift build -c release`: clean.
- `swift test`: 697 tests pass.
- `scripts/check-all.sh --fast`: exit 0 (697 Swift, 219 Python, 6 fixture and 13 policy conversions, 22
  rejection/cleanup cases, repeat-run identity).
- Corpus lane: the table above.

The tools in `tools/` were run from a scratch directory holding #118's `recount.py` and `pagediff.py`; paths inside
them are those of the run.

## Remaining gaps and defects

- **Reading order interleaves a caption at a column's foot with the prose beside it** (FAA 341, 391, 397): the
  captions are now whole, but the order still comes from the row sort, because one wide line beside a figure is no
  prose-column evidence. The gutter test could count a preserved image as column content.
- **Blue Book's list of illustrations** (pages 5–7): 30 entries set over two lines are split at the wrap, e.g.
  `…Distribution of Object Sightings by Months Among the Eight Duration` / `Groups for All Years`. Nothing is read
  between the two parts, so this change leaves them; why the paragraph rule separates them was not traced.
- **Census page 2's `( 13]`**: the decoded bracket (#143).
- A proper noun after a word that can end a sentence, with no tag, open parenthesis or other evidence, stays split.
