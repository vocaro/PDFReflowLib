# Tall list marker lines, inflected-form hyphen evidence (#115) and coded weather reports (#96)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 (26A428) arm64, Xcode 27.0
(27A266a), release CLIs, six-agent host load. Work began on `3f59dff` and was fast-forwarded to
`9bf4e76` and then `43b20aa`. The Wallace and FAA figures compare an unmodified `git archive 9bf4e76`
release build with the candidate. The Fed and 9/11 figures compare `git archive 43b20aa`, because
that commit changes Fed. The candidate is `43b20aa` plus this working tree. Hashes are in
`identity.json`. No source PDF or full EPUB is committed.

## #115, part 1: a tall license bullet loses its wrapped line (Wallace page 2)

**Cause.** Wallace page 2 sets its license bullets (`•` and U+2212 `−`) in 17.0-point line
rectangles on a page whose ordinary 10-point lines are 9.9 points tall. Each marker line overlaps
its wrapped second line by 4.8 points. `continuesListItem` allowed `0.4 × body`, 3.98 points. So
six wrapped lines became paragraphs after their items: `licensor (but not…`, `right holder.`,
`applicable law…`, `limitations;`, `such as publicity…` and `this work. The best way…`. This is
#109's cause in the list branch.

**Rule.** The prose branch's extra-height measure moves into a local `extraHeight(_:listText:)`,
unchanged for prose. `continuesListItem`'s lower gap bound grows by the extra height of the item's
latest line and of the candidate line, as the prose branch's does. Extra height is the rectangle's
height over the page's ordinary height at that size, and it counts only when all three hold:

- it exceeds a quarter body size;
- the rectangle is at most twice the ordinary height;
- the line reads as text.

For prose, "reads as text" means `isProseRow`. A list line is set on its item's measure, not the
paragraph's. `− Your fair dealing…` shares its measure with one other line, so `isProseRow`
declines it. So with `listText`, a line that `isWordy` and `readsAsSentence` also counts. A row of
exercise terms (`1) 3x+ 4y=− 2x− 6y+ 12`) does not. The upper bound, the indent band and the
first-wrapped-line guards are unchanged.

A draft also required the line to have its row to itself, with no other line on the same row. Its
mutant survived. Where another column shares the row, the reading order already closes the item.
Where it could fire, it would stop an exercise-column word problem from keeping its wrapped line,
which #50 wants. It was dropped.

**Before/after (page 2).** Before: 10 items, with 6 wrapped lines as paragraphs. After: 10 items,
each holding its wrapped lines (`copy-` + `right` repaired to `copyright`). Checked against a 70-DPI
render. The Notice item's address `http://creativecommons.org/licenses/by/3.0/` is set off by
added space (11.6-point gap) as a display line and stays a paragraph. The issue does not cover it.

## #115, part 2: `sep-` + `arates` (Wallace page 9)

**Review.** The hyphen policy removed a line-end hyphen only when the book's vocabulary holds the
joined word and not the compound. Wallace never prints `separates`. It prints `Separate` (6),
`separated` (2) and `separately` (5), per `pdftotext`. So the hyphen stayed, with `uncertainHyphen`.
Keeping it without evidence is deliberate. But here the book does give evidence: other forms of
the joined word.

**Rule (`inflectionVouches`).** This applies only when neither the joined word nor the compound
decided. The hyphen is removed when all of these hold:

- Another inflected form of the joined word is a book word. Forms come from `inflectedForms`: take
  one ending from `s es d ed ing ly` off, leaving at least four letters, restore a dropped `e`,
  then add each ending back.
- No inflected form of the compound (`prefix-` + a form) is a book word.
- The two halves are not both book words, as a compound's halves are.
- Each half has at least two letters, and six or more in all.

