# Real lists for bulleted and verified numbered items (#194)

Step 2 of [#29](https://github.com/vocaro/PDFReflowLib/issues/29), following the owner's decision
on [the survey](../semantic-lists/record.md): bulleted items become `<ul>`, numbered items become
`<ol>` where their printed numbers verify, and every other list-shaped block stays preformatted
(the remaining classes are #195).

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, release CLI. Baseline:
`bafb0ea` (converter SHA-256 `d18871c1…`). Candidate: `bafb0ea` plus this change. Both were run
through `tools/run_corpus_regressions.py` one case at a time with one environment probe, and each
pair compared with `tools/compare_conversion_runs.py --allow-different-converters`. No source PDF or
EPUB is committed. Page reviews read `pdftoppm` renders of the source against the emitted markup.

## The model

`ReflowBlock.Content` gains `.listItem(ListItem)`: the item's text without its printed marker, the
marker (kept for provenance), the printed number of a numbered item, its kind (`unordered` or
`ordered`), its depth and whether it opens a list element. Items stay a flat sequence, as the survey
proposed, because the writer streams blocks. `.preformatted` now means monospaced code, a coded
report, or a list-shaped line the list pass did not verify.

One departure from the survey's sketch: reconstruction still builds every list-shaped line as a
preformatted block, now carrying `ReflowBlock.listEvidence` (its marker line's left edge, type size,
tagged list item and whether the text transcribes a scan), and a document-wide pass,
`ListBuilder.build`, decides after `NoteLinker` which of them are list items. The decision needs the
whole document (a run crosses pages; an answer key is recognised by the entries around it), and the
dozen page and column joins that grow an item already preserve its preformatted representation, so
none of them had to learn a second case. A rejected run is byte for byte what it was.

## What becomes a list

- **Bulleted**: `•`, `-`, `+` or `*` (not `−`, which opens derivation rows; not `* * *`), in a run of
  at least two with one glyph.
- **Numbered**: one to three digits with `.` or `)` (a year is no item number), in a run of at
  least two whose printed numbers ascend by exactly one. A `1` opens a new run. A gap or a step back
  leaves the whole run preformatted; the list never renumbers.
- Every candidate's text past the marker must read as words, and no candidate may be a contents
  entry or a transcription of a scan (OCR, or an inherited invisible text layer).
- A numbered run also stays preformatted when its items each stand alone between other blocks
  (numbered titles, FAA page 320's forecast sections), when most items end on a folio or carry
  section numbers (a contents list), give quantities and ask for one (an exercise set), open on an
  author or cite `Author, 2021:`, a DOI or an address (a reference list), or when its pages hold more
  numbered entries that read as no item than it has items (an answer key).

A run chains each candidate to the latest candidate of its family on the same page or the previous
one; candidates of other families between are nested items. Accepted items with only page
boundaries and other items between them form one list element; a marker set deeper (0.8–5 ems) on
the same page nests, as does one on the next page left of which the parent list's next item stands
(the 9/11 brief's bullets under `1.`, pages 146–147), and a marker returns to the open level on its
edge or, where edges say nothing (another column), to the level with its glyph. A lone bullet set
deeper between two items of a list is nested in it. Where the PDF tags its lists, the tags decide
depth and list identity, except that a producer's list element closed at a page break continues on
the next page (Loper Bright pages 86–87 tag one five-item list as two `L`s).

## Counts

All 20 gated English cases. The survey's classes are from its classifier run on the `bafb0ea`
baseline output (the corpus has moved since the survey's commit, so its totals differ slightly from
the survey table); each baseline `<pre>` block was located in the candidate output.

| Book | `<ul>` (items) | `<ol>` (items, with `start`) | nested | across a page | one item | survey bulleted → `<li>` | survey numbered → `<li>` |
|---|---:|---:|---:|---:|---:|---:|---:|
| faa-phak-8083-25c | 182 (816) | 69 (212, 16) | 6 | 14 | 24 | 813 / 813 | 212 / 216 |
| gpo-911-2004 | 54 (180) | 3 (17, 0) | 4 | 16 | 8 | 179 / 179 | 13 / 17 |
| noaa-nca5-2023 | 45 (168); 43 (172) on `798b3c3` | 0 | 1 | 2 | 10 | 168 / 168 | 0 / 2 |
| fed-explained-2021 | 23 (79) | 8 (22, 2) | 0 | 2 | 4 | 78 / 78 | 22 / 24 |
| dga-2025-2030 | 26 (86) | 0 | 5 | 0 | 4 | 18 / 18 | — |
| census-rrs2002-01 | 0 | 1 (16, 0) | 0 | 0 | 0 | — | 16 / 16 |
| ntrs-20180003024-earthdata-slides-2018 | 0 | 3 (14, 0) | 0 | 0 | 0 | — | 14 / 14 |
| ntrs-20190030725-dasc-2019 | 7 (9) | 1 (4, 0) | 0 | 0 | 5 | 9 / 9 | 4 / 4 |
| wallace-algebra-2010 | 6 (9) | 6 (24, 0) | 0 | 1 | 4 | 9 / 11 | — |
| gpo-our-flag-2003 | 0 | 1 (7, 0) | 0 | 0 | 0 | — | 7 / 7 |
| ntrs-20200002975-gwl-2020 | 1 (5) | 0 | 0 | 0 | 0 | 5 / 5 | — |
| scotus-loper-bright-2024 | 1 (5) | 0 | 0 | 1 | 0 | 5 / 5 | — |
| cia-blue-book-14-1955 | 0 | 0 | 0 | 0 | 0 | 0 / 15 | 0 / 1 |

The seven other gated English cases emit no list: their `<pre>` blocks, where they have any, are
contents entries, section titles, form labels or single marked lines, all unchanged.

Survey-classed items that stay preformatted, and why:

- **FAA page 320** (4 numbered): each item heads its own example and explanation, so no two items
  touch; the run is numbered sections, not a list.
- **9/11 pages 5 and 7** (4 numbered): contents entries the survey's classifier missed
  (`11. FORESIGHT—AND HINDSIGHT`); the whole contents run ends on folios and section numbers.
- **Fed page 44** (2 numbered): `2019.` and `2020.` are years opening paragraphs, not item numbers.
- **Wallace** (2 bulleted): `• Notice:` on page 2 follows `−` sub-items, which are not bullets, and
  `• 4 terms: grouping` on page 234 has no sibling.
- **NOAA** (2 numbered): `1) cliffs, 2) low-lying beaches…` and `3) flooding…` are enumerations
  inside prose, and their run steps by two.
- **CIA** (15 bulleted, 1 numbered): an inherited text layer over a scan. The "bullets" are OCR of
  table headers (`- PerCenl`, `- Per Cent N- Per Cent`); the survey's class caught them by shape.

Beyond the survey's classes, the pass also makes lists of what the classifier filed elsewhere but
the source sets as lists: six Wallace procedures (`1. Distribute through any parentheses.` on page
40, and pages 59, 73, 206–207, 381, 403), which the classifier called exercises only because it
filed every Wallace number that way; the FAA's `• Class` and `• Type` on page 30 and `• Temporary
flight restrictions` on page 28, survey singletons that are items with nested numbered lists; and
the 9/11 brief's items on pages 146–147 and its lone bullet under item 2. Wallace's exercise sets
(`1. When five is added to three more than a certain number…`) and answer keys stay preformatted:
the exercise rule rejects ten runs, the answer-key rule eight, the sequence rule eleven, the
contents rule two and the lone-items rule one. No run of NOAA's chapter references converts: the
reference rule and the sequence rule (wrapped entries whose false markers break the numbering)
leave all of them preformatted, as #195 requires.

## Page markers

A list may contain only items, so a source-page marker before an item is written as the item's first
child, and a marker for an empty page between two items ends the open item. 46 markers open an item
in the gated output (FAA 21, 9/11 18, Fed 3, NOAA 3, Wallace 1); none ends one. 36 list elements
hold items that open on two pages. The writer packs a list as one unit, like a table, so no list
crosses a spine document (the survey counted two that would have). Every source-page anchor is
present and ordered in every book (`pageMarkersEqual` in every comparison), and EPUBCheck passes on
all 20 cases. `tools/check_corpus_content.py` now refuses a list element that holds anything but
items, and reads a marker that opens an item as starting that item's page.

## Tagged lists

`StructureTreeReader` now reads `L`, `LI`, `Lbl` and `LBody`. They still form no paragraph group
(content under them is reconstructed spatially, and the structure-fallback warning is unchanged),
but each marked-content item under an `LI` records its list, item, `L` depth and whether it is the
label; the associations are validated against the parent tree like group tags, and
`MarkedTextReader` gives a line the item every one of its tagged shows names. An `LI` set directly in
another element (Our Flag's `Sect` > `LI`) is an item of the list that element holds.

Consumers: a line of the open item's `LI` continues that item wherever it stands, and a line of
another item never does; the list pass takes depth and list identity from the tags. On the gated
books the tags reach Fed (101 of 106 list candidates carry one), Loper Bright (5 of 5), the NASA GWL
paper (5 of 5), Our Flag and NOAA. Against the same conversion with list tags ignored, Fed's lists
are identical; Our Flag page 26's `Hold bottom to top and edges together securely.` joins item 2
(it was a paragraph that split the seven folding steps into two lists); and Loper Bright's five
bullets, tagged as one `L` per page, would have split in two at the page break without the
continuation allowance above. The `Lbl` flag is recorded on every tagged line but not yet used: the
printed marker is removed by its pattern.

## The `+` bullet

`isList` accepts `+` when a word (or a percentage, `+ 100% fruit or vegetable juice`) follows and
the rest reads as words, so a derivation row such as Wallace page 40's `+ 21 + 21 Add 21 to both
sides` keeps its reading. Converting the 19 gated English cases other than NOAA with and without
the `+` rule changed one book, the dietary guidelines, on eight pages (NOAA, not in that pair of
runs, has no block that opens with `+` in its baseline). Its 68 `+` items, all paragraphs before,
are list items, and its 18 `-` items are nested beneath them instead of standing as preformatted
blocks between paragraphs (DGA pages 4, 6, 7 and 8). The guidelines tag each `+` item as a
paragraph; such a group, whose only list line opens it, keeps its tag as one item, as a split
marker's group does (#81), so its column-crossing text stays whole (`+ Lactation increases…`,
page 9) and page 7's `Some infants require iron supplementation.` keeps its second sentence. Word
text is identical on every page.

## A bulleted item's wrapped line after a sentence

A bulleted item's first wrapped line used to be refused when the marker line ended a sentence (the
rule that keeps Loper Bright page 64's lettered citation from swallowing the indented paragraph
beneath it). A bullet now continues when the page's other items with that bullet on that edge wrap
to the same indent. Converting the same 19 cases with and without this rule changed five items: FAA
pages 47 (`Instruments?` / `Lights?…`), 68 and 211 (`Most flying occurs within this range.`) and
9/11 pages 409 and 432, each a sentence that had been a paragraph beside its own item; all five were
checked on renders. Numbered and lettered markers keep the old rule.

## Comparison against the baseline

| Case | changed pages | image, report or navigation changes |
|---|---:|---|
| faa-phak-8083-25c | 167 | none |
| gpo-911-2004 | 62 | none |
| noaa-nca5-2023 | 32 (34 on `798b3c3`) | none |
| fed-explained-2021 | 29 | none |
| wallace-algebra-2010 | 9 | none |
| dga-2025-2030 | 8 | none |
| ntrs-20180003024-earthdata-slides-2018, ntrs-20190030725-dasc-2019 | 3 each | none |
| scotus-loper-bright-2024 | 2 | none |
| census, Our Flag, GWL | 1 each | none |
| the other seven cases | 0 | none |

Every changed page is a page holding a list or the page before one (a list that opens there and
whose first item's marker is the next page's), and the words on every page are unchanged apart from
the removed markers (a word-level diff of each page's text, markers ignored, is empty in every
book).

## Checks

The checker's `listItems` and `continuedListItems` now read `<li>` identities. Two check types are
new: `preformattedBlocks` (a phrase one `<pre>` must hold, for list-shaped lines that must not become
items) and `lists` (a list element's kind, `start`, depth and consecutive items). Reviewed changes to
`corpus/regressions.json`:

- Phrases that opened with the printed marker lose it (DGA, Loper Bright, GWL, 9/11, FAA, Wallace,
  census, Earthdata, DASC): `listItems`, `orderedText`, `text`.
- DGA's `+` paragraphs checked as `paragraphs` are `listItems`, and its two `distinctParagraphs`
  pairs, now two consecutive items, are `lists` checks, which prove the same separation.
- List-shaped lines that stay preformatted move from `listItems` to `preformattedBlocks`: FAA's
  METAR and PIREP reports (pages 316–318), Wallace's `−` license sub-items, `• Notice`, exercise
  coordinates and derivation rows (pages 2, 9, 101, 120), Earthdata's lettered sub-items and the
  court form's lettered fields. New `preformattedBlocks` pin a 9/11 contents entry (page 6) and a
  Wallace exercise (page 10).
- New `lists` checks pin the markup on DGA pages 3–8, Loper Bright 87, GWL 13, 9/11 147, 205, 365
  and 374, FAA 27, 28, 30, 191, 251, 317 and 319, Fed 9, 22 and 58, Wallace 40, census 3, Earthdata
  7–9 and DASC 7.
- FAA page 319's `preformattedLines` (the TAF) is unchanged and passes: the report is one `<pre>`.

## Not done here

- Lettered sub-items, reference and note apparatus, exercises and answer keys, questionnaires and
  OCR debris stay preformatted (#195).
- FAA page 30's `- Airship—…`, `- Balloon—…`, `- Gyroplane—…` and `- Helicopter—…` sub-items are
  paragraphs in the baseline and remain paragraphs, outside the lists they belong to.
- A numbered item whose first line ends a sentence still loses its wrapped lines to a paragraph
  (FAA page 47's IMSAFE items 4 and 5), which splits the `<ol>` into pieces that keep their printed
  numbers through `start`. The bulleted rule above is not extended to numbers because it would
  regroup exercise and reference entries, which are #195's.
- A lone numbered item (CDC's `1) Get a Kit`) stays preformatted; a one-item `<ol>` is not evidence.
- Warren is outside the gated lane (#5) and was not converted.

## Re-verification on `798b3c3`

The change was merged onto `fbe3464` and then `798b3c3` (#149, #150, #161, #177, #181, #186,
#187, #188, #189, #193 and the removal of the two non-English cases). Contracts were merged three
ways by case, page and key. Two edits overlapped: census page 3's ordered text (its printed markers
are dropped and #189's spelled-out `fl` kept; the list checks' own `ﬂag` ligatures are spelled
out too, which #189's contract test requires), and Wallace page 120's derivation row, now `− 18 <
− 12` after #177, which stays a `preformattedBlocks` check. Against a `798b3c3` baseline, all 20
cases pass one per call with EPUBCheck; every comparison shows no image, report or navigation
change and complete page markers, and the per-page word diff (markers ignored) is empty. The list
counts are those above for every book but NOAA, which on `798b3c3` has 43 bulleted lists of 172
items. Wallace's rows split after an exponent (`<pre>− 8x− 20</pre>`, #177) open with a minus sign
and stay preformatted.
