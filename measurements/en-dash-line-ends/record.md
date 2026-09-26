# A line broken after a closed en dash carries on with no space

Measured under [#297](https://github.com/vocaro/PDFReflowLib/issues/297) item 3, baseline `2bff36c6`,
2026-09-25, macOS 27 / Xcode 27, arm64, release CLI, sources from the pinned corpus cache. Every
manifest document was converted with the flags its manifest entry asks for
(`evaluate_real_document.conversion_flags`) and pinned packaging, once with `2bff36c6`'s binary and
once with this change, and only the XHTML kept; the EPUBs were discarded as they were read.

## What was wrong

`HyphenRepair.joinOperation` closed up a line only when it ended in a hyphen or a soft hyphen;
every other line end took a space. A range the page broke after its en dash came out with a space
of the library's own in it. The Census report's page 17 sets reference [ 9] as
`…Survey Research Methods, (1990) 456–` over `461.`, and [ 10] as `…(1995) 114–` over `119.`
(read against the page's raster; its text layer is index-shifted, so no text tool reads it), and
the conversion wrote `456– 461` and `114– 119`.

## What the corpus's own line ends say

`pdftotext` reads every other corpus source's text layer line by line. Its lines ending in U+2013,
classified by the character before the dash and the one opening the next line:

| before the dash | next line opens with | lines | books |
| --- | --- | ---: | --- |
| a space | anything | 272 | Hebrew Shakespeare (271), FAA (1) |
| a figure | a figure | 33 | NCA5 20, Loper Bright 10, 9/11 1, Replay Clocks 1, Hebrew Shakespeare 1 |
| a figure | a capital | 22 | 9/11 19, NCA5 3 |
| a letter | a lower-case letter | 15 | NCA5 |
| a letter | a capital | 9 | NCA5 7, 9/11 1, FAA 1 |
| other | | 6 | 9/11, Loper Bright, FAA, Fed |

A dash with a space before it is the parenthetical dash, `word – word`: the Hebrew Shakespeare
study sets `(Shavit 1993: 117–18) –` over `although not all early Maskilim`, and its space after is
the page's own. A dash closed against the letter or figure before it is a closed dash, and every
one of those the sweep below joins reads closed in its source: ranges (`10407–10418`,
`(2020–2050)`, `761–763`, `134–141`, `January 31–July 3`, `S38–S43`, `E836–E848`) and compounds
(`Saffir–Simpson`, `social–ecological`, `land–ocean–atmosphere`, `intensity–duration–frequency`,
`September–October`, `Surveillance–Broadcast`, `Kansas–Nebraska`). NCA5 also prints the suspended
form `natural resource– and outdoor-dependent economies`, with a space after the dash; that one
stands inside a line, so no join reaches it.

## The rule

`LayoutReconstructor.breaksAtClosedEnDash`: a line ending in U+2013 whose character before the
dash is a letter, a figure or `_`, joined to a line opening with a letter, a figure or `_`, joins
with no space. `_` is Loper Bright's blank page number, `589 U. S. ___, ___–` over `___ (2020)`.
Everything else keeps the space: a spaced dash, a dash alone on its line, a next line opening with a
marker, bracket or quotation mark. The dash is never looked up in the vocabulary and never raises
`uncertainHyphen`. Only the en dash is read.

## What it moves across the corpus

Every block of every manifest document, baseline against candidate (`sweepdiff`, block by block):

| Book | joins closed | anything else |
| --- | ---: | --- |
| noaa-nca5-2023 | 44 | one reference moved between two spine files: `(1970– 2019)` lost a byte and the packer's byte budget took the next block into the earlier file |
| scotus-loper-bright-2024 | 11 | none |
| census-rrs2002-01 | 2 | none |
| arxiv-replay-clocks-2023 | 1 | none |
| gpo-911-2004 | 1 | none |
| faa-phak-8083-25c | 1 | none |
| the other 18 books | 0 | none |

**Sixty joins, and not one other character of any book changed.** Every one of the sixty is a
line end the table above counts, closed in its source (the Census pair on the raster). Of the
source's closed line-end dashes the rule does not reach, 21 are 9/11's open ranges ending an entry
of its cast of characters (`Deputy Secretary of State, 2001–`), whose next line is the next
entry, in a block of its own before and after; two end a page; and four sit in text no join
reaches (FAA's `.–`, the Fed's chart `$–`, a NCA5 figure caption the crop takes, a Hebrew
Shakespeare bibliography line). None of the 272 spaced dashes changed.

## Not changed here

- **Em dashes.** Eight books end 124 source lines with an em dash closed against a letter, and the
  conversion sets 101 of them `word— word` (9/11 45, NCA5 29, Loper Bright 12, FAA 8); inside their
  lines those books close the em dash on both sides (9/11 727 closed, none spaced after). The same
  shape for a different character with its own conventions, outside this issue's scope:
  [#315](https://github.com/vocaro/PDFReflowLib/issues/315).
- **Hebrew Shakespeare's `117– 18` inside a line.** 384 ranges read `117– 18` where the page prints
  `117–18`, none of them at a line end. `mutool trace` on page 14 shows the source drawing a space
  glyph after the dash and taking its advance back before the next figure (the space at x 139.868,
  the `1` at 139.867), so the text layer itself states the space; this rule never sees it, and 231
  hyphens in that book read the same way (`back- translation`):
  [#316](https://github.com/vocaro/PDFReflowLib/issues/316).

## Tests

`Tests/PDFReflowLibTests/HyphenRepairTests.swift`, three tests:

- `aLineBrokenAfterAClosedEnDashCarriesOnWithNoSpace`: Census's `456–` over `461.`, NCA5's
  `(2020–` over `2050)`, `January 31–`/`July 3`, `S38–`/`S43.`, Loper Bright's `___–`/`___`, and the
  compounds `Saffir–`/`Simpson` and `social–`/`ecological`; no warning.
- `aSpacedOrStrandedEnDashKeepsTheSpaceAfterIt`, the controls: the Hebrew study's spaced dash, the
  FAA's `following –`, a dash alone, a next line opening with a bullet, a bracket or a quotation
  mark, a dash closed against punctuation, a line with no dash.
- `aParagraphBrokenAfterARangeReadsTheRangeWhole`: reference [ 9] over three lines through
  `LayoutReconstructor.blocks`, with a spaced-dash paragraph beneath it as the control.

Disabling the rule fails 8 expectations in the first and third tests; the controls pass either way.

## Contracts

`corpus/regressions.json`: Census page 17 orders `…(1990) 456–461.` and `…(1995) 114–119.` and
forbids `456– 461` and `114– 119`; Replay Clocks page 10 (`pages 134–141, 1990.`), Loper Bright
page 45 (`576 U. S. 743, 761–763 (2015)`) and NCA5 pages 185 (`Saffir–Simpson`) and 510
(`social–ecological systems`) the same way. `2bff36c6`'s output holds each forbidden form (the
sweep above).

## Commands

```sh
swift build -c release --product pdf-reflow
pdftotext -enc UTF-8 corpus/cache/<file>.pdf <out>.txt     # every cached source
mutool trace corpus/cache/The-First-Hebrew-Shakespeare-Translations.pdf 14
python3 tools/run_corpus_regressions.py --converter .build/release/pdf-reflow \
  --epubcheck "$(command -v epubcheck)" --output <lane> --case census-rrs2002-01 \
  --case arxiv-replay-clocks-2023 --case scotus-loper-bright-2024 --case noaa-nca5-2023
```
