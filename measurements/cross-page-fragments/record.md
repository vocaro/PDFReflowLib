# Fragments a page's own furniture hides from the vocabulary (#107)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, release CLIs, multi-agent
host load. Baseline: `73cbdfe`, built from `git archive 73cbdfe` into a scratch tree (release
SHA-256 `25dbaaa1…`). Candidate: `73cbdfe` plus this working tree. Six lane cases ran on release
`eecc943f…`; the 9/11 report and the two non-English books ran on `7da68df2…`, which differs only
in reading the text-stream test as "a letter that is no capital" rather than "a lowercase letter",
identical on a cased script. The 9/11 report, the one case whose output moves, was rerun on
`7da68df2…` and gave the same ten pages. No public API or default changed.

## What #148 had already fixed

#107 was opened during #101 with two gaps. The first — "when a page's last body line ends in a
hyphen, the next page's opening word still counts as a book word" — is closed: #148 (commit
`c64f637`) made `addVocabulary` carry the previous page's last line in `previous`, so Loper Bright
page 11's `…And in general, it author-` already stops `izes` from being a book word on page 12.
#148 also handled half of the second gap: a page's head matter, read as the lines before its first
body-sized line, leaves the carried line standing, which covers Loper Bright's
`4 LOPER BRIGHT ENTERPRISES v. RAIMONDO` and `Opinion of the Court`.

What was left is the same furniture on the *other* side of the break, and the head matter a book
sets in the body's own size:

1. **Foot matter replaced the carry.** Every line at or after the first body-sized line overwrote
   `previous`, so the line the next page read was whatever the page ended with. Wallace's folio
   (`62` under `…varies inversely as the pres-`) and the Fed's note
   (`/monetarypolicy/fomccalendars.htm.` under `…Some of these com-`) both hid a real break.
2. **Head matter at the body's size ended the carry.** The 9/11 report sets
   `84 THE 9/11 COMMISSION REPORT` at 9.5 pt against a 10.25 pt body — inside the 15% window — so
   `reachedBody` turned true on the running head and the carried line was thrown away before the
   continuation was read. 52 breaks in that book.
3. **Head matter stood as no line at all.** Because `previous` was only assigned once
   `reachedBody` was true, a line before the page's first body-sized line was not the line above
   the line below it either, so a break among a page's opening lines was lost where the page's
   dominant size is set further down (Wallace's worked examples, the Fed's box pages).

The issue also proposes measuring "after furniture removal". That reference is necessary but not
sufficient: the Fed page 33 case is a *note*, which `FurnitureDetector` does not remove, so a rule
built on furniture removal alone would still miss it. The rule adopted reads the page's own text
stream instead, and the survey below scores it against the furniture-removed reference anyway.

## The rule

A page's **text stream** is its lines set within 15% of the page's body size that print a letter
which is no capital. A running head or a folio set in the body's own size prints none beside its
page number (`84 THE 9/11 COMMISSION REPORT`, `62`, `FROM THREAT TO THREAT 197`); a script without
case — the Arabic and Chinese corpus books — writes only such letters, so its prose reads as text
wherever it is set and nothing about those books changes.

- The carried line stands until the page's first text-stream line.
- The line carried to the next page is the page's last text-stream line; a page with none carries
  the word on untouched (a plate, a full-page table).
- Every line stands as the line above the one below it, head matter included.

`LayoutReconstructor.opensBrokenWord` holds the unchanged #101/#126/#157 test (a hyphen, a soft
hyphen or the book's own `=`; a lowercase opening; a first word with no hyphen of its own).

## Survey

`CrossPageFragmentSurvey.swift` is kept here and is not part of the package; its header says how to
run it. It reads native lines per page with hidden text removed and no OCR, as the pipeline
collects them, and builds three vocabularies that differ only in which words the fragment rule
skips: `old` (the rule before this change), `new` (the rule above) and `ref` (`FurnitureDetector`
strip, the previous surviving line, the stripped page's last line, with the removed lines' words
added back since furniture words are not fragments). A `build` helper mirrors `addVocabulary` with
the skip decision supplied; the survey asserts the mirror under `new` equals
`LayoutReconstructor.vocabulary(in:)`, so a drift between the survey and the library fails the run
rather than biasing the counts. Full output: `survey/<case>.txt`.

