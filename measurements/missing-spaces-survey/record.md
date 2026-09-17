# Missing word spaces at font changes (#110)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, Xcode 27.0, release CLIs.
The survey and the change were measured against `d333b4d` (#104). The work was then carried by merge
onto `785a974`, `63680df`, `de0df61`, `f15ab78` and `3f59dff`, and the line census was repeated on
`de0df61`, `f15ab78` (every book) and `3f59dff` (Wallace, Fed, Replay Clocks) with identical results.

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline CLI | `d333b4d`, `swift build -c release` | `e0b3a108…` |
| candidate CLI | this change on `d333b4d` | `74c9d62b…` |
| candidate CLI (final lanes) | this change on `3f59dff` | `b8d955c2…` |
| `survey-lines` / line census | `tools/build.sh <tree>`: `tools/main.swift` compiled with a tree's library sources | — |

No source PDF or EPUB is committed. Lane outputs and renders were deleted after review.

## Question

#110: NativeSpacingReader (#43) discards a page's evidence at the first `gs` (every measured page in
FAA, DGA, Fed, Our Flag, 9/11, Wallace and Loper Bright) and then at `Tc`, `Tw` and unpositioned
shows. It was not known whether these books have missing spaces at font changes at all. Step 1
measures that. Step 2 extends the reader only where step 1 confirms instances.

## Step 1: sampling method

Every page of each book was sampled, not 20 per book, so the sample includes every page with math or
style changes. For each book:

1. `tools/main.swift` (`survey-lines`) writes the product `NativeTextReader` lines, with the pipeline's
   styled-extraction gate, so any existing spacing repair is already applied. It also writes each
   line's PDFKit attributed string with `¦` at every run boundary (font name, bold/italic traits,
   size or baseline offset).
2. `tools/fused.py` flags a native token (split on whitespace) that is absent from the page's
   `pdftotext` tokens but equals two or three adjacent tokens on one `pdftotext -layout` line or in
   `pdftotext` reading order. Class `word`: a letter or digit on both sides of every split, the
   #43 rule's case. Class `punct`: otherwise.
3. `tools/glyphs.py` anchors each `word` candidate's native line in the page's `mutool trace` glyphs.
   It reports the fonts on each side of the split, whether font or size changes, the gap from the
   left glyph's advance end in em, the baseline offset and any space glyph.
4. Renders (`pdftoppm`) confirm each class (`tools/crops.py` stacks per-line strips).

The detector was validated on Replay Clocks: it finds the page-10 math fusions (`𝑒must`,
`Eprovides`) that the reader leaves unrepaired there, because that page has an unpositioned show.

`run-books.sh <work> <survey-lines> <book>…` runs steps 1–2. Candidate lists are in `instances/`
(`<book>-candidates.tsv`, or word class only for 9/11 and Wallace, whose `punct` lists are
5,139 and 10,591 rows of math and pdftotext spacing noise). Glyph analyses are in
`instances/<book>-word-candidates-glyphs.tsv`.

## Step 1: results per book

| Book | Pages | Native lines | Candidates (word / punct) | Confirmed missing spaces at a font or style change |
| --- | ---: | ---: | --- | --- |
| FAA | 522 | 32,250 | 22 / 6 | **0** |
| DGA | 10 | 388 | 0 / 2 | **0** |
| Fed | 128 | 4,399 | 0 / 2 | **0** |
| Our Flag | 54 | 1,530 | 1 / 0 | **0** |
| 9/11 | 577 | 25,984 | 99 / 5,139 | **16**, a size change the #43 rule cannot use (below) |
| Wallace | 489 | 27,789 | 769 / 10,591 | **about 250**: 160 anchored in glyphs plus about 90 of the same form that the anchor could not place |
| Loper Bright | 114 | 4,389 | 0 / 43 | **0** |

### FAA, DGA, Fed, Our Flag, Loper Bright: none

