# `=` printed as the 9/11 report's hyphen (#126), and hyphens inside codes (#127)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64 release CLIs, six-agent host
load. Work began on `9803329`. It was merged forward to `e002972` (#119, same-font word spaces)
before any figure below was taken, then to `458a2e9` (#116, OCR path only) and `be34d39` (#122/#123,
ligature vocabulary and fallback ordering). The 9/11 figures were taken on `e002972` and `458a2e9`
and re-verified on `be34d39`: the lane comparison lists the same 198 pages with the same fields.
Baseline: release CLI built from an archive of `be34d39` (SHA-256 `25983784…`). Candidate: `be34d39`
plus this working tree (`1b1889ef…`).
Source: `GPO-911REPORT.pdf` (`657d4147…`). No public API or default changed.

## Diagnosis: the glyph is an equals sign

Page 235's body font is `KAFHKN+Bembo`, a Type 1C subset with a custom encoding (object 2481).
- **Code.** Every line-end break is code `0x3D`. The `/Differences` array names it `/equal`, and
  ToUnicode maps `<3d>` to U+003D (`mutool trace`: `glyph="equal"`, advance 0.667).
- **Outline.** In the embedded CFF (object 2484, read with fontTools), `equal` is a two-bar outline
  71–596 × 232–457 with width 667. `hyphen` is a single bar 35–361 × 171–221 with width 396.
- **Render.** A 400 dpi Poppler render of `…local worship=` shows an equals sign.

The PDF therefore prints an equals sign. No glyph name, width or outline evidence says hyphen, so
recognition uses a book-level signal. The book's other chapters break words with `-` (3,100
native line ends).

## Survey: `=` at line ends in the English corpus

`tools/survey_eq.py` reads native line dumps (`measurements/list-marker-pieces/dump-lines.swift`,
rebuilt on `e002972`) and classifies every line ending in `=` by the character before it and the
opening of the next line. `EqualsHyphenSurvey.swift` then applies the library's own functions to the
same native pages. Output is in `survey/`.

| Document | Lines ending `=` | Shape accepted, next line lowercase | Other lines holding `=` | Marks hyphens |
| --- | ---: | ---: | ---: | --- |
| gpo-911-2004 | 994 | 993 | 5 (URL queries in notes 571–583) | yes |
| wallace-algebra-2010 | 462 | 0 (9 accepted before digits or math: `slope=` + `1`, `16oz=` + `1hr`) | 4,047 | no |
| faa-phak-8083-25c | 4 | 0 | 90 | no |
| nbs-jres-geltman-1977 | 3 | 0 | 44 | no |
| arxiv-replay-clocks-2023 | 2 | 0 | 69 | no |
| census-rrs2002-01 | 3 | 0 (1 accepted, cipher-damaged, before a digit) | 23 | no |
| cia-blue-book-14-1955 | 9 | 0 | 161 | no |
| noaa-nca5-2023, gpo-warren-1964 (outside the gate) | 4, 1 | 0 | 147, 14 | no |
| fed-explained-2021, dga, our-flag, cdc, usgs, scotus | 0 | 0 | 0–1 | no |

Wallace's 28 `letter=` + lowercase line ends are math (`b=` + `c`, `31) R=` + `kA(T1 + T2)`,
`hypotenuse tanθ=` + `adjacent`, `formula, m=` + `m =…`). A single letter or a non-ASCII letter
before the sign fails the shape. In 9/11, all 994 are prose word breaks at the 10.25 pt body size,
on pages 163–341 (chapters 5–9). 993 continue lowercase; `mid=` + `1990s)` (page 242) continues
with a digit.

## What changed

`Sources/PDFReflowLib/LayoutReconstructor.swift` and `PDFReflowLibPipeline.swift`.

- **Shape (`endsWithEqualsHyphen`).** A line qualifies when:
  - it ends in `=` directly after two ASCII letters;
  - it holds no other `=`;
  - its last word holds none of `/ ? & # @`, nor `www.`.

  No word boundary is required: some 9/11 breaks follow a missing word space (`Hambali.Ham=`).
