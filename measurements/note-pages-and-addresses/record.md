# Refused endnote pages and web addresses broken across lines (#80, #79)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64 release CLIs. Work began on
`78a4ba1`, was merged with `5bf5e59`, `7a29c09` and `4bc0914` (keeping both sides; the only conflicts
were `blocks`' parameter list, the pipeline call, the contract file and the coverage counts), and is
measured against a `4bc0914` baseline built from `git archive 4bc0914` (release SHA-256 `ffcf9928…`).
The candidate is `4bc0914` plus this working tree (release `ede39982…`). The same comparison against
`5bf5e59` and `7a29c09` baselines produced identical word diffs, link counts and image changes in all
three changed books. Sources: 9/11 `GPO-911REPORT.pdf` (`657d4147…`), The Fed Explained
`the-fed-explained.pdf` (`8db8fd9e…`), FAA `faa-h-8083-25c.pdf` (`247929ca…`). Pages 543, 571, 572,
578 and 581–583 (9/11), 37 and 83 (Fed) and 92 and 372 (FAA) were rendered with Poppler and read.

## What was wrong

**#80.** On 9/11 endnote pages 543, 571, 572, 578 and 581–583, `NumberedNoteDetector` refused the
page. Each note's first line then became a `<pre>` list item and its wrapped lines, which return to
the marker's left edge, became separate paragraphs. #50's list continuation needs a hanging indent,
so it did not help, and no note on those pages could be linked. The #11 record's refusal reasons,
re-measured on `78a4ba1` with the detector's own `analyze` reasons, were:

| Page | Refusal | Cause |
| --- | --- | --- |
| 571, 581, 582, 583 | image element | A line citing an address with a query string (`companies_list.asp?letter=a`, `print.php3?ReportID=145`, `display?theme=45&content=3498&print=true`, `newsflash.asp?Mode=View&articleid=1686&Category=All`) matched `graphicsWithLabels`' formula test: an `=` with at most 12 words. Its ±8 pt crop swallowed one to five note lines into an image. |
| 572, 578 | no heading | `NOTES TO CHAPTERS 9-10` / `10-11` named no single chapter. Both pages switch chapters at `10 Wartime` / `11 Foresight—and Hindsight`. |
| 543 | gap | Note 107 introduces a numbered list of candidate operatives (`1.` … `6.`, `4 and 5.`). The items sit 12 pt inside the note indent after 9.7 pt of added space, wrap back to the note indent, and run onto page 544. |
| 583 | gap (after the crop fix) | Note 4 of chapter 13 ends with five bullets at the note indent after added space, wrapping 4 pt in. |

Pages 496 and 575 (refused in the #11 record) and #62's head-removal pages already passed on `78a4ba1`.

**#79.** `joinOperation` joined lines with a space except after a soft hyphen, a line-ending hyphen
(vocabulary policy) or #70's slash. A break inside a web address therefore rejoined with a space:
Fed page 37's `…/monetarypolicy/bst_` + `openmarketops.htm.` became `bst_ openmarketops.htm`, FAA page
372's `(NACO)—www.faa.` + `gov/air_traffic/…` became `www.faa. gov/…`, and 9/11 page 581's
`…cfm?content_` + `item_id=1645…` split the same way.

## What changed

`Sources/PDFReflowLib/NumberedNoteDetector.swift`, `LayoutReconstructor.swift` and
`PDFReflowLibPipeline.swift`. No public API or default changed.

- **Two-chapter heads.** `NumberedNoteDetector.chapters(on:)` reads `NOTES TO CHAPTER N` as `N...N` and
  `NOTES TO CHAPTERS N-M` (hyphen or en dash) as `N...M`, only for `M == N + 1`. `chapter(on:)` returns
  the first chapter. The pipeline keeps the range and passes it to `blocks(…, noteChapter:,
  noteLastChapter:)`. `analyze` accepts a two-chapter page only if the existing mid-page `N+1 Title`
  switch has reached `M`. The page is still not body for `NoteLinker`.
- **Lists inside a note.** While a note is open, a list opens with a bullet (`• ` and four letters)
  at or up to three body sizes inside the note indent, or with `1.` (or `1 and 2.`) followed by a
  capital one to three body sizes inside it. The added space before it may reach 1.6 body sizes
  instead of 0.8. Following items sit on the same edge: bullets, or numbers counting on. Bullets wrap
  to one hanging edge 0.25–1.5 body sizes in. Numbered items wrap back to the note indent, but never
  on a line numbered as the note the sequence expects. An unnumbered line of at least ten letters on
  a numbered item's edge is a further paragraph. Every item is a further paragraph of the note (no
  `NoteKey`). Any other line closes the list and meets the existing rules. These shapes all refused
  a page before, so pages the detector already accepted cannot change.
- **Formula seeds.** A line seeds a formula crop through its `=` only when a word holding `=` is not
  `isURLQuery`: an address with `?` before the `=` and a `/` or `.` before the `?`, or two or more
  `name=value` pairs joined by `&`. Mathematical-symbol lines are unchanged.
- **Address joins (`addressContinues`).** `trailingAddress` is the run of URL characters ending the
  joined text, so an attached em dash or quote is not part of it, without leading `( [ < : ; ,`. It
  must hold a dot and have a scheme, start with `www.` or open with `domain.tld/`. The break joins
  with no space when the address:
  - ends in a percent escape (`Lithium%20` + `Batteries…`) before a letter, digit or `%`;
  - ends in `_ = & ? # ~` after a letter or digit, before a letter or digit;
  - ends in `.` after a letter or digit, before a lowercase letter, or before a digit starting a
    word that is not a bare number (`14693062.` + `2022.2061405`; never `45.` or `2004`);
  - ends in `-` before a digit or capital (hyphen kept);
  - ends in a letter or digit before `/ . _ ? # = & % ~` and a letter or digit (break before).

  A `-` before a lowercase letter stays with the vocabulary hyphen policy, because the Fed's
  typesetter hyphenates inside addresses (`communi-` + `cations.htm`, `federalre-` + `serve.gov`) as
  well as breaking at real hyphens (`dfa-` + `stress-tests.htm`). A period after `)` or before a
  capital ends the sentence. #69's list continuation also uses the test: a marker line ending inside
  an address (`• Aeronautical Information Manual (AIM)—www.faa.`) keeps its first wrapped line.

## Corpus survey (#79)

`survey-url.py` applies `trailingAddress`/`addressContinues` to native line dumps of the 16 English
documents (`measurements/list-marker-pieces/dump-lines.swift`). It runs before furniture, image,
table and note handling, so its counts are upper bounds. Full listing: `survey-url.txt` (NOAA detail
truncated to 15 per category). `carried` marks a break whose address began on an earlier line. In
NOAA's reference lists most `carried` hits pair an address with an entry number in the neighbouring
column, which is a survey artifact.

| Document | Joins (by character) | Hyphen policy (unchanged) | Space kept | Unmarked |
| --- | --- | --- | --- | --- |
| faa-phak-8083-25c | 10 (`.` 8, `_` 2) | 0 | 0 | 0 |
| fed-explained-2021 | 25 (`.` 22, `_` 2, before `/` 1) | 14 | 0 | 0 |
| gpo-911-2004 | 5 (`-` 1, `_` 1, before `/` 3) | 1 | 28 (`).` sentence ends) | 0 |
| cia-blue-book-14-1955 | 0 | 0 | 1 (OCR) | 0 |
| noaa-nca5-2023 (outside the gate) | 2,077 (`.` 1,726, `-` 251, `_` 71, `%` 19, before `.` 6, before `/` 2, `#` 1, `=` 1) | 361 | 191 | 14 |
| Warren, algebra, Loper Bright, DGA, Our Flag, CDC, USGS, NBS, arXiv, Census | 0 | 0 | 0 | 0 |

Review of the gated books (every hit): the 10 FAA, 25 Fed and 5 9/11 joins are all addresses broken
mid-address in the source and all rejoin correctly (listed in `text-diffs.txt`). All 28 kept 9/11
spaces are `…html).` + `NN.` note starts. Of the Fed's 14 lowercase hyphen breaks, 7 are real
hyphens and 7 typesetter hyphens. The unchanged vocabulary policy gets 12 right and 2 wrong (below).
NOAA was reviewed by sampling each category: DOIs (`s41598-` + `020-62188-4`, `10.1080/14693062.` +
`2022.2061405`), file slugs (`E3_` + `Residential_…`, `USVI-` + `Snapshot_red.pdf`) and percent
escapes all join correctly. Its `unmarked` breaks (`https://doi.org/10.1` + `080/…`) carry no URL
character and stay spaced.

## Before and after

Release CLIs, library defaults, `tools/run_corpus_regressions.py` one case at a time with a shared
capability probe; comparisons by `tools/compare_conversion_runs.py --allow-different-converters`,
a block-level page comparison, an image-content comparison and a word-level text diff.

| Book | Pages whose blocks change | Pages whose text changes | Images (identical by content) | Warnings | Content checks (candidate / baseline) |
| --- | --- | --- | --- | --- | --- |
| gpo-911-2004 | 84 | 9 (7 beyond spacing) | 520 → 516 (516) | 945 → 941 | 176 pass / 33 fail |
| fed-explained-2021 | 23 | 23 (1 beyond spacing) | 262 → 261 (261) | 528 → 528 | 135 pass / 9 fail |
| faa-phak-8083-25c | 8 | 8 (1 beyond spacing) | 599 → 598 (598) | 1,450 → 1,449 | 154 pass / 7 fail |
| scotus-loper-bright-2024 | 0 | 0 | 0 | 296 → 296 | 91 pass / 91 pass |
| wallace-algebra-2010 | 0 | 0 | 2,047 → 2,047 (2,047) | 913 → 913 | 92 pass / 92 pass |

The comparison tool passes Loper Bright and Wallace outright (no changed pages, images or report
fields). For the other three it lists more pages and images than the table because every image after
a removed crop is renumbered (`changedImages`: 9/11 15, FAA 499, Fed 101 on the `7a29c09` comparison). The content comparison above shows
that no remaining image changed.

### 9/11: note links per chapter

Superscript digit runs in body blocks on pages 19–467, chapter from the outline openings (#11). The
#11 record counted 1,459 of 1,564 on `162cf60` with a different marker count; this table counts one
way on both sides.

| Chapter | Linked before | Plain before | Linked after | Plain after |
| --- | --- | --- | --- | --- |
| 1 | 241 | 0 | 241 | 0 |
| 2 | 93 | 0 | 93 | 0 |
| 3 | 94 | 20 | 94 | 20 |
| 4 | 174 | 20 | 174 | 20 |
| 5 | 108 | 1 | 108 | 1 |
| 6 | 206 | 4 | 206 | 4 |
| 7 | 155 | 10 | 162 | 3 |
| 8 | 98 | 0 | 98 | 0 |
| 9 | 159 | 14 | 173 | 0 |
| 10 | 63 | 23 | 82 | 4 |
| 11 | 27 | 13 | 39 | 1 |
| 12 | 12 | 30 | 39 | 3 |
| 13 | 11 | 11 | 15 | 7 |
| **Total** | **1,441** | **146** | **1,524** | **63** |

All 83 new links point at notes on the seven claimed pages. Every link resolves and returns (the lane's
EPUB checks and ten new `noteLinks` contracts). All 117 headed notes pages (469–585) now pass the
detector; `468` is the unheaded `Notes` title. The 63 plain markers are all present on the baseline.
- 40 (chapters 3 and 4, notes 93–112) collide through page 496's misprinted head (defect 1).
- 16 (chapters 7 and 10–13) sit inside `<pre>` bullet or list items, which `NoteLinker` does not scan
  (defect 3).
- 2 are chapter 7's 7 and 9 (defect 2).
- 5 are chapter 6's four markers on page 205 and chapter 5's 85 on page 183 (not investigated).

### 9/11: reviewed changes

- **74 body pages** differ only in link markup (the new `<sup><a epub:type="noteref">` wrappers). This
  includes #11's documented case of a marker extracted as `N ` writing its trailing space after the
  link (pages 344, 354, 356, 359–362, 421). No body text changed.
- **543.** Notes 100–107 are paragraphs keyed `c7-100…107`. Note 107 ends `The candidate operatives
  were`, and its items `1.`, `2.`, `3.`, `4 and 5.`, `6.` follow as paragraphs, each holding its wrapped
  lines (`mus-` + `cle` now repairs to `muscle`). Item 6 continues onto page 544 as before.
- **571.** The crop is gone. Note 200 reads `…(online at http://worldtradeaftermath.com/…?letter=a); CNN,WTC
  tenants, 2001 (online at www.cnn.com/SPECIALS/2001/trade.center/tenants1.html); September 11 personal
  tributes…`, matching the render. The `Original page 571` reference image used to split note 208
  mid-sentence (`was the [image] alleged failure`). It now precedes the whole note, as #45 places
  images ahead of a joined paragraph. The same move happens on 582.
- **572 / 578.** Chapter 9 notes 209–210 then `10 Wartime` and chapter 10 notes 1–8 (572); chapter 10
  notes 76–86 then `11 Foresight—and Hindsight` and chapter 11 notes 1–13 (578). Notes 4 and 5 on 572
  stay distinct.
- **581–583.** The crops are gone, and their lines are note text again (including note 24's two
  addresses and note 38's carry-over `Coun-` + `cil report,…` from 582 to 583). Note 4 of chapter 13
  keeps its five bullets as further paragraphs.
- **547.** Markup only: note c7-122's backlink now names `chapter-15.xhtml`, because the added link
  markup moved a body page into the next spine file.
- **570, 577, 581.** Addresses rejoin (`…AboutthePortAuthority` + `/PortAuthorityPolice/…`, `…/stories` +
  `/2004/…`, `…/Spec/02-` + `2004/Article…`).
- `<pre>` blocks 318 → 227. The 91 removed were note first lines and nested items on the seven pages.
  Characters +1,378: text recovered from the crops, minus joined spaces and repaired hyphens. Hyphen
  repairs in newly joined notes: 13, 12 of them to the dictionary word (`muscle`, `Commanders`,
  `transcripts`, …). `Non-` + `proliferation` keeps its hyphen under the unchanged policy;
  `uncertainHyphen` warnings are unchanged (141, one per page).

### Fed and FAA: reviewed changes

- **Fed.** 25 address joins on 22 pages (`https://www.` + `federalreserve.gov/…`,
  `federalreserve.` + `gov/…`, `…gov` + `/monetarypolicy/…`, `bst_` + `openmarketops.htm`,
  `central_bank_hub_` + `overview.htm` in page 64's table, `paymentsystems.` + `htm`, …). Page 83's `https://www.ecfr.gov/cgi-bin/ECFR?page=browse` line
  had seeded a crop that held three lines of the figure's note. They are text again: `…Federal Reserve
  regulations governing the payment system,” on page 109. To view the full text of these and other
  Federal Reserve regulations, visit https://www.ecfr.gov/cgi-bin/ECFR?page=browse and select “Title
  12” of the Code of Federal Regulations.`
- **FAA.** 10 address joins on 8 pages, including both page-372 bullets: NACO's wrapped item line, and
  the AIM item whose marker line ends inside `www.faa.` (the #50 list-continuation case). Page 92's
  `www.srh.noaa.gov/epz/?n=wxcalc_densityaltitude` crop had split its paragraph. The paragraph is whole
  again; the page's two heading ids renumber (`heading-92-7` → `-5`, `-9` → `-7`).

## Contracts

`corpus/regressions.json`, applied to `4bc0914`'s file (which holds 895 checks on 183 pages), gains 50
checks on 16 new pages, for 945 checks on 199 pages.
- **9/11 (+34).** Paragraph checks for whole notes, items and bullets on 543, 571, 572, 578 and
  581–583. Distinct-paragraph checks keep items and notes apart (543, 572, 583). There are absent
  checks for `mus- cle` and `content_ item_id`, a continuation check for note 38 across 582/583, and
  address text on 570 and 581. Ten `noteLinks` run from body pages 253 (×2), 334, 341, 343, 356, 357,
  393, 406 and 422 to notes on the claimed pages. Pages 581–583's `minimumImages` changes from 2 to 1.
  The second image #62's review counted was the false crop; the reference image remains.
- **Fed (+8).** Page 37's text becomes the whole sentence ending `bst_openmarketops.htm.` plus
  `absentText: bst_ openmarketops`. New checks cover the address text on 19, 36, 64 and 105 (with
  `paymentsystems. htm` absent) and page 83's recovered sentence.
- **FAA (+8).** Page 92's two paragraphs. Page 372's three bullets as `listItems`, the third being #70's
  slash control, plus `absentText: www.faa. gov`. Page 25's two addresses.

Negative control: the content checker against the `4bc0914` evaluations fails exactly the new
reproducer expectations: 33 on 9/11, 9 on Fed, 7 on FAA. The controls pass on both builds: the
`minimumImages: 1` edits, the FAA 372 slash item, and the Loper Bright and Wallace contracts. So does
9/11 581's `content_ item_id` absence, where the text was entirely in the crop before.
`doc/regression-testing.md`'s coverage sentence and test count, and `basis` sentences for the three
cases, are updated.

## Verification

- `swift test`: 379 tests pass (368 on `4bc0914` plus 11). The new tests are
  `UnclaimedNotePageTests.swift` (source fixtures `911-543`, `911-571`, `911-572`, `911-578`,
  `911-581`–`583`; head parsing and the two-chapter requirement; list shapes with five refusal
  controls; URL query words, page crops and equation controls) and `AddressJoinTests.swift` (30 join
  cases including 14 space controls, hyphen-policy controls, address shape, and fixtures `fed-37` and
  `faa-372`). New fixtures `911-543`, `911-578`, `fed-37` and `faa-372` were captured with
  `tools/capture-layout-fixture.swift`. The committed `911-571/572/581/582/583` fixtures match fresh
  captures except for the empty `paints` key missing on three.
- Negative control for the suite ([before-tests.log.gz](before-tests.log.gz)): the new tests compiled
  against `4bc0914` with pass-through stubs (`chapters` = single chapter, `isURLQuery` = false,
  `trailingAddress` = nil, `noteLastChapter` ignored). 10 of 11 fail with 94 issues, all reproducer
  expectations. The join test fails exactly its 16 join cases × 2 join paths. The 14 space controls,
  the equation controls, the refusal-shaped head controls and
  `hyphenPolicyStillDecidesLowercaseBreaksInsideAddresses` pass. The same result on `7a29c09`.
- `scripts/check-all.sh --fast`: exit 0 (379 Swift, 186 Python, 13 policy conversions and 22
  rejection cases, repeat-run identity on six fixtures).
- Corpus lane, both binaries, one case per call: `gpo-911-2004`, `fed-explained-2021`,
  `faa-phak-8083-25c`, `scotus-loper-bright-2024`, `wallace-algebra-2010`. EPUBCheck 0 on all ten
  runs; progress and memory gates pass. Peak RSS: 9/11 108 → 100 MiB, Fed 286 → 283, FAA 843 → 791,
  Loper 37 → 37, Wallace 78 → 78 (host load from other agents varies these more than the builds do).
  The candidate passes every content check; the baseline fails only the new expectations (above).
- `git diff --check` clean.

## Remaining gaps and defects to file

1. **9/11 page 496's running head misprints its chapter.** It reads `478 NOTES TO CHAPTER 4` but holds
   chapter 3's notes 93–112 (page 495 ends at 92, page 497 continues with 113). The notes are keyed to
   chapter 4 and collide with page 502's real chapter-4 notes 93–112. `NoteLinker` treats both sets as
   ambiguous, so 40 markers (chapter 3 pages 115–123, chapter 4 pages 143–148) stay plain and 40 notes
   have no ids. Expected: the numbering continuing from the previous notes page scopes 496 to chapter 3.
2. **9/11 page 544 is misread as chapter 7 notes 7–9.** It holds only the continuation of note 107's
   candidate list from page 543 (items 7–9 with their wraps and further paragraphs). The detector's
   first start is the items' edge, so the items get keys `c7-7…9`. These collide with page 532's notes
   7–9, and the markers 7 and 9 on page 234 stay plain. On page 545, item `10. Abderraouf Jdey…` (before
   the page's first note, 108) is a `<pre>` holding its first line, with its wraps as paragraphs.
   Expected: the list still open at the end of 543 continues on 544–545 as further paragraphs of
   note 107. The fix needs page-to-page detector state.
3. **Markers inside list items are never linked.** `NoteLinker` scans paragraphs only, so 16 raised
   markers inside `<pre>` bullets and numbered items in 9/11 chapters 7 and 10–13 stay plain (e.g.
   page 430's 12–14, page 344's 13).
4. **Fed address hyphens decided by the vocabulary.** Page 36 reads
   `…/monetary-policy/bst_crisisresponse.htm`; the source address is `monetarypolicy`, and the
   typesetter's hyphen is kept because `monetary-policy` is a known compound. Page 46 reads
   `…/publications/page1econ/…`; the source is `page1-econ`, and the real hyphen is removed. Both
   predate this work and are unchanged.
5. Not changed: breaks inside an address with no URL character at the break (`https://doi.org/10.1` +
   `080/…`, 14 in NOAA) stay spaced. A list line that is not a bullet or `1.`-style item (for example
   lettered `a.`) still refuses a notes page. Chapter 6's four plain markers on 9/11 page 205 were not
   investigated.
