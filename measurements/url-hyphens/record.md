# Line-end hyphens inside web addresses (#88)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, Xcode 27.0 (27A266a),
release CLIs. Baseline: `d63bbbc`, built from `git archive d63bbbc` into a scratch tree (release
SHA-256 `c1ddf7e7…`). Candidate: `d63bbbc` plus this working tree (release `747b5f8e…`). Source:
The Fed Explained `the-fed-explained.pdf` (`8db8fd9e…`). Pages 36 and 46 were rendered with Poppler
(`pdftoppm -r 110`) and read, and their text layer (`pdftotext -layout`) and link annotations
(`mutool show … Annots/*/A/URI`) were checked.

## What was wrong

`joinOperation` sent a line-end hyphen inside a web address before a lowercase letter to the prose
hyphen policy, as #79 left it. That policy removes the hyphen when the book knows the joined letters
and not the compound. For addresses it is wrong in both directions.

- **Page 36** (folio 32, sidebar). The line `time, see https://www.federalreserve.gov/monetary-` is
  followed by `policy/bst_crisisresponse.htm.` The render and text layer both show a hyphen. The link
  annotation is `https://www.federalreserve.gov/monetarypolicy/bst_crisisresponse.htm`, so the
  hyphen is the typesetter's. The EPUB read `…/monetary-policy/bst_crisisresponse.htm` because the
  book holds the compound `monetary-policy` (page 46's `…implementing-` + `monetary-policy.htm.`).
- **Page 46** (folio 42, sidebar). The line `https://research.stlouisfed.org/publications/page1-` is
  followed by `econ/2020/08/03/the-feds-new-monetary-policy-tools.` The annotation is
  `…/publications/page1- econ/…`, and the St. Louis Fed publication path is `page1-econ`, so the
  hyphen is real. The EPUB read `page1econ`. The policy took only the letters before the hyphen,
  which is nothing after the digit `1`. The joined "word" was therefore `econ`, which the book knows.

The typesetter does both inside addresses, so no break shape decides.

## What changed

`Sources/PDFReflowLib/LayoutReconstructor.swift`. No public API or default changed, and no new
parameters were added.

- **Address evidence (`addAddressVocabulary`).** `addVocabulary` also records every address on each
  line in the same set, under a `\u{1}` prefix that no word can hold (the vocabulary's only reader is
  `joinOperation`). A word is an address when it holds `/` or `www.` and `trailingAddress` accepts
  its URL-character run. Each address is lowercased, loses its scheme, `www.` and trailing
  `. , ; : ) ]`, and is recorded two ways:
  - every prefix ending at `/ . ? # & = :` or at the end (`federalreserve.gov`,
    `federalreserve.gov/monetarypolicy`, …);
  - every segment between those characters (`monetarypolicy`, `bst_crisisresponse`, …).

  An address that ends its line may continue on the next, so its last segment is dropped. A line's
  first word without a scheme or `www.` may be the rest of a broken address (`federalre-` +
  `serve.gov/…`), so its first segment is not recorded as a segment (its prefixes can never match a
  whole address).
- **Decision (`addressHyphenOperation`).** It applies when `joinOperation` reaches a `-` before a
  lowercase letter and `trailingAddress(left)` is an address. `left` is the accumulated block text,
  so an address carried over several lines is whole. The broken segment continues up to the next
  delimiter on the right. Two forms are compared: `removed` (without the hyphen) and `kept`.
  1. **Address.** If exactly one form's address, through the broken segment, is a recorded prefix,
     that form wins.
  2. **Segment.** Otherwise, if exactly one form's broken segment is a recorded segment, that form
     wins.
  3. **Word.** Otherwise the hyphen is removed only when all three hold:
     - the letter runs on either side have no digit next to them;
     - they join into a book word;
     - they are not both book words.

     This is Fed page 27's `communi-` + `cations.htm`. `cations` is a book word only as the start
     of a line after a prose hyphen, and `communi` is not a word. The digit condition stops
     `page1-` + `econ`. The "not both" condition stops `monetary-` + `policy` and
     `forward-` + `guidance`.
  4. Otherwise the hyphen stays and the page gets `uncertainHyphen` (one per page, as before).

  A kept or removed decision from tiers 1 and 2 adds no warning. The prose policy and #79/#70 joins
  are unchanged. The warning helper is shared with the prose path, which behaves the same.

## Corpus survey

`survey-url-hyphens.py` finds breaks as #79's `survey-url.py` does (its `hyphen policy` category)
in native line dumps (`measurements/list-marker-pieces/dump-lines.swift`). It mirrors the evidence
collection and decision above, and also reports the old policy's decision. The full listing is in
`survey.txt`. The Fed and 9/11 results were checked against the candidate and baseline EPUBs:
every break's text in the EPUB matches the mirror.

| Document | Breaks | Address | Segment | Word | No evidence (kept, warned) | Text changes |
| --- | --- | --- | --- | --- | --- | --- |
| fed-explained-2021 | 14 | 7 (6 removed, 1 kept) | 0 | 1 | 6 | 2 |
| gpo-911-2004 | 1 | 1 (removed) | 0 | 0 | 0 | 0 |
| faa-phak-8083-25c, scotus-loper-bright-2024, usgs-mcs2025-copper, arxiv-replay-clocks-2023 | 0 | – | – | – | – | – |
| noaa-nca5-2023 (outside the gate, mirror only) | 361 | 10 (kept) | 2 (kept) | 0 | 349 | 17 |

**Fed, every break reviewed against the link annotations or render.** All 14 are right after the
change. Two were wrong before.

| Page | Break | Source | Before | After (tier) |
| --- | --- | --- | --- | --- |
| 20 | `structure-federal-open-` + `market-committee.htm` | real | kept | kept, warned (none) |
| 27 | `…-and-communi-` + `cations.htm` | typesetter | removed | removed (word) |
| 36 | `gov/monetary-` + `policy/bst_crisisresponse.htm` | typesetter | **kept** | removed (address) |
| 36 | `timeline-forward-` + `guidance-…` | real | kept | kept, warned (none) |
| 46 | `…implementing-` + `monetary-policy.htm` | real | kept | kept, warned (none) |
| 46 | `publications/page1-` + `econ/…` | real | **removed** | kept, warned (none) |
| 54 | `financial-stability-` + `report.htm` | real | kept | kept, warned (none) |
| 63 | `financial-markets-financial-` + `institutions-…` | real | kept | kept (address) |
| 81 | `supervisionreg/dfa-` + `stress-tests.htm` | real | kept | kept, warned (none) |
| 85 | `www.federalre-` + `serve.gov/…` | typesetter | removed | removed (address) |
| 122 | `gov/supervi-` + `sionreg/…` | typesetter | removed | removed (address) |
| 125 | `gov/consumer-` + `scommunities/cra_about.htm` | typesetter | removed | removed (address) |
| 125 | `gov/publica-` + `tions/annual-report.htm` | typesetter | removed | removed (address) |
| 129 | `gov/consumer-` + `scommunities.htm` | typesetter | removed | removed (address) |

**9/11 page 580.** `www.white-` + `house.gov/news/releases/…` is removed on both builds, now by the
address `whitehouse.gov` elsewhere in the book.

**NOAA** (not converted: the case is outside the gate). The mirror shows 17 breaks whose text would
change from removed to kept with a warning, all reviewed by reading the address:
- 16 are real hyphens. The old policy removed 15 because the letters before the hyphen stopped at
  a digit (`report-2020-2021-` + `southwestern-us-drought` ×2, `item/5674-` + `fierce-climate-…` ×4,
  `executive-order-14008-` + `tackling-…`, `highway-1-` + `realignment-…`, `last-20-` + `years-…`,
  `post-2015-` + `frameworks-…`, `2010-2013-` + `assessing-…`, `Plan-7142021-` + `compressed.pdf`,
  `guidance-2018-` + `update.html`, `2020/dec/2020-` + `commonwealth-…`, `bill-no.-2813-` +
  `draft-1.pdf`). It removed `the-public-` + `health-implications-…` because the book holds
  `publichealth` (from `publichealth.gwu.edu`).
- One is a regression: `census.gov/programs-surveys/community-resilience-es-` + `timates.html`.
  The source is `estimates`, but `es` (the line-start fragment in `citi-` + `es`) and `timates`
  (this break's own continuation line) are both in the vocabulary, so the word tier declines. The
  hyphen is kept with a warning, not silently.

Another 34 NOAA breaks keep the same text and gain a warning, because the old policy trusted a
compound. Two keep the same text and lose a warning, because their address was seen hyphenated.

## Before and after

Release CLIs, library defaults, `tools/run_corpus_regressions.py` one case per call with a shared
capability probe (`tools/probe-raster-environment.swift`), compared by
`tools/compare_conversion_runs.py --allow-different-converters --detail`, plus a word-level text
diff of changed pages.

| Book | Changed pages | Text changes | Images | Navigation / report fields | Warnings | Peak RSS (MiB) |
| --- | --- | --- | --- | --- | --- | --- |
| fed-explained-2021 | 36, 46 | 2 (below) | unchanged | unchanged | 523 → 523 | 233 → 215 |
| gpo-911-2004 | none (tool passes) | 0 | unchanged | unchanged | 827 → 827 | – |
| faa-phak-8083-25c | none (tool passes) | 0 | unchanged | unchanged | 1,655 → 1,655 | 709 → 845 |

- Fed 36: `https://www.federalreserve.gov/monetary-policy/bst_crisisresponse.htm.` →
  `https://www.federalreserve.gov/monetarypolicy/bst_crisisresponse.htm.`
- Fed 46: `https://research.stlouisfed.org/publications/page1econ/2020/08/03/the-feds-new-monetary-policy-tools.` →
  `…/publications/page1-econ/2020/08/03/the-feds-new-monetary-policy-tools.`
- Pages 36 and 46 already carried `uncertainHyphen` from other breaks, so warning totals do not move.
- EPUBCheck completes on all six runs, and every progress, memory and content gate passes. FAA's
  RSS difference is within the host-load variation seen in the #79 record (843 → 791), under
  six-agent load.

An earlier candidate, whose word tier required neither piece to be a word, changed Fed page 27 to
`communi-cations.htm`. That is why the tier accepts one non-word piece.

## Contracts

`corpus/regressions.json` (Fed) gains 9 checks and 3 review pages: 1,116 checks on 251 pages.
- **Page 36:** the paragraph ending `…/monetarypolicy/bst_crisisresponse.htm.` and
  `absentText: monetary-policy/bst_crisisresponse`.
- **Page 46:** the paragraph ending `…/publications/page1-econ/…tools.`, `absentText: page1econ`, and
  `warningCodesAnyOf: uncertainHyphen`.
- **Controls:** page 27's paragraph ending `…tools-and-communications.htm.` with
  `absentText: communi-cations`, page 81's `…/dfa-stress-tests.htm.`, and page 85's
  `…/supervisionreg/srletters/srletters.htm.`

Negative control: `tools/check_corpus_content.py` against the baseline evaluation fails exactly the
four reproducer expectations (the page 36 paragraph and absence, and the page 46 paragraph and
absence). The candidate passes all 147 Fed checks. The controls pass on both.
`doc/regression-testing.md`'s coverage sentence, the Fed `basis`, `doc/architecture.md`'s join
paragraph and README's hyphen bullet are updated.

## Verification

- **`swift test`:** 429 tests pass (8 new in `AddressHyphenTests.swift`).
  - Address-tier removal (Fed 36, 9/11 580) and keep (`page1-econ` seen elsewhere).
  - Segment tier (`dfa-stress-tests`, `supervisionreg`).
  - No evidence: kept with a warning (Fed 46, and Fed 36 with prose words only, both forms seen).
  - Word tier (`communi-cations`, digit guards, `forward-guidance` control).
  - Evidence rules: last segment at a line end, first segment of a line-initial fragment, a
    continuation after `https://www.`, and address entries never answering word lookups.
  - Prose policy controls, and #79's digit-hyphen join.
  - Fixtures `fed-36` (new) and `fed-46` with the two pages' vocabulary.

  `fed-46-layout.json` was recaptured with `tools/capture-layout-fixture.swift`. The only change is
  the `paints` key (335 added lines, none removed). Without the sidebar frame the address and its
  continuation fall into separate blocks. `HeadingTests`, the fixture's other user, passes.
- **Negative control for the suite:** the tests compiled with `addressHyphenOperation` bypassed
  (the `d63bbbc` decision).
  - 10 reproducer expectations fail across the seven new unit tests. The fixture test fails its 4
    page 36/46 expectations, and its `timeline-forward-` control passes.
  - Also passing: `proseHyphenPolicyIsUnchanged`, `hyphenPolicyStillDecidesLowercaseBreaksInsideAddresses`,
    #79's 30 join cases, `faaPage372…`, `fedPage37…` and `trailingAddress…`.
- **`scripts/check-all.sh --fast`:** exit 0 (429 Swift, 196 Python, 13 policy conversions and 22
  rejection cases, repeat-run identity on six fixtures).
- `git diff --check` clean.

## Remaining gaps

- The word tier cannot tell a word from a line-start fragment of prose hyphenation, because the
  vocabulary is a set. It keeps (and warns about) a typesetter split whose two pieces are both such
  fragments (NOAA's `es-` + `timates.html`).
- Breaks inside an address before a digit or capital still follow #79 (hyphen kept, no space).
