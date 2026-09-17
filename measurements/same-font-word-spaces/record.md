# Same-font word spaces PDFKit drops in the 9/11 report (#119)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64 (26A428), Xcode 27.0, release
CLIs. Work started on `9bf4e76` and was carried by fast-forward onto `43b20aa`, `d35285f`, `605d7e3`,
`e949bea` and `9803329`. Every number below was measured on `9803329` unless a section says otherwise.
The survey, lanes and line diffs were repeated on `e949bea` with identical results.

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline CLI | `9803329`, `git archive`, `swift build -c release` | `532f606e…` |
| candidate CLI | this change on `9803329` | `ae95a690…` |
| `survey-lines` (base, cand) | `missing-spaces-survey/tools/build.sh <tree>` | — |
| source | `corpus/cache/GPO-911REPORT.pdf` | `657d4147…` |

No source PDF, EPUB or render is committed. Lane outputs, renders and line dumps were deleted after
review. `tools/` holds every script. Paths below are relative to this directory.

## Diagnosis: how the report encodes the spaces PDFKit drops

The report is Quark output distilled by Acrobat Distiller 6.0.1 (encrypted with an empty user
password). Body text is `KAFHKN+Bembo`, a Type1 font with `Widths` (space 0.278 em) and a
bfchar/bfrange ToUnicode map. Every line is justified with nonzero `Tc` and `Tw` (577 of 585 pages;
`tools/operators.py`), and the page's only other state is a font-free `/GS1 gs`. Page 234, abridged:

```
10.25 0 0 10.25 39.66 540.2433 Tm -0.0008 Tc -0.0687 Tw
[(Saudi students and seek assistance at local mosques.)-108.9(He counted on their br)19.6(eak=)]TJ
... [(Air)-39.9(por)-25(t,)-106.6(w)39.7(e)-0.1( do not kno)39.7(w wher)19.7(e the)19.7(y w)39.7(ent.)]TJ
7.175 0 0 7.175 208.9782 407.4983 Tm 0 Tc 0 Tw (8)Tj
10.25 0 0 10.25 213.2925 405.2433 Tm ... [(The)19.7(y appear to ha)29.8(v)39.9(e)0( obtained assis=)]TJ
... [(as instr)-25(ucted,)-133.8(the)19.7(y attempted to enr)29.7(oll in thr)19.7(ee language schools in Los )79.9(Angeles.)]TJ
```

A word space is set in one of three ways:

1. **An explicit space glyph** (`Los )79.9(Angeles`), widened by `Tw` and sometimes narrowed by a kern.
   PDFKit keeps every one: none of the space glyphs located in its lines is dropped (262,307 in all),
   even at 0.09 em (`instances/911-space-glyph-outcomes-base.tsv`).
2. **A TJ adjustment between two glyphs, with no space glyph** (`mosques.)-108.9(He`,
   `research,)-106.6(which`). Distiller writes this where Quark kerned the space, which happens after
   punctuation and before a capital that overhangs to the left (`New|York`, `the|Vice`). PDFKit
   inserts a space only from about 0.14 em (461 of 817 at 0.14, 887 of 918 at 0.15, every one above).
   Narrower adjustments reach the EPUB fused. **This is the defect** (`instances/911-adjustment-gap-outcomes-base.tsv`).
