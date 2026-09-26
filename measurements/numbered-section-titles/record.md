# A book's own section numbering reads its titles as headings

Measured under [#297](https://github.com/vocaro/PDFReflowLib/issues/297) item 2, baseline `2bff36c6`
with item 3's en-dash change applied (so that item's sixty joins are not counted here),
2026-09-25, macOS 27 / Xcode 27, arm64, release CLI, sources from the pinned corpus cache. Every
manifest document was converted with the flags its manifest entry asks for and only the XHTML
kept.

## What the output was

`d3a74b9f` (the page's own leading, [page-leading-and-ligature-vocabulary](../page-leading-and-ligature-vocabulary/record.md))
split `2.1 Domingo-Ferrer and Mateo-Sanz` from its paragraph on the Census report's page 3. On
`2bff36c6` it is a block of its own and a paragraph, `<p>2.1 Domingo-Ferrer and Mateo-Sanz</p>`,
and so are `2 Data Files`, `2.2 Kim-Winkler`, page 2's `1 Introduction`, page 10's `4 Results` and
`4.1 Domingo Data Statistics`, and page 11's `4.2 Kim-Winkler Data Statistics`. The rasters set
every one of them as a heading: section titles in 12-point bold over the 10.08-point body,
subsection titles in bold at the body's size, each with space above and below.

## Why

- **No weight reaches the library.** `LayoutReconstructor.sectionLabels` (#218) needs a label to
  read wholly bold, and bold comes from the font name PDFKit reports. PDFKit reports every font of
  this report as `Helvetica` with no bold trait (#250, FB24908889). The font resources do not
  state a weight either: `dcbx100120`'s descriptor has `/Flags 4` and `/StemV 0`, like `dcr`'s, and
  its CFF Top DICT names only the family (`FontMonger:dcbx10`). None of the report's output carries
  `<strong>`; `Abstract.` and `Keywords:` are plain as well. So the recurring-style rule has no
  style to count, on three pages or on one.
- **A fifth larger is not title-sized.** The heading threshold is 125% of the page's heading body;
  12 over 10.08 is 119%. `sectionLabels` only takes lines under 115% of the body. The section titles
  fall in between. `7 References` is a heading only because page 17's body is its nine-point
  bibliography, against which 12 points is 133%.

## The rule

`NumberedSectionTitles` reads the book's outline from its numbering, as `doc/behavior.md`
(*Numbered section titles (#297)*) states in full:

- a candidate opens with a number of one or two levels, one or two digits each, no point after
  the last, then a capital and three letters; it stands at least 0.8 of a body below the line
  above it in its column and 0.4 above the line beneath, which must exist, and ends no sentence.
  A title wrapped onto one more line at its own size and leading ends on that line, which must
  stand apart from the text beneath, and the two become one heading;
- candidates come from native pages only, gathered in the extraction pass
  (`DocumentEvidence.collect`), and are read as an outline once the book is read: **sections** are
  one-level titles at least 10% over the page body at one size, at least three, from `1`, each
  number once, rising in reading order by at most three; **subsections** are two-level titles at
  the body's size, at least two, rising, each after the section its number names and before the
  next;
- a title the outline vouches for is passed to `role(of:)` with the page's labels and becomes a
  heading. Levels stay flat.

The census of the report's native candidates, in reading order: `1` (page 2, 12 pt), `2`, `2.1`,
`2.2` (page 3), `4`, `4.1` (page 10), `4.2` (page 11), `7` (page 17). Sections `3`, `5`, `6` and `8`
are on pages 4, 16, 16 and 18, which the report's damaged encoding sends to recognition, so the
native sequence reads `1, 2, 4, 7`: rising by at most three.

## What it moves across the corpus

Whole books, baseline against candidate, blocks in spine order with file boundaries ignored
(`bookdiff`):

| Book | titles now headings | anything else |
| --- | --- | --- |
| census-rrs2002-01 | `1 Introduction`, `2 Data Files`, `2.1 Domingo-Ferrer and Mateo-Sanz`, `2.2 Kim-Winkler`, `4 Results`, `4.1 Domingo Data Statistics`, `4.2 Kim-Winkler Data Statistics` | none on native pages |
| arxiv-replay-clocks-2023 | sections `1`–`10`: nine had opened their own paragraph (`1 INTRODUCTION According to the observer effect…`) and now head it; `6 REPRESENTATION OF REPCL AND ITS` / `OVERHEAD`, two paragraphs, is one heading | none |
| ucl-hebrew-shakespeare-2017 | the introduction's `1`–`4` and `3.1`–`3.3`, `4.1`–`4.3`; `1 The historical and literary background to the first Hebrew Shakespeare translations` over two lines | none |
| the other 21 books | none | OCR text only, below |

Every heading was read against its source render: Census pages 2, 3, 10 and 11, Replay Clocks
pages 1 and 6, the Hebrew study's pages 13 and 21. The Hebrew study's contents page (page 11)
lists the same numbers; its entries stand one leading apart and are no candidates.

Differences elsewhere are recognition reading the same page differently between runs, as #173 and
#284 record, on pages the rule never reaches (it reads no recognized page): the Hindi reader (17 of
17 pages recognized), Census's recognized pages, and Warren's inherited and recognized pages,
whose recognized page count moved between 12 and 9 across runs of binaries that all carry the
same extraction and diagnosis code.

### What the rule refused, and why

An earlier draft counted any three rising numbers as sections. *Agricultural Research*'s contents
page opens its display titles with the page they start on, `4 DWFP: A Battle Plan To Protect U.S.
Troops From` / `Harmful Insects`, `18`, `20`, `21`: rising, apart, larger than the body. Those were
headings already; the draft would have joined their wrapped lines. An outline starts at `1` and
counts on, and a page number does neither, so the rule asks for both and that book is unchanged.

## Tests

`Tests/PDFReflowLibTests/NumberedSectionTitleTests.swift`:

- `censusNumberedSectionAndSubsectionTitlesAreHeadings`: Census page 3 from the checksum-pinned
  layout fixture, its lines given the text the page prints, with pages 2, 10, 11 and 17 set as the
  report sets them, through `DocumentEvidence` and `LayoutReconstructor.blocks`. Page 3 heads
  `2 Data Files`, `2.1 …` and `2.2 …`; with no outline, or with page 3 alone as the book, it heads
  nothing; the numbered list and the paragraphs stay what they were.
- `anOutlineIsTheBooksOwnNumbering`: the outline's own rules, each with its refusal (two sections,
  a sequence from `2`, a repeated number, page numbers, sections at body size, a subsection before
  its section, a lone subsection, a subsection set large).
- `onlyALineThatStandsApartIsANumberedTitle`: a title and a wrapped title, against a bold run-in
  paragraph start, a wrapped numbered paragraph, numbered list items with and without a point, a
  line one leading below the text above it, a title with nothing beneath it, a bold body line, a
  title that ends a sentence, and the number grammar's refusals (`1.`, table rows, lower case,
  three levels, `0`, a bracketed equation number, three digits, too long).

Disabling the reconstruction's use of the outline fails the Census test's three heading
expectations; the unit tests are the rule's own.

## Contracts

`corpus/regressions.json`: Census `headings` on pages 2, 3, 10 and 11; Replay Clocks page 1
(`1 INTRODUCTION`) and page 6 (`6 REPRESENTATION OF REPCL AND ITS OVERHEAD`,
`7 SIMULATION RESULTS`); the Hebrew study's page 13 (its two-line section 1) and page 21
(`3 Salkinson’s Shakespeare translations`, `3.1 Publication and reception`).

## Commands

```sh
swift build -c release --product pdf-reflow
pdftoppm -r 60 -f 10 -l 11 -png corpus/cache/rrs2002-01.pdf <out>
pdftoppm -r 60 -f 6 -l 6 -png corpus/cache/2311.07842v1.pdf <out>
pdftoppm -r 50 -f 13 -l 13 -png corpus/cache/The-First-Hebrew-Shakespeare-Translations.pdf <out>
mutool show corpus/cache/rrs2002-01.pdf 146        # dcbx100120's descriptor
python3 tools/run_corpus_regressions.py --converter .build/release/pdf-reflow \
  --epubcheck "$(command -v epubcheck)" --output <lane> --case census-rrs2002-01 \
  --case arxiv-replay-clocks-2023 --case ucl-hebrew-shakespeare-2017
```
