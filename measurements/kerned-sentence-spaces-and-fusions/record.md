# Kerned sentence spaces (#128) and remaining fusions (#120)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, Xcode 27.0, release CLIs. Work began on
`e002972` and was carried by fast-forward onto `458a2e9`, `be34d39`, `a295f33` and `0fa3057`. Every number
below was measured on `0fa3057` unless a section says otherwise. (The 9/11 line survey is identical on
`a295f33` and `0fa3057`, since #125 changes styles only.)

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline CLI | `0fa3057` (this worktree with the reader at HEAD), `swift build -c release` | `f6656611…` |
| candidate CLI | this change on `0fa3057` | `b21f822f…` |
| `survey-lines` (base, cand) | `missing-spaces-survey/tools/build.sh <tree>` | — |

No source PDF, EPUB or render is committed. Lane outputs, renders and line dumps were deleted after
review. `tools/` holds every script used; paths below are relative to this directory.

## #128: sentence spaces a kern absorbs entirely

### Diagnosis

`same-font-word-spaces/tools/shows.py` on all 585 pages of `GPO-911REPORT.pdf` gives 1,357 boundaries
between `. , ; : ? ! ” ’ )` and a capital or opening quote, inside one show with no space glyph, at
min(adjustment, adjustment + Tc) below #119's 0.005 em threshold (`tools/pc.py`). 1,080 carry an
adjustment (−0.125 to +0.005 em; the mode is −0.017 to −0.021 em, the kern before an overhanging T, V,
W or Y), and 277 carry none at all (`unharmed.We`, a glyph set straight after the period). Renders
(`probe` strips at 400 dpi) show these set visually closed: `casualties.The`, `Berger,Tenet`,
`unharmed.We`. Only side bearings separate them. So is `10.August`, which the corpus contract pins as
closed. `FAA:|Yes.` is a different case, a semibold speaker label followed by a Bembo show 0.10 em
later, below the #43 font-change rule's 0.15 em.

Gap cannot separate these from abbreviations: `U.|S.` (631 closed), `N.|Y.`, `D.|C.` lie in the same
band. The book's own spacing decides the character rule (`tools/evidence.py`: every boundary after a
period before a capital, by the left word's final segment and the character after the capital,
counted as space glyph / measured adjustment ≥ 0.005 em / closed):

| Left segment → right | Space glyph | Measured | Closed | Reading |
| --- | ---: | ---: | ---: | --- |
| word of 3+ letters → capitalized word | 2,855 | 2,791 | 331 | sentence spaces; the closed ones are the defect |
| initial (1 letter) → capitalized word | 146 | 84 | 6 | spaced (`Thomas H.|Kean`); closed ones are fusions (`v.|Yousef`, `Y.|Yun`) |
| `U.S.`, `D.C.` → capitalized word | 76 | 81 | 0 | spaced (`U.S.|Army`) |
| initial → capital followed by a period | 3 | 7 | 755 | closed abbreviations (`U.|S.`, `D.|C.`, `N.|Y.`) |
| `…U.|S.`, `C.F.|R.` (internal period) → capital + period | 9 | 1 | 26 | closed |
| digits at a show start → capital | — | — | 14 | note and list numbers (`21.|While`, `10.|August`) |

An abbreviation stoplist is therefore not supported by the book: every abbreviation it uses (`v.`,
`Asst.`, `No.`, `p.`, `Sept.`) takes a space before a capitalized word. The only closed form is a
capital that continues an abbreviation. Of the 1,357 candidates, the prototype classifier
(`tools/classify.py`) excludes 781 capital-plus-period continuations, 50 apostrophes (`QAEDA’|S`,
`O’|Neill`, `L’|Houssaine`), 7 ellipses, 2 URLs (`print.php3?|ReportID`) and 26 numbers. About 460
sentence boundaries remain. Tw adds no separating evidence: both abbreviations and absorbed sentence
spaces lack a space glyph in the same justified shows.

### Rule (`Sources/PDFReflowLib/NativeSpacingReader.swift`, `sentenceSpace`)

