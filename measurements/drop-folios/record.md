# Drop folios on opening pages

A **drop folio** is the page number a book prints at the foot of an opening page, where the
running head that carries it on every other page is suppressed. The 9/11 report sets one on every
chapter- and appendix-opening page, and each reached the reader as a paragraph holding nothing but
a number ([#271](https://github.com/vocaro/PDFReflowLib/issues/271)). `FurnitureDetector` now
removes such a line where the book's own numbering says it is that page's folio. This record is
the survey behind that rule, and the control that says what else moves.

## What the page states, and what it does not

The issue reads the drop folio as standing in "the bottom 7% band the footer rule already looks
in", and as failing only the margin slot's "at least six pages **and** at least a quarter of the
document's pages". Measured, neither holds:

- The folio on physical page 447 is at `x=342.7, y=45.5, h=8.61` on a 612-point page, so its
  midpoint stands at **0.0814** of the page height. The footer candidate band is
  `position(midY) <= 0.07`. The line was never a candidate at all, so no threshold inside
  `resolve` could have reached it.
- A slot is built only from lines the plan already removes. The 9/11 report removes nothing at its
  foot edge, so it has no bottom slot to relax — lowering the quarter would not have found one.
- `PDFPage.label` says nothing here. PDFKit returns `447` for physical page 447 and `448` for 448:
  the report declares no usable `/PageLabels`, so `printedLabel` is nil on all 585 pages
  (`PageReader` drops a label equal to the physical index) and the page's printed label cannot be
  compared with the number at its foot.

What the document does state is its **offset**. The running head reads `430 APPENDIX` at the top
of physical page 448 — printed 430, physical 448, offset -18 — and 546 of the report's 585 pages
carry a removed margin line stating that same offset. The bare `429` at the foot of page 447
states it too. That is the evidence the rule uses: a bare number, alone on its line, standing
further out at the foot than any other line, set apart from the body by its own separation, inside
the outer tenth, goes where its value is exactly the folio an established offset predicts for its
page. An offset counts as established on at least six pages and at least a quarter of the
document's — the floor a margin slot asks of a place.

The outer tenth mirrors the header band. The narrow 7% footer band is untouched: nothing is
removed on position alone by this path, so no whitespace cut around an illustrated row moves.

## Scope and method

Native extraction only, over every source in `corpus/cache`: each page's lines are read with
`NativeTextReader`, `FurnitureDetector.collect`/`resolve` run over the whole document, and the
**line indices** each build removes are diffed (comparing by text alone hides a folio on a page
that prints the same digits elsewhere). No conversion, reconstruction or OCR is involved. The base
revision is `f939bec`. The probe is a throwaway diagnostic, not committed tooling; the
reproduction is below, and the per-book counts are in [margin-survey.json](margin-survey.json).

## What moves

Across the 24 sources, **2,230** bare folios stand in the outer tenth at the foot. **39** are newly
removed, in two books; **none** that the old detector removed is retained by the new one, in any
book.

| source | pages | bare foot folios in the outer tenth | offset the book states | newly removed |
| --- | --- | --- | --- | --- |
| GPO 9/11 report | 585 | 17 | -18 on 546 pages | **15** |
| Warren Commission report | 920 | 840 | -28 on 743 pages | **24** |
| Wallace, *Algebra* | 489 | 489 | 0 on 487 pages | 0 |
| FAA PHAK | 522 | 437 | none reaches the 131-page floor | 0 |
| CIA Blue Book 14 | 312 | 230 | none; the book loses no margin line | 0 |
| USCIS M-618 (Arabic) | 116 | 107 | -6 on 99 pages | 0 |
| Our Flag (CDOC-108hdoc97) | 56 | 48 | none; the book loses no margin line | 0 |
| NASA TM 20200002975 | 20 | 20 | none; the paper loses no margin line | 0 |
| every other source | — | 42 | — | 0 |

- **The 9/11 report loses 15 lines**, on physical pages 65, 89, 126, 163, 192, 233, 272, 296, 343,
  357, 379, 417, 447, 449 and 457. Ten of them are the ten the issue tabulates; the other five are
  opening pages of the same kind that its spine scan did not list. Each removal is the whole of
  the line and the whole of the change on its page: nothing is added, joined or reordered.
- **The Warren report loses 24 lines** — physical pages 31, 34, 195, 262, 264, 266, 271, 274, 280,
  286, 290, 450, 819, 833, 847, 849, 895, 899, 905, 909, 911, 913, 915 and 916. This book already
  loses a folio on most of its pages; these are the same folio where the neighbors' folios were
  read differently enough to break the run, so no three-page run covered them. The full Warren
  conversion is excluded from the corpus lane for the image-output ceiling, so this count is from
  the native survey; the pinned five-page suspect-text excerpt is unchanged.

## Negative controls on real pages

- **Our Flag** prints a bare folio at the foot of 48 of its 56 pages, at 0.0809 — within a point of
  where the 9/11 report drops its own — and its section titles at the head are not furniture, so
  the book loses no margin line at all. Nothing it loses states an offset, nothing is admitted on
  one, and all 48 stay. This is the book the narrow footer band exists for: widening that band
  instead would have removed them and disturbed the alphabetical row order of the illustrated
  entries on pages 34, 42 and 43.
- **The CIA Blue Book** (230 in the band) and **NASA TM 20200002975** (20) likewise lose no margin
  line, so none of the 250 numbers they print at the foot is reached. The NASA paper is
  [#154](https://github.com/vocaro/PDFReflowLib/issues/154) item 2 and stays open: its twenty
  pages state no offset anywhere, so this rule has nothing to stand on.
- **The FAA handbook** does lose 508 margin lines, including its `1-15`-style chapter-page folios,
  but its chapter half restarts the page half in every chapter, so no single physical-page offset
  reaches the 131-page floor and nothing is admitted on one.
- **Wallace's *Algebra*** states offset 0 on 487 pages and still loses nothing new: 487 of its 489
  band folios are already runs, and the two that are not — physical pages 175 and 437 — are the
  only line their page prints, so they have no inward gap to be set apart from (and `apply` would
  refuse to empty the page in any case). The eight **M-618** folios outside its 99 removals are
  the same shape.
- **The 9/11 report's own pages 19 and 467** keep their numbers. Page 19 sets `1` 6.5 points under
  its last body line and page 467 sets `449` 3.5 points under its own, against a required
  separation of 8.61 points. Both stand at 0.0814, in the outer tenth, with the offset the book
  states; only the page's own spacing keeps them, which is the conservative answer where the page
  does not set the number apart.

## Synthetic controls

`Tests/PDFReflowLibTests/FurnitureTests.swift` pins the keep side on a twelve-page book whose head
states offset -10 and whose every third page drops a folio to the foot. The folio goes; a number
one off it, a number equal to the physical page, a constant `42` and the same folio set 16 points
higher all stay, and a book with no head anywhere keeps all twelve.

## What the reader got, and what #45 has to do with it

In the baseline EPUB, `EPUB/chapter-22.xhtml` sets appendix A's abbreviation list and then, before
the page-448 anchor, `<p>429</p>` on its own:

```
<pre>NMCC National Military Command Center</pre>
<p>429</p>
<span epub:type="pagebreak" role="doc-pagebreak" id="page-448" aria-label="448"/>
<pre>NORAD North American Aerospace Defense Command</pre>
```

After the change that paragraph is gone, the list runs on, and the page anchor is where it was.
This is **not** a face of [#45](https://github.com/vocaro/PDFReflowLib/issues/45), whose folio
defect is a cross-page paragraph *join* anchored on a folio: here nothing is joined to the number
or to anything else, before or after, and `appendPage` is untouched. The two do meet in one place:
a folio this rule removes is one fewer folio for a cross-page join to anchor on. The join rule
itself remains what [#231](https://github.com/vocaro/PDFReflowLib/issues/231) holds.

## Corpus lane

`tools/run_corpus_regressions.py --jobs 4` over all 18 pinned cases passes on this change and on a
release binary built from `f939bec`, with `runPassed` true and an empty `errors` list in every
`content-assessment.json` on both sides. Reading both runs' EPUB page text back with
`tools/check_corpus_content.read_pages`, exactly one book differs: `gpo-911-2004`, on 15 pages,
each losing one block whose whole text is the folio. The other 17 books' page text is identical,
page for page.

## Reproduction

Compile `FurnitureDetector.swift` with the extraction sources
(`python3 tools/pdfreflow_tools/swift_sources.py audit-report-margins.swift` lists them) against a
throwaway `main` that reads each page with `NativeTextReader`, runs `FurnitureDetector.collect`
and `resolve` over the document, and prints every page's outer-band lines with their index,
position, type size and whether the plan removes them; build the same probe once against
`git show f939bec:Sources/PDFReflowLib/FurnitureDetector.swift` and diff the two outputs over
`corpus/cache`. The per-book table above is that diff; `margin-survey.json` is its summary.
