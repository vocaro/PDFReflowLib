# A column label the recognizer split or joined

Measured under [#262](https://github.com/vocaro/PDFReflowLib/issues/262), baseline `ecee3eb`,
2026-09-22, macOS 27 / Xcode 27, arm64, release CLI at library defaults with a fixed package
identifier and modification date. Character counts are non-whitespace characters of every `<p>`,
`<pre>` and `<h*>` in the converted book.

[#257](https://github.com/vocaro/PDFReflowLib/issues/257) stopped a crop releasing a table's
column header into the prose, and took seven of the nine table lines
[#255](https://github.com/vocaro/PDFReflowLib/issues/255) had let out of the CIA report's
pictures back to their tables. Two escaped:

```
! lt>mber Per Cent Number Percent          (page 151)
I Number Per Cent Number PerCeat           (page 241)
```

`printsOneColumnLabel` compares the line's words one to one, allowing an edit distance of half
the shorter, because the recognizer spoils letters inside a word. Here it moved the spaces
instead — `Number` came back as `lt` and `mber`, `Per Cent` closed up into `Percent` and
`PerCeat` — so the words on either side of the repetition do not line up at all and there is
nothing for the comparison to be near.

## The two lines as main reads them now

[#264](https://github.com/vocaro/PDFReflowLib/issues/264) landed under this book the same day,
cutting the margin rule its recognition read as capital `I`s. Both lines survive it word for
word: page 151's still opens on the `!` the recognition put before `lt>mber`, and page 241's
still opens on an `I` that is not a margin mark but the table's own left rule read inside the
row. Read on `ecee3eb` they are exactly the two strings the issue quotes.

## The reading

The line is read a second way, on its letters in order with the printed spaces taken out. For
each number of columns from two upwards the letters are cut into that many pieces of equal
length, each cut moved to the nearest word boundary, and the pieces are compared exactly as the
words were — against the first piece and against the piece before it.

| Line | Letters | Cut | Pieces | Distance |
| --- | --- | ---: | --- | ---: |
| page 151 | `ltmberpercentnumberpercent` | 13 | `ltmberpercent` / `numberpercent` | 2 |
| page 241 | `inumberpercentnumberperceat` | 14 | `inumberpercent` / `numberperceat` | 2 |
| page 203 (#257's) | `numberpercent…numberpercelt` | 13, 26, 40 | four pieces, `nuntlerpercent` among them | 3 |

A piece the recognizer broke in two or ran together still stands where the label stands, so the
cut lands on it wherever its own spaces went.

Two things hold the reading in. A piece is a stretch of several words, and half of a piece is far
more room than half of a word: `humanfactorsscienceor` and `humanfactorstechnologies`, the two
halves of a sentence in the FAA handbook, are within half of the shorter. The pieces therefore
agree within **a fifth** of the shorter, which over a three-word label is tighter than the word
comparison already allows a single spoiled word inside it. And **every word of the line must hold
a letter**, because a label is written in words: dropping the printed spaces is exactly what lets
arithmetic repeat, and the IRS publication's `0 0 0 200` and Wallace's `3r + 6+ 3r =30` are a
table's own figures and an equation, not a heading.

## What the reading admits, over every row the geometry half accepts

`TableRegionDetector.columnHeaders` was instrumented to record every line of every printed row
that passes its column-edge test, over all eighteen corpus books converted with a release binary
built from `ecee3eb`. Sixteen books reach that test at all; `scotus-loper-bright-2024` and
`gpo-warren-1964-suspect-text-excerpt` state no column edge anywhere. The captured lines were
then replayed through the shipped `printsOneColumnLabel`, before and after.

| Book | Distinct lines | Newly read as a label | No longer read |
| --- | ---: | ---: | ---: |
| cia-blue-book-14-1955 | 16,572 | **96** | 0 |
| faa-phak-8083-25c | 21,382 | 0 | 0 |
| wallace-algebra-2010 | 11,690 | 0 | 0 |
| irs-p596-zhs-2025 | 5,247 | 0 | 0 |
| usda-ars-agresearch-2012-11 | 1,499 | 0 | 0 |
| fed-explained-2021 | 916 | 0 | 0 |
| gpo-911-2004 | 644 | 0 | 0 |
| arxiv-replay-clocks-2023 | 596 | 0 | 0 |
| uscis-m618-arabic-2015 | 479 | 0 | 0 |
| gpo-our-flag-2003 | 325 | 0 | 0 |
| dga-2025-2030 | 253 | 0 | 0 |
| cdc-zombie-pandemic-2011 | 174 | 0 | 0 |
| census-rrs2002-01 | 71 | 0 | 0 |
| nbs-jres-geltman-1977 | 66 | 0 | 0 |
| usgs-mcs2025-copper | 26 | 0 | 0 |
| ntrs-20180003024-earthdata-slides-2018 | 23 | 0 | 0 |

Of 59,963 distinct lines the letters reading adds 96, all of them in the one book, and takes none
away. Ninety-four are that book's column headers spelled some other way — `! r.imber Per Cent
Number Per Cent`, `Number Percent Nuoi>er Percent`, `Ce,lain Doubtful Total Certain Doubtf\11
Total ertain Doubtful Total Certain Doubtful Total`, `Co""t Variable Total Const Variable Total`.
The other two are handwriting inside the tables themselves, `cJ &.o /J. CJ` on page 199 and
`~ OIJ / J' I.J ~` on page 213; both stand inside a picture their crop already holds, neither
reads as English words, and neither moves a character.

The tolerances that were rejected, on the same capture. Every one of them reads both of the
issue's lines, so the two lines decide nothing here; what the corpus decides is the rest.

| Pieces agree within | Every word holds a letter | Newly read in the CIA report | Newly read outside it |
| --- | --- | ---: | --- |
| half the shorter | yes | 260 | 66: 49 in the FAA handbook, 9 in Wallace, 3 in the USCIS book, 2 in the 9/11 report, one each in the arXiv paper, the Fed's book and the magazine |
| half the shorter | no | 293 | 729, 621 of them rows of the IRS earned-income tables |
| a third | yes | 192 | 12: 9 in the FAA handbook, 3 in Wallace |
| a quarter | yes | 139 | 2, both in the FAA handbook |
| **a fifth** | **yes** | **96** | **none** |
| a fifth | no | 111 | 12: 8 in Wallace, 4 in the IRS tables |
| a sixth | yes | 84 | none, and twelve of the report's own headers go unread |

Half of a piece is what the word comparison allows a word, and over a piece it is far too much:
it reads `Human factors science, or human factors technologies,` and `Differential pressure—the
difference in pressure` as labels. A third still reads `reaches the saturation point. Second, the
saturation point may`; a quarter still reads `• Climbs and descents—during climbs and descents
in`. A fifth reads none of the corpus's prose, and a sixth buys nothing more while giving up
twelve of the headers this rule exists for.

Dropping the printed spaces is also what lets arithmetic repeat, which is why every word must
hold a letter: at a fifth without that guard the IRS publication's `0 0 0 200` and `1,050 1,100`
and eight of Wallace's exercises — `13)r2 + 3r + 2`, `5) (1− 7n)(1+ 7n)` — read as labels.

## What the two halves together now cost and recover

Every corpus book was converted twice, with release binaries built from `ecee3eb` and from this
change:

| Book | Before | After | Delta |
| --- | ---: | ---: | ---: |
| cia-blue-book-14-1955 | 610,813 | 610,132 | **−681** |
| every other covered book | | | 0 |

The seventeen other books are byte-identical entry by entry, 4,033 EPUB entries in all.

Thirteen blocks leave the CIA report's prose — nine from page 151 and four from page 241 — and
five appear. That is the two header lines and the table text the crops beside them can now grow
far enough to take:

| Page | Block | What it is |
| ---: | --- | --- |
| 151 | `! lt>mber Per Cent Number Percent` | the issue's first line |
| 241 | `I Number Per Cent Number PerCeat` | the issue's second line |
| 151 | `Enluabon` | the stub column's heading |
| 241 | `Evaluation` | the same |
| 151 | `~~~noon {/ I I tJ.C, 0./ t,f …`, `4-Bnds C I`, `I tJ./J IP.I ~/ …`, `S-Clouds. Oust, etc. …`, `....... I /) I tJ.I ao tu …`, `9-0lller 0 u 0 tJ.O. …` | rows of the table's handwritten figures |
| 151, 241 | two `Certain Doubtful Total …` rows | the eight-column header rows, of which the crop now takes the first half; the second half reappears as its own block |
| 241 | `>c S/G#7"""//Y6 …` | a figure title, which reappears split in two where the grown crop cuts it |

Nothing the issue asked to keep moves. The five lines #255 was landed for are still in the
prose — both of page 65's sentences and all three figure titles — and so are the magazine's
articles, whose 52,165 characters are unchanged.

## Reproducing

```
swift build -c release
.build/out/Products/Release/pdf-reflow \
  corpus/cache/CIA-UAP-015-Project_Blue_Book_Special_Report_No_14.pdf out.epub \
  --package-identifier urn:uuid:fixed --modification-date 2026-01-01T00:00:00Z
```

The line capture was taken by writing each edge-stating row's lines out of
`TableRegionDetector.columnHeaders`, and replayed through the shipped `printsOneColumnLabel`; the
per-book counts by converting every case in `corpus/regressions.json` with each binary and
counting non-whitespace characters in the XHTML. Neither capture is committed
([decision 0006](../../doc/decisions/0006-measurements-are-records.md)).