Only in shows with nonzero `Tc` or `Tw` (#119's producer condition), at a glyph boundary that is not
already a word space, with gap = the adjustment's min(adj, adj + Tc), or min(0, Tc) with no
adjustment. A boundary is a sentence space when:

- the word before it (back to a space glyph or a word space) ends with `. , ; : ? !`, optionally
  followed by `” ’ ) ]`, and the punctuation follows a letter, a digit, or a closing `) ] ” ’`
  (`(OMB).|They`); a word of only closers (`)).`) is not;
- the word after it starts with a capital that a period does not follow, or with `“ ‘` before a letter
  or digit;
- neither side is a mathematical letter; the word holds no `/ @ = \` or `www`;
- an initial (a capital and at most one more letter, then `.`) is not followed by a capitalized
  abbreviation of at most four letters ending in a period (Our Flag's title page `H.Doc. 108-97`,
  and so 9/11's `S.Ct.`);
- a period does not end a number that begins its show (`10.|August`, `21.|While`);
- the gap is −0.15 to 1 em.

Two extensions reach the same class across shows:

- **Cross-show** (`missingSpaces`): two shows on one baseline (sizes within 0.8), either with
  `Tc`/`Tw`, gap = (origin − previous end) / size (`FAA:|Yes.`, `moves.|Call` at 0.126 em).
- **Show edges**: a boundary whose word before reaches the show's start, or whose capital's word
  reaches its end, is kept as a candidate with its gap (`Evidence.sentenceCandidates`) and decided in
  `missingSpaces` over the line's characters. Word gaps between shows (0.1 em, or a baseline change)
  are breaks there. Examples: `Encyclopedia|.Six` (italic title, roman period), `June,T|enet` (a show
  split inside a name), `Newsweek|,Nov.`.

`sameFontWordSpace` gains an `after` character. A chained initial (a capital, `.`, then a capital
followed by `.`) takes the 0.066 em letter threshold instead of the 0.005 em overhang threshold.
Without it, NOAA's newly readable pages (below) inserted 8 spaces into closed initials (`C.A. Morgan`),
where Lora kerns `.|A` by +0.027 em on lines with `Tw` −0.002 em. The cost is 2 of #119's reviewed 9/11
insertions: `George H.W. Bush` on pages 93 and 216 (0.015 and 0.029 em) returns to closed, the form the
source itself sets on page 358.

### The coordinator's `JointTer-rorism`, `inVic-toria`, `toVir-ginia`, `delayedTal-iban`

These are not missing on `a295f33` or later. The product lines read `FBI Joint Ter=`, `station in Vic=`,
`to Vir=` and `delayed Tal=` on every extraction path: plain, with column joints, and with
borderless-table ink (`tools/pipelines.swift`). The gaps are measured (0.083, 0.032, 0.072 and 0.108 em)
and #119 restores them. The `a295f33` EPUB reads `in Victoria`, `to Virginia` and `delayed Taliban`
with no `uncertainHyphen` warning on pages 196, 205, 239 or 270. Page 205's bullet is not reflowed text.
The `equals-hyphen-and-codes` record's list predates its #119 merge.

## #120

- **(c) Replay Clocks page 10: fixed.** The page's only disqualifier is its reference list,
  `[([8])]TJ 0 g 0 G [-571(D)29(.)…]TJ`, a show that continues the text cursor. The reader now keeps
  the text matrix (Tm) apart from the line matrix (Tlm). After a show with complete widths it advances
  Tm by the full advance: widths, Tc, Tw on code 32, and every adjustment including a trailing one.
  An unpositioned show after that is placed there; after a show without complete widths it still
  disqualifies the page, as do `'`, `"` and a show before any positioning. Evidence origins and
  measured ends are unchanged for positioned shows. Replay gains 12 font-change spaces on page 10
  (`𝑒 must`, `E provides`, `𝑅𝑒𝑝𝐶𝑙 to`, `𝑗 and`). In every other English book this reads more pages,
  but only NOAA's 8 chained initials (fixed above) and FAA's table (b) changed.
- **(b) FAA page 458: fixed in product lines; no EPUB effect.** The Challenger 605 table sets its
  column gaps as character spacing inside two-glyph shows: `(68)Tj 1.465 Tc -1.465 Tw (52)Tj` draws
  `1,685 2,599`, and `(52)` continues the cursor (so (c) made the page readable). FAA-wide
  (`tools/shows.py` with an ASCII fallback), digit and letter character spacing inside strings is
  bimodal: 685 boundaries at 0.1–0.2 em (letter-spacing: `2000`, `Atmospheric`) and 21 at 0.59–7.3 em,
  all column gaps on pages 27, 458 and 459. Rule: a single-string show of exactly two glyphs whose Tc
  is 0.5–10 em has a word space between them if the characters pass #119's word classes. That gives
  8 insertions (`0 3,550`, `11,980 16,820`, `290 Speed`, `FL310 FL330`, `M0.82 M0.80`). `1,6852,599`
  itself stays fused: its row's `[(\(NM\))-4632 (0)]TJ` spans two PDFKit lines, and the exact-line
  rule refuses it. Both pages are preserved figure crops in the EPUB, whose text is unchanged.
- **(a) Wallace: partly fixed.** Math punctuation before prose at a font change (`6)when`,
  `(subtract)in`, `1);use`, `Second:m`): the #43 rule (different fonts, ≥ 0.15 em, one baseline) now
  also accepts `) ] , ; :` on the left before a letter, when the punctuation follows a non-space
  character of its own show or its one-character show follows the previous one without a word gap
  (a space, or 0.15 em on one baseline; a subscript's shift is not a gap). That gives Wallace 103 and
  Replay Clocks 30 insertions. Two correct ones are lost to the word-gap condition (`Use ) for`,
  `hb𝑓) and`); it keeps the #43 control `event ,must` joined.
  **Left:**
  - The **95 digit-then-word fusions** on radical and side-by-side derivation lines would need partial
    line matching. The exact-line rule accepts a line only when all its shows spell it; accepting a
    matched sub-span risks misassigning shows across the overlapping line rectangles that cause the
    refusals. Not bounded.
  - **Same-font tight tables** (`toboth sides`, pages 82, 154, 231, 373) are Ghostscript output with
    Tc = Tw = 0, the same producer whose CMMI kerns (`x|y`) gave #119's 439 spurious insertions. No gap
    separates them without a table model. Not bounded.

## Every inserted space, all English books

`tools/survey-all.sh` (`same-font-word-spaces/tools/survey-book.sh` and `insertions.py`) diffs product
`NativeTextReader` lines between base and candidate `survey-lines` on `0fa3057`. Full lists:
`instances/911-insertions.tsv.gz`, `wallace-insertions.tsv`, `replay-insertions.tsv`,
`faa-insertions.tsv`.

| Book | Lines | Changed lines | Inserted spaces |
| --- | ---: | ---: | ---: |
| 9/11 | 25,984 | 501 | **517** (all punctuation class) + 2 lines where #119's `H. W.` returns to `H.W.` |
| Wallace | 27,789 | 97 | **103**, math punctuation at a font change |
| Replay Clocks | 1,008 | 34 | **42**: 12 on page 10 (c), 30 math punctuation (a) |
| FAA | 32,250 | 6 | **8**, character-spacing column gaps (b) |
| Fed, Loper Bright, DGA, Our Flag, USGS, Census RRS, NBS JRES, CDC, CIA Blue Book, Warren, NOAA | 4,399; 4,389; 388; 1,530; 132; 859; 598; 535; 31,831; 48,023; 77,882 | 0 | 0 |

9/11's 517 by left character: `.` 399, `,` 79, `:` 22, `;` 13, `”` 4 (`.”` and `,”`). Eleven of
them are show-edge insertions. Unusual left words: initials before a name (`Peter F. Verga`,
`William Y. Yun`), `v.` ×3 (`United States v. Yousef`), `U.S. VISIT`, `...Okay. Push` and
`89. Ibid. The`.

### Counts before and after

With `tools/fusions.py` (every `word[.,;:?!][”’)\]]*[A-Z“‘]` run, classified by the rule's exclusions):

| 9/11 | Baseline | Candidate |
| --- | ---: | ---: |
| product lines, sentence class | 533 | 17 |
| product lines, `initial` class | 802 | 804 |
| EPUB text, sentence class (`casualties.The`) | **521** | **15** |
| EPUB `initial` class (`U.S.`, `D.C.`: not defects) | 791 | 793 (the two `H.W.`) |
| EPUB `casualties.The` or `FAA:Yes` | 3 | 0 |

The 15 EPUB residuals are:

- 11 lines the exact-line rule refuses (#119's limit): 10 appendix `(a.k.a.Abu …` and `(a.k.a. …,Waleed`
  lines, plus `arrived.Hawsawi`, `attack.At` and `Jordanian;Virginia`. The reader has the space
  (`wordSpaces` or `sentenceSpaces`), but the line's shows do not spell it.
- `123 S.Ct.`: the initial-abbreviation exclusion.
- `Director,Federal` in a table cell.

Wallace EPUB: `(subtract)in` 1 → 0. Replay EPUB page 10: `𝑒must`, `Eprovides` and `≈Etime` → spaced.

## Review

Every row is in `instances/reviewed-insertions.tsv` (set, row, page, pair, verdict, and whether it is
in the final lists). Strips are `same-font-word-spaces/tools/review.py` renders at 200–400 dpi.

| Set | Rows | Spurious |
| --- | ---: | ---: |
| 9/11 random sample of period insertions (seed 128) | 125 | 0 |
| 9/11 every non-period insertion (`, : ; ”`) | 111 | 0 |
| 9/11 every show-edge insertion | 11 | 0 |
| 9/11 every new insertion on the six fixture pages | 15 | 0 |
| 9/11 every unusual left word (`F.`, `Y.`, `v.`, `S.`, `U.S.`, `Ibid.`, `...Okay.`, `303(b).`, times), read on their lines; 7 also rendered above | 18 | 0 (`S. Ct.` later excluded as a closed form) |
| FAA every insertion | 8 | 0 |
| Replay every page-10 insertion | 12 | 0 |
| Replay every math-punctuation insertion | 31 | 0 (`hb𝑓) and` later lost to the word-gap condition) |
| Wallace math-punctuation sample (seed 120) | 50 | 0 |
| Our Flag, first candidate | 1 | **1** (`H.Doc.` is set closed; fixed by the abbreviation exclusion) |
| NOAA, after (c) made pages readable | 8 | **8** (`C.A.`, `B.A.`, `J.A.` closed initials; fixed by the chained-initial threshold) |

In 9/11 the source sets these boundaries visually closed, so the review asks whether the text needs a
space, not whether ink shows one. Every 9/11 insertion separates two sentences, clauses, list items
or a citation's parts. `U.S. VISIT` (page 582) matches the book's own `US VISIT` elsewhere. Three
`transcript, Vice` strips and the `Newsweek, Nov.` strips were located at an already spaced occurrence
on the same page (labelled `ambiguous`); the pattern is identical. Wallace, Replay and FAA strips all
show a visible space.

## Tests (`Tests/PDFReflowLibTests/NativeSpacingTests.swift`)

| Test | Checks |
| --- | --- |
| updated `nineElevenSameFontWordSpacesAreRestoredOnSourcePages` | the fixture pages' insertion lists gain the 15 reviewed #128 insertions; `dispute.The` turns from a negative into a positive control; new control: the only punctuation-capital runs left on the six pages are `A.M.`, `D.C.`, `O.K.`, `U.S.`, `S.D.`, `N.Y.` and the two ellipses |
| `sentenceSpaceSeparatesSentencesFromInitialsAbbreviationsAndAddresses` | the predicate on measured book forms: positives, and closed forms (`U.|S.`, `H.|Doc.`, `O’|Neill`, ellipses, addresses, list numbers, gaps) |
| `kernedSentenceSpacesAreRestoredInsideAndAcrossJustifiedShows` | adjusted and unadjusted boundaries, closed forms, producer condition, speaker label (lowercase, size and producer controls), italic title and split-show edges, word-gap control |
| `chainedInitialsTakeTheLetterThresholdBeforeAnOverhangingCapital` | NOAA `C.|A.` closed, `ic.|A` spaced, `H.|W.` vs `M.|W.` thresholds |
| `showsThatContinueTheTextCursorAreReadFromTheMeasuredAdvance` | origins and ends after a trailing adjustment, Tc advance, `Td` relative to the line, unmeasured-show / `'` / unpositioned controls |
| `characterSpacingColumnGapsSplitTwoGlyphTableCells` | FAA's `(52)` at 1.465 and 0.756 em; 0.2 em, three glyphs, 10.5 em controls |
| `mathPunctuationClosingAFormulaBeforeProseAtAFontChangeRestoresItsSpace` | `)` and `;` spaced; 0.14 em, digit, word gap, own-show space, period controls |

On the `0fa3057` reader the six new tests do not compile (new API), and the updated fixture test fails
on 5 pages and the `dispute. The` control.

Mutation controls (`tools/mutate.py`; the reader is restored after each run and was byte-compared
afterwards):

| Mutation | Failing tests |
| --- | --- |
| `no-initial` (a capital followed by a period no longer blocks) | sentence unit, kerned, chained, fixture |
| `no-abbreviation` | sentence unit, kerned |
| `no-closer-check` | sentence unit |
| `no-list-number` | sentence unit, kerned |
| `no-edge` | kerned |
| `no-cross-show` | kerned, fixture |
| `no-continuation` | continuation, column, kerned |
| `no-column` | column |
| `no-two-glyph` | column |
| `no-chained` | chained |
| `no-word-gap` | math punctuation, `fontChangeGapsBelowWordSizeOrOutsideWordsStayJoined` |
| `no-math-punctuation` | math punctuation |

Positive controls unchanged and passing: `sourceFontBoundariesRestoreReplayClocksWordSpaces`,
`wallaceDigitBeforeTextFontRestoresItsWordSpaceAndMathStaysJoined`,
`tjAdjustmentsInJustifiedShowsRestoreWordSpacesAndLetterSpacingStaysJoined`,
`noteReferenceBeforeACapitalRestoresItsWordSpaceOnly`, the Type3 label tests and
`unsupportedSourceSpacingStateFallsBack` (its unpositioned Type3 show still disqualifies: no widths).

## Corpus lane and contract

`tools/lane.sh <scratch> <case> base|cand` and `tools/compare.sh` (`compare_conversion_runs.py
--allow-different-converters`); summaries in `lane-summaries/`. `tools/add-contract.py` adds a phrase only
when the candidate EPUB has it and not the fused form, and the baseline has the fused form and not the
phrase. Added: 9/11 pages 134 (`10,000 casualties. The CIA`), 193 (`Encyclopedia. Six of`), 312
(`relatively unharmed. We know`); Wallace page 24 (`Negative (subtract) in middle`); Replay page 10
(`then 𝑒 must occur before 𝑓`, `observe that E provides one way`), each with its fused form as
`absentText`. 9/11 `FAA: Yes.` was refused, because the `0fa3057` baseline splits speaker turns.

| Case | Content checks | Baseline | Candidate | compare_conversion_runs |
| --- | ---: | --- | --- | --- |
| gpo-911-2004 | 242 | **fails exactly the 6 new checks** | pass | 365 pages change; all 4,663 blocks identical once whitespace is removed (381 differ in whitespace); fields text, paragraphs, markup, noterefs and scripts (their `before` context); images, navigation, OCR, markers and report unchanged |
| wallace-algebra-2010 | 180 | **fails exactly the 2 new checks** | pass | 19 pages, 22 blocks; every XHTML file identical or whitespace-only; images, navigation, markers unchanged |
| arxiv-replay-clocks-2023 | 63 | **fails exactly the 4 new checks** | pass | 7 pages, 19 blocks; whitespace-only; images, navigation, markers unchanged |
| faa-phak-8083-25c | 487 | pass | pass | passed: no changes (pages 458–459 are image crops) |
| fed-explained-2021 | 166 | pass | pass | passed: no changes |
| scotus-loper-bright-2024 | 91 | pass | pass | passed: no changes |

The comparisons ran before the contract rows were added (same binaries). EPUBCheck, progress and
memory gates passed in every run. `sameVisionPrograms` differs only because the executable names differ
(`base`, `cand`); no OCR page changed.

## Verification

- `swift test`: 611 tests pass on `0fa3057` plus this change (605 plus 6).
- `scripts/check-all.sh --fast`: exit 0. It ran 611 Swift tests, 214 Python tests, fixture, policy (13
  conversions, 22 rejection/cleanup cases) and repeat conversions (identical bytes). The real-document
  memory gate is skipped under `--fast`.
- Line survey of all 15 English PDFs and the six lanes: above.

## Limits

- Lines the exact-line rule refuses keep their fusions: 9/11's appendix `(a.k.a.` lines and 3 prose
  lines, FAA's `1,6852,599` row, and Wallace's 95 digit-word fusions.
- An ellipsis before a capital (`House....Six`, `...|Okay`) and `S.Ct.` stay closed by design.
- A sentence ending in an initial before a short capitalized abbreviation (`… in section H.|Doc. …`)
  would stay fused; none occurs in the corpus.
- The show-edge completion treats a transition under 0.1 em on one baseline as the same word.

## Defects to file

1. **Exact-line refusals hide repairs the reader already has** (9/11 appendix `(a.k.a.Abu`, 10 EPUB
   runs; `arrived.Hawsawi`, `attack.At`, `Jordanian;Virginia`; FAA `1,6852,599`; Wallace's 95 digit-word
   fusions). A partial match that repairs only the shows owning a sub-span of the line would recover
   them. Needs its own ownership analysis.
2. **Wallace same-font tight table text** (`toboth sides`, pages 82, 154, 231, 373): Tc = Tw = 0 output
   whose gaps overlap CMMI kerns. Needs a table-region signal, not a gap threshold.
3. **9/11 ellipsis before a sentence** (`House....Six`, `...Okay`): closed by design here, about 6 EPUB runs.
