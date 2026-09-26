# A space glyph the page takes back is no word space

Measured under [#316](https://github.com/vocaro/PDFReflowLib/issues/316), baseline `af18cfb9`,
2026-09-25, macOS 27 / Xcode 27, arm64, release CLI, sources from the pinned corpus cache. Every
one of the 24 manifest documents was converted with the flags its manifest entry asks for
(`evaluate_real_document.conversion_flags`), `--no-ocr` wherever the entry names no OCR mode, and
pinned packaging (`--package-identifier urn:uuid:identity --modification-date
2026-01-01T00:00:00Z`), once with `af18cfb9`'s binary and once with this change. Only each book's
XHTML and EPUB hash were kept; the EPUBs were discarded as they were read.

## What was wrong

*The First Hebrew Shakespeare Translations* (`ucl-hebrew-shakespeare-2017`, `--language he`) read
`(Shavit 1993 : 117– 18)`, `4.2 The English back- translation`, `non- fi ction` and `twenty- fi ve`
where the page prints `(Shavit 1993: 117–18)`, `back-translation`, `non-fiction` and
`twenty-five`. Its XHTML held 384 `<figure>– <figure>` against 2 closed, and 326
`<letter>- <letter>` against 87 closed.

The book (InDesign CS5.5 through Distiller 7) marks every place a line may break without a space
with a space glyph and a `TJ` adjustment that takes the space's advance back. Page 14 draws
`[( )254(:\002)-32(117\205 )254(18\)…`: `–`, then a space of 0.222 em plus 0.0319 em of word
spacing, then an adjustment of 254 that brings the `1` back to 0.0001 em short of where the space
began (`mutool trace`: the space at x 139.868, the `1` at 139.867). The same mark stands after
slashes (`wit/ it`, URLs), around each linked citation (`( )254(1993)`, then `( )254(:`), before
closing punctuation (`Godless ,`), inside transliterations drawn in another font (`Shibbu ṣ`,
`HaSha ḥ ar`), between the two letters of a small-capital `L ord`, and after every `ﬁ` and `ﬂ`
ligature, where the adjustment stands in front of the space instead (`ﬁ` ends at x 167.07, the
space begins 0.283 em back inside it, and its advance brings `c` to 167.08). PDFKit reads each as
a space.

The spacing reader could not have seen most of them in any case: it refused every page that sets
a text rendering mode other than 0, and the study strokes its pointed Hebrew with `1 Tr` and
`2 Tr` on the bilingual pages whose English notes carry most of the ranges. It read 113 of the
book's 553 pages.

## Where the corpus draws a space and takes it back

Every U+0020 glyph every manifest document draws upright was paired with the glyph the content
stream draws next (`mutool trace`, all pages, independent of the library). Spaces with a drawn
character on both sides whose next glyph begins within ±0.01 em of the space's own origin:

| book | such spaces | what they are |
| --- | ---: | --- |
| ucl-hebrew-shakespeare-2017 | 10,818 | the marks above; in the Hebrew passages a space between a word and its punctuation |
| faa-phak-8083-25c | 112 | contents leaders (`Dehydration⟦ ⟧.....`), chart labels |
| cia-blue-book-14-1955 | 106 | its invisible OCR layer (`Tr 3`), which the visible reader never reads |
| noaa-nca5-2023 | 17 | contents leaders |
| fed-explained-2021 | 10 | `short⟦ ⟧falls`, `collec⟦ ⟧tion`, `www.⟦ ⟧federalreserve`, `check-⟦ ⟧collection` |
| gpo-911-2004 | 4 | `angry. . . . ⟦ ⟧[T]he`, `a price. . . . ⟦ ⟧One` |
| usda-ars-agresearch-2012-11 | 3 | `infor⟦ ⟧mation`, `discri⟦ ⟧mination`, `Non⟦ ⟧-copyrighted` |
| nbs-jres-geltman-1977, uscis-m618-arabic-2015 | 2, 1 | an invisible OCR layer; an Arabic period |
| the other 14 books | 0 | |

9/11's four are the case a rule on the space alone would get wrong: the letter-spaced ellipsis
carries 0.196 em of character spacing into the space glyph, so the next mark stands where the
space begins but a word-size gap already separates it from the last period. A take-back is the
next mark standing where the *mark before the space* ends. FAA's and NOAA's leaders begin anywhere
from 0 to 0.1 em after their title's last glyph (FAA 100 within 0.01 em, 46 within 0.02, 168
within 0.05, 320 within 0.1), a tab stop's accident and not a take-back, and each is a space drawn
as a show of its own between the title's show and the leader's.

The reader's own placement of every space glyph between two marks (every page it reads, gap from
where the mark before the run of spaces ends to where the mark after it begins, in em):