- FAA (28). Pages 211 and 510: `(VN0)`, `VNO.` are subscripts 2 pt low with a 0.03 em gap and no
  source space. Pages 401 and 416: letter-spaced digits `30`, `21`, `12`, `*50` that pdftotext
  splits, with no font change. Pages 14–15: leader dots. Page 458: seven same-font Helvetica
  fusions in the Challenger 605 chart's data table (`1,6852,599`, `11,98016,820`; gaps 0.7–1.5 em,
  confirmed on the render), a column fusion rather than a font change (defect 3). Page 459: nine
  tokens from a chart whose rotated axis labels share visual lines with its table (`290Speed`,
  `FL310FL330`), not a font change and not reviewed individually.
- DGA (2): footnote URLs whose note numbers pdftotext separates.
- Fed (2): `..63` leaders and `Components•`, a bullet.
- Our Flag (1): the page-47 drop cap `O¦n`, one word.
- Loper Bright (43): nested quotes and bracketed elisions (`“‘warrant`, `restate[]`), where
  pdftotext adds a thin space and the source has none.

The `gs` gate hid no missing spaces in these five books. Their fonts do change within lines (italic
case names, bold labels), but PDFKit already spaces those boundaries.

### 9/11: 16 at a superscript, outside the #43 rule

The 99 word candidates, anchored in glyphs:

- **16 note references fused to the next sentence** (`instances/911-word-candidates-glyphs.tsv`,
  `fontChange yes`): pages 52 `FAA.175This`, 96 `Act.29This`, 138 `network.”57The`, 140
  `1997.67Though`, 146 `Iraq.”110This`, 152 `Baghdad.”135Though`, 156 `CIA.161When`, 194
  `necessary.16Tenet`, 200 `“where.”59The`, 234 `went.8They`, 284 `suspicious.59Yet`, 290
  `General.86We`, 347 `departed.29The`, 348 `somber.32The` and `council.”33This`, 363
  `thousands.”18Yet`. Same font resource (Bembo), 7.2 pt raised 2.25 pt (3.4 pt on page 363) before
  10.25 pt text, and no space glyph. The gap is 0.111–0.137 em of the superscript size. The page-234
  render shows a narrow but real space (`went.8 They`). They reach the EPUB (`went.8They`).
  The #43 rule needs two different fonts and a gap of at least 0.15 em. Neither holds, and even a
  reader that accepted `gs`, `Tc` and `Tw` would insert nothing here.
- 68 same-font fusions before a capital (`NewYork` ×25, `theTaliban`, `PortAuthority`,
  `inYemen`): Bembo on both sides, no space glyph, a gap of 0.10–0.14 em. This book sets narrow word
  spaces before kerned capitals and after punctuation throughout. The `punct` class holds about 4,100
  more (`forward.We`, `Towers,the`), and the EPUB keeps them (`NewYork` 101 times, `forward.We`).
  This is not a font change (defect 1).
- 18 in `Bembo-SC` chapter openers (`Tue sday`, `chapte r`): pdftotext splits letter-spaced
  small caps. PDFKit is right.

### Wallace: confirmed at a font change, and the reader could not see them

About 250 digit-then-word fusions: `Subtract 7from both sides`, `Add 5to`, `LCM of 4and 6is 12`.
Ghostscript 8.70 (Lulu) sets a digit in CMR12 (or CMR10) and resumes the prose in
`EuropeanComputerModern-R`. The gap is 0.162 em (157 of 160 anchored cases; 0.17 em in 3), on
one baseline, with no space glyph. The page-29 render shows the space (`Subtract 7 from`), and the
d333b4d EPUB keeps the fusion (`Subtract 7from`, 35 digit-then-`from|and|to|into|with` fusions
against 15 spaced). This is exactly #43's case: different fonts, at least 0.15 em, a digit and a
letter.

Other Wallace word candidates are not missing spaces. Exponents and juxtaposed variables
(`x2y`, `14y2`, `(x3yz2)4`) change font or baseline with a gap of about 0 em. Page 364's `22` is
two exponents. The same-font tight tables on pages 82, 154, 231 and 373 (`toboth sides
sovariableis`) have gaps of 0.11–0.12 em (defect 2). Math punctuation before prose at a font change
(`6)when`, `(subtract)in`, `through:(2,`) is in the `punct` class. It is outside the #43 rule's
letter-or-digit condition and was not reviewed individually.