Otherwise the hyphen stays with the warning, as before. Address hyphens (#88) and #101's
fragment-free vocabulary are untouched.

**Survey** (`InflectionSurvey.swift`, output in `survey/inflection/`). It reads native lines of 15
English books (no OCR, hidden text removed) with the pipeline's vocabulary. It joins every
consecutive line pair with the real `join`, carrying address tails as #101's survey does. It lists
every prose break the tier reaches.

| Document | Prose breaks | Joined word decides | Compound decides | Reach tier | Tier removes |
| --- | ---: | ---: | ---: | ---: | ---: |
| wallace-algebra-2010 | 340 | 316 | 10 | 14 | 1 |
| faa-phak-8083-25c | 103 | 3 | 57 | 43 | 0 |
| fed-explained-2021 | 459 | 416 | 17 | 26 | 8 |
| gpo-911-2004 | 2,971 | 2,774 | 25 | 172 | 42 |
| scotus-loper-bright-2024 | 913 | 786 | 6 | 121 | 46 |
| arxiv-replay-clocks-2023 | 35 | 29 | 0 | 6 | 4 |
| nbs-jres-geltman-1977 | 26 | 10 | 6 | 10 | 1 |
| gpo-our-flag-2003 | 14 | 7 | 1 | 6 | 0 |
| dga-2025-2030 | 1 | 0 | 1 | 0 | 0 |
| cia-blue-book-14-1955 | 55 | 12 | 38 | 5 | 0 |
| gpo-warren-1964 | 4,101 | 3,677 | 54 | 370 | 53 |
| noaa-nca5-2023 | 1,836 | 1,639 | 102 | 95 | 13 |
| usgs, census, cdc | 0 | | | | |

**All 168 removals were reviewed by hand. Every one is a word broken by hyphenation, and no
compound is joined.**

- **Typical removals.** Wallace `sep-arates`; Fed `distribut-ing` (the #50 record's defect 4),
  `ap-proves`, `inter-preted`, `con-nections`, `alter-natively`, `fundamen-tals`, `de-teriorate`,
  `tailor-ing`; arXiv `func-tions`; 9/11 `stew-ardesses`, `dis-seminates`, `Con-tra`,
  `Par-liament`; Loper Bright `Wil-liams`, `trig-gering`.
- **OCR-damaged Warren words** join as printed: `re-motly`, `con-troled`, `inter-vieAvs`.
- **NOAA `shov-` + `el-ready`** becomes `shovel-ready`.

**What the tier keeps.**

- **Compounds** stay because their halves are words: FAA `well-braced`, `re-engine`; Wallace
  `re-writing`, where `rewrite` is known but `re` and `writing` are both words.
- **Breaks with no form in the book** stay: Fed `expendi-tures`, `remit-tance`.
- **Wallace `dif-` + `ferent`** stays too. See defects below.

## #96: METAR and PIREP examples split into fragments (FAA pages 316–318)

**Cause.** The METAR example (pages 316 and 317) is set as three tagged paragraphs:
`METAR KGGG 161753Z AUTO 14021G26KT 3/4SM`, `+TSRA BR BKN008 OVC012CB 18/17 A2970 RMK` and
`PRESFR`. The PIREP (page 318) is two: `UA/OV … C182/SK` and `080 OVC/WX … LGT/RM HVY RAIN`. The TAF
on page 319 has the same geometry and tagging: 10-point lines at 12.5-point leading, each its own
paragraph group. Its change groups must stay separate lines. No layout rule tells these apart.

**Rule.** `codedReportGroupCount` counts a line's groups from the aviation weather formats. It
returns nil when any token holds a character outside capitals, digits and `/ + -`. The groups are:

- date-time `161753Z`;
- wind `14021G26KT`;
- visibility `3/4SM`, `P6SM`;
- sky condition `OVC012CB`, `SKC`;
- temperature and dew point `18/17`;
- altimeter `A2970`;
- valid period `1112/1212`;
- change groups `FM1500`, `TEMPO`, `BECMG`, `PROB30`;
- `METAR SPECI TAF AUTO COR AMD RMK`;
- coded weather `+TSRA`, `BR`;
- PIREP fields `/OV /TM /FL /TP /SK /WX /TA /WV /TB /IC /RM` (plus `UA/`);
- a four-character station directly before a date-time group.

`codedReportRuns` walks the page's body lines in reading order. A run opens on a line with three or
more groups, or on a lone `METAR`/`SPECI`/`TAF` line above one. The next line continues the run when
all of these hold:

- it is in the same column (left edge within half a body, same size, gap in the ordinary
  `-0.4…0.9 body` window);
- it holds only report characters;
- it has at least one group, or the run holds `RMK`, whose remarks are free capitals (`PRESFR`);
- it does not open another report (`METAR SPECI TAF UA UUA`).

A run of two or more lines becomes one preformatted block. A wrapped line joins with a space. The
line after a lone report type, and a line opening a TAF change group, keep their break (`\n`). The
join is literal, so the hyphen and slash policies never touch a report. Images, tables, boundaries
and note groups end a run.

**Survey** (`CodedReportSurvey.swift`, `survey/coded-reports/`). It lists every native line with two
or more groups and every run, in the same 15 books.

- **FAA:** 13 lines and 4 runs, exactly the METAR on 316 and 317, the PIREP on 318 and the TAF on
  319.
- **Every other book:** zero lines with two groups, zero runs.
- **Prose that quotes groups** (`Wind—reported with five digits (14021KT) unless`) is rejected by
  its lowercase letters.

**Before/after** (checked against 80-DPI renders of 316 and 319):

| Page | Before | After |
| --- | --- | --- |
| 316, 317 | 3 paragraphs | `<pre>METAR KGGG 161753Z AUTO 14021G26KT 3/4SM +TSRA BR BKN008 OVC012CB 18/17 A2970 RMK PRESFR</pre>` |
| 318 | 2 paragraphs | `<pre>UA/OV GGG 090025/TM 1450/FL 060/TP C182/SK 080 OVC/WX FV04SM RA/TA 05/WV 270030KT/TB LGT/RM HVY RAIN</pre>` |
| 319 | 7 paragraphs (`FM120000…PROB30` + `1200/1204…` already one) | one `<pre>` of 7 lines: `TAF` / `KPIR 111130Z 1112/1212` / `TEMPO …` / `FM1500 …` / `FM120000 … PROB30 1200/1204 3SM TSRA BKN030CB` / `FM120400 …` / `TEMPO …` |

The TAF control changes representation, from paragraphs to one block. Its separation is intact:
every change group stays its own line, and nothing merges. "One element per report" applies to the
TAF as much as to the METAR. `pre { white-space: pre-wrap }` wraps the long METAR line in a reader.
The `Example:` and `Explanation:` labels and the explanation lists are unchanged.

## Tests

`Tests/PDFReflowLibTests/ListBulletsAndCodedReportsTests.swift` has 8 tests. New fixtures
`faa-316-tagged`, `faa-317-tagged` and `faa-318-tagged` were captured with
`tools/capture-layout-fixture.swift`. A recapture of `faa-319-tagged` was byte-identical to the
committed fixture, and all four recaptured identically at `9bf4e76`.

- **`sourceTallLicenseBulletsKeepTheirWrappedLines`:** page 2's ten items exactly. No wrapped
  fragment is a paragraph. Controls: the Notice address and the list labels stay paragraphs.
- **`syntheticTallMarkerLineKeepsItsWrappedLine`:** the Wallace geometry joins.
  - Controls that stay apart: ordinary rectangles overlapping 4.8 points, an overlap past the extra
    height, a display rectangle over twice the ordinary height, and a terms marker line, alone or
    beside another exercise.
  - The terms controls run with crops off, since the formula crop would otherwise take those lines
    first. A sentence marker line with crops off joins.
- **`sourceSeparatesJoinsWhereTheBookUsesAnotherForm`:** page 9 with its own vocabulary keeps
  `sep-arates` and warns. With Wallace's `separate`, `separated` and `separately` added, it reads
  `separates` with no warning.
- **`inflectedFormsVouchOnlyForAWordBrokenInsideItself`:** four survey joins. The joined word and
  the compound still decide first. Controls: no form seen, both halves words, a compound form seen,
  too short.
- **`sourceMetarAndPirepExamplesAreOneBlockEach`:** 316, 317 and 318 exactly. Controls: labels, the
  following prose and the explanation list item that quotes `(14021KT)`.
- **`sourceTafKeepsItsChangeGroupsOnSeparateLines`:** page 319's block, line for line.
- **`codedReportGroupsAreTheReportFormatsTokens`:** group counts. Prose is nil, and capitals
  (`PILOT WEATHER REPORTS`, `VFR IFR MVFR LIFR`) count zero.
- **`syntheticCodedReportRunsFollowTheFormatNotTheGeometry`:**
  - Joins: the METAR run, and change-group breaks.
  - Runs end at free capitals without `RMK`, prose, or another report.
  - Controls that make no run: a single coded line, a lone type over prose, two-group lines.
  - Geometry controls: added space and another column.

Expectations that moved:

- **`TallRowsAndMinusTests.sourceMinusLinesOutsideJoinedRowsStayListLines`** (#109) pinned page 2's
  minus items without their wrapped lines. It now expects the whole items. They are still list
  lines.
- **`TaggedSplitsAndTitlesTests.codedReportsListsAndTableRowsStayApartAtTheirTagBoundaries`** (#89)
  read the TAF's separation from paragraphs. It now reads each change group as a line of the
  report's block, and requires no paragraph to hold `FM1500`.

**Checker.** `tools/check_corpus_content.py` gains `preformattedLines`: one `<pre>` must hold each
named line whole and in order, read before whitespace normalization. `tools/test_corpus_content.py`
adds one test. Positive: a kept block. Negatives: lines merged into one, split across blocks, set
as paragraphs, reordered, or a prefix. Invalid shapes raise. The key is documented in
`doc/regression-testing.md`.

**Contracts** (`tools/addcontract.py`).

Wallace (162 → 172 checks):
- `listItems` for page 2's six joined items and page 64's two;
- page 9's `separates` paragraph, and `absentText` for `sep-arates`.

FAA (463 → 468 checks):
- `listItems` for the reports on 316, 317 and 318;
- controls: `paragraphs` for 316's `A typical METAR report…` and 318's `Explanation:`;
- page 319's `distinctParagraphs` pair, which read the TAF's separation from `<p>`, is replaced by a
  `preformattedLines` check of all seven lines.

## Verification

- **`swift test`:** 535 tests pass (527 at `43b20aa` plus 8).
- **Negative control** (`tools/negative-control.sh`, `before-tests.log.gz`). The three affected
  suites ran against `43b20aa`'s `LayoutReconstructor.swift`, with only the pure helpers grafted
  on: the recogniser and `inflectedForms`/`inflectionVouches`, which that `blocks`/`joinOperation`
  never call. Result: 8 of 25 tests fail, with 26 issues.
  - Failing: every source reproducer, the synthetic tall-marker positives, the four survey joins,
    and both moved expectations.
  - Passing: every control, the group-count text rules, and the run helper's own synthetic test
    (which tests the grafted helper).
- **Guard mutations** (`tools/mutate.py`, `guard-mutations.log`). All 12 are killed:
  - the list allowance, its sentence guard (#95's exercise-column test catches it too) and the
    display cap;
  - the inflection tier, its halves guard, its compound-forms guard and its length floor;
  - change-group breaks, the opens-report guard, free capitals without `RMK`, the geometry bounds,
    and a two-group opener.
- **`scripts/check-all.sh --fast`:** exit 0. 535 Swift tests, 211 Python tests, fixture and policy
  conversions with repeat identity, and the concurrency trials.

## Lane

One case per invocation (`tools/lane.sh`, `tools/compare.sh`), with summaries in `lane-summaries/`
and block diffs in `block-diffs/`. Every run passed EPUBCheck, the structural gate, the progress
gate and the memory gate, with no memory-gate failure.

| Case | Baseline | Checks | Baseline result | Candidate | Changed pages | Other changes |
| --- | --- | ---: | --- | --- | --- | --- |
| wallace-algebra-2010 | `9bf4e76` | 172 | fails exactly the 10 new reproducers | pass | 2, 9, 64 | `warnings` (page 9); no image, navigation, OCR or marker change |
| faa-phak-8083-25c | `9bf4e76` | 468 | fails exactly the 4 new reproducers (316, 317, 318, 319) | pass | 316, 317, 318, 319 | none |
| fed-explained-2021 | `43b20aa` | 166 | pass | pass | 16, 17, 19, 31, 54, 60, 122 | `warnings`; no image, navigation or marker change |
| gpo-911-2004 | `43b20aa` | 193 | pass | pass | 48 pages (below) | `warnings`; no image, navigation or marker change |

Before the contract change, the FAA candidate failed only the old `distinctParagraphs` check on page
319, and Wallace passed both ways. Every hunk was reviewed:

- **Wallace 2:** the six joins above.
- **Wallace 9:** `sep-arates` → `separates`, and the page's warning goes.
- **Wallace 64:** the `More than` and `Less than` bullets each keep their wrapped line
  (`writing the second part plus the first`, `well, writing the second part minus the first`),
  checked against the render. Their tall rectangles overlapped the same way.
- **FAA 316–319:** the reports above.
- **Fed:** exactly the survey's 8 hyphen repairs; page 19 has two. `warnings` drops where the repair
  was the page's only uncertain break.
- **9/11:** exactly the survey's 42 hyphen repairs on 40 pages (77 and 93 have two). The other 8
  pages (71, 102, 156, 164, 166, 173, 235, 298) change only `noterefs`. The comparison includes each reference's target
  note text, and those notes hold a repaired word (`Appre-hension`, `Mag-azine`, …).
- **No list, paragraph or reading-order change** in Fed or 9/11. Their bullet lists, numbered notes
  and FAA's bullet lists are controls that did not move.

## Remaining gaps

- A single-line coded report (none in the corpus) keeps today's paragraph. Only a report set over
  two or more lines becomes a block.
- Wallace page 2's Notice address is its own paragraph after the Notice item. It is a spaced display
  line inside the item.
- The inflection tier knows only `s es d ed ing ly` and a dropped `e`. A doubled consonant
  (`refer-ring`, from `referred`) works only because `referred` shares the doubled stem. Irregular
  forms get no evidence.

## Defects to file

- **Hyphen evidence misses words printed with ligatures.** Wallace sets `diﬀerent` with U+FB00, but
  a line break extracts `dif-` + `ferent` (pages 50, 218). The vocabulary never matches the joined
  letters, so the hyphen is kept and warned. Expected: `different`. Vocabulary collection or the
  join lookup should fold compatibility ligatures (`ﬀ ﬁ ﬂ ﬃ ﬄ`).
- **A spaced example line under a list item runs into the item** (Wallace page 64). `Three more than
  a number becomes x + 3` is set under the `More than` bullet after added space, as its own example
  line. Before and after this change, it continues the wrapped line's text
  (`…plus the first Three more than…`). Expected: the example stays a separate line or block. The
  same holds for `Four less than…`. `continuesListItem` has no added-space test once the hanging
  indent is established.
- **The `Is` bullet on Wallace page 64 disappears into a formula crop.** `• Is (or other forms of
  is: …) often represents equals (=)` and its example `x is 5 becomes x = 5` are inside a preserved
  region image. The item text is lost from the reflowed page (the `(=)` and `x = 5` glyphs trigger
  the crop). Expected: the bullet as text.
