# Hearing lists and the Table of Names (#161)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, Xcode 27, release CLIs, Python
3.14.6, EPUBCheck from `/opt/homebrew/bin/epubcheck`. Baseline `a6be9aa` (the coordination branch's
head, which carries #159's first-line indents, #162's hanging lists, #178's column-numbered keys and
#180's row pieces); candidate this tree on it.

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline | `a6be9aa` | `65189d8c380ec831b071df457ca177ae458784bcc574dea9072b75492d83f98f` |
| candidate | this tree on `a6be9aa` | `4202c92d91509e3ae0e0f9f969c5e0f0ed693b17d0632cacfb2aeb8d3e68b405` |
| probe | `tools/probe-raster-environment.swift` | `1b6ceaa595f3f673d23e46ddb02f2431f289da12b2c023c0c14075ef887650a5` |

No source PDF or EPUB is committed; each lane's EPUBs were deleted once its page diff was written. Seven
source fixtures were captured at `a6be9aa` with `tools/capture-layout-fixture.swift` (`911-450`,
`911-456`, `911-457`, `911-461`, `911-463`, `911-464`, `blue-303`); `911-451`, `911-458`, `911-460` and `911-462`
were already committed and were not recaptured.

## State on the baseline

None of the issue's four items had been closed by the changes since #134. On `a6be9aa`:

1. **Wide one-line entries still ran on** — page 463 `…Louis J. Freeh, …` / `…Janet Reno, …` and (not in
   the issue) `…Robert S. Mueller III, …` / `Maureen Baginski, …`; page 464 `Joseph F. Bruno, …` /
   `…Rudolph W. Giuliani, …` and `Adam B. Drucker, …` / `CIA Officials`.
2. **Page 457** — `The Experience of the Attack` and `Representatives of the Victims` were already
   headings (each is narrower than the witness beneath it, #76), but `The Attackers, Intelligence, and
   Counterterrorism Policy` was fused with its four witnesses, and every panel's witnesses (and the two
   governors' lines, and the venue and date) ran together.
3. **Page 461** — `Preventive Detention: … to Combat Terrorism` was its own paragraph, not a heading.
4. **Table of Names** — pages 450 and 456 read every name, then every description; pages 451–455 kept
   rows but split each wrapped name around its description's lines (`Mohammed Farrah`, `Somali warlord…`,
   `Aidid`, `Somalia in…`, eleven such names), so `al Bashir` and `Ghamdi` ran into the next name.

## Evidence

Geometry from the fixtures, read against 80-DPI Poppler renders of pages 456 and 457.

**Wide entries.** The hearing lists set 9-point entries at 11-point pitch, each wrapped line one em in
(8.8–9 points). #134 split two lines on the edge only when the upper ended early: the lower line's first
word would fit before the edge's widest line, or (two wrapped entries on the edge) the upper ends an em
short of it. Freeh (maxX 326.5) and Mueller (327.3) are page 463's two widest lines, Bruno (313.0) and
Drucker (313.7) page 464's. The lists do not break by fit at all: `Alan Reiss, …, Port Authority of` /
`New York and New Jersey` breaks where `New` would still fit. What the pages do show is that no entry of
that size ever continues flush on the edge: every continuation hangs, and every line on the edge opens
with a capital after a line that is not hyphenated. The only flush continuation on these pages is page
461's bold title (`…Des-` / `ignations to Combat Terrorism`).

**Page 457.** Seventeen plain 9-point lines on the 44.7 edge (venue, date, two governors, thirteen
witnesses), none wrapping; three 9-point bold panel titles on the same edge in the style #134's pages establish (the book's label style: bold 9-point at a 9-point
body, from 458, 460 and 462), each directly over a witness. The page's 10.5-point opening paragraph
shares the edge and is justified to 356.7; the 9-point lines have no justified measure (no three end
within a point of each other). The venue and date under `FIRST PUBLIC HEARING` are bold italic, and
read as separate lines on every later hearing page since #134.

**Page 461.** The title's first line runs to 356.3, the page's full measure, wider than any witness
(the widest, Barr, is 277 wide): `sectionLabels` refused any sub-heading wider than the column's widest
prose line before looking at its second line. The second line stands flush after a hyphen, not in the
indent.

**Table of Names.** Names stand at x 39.7 (verso) or 44.7 (recto) in 10.2-point type, their wraps 12
points in; descriptions start on the name's baseline 108 points in, wraps 12 points in. The widest name
on each page decides the gutter: `Prince Turki bin Faisal` leaves 17 points on page 456 and page 450's
widest name 35, over the 1.5-body gutter for which `whitespaceCut` asks no prose on either side; the
other pages leave less, fall through to the row sort, and interleave a wrapped name with its
description. Three rows PDFKit reads as one line across the gutter (`John Ashcroft Attorney General,
2001–` on 449, `Janet Reno …` on 451, `Khallad see Tawfiq bin Attash` on 454) stand on the names' edge.

## Rules

**`LayoutReconstructor.HangingEdge.hangsOnly`, `opensHangingEntry`.** An edge records whether any entry
of its size runs on flush beneath another on the edge (a line opening in lowercase, or after a
line-end hyphen or slash). Where none does and two or more entries wrap there (or the edge is titled,
below), a line back on the edge opens the next entry however far the line above it ran, unless that
line fills the page's justified measure for its size (`justifiedMeasures`, within 0.75 body). #134's
early-ending tests are unchanged and apply first.

**Titled edges (`hangingEntryEdges(_:body:titles:)`).** Given the book's label styles, an edge with no
wrapped entry qualifies when at least two lines wholly bold in one of those styles stand on it, each
directly over a non-bold line on the edge in its size at ordinary leading; no line of that size opens
on an indent under a sentence's end there (#134's disqualifier); the size has no justified measure on
the page; and no entry runs on flush. `sectionLabels` passes its `styles`, `blocks` its `labelStyles`;
`labelEvidence` passes none, so the book's label evidence is unchanged.

**Wide titles (`sectionLabels`).** A bold sub-heading in the book's style on a hanging-entry edge may be
wider than the column's prose; only the two-line path admits it (the single-line path still asks for
nine tenths of the prose width), with every other test of that path unchanged.

**`LayoutReconstructor.namedEntries`**, tried in `ordered` before any whitespace cut. In the region's
most common size (lines within 5% of it): every line stands on the leftmost edge (names), on the
descriptions' edge, or 0.5–2.5 of that size inside either; at least four names, and two thirds of
them, share a baseline with a line starting past their end, all those lines starting on one edge; the
widest such name is at most three fifths of the widest description line; and every name line holds at
least two letters (added after the CIA lane, below). The region then reads each name, its wrapped lines and its description's lines; lines in other sizes (`U.S. OFFICIALS`, a
folio) keep their place; description lines above the first name (continued from the previous page)
read first. A name line PDFKit read across the gutter is a name with no partner.

## Contracts (`corpus/regressions.json`, gpo-911-2004)

42 new checks on eight pages; page 450's and 451's existing entries were extended, no page has two
entries.

- Page 450: ordered `Roger Cressey`, `NSC counterterrorism official`, `Ralph Eberhart`, `Commander in
  Chief, NORAD`; distinct Cressey/Eberhart and Freeh/Fry.
- Page 451: paragraphs `Mohammed Farrah Aidid` and its whole description.
- Page 454: paragraphs `Khalid Sheikh Mohammed`, `Mullah Mohammed Omar`.
- Page 456: nine ordered phrases from the continued `during the 1990s` through `see Zein al Abideen
  Mohamed Hussein`; paragraphs `Khalid Saeed Ahmad al Zahrani`, `Mohammed Haydar Zammar`; distinct
  Prince Turki/Ramzi Yousef and the last description/`see Zein …`.
- Page 457: headings `The Experience of the Attack` (control) and `The Attackers, Intelligence, and
  Counterterrorism Policy`; four witness and opening-paragraph paragraphs (the opening paragraph's two
  line joins are controls); distinct Pataki/Bloomberg, David Lim/Lee Ielpi and (control, across a
  title) Allison Vadhan/Daniel Byman.
- Page 461: headings `Preventive Detention: … to Combat Terrorism` and (control) `Protecting Privacy,
  Preventing Terrorism`; paragraph `Jan Ting, Temple University`.
- Page 463: distinct Freeh/Reno, Mueller/Baginski and (control) Pickard/Black.
- Page 464: distinct Bruno/Giuliani, Drucker/`CIA Officials` and (control) Reiss/Morris; paragraph
  `Alan Reiss, …, Port Authority of New York and New Jersey` (a wrapped entry stays whole).

The baseline fails 21 of the 42 (the rest are controls or phrases the baseline already holds whole);
the candidate passes all 348 checks of the case.

## Tests (`Tests/PDFReflowLibTests/HearingListsAndNamesTests.swift`)

| Test | Reproducer / control |
| --- | --- |
| `source911OneLineEntriesAsWideAsTheirPageStandApart` | `911-463`, `911-464`: the four wide pairs are separate paragraphs; wrapped entries (Berger, Black, Reiss, the NTSB venue) stay whole. |
| `source911PanelsWithoutAWrappedEntryAreTitledByTheBooksStyle` | `911-457` with the appendix style: three titles, one paragraph per witness, the justified opening paragraph whole; without the style, no title and the witnesses fused, as before. |
| `source911TitleWrappedFromAFullMeasureLineHeadsItsEntries` | `911-461`: the title is a heading, no paragraph holds it, the next panel's control title stays a heading. |
| `entriesAsWideAsTheEdgeSplitOnlyWhereEntriesOnlyHang` | Synthetic: a widest one-line entry splits beside two wrapped entries; one wrapped entry, a lowercase flush continuation and justified prose keep lines together. |
| `titledEdgesNeedTwoTitlesInTheBooksStyleAndNoMeasure` | Synthetic: two styled titles make a titled edge and split its entries; one title, no style, a justified measure or a lowercase run-on make none. |
| `source911TableOfNamesReadsEachNameBesideItsDescription` | `911-456`, `911-450`, `911-451`: name, then description, the continued line first, a wrapped name whole. |
| `namedEntriesNeedNamesNarrowerThanTheirDescriptions` | Synthetic rows read by entry; two prose columns, a stray line, the Blue Book's code tables (`blue-303`) and the hearing pages `911-458`/`911-463` are refused. |

Negative controls (`tools/mutate.py`, `negative-mutations.txt`), over this suite and the hanging-entry,
box-title, font-weight, FAA heading, list-continuation and fallback-block suites: each of the twelve
mutations fails at least one test (see the file).

## Corpus lanes

`run_corpus_regressions.py` one case per call for each side, `compare_conversion_runs.py
--allow-different-converters --detail`, and a block-per-line page diff of changed pages
(`pagediff-gpo-911-2004.txt`, `pagediff-usda-ars-agresearch-2012-11.txt`).

Candidate lanes ran first with an earlier build (`d3d20dab…`); CIA page 303 then changed (below), a
guard was added, and the final candidate (`4202c92d91509e3ae0e0f9f969c5e0f0ed693b17d0632cacfb2aeb8d3e68b405`)
reran every case the earlier build had changed (9/11, CIA, USDA). The guard only refuses more regions,
so the cases the earlier build left unchanged stay unchanged. 59–63 GB free throughout.

| Case | Baseline | Candidate | Changed pages |
| --- | --- | --- | --- |
| gpo-911-2004 | fails 21 of the 42 new checks | pass (348 checks) | content: 450–457, 461, 463, 464; `headingRanks` only: 458–460, 462, 465 and 14 notes pages |
| usda-ars-agresearch-2012-11 | fails the 3 new checks | pass (245 checks) | 22, 23 (the 2012 index) |
| cia-blue-book-14-1955 | pass | pass | none (the earlier build changed 303) |
| scotus-loper-bright-2024, fed-explained-2021, faa-phak-8083-25c, arxiv-replay-clocks-2023, ntrs-20200002975-gwl-2020, wallace-algebra-2010, dga-2025-2030, gpo-our-flag-2003, cdc-zombie-pandemic-2011, usgs-mcs2025-copper, census-rrs2002-01, nbs-jres-geltman-1977, uscourts-pro-se-1-2016, ntrs-20190030725-dasc-2019, ntrs-20180003024-earthdata-slides-2018, ntrs-20210020887-techport-thm-2021 | pass | pass | none |

No image, report field or warning changed in any case.

**USDA pages 22–23.** The magazine's index sets one-line entries flush and wraps entries and
sub-entries into an indent; ten pairs of adjacent one-line entries read as one paragraph
(`American beautyberry, …, Nov/Dec-4 Ammonia, …`) and now stand apart, read against a 70-DPI render of
page 23. Its contract adds three distinct-paragraph checks to pages 22 and 23's existing entries.
Sub-entries still join their entry (`Irrigation … Sep-22 deficit, in peaches, …`), as before.

**CIA page 303 (earlier build).** Two scanned code tables set single-character codes (`0`, `X`) beside
their meanings, one column of words (`Days`, `Hours`) at the codes' edge: the region passed as names
and read `X`, `X`, `y`, `y`, … one code to a paragraph. A name must now hold at least two letters; the
page is identical to the baseline, and `blue-303` (captured at `a6be9aa`) is the source control.

Every 9/11 hunk was read: pages 450–456 against the fixtures' geometry (and page 456 against its
render), 457 against its render, 461, 463 and 464 against their geometry. Each split falls at a source
entry, each join joins one name or one description, and no title was lost. Pages 458–460, 462, 465 and
the notes pages that the comparison lists changed only `headingRanks`, the book-wide heading ordinals the
two new headings shift. No body paragraph, image, report field or warning changed; navigation gains
the two new titles (457, 461).

## Remaining defects

1. **Rows PDFKit reads across the Table of Names' gutter** stay one line and run into the next name:
   page 449 `John Ashcroft Attorney General, 2001– Monte Belger`, page 451 `Janet Reno Attorney General,
   1993–2001 Condoleezza Rice`. (Page 454's `Khallad see Tawfiq bin Attash` now stands apart, since its
   names' edge has two wrapped names.) The cut belongs in extraction, beside #65's column-joint split.
2. **A description's lost line-end hyphen** now joins with a space: page 453 `al Qaeda asso ciate`
   (before, two paragraphs). The column is ragged, so #157's justified-measure test cannot see it.
3. **`J. Cofer Black`** on page 449 is still read as a list line (`<pre>`), as on the baseline.