The census in #104 found that accepting a font-free `gs` let all 429 Wallace pages through yet
inserted nothing. The cause: **no Wallace text font has a ToUnicode map.** Only CMSY10 has one.
The fonts carry `WinAnsiEncoding` (with `Differences` for quotes and ligatures), so every show
around these boundaries was undecoded, and the rule needs every show on the line to spell it.

## Step 2: change (Wallace only)

`NativeSpacingReader`:

1. **`gs`** is accepted when the named ExtGState resource is a dictionary with no `Font` entry
   (Wallace's `/R7` sets only `/OPM 1`). A `gs` whose resource is missing or not a dictionary, one
   that sets a font, and a bare `gs` still disqualify the page.
2. **WinAnsi decoding** (`winAnsiUnicodeMap(differences:)`, internal) applies to a Type1 or MMType1
   font with **no** ToUnicode stream whose `/Encoding` is `WinAnsiEncoding`, either by name or as
   the `BaseEncoding` of a dictionary. Codes 32–126 read as ASCII. A `Differences` name comes from
   a small Adobe Glyph List table: ASCII punctuation, letter and digit names, quotes, en and em
   dashes, and `ff`–`ffl` ligatures. An unknown name removes its code. More than 256 entries, a
   name before any code, or a code outside 0–255 fails. Other encodings, TrueType, and a font
   whose ToUnicode map is present but rejected do not decode. `hasSupportedFont` counts such fonts.
3. **Trailing TJ adjustments** no longer shorten a show's measured end. Adjustments count only when
   a string follows them. The first build of 1–2 inserted 434 spaces in Wallace on 413 lines
   (against 155 on 149 lines after this fix), the excess inside formulas (`5 y`, `21 x`, `2 p`). Ghostscript ends every math show with a positive
   adjustment (`[(5)178.413]TJ`) and places the next show with its own `Td`. Subtracting 0.18 em
   from the end turned the 0.05 em coefficient-to-variable gap into 0.23 em. A trailing adjustment
   moves none of its own show's glyphs, and the reader accepts only independently positioned shows,
   so the adjustment carries no geometry. Interior adjustments still count (Replay's `[(e)-300(f)]`
   test is unchanged).

`Tc`, `Tw`, `Ts`, `Tr`, `Tz` and unpositioned shows still disqualify pages. No confirmed instance
needs them: 9/11's 16 cases fall outside the rule anyway. FAA's mixed maps and the two-range
codespace block no confirmed instance and are unchanged. The #43 rule itself (different fonts,
0.15 em, a letter or digit on both sides, an exact line match) is unchanged. No public API, option
or default changed.

## Every inserted space, all books

`tools/diff-lines.sh` diffs product `NativeTextReader` lines between a base and a candidate
`survey-lines` build for all 15 English PDFs in `corpus/cache` (Arabic M-618 and Chinese P596 are
excluded).

| Book | Lines | Changed, d333b4d → candidate |
| --- | ---: | ---: |
| Wallace | 27,789 | **149 lines, 155 inserted spaces** |
| Replay Clocks, DGA, FAA, Fed, Our Flag, 9/11, Loper Bright, USGS, Census RRS, NBS JRES, CDC, CIA Blue Book, Warren, NOAA | 1,008; 388; 32,250; 4,399; 1,530; 25,984; 4,389; 132; 859; 598; 535; 31,831; 48,023; 77,882 | 0 |

The same 149-line diff is byte-identical on `de0df61`, `f15ab78` and `3f59dff`. Other books are
unchanged on `de0df61` and `f15ab78` (every book) and on `3f59dff` (Fed and Replay). The product
lines of FAA, 9/11, Fed, DGA, Our Flag, Loper Bright and Wallace are identical between `d333b4d`
and `de0df61`, so step 1's sample did not need re-sampling for the later tips. f15ab78 splits Fed
lines at rule-grid joints, which cannot fuse words, and Fed has 4,399 lines on both.

Review (`instances/wallace-repairs-reviewed.tsv`, `tools/review-insertions.py`):

- 131 insertions separate exactly the two tokens pdftotext also separates (`split`).
- 24 differ from pdftotext only in tokenization around minus signs and parentheses: `3 and− 4`,
  `+2 for`, `1 (2 total)to`, `Electrician: 2 hr,`.
