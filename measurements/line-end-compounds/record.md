# Line-end hyphens that still joined with a space (#131)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64 release CLIs, shared host
with other agents' conversions running. Work began on `277cbde` and was merged forward to `96667ce`
(#133 italic runs, #118 column continuation) and `4fc3115` (#132 blank pages, #135 drop caps) before
the final figures. Every figure below the survey section was taken on `4fc3115`: baseline is a
release CLI built from an archive of `4fc3115` (`54600481…`), candidate is `4fc3115` plus this
working tree (`ee96ba42…`). One raster/Vision probe binary served both lanes. No public API or
default changed.

## What was wrong

#127's survey left three kinds of line-end hyphen joined with a space:

1. **Compounds broken before a capital or a digit.** `joinOperation` sent every hyphen before a
   non-lowercase letter to `.space` once the address and code rules declined it: 9/11 `non-
   Muslims`, `mid- 1990s`, FAA `Single- Pilot`, Loper Bright `pre- APA`.
   `AddressJoinTests.hyphenPolicyStillDecidesLowercaseBreaksInsideAddresses` pinned `the pre-
   Columbian era` and `a mid- 1990s peak`; `EqualsHyphenTests` pinned the prose controls with a space.
2. **Word breaks split across two blocks.** The halves were never passed to `join`, because layout
   put them in different blocks:
   - 9/11 page 147, `hijack train-` + `ing`: item 2's wrapped lines sit flush with its marker
     (`continuesListItem` wants a hanging indent).
   - Page 220, `178 In March 2001, the CIA’s brief=` + `ing slides…`: the line PDFKit read with the
     raised marker `178` carries the marker's 7.175-point size, so its wrap opened a paragraph.
   - Page 438, `the intel-` + `ligence establishment…`: PDFKit split `the intel-` from its row
     (`…oversight of`), and each piece became a paragraph.

   The same class appears in Wallace (`con-` + `nect`, `pre-` + `vious`, `sim-` + `plify`), Fed
   (`em-` + `ployment`, `mini-` + `mum`), Loper Bright (`trig-` + `gered`, `at-` + `tempted`),
   Census (`infor-` + `mation`, `Mi-` + `crodata`) and the Blue Book. On `4fc3115`, #118's
   same-column rules already join page 147's item, 9/11 page 215's `command-and-` + `control`,
   Fed page 44's `bal-` + `ances` and Our Flag page 26's `horizon-` + `tally`, so none of these
   changes here.
3. **Number codes.** `CTC 96-` + `30015` and `SD 108-` + `00` have no letter segment, so
   `codeContinues` declines them.

## What changed

`Sources/PDFReflowLib/LayoutReconstructor.swift` only.

- **`compoundOperation`** runs in `joinOperation` after the address and code rules and before the
  lowercase hyphen policy. It handles a line-end `-` before an uppercase letter or a digit:
  - **Word before a capital.** The hyphen stays with no space. It goes when the vocabulary holds
    the halves joined and not the compound (`CENT-` + `COM` beside `CENTCOM`, `Harper-` + `Collins`).
  - **Word of two or more letters before a digit.** The hyphen stays with no space only when the
    book sets that word before a number inside a line. Otherwise the space stays, as before.
  - **Number before a number.** The hyphen stays with no space when:
    - the left run of digits and hyphens follows whitespace, `(`, `[` or the line start;
    - the right run ends at whitespace, closing punctuation or the end;
    - no segment is empty;
    - one number has at least two digits.

    A number before a capital keeps the space (`601-` + `CE 1318`).
- **Number-prefix vocabulary.** `addNumberPrefixVocabulary` is called from `addVocabulary`. For
  each `letters-digit` inside a line, it records the letters under the key
  `\u{1}number-prefix:`. Plain word splitting cannot supply this evidence: `mid-1980s` yields
  `mid-`, the same token every line-end `mid-` yields.
- **`joinWordBreaks`** runs at the end of `blocks`, after `joinColumnContinuations`. It joins
  adjacent blocks on one page when all of these hold:
  - the left block is a paragraph or a list item (`joinableText`) ending in `-` after two letters;
  - the right block is a paragraph that opens lowercase and carries no note key;
  - neither block has a validated role other than paragraph;
  - the hyphen policy has evidence for the join, so it would not warn `uncertainHyphen`.

  `join` then applies the hyphen policy. The evidence gate was added after the first survey of
  NOAA. There, reading order sets four broken fragments beside the wrong neighbour
  (`acidifica-` + `oceans, animal…`, `deforesta-` + `and ocean…`, `dispro-` + `storm activity.`,
  `well-docu-` + `discusses implications`). Without evidence, those four merged with the hyphen
  kept.

## Survey: every changed join

`tools/join-log.patch` is a survey-only instrumentation. It is not in the library. With
`PDFREFLOW_JOIN_LOG` set, it logs:
- every join `compoundOperation` decides (the baseline spaced all of them);
- every merge `joinWordBreaks` makes (the baseline kept those blocks apart).

The instrumented candidate ran every corpus lane, and `survey/<case>.tsv` holds the logs. The
Python scripts in `tools/` are the scratch scripts as run. They read evaluations under
`/private/tmp/h131/<label>-<case>`, so adjust that path to rerun them. The lane
comparison (`compare-<case>.json.gz`, `--allow-different-converters --detail`) was then diffed page
by page (`tools/textdiff.py`). Every text change is one logged join, and every logged join is one
text change. The only other changed fields are `noterefs` and `anchors` on pages whose note text
changed.

| Book | Capital: hyphen kept | Capital: hyphen removed | Word before digit | Number codes | Block merges | Total |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| gpo-911-2004 | 26 | 3 | 5 | 2 | 2 | 38 |
| faa-phak-8083-25c | 4 | 0 | 0 | 0 | 0 | 4 |
| wallace-algebra-2010 | 1 | 0 | 0 | 0 | 3 | 4 |
| fed-explained-2021 | 1 | 1 | 0 | 0 | 2 | 4 |
| scotus-loper-bright-2024 | 1 | 0 | 2 | 0 | 2 | 5 |
| census-rrs2002-01 | 2 | 0 | 0 | 0 | 2 | 4 |
| arxiv-replay-clocks-2023 | 1 | 0 | 0 | 0 | 0 | 1 |
| cia-blue-book-14-1955 (OCR) | 1 | 0 | 0 | 0 | 1 | 2 |
| gpo-warren-1964 (outside the gate) | 38 | 14 | 0 | 87 | 293 | 432 |
| noaa-nca5-2023 (outside the gate) | 56 | 1 | 0 | 0 | 0 | 57 |
| dga, our-flag, cdc, usgs, nbs, uscis, irs | 0 | 0 | 0 | 0 | 0 | 0 (identical) |

Each logged join was spaced on the baseline (`x- y`, or the halves in two blocks). The review below
names each join in its candidate form.

### Review by class

**Capital, hyphen kept (37 in lane books).** All are compounds. The book's own unbroken uses were
counted in the `277cbde` baseline EPUB with `tools/evidence.py`:
- 9/11:
  - `Inter-Services` (4 unbroken), `non-Muslims` (1), `mid-November` (2), `al-Rahman` (2),
    `Hizbul-Ittihad` (1), `Israeli-Palestinian` (1; ×2);
  - `anti-Taliban` (6), `mid-June` (1), `mid-July` (5), `Atta-Binalshibh` (3), `Al-Ballushi` (1),
    `Political-Military` (5), `non-NATO`, `Goldwater-Nichols` (9; ×2);
  - `AD-Inspection`, `Afghan-Bosnian`, `Malaysian-Indonesian` (1), `Post-Watergate`,
    `al-Midhar` (2), `After-Action` (15), `al-Badawi` (2);
  - `Qida-Afghan-Pakistan`, `Pakistan-Afghanistan` (1), `McGraw-Hill` (1).
- FAA: `Single-Pilot` (14), `Acceleration-North/Deceleration-South`, `/Multi-Function` (8),
  `Services-Broadcast` (1).
- Wallace: `ibn-Musa`. Fed: `intra-System`. Loper Bright: `pre-APA` (4).
- Census: `Domingo-Ferrer` (7), `Kim-Winkler` (9). Replay Clocks: `Singhal-Kshemkalyani’s`.
- Blue Book: OCR table debris `ID-` + `I•`, meaningless on both builds.

**Capital, hyphen removed (4).** 9/11 `CENTCOM` ×2 (10 unbroken, no `cent-com`) and `HarperCollins`
(2 unbroken). Fed page 19 `Fed-` + `Wire` becomes `FedWire`: the book prints `Fedwire` 26 times
and never `Fed-Wire`, so the break was the typesetter's. The capital W comes from the source line.

**Word before a digit (7).** 9/11 `mid-1980s`, `mid-1990s`, `pre-9/11` ×2 and `Post-9/11`; Loper
Bright `mid-1980s` ×2. Each word appears before a number inside a line elsewhere in its book (9/11:
`mid-` 3 and 4 unbroken, `pre-9/11` 12, `Post-9/11` 14; Loper Bright `mid-1980s` 3). The one
corpus pair left spaced is FAA page 73's `Category Airplanes-` + `14 CFR part 23`. There the source
sets a hyphen for the em dash its neighbours use (`Airplanes—14 CFR part 25`), so neither form
is right.

**Number codes (2).** 9/11 page 486 `CTC 96-30015` and page 554 `SD 108-00`.

**Block merges (12 in lane books, every hyphen removed).**
- 9/11:
  - Page 220 `briefing slides`. The marker line `178 In March 2001, the CIA’s briefing slides…`
    still starts a paragraph of its own; see defects below.
  - Page 438 `the intelligence establishment…`.
- Wallace: `connect` (92), `previous` (245), `simplify` (301).
- Fed: `employment` (20), `minimum` (84).
- Loper Bright: `triggered`, `attempted` (4).
- Census: `information` (9), `Microdata` (17).
- Blue Book (68): `impossible`. `southern-` + `most`, which has no evidence, stays in two
  blocks.

Each joined word occurs unbroken in its book (9/11 `training` 275, `briefing` 221, `intelligence`
1,421; Wallace `connect` 10, `simplify` 81; Fed `employment` 39, `minimum` 6). None of the joined
words is a compound.

**Warren and NOAA (outside the gate).** Both CLIs converted each full report on `4fc3115` with JPEG
images and no output cap. The text diffs (`tools/epubdiff.py`) and logs are in `survey/`. Every
text change is one logged join, and every logged join is one text change (Warren 432, NOAA 57).

Warren is OCR, and most of its joins are in its notes and citations.
- **Number ranges (87), all correct.** Page citations (`105-` + `106`, `5553-` + `5560`) and
  `750-850 rubles`.
- **Block merges (293).**
  - 291 remove the hyphen. All are word breaks the page split into blocks (`Os-wald`,
    `Mohren-schildt`, `Com-mission`, `concern-ing`).
  - 2 keep it on compound evidence: `film-plane` and `mem-bers`, OCR text the book also prints
    hyphenated.
  - Before the evidence gate, 28 more merged with the hyphen kept and a warning: 18 word breaks,
    5 compounds and 5 OCR debris. They now stay in two blocks, as on the baseline.
- **Capital, hyphen removed (14), all correct.** `CONSPIRACY`, `PRESIDENT`, `INTERROGATION`,
  `NOVEMBER`, `McCurdy`, `MacDonald`, `Os-Avald` → `OsAvald` (OCR of `Oswald`).
- **Capital, hyphen kept (38).**
  - 31 correct: `Dallas-Fort Worth` ×4, `Times-Herald` ×4, `Mannlicher-Carcano` ×4,
    `anti-Castro` ×4, `anti-Castroite`, `anti-American`, `anti-Semitic`, `pro-Nazi` ×2,
    `Remington-Peters` ×2, `Homicide-Robbery`, `Jaggars-Chiles-Stovall`, `WFAA-TV`,
    `Walter-McCarran`, `Seventy-Fourth`, `co-Counsel`, `mid-February`, and `business-` +
    `Jaggers-Chiles-Stovall` (source unread).
  - 7 are OCR damage. Each was wrong on the baseline too, with a space: `Mc-Xamara`,
    `Uro-Icgical`, `rail-Avay`, `tracheot-Qj^y`, `organization-L:ACS`, `THEIMMIGRA-TION`,
    `Leninlat-Karxist`.

NOAA:
- **Capital, hyphen kept (56), all correct.** Hyphenated surnames in references (`Masson-Delmotte`
  ×6, `García-Reyes` ×3, `Ayeb-Karlsson` ×2, `Berrang-Ford`), `Yukon-Kuskokwim` ×3,
  `Mid-Atlantic`, `mid-Pliocene`, `Indo-Pacific`, `Low-Income`, `Climate-Related`,
  `HighResMIP-PRIMAVERA`.
- **Capital, hyphen removed (1).** `[USA-` + `PI]` → `[USAPI]`, which the report prints unbroken.
- **No block merges.** Its five candidates had no evidence: four fragments beside the wrong
  neighbour (above), and the address `…-bridge-` + `crack-2021-05-12/`.

### What still reads `x- y`

`tools/spaced.py` lists every `x- y` left in the candidate EPUBs. None comes from a line-end join
this issue covers:
- **Suspended hyphens, correct as printed.** 9/11 `ultra-high- and`, `second- or`, `30- to`; Fed
  `low- and` ×7, `consumer- and`.
- **Source-literal mid-line breaks.** Fed 95/96 `check- collection` and 118 `community- oriented`
  are single native lines. FAA 12/333 `Service- Broadcast (FIS-B)` is a heading and its contents
  entry.
- **Paragraph cut by a box or figure** (Fed `insti-` + `More on…`, `previ-` + `Monetary policy…`,
  `major-` + `Box 3.5`; Wallace 410 `intro-` + a preserved region). The right block is a heading,
  caption or figure, so no adjacent-block rule applies.
- **FAA 73 `Airplanes- 14 CFR`** (above) and OCR debris (Census, NBS, Blue Book).

## Contracts

`corpus/regressions.json` gains 34 checks on 13 new pages (1,633 → 1,667 checks, 377 → 390 pages).
The basis of each case is extended.
- **Reproducers (31).**
  - 9/11:
    - 143 `non-Muslims`, 242 `mid-1990s`, 372 `pre-9/11`, 426 `Goldwater-Nichols`,
      450 `CENTCOM`, 486 `CTC 96-30015`, 554 `SD 108-00…SD 108-01`, each with its spaced
      form absent;
    - 220 and 438 paragraphs, each with its spaced form absent.
  - FAA 6 `Single-Pilot` and 360 `Services-Broadcast`, each with its spaced form absent.
  - Wallace 92 paragraph `connect the dots`, with its spaced form absent.
  - Fed: 20 paragraph `maximum employment`, with its spaced form absent; 12 `intra-System`.
  - Loper Bright: 4 paragraph `triggered`, with its spaced form absent; 104 `pre-APA`, with its
    spaced form absent.
- **Controls (3).** 9/11 111 `ultra-high- and very-high-frequency` (a suspended hyphen), 147 list
  item `…hijack training, according to various sources` (joined by #118 on both builds), and
  Fed 120 `low- and moderate-income`.

Negative control, with `tools/check_corpus_content.py` on the baseline evaluations:
- The baseline fails exactly the 31 reproducers (9/11 18, FAA 4, Wallace 2, Fed 3, Loper Bright 4)
  and passes the 3 controls.
- The candidate passes all 1,667.

## Tests

`Tests/PDFReflowLibTests/LineEndCompoundTests.swift`, 6 tests. New fixtures `911-147`, `911-220` and
`911-438` were captured on `4fc3115` with `tools/capture-layout-fixture.swift`. They are identical
to captures on `96667ce`.
1. Compounds before a capital join, including `the pre-` + `Columbian era`. Vocabulary evidence
   removes the hyphen (`CENTCOM`, `HarperCollins`), and a vocabulary holding both forms keeps it.
   Controls: a lowercase break through the policy, and a dash, a period or `U.S.-` before the
   break.
2. A word before a digit joins only with number-prefix evidence. A line-end `mid-` is no evidence.
   Controls: `Airplanes-` + `14 CFR`, `pres-` + `62`, `investi-` + `22S.`, a one-letter prefix.
   `less-than-` + `5-second` joins only once the book sets `than-5`.
3. Number-prefix vocabulary: prefixes inside a line are recorded; line ends, digits before the
   hyphen and plain words are not.
4. Number codes and ranges join. Controls: `601-` + `CE 1318`, `183-` + `WFAA-TV`, single digits,
   decimals, `=12-`, and `12-` + `15a3`.
5. Source pages 147, 220 and 438:
   - the reproducers (`briefing slides`, `the intelligence establishment`);
   - item 2's `training` inside its list item;
   - no block ends in `-` before a lowercase block;
   - controls: five bullets, and page 220's `Starting a Review` section stays apart.
6. Synthetic blocks: a gap between the halves still joins. Controls stay apart:
   - a sentence end;
   - a capital (`institu-` + `Figure 6.6.`);
   - a break with no evidence (NOAA `acidifica-` + `oceans, animal`);
   - a single letter (`Z-` + `r.,mbel`).

   `ListBulletsAndCodedReportsTests.syntheticTallMarkerLineKeepsItsWrappedLine` is unchanged. Its
   geometric controls set `copy-` and `right holder.` in two blocks, and the page has no
   `copyright`, so they stay apart.

Updated tests:
- `AddressJoinTests`: `the pre-Columbian era` now joins. `a mid- 1990s peak` keeps its space with
  an empty vocabulary.
- `EqualsHyphenTests`: the code-control list records which pairs now join. All of them still fail
  `codeContinues`. The page 242 comment explains that the three fixture pages carry no `mid-`
  evidence.

Negative control (`negative-tests.log.gz`, on the final tree). Three stubs restore the baseline: no `joinWordBreaks`
call, no `compoundOperation` call, and no `addNumberPrefixVocabulary` call.
- 8 tests fail with 36 issues: all 6 new tests, `AddressJoinTests` (the `pre-Columbian`
  expectation) and `EqualsHyphenTests` code controls (5 compounds and codes).
- `HyphenFragmentTests`, `AddressHyphenTests`, `InlineFormulaProseTests`,
  `ListBulletsAndCodedReportsTests` and the other `EqualsHyphenTests` pass.
- Page 147's item passes under the stubs, because #118 joins it.

## Verification

- `swift test`: 685 tests pass (679 on `4fc3115` plus 6).
- `scripts/check-all.sh --fast`: exit 0. That covers 685 Swift tests, 219 Python tests, 13 policy
  conversions, 22 rejection cases and repeat-run identity on six fixtures.
- Corpus lane on both binaries, one case per call, all 15 reviewed cases, compared with
  `tools/compare_conversion_runs.py --allow-different-converters --detail`:
  - Every run passes EPUBCheck and the structural, progress and memory gates. The baseline runs used
    the old contract; the candidate runs used the new one.
  - The eight changed books are listed in the survey table. Their changed pages are 9/11 50, FAA 4,
    Wallace 4, Fed 4, Loper Bright 4, Census 4, Replay Clocks 1 and Blue Book 2 (68, and 225's OCR
    debris).
  - No images changed.
  - Navigation changed only for FAA (page 328's heading `/Multi-Function Display`).
  - No report field changed.
  - DGA, Our Flag, CDC, USGS, NBS, USCIS and IRS are identical.
  - Converter peak RSS: 9/11 79 → 84 MiB, FAA 843 → 821 MiB.

## Defects to file

- **9/11 page 220: a detached note marker's line opens its own paragraph.** Expected: `…for the
  Cole.178 In March 2001, the CIA’s briefing slides…` is one paragraph, with marker 178 raised at
  the end of `…for the Cole.`. The marker line shares the row of `that al-Qida was responsible” for
  the Cole.` (y 481.6) and carries the marker's 7.175-point size.
- **9/11 page 438: a PDFKit row piece opens a paragraph.** Expected: `…to conduct oversight of the
  intelligence establishment and be clearly accountable…` is one paragraph. `the intel-` starts
  4.2 points after `…agencies,to conduct oversight of` on the same row. `joinedRows` joins only
  rows that carry mathematics.
- **Loper Bright pages 11→12: a cross-page word break is not joined.** Expected: `And in general,
  it authorizes the Secretary to impose “sanctions”…`. `continuation` refuses because page 11's
  last line, `§§1854(d)(2)(B), 1862(b)(2)(E). And in general, it author-`, fails `readsAsProse`
  (letters are under half its ink). The line-end hyphen and the lowercase `izes` are evidence
  enough.
- **Fed pages 22, 28, 47, 56, 57, 80 and 98: a paragraph cut by a box or figure keeps its broken
  half word before the box** (`insti-` + `More on Federal Reserve Advisory Councils…`). Expected:
  the paragraph continues after the box (`institutions…`).
- **FAA page 73 prints a hyphen for an em dash** (`Commuter Category Airplanes- 14 CFR part 23`).
  Expected `Airplanes—14 CFR part 23`, as its neighbours print. Out of scope for join spacing.
- **Fed pages 95, 96 and 118: source-literal `check- collection` and `community- oriented` inside
  one native line.** Expected `check-collection` and `community-oriented`.
