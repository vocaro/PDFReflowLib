# Math spaces beside operators (#188) and spaces after ligatures (#189)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, Xcode 27.0, release CLIs.
Work began on `56e70e2` merged with `f3840f4`; every number below was measured on that tree
(baseline) and on this change (candidate). Date 2026-09-17.

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline CLI | `f3840f4` merge, `swift build -c release`, launched as `base/pdf-reflow` | `6150e1cc…` |
| candidate CLI | this change, launched as `cand/pdf-reflow` | `8992b6b1…` |
| `survey-lines` (base, cand) | `missing-spaces-survey/tools/build.sh <tree>` | — |
| `operators` probe | `tools/build.sh <tree> <out>` (this change's reader) | — |

Both converters share one executable name, so one Vision model cache (#94). No source PDF, EPUB or
render is committed; lane outputs, renders and line dumps were deleted after review. `tools/` holds
every script used, `instances/` the per-boundary and per-insertion lists, `lane-summaries/` the run
summaries and comparisons.

Both issues are in lines set by TeXmacs through Ghostscript (`CMSY10`, `CMR12`, `CMMI12` and the EC
text fonts, Tc = Tw = 0), which positions every math token with a TJ adjustment or a `Td`, never a
space glyph. The #188 issue text says LaTeX; the producer is TeXmacs.

## #189: no space is inserted after a ligature

### Survey

- **Product lines, 21 English documents** (`survey-lines` on the baseline): 225 ligature characters
  (Wallace 224, NOAA 1). Three are followed by a space and all three end a word (`oﬀ the` ×2,
  `staﬀ of`). No line splits a word at a ligature, in product text or in PDFKit's own text.
  Replay Clocks and the IEEE paper emit no ligature code point (their ToUnicode maps spell them).
- **EPUBs** (`tools/epub-ligatures.py`, baseline): Wallace 182 ligatures, 2 followed by a space
  (`oﬀ the`, `staﬀ of`), 0 split words; Census (whose decoded Cork fonts emit `ﬁ ﬀ ﬃ`, #143) 28, 0.
  Example 5 on page 8 reads `Diﬀerent signs, subtract 4− 3, …` in the baseline EPUB.
- **Gaps** (`tools/gaps.py`, all 489 Wallace pages): 1,136 boundaries after a ligature glyph
  (`ﬁ` 860, `ﬀ` 158, `ﬃ` 66, `ﬂ` 52). The 1,133 inside a word measure −0.005 to +0.017 em; the
  3 word ends measure 0.16, 0.32 and 0.48 em. The ligature's advance does not open a word-sized gap;
  the book's word spaces begin at 0.157 em (below).

So the defect does not reproduce on `f3840f4`, and the measured gaps rule out the proposed mechanism.
PDFKit already spells `ﬁ` and `ﬂ` out for Wallace's EC fonts, and emits `ﬀ` and `ﬃ` as U+FB00 and
U+FB03, which the EPUB keeps (#123).

### What a reader may have seen (not confirmed)

`tools/ligature-fonts.swift`: Charter, Times New Roman, Avenir Next and the system UI font map no
glyph to U+FB00, U+FB03 or U+FB04 (they have U+FB01 and U+FB02). CoreText draws those characters from
Lucida Grande or Helvetica Neue instead. `tools/ligature-render.swift` draws `Diﬀerent` both ways in
each family at 48 pt: the fallback glyph is visibly a different design, but the widest blank run
inside the word is the same as for the spelled-out word (3, 4, 6 and 4 px), so CoreText opens no gap.
Apple Books on the device was not tested. If the owner's `Diff erent` came from a reading font
without U+FB00, spelling `ﬀ ﬃ ﬄ` out in emitted text would remove it; that reverses #123's decision
and changes Census's and Wallace's contracts, so it is left as a follow-up.

**Nothing changed for #189.** The Wallace fixture test and contract pin `Diﬀerent` without a space.

## #188: the math space beside an operator

### What the source sets

Wallace page 7, Example 1, rendered at 200 dpi: `− 5 + ( − 3)` and `add 5 + 3`. TeXmacs sets the
unary minus as it sets the binary operator, so **the source itself prints a space after the unary
sign** (`( − 3)`), not the issue's `−5 + (−3)`. The content stream:

```
/R20 11.9552 Tf 79.9199 -30.3602 Td [(\000)175.528]TJ           CMSY10 minus, width 778
/R46 11.9552 Tf 11.2801 0 Td [(5)-162.863(+)-171.939(\()159.952]TJ   CMR12
/R20 11.9552 Tf 25.4398 0 Td [(\000)175.528]TJ
/R46 11.9552 Tf 11.2801 0 Td [(3)-2.26881(\))159.952]TJ
```

| Boundary | How | Gap (em) | PDFKit |
| --- | --- | ---: | --- |
| `−|5` | next show | 0.1655 | space |
| `5|+` | TJ adjustment | 0.1629 | **none** |
| `+|(` | TJ adjustment | 0.1719 | space |
| `(|−` | next show | 0.1601 | **none** |
| `−|3` | next show | 0.1655 | space |
| `3|)` | TJ adjustment | 0.0023 | none |

The commentary line beside it: `Same|sign` 0.157, `,|add` 0.160, `add|5` 0.169, `5|+` 0.163
(**none**), `+|3` 0.172, `,|keep` 0.160; kerns inside words −0.025 to +0.010. So every gap in these
lines is one math/word space of 0.157–0.172 em (TeX's thin space is 1/6 em), and PDFKit's own
threshold falls inside that band and depends on the fonts: `(|−` at 0.1702 em has no space on page 8
while `−|3` at 0.1655 em has one. **The kerns do not distinguish a binary operator from a unary
sign**: both carry the same thin space.

### Survey before the change

**Line classes** (`tools/classes.py` on product lines; an operator between operands, by where PDFKit's
text spaces it; occurrences and lines):

| Book | Lines | after only (`5+ 3`) | before only (`9 +4`) | both | neither | lines with an asymmetric operator |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Wallace | 27,791 | 7,614 (5,581) | 3,015 (2,546) | 4,519 (3,815) | 1,347 (1,220) | **6,843** |
| Replay Clocks | 1,008 | 68 (60) | 13 (13) | 87 (80) | 85 (56) | **70** |
| IEEE (DASC 2019) | 1,181 | 10 (10) | 8 (8) | 27 (26) | 85 (69) | **18** |

**Gaps against each book's word spaces** (`tools/gaps.py`, `tools/histogram.py`; every glyph boundary
inside a show or between shows on one baseline; `text words` are two letters or punctuation and a
letter in a text font, `math letters` have a math-italic side, the juxtaposed variables of #119):

| Wallace, gap (em) | text words | operator | math letters | after ligature |
| --- | ---: | ---: | ---: | ---: |
| < 0.02 | 244,343 | 16 | 11 | 1,132 |
| 0.02–0.066 | 5,586 | 372 | 4 | 0 |
| 0.066–0.1 | 7 | 26 | **551** | 0 |
| 0.1–0.14 | 218 | 53 | 23 | 0 |
| 0.14–0.15 | 4 | **0** | 0 | 0 |
| 0.15–0.2 | 10,836 | **24,961** | 959 | 1 |
| 0.2–0.3 | 5 | 2,351 | 276 | 0 |
| 0.3–1 | 45,648 | 1,554 | 661 | 2 |
| > 1 | 103 | 457 | 396 | 0 |

Wallace's word spaces are bimodal: 0.15–0.2 em in math-mode commentary (`Same sign, add`), 0.3–0.6 em
in prose. Its operator gaps sit in the first mode; no operator gap falls between 0.14 and 0.15 em.
Below that are script-size signs (exponents, 0.047 em at 8 pt) and a 7-pt cluster at 0.139 em. The
551 math-letter gaps at 0.066–0.1 em are #119's hazard, which the rule cannot reach (no operator).

Replay Clocks (pdfLaTeX, Libertine): operator gaps 0.2–1 em for relations and binary signs (TeX's
thick and medium spaces), kerns below 0.05 em, and `𝑛|=` at 0.035 em in one caption the authors set
closed. The IEEE paper's math fonts (`CMMI10`, `CMSY10`, `CMR10`) carry neither ToUnicode nor
`/Encoding`, so the spacing reader cannot decode any of its math and no rule here can reach it.

**Operator boundaries against PDFKit's text** (`operators` probe: every boundary beside an operator
on a line whose shows the reader owns, with whether PDFKit's text spaces it; spaced / not):

| Book | Boundaries (lines spelled) | < 0.05 | 0.05–0.15 | 0.15–0.2 | 0.2–0.3 | 0.3–1 | > 1 | would insert (lines) |
| --- | --- | --- | --- | --- | --- | --- | --- | ---: |
| Wallace | 25,314 (7,152 of 7,619) | 0 / 252 | 7 / 46 | 13,525 / **7,998** | 978 / **1,014** | 416 / **832** | 80 / 166 | 8,958 (5,237) |
| Replay Clocks | 419 (141 of 141) | 0 / 11 | 0 / 7 | 0 / 10 | 130 / **86** | 100 / **73** | 0 / 2 | 169 (92) |
| 9/11, FAA, USGS, NOAA | 17, 19, 11, 54 | all below 0.15 or spaced | | | | | | 0 |
| every other English book | 0 | | | | | | | 0 |

PDFKit dropped 63% of Wallace's thin spaces beside a sign on one side and kept them on the other. The
0.3–1 em misses are exercise labels before a negative answer (`23)− 4`, 0.49 em), coordinates
(`65,− 63`), `Slope =− 1` and Replay's relations (`𝑛= 32` at 0.285 em, `E= 1𝑚𝑠`).

### Rule (`NativeSpacingReader.operatorSpace`, `Evidence.operatorGaps`, `missingSpaces`)

A boundary is a math space when either side is one of `+ − × ÷ ± ∓ ∗ ⋅ = ≠ < > ≤ ≥ ≈ ≡`, neither
side is whitespace, and the gap is at least 0.15 em and at most 1 em. The ASCII hyphen, the slash and
the middle dot are not signs (prose punctuation). The gap is read inside a show at a TJ adjustment
(`Evidence.operatorGaps`, recorded for every adjusted boundary beside a sign **whatever the show's
Tc/Tw**, since math spaces are kerns in every producer) and between consecutive shows on one baseline
(within 0.1 of the larger size), in em of the larger size. Everything else is #119/#128's machinery:
the exact-line rule, show ownership, insertion only where PDFKit's text has no whitespace.

Why this does not reintroduce #119's or #128's spurious insertions: #119's 439 Wallace insertions
were CMMI kerns between juxtaposed variables (`x|y`), which have no sign; #119's producer condition
stays in force for every word space it reads. The gap alone decides between signs too: two relations
TeX sets together (`>>`, 0.043 em) and script-size signs stay joined.

A sign next to a sign is included: Wallace's 796 `=|−` boundaries (0.160–0.494 em) were spaced by
PDFKit in none, and the render sets them apart (`y = − 5`).

### Layout: a sign is not a term (`LayoutReconstructor.isWordy`, shared)

The first candidate turned two prose lines into formula crops: Wallace page 89's
`from zero, representing x = 1, 2, 3....` and page 125's `Interval Notation: ( − ∞, 1)`. `isWordy`
requires words of two or more letters to be 40% of the whitespace tokens; `x =1` was two tokens where
`x = 1` is three, so 15 ≥ 14 became 15 < 16. The heuristic had been calibrated on PDFKit's operator
spacing, which the survey shows is arbitrary. `isWordy` now does not count a token made only of signs.
On baseline text this changes `isWordy` for Wallace 58, Replay 4, FAA 4, NBS 1 and no other line
(`tools/standalone.py`); all are prose with inline arithmetic (`For example, 3 = 30°, 6 = 60°, and 33 =
330°.`) or a caption, and none changes FAA's or NBS's output (lanes below). NOAA has one line whose
margin moves (−2 to 0) but it has one word of three letters and fails either way.

### Lines before and after

`tools/insertions.py` on product lines (`instances/wallace-insertions.tsv.gz`, `replay-insertions.tsv`):

| Book | Lines changed | Inserted spaces | Other changes |
| --- | ---: | ---: | --- |
| Wallace | 5,211 | 8,910 | none; page 141 has one line fewer (below) |
| Replay Clocks | 92 | 169 | none |
| IEEE and every other English book | 0 | 0 | — |

Most common Wallace pairs: `x|−` 1,058, `=|−` 730, `)|−` 717, `(|−` 492, `y|=` 419, `+|1` 283,
`,|−` 258. Replay: `𝑛|=` 26, `E|=` 13, `||≤` 8, `𝑥|−` 7.

| Lines with an asymmetric operator | Baseline | Candidate |
| --- | ---: | ---: |
| Wallace | 6,843 | 2,240 |
| Replay Clocks | 70 | 18 |
| IEEE | 18 | 18 |

Wallace's 2,240 left: 1,635 lines whose shows the reader cannot assign to one line (overlapping
rectangles of fractions and exponents, #120's exact-line limit), 358 lines whose shows do not spell
PDFKit's text, 144 with a gap above an em (table columns: `− 1 − 1− 1− 1`), 63 whose unspaced gaps
are all below 0.15 em (script signs, `h−1(x)`, and `64−7` set tight in the source), 40 other.

Page 141: the table row `Solution | (− 1,− 3)` was cut in two by `splitDetachedShows` (#14), whose
check compares PDFKit's raw pieces with the repaired line; with the row repaired it no longer
matches, and the row stays one line (`Solution ( − 1, − 3)`). The table is a preserved region in the
EPUB, whose text is unchanged.

### Review

| Set | Rows | Spurious |
| --- | ---: | ---: |
| Wallace pages 7–8, every changed line (the issue's examples), 150-dpi renders | 26 | 0 |
| Wallace random changed lines (seed 188) and the issue's four lines, 200-dpi strips (`instances/reviewed-wallace-lines.tsv`) | 52 | 0 |
| Replay random changed lines (seed 188) (`reviewed-replay-lines.tsv`) | 24 | 0 |
| Replay page 7, every changed line; caption (e) set `𝑛=` in the source stays closed | 7 | 0 |
| One respelled contract phrase per changed contract page (`reviewed-contract-lines.tsv`) | 12 | 0 |

Every inserted space is visible in the ink. Residual defects seen in the strips are not from this
change (`x(3x + 5) 0` for `≠ 0`, `22)x − 7` in a fraction numerator).

Wallace EPUB pages that changed beyond whitespace (16; `tools/pagediff.py`, `lost.py`, `blocks.py`,
each read against its render): **no page loses reflowed text**. Pages 25, 58, 90, 91, 112, 113, 116,
139, 185, 189, 190, 194 and 227 bring text out of formula crops: an example's sentence
(`c varies indirectly as d and c = 4.5 when d = 6`), exercises without fractions (page 25's 2, 6, 8,
10, 12–16 and `Combine Like Terms`; the crops keep 1, 3, 4, 5, 7, 9, 11, 17–20), and derivation
annotations beside their steps (page 227's `Multiply to ac or (4)( − 5) = − 20, add to − 1`, exponents
still `<sup>`). Page 114's sentence reads as text around a crop of its fraction (`3/5 x + 4 in`),
where the baseline cropped the whole sentence (mixed). Page 115 re-cuts one crop into three. Page 468
(answers to 7.3) loses five headings the baseline made of answer rows (`13) x (x− 3) 14) 4(x− 2) …`)
and now sets one answer per line; `Answers - Add and Subtract` becomes a paragraph, as `Answers -
Integers` already is on page 438. Wallace's image count goes from 1,979 to 1,974.

## Tests (`Tests/PDFReflowLibTests/NativeSpacingTests.swift`)

Source fixtures, captured by `capture.swift` with the source checksum pinned and checked against the
existing layout fixtures: `fixtures/algebra-7-8-text-operators.json` (Wallace pages 7–8) and
`fixtures/replay-7-text-operators.json` (Replay page 7; its plots' `Do` removed).

| Test | Checks |
| --- | --- |
| `operatorSpaceSeparatesTheMathSpaceFromKernsScriptsAndClosedSigns` | measured gaps (`5|+` 0.1629, `(|−` 0.1601, `𝑛|=` 0.2851, `=|−`); the 0.15 and 1 em edges; controls: `𝑛|=` 0.035, `>>` 0.043, script `−|5` 0.047, `x|y`, hyphen, slash, middle dot, whitespace, NaN |
| `wallaceWorkedExamplesSpaceEveryOperatorAsTheSourceSetsIt` | every changed line of pages 7–8 (26), no space after `ﬀ` (#189); controls on the source stream: `5|+` at 0.12 em stays `5+`, digits record no operator gap, no show has Tc/Tw or #119 word spaces |
| `replayCaptionsSpaceTheirRelationsAndKeepTheOneTheAuthorsSetClosed` | the seven operator lines of page 7, caption (e) unchanged |
| `whetherASignStandsApartDoesNotDecideThatARowIsProse` | page 89's row is prose as `x =1`, `x = 1` and `x=1`; controls: arithmetic with two words and a derivation step are not, however spaced; a spaced comma still counts |

On the baseline the new tests do not compile (new API). Mutation controls (`tools/mutate.py`, sources
restored and byte-compared after each run):

| Mutation | Failing tests |
| --- | --- |
| `no-in-show` (TJ-adjustment gaps ignored) | Wallace fixture |
| `no-cross-show` (gaps between shows ignored) | Wallace fixture, Replay fixture |
| `threshold-0.1` | predicate, Wallace fixture (the 0.12 em control gains a space) |
| `no-em-cap` | predicate |
| `no-sign-pairs` (a sign beside a sign excluded) | predicate |
| `producer-condition` (operator gaps read only with Tc/Tw, as #119's) | Wallace fixture |
| `hyphen-is-a-sign` | predicate, Replay fixture |
| `signs-count-as-tokens` (the `isWordy` change undone) | prose-row test |

## Corpus lanes and contracts

`tools/lane.sh` (one case per call, EPUBCheck, probe, `--execution-context host-terminal`) and
`tools/compare.sh` (`compare_conversion_runs.py --allow-different-converters`). EPUBCheck, progress
and memory gates passed in every run; no OCR page changed and both runs used one Vision program set.

| Case | Baseline | Candidate | compare_conversion_runs, and `pagediff.py` |
| --- | --- | --- | --- |
| wallace-algebra-2010 | fails 64 of 306 checks (above) | pass | 220 pages differ; 189 in whitespace only, 16 reviewed above; navigation only on page 468; `imageCount` 1,979 → 1,974 |
| arxiv-replay-clocks-2023 | fails the 2 new of 73 | pass | 8 pages, whitespace only; images and navigation unchanged |
| ntrs-20190030725-dasc-2019 (IEEE) | pass | pass | no changes |
| gpo-911-2004, fed-explained-2021, faa-phak-8083-25c, nbs-jres-geltman-1977 | pass | pass | no changes |
| dga, our flag, cdc, usgs, scotus, census, pro se, gwl, usda, earthdata, techport, blue book | pass | pass | no changes |

NOAA was not converted: its spacing is unchanged (54 operator boundaries, none inserted) and no line
changes `isWordy` (above). Warren is excluded from full conversions (#5).

**Contracts** (`corpus/regressions.json`). 54 existing Wallace phrases on 15 pages pinned PDFKit's
asymmetric spacing for other purposes (column order, answers, script context); `tools/respace-contract.py`
respelled each to the candidate's text only where its non-whitespace characters match exactly once,
and gave the order guards (`absentText`) their respaced form beside the old one; page 471's two
guards (`22)− 2,`, `29)−`) gained `22) − 2,` and `29) −` by hand. New entries
(`tools/add-contract.py`): Wallace page 7 (`− 5 + ( − 3) Same sign, add 5 + 3, keep the negative`,
`Diﬀerent signs, subtract 7 − 2, …`; absent `5+ (− 3)`, `add 5+ 3`, `subtract 7− 2`, `Diﬀ erent`),
page 8 (`4 + ( − 3) Diﬀerent signs, subtract 4 − 3, …`, `9 − ( − 4) Add the opposite of − 4 9 + 4 Same
sign, add 9 + 4, keep the positive`; absent `4+(− 3)`, `subtract 4− 3`, `opposite of− 4`, `9 +4`,
`Diﬀ erent`) and Replay page 7 (the paragraph with `if E = 1𝑚𝑠`; absent `if E= 1𝑚𝑠`; its captions are
inside the figure crop). Wallace: 306 checks, the baseline fails 64 (the 53 respelled phrases that
now differ and 11 new checks; the two `Diﬀ erent` guards pass on both); Replay: 73, the baseline fails
the 2 new ones. Both candidates pass.

## Verification

- `swift test`: 907 tests pass (903 plus the 4 above; 906 before the `isWordy` test was added).
- `scripts/check-all.sh --fast`: exit 0 (907 Swift tests, 242 Python tests, fixture conversions,
  policy and concurrency checks, repeat-run identity).
- `python3 tools/update_doc_counts.py` regenerated the documented counts.
- The candidate binary in the lanes predates two comment-only edits to `NativeSpacingReader.swift`.

Shared functions touched: `NativeSpacingReader.missingSpaces` and the show reader (`read`'s TJ
callback: `Evidence.operatorGaps`), and `LayoutReconstructor.isWordy` (used by `isProseRow`,
`isSentenceRow`, list-item and paragraph-indent rules).

## Limits and follow-ups

1. **The unary minus.** The source spaces it (`( − 3)`); TeX would not (its Bin-to-Ord rule after an
   opening bracket, a relation or at the start). No kern tells them apart, so the EPUB follows the
   source. Emitting `−5 + (−3)` needs that syntactic rule, removing a space the source sets.
2. **Exact-line refusals** keep 1,635 Wallace lines with an asymmetric sign (overlapping line
   rectangles; #120's defect 1) and 358 whose shows do not spell PDFKit's text.
3. **IEEE (DASC 2019)**: 18 lines keep asymmetric signs because its CM math fonts have no ToUnicode
   or `/Encoding`; decoding TeX's built-in math encodings would reach them.
4. **`splitDetachedShows`** compares raw PDFKit pieces with the repaired line, so any spacing repair
   stops a detached-show split (Wallace page 141, inside a preserved table).
5. **#189**: not reproducible; if the owner reads with a font lacking U+FB00 (Charter, Times New
   Roman, Avenir Next, San Francisco), spelling `ﬀ ﬃ ﬄ` out would remove any fallback artefact but
   reverses #123 and changes Census's and Wallace's contracts. Device test in Books needed first.
6. **Wallace page 114** reads a sentence around a crop of its inline fraction (`… to y = −` [crop]
   `slope-intercept form.`) where the baseline cropped the sentence whole.