- All 155 were checked on 144-dpi renders of their source lines (`tools/crops.py`, three sheets of
  split cases and one of the rest). 149 strips were located and every one shows the space. The six
  that the glyph anchor could not place (pages 25, 82 ×2, 243, 271, 360: `p = 6 and q`,
  `6 showing his 6 hour`, `5 from second equation`, `9 points less`, `8 by 10`) are pdftotext
  `split` cases. **No spurious insertion remains.**

Coverage: of 223 digit-then-lowercase-word fusions in the d333b4d lines, 95 remain
(`instances/wallace-digit-word-residual.tsv`). They cluster on pages with radicals, inline
inequalities and side-by-side derivations (`Subtract 2from both sides` on page 349, beside `± 5 2 √`),
where the rule's exact line match or its single-rectangle ownership refuses the line. They were not
diagnosed one by one.

EPUB: in the d333b4d-based lane, 42 Wallace pages change. Their 45 changed text blocks equal the
baseline once whitespace is removed, and block counts and tags are identical. The other changed
lines lie in regions the pipeline preserves as images.

## Tests

`Tests/PDFReflowLibTests/NativeSpacingTests.swift`, three new functions:

| Test | d333b4d | Candidate |
| --- | --- | --- |
| `wallaceDigitBeforeTextFontRestoresItsWordSpaceAndMathStaysJoined`: page 29's structure (WinAnsi fonts without ToUnicode, `/R7 gs`, `[(7)178.413]TJ`) decodes, measures `[80, 87, 108.6]` and repairs `Subtract 7from`. Control: page 24's `5y` at 0.05 em stays joined. An interior adjustment still counts | fails | passes; with trailing adjustments subtracted again it fails 4 checks, including `5 y` |
| `graphicsStateWithoutAFontKeepsEvidenceAndAnyOtherDisqualifies`: a font-free ExtGState before, inside `q`/`Q`, or inside text keeps the repair. `Font` entry, missing, non-dictionary and bare `gs`, and `gs` plus nonzero `Tc`/`Tw` yield no evidence | fails | passes |
| `onlyWinAnsiEncodedType1FontsWithoutToUnicodeDecodeThroughTheirEncoding`: the table (95 ASCII codes; Wallace's `Differences` quotes, ligatures and digit names; unknown names removed; malformed and oversized arrays fail). By name, as a base, MMType1 decode. No encoding, MacRoman, a dictionary without a base, Standard base, unknown name, a name before any code, TrueType, and a rejected ToUnicode map with WinAnsi do not decode or repair. A page with only undecodable simple fonts is not scanned | does not compile (new API) | passes |

Positive controls, unchanged: `sourceFontBoundariesRestoreReplayClocksWordSpaces` (Replay's eight
reviewed page-1 repairs), the Type3 label controls (`sourceType3KerningRepairsOnlyTheTwoDgaLabelSpaces`,
`unsupportedSourceSpacingStateFallsBack` with its missing-resource `/G gs`), the #104 Adobe-map
tests and `rotatedShowsAndFormsLeaveUprightEvidenceIntact`.

Corpus contract (`wallace-algebra-2010`, pages 34, 40, 230; renders reviewed): paragraphs
`Start by focusing on the positive 8 Subtract 8 from both sides`, `Plug 2 in for each x. Multiply
inside parenthesis` and `Multiply to 9, add to− 6 The numbers are− 3 and− 3, the same! Perfect
square`, with absent `8from`, `Plug 2in` and `3and`. The candidate passes 142 checks on d333b4d
(162 on 3f59dff). The d333b4d baseline fails exactly these six
(`lane-summaries/base-wallace-algebra-2010-new-contract.json`).

## Verification

- `swift test`: 517 tests pass on `3f59dff` (514 plus 3). Also 503 on `de0df61` and 511 on `f15ab78`.
- `scripts/check-all.sh --fast` on `3f59dff`: exit 0. It ran 517 Swift tests, 205 Python tests,
  8/8 fresh concurrency processes, 6 fixture conversions, and 13 policy conversions with 22
  rejection/cleanup cases. It also exits 0 on `f15ab78`.
- Corpus lane: `tools/lane.sh <case> base|cand` runs `tools/run_corpus_regressions.py`
  (EPUBCheck, environment probe, host terminal). `tools/compare.sh <case>` then runs
  `tools/compare_conversion_runs.py --allow-different-converters`. Baseline is d333b4d
  (`e0b3a108…`) and candidate is this change on d333b4d (`74c9d62b…`), before the Wallace contract
  was added. Every run passed EPUBCheck, progress and memory gates, and both sides had the same
  Vision programs.

  | Case | Content checks | Baseline | Candidate | compare_conversion_runs |
  | --- | ---: | --- | --- | --- |
  | wallace-algebra-2010 | 136 | pass | pass | 42 changed pages (expected: text-only, reviewed above); OCR pages, images, navigation, report fields unchanged; markers equal |
  | arxiv-replay-clocks-2023 | 59 | pass | pass | passed: no changes |
  | gpo-911-2004 | 191 | pass | pass | passed: no changes |
  | faa-phak-8083-25c | 339 | pass | pass | passed: no changes |
  | dga-2025-2030 | 26 | pass | pass | passed: no changes |
  | fed-explained-2021 | 147 | pass | pass | passed: no changes |
  | gpo-our-flag-2003 | 70 | pass | pass | passed: no changes |
  | scotus-loper-bright-2024 | 91 | pass | pass | passed: no changes |

  On `3f59dff` with the contract, the candidate (`b8d955c2…`) passes wallace-algebra-2010 (162) and
  arxiv-replay-clocks-2023 (59). `cand-wallace-algebra-2010.json` and
  `cand-arxiv-replay-clocks-2023.json` are those runs.

## Limits of the reader, for future books

- Adobe, Word and GPO books with nonzero `Tc` or `Tw` (FAA, 9/11, Our Flag, Loper Bright, USGS) or
  with shows that continue the text cursor (Fed, FAA) still yield no evidence. None of them showed
  a missing space at a font change in this survey, so that modelling stays unbuilt.
- Fonts decode through ToUnicode (one-byte, #104's Adobe form) or, without one, through WinAnsi only.
  MacRoman, Standard and custom base encodings, symbolic TrueType, FAA's mixed maps and the
  two-range codespace do not decode.
- The rule needs two different font resources and at least 0.15 em. Same-font narrow spacing and
  size-only changes (9/11's note references) are outside it.

## Recommendation for #110

Close #110 with this change. The survey found font-change missing spaces in one of the seven books
(Wallace), and the reader now repairs 155 of them with no spurious insertion. Its `gs` gate was
only part of the cause there; the missing ToUnicode maps and trailing TJ adjustments were the rest.
In FAA, DGA, Fed, Our Flag and Loper Bright no missing space at a font change exists, so tracking
`Tc`, `Tw` and the implicit cursor is not needed. 9/11's missing spaces are same-font or size-only
and belong to defect 1.

## Defects to file

1. **9/11: PDFKit drops narrow word spaces throughout** (about 4,100 after punctuation, such as
   `forward.We` and `Towers,the`; 68 before kerned capitals, such as `NewYork` ×25; 16 after
   superscript note references, such as `went.8They`). Same Bembo font, no space glyph, gaps of
   0.10–0.14 em. Present in the EPUB. Not a font change, so not NativeSpacingReader's rule. A repair
   would need a per-book gap model and must avoid 9/11's own tight typesetting.
2. **Wallace: 95 digit-then-word fusions remain**, on lines the exact-match or single-rectangle
   requirements refuse (radicals, inequalities, side-by-side derivations). Wallace also has
   same-font tight table text (`toboth sides sovariableis onlyon`, pages 82, 154, 231, 373; gaps of
   0.11–0.12 em) and math punctuation fused to prose at a font change (`6)when`, `(subtract)in`),
   which the rule's letter-or-digit condition excludes.
3. **FAA page 458: chart data-table columns fused** (`1,6852,599`, `11,98016,820`), same font, gaps
   of 0.7–1.5 em. Relevant only where that text is not inside a preserved figure crop.
4. **Replay Clocks page 10 keeps math fusions** (`𝑒must`, `Eprovides`, `𝑅𝑒𝑝𝐶𝑙to`). The page
   has an unpositioned show, which disqualifies it (#104's census). This is the one remaining #43
   gap on its own reproducer book.
