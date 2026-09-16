# Folio-bearing margin lines and short head runs (#62, #10)

A running head whose text changes from page to page, and a head that alternates over too few
pages for a three-page text run, are now recognized by the page number they carry. This closes
[issue #62](https://github.com/vocaro/PDFReflowLib/issues/62) and the *short/multi-line header
runs* and *remaining margin layouts* items of
[issue #10](https://github.com/vocaro/PDFReflowLib/issues/10). Broader heading precision and
timeline row/column ownership remain open; see *Remaining* below.

Tier: deterministic Apple PDF stack, library defaults, macOS 27 arm64 release CLI.
Baseline: branch tip `26d5209` (after #43, #54, #55 and #11). Corpus: the 9/11 report
(`corpus/cache/GPO-911REPORT.pdf`, SHA-256 `657d4147…`, 585 pages) and *Loper Bright*
(`corpus/cache/22-451_7m58.pdf`, 114 pages), with the FAA handbook, The Fed Explained, Our Flag
and Wallace's algebra as controls.

## Diagnosis

`FurnitureDetector` grouped margin candidates by their **text**, normalizing at most a boundary
page number, and removed a group only where three nearby pages repeated it. Two real running
heads escape that evidence.

- **9/11 notes pages.** Physical page 572's head is `554 NOTES TO CHAPTERS 9-10`: it names two
  chapters, so no other page repeats its text and its group never reaches three. Its neighbours
  571 (`NOTES TO CHAPTER 9 553`) and 573 (`NOTES TO CHAPTER 10 555`) are removed by their own
  chapter's runs, leaving 572 stranded. Since #43 the line clears the section-label rule (short,
  capitalized, 9.5 pt over the notes' 7 pt body, clear space above) and was emitted as an `<h6>`;
  before #43 it was a paragraph, also wrong. The same happens on 578, 579, 580, 584 and 585, and
  the front-matter heads on 14, 16, 17 and 18 (`xiv COMMISSION STAFF`, `xvi PREFACE`,
  `PREFACE xvii`, `xviii PREFACE`) were never recognized at all because the boundary-number
  normalization read Arabic digits only. `450 NOTES` on 468 is the first notes page after the
  `NOTES` opening and repeats nowhere.
- **Loper Thomas concurrence.** It runs four pages (44–47), so each alternating head occurs
  twice: #40 recorded this as unfixed. Verso pages carry `2 LOPER BRIGHT ENTERPRISES v. RAIMONDO`
  / `4 LOPER BRIGHT …`, recto pages a bare folio beside `Cite as: 603 U. S. ____ (2024)`, and all
  four carry `THOMAS, J., concurring` on the second row. The second row is a four-page run and
  sat in the plan already, blocked by #40's dependency on its row above.

What every one of these lines does share is a **folio offset**: the page number at the line's
edge stays a fixed distance from the physical page (−18 through the 9/11 body, 0 in its Roman
front matter, −43 through the Thomas concurrence) while the rest of the text changes.

## What changed

`FurnitureDetector.folioValue` reads a page number at a margin line's first or last word:
Arabic (`554`), chapter-prefixed (`5-3`, whose second part numbers the page inside its chapter)
or a Roman numeral (`xiv`). A Roman reading must be the one canonical spelling of a value in
1–400 and at least two letters long, so `did`, `mill`, `civil`, `mix` and an initial `C` are not
page numbers. A line whose first word names a numbered object (`figure`, `table`, `plate`,
`chart`, `exhibit`, `map`, `box`) supplies no folio: its number counts the object, not the page.

`collect` records, beside each existing text group, every margin candidate that carries such a
number, with its edge, numeral system, offset from the physical page, type size and the other
lines on its row. Nothing new becomes a candidate: the band, separation and outermost-row rules
already decided that.

`resolveFolios` then groups those records by **edge, numeral system and offset** and looks for a
run of three or more pages at most two apart whose height in the band agrees within 0.04 of the
page and whose type size agrees within 10%. Members of such a run are furniture:

- a line that carries head text beside its folio is removed outright;
- a line that is **nothing but** a folio is not — a chapter opening's lone page number is not a
  running head — unless every other line on its row is itself removed, in which case it goes with
  that row rather than leaving half a `folio + title` row behind.

`resolve`'s existing three-occurrence text rule, its position and typography tolerances, the
two-row dependency of #40 and the synthetic-OCR path are untouched; the new pass only adds
removals. Because a run needs three pages of agreeing evidence, no single page can invent an
offset, and a book with no repeating folio gains nothing.

**Heading floor.** `LayoutReconstructor.isHeaderLike` already described a separated top-band line
that opens or closes with a page number; it gains the foot of the page (`bothBands`) and is now
consulted by `blocks()`'s `isHeadingCandidate`, so such a line is never a heading whatever
furniture removal made of it — including with `removeRepeatedHeadersAndFooters = false`. This is
the one change inside `blocks()`: one clause on the existing #55 predicate. The line keeps its
text as a paragraph; the rule decides navigation, not retention.

## Reproducers and controls

Source fixtures captured with `tools/capture-layout-fixture.swift` from the checksum-pinned PDFs:
`911-571`, `911-572`, `911-573`, `loper-44` … `loper-48`.

- `isolatedNotePageHeadGoesWithItsNeighborsFolioOffset` — pages 571–573 share no head text, so
  the text rule removes none; all three go on the shared −18 offset and every line below the band
  survives. Chapter opening `911-126` and `911-127` are in the same document: 126's bottom folio
  `108` carries the same offset and must stay, and it does, being alone on its row and outside
  the narrow footer band.
- `fourPageConcurrenceHeadsGoWithTheirOpinionsFolioOffset` — the exact removed set on each of
  Loper 44–48. Page 48 opens the Gorsuch concurrence and restarts the folio at 1, so its offset
  has one page of evidence: its folio and its opinion row stay, and only the `Cite as:` head its
  neighbours repeat is removed. The body's own `(THOMAS, J., concurring)` citations are untouched.
- `loneFoliosStayWhileFoliosBesideRemovedHeadTextGo` — over 51 pages whose heads establish the
  offset, the chapter openings at 20, 40 and 60 keep their lone foot folio; the same folios beside
  removed head text on one row leave with the row.
- `mirroredBoundaryFoliosRequireMatchingOffsetsAndMeaningfulInternalDigits` keeps #10's controls
  (offsets that do not agree, internal sequential digits) and adds a numbered figure label and a
  two-page agreement. Its "different internal chapter numbers" control is now a positive case:
  `NOTES TO CHAPTER 11 19` / `20 NOTES TO CHAPTER 12` / `NOTES TO CHAPTER 13 21` is exactly the
  9/11 shape, and the offset is the evidence the text cannot give. Roman heads are removed.
- `folioReadingAcceptsOnlyCanonicalPageNumbers` — the reading in isolation, with the word and
  initial rejections above.
- `shortSourceNotesRunCombinesLeadingAndTrailingFolios` (#10) expected 581–583 only; all seven of
  579–585 now go, and its body-line conservation is unchanged.
- `foliobearingMarginLinesAreNeverHeadings` and
  `marginFolioHeadingRuleNeedsTheBandTheFolioAndTheSeparation` — the heading floor, with controls
  for a head without a folio, a folio-bearing line inside the text block, and one the body runs
  straight into.

## Before and after

Baseline `26d5209` release CLI against this tree's, library defaults, same machine.

| Book | Blocks | Headings | `furnitureRemoved` pages | Images |
| --- | ---: | ---: | ---: | ---: |
| 9/11 report | 4565 → 4548 | 137 → 131 | 538 → 549 | 520, identical bytes |
| Loper Bright | 355 → 346 | 5 → 5 | 112 → 114 | none |
| Our Flag | 732 → 732 | 54 → 36 | 0 → 0 | 147, identical bytes |
| The Fed Explained | 1175 → 1173 | 158 → 158 | 119 → 121 | 262, identical bytes |
| Wallace algebra | 5952 → 5952 | 205 → 205 | 487 → 487 | 2047, identical bytes |
| FAA handbook | 8988 → 8988 | 173 → 173 | 430 → 430 | 599, identical bytes |

Navigation per level:

| Book | Baseline | This tree |
| --- | --- | --- |
| 9/11 | h2 1, h3 39, h4 1, h5 63, h6 33 | h2 1, h3 39, h4 1, h5 63, **h6 27** |
| Our Flag | h1 1, h2 24, h3 7, h4 4, h5 18 | h1 1, h2 24, h3 7, h4 4, **h5 0** |
| Loper, Fed, Wallace, FAA | unchanged | unchanged |

The six 9/11 headings that leave are the note-page running heads `554 NOTES TO CHAPTERS 9-10`,
`560 NOTES TO CHAPTERS 10-11`, `NOTES TO CHAPTER 11 561`, `562 NOTES TO CHAPTER 11`,
`566 NOTES TO CHAPTER 13` and `NOTES TO CHAPTER 13 567`. No heading is added, and the genuine
per-chapter notes titles (`10 Wartime`, `11 Foresight—and Hindsight`, `12 What to Do? A Global
Strategy`, `13 How to Do It? …`) stay, on their own pages. The eighteen Our Flag headings that
leave are the printed page numbers in the margin (`9`, `13`–`15`, `26`–`39`); each stays in the
text as a paragraph, the block count is unchanged, and no other heading changes level, so the
size tiers of the real headings are untouched. The Fed change is two running heads,
`The Three Key System Entities 7` and `… 9` on pages 15 and 17. Wallace and the FAA handbook are
identical block for block.

Eleven 9/11 pages newly report `furnitureRemoved`: 14, 16, 17, 18, 468, 572, 578, 579, 580, 584,
585. Loper pages 45 and 47 were the only two of 114 without the warning; now every page has it.

**Page text, reviewed by hand.** Removing a head lets #45's cross-page join run, which is the
only way body text moves. Five joins appear, each read against the source render as a
mid-sentence or mid-word continuation:

- 9/11 16→17 `…to take on this` / `all-consuming assignment.`
- 9/11 17→18 `…with humility.We have` / `made a limited number of them.`
- 9/11 467→468 `…at one of the Com` / `mission's 12 public hearings…`
- 9/11 571→572 `…one of the ESU offi` / `cers and one of the firefighters…`
- 9/11 577→578 `…perhaps delib` / `erately selecting a non–al Qaeda target…`
- Loper 46→47 `…(slip op., at 3). If that were true, Chevron` / `would mean that "agencies are
  unconstitutionally exercising…"`

No other page text changes in any of the six books. Where a join moves a page boundary inside a
paragraph, blocks after it are reported under the later page's anchor; the reflowed-page counts
and image ownership are unchanged and every image file still matches byte for byte.

## Corpus contracts

`corpus/regressions.json` gains 9/11 pages 14, 16, 17, 18, 467, 468, 571, 572, 577–580, 584, 585
and Loper 44–48, and `absentHeadings` on Our Flag 33, 34, 42 and 43. `tools/check_corpus_content.py`
gains that one key: a line the page still carries but which must not be in the navigation.

#45's two front-matter separation checks named the running head that followed each folio
(`{"end": "xiii", "next": "xiv COMMISSION STAFF"}`); the head between them is now furniture, so
they name the first paragraph that follows instead. What they protect is unchanged — the folio
must not absorb the next page's text — and both still pass.

Forbidden phrases for the Loper opinion rows span the folio row and the opinion row
(`v. RAIMONDO THOMAS, J., concurring`, `1 THOMAS, J., concurring`), because the concurrence's own
body cites `(THOMAS, J., concurring)` legitimately and must not be caught.

## Validation

- `swift test`: 305 tests pass in 3 suites (299 at `26d5209` plus 6).
- `python3 -m unittest discover -s tools -p 'test_*.py'`: 165 tests OK.
- `scripts/check-all.sh --fast`: exit 0 — 305 Swift, 165 Python, concurrency trials, 6 fixture
  conversions, 13 policy conversions (including `headers-keep`) and 22 rejection/cleanup cases.
- Corpus lane, all six English cases, EPUBCheck, progress and memory gates: **506 content checks
  on 113 pages pass**, 0 errors.
- Negative control: the same contracts against the `26d5209` CLI fail **41 checks** — 28 in 9/11,
  9 in Loper, 4 in Our Flag — and pass 0 new ones. FAA, Fed and Wallace pass on both builds.

```sh
swift build -c release
python3 tools/run_corpus_regressions.py --converter .build/release/pdf-reflow \
  --epubcheck /opt/homebrew/bin/epubcheck --output <dir> \
  --case gpo-911-2004 --case scotus-loper-bright-2024 --case faa-phak-8083-25c \
  --case gpo-our-flag-2003 --case fed-explained-2021 --case wallace-algebra-2010
```

The margin inventory behind the audit below is `tools/audit-report-margins.swift`, compiled with
`NativeTextReader.swift`, `ConversionTypes.swift`, `DocumentModel.swift`, `ReflowDocument.swift`,
`FurnitureDetector.swift`, `NativeSpacingReader.swift` and `GraphicsReader.swift`, run against
the pinned report. It records extraction and detector decisions only.

## Audit of the twelve remaining 9/11 margin pages (#10)

The [report-header qualification](../report-header-qualification/record.md) listed twelve pages
whose top-band row survived. All twelve reproduce on `26d5209`; eleven are fixed here.

| Page | Retained row | Folio offset | Now |
| --- | --- | ---: | --- |
| 14 | `xiv COMMISSION STAFF` | 0 (Roman) | removed |
| 16 | `xvi PREFACE` | 0 (Roman) | removed |
| 17 | `PREFACE xvii` | 0 (Roman) | removed |
| 18 | `xviii PREFACE` | 0 (Roman) | removed |
| 257 | `AL QAEDA AIMS AT THE AMERICAN HOMELAND` + `239` | — / −18 | **retained** |
| 468 | `450 NOTES` | −18 | removed |
| 572 | `554 NOTES TO CHAPTERS 9-10` | −18 | removed |
| 578 | `560 NOTES TO CHAPTERS 10-11` | −18 | removed |
| 579 | `NOTES TO CHAPTER 11 561` | −18 | removed |
| 580 | `562 NOTES TO CHAPTER 11` | −18 | removed |
| 584 | `566 NOTES TO CHAPTER 13` | −18 | removed |
| 585 | `NOTES TO CHAPTER 13 567` | −18 | removed |

Page 257 is the one remaining case. Its head row extracts as two lines at the same height
(0.9262): `AL QAEDA AIMS AT THE AMERICAN HOMELAND` at x 90.5–310.9 and `239` at x 342.7–356.7,
split at the wide gap between them. The page is a photograph insert inside chapter 7, whose
neighbours are headed `THE ATTACK LOOMS 239`; this page carries chapter 5's title instead. The
title carries no page number, so the folio evidence cannot reach it, and `239` is a lone folio
whose row mate is not removed, so it keeps its row. Both remain paragraphs, neither is a heading,
and no body text is affected.

A rule that removed a whole band row once any line on it carried an established folio would
reach this page. It is not adopted here: one page is not evidence that a title sharing a row with
a folio is always furniture, and a part-title or chapter-opening page can legitimately set a
title beside its page number. It is recorded as the remaining case instead.

A related correction to the record of #43: its heading table annotates the 9/11 `h6 36` tier as
"note-page running heads". Only six of those entries were running heads; the rest are the
appendix hearing titles and the per-chapter notes titles. The tier is `h6 27` here.

## Remaining

- **Short runs, generally.** The three-occurrence minimum is unchanged for head **text**. It is
  the folio offset, not the repetition count, that was lowered: three pages of agreeing offset,
  position and type size. A head that repeats twice and carries no page number — an alternating
  opinion row with no folio anywhere on its row, a two-page transition title — is still retained.
  The Loper concurrence is fixed because its folio row is removed first and #40's dependency then
  releases the row beneath it; a concurrence whose pages carried no folio would not be.
- **The heading floor is page-local.** `blocks()` reconstructs one page and does not know the
  document's folio offset, so any number at the edge of a separated line in the outer tenth reads
  as that page's number. A genuine title set that far into the head margin and clear of the body
  would be demoted to a paragraph. No heading in the six corpus books is lost to this, and a
  Swift control states the limit explicitly.
- Multi-line margins beyond #40's two rows, OCR header corruption, broader heading
  reconstruction and recall, and timeline row/column ownership remain unqualified. The
  `report-header-qualification` inventory still supplies no source-backed multi-line running-head
  case in this report.
- Full Warren and NOAA remain outside the default corpus lane for the recorded image-budget
  failures. No PDFKit leak or physical-device claim is made here.

## Defects observed, not fixed

1. **Conversion is not reproducible for tagged books.** Two runs of the *same* binary on The Fed
   Explained report 67 and 118 `structureFallback` warnings and differ in 157 block regions;
   Our Flag alternates between 688 and 732 blocks with 61 regions differing, including heading
   levels (`"I PLEDGE ALLEGIANCE` as `h3` or `h4`) and whether adjacent lines are joined. The
   9/11 report, Loper, Wallace and the FAA handbook are stable across runs. Observed on
   `26d5209` and on this tree alike, so it precedes this change; the comparisons above pair runs
   that agree on the `structureFallback` count and confirm each mode is self-consistent. Expected:
   one input, one output.
2. **9/11 physical page 257 keeps its running head.** Document: `gpo-911-2004`, physical page
   257 (printed folio 239), a photograph insert in chapter 7. Observed: the head row survives as
   two paragraphs, `AL QAEDA AIMS AT THE AMERICAN HOMELAND` and `239`. It is the only top-band
   row left in the book. The title is chapter 5's, not chapter 7's, so no neighbouring page
   repeats it, and it carries no page number of its own. Expected: the row is furniture, as it is
   on every neighbouring page. Needs evidence that a title beside a folio on one band row is
   furniture generally; see *Remaining*.