Every English corpus document, including the two outside the lane (Warren, #5; the Blue Book scan):

| Document | Pages | Skips old → new | Words dropped | In-page decisions changed |
| --- | ---: | ---: | ---: | ---: |
| gpo-911-2004 | 585 | 3,981 → 4,033 | 38 | 4 |
| gpo-warren-1964 (outside the lane) | 920 | 4,295 → 4,422 | 35 | 0 |
| wallace-algebra-2010 | 489 | 337 → 347 | 9 | 0 |
| fed-explained-2021 | 135 | 471 → 473 | 2 | 0 |
| cia-blue-book-14-1955 | 312 | 53 → 59 | 0 | 0 |
| nbs-jres-geltman-1977 | 7 | 24 → 25 | 0 | 0 |
| usda-ars-agresearch-2012-11 | 24 | 148 → 149 | 0 | 0 |
| faa-phak-8083-25c | 522 | 98 → 98 | 0 | 0 |
| noaa-nca5-2023 | 1,834 | 1,866 → 1,866 | 0 | 0 |
| scotus-loper-bright-2024 | 114 | 914 → 914 | 0 | 0 |
| gpo-our-flag-2003, dga-2025-2030, arxiv-replay-clocks-2023, usgs-mcs2025-copper, census-rrs2002-01, cdc-zombie-pandemic-2011, uscourts-pro-se-1-2016, the four NTRS documents | 2–56 | unchanged | 0 | 0 |

A skip only removes a word when *every* occurrence of it is a continuation, which is why six more
skips on the Blue Book, one on NBS and one on USDA drop no word at all.

**Words dropped, per book.**

- **9/11 (38):** `ated cers ernment ers fined fited gence gress ians ignating ing mally mation nent
  ness nesses nis nistan ority plete plish posals preted puter quate rorist rorists severed sible
  sibly sion sional tary tence ticipant tify tigation tion`. Every one is the tail of a word the
  page break cut under the running head: `ter-` + `rorists` (101→102), `act-` + `ing` (227→228),
  `eyewit-` + `ness` (303→304), `per-` + `severed` (244→245), `infor-` + `mally` (214→215),
  `Afgha-` + `nistan`. `severed` is the only one that is also an ordinary English word, and the
  report never prints it as one — its single occurrence is the second half of `persevered`.
- **Wallace (9):** `bers eral ested nator nect sion tion tions tive`. `bers` (212→213 `num-`),
  `ested` (134→135 `inter-`), `tion` (140→141 `substitu-`) and `tions` (107→108 `direc-`) come from
  the folio under the last body line; `eral nator nect sion tive` from breaks among a page's
  opening lines (`sev-` + `eral`, `denomi-` + `nator`, `con-` + `nect`, `expres-` + `sion`,
  `nega-` + `tive`). None is an English word.
- **Fed (2):** `munications` (33→34, under the note) and `teristics` (page 13, `charac-`). Page 34
  prints `communications` whole two lines below the break, so that word is untouched.
- **Warren (35):** `arated benzidine dentto dow ducted eluding erated eration ernor ffo ging
  hibits hk ilsapi lail longed mately migration nally parison pendant plaint portant poses
  quainted quent rogated scopic sible terial ting tributed tributor ture ures`. The book's folio
  hid its page breaks (`sepa-`, `con-`, `Gov-`, `micro-`, `com-`). `benzidine` is a real word but
  not one this book prints on its own: its only occurrence is the second half of page 588's
  `diphenyl-` + `benzidine`. `dentto ffo hk ilsapi lail` are the inherited OCR's own noise.

**Words gained: none, in any book.** The rule only ever adds skips.

**Against the furniture-removed reference.** `new` and `ref` agree on every hyphen decision in every
book (`still short of the reference: 0` throughout). They differ on words in three places:

- **NOAA, 14 words the reference drops and `new` keeps.** NOAA's running head is
  `Fifth National Climate Assessment` over `23-29 | US Caribbean`, both at the body's size and
  both printing lowercase letters, so no evidence on the page itself separates them from prose.
  This is the residual of gap 2 that only document-wide furniture evidence can close; it changes
  no decision in the book (the lane was not rerun, since the vocabulary is unchanged).
- **Fed, one word the reference keeps and `new` drops** (`munications`): the note is not furniture,
  as above, so the reference is the weaker rule here.
- **Blue Book (2) and Warren (9/3):** the reference reads its own `justifiedMeasures` off the
  stripped page, so #157's lost-hyphen test lands differently on a few OCR lines. Both sides are
  OCR noise (`faawo`, `rtjmber`, `ilsapi`); no decision moves.

## Lane: every case whose output changes, and the named controls

Release CLIs, library defaults, `tools/run_corpus_regressions.py` one case per call with
`tools/probe-raster-environment.swift`, compared by
`tools/compare_conversion_runs.py --allow-different-converters --detail`.

| Book | Baseline | Candidate | Changed pages, images, navigation, report fields |
| --- | --- | --- | --- |
| gpo-911-2004 | pass | pass | 10 pages, 6 warnings withdrawn; no image, navigation or id change |
| fed-explained-2021 | pass | pass | none |
| wallace-algebra-2010 | pass | pass | none |
| faa-phak-8083-25c | pass | pass | none |
| gpo-our-flag-2003 | pass | pass | none |
| scotus-loper-bright-2024 | pass | pass | none |
| uscis-m618-arabic-2015 | pass | pass | none |
| irs-p596-zhs-2025 | pass | pass | none |

Fed and Wallace change their vocabulary and no decision, matching the survey. The two non-English
books were converted because the text-stream test reads letter case, and both are byte-identical.
NOAA was not converted: its vocabulary is unchanged, so its output cannot be. Warren has no
successful-conversion lane (#5).

### The ten changed pages of the 9/11 report, against the source

Every one is a break the running head hid, joined the way the printed page reads. Six
`uncertainHyphen` warnings are withdrawn and none is added.

| Page | Source | Baseline | Candidate |
| --- | --- | --- | --- |
| 172 | `…came to share his preoccupa=` / `tion with attacking America` | `preoccupa-tion` | `preoccupation` |
| 181 | `…for dress=` / `ing too provocatively` | `dress-ing` | `dressing` |
| 206 | `…had been wary of endors=` / `ing them` | `endors-ing` | `endorsing` |
| 214→215 | `The paper was therefore infor-` / `mally referred to as the “Blue Sky” memo` | `infor-` at the page end | `infor`, joining `mally` |
| 244→245 | `Again, Hanjour per-` / `severed; he completed the initial training` | `per-` at the page end | `per`, joining `severed` |
| 245 | (the other half of 244's break) | `uncertainHyphen` | no warning |
| 344 | `…were grounded, strand-` / `ing tens of thousands` | `strand-ing` | `stranding` |
| 373 | `…a fully informed joint plan.Accomplish-` / `ing all this` | `plan.Accomplish-ing` | `plan.Accomplishing` |
| 388 | `…It is reveal-` / `ing that in June 2004` | `reveal-ing` | `revealing` |
| 392 | `…analysis of Saudi Arabia, contend-` / `ing that fundamentally friendly rulers` | `contend-ing` | `contending` |

Pages 172, 181 and 206 are chapters 5–9, where the report's line-end hyphen is the Bembo `equal`
glyph (#126); `restoreEqualsHyphens` had already turned them into hyphens, and only the vocabulary
decided them wrongly. Pages 214 and 244 are the cross-page shape the issue names. The joined words
are each printed whole elsewhere in the report, or reached through #115's inflected form: page
344's `stranding` is vouched for by the single `strand` on page 240.

## Tests

`CrossPageFragmentTests.swift` (10 tests). Fixtures are native extraction from the checksum-pinned
sources with their furniture kept, as the pipeline collects it; new fixtures `911-101`, `911-102`,
`911-227`, `911-228`, `911-344`, `algebra-213`, `fed-33` and `fed-34` were captured with
`tools/capture-layout-fixture.swift`. Every expected phrase was read against the rendered page.

- **Reproducers.** The folio under the last body line (Wallace 212→213, `bers`); the running head
  at the body's size (9/11 101→102, `rorists`, with the head asserted to be inside the size window
  and to print no lowercase letter); the note under the last body line (Fed 33→34, `munications`,
  with `communications` still a word); head matter as the line above (a page whose body size is its
  note size, `denomi-` + `nator`); and the decision itself (9/11 227+228+344: `ing` is no word and
  `strand-` + `ing` joins silently).
- **Controls.** The carried line is consumed by the page's own first text line, so a lowercase line
  further down keeps its word; a capital opening, a compound that keeps its own hyphen and a page
  after an unbroken line are not skipped; a page with no text stream carries the word on while one
  with prose of its own ends the carry; a caseless script reads as text wherever it is set; and
  Loper Bright 11→12 still drops `izes` with its head matter present, which #148's own test removes
  by hand.
- **Negative control.** `negative-stub.py` puts back exactly what #148 left: one `previous`, tested
  against every line and assigned by every line at or after the page's first body-sized line. With
  it, 7 of the 10 new tests fail with 9 issues and every other test in the suite passes — the three
  that still pass are the controls that must hold both ways (a capital continuation and a compound
  that keeps its own hyphen; a caseless script; Loper Bright 11→12, which #148 already fixed).

## Verification

- `swift test`: 837 tests pass (10 new).
- `scripts/check-all.sh --fast`: exit 0.
- `python3 tools/update_doc_counts.py`: the Swift-test count moved 827 → 837.
- `git diff --check` is clean.

## Limits

- The survey joins consecutive native lines, not the blocks layout builds; the lane comparisons
  cover the rest, and they found six changed pages the survey did not (the two cross-page joins and
  the four `=` pages whose decision the same words moved).
- A running head the book sets at the body's size with ordinary capitalization (NOAA's
  `23-29 | US Caribbean`) still hides its break. Closing that needs the vocabulary collected after
  furniture removal, which the two-pass pipeline cannot do without a third pass over the page
  store; it is recorded above and left as follow-up work.
- OCR pages are not surveyed, and a recognized or synthetic page still has no measure for #157's
  lost hyphens.
