# A crop keeps its table's column headers

Measured under [#257](https://github.com/vocaro/PDFReflowLib/issues/257), baseline `ec7e943`,
2026-09-20, macOS 27 / Xcode 27, arm64, release CLI at library defaults with a fixed package
identifier and modification date. Character counts are non-whitespace characters of every `<p>`,
`<pre>` and `<h*>` in the converted book.

[#255](https://github.com/vocaro/PDFReflowLib/issues/255) stopped a crop from burying a line that
reads as the book's own prose, recovering 45,754 characters across eight of the eighteen corpus
books. In `cia-blue-book-14-1955` part of what it let out is not prose: the column headers of the
statistical tables the crop preserves as pictures. Every token of
`Number Per Cent Number Per Cent Nuntler Per Cent Number Per Celt` and
`Certain Doubtful Total Certain Doubtful Total ertain Ooubtfut Total` is an English word, so the
word test admits them, and beside the picture of their own table they say nothing a reader can
use.

## What the release rule actually let out

`LayoutReconstructor.expanded` was instrumented to record every line the #255 fallback releases.
Over the whole book it releases **fourteen distinct lines**; the rest of that book's +2,520
characters is knock-on, lines a crop no longer grows far enough to take.

| Page | Line | What it is |
| ---: | --- | --- |
| 132 | `Total ~rtai• Doubtful Total Certain Doubtful Total Certain Doubtful Tola! …` | table column header |
| 133 | `7-Psycllolocical I /; I ;/o.o fJ.O ,uo I 0 I It. 7 /J,0 1,.1` | table row, handwritten figures |
| 136 | `Certain DoubHul Total Certain DoubHul Total Certain lku>lful Total …` | table column header |
| 151 | `! lt>mber Per Cent Number Percent` | table column header |
| 203 | `Number Per Cent Number Per Cent Nuntler Per Cent Number Per Celt` | table column header |
| 222 | `-Variable Total Const Variable Total` | table column header |
| 241 | `Number Per Cent Number Per Cent` | table column header |
| 241 | `I Number Per Cent Number PerCeat` | table column header |
| 241 | `Certain Doubtful Total Certain Doubtful Total ertain Ooubtfut Total …` | table column header |
| 28 | `FIGURE 2 DISTRIBUTION OF EVALUATIONS OF OBJECT,` | figure title |
| 28 | `UNIT, AND ALL SIGHTINGS FOR ALL YEARS I` | figure title |
| 34 | `FIGURE 8 DISTRIBUTION OF OBJECT SIGHTINGS BY SIGHTING` | figure title |
| 65 | `I All of the above calculations were made with IBM equipment. Sines,` | the book's own prose |
| 65 | `I Having found the angle ZS, the bearing of the sun ( angle B} was ob` | the book's own prose |

Nine belong to a table; five are what the issue asked to recover and must stay recovered.

## Why `rowBlocks` reads nothing here

`TableRegionDetector.rowBlocks` was run over every one of those pages' lines, crop text included.
It returns **no block on any of them**. It reads a table from a run of rows sharing one left edge,
one type size and one leading, and this book's inherited text layer has none of that: one table on
page 203 hands its rows back at 5.6, 16.0, 9.0, 10.2 and 19.4 points. Its second-cell rule also
requires a cell to begin inside the width the run's opening cells reach, and here the stub column
(`0-Balloon`, 17 pt wide at x=85) ends long before the first data cell begins at x=130.

## The rule, and why geometry alone is not enough

`TableRegionDetector.columnHeaders` reads a header from two things at once.

**The page set the line in a table's columns.** Its printed row holds pieces the page kept apart
as cells — each beginning at or after the one before it ends — and at least two other rows of the
page begin a piece on the same column edge. Page 203's `Evaluation | Certain Doubtful Total … |
ertain Doubtful Total …` has that shape, on the edges every row of the table below stands on. A
line of prose is one piece, and where the extractor merges two printed lines into one row — this
book paints a rule down its margin, and the tall rectangle that gives the line swallows the line
beneath — the second piece begins inside the first rather than after it.

That half alone refuses all nine table lines and releases all five of the others. It also costs
seven other books, because it is not a statement about tables at all:

| Book | #255 baseline | Geometry alone | Geometry and crossing proof |
| --- | ---: | ---: | ---: |
| usda-ars-agresearch-2012-11 | 52,208 | 34,868 (**−17,340**) | 40,506 (−11,702) |
| irs-p596-zhs-2025 | 36,696 | 34,335 (−2,361) | 34,944 (−1,752) |
| wallace-algebra-2010 | 320,518 | 319,314 (−1,204) | 319,314 (−1,204) |
| faa-phak-8083-25c | 1,414,612 | 1,414,153 (−459) | 1,414,472 (−140) |
| arxiv-replay-clocks-2023 | 39,855 | 39,727 (−128) | 39,816 (−39) |

The magazine sets three columns whose lines PDFKit hands back on shared baselines, so every row of
its running prose holds pieces the page kept apart on an edge every other row states. Two thirds
of what #255 recovered from that book goes back inside the pictures. `rowBlocks` guards the same
case with merged rows reaching across the boundary; adding that proof here recovers a third of the
loss and no more, because the magazine's own pages set headlines and captions across their
gutters.

**The line prints one column label once per column.** That is what a header is and what prose is
not: the same short group of words over and over. It is read against the first group and against
the group before, because the recognizer spoils words a group at a time, and words are compared
within an edit distance of half the shorter one, because it spoils letters within a word —
`Nuntler` for `Number`, `Ooubtfut` for `Doubtful`. Four repeated words in five must agree.

Tested against the 226 distinct lines the geometry half refuses across the magazine, the IRS
publication, Wallace's algebra, the FAA handbook and the arXiv paper, **not one** prints a
repeated label. The nearest miss is `10 lbs of nuts and 20 lbs of chocolate`, a worked exercise in
Wallace, at three repeated words in four.

## What the two halves together cost and recover

Every corpus book was converted twice, on `ec7e943` and on this change:

| Book | Before | After | Delta |
| --- | ---: | ---: | ---: |
| cia-blue-book-14-1955 | 610,356 | 608,899 | **−1,457** |
| every other covered book | | | 0 |

The other seventeen covered books are unchanged to the character, so #255's 45,754-character
recovery stands except for the CIA report's own share, which falls from +2,520 to +1,063 against
the pre-#255 reading of 607,836.

Seven of the nine table lines go back to their tables — pages 132, 133, 136, 203, 222 and two of
page 241's three — and with them 1,457 characters of knock-on table text, including the
handwriting the issue quotes, `y,e t9?t- ,_ •• ,,IL .,,r:,,o`, which a crop now grows far enough
to take again. All five lines #255 was landed for are still released, read back from the same
instrumented run: both of page 65's sentences and all three figure titles.

## What this does not reach

Two of the nine escape, and both are spoiled past the point where a repeated label can be read:

- page 151's `! lt>mber Per Cent Number Percent` — the recognizer broke `Number` into `lt` and
  `mber` and closed up `Per Cent` into `Percent`, leaving no two groups that agree;
- page 241's `I Number Per Cent Number PerCeat` — the same, with `PerCeat` for `Per Cent`.

The comparison is word to word, so a word the recognizer split or joined has no counterpart to be
near. Filed as [#262](https://github.com/vocaro/PDFReflowLib/issues/262).

The handwriting half of the issue is not this rule's. That book's inherited OCR layer is
unverified and [#216](https://github.com/vocaro/PDFReflowLib/issues/216) catalogues what it
produces; the lines this rule takes back are those its geometry and its own words identify as a
table's, not those a reader would call badly recognized.

One thing beyond the headers goes back into the pictures: the report's code tables in chapter 19,
`CODE 65 LIGHT BRIGHTNESS (Intensity) X Decreased y 0 Sunlight on mirror l Sunlight on aluminum
2 Sunlight on plaster …`, which repeat `Sunlight on …` once per code and so read as one label per
column. They are the legend of the picture beside them, and the picture is still there.

## Reproducing

```
swift build -c release
.build/out/Products/Release/pdf-reflow \
  corpus/cache/CIA-UAP-015-Project_Blue_Book_Special_Report_No_14.pdf out.epub \
  --package-identifier urn:uuid:fixed --modification-date 2026-01-01T00:00:00Z
```

The released-line table was captured by printing `line.rect` and `line.text` from the
`releasesProse` branch of `LayoutReconstructor.expanded`; the per-book counts by converting every
case in `corpus/regressions.json` with each binary and counting non-whitespace characters in the
XHTML. Neither capture is committed ([decision 0006](../../doc/decisions/0006-measurements-are-records.md)).
