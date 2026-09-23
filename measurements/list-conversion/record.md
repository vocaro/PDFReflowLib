# Real lists for verified bulleted and numbered runs, ported onto main (#292)

The list conversion #194 landed on the abandoned coordination branch (`8176df5`, `da23b64`,
`508fdfa`; [decision 0005](../../doc/decisions/0005-abandoned-coordination-branch.md)) never
reached `main` (#219). This is the port: a `.listItem` block in the document model, a
`ListBuilder` that decides which marker-opened blocks are the items of a real list, and `<ul>` /
`<ol>` output from the writer, under the rules the owner ruled on for #194 and #195 and carried
over to #292 as written.

Tier: deterministic Apple PDF stack, library defaults plus `--no-ocr`, macOS 27.0 arm64, release
CLI. Baseline: `8faeaab` (converter SHA-256 `89d1863d…`). Candidate: `8faeaab` plus this change,
the commit that carries this record (converter SHA-256 `8d64689f…`). Every cached corpus source
except the two the coordinator held back for another agent's gate
(`GPO-WARRENCOMMISSIONREPORT.pdf` and `noaa_61592_DS1.pdf`) was converted with both binaries,
one book at a time, with

```
pdf-reflow <source> <out>.epub --no-ocr --package-identifier urn:uuid:identity --modification-date 2026-01-01T00:00:00Z
python3 tools/epub_identity.py --baseline-epub … --candidate-epub … --baseline-report … --candidate-report …
```

and each pair was deleted before the next book. For a book that moves, every block of both
outputs was read page by page (kind, text, and each list's items), and EPUBCheck 5 was run on
both sides. No EPUB or capture is committed.

## The design on main

`main`'s reconstruction is 1,965 lines against the branch's 7,373, so this is a re-implementation
onto the current code rather than a cherry-pick; the marker grammar, the verified-numbering rule
and the shape of the tests are borrowed where they still fit.

- **Evidence, not re-derivation.** `BlockAssembler` already reads a bulleted line as an item
  (`LineRole.listItem`) and a numbered or lettered line on an edge the page sets a list on as one
  (`LineRole.markedLine` with `MarkerColumn.setsAList`, #171, #172). Each such block now records
  that a marker opened it (`ReflowBlock.listEvidence`) and whether the page transcribes a scan.
  Code, table rows and every line of a page the document heads as a chapter's notes record
  nothing. The builder consumes that reading; it never re-reads the page.
- **A stream, not a document pass** ([decision 0008](../../doc/decisions/0008-streamed-blocks-to-the-writer.md)).
  The branch ran `ListBuilder.build` over the whole block list after reconstruction. `main`
  streams blocks to the writer, so `ListBuilder` sits between reconstruction's `pending` tail and
  `send`, holds a block only while a run it may belong to can still change (a run chains within
  one page, so it is decided once every block of the page after its last member has arrived, plus
  one page more so that a marked line's numbered sibling two pages on is seen), and keeps what a
  decision reads from further back as counts and markers, so it holds a run for at most three
  pages past its end and nothing else.
- **Flat items** (#219 item 3). The branch nested by measured indentation and tags. Here a list
  item carries its text without the marker, the marker, the printed number, its kind and whether
  it opens a list element, and nothing else; the writer nests nothing. A candidate of another
  family between two items of a run leaves the run intact but ends its list element, so the 9/11
  brief's `1.`/`2.`/`3.` around their bullets become paragraphs keeping their numbers while the
  bullets list. Lettered sub-items are never candidates and stay preformatted, as today.
- **Tags are not consumed.** `StructureTreeReader` still parses and discards `L`, `LI`, `Lbl`
  and `LBody`. The branch's record found they moved almost nothing (Fed's lists identical with
  and without them, one Our Flag join, one Loper Bright split avoided), the spatial rule has to
  work without them, and the flat model has no depth for them to decide; the `+` bullet, which
  the branch reached through a tagged-group exception, is read from the text instead.
- **`+` is read from the text.** Reconstruction reads `+` as the operator it is in every other
  book (Wallace's `+ 21 + 21 Add 21 to both sides`), and the dietary guidelines' `+` items reach
  the builder as whole paragraphs. So a paragraph opening with `+`, a space and a word — or a
  percentage, `+ 100% fruit or vegetable juice` — whose rest reads as words is a candidate of the
  `+` family. Widening `isList` instead would have made those paragraphs marker-opened blocks
  and split every one that wraps (see below).
- **`−` is not a bullet.** The coordinator's glyph list came from `isList`, which reads `−`.
  Wallace's derivation rows open with it and 29 of them read as words (`− 7+6x Our Solution`),
  five pairs adjacently, so a `−` family would have listed worked examples; the branch excluded it
  for the same reason. Wallace page 2's three `−` licence sub-items stay preformatted.
- **`start`.** The writer supports it, so a verified run whose first printed number is not 1
  keeps it (`<ol start="22">`), as the branch did.
- **Page markers.** The survey found the standalone source-page marker emitted between blocks
  would stand illegally inside a list. The writer packs a list as one unit, like a table: items
  are gathered until a block that is not an item, a validated chapter start or the end of the
  document arrives, so no spine document ends inside a list and a list over the body target is
  its own document. A marker that arrives between two items is written inside the item it
  precedes as its first child; the marker of an empty page inside the item before it; a marker
  before the first item stands before the list as any marker does, and one after the last item
  travels with what follows. A chapter start closes the list in one document and the next item
  opens a fresh one in the next. One FAA list, two 9/11 lists and one Wallace list open items on
  two pages in the gated output; EPUBCheck reports 0 errors on every converted book (its warnings
  — `OPF-085` for the pinned `urn:uuid:identity` identifier, and `NAV-011` on the 9/11 report —
  are on the baseline too).

## Two rules main needed that the branch did not

Both came from reading what `main` produces, not from the branch's record.

- **A chapter's notes are not a list.** On the branch the 9/11 report's endnotes were the note
  apparatus (`NoteLinker`, branch only); on `main` they are one preformatted block per note and
  their numbers run 1 to 200 by one, so the first candidate build listed them as 168 `<ol>`
  elements. The owner's ruling on Warren — endnotes want the note-key apparatus, not a list — is
  read as the rule for every notes apparatus: a page the document heads `NOTES TO CHAPTER n`
  records no list evidence (`DocumentContext.numberedNotePages`, the set `NumberedNoteDetector`
  already reads). Two of the report's notes pages are headed for two chapters at once (`NOTES TO
  CHAPTERS 9-10`, pages 554 and 560 printed), which the detector now reads; the notes on those
  pages otherwise listed.
- **Exercise sets keep their numbers.** The owner excluded Wallace's exercises until their
  reading order is switched (#219 item 4), and the branch's rules held only because that reading
  was column-major: on `main` four practice sets read in order and listed (pages 61, 62, 69 and
  285 — 43 items). Two rules keep them out. A run whose numbering the list-shaped entry before or
  after it continues, that entry reading as no item, is part of that entry's apparatus (page 285's
  `4. 1.35 km to centimeters` after `1.`–`3.`, which are conversions of figures; the branch had
  this rule for transcriptions only, for the Warren notes page 897). And a numbered run under a
  heading that names an exercise set — a word *practice* or *exercise(s)* — stays as printed; the
  book's own heading is the evidence, as `NOTES TO CHAPTER` is for a notes page. Wallace's six
  worked procedures (pages 40, 59, 73, 206, 381 and 403), headed otherwise, list exactly as they
  did on the branch.

## Counts

Eleven of the twenty-two swept books move; eleven are byte-identical (the Earthdata slides, the
GWL paper, *Loper Bright*, the Replay Clocks paper, the Arabic USCIS guide, the magazine, the
tank-health report, the CDC comic, the court form, the USGS summary and the Warren excerpt).
Every book that moves differs only in its spine documents and, where a heading's anchor moved,
its navigation; every conversion report is identical. On every moving book the words of every
page are the same apart from the removed markers, and the sequence of words over the whole book
is identical apart from them.

| Book | `<ul>` (items) | `<ol>` (items, with `start`) | across a page | marker lines that became paragraphs | pages changed |
|---|---:|---:|---:|---:|---:|
| faa-phak-8083-25c | 37 (136) | 19 (54, 4) | 1 | 268 | 97 |
| gpo-911-2004 | 14 (35) | 0 | 2 | 129 | 52 |
| fed-explained-2021 | 14 (38) | 4 (12, 1) | 0 | 24 | 22 |
| dga-2025-2030 | 19 (57) | 0 | 0 | 0 | 8 |
| wallace-algebra-2010 | 3 (6) | 7 (22, 1) | 1 | 10 | 11 |
| irs-p596-zhs-2025 | 0 | 4 (9, 2) | 0 | 7 | 9 |
| census-rrs2002-01 | 0 | 2 (18, 0) | 0 | 1 | 2 |
| gpo-our-flag-2003 | 0 | 3 (6, 2) | 0 | 1 | 1 |
| cia-blue-book-14-1955 | 0 | 1 (6, 1) | 0 | 3 | 3 |
| ntrs-20190030725-dasc-2019 | 0 | 0 | 0 | 9 | 2 |
| nbs-jres-geltman-1977 | 0 | 0 | 0 | 1 | 1 |
| **total** | **87 (272)** | **40 (127)** | 4 | 453 | 208 |

127 list elements holding 399 items, against the 512 elements and 1,703 items the survey
expected on the branch's reading. The difference is `main`'s reading of a wrapped item, not the
rules: on `main` an item that wraps is its marker line as one preformatted block and the rest as
a paragraph beneath it (#266, and "no list model" in the behavior guide), so the paragraph stands
between the item and the next and ends the list element. The 453 marker lines that became
paragraphs are those pieces of one — an item set apart from its run by its own wrapped line, in
nearly every case — and the lone marked lines (#195): a paragraph that keeps its printed marker
reflows where the preformatted block did not. The FAA's page 47 shows the shape: of its five `•`
alternatives to a marginal flight, the four one-line ones list and `• Wait for the weather to
improve…`, which wraps, is a paragraph above its wrapped line; its numbered IMSAFE checklist
lists 1–2, which are whole, and items 3 to 6, each wrapping, are paragraphs `3. Stress—…`,
`4. Alcohol—…` with their wrapped lines beneath them. DGA moves from 59 `+` paragraphs and 8
`-` blocks to 57 items in 19 lists and 10 marked lines that stand alone as paragraphs — nine `+`
items their `-` sub-items or a heading set apart, and one `-` item its own wrapped line does.

What stayed preformatted, and why, on the gated books: the 9/11 report's contents (the contents
rule), timelines and notes (notes pages record no evidence); Wallace's exercises and answer keys
(the apparatus-continuation, heading and word-test rules; 2,272 numbered blocks are as they were)
and `−` rows; the FAA's METAR/TAF/PIREP reports (no marker) and lettered sub-items; the Blue
Book's recognized bullets (`- Per Cent`, 173 blocks) and lettered options; the IRS publication's
lettered sub-items and note asterisks; the Geltman paper's numbered section titles apart from
`3. Quantum Description`, which stands alone in the book's reflowed text (its siblings are
headings) and becomes a paragraph keeping its number, as the lone-line rule says.

## Contracts

`corpus/regressions.json` gains a `lists` check type — one list element's kind, `start` and
consecutive item phrases — in `tools/check_corpus_content.py`, with negative controls in
`tools/test_corpus_content.py`, and a reader that refuses a list element holding anything but
items. Pins, each read against the source page with `pdftotext -layout`: FAA 91 (the three
effects of thin air, `<ul>`; the two density-altitude steps stay preformatted) and 212 (the three
airspeed-indicator conditions, `<ol>` from 1); Wallace 2 (two `<ul>`s of licence terms, the
`Attribution` paragraph, the `−` sub-items and `Notice` preformatted); Fed 19 (`<ol start="2">`)
and 75 (`<ol>` 1–4 and item 5 a paragraph); DGA 3 (two `<ul>`s of `+` items); Census 3 (`<ol>`
1–16, whose `orderedText` phrases lose their printed numbers); 9/11 381 (the strategy's three
policies), Our Flag 26 (folding steps 1–2 and 6–7 as lists, step 5 a paragraph), Blue Book 270
(`<ol start="22">`, item 28 a paragraph) and IRS 17 (`<ol>` 1–3), the last four as new review
pages. The list and paragraph checks fail on the baseline output; the preformatted controls pass
on both.

## Gates

`scripts/check-all.sh --fast` passes, exit status read directly. The corpus lane passes 18 of
18 cases, each `runPassed` and content assessment read from its own `result.json` and
`content-assessment.json`, with EPUBCheck clean. All 704 Swift tests pass on this host, the five
Vision tests included.

## Not done here

- **Wrapped items.** The one change that would multiply these counts is joining an item's
  wrapped lines to the item in reconstruction, which #266 closed for the broken-word case only
  and the behavior guide records as "no list model". It is reconstruction's, corpus-wide, and not
  this port's; the counts above are what `main`'s reading gives.
- **Nesting**, lettered sub-items, NOAA's bibliography and Warren's endnotes wait on #219 in the
  order the owner set; the Wallace exercise-order switch is queued after this lands.
- **Tags** are parsed and discarded as before.
- The full Warren report and NOAA were not swept.