3. **A separately positioned show.** Note references are 7.175-point digits raised 2.25 points
   (`(8)Tj`), and the text resumes with its own `Tm` 0.11–0.14 em (of the reference's size) after the
   digit's advance. PDFKit drops the space before the text (16 cases, all listed in the issue).

`Tc` matters. Letter-spaced Bembo-SC chapter openers set `Tc` +0.094 em with adjustments near
−0.02 (`Tue sday`, a pdftotext artefact that PDFKit reads correctly). Some adjustments are cancelled
by a negative `Tc` (`9:34` sets +31 against `Tc` −0.031 em, `Ye|s.` +160 against −0.160,
`WA|RTIME` +100 against −0.100). The measure used below is therefore **min(adjustment, adjustment + Tc)** in em of
the font size, so neither a letter-spacing `Tc` nor a cancelled adjustment reads as a gap.

`NativeSpacingReader` disqualified every 9/11 page at its first nonzero `Tc` or `Tw` (#110), so none
of this was measured.

## Gap distributions and thresholds

`tools/shows.py` simulates each page's text operators (via `mutool show`) and writes every boundary
between glyphs: TJ adjustments between two non-space glyphs, explicit space glyphs, and show-to-show
gaps on one baseline (1,593,884 boundaries). `tools/join.py` locates each boundary's context in the
page's baseline product lines and records whether PDFKit's line has a space there.
`tools/groups.py` bins min(adjustment, adjustment + Tc) at 0.01 em by pair class. Left: `l`
lowercase, `U` uppercase, `D` digit, `P` `. , ; : ? !`, `Q` `” ’ )`, `O` other. Right: `v` an
overhanging capital `A T V W Y`, `q` an opening `“ ‘ (`, `w` another letter or digit, `o` other.
Cells are PDFKit dropped/kept. Excerpt of `instances/911-adjustment-groups-base.tsv` (full table
there):

| adj em | Pw | Pv | Pq | lv | lw | Uv | Qw | lo |
| ---: | --- | --- | --- | --- | --- | --- | --- | --- |
| −0.02 | 2/0 | 171/0 | . | . | 32954/0 | 7/0 | . | . |
| +0.00 | 660/0 | 28/0 | 11/0 | . | 12508/0 | 38/0 | 6/0 | 305/0 |
| +0.01 | . | 145/0 | 72/0 | 4/0 | 863/0 | . | . | 2/0 |
| +0.03 | . | 259/0 | 57/0 | 35/0 | 4513/0 | . | . | 150/0 |
| +0.04 | . | 232/0 | 62/0 | 20/0 | 13076/0 | . | . | . |
| +0.05 | . | 341/0 | 72/0 | 35/0 | 159/0 | 1/0 | . | . |
| +0.07 | 2/0 | 261/0 | 104/0 | 48/0 | . | . | . | . |
| +0.09 | 56/0 | 269/0 | 67/0 | 117/0 | . | . | 2/0 | . |
| +0.11 | 2082/1 | 200/0 | 69/0 | 19/0 | . | . | 91/0 | 1/0 |
| +0.13 | 1253/13 | 113/1 | 20/0 | 11/0 | . | . | 65/1 | 4/0 |
| +0.15 | 16/758 | 4/28 | 1/6 | 0/6 | . | 0/17 | 0/53 | . |
| +0.18 | 0/1573 | 0/3 | . | 0/9 | . | . | 0/173 | . |

Each group is bimodal, but the modes sit in different places:

- **Before a letter, digit or `(` that does not overhang** (`Pw`, `Qw`, `Dw`, `lw`). Kerns and
  abbreviations lie at or below +0.005 em after punctuation (`U.S`, `D.C`, 660 at 0.00) and at or
  below 0.059 em between letters (`r|i` +0.045, the largest `Er|itrea` 0.0586). The word-space mode
  starts at 0.075 em (`U.S.|intelligence` 0.0747) and runs to 0.24 em. Only one boundary lies
  between 0.060 and 0.074 in the whole book. Before `(`: one kern at 0.000, word spaces 0.10–0.20.
  **Threshold 0.066 em**, the midpoint between the last kern (0.0586) and the first word space (0.0747).
- **Before `A T V W Y` or an opening quote, after a lowercase letter or punctuation** (`lv`, `Pv`,
  `Pq`, `Qv`, `Qq`). The space's kern falls into the gap. Lowercase before these capitals never
  occurs with a zero or negative adjustment. After punctuation, abbreviations and initials lie at or
  below +0.001 em (`N.|Y.` −0.0004 ×15, `W.|W.` −0.0002), while sentence spaces continue from
  +0.0027 (`nephew,|Yousef`). **Threshold 0.005 em.** Below it the two modes overlap: about 300
  boundaries at −0.03 to +0.005 em after punctuation, mostly sentence spaces (`followed.|The` −0.007)
  with the abbreviations among them, stay unrepaired.
- **Between capitals, and after a digit, before an overhanging capital.** The narrow mode is kerning
  in other books (Replay Clocks' Libertine small caps `WI|TH`, `N|TP` +0.037, `H|VC` +0.023). This
  book's own word spaces there are 0.075–0.084 (`DCI|Tenet`, `WTC|Victim`), so the 0.066 letter
  threshold applies.
- **Not a word start** (`lo`: `f|’` +0.125, `Po`: ellipsis dots +0.11–0.14): never repaired.

Note references (`tools/notes.py`): raised digit shows before larger text have gaps of 0.114–0.39 em
of their own size. The only near-zero gaps are small-caps `A|.M.`, whose right side is punctuation.
The same 0.066 em threshold applies, in the reference's size.

PDFKit's own threshold is about 0.14 em, so the reader only ever adds spaces in 0.005–0.14 em
(and to 0.39 for references).

## Rule (`Sources/PDFReflowLib/NativeSpacingReader.swift`)

1. **Character and word spacing are modelled.** `Tc` and `Tw` are part of the saved text state
   (`q`/`Q`). A glyph's advance is width × size + Tc, plus Tw on code 32. The measured end of a show
   excludes the spacing after its last glyph. A `Tc` or `Tw` beyond 1000 units still disqualifies the
   page, as do `Ts`, `Tr`, `Tz`, font-setting `gs`, `'`, `"`, inline images and unpositioned shows.
   Type3 space removal (DGA's labels, `native-label-spacing`) ignores any show with character or word
   spacing.
2. **In-show word spaces** (`Evidence.wordSpaces`). The reader considers a boundary between two
   non-empty strings of one TJ array, with at least one nonzero adjustment between them, only in a
   show that sets nonzero `Tc` or `Tw`. Its gap is min(adjustment, adjustment + Tc) in em.
   `sameFontWordSpace(before:left:right:gap:)` accepts it when:
   - the left character ends a word (a letter, a digit, `. , ; : ? !`, `” ’ )`);
   - the right character starts one (a letter, a digit, `“ ‘ (`);
   - neither side is a mathematical alphanumeric or letterlike symbol (U+1D400–1D7FF, U+2100–214F);
   - it is not a period or colon between digits;
   - the gap is at most 1 em and at least 0.005 em (an overhanging capital or opening quote after a
     lowercase letter or punctuation) or 0.066 em (otherwise).

   A boundary is dropped when it sits beside a one-glyph string whose other side is also a word gap
   (letter-spaced `C H A P`).
3. **Note references** (`noteReference`): a show of one to four digits, at most 0.8 of the next
   show's size and raised by 0.15–0.6 of it, followed by a show starting with a capital or `“` at a
   gap of 0.066–1 em of the reference's size.
4. **The exact-line rule is unchanged.** All shows in the line's rectangle must belong to it alone and
   spell PDFKit's line exactly apart from PDFKit's own spaces. One addition: a trailing source space
   glyph that PDFKit trims is allowed. Distiller ends lines with one; without this, 5,241 of the
   6,755 repaired 9/11 lines were refused. `apply` now also runs the insertion path for a single show.

The #43 font-change rule, the WinAnsi decoding (#110) and the public API are unchanged.

### Why the producer condition (nonzero `Tc` or `Tw`)

The first builds, without this condition and without the mathematical and capital guards, inserted
spaces in three other books. Every one was spurious (apart from a few table fusions noted below) and
every one was in a show with `Tc` = `Tw` = 0:

- **Replay Clocks (pdfTeX), 217 spaces.** Math italic kerns and italic corrections (`ℎ𝑙𝑐. 𝑓`,
  `𝑟 𝑒𝑐𝑒𝑖𝑣𝑒`) and Libertine small-caps kerns (`IN TRODUCTION`, `WI TH`). The mathematical and
  capital guards alone removed all 217.
- **NOAA (InDesign, Lora), 33 spaces.** Lora kerns `.|A` by a constant +0.027 em inside initials
  (`E.A.`, `J.M.` are set closed) and in DOIs (`NCA5.2023.A1`).
- **Wallace (Ghostscript), 439 spaces.** 432 were juxtaposed CMMI variables `x|y`, `a|b`, and 7
  followed math punctuation (`LCD: 3−`). The set also held a few genuine same-font table fusions,
  `to|both sides so|variable` (the #110 defect 2).

These producers write a word space as a space glyph or a full-width adjustment, which PDFKit keeps,
so their narrow gaps are kerns. In 9/11, all but 4 of the boundaries that PDFKit drops at gaps above
+0.003 em lie in shows with nonzero `Tc` or `Tw`. The condition removed NOAA's 33 and Wallace's 439
insertions and none of 9/11's.

A final `=` matched against PDFKit's `-` was tried and removed. PDFKit keeps 9/11's `=` line-end
glyph as `=` (`their break=`), and the equivalence never fired.

## Every inserted space, all English books

`tools/survey-book.sh` diffs product `NativeTextReader` lines between baseline and candidate
`survey-lines` builds on `9803329`. `tools/insertions.py` lists and classifies every inserted space.

| Book | Lines | Changed lines | Inserted spaces |
| --- | ---: | ---: | ---: |
| 9/11 | 25,984 | 6,755 | **11,700**: 10,998 after punctuation, 682 letter before capital or quote, 19 digit before capital (16 references plus `5 WTC`, `7 WTC`, `9/11 Tapes`), 1 other (`knew that`) |
| Wallace, FAA, Fed, Loper Bright, Replay Clocks, DGA, Our Flag, USGS, Census RRS, NBS JRES, CDC, CIA Blue Book, Warren, NOAA | 27,789; 32,250; 4,399; 4,389; 1,008; 388; 1,530; 132; 859; 598; 535; 31,831; 48,023; 77,882 | 0 | 0 |

All inserted spaces are in `instances/911-insertions.tsv.gz`. Among 9/11's insertions, 658 are a comma
between digits (`11, 2001`), 217 follow a one-capital abbreviation or initial (`U.S. Attorney`,
`H. W. Bush`), 17 follow an ellipsis, 1,062 precede an opening quote and 15 precede `(`
(`tools/risk.py`).

### Counts per class before and after

Independent of the rule, with #110's pdftotext-based fusion detector (`missing-spaces-survey/tools/fused.py`)
on 9/11's product lines, classified by `tools/classes.py`:

| Class | Baseline | Candidate |
| --- | ---: | ---: |
| after punctuation (`forward.We`, `Towers,the`) | 5,066 | 41 |
| letter before capital (`NewYork`, `theTaliban`) | 82 | 0 |
| note reference (`went.8They`) | 16 | 0 |
| letter-spaced small caps (`Tue sday`; pdftotext artefact, not a defect) | 15 | 14 |
| other (pdftotext splits at `’s`, `”`) | 59 | 54 |

In the product lines, `NewYork` 101 → 0, `went.8They` 1 → 0, and lowercase-punctuation-letter
fusions 6,547 → 749 (most of the rest are real abbreviations and URLs). In the EPUB (lane below),
`NewYork` 101 → 0, `forward.We` 1 → 0, `Towers,the` 1 → 0, and the issue's 16 references 16 → 0.
Lowercase-punctuation-capital runs fall 4,275 → 436, and lowercase `, ; :` lowercase runs 1,976 → 11.

The 41 detector residuals after punctuation (`instances/911-residual-fused-cand.tsv`) and about 417 of
the 436 EPUB runs are:

- **Sentence spaces absorbed entirely by an overhanging capital's kern** (`casualties.The`,
  `FAA:Yes.`, `Berger,Tenet`). Their gap, −0.03 to +0.005 em, overlaps abbreviations and initials,
  so no gap threshold can separate them.
- **Lines the exact-line rule refuses**: multi-line shows in the appendix (`(a.k.a.Abu`), and
  `Encyclopedia.Six`.
- **Pdftotext noise**: `...`, `C.F.R.§`.

In the adjustment table on the candidate (`instances/911-adjustment-groups-cand.tsv`), every target
cell from +0.01 (overhang) or 0.07 (other) up is spaced, except 7 boundaries on refused lines. Every
kern cell is unchanged.

## Review

Every row below was rendered with `tools/review.py`: 200-dpi strips of the two words beside the space,
located in `mutool trace` glyphs. Doubtful strips were re-rendered at 500–600 dpi. Rows and verdicts
are in `instances/911-reviewed-insertions.tsv`: 713 rows, 672 distinct insertions.

| Set | Rows | Spurious |
| --- | ---: | ---: |
| random sample (seed 119, drawn before `(` was added; all rows still in the final set) | 125 | 0 |
| every insertion after a one-capital abbreviation or initial | 217 | 0 |
| every insertion after an ellipsis | 17 | 0 |
| digit-comma-digit sample | 50 | 0 |
| opening-quote sample | 50 | 0 |
| lowercase-before-capital sample | 50 | 0 |
| every insertion on the six fixture pages (19, 45, 48, 57, 234, 489) | 117 | 0 |
| every insertion before `(` | 15 | 0 |
| every insertion behind a contract rewrite (below) | 51 | 0 |
| zoom checks (`went.8 They`, `5 WTC`, `New York`, `H. W.`, `M. W.`, `G. and`, `L. to`) | 21 | 0 |

Narrow cases were confirmed at high resolution. `New|York` and `5|WTC` show a gap clearly wider than
the letter spacing, and `H. W. Bush` has a space after `H.` as wide as the one after `W.`. By
contrast `A.Q. Khan`, `H.W. Bush` (page 358) and the `N.Y.` inside `(S.D. N.Y.)` are set closed in
the source, and those stay closed. No other book has any insertion to review.

## Tests (`Tests/PDFReflowLibTests/NativeSpacingTests.swift`)

Reproducer fixture: `fixtures/911-text-operators.json`, built by `tools/fixture.py` and
`tools/native-lines.swift`. It holds the unmodified font dictionaries (Widths, decoded ToUnicode),
ExtGState entries and full decoded content streams for 9/11 pages 19, 45, 48, 57, 234 and 489. Bytes
above 127 in string operands are written as octal escapes. It also holds PDFKit's native lines and
bounds.

| Test | `9803329` baseline reader | Candidate |
| --- | --- | --- |
| `nineElevenSameFontWordSpacesAreRestoredOnSourcePages`: each page rebuilt from source operators; the 117 reviewed insertions per page. Negative controls on the same pages: small caps with `Tc`, `9:34`, `staff’s`, ellipsis dots, `(S.D. N.Y.)`, `Los Angeles` space glyph, and `dispute.The` below the threshold. With every `Tc`/`Tw` zeroed, only `went.8 They` remains | fails 7 checks (every page and the zeroed control) | passes |
| `sameFontWordSpaceSeparatesTheMeasuredGapModes`: both thresholds at their measured edges, capitals, decimals and times, comma between digits, ellipsis, `f’`, dashes, mathematical letters, non-finite and >1 em | does not compile (new API) | passes |
| `tjAdjustmentsInJustifiedShowsRestoreWordSpacesAndLetterSpacingStaysJoined`: exact-line matching, trimmed trailing space, `Tc` cancellation, letter-spaced runs, the producer condition, empty strings | does not compile | passes |
| `noteReferenceBeforeACapitalRestoresItsWordSpaceOnly`: gap, raise, lowercase continuation, size ratio, non-digits | does not compile | passes |
| updated: `unsupportedSourceSpacingStateFallsBack` (Type3 removal ignores `Tc`/`Tw`; >1000 disqualifies), `graphicsStateWithoutAFontKeepsEvidenceAndAnyOtherDisqualifies` (ends with `Tc`/`Tw`), `rotatedShowsAndFormsLeaveUprightEvidenceIntact` | 6 checks fail | pass |

Mutation controls (`tools/negative-controls.sh`, `tools/mutate.py`; the reader is restored after each):

| Mutation | Failing tests |
| --- | --- |
| `no-gate` (read shows without character or word spacing) | fixture (the zeroed control), tj |
| `no-overhang` (letter threshold before overhanging capitals and quotes) | unit, fixture (5 pages) |
| `no-letterspace` | tj (2) |
| `no-math` | unit |
| `no-trailing` (refuse a trailing source space) | tj, fixture (6 pages) |
| `no-note` | note (2), fixture (2) |

Positive controls, unchanged and passing: `sourceFontBoundariesRestoreReplayClocksWordSpaces` (#43),
`wallaceDigitBeforeTextFontRestoresItsWordSpaceAndMathStaysJoined` (#110),
`sourceType3KerningRepairsOnlyTheTwoDgaLabelSpaces`, and the other Type3 label tests.

## Corpus lane and contract

`tools/lane.sh <scratch> <case> base|cand` runs `tools/run_corpus_regressions.py` (EPUBCheck,
environment probe, host terminal). `tools/compare.sh` runs
`tools/compare_conversion_runs.py --allow-different-converters`. The summaries are in `lane-summaries/`.

The 9/11 contract (`corpus/regressions.json`, `gpo-911-2004`) held 28 phrases that spelled the fused
text (`40.The 56 passengers`, `Pearl Harbor:Warning`, `Khallad,Apr. 5`). `tools/contract-spaces.py`
rewrites a phrase only when three conditions hold:

- the candidate EPUB carries it with inserted spaces and nothing else changed (on the phrase's page or
  the next; for a note link, in the linked note on `notePage`);
- the baseline EPUB carries the old phrase;
- the baseline lacks the new phrase.

All 28 rewrites passed those conditions, and all 51 underlying insertions were reviewed on renders.

| Case | Content checks | Baseline | Candidate | compare_conversion_runs |
| --- | ---: | --- | --- | --- |
| gpo-911-2004 | 209 | **fails the 27 rewritten checks** (negative control) | pass | 557 pages change, text only (below); 9 navigation pages (headings `3.3 . . . AND IN THE …`); `imageCount` 141 → 136; 5 `uncertainHyphen` and 3 `imageRegion` warnings gone; no OCR or marker change; same Vision programs |
| wallace-algebra-2010 | 172 | pass | pass | passed: no changes |
| arxiv-replay-clocks-2023 | 59 | pass | pass | passed: no changes |
| faa-phak-8083-25c | 487 | pass | pass | passed: no changes |
| fed-explained-2021 | 166 | pass | pass | passed: no changes |
| scotus-loper-bright-2024 | 91 | pass | pass | passed: no changes |

EPUBCheck and the memory and progress gates passed in every run.

9/11 page text, with whitespace removed, is identical on 571 of 585 pages. The other 14 pages gain from
the spaces:

- **Five prose lines that the baseline froze as images now reflow as text** (pages 255, 299, 317, 328,
  338: `But during these drills, civilians were not directed into the stairwells, or pro=`; the base
  images were checked and hold only those lines).
- **Nine line-end hyphens now join**, because the fused neighbour no longer hides the word:
  `dismissedWest-ern` becomes `dismissed Western`, and likewise `spreadWah-habi`,
  `InformalTrans-lation`, `HijackersTime-line` (twice), `Cap-tain`, `West-ern`, `Tal-iban` and
  `Thu-mairy`.

The same lanes, compares and line survey on `e949bea` (binaries `98489f52…`, `30f9d22e…`, 23 contract
rewrites before #11 added checks) gave the same results.

## Verification

- `swift test`: 567 tests pass on `9803329` (563 plus 4).
- `scripts/check-all.sh --fast` on `9803329`: exit 0. It ran 567 Swift tests, 213 Python tests, 8/8
  fresh concurrency processes, 6 fixture conversions, 13 policy conversions with 22
  rejection/cleanup cases, and 6 byte-identical repeat conversions.
- Line survey of all 15 English PDFs and the six lanes: above.

## Limits

- **Sentence spaces fully absorbed by an overhanging capital's kern** (about 300 boundaries, about 400
  EPUB runs such as `casualties.The`) stay fused. Their gaps coincide with abbreviations and initials.
  Only a character rule could separate them, and that is outside this measured rule.
- **Lines whose shows span two PDFKit lines** (appendix lists, `(a.k.a.`) are refused by the
  exact-line rule.
- **Books without character or word spacing** are not read for in-show spaces at all. That includes
  Wallace's genuine same-font table fusions (`toboth sides`), which remain #110's defect 2.

## Defects to file

1. **9/11: sentence spaces absorbed by kerning before T, V, W, Y stay fused** (about 400 in the EPUB:
   `casualties.The`, `system.We`, `FAA:Yes.`, `Berger,Tenet`). The TJ adjustment is zero or negative,
   so no gap evidence exists. A repair would need a character model (lowercase or `:` before an
   overhanging capital, excluding abbreviations), not geometry.
2. **9/11: prose lines preserved as images in the baseline** (5 lines on pages 255, 299, 317, 328,
   338). They were fixed here only as a side effect of the spaces, so the crop logic is sensitive to
   fused prose. Worth a check in the crop-seeding work for other books with fused text.
3. **Wallace: same-font table fusions** (`toboth sides sovariableis`): still #110 defect 2, and outside
   this rule's producer condition.

The `=` line-end glyph that 9/11 draws for its hyphen (`Han= jour`, 934 in the EPUB) is being handled
in #126 and is not refiled.