- **Evidence (`EqualsHyphenEvidence`, collected in pass 1 with the vocabulary).**
  - A break is a native line of that shape whose next line opens lowercase.
  - Every other line holding `=` counts against.
  - Recognized (OCR) pages are skipped.
  - The book is marked when it has at least 100 breaks, outnumbering the other lines ten to one.
- **Rewrite (`restoreEqualsHyphens`, pass 2).** In a marked book, each qualifying line's trailing `=`
  becomes `-` before reconstruction reads the page. The line keeps its rectangle, size, tag and
  styled runs. The formula seed, hyphen policy, cross-page and column joins then see the book's
  hyphen.
- **Vocabulary.** `addVocabulary` skips the word after a qualifying `=` line end, as #101 skips
  the word after `-`. It is not gated by the book evidence, because collection precedes the
  decision. No corpus book other than 9/11 has such a pair, so no other vocabulary changes.
- **Codes (`codeContinues`, #127).** A line-end `-` before an ASCII digit or capital joins with no
  space, keeping the hyphen, when all of these hold:
  - the left code is the run of ASCII letters, digits and hyphens ending the line, not preceded by
    `/ . _ @ : # ? & = % ~ + \`;
  - the right code is the same kind of run opening the next line, followed by the end, a space or
    `. , ; : ) ] ” ’ " '`;
  - every hyphen-separated segment is capitals and digits, or digits with a one- or two-letter
    lowercase suffix;
  - either one segment mixes digits and letters, or the left ends in two or more capitals and the
    right opens with a digit.

  It runs after the address rules (#79/#88) and before the prose policy.

An intermediate candidate also let a lowercase first segment precede a suffixed number
(`mid-` + `1990s`). It failed `AddressJoinTests.hyphenPolicyStillDecidesLowercaseBreaksInsideAddresses`,
which keeps `a mid-` + `1990s peak` under the prose rule. A decade is a prose compound, not a
code, so that allowance was dropped.

## 9/11: the rewritten breaks through the hyphen policy

`EqualsHyphenSurvey.swift` joins each of the 994 rewritten lines to its next native line with
`LayoutReconstructor.join` and the book's vocabulary (`survey/gpo-911-2004.txt.gz`).

| Tier | Breaks |
| --- | ---: |
| Removed: joined word in the book, compound not | 947 |
| Removed: another inflected form in the book (#115) | 9 |
| Kept as a compound | 0 |
| Kept with `uncertainHyphen` | 37 |
| Spaced (next line opens with a digit) | 1 (`mid-` + `1990s`) |

Review:
- **Removed (joined word).** A seeded random sample of 100 of the 947 was read. Every one is a
  word broken by hyphenation (`organiza-tion`, `memoran-dum`, `fundamental-ist`). All 14 removals
  whose first half is a common compound prefix (`pre-`, `inter-`, `sub-`, `fund-`, `follow-`) were
  also read: `pre-sumably`, `inter-nal`, `fund-ing`, `sub-ject`, … none is a compound.
- **Removed (inflected form), all 9.** `grad-uate`, `restau-rants`, `delib-erate`, `temper-atures`,
  `iden-tifier`, `desper-ately`, `presen-tations`, `inexperi-ence`, `revis-ited`. All are correct.
- **Warned, all 37.** Each is a real word break with no evidence for either form, kept with the
  warning exactly as a printed `-` break is:
  - 32 joined words the book never prints (`excep-tional`, `unquestion-ably`, `bun-galow`,
    `reas-cend`);
  - 4 prefixes glued to the previous word by a missing space that #119 did not restore:
    `JointTer-rorism` (205), `inVic-toria` (196), `toVir-ginia` (239), `delayedTal-iban` (270);
  - 1 closed compound whose halves are words (`camera-man`, 232).
- **EPUB check.** On the first candidate (before the #119 merge), each of the 994 decisions was
  checked against that page's EPUB text: the joined or hyphenated form is present on the page or
  the next, with 0 mismatches. The check matches the word anywhere on the page, so it missed
  page 220's `brief- ing` (`briefing` also occurs there), a join the policy never reaches (below).

## 9/11 before and after

| Measure | Baseline | Candidate |
| --- | ---: | ---: |
| `letter= lowercase` in the XHTML | 938 | 0 |
| Preserved-region crops (pages 19–467) | 108 (91) | 55 (38) |
| Images in the report | 136 | 83 |
| `imageRegion` warnings | 89 | 44 |
| `uncertainHyphen` warnings | 111 | 139 |
| Linked notes | 1,738 of 1,742 | 1,742 of 1,742 |

Links per chapter (`measurements/note-continuations-and-lost-markers/tools/lost.py`):

| Chapter | Notes | Linked, baseline | Linked, candidate | Recovered |
| --- | ---: | ---: | ---: | --- |
| 1–4 | 241, 93, 114, 194 | all | all | — |
| 5 | 132 | 131 | 132 | 36 (page 172) |
| 6 | 261 | 260 | 261 | 132 (page 210) |
| 7 | 192 | 191 | 192 | 16 (page 235) |
| 8 | 113 | 113 | 113 | — |
| 9 | 210 | 209 | 210 | 91 (page 313) |
| 10–13 | 86, 42, 42, 22 | all | all | — |

Chapter 7's note 116 (page 255), one of the issue's five, already links on the baseline. #119
restored page 255's word spaces, and its `=` lines stopped seeding a crop over the marker.

**Crops.** 53 crops on 45 pages go (165–339). None is added. Each removed page was diffed word by
word against the baseline. The only words lost are the crop's alt text and the fragment a crop
edge had split off, now joined (`ter` → `terrorist`, `ruary` → `February`). The crops that remain
on chapter 5–9 pages were viewed:
- photographs and diagrams on 166, 297, 302, 306, 330 and 331 (×2);
- blank pages 162 and 342, which are all-white full-page images on both builds (a separate matter).

**Lane comparison** (`compare-gpo-911-2004.json.gz`, `--allow-different-converters --detail`).
- 0 provenance errors, unchanged navigation, equal page markers.
- 198 changed pages, 53 changed images, report fields `imageCount` and `warnings`.
- Text changes classified by `tools/classify.py`:
  - 907 `=` breaks removed and 31 kept with a hyphen;
  - 35 in-page code joins (below);
  - 53 changes that are former crop text reflowing, plus `brief=` → `brief-` (220) and `mid=` →
    `mid-` (242).
- Pages without text changes differ in `noterefs` (their note's text changed), or in `anchors` and
  `markup` (509, 525, 533, 564: the recovered notes' backlinks).
- Converter peak RSS 108 → 105 MiB. EPUBCheck, structural, progress and memory gates pass on both.

## #127: code joins

The survey lists every consecutive native pair with a line-end `-` before a digit or capital:

| Document | Pairs | Joined as codes |
| --- | ---: | ---: |
| gpo-911-2004 | 73 | 35 |
| faa-phak-8083-25c | 11 | 3 |
| cia-blue-book-14-1955 | 302 | 1 |
| noaa-nca5-2023 (outside the gate) | 321 | 3 |
| gpo-warren-1964 (outside the gate) | 662 | 4 |
| scotus, wallace, fed, nbs, arxiv | 1–7 each | 0 |

Every join was read.
- **9/11 (35, all correct).**
  - FBI serials, 27: `265A-NY-` + `280350-302`, `265A-NY-280350-` + `IN`, `315N-NY-280350-` + `BS`,
    and `1474;265A-NY-` + `280350-302` after a missing space;
  - CTC reports: `2002-` + `30060CH`, `2003-` + `40028CHX`;
  - `IC-2001-` + `04A`, `CR99-` + `666C`, `C-` + `130H` (43), `MI-` + `5` (441).
- **9/11 across pages.** The lane EPUB also shows 541→542 `265A-NY-280350-302` and 550→551
  `315N-NY-280350-SD`, the issue's `280350- SD`.
- **FAA (3, all correct).** `737-` + `700C` (31), `(PA-` + `23)` (57), AIM paragraph `4-5-` + `7e`
  (364). The lane compare shows exactly these three pages changed.
- **NOAA (3, correct).** `EPA-430-R-22-004`, `UC-ITS-2020-38`, `CNRA-CEC-2018-006`.
- **Warren (4, outside the gate).** Native order runs two columns of citations together:
  `AFL-` + `789` (a folio the pipeline removes), `KRLD-` + `237.`, `H394-` + `348.` and `KULD-` +
  `1200.` (the next citation). These would join only if layout made the same pair.
- **Blue Book (1).** OCR table debris (`II-` + `9-QTI-IER.`).

Not joined, and outside this rule:
- prose compounds before a capital or digit (`non-` + `Muslims`, `Israeli-` + `Palestinian`,
  `mid-` + `November`, `pre-` + `9/11`, FAA `Single-` + `Pilot`);
- pure-number codes (`CTC 96-` + `30015`, `SD 108-` + `00`);
- `(CENT-` + `COM)`.

## Contracts

`corpus/regressions.json` (9/11) gains 27 checks on 11 new pages (209 → 236). The basis is extended.
- **Reproducers (24).**
  - `noteLinks` from 172 (36 → 509), 210 (132 → 525), 235 (16 → 533) and 313 (91 → 564), with
    `maximumImages: 0` on each page.
  - Text and absence:
    - 163 `terrorist safehouse` / `terror= ist`;
    - 172 `excep-tional commodities.` with `warningCodesAnyOf: uncertainHyphen`;
    - 235 `February 1, 2000, lunch`, `encountered Omar al Bayoumi` / `encoun= tered`;
    - 242 `lessons in the mid-` / `mid= 1990s`.
  - #127: 43 `C-130H` / `C- 130H`, 441 `American MI-5,`, 537 `265A-NY-280350-302-16752).` /
    `265A-NY- 280350`, and 546 `…265A-NY-280350-HQ, serial 11297;` / `265A-NY- 280350`.
- **Controls (3).** 255's link (116 → 546) and `maximumImages: 0`, and 546's `Hijackers Timeline,”
  Dec. 5, 2003`. Page 581's existing URL-query (`ReportID=145`) and `Spec/02-2004` address checks
  also stay green.

Negative control: the baseline lane fails exactly the 24 reproducers and passes the 3 controls. The
candidate passes all 236.

## Tests

`Tests/PDFReflowLibTests/EqualsHyphenTests.swift`, 7 tests. New fixtures were captured on `e002972`
with `tools/capture-layout-fixture.swift`: `911-172`, `-210`, `-235`, `-242`, `-255`, `-313`,
`-546`, `-550`, `-551` and `algebra-110`.
1. **Crops and markers.** As extracted, pages 172, 210, 235 and 313 seed a crop over the marker line
   and the marker does not link. With `restoreEqualsHyphens`, the page has no crop and the marker
   links through `NoteLinker`. 255 is the control: no crop and a link either way.
2. **Hyphen policy on 172/235/242.**
   - No `word= ` and no `x- y` lowercase gap remain.
   - `February` joins, and `excep-tional` stays with `uncertainHyphen`.
   - `mid- 1990s` follows the prose rule.
   - The continuations `ruary` and `tional` are not vocabulary.
3. **Shape and evidence.** Accepted and rejected shapes; 100/10 marks, 99/0 and 100/11 do not; OCR
   pages are ignored; a `slope=` + digit line is no break.
4. **Equation books.** Wallace 110 (which has accepted `slope=` lines), 288, 289, 291, NBS 7 and
   FAA 227 carry no breaks, and the 9/11 pages carry only breaks.
5. **Rewrite fidelity.** Geometry, tags and run structure are kept.
6. **Code joins.** 13 reproducers (9/11 and FAA) and 15 controls (prose compounds, citation ranges,
   folio numbers, pure numbers, lone letters, `less-than-` + `5-second`, a dash). A `Spec/02-`
   address still joins by #79, and a lowercase continuation is not a code.
7. **Serials on source fixtures.** Page 546 within the page, and 550→551 across pages through
   `NumberedNoteDetector` and `appendPage`.

Negative control (`negative-tests.log.gz`, run on the `458a2e9` merge). Three stubs restore the baseline: no rewrite, no `=`
fragment rule in `addVocabulary`, and no `codeContinues` call in `joinOperation`. With them, 5 of
the 7 tests fail with 50 issues, all reproducer expectations. The other 27 tests in the run pass:
the shape and evidence tests, `AddressJoinTests`, `AddressHyphenTests`, `HyphenFragmentTests` and
`InlineFormulaProseTests`. A mutant that always marks the book and drops the address exclusion
fails both remaining tests (5 issues).

## Verification

- `swift test`: 590 tests pass (583 on `be34d39` plus 7).
- `scripts/check-all.sh --fast`: exit 0 (590 Swift, 214 Python, 13 policy conversions and 22
  rejection cases, 8/8 concurrency processes, repeat-run identity on six fixtures).
- Corpus lane, both binaries, one case per call, shared probe, compared with
  `tools/compare_conversion_runs.py --allow-different-converters --detail`:

  | Case | Baseline | Candidate | Compare |
  | --- | --- | --- | --- |
  | gpo-911-2004 | 212 pass / 24 fail (236) | 236 pass | 198 pages, reviewed above |
  | wallace-algebra-2010 | 178 pass | 178 pass | identical |
  | nbs-jres-geltman-1977 | 17 pass | 17 pass | identical |
  | faa-phak-8083-25c | 487 pass | 487 pass | pages 31, 57, 364 (the three code joins); RSS 786 → 780 MiB |
  | fed-explained-2021 | 166 pass | 166 pass | identical |

  EPUBCheck, structural, progress and memory gates pass on all ten runs.
- Contract totals were recounted with `tools/count_checks.py`, which counts as
  `tools/check_corpus_content.py` does and matches its `contentChecks` on the five lanes: 1,528
  checks on 353 pages. `doc/regression-testing.md` and README now carry these figures and the
  test counts.

## Remaining gaps and defects to file

- **Prose compounds broken before a capital or digit keep a space.** 9/11: `non- Muslims` (143),
  `mid- November` (145), `Israeli- Palestinian` (217, 225), `anti- Taliban` (221), `pre- 9/11`
  (372, 493), `Goldwater- Nichols` (426), `mid- 1990s` (242); FAA: `Single- Pilot` (6),
  `Multi- Function` (328); SCOTUS: `pre- APA` (104), `mid- 1980s` (48, 80). Expected: the hyphen kept
  with no space when the compound is evidenced, or at least no space before a capitalized proper
  adjective. `AddressJoinTests` pins today's behaviour.
- **Line-end hyphens beside a detached marker or at a block boundary join with a space.** 9/11
  `train- ing` (147), `brief- ing` (220; `brief= ing` before this change), `intel- ligence` (438).
  The pair never reaches `joinOperation`.
- **Missing word spaces before a capital that #119 did not restore.** 9/11 `JointTer-rorism` (205),
  `inVic-toria` (196), `toVir-ginia` (239), `delayedTal-iban` (270). The glued prefix defeats hyphen
  evidence, so each is warned.
- **Blank pages become all-white preserved regions.** 9/11 pages 162 and 342 (no text, no ink) each
  emit a full-page white image on both builds.
- **Pure-number codes** (`CTC 96-` + `30015`, `SD 108-` + `00`) still join with a space. Numeric
  ranges make them ambiguous without citation context.