| book | gap in [−0.1, 0.01] | narrowest gap above 0.01 |
| --- | ---: | --- |
| ucl-hebrew-shakespeare-2017 | 4,061 (3,475 within ±0.001; kerns to −0.064, `Bar-⟦ ⟧Yosef`) | 0.0101 |
| fed-explained-2021 | 9, all within ±0.001 | 0.020, a leader space narrowed by word spacing |
| gpo-911-2004 | 0 | 0.0446, `New⟦ ⟧York` narrowed by word spacing (`-0.234 Tw`) |
| faa-phak-8083-25c | 0 | 0.035 |
| every other book | 0 | 0.13 or more |

The study also leaves 19 spaces between 0.01 and 0.2 em after a dash, hyphen or slash closed
against the word before it: the adjustment takes back the space glyph's own 0.222 em and leaves
the line's word spacing (`39–⟦ ⟧41` 0.027, `52–⟦ ⟧3` 0.070, `my back-⟦ ⟧translation` 0.165 em on a
loose line). The page
draws that gap, and geometry cannot tell it from a word space: 9/11 page 115 sets `at Norfolk, V…`
with an adjustment of 0.2791 em against its 0.278 em space glyph and leaves a 0.161 em word space.
They keep their reading ([#323](https://github.com/vocaro/PDFReflowLib/issues/323)).

## The rule

`NativeSpacingReader.takesBackSpace`: a run of U+0020 glyphs of positive width between two marks
— the mark after it in the run's own show, straight after the run or after a `TJ` adjustment, and
the mark before it in that show or ending the show before on its baseline at its size — is taken
back where the mark after begins within 0.01 em of where the mark before ends, or up to 0.1 em
back over it. A run that ends its show (page 35's title, `[( )-228(The English back)45(- )]TJ`,
then `translation` positioned by `Td` at the hyphen's end) reaches the next show's first mark only
where the mark before it is the run's own show's; a space drawn as a show of its own is placed by
its own positioning, like FAA's leader tabs. A taken-back space is a closure in the line's source
reading, and `closedSpaces` removes PDFKit's one space there.

Three changes carry the rule to the book's pages:

- **Render modes 1 and 2 are read.** Filled, stroked or filled-and-stroked text places its glyphs
  alike; the invisible reader still reads mode 3 alone and the visible one refuses 3 to 7. The
  reader now reads 516 of the study's 553 pages, 1,822 of NCA5's 1,834 (one more) and 15 of the
  Hindi reader's 17 (none before); no other book gains a page, and neither NCA5's nor the Hindi
  reader's EPUB changes by a byte.
- **A removal is owned across a split row.** PDFKit splits a note's number and text, one show,
  into two lines (`40` and `This and the next line … (2.1.129– 30).`), so neither line spelled the
  show whole and the whole-line walk owned neither. A line whose marks fill exactly one run of the
  shows' marks now owns the closures inside that run.
- **A ligature counts as the letters it joins.** PDFKit reads the study's `ﬁ` as `fi`, and the
  whole-line walk stopped at the first one.

## What it moves across the corpus

| book | EPUB | change |
| --- | --- | --- |
| ucl-hebrew-shakespeare-2017 | differs | below |
| fed-explained-2021 | differs | 8 spaces removed: `shortfalls`, `https://www.federalreserve.gov`, `crisis—assigned`, `collection`, `(figure 6.2)`, `check-collection` twice, `community-oriented` |
| the other 22 books | byte-identical | none |

The Hebrew study, block by block over the whole spine:

- **3,108 spaces removed**, and every one sits where the page prints nothing: 993 inside a word
  (`fi|rst` 68 times, `fi|nd` 88, `L|ord` 27, `shibbu|ṣ`, `HaSha|ḥar`, and the first word of a
  speech whose opening letter the page sets apart, `W|hat`, `A|nd`), 366 after an en dash, 297
  after a hyphen, 296 after a slash, 912 before closing punctuation, 125 between a year and its
  colon, 104 after an opening bracket or quotation mark, and 15 before a dash or a year's letter
  (`2004|a`).
- **The bibliography's entries** (pages 547–552) now open at their own author–year openings: 18
  runs, 64 blocks before and 58 after; entries run together (`Barb … Knoller . Bar- Efrat …`) now
  stand apart and entries broken at a line end (`Amit … 508 – 57 .` / `Oxford : …`) now stand
  whole. Two entries break anew at a wrapped line that opens with a number and a period
  (`Markel … Epidemics of` / `1892. Baltimore`, `Singerman … 140–` / `54. New York`): the line
  reads as a list marker once the stray space before its period is gone, the defect 9/11, the Fed
  and NCA5 already show at `in Hamburg in` / `1995. The` ([#322](https://github.com/vocaro/PDFReflowLib/issues/322)).
- **Page 476**: 25 lines of Hebrew verse that read as `h2` headings read as paragraphs, and two
  pairs of them join. The page's only other change is the spaces its notes lose (13 taken back
  there), and its heading threshold is read from the size its lines hold the most characters in
  (`LayoutReconstructor.bodySize`), which those spaces tipped.
- **Page 410**: `stiff necked` reads `stiff-necked`. The line ends `stiﬀ-`, with the ligature's
  space inside the `ﬀ`; without it the hyphen repair sees the compound the book prints in its note
  on the same page (`a stiff-necked people`).
- **Page 324**: the cast list's `Friar Laurence … Rezin` row is two paragraphs, not one. This is
  the only change reading the stroked pages makes by itself (a build reading modes 1 and 2 with
  the rule turned off changes nothing else in the book): #172's detached-label split reaches the
  row now that the page's shows are read.

Counts in the book's XHTML:

| | `af18cfb9` | this change |
| --- | ---: | ---: |
| `<figure>–<figure>` closed | 2 | 398 |
| `<figure>– <figure>` spaced | 384 | 26 |
| `<letter>-<letter>` closed | 87 | 369 |
| `<letter>- <letter>` spaced | 326 | 46 |

Of the 46 spaced compounds three are suspended hyphens the page spaces (`nineteenth- and early
twentieth-century`, `sixteenth- and seventeenth-century`, `twelfth- or thirteenth-century`). The
26 ranges and 43 compounds left are [#323](https://github.com/vocaro/PDFReflowLib/issues/323):
16 ranges and 6 compounds on the 37 pages the reader still refuses as a whole, spaces whose word
spacing the page keeps (above), and lines that also hold the study's pointed Hebrew, which the
reader does not decode, so the shows cannot account for PDFKit's reading of the line.

## Tests

`Tests/PDFReflowLibTests/TakenBackSpaceTests.swift`, seven tests over a page drawn in one simple
font (`Widths`: space 250, hyphen 333, en dash 500):

- `aSpaceGlyphWhoseAdvanceATJKernTakesBackIsNoWordSpace`: after an en dash, after a hyphen, with
  word spacing taken back too, behind a kern, in front of the space (the ligature form) and a run
  of three.
- `aSpaceTheShowBeforeOrAfterTakesBackIsNoWordSpace`: a citation's own show, and page 35's title.
- `everySpaceThePageDrawsKeepsItsReading`, the controls: an ordinary space and a spaced dash, a
  space justified narrower but not taken back (by word spacing and by an adjustment), word spacing
  kept after the glyph's width, 9/11's ellipsis gap before the space, a `TJ` gap with no space
  glyph, a space drawn as a show of its own, and a mark drawn far back.
- `aTakenBackSpaceIsNoWordSpaceWithinAFractionOfAHundredthOfAnEm`: the thresholds.
- `aTakenBackSpaceIsRemovedWhereTheLineHoldsItsShows`: the closure at the space, runs, a space of
  the page's own beside it, the split note row, a line placed twice, a line holding a hole, and a
  ligature both ways.
- `strokedTextIsReadLikeFilledText`: modes 1 and 2 read, 3, 4 and 7 refused.
- `aLineReadsTheRangeAndTheCompoundThePagePrints`: end to end through PDFKit, which reads
  `pages 117– 18 in all` and `the English back- translation` without the rule.

Turning the rule off (`takesBackSpace` always false) fails 17 expectations in five of them; the
controls pass either way.

## Contracts

`corpus/regressions.json`, `ucl-hebrew-shakespeare-2017`: page 14 orders `form (Shavit 1993:
117–18) – although not all early Maskilim`, `(Shavit 1993: 114–15; Eldar 2016: 29)`, `other forms
of non-fiction. Maskilic fiction included`, `(Almagor 1975: 721–6; Toury 2012: 162–72)` and `there
was a gap of twenty-five years`, and forbids `117– 18`, `114– 15`, `1993 :`, `non- fi ction` and
`twenty- fi ve`; page 35 heads `4.2 The English back-translation`, orders it after `consulted the
Schlegel-Tieck German translation` and before `accompanied by a facing English back-translation.
The primary purpose of the back-translation`, and forbids `back- translation` and `Schlegel- Tieck`.
`af18cfb9`'s output holds each forbidden form.

## Commands

```sh
swift build -c release --product pdf-reflow
mutool trace corpus/cache/The-First-Hebrew-Shakespeare-Translations.pdf 14
mutool show -b corpus/cache/The-First-Hebrew-Shakespeare-Translations.pdf pages/14/Contents
.build/release/pdf-reflow corpus/cache/<file>.pdf <out>.epub <manifest flags> --no-ocr \
  --package-identifier urn:uuid:identity --modification-date 2026-01-01T00:00:00Z
python3 tools/run_corpus_regressions.py --converter .build/release/pdf-reflow \
  --epubcheck "$(command -v epubcheck)" --output <lane> --case ucl-hebrew-shakespeare-2017 \
  --case fed-explained-2021
```
