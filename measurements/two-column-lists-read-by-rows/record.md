# A stack of cells standing on the rows beside them is not a column of the page (#283)

Tier: deterministic Apple PDF stack; a source-derived extraction fixture for the page, and an
isolated macOS arm64 release CLI at `--no-ocr` with fixed packaging for the corpus comparison.
Corpus: `gpo-911-2004` physical page 451 (appendix B, the table of names), with all 23 cached
sources converted for the comparison.
Build: this change over `main` at `9649a62`, Xcode 27.0 (27A266a), Swift 6.4, macOS 27.0 (26A428,
Darwin 27.0.0, xnu-13432.1.9~1); release executable SHA-256
`a4f3311871b80fbeda405cd4f853ec43e75317310f7a4c72362f114282951cfa`, against `9649a62`'s
`78416ee97cbbf61a04fe7142e5cabe40552d5611ea5d7c3d407f23b208c70b67`.

## The page

Appendix B sets twenty-three printed rows, a name at x=44.70 and an office at x=152.70, with 29
points of white between them — four times what a straight column cut needs:

```
y=537.86  x= 44.70 w= 74.54  'Thomas Pickering'
y=537.86  x=152.71 w=149.36  'Under Secretary of State, 1997–2000'
y=526.60  x= 44.70 w= 52.91  'Colin Powell'
y=526.60  x=152.70 w= 99.94  'Secretary of State, 2001–'
y=504.10  x= 44.70 w=229.00  'Janet Reno Attorney General, 1993–2001'   <- one line, both columns
```

PDFKit merges exactly one of those rows, and that undivided line bridging the gutter is the only
thing that keeps the page from being cut there. Divide it — which is the correct reading of what
the page prints, and what #270's rule does on its own geometry — and the page reads twenty-three
names and then twenty-three offices, `Thomas Pickering Colin Powell Ronald Reagan …`, and no
reader can tell whose office is whose. #270 declined the page for that reason and left the defect
here.

The defect is the straight cut, not `columnRuns`: that rule's substance test already refuses this
page on its own, because no name reaches twelve bodies.

## The rule

A straight cut is refused where one side is a stack of cells standing on the rows of a column of
prose: three or more elements, no two of them on one row, each on the row of a line on the other
side, not one of them a text line of the measure a column is set to, not one of them opening a
list marker — and the other side holding two lines of that measure.

Three rows at least, and each on its own row: two cells beside two lines are a label and a
heading, which #277's page-number rule already reads where they are numbers, and one element is no
stack. A line the page lettered sideways is never one of these cells, its rectangle being as tall
as the line is long (#263).

**The other side has to be a column.** Cells beside prose are that prose's rows; two stacks of
cells beside each other are two columns, and reading them across takes each apart. The 9/11
report's own staff pages, twelve leaves before the appendix this issue is about, set a name over
the post they held down both sides of the page — `Joanne M. Accolla` / `Staff Assistant` on one
side, `Samuel M. W. Caspersen` / `Counsel` on the other. Every one of those names is short, on its
own row and beside a line of the other column, and without this condition page 13 read
`Joanne M. Accolla`, `Samuel M. W. Caspersen`, `Staff Assistant`, `Counsel`, which is neither
column. Two lines of twelve bodies is the same substance the narrow-gutter test already asks of
both sides.

**And not one of them numbered.** A numbered grid states its own order. Without that condition the
rule reorders Wallace's two-per-row exercise grids from column order to number order —

```
+2) 4− (− 1)
+4) (− 6) +8
+6) (− 8)− (− 3)
```

— which is exactly the switch the owner approved in #195 and #219 item 4 scopes, naming
`rowMajorLabels`, `columnNumberedGridsAndExerciseSetsKeepColumnOrder` and the Wallace contract as
what has to move with it. Making it happen as a side effect of a reading-order guard, without
those, would land on-hold work and put the lane's Wallace contract at odds with the reading.

## What each condition costs, measured

Four forms of this rule were converted over the whole corpus, each against the build before it:

| form | books moved of 22 | what it did that it should not |
| --- | ---: | --- |
| any short cell on the row of a line beside it | 10 | dozens of blocks in several books, thousands of characters in two |
| + three rows, each on its own row | 4 | reordered Wallace's two-per-row exercise grids into number order |
| + no cell opening a list marker | 4 | read the Blue Book's scanned statistical tables across their rows, moving 13 of its 20 documents and 1,036 characters onto one page; read the 9/11 report's own two-column staff pages across, so `Joanne M. Accolla` was followed by `Samuel M. W. Caspersen` |
| + the other side is a column of prose | 3 | the CDC comic's page 23, below |

Each row is the whole corpus converted twice, not a spot check.

## Before and after

Nineteen of the twenty-two cached sources are byte-identical. Three move.

**The 9/11 report, one document of thirty-six, 486 blocks to 529, and its character count the same
to the character.** This is the win, and it is not the latent page: appendix A's own page 447 has
the same shape as 451 and PDFKit merges enough of its rows for the cut to be made there today, so
the page reads a run of names and then a run of offices. Every one of them now keeps its own:

```
-<p>Newt Gingrich Rudolph Giuliani John Gordon Al Gore, Jr. Scott Gration</p>
-<p>Stephen Hadley Dennis Hastert Karl Inderfurth</p>
-<p>NSC counterterrorism official, 1999–2001 Commander in Chief, NORAD and …</p>
+<p>Newt Gingrich</p><p>Speaker of the House, 1995–1999</p>
+<p>Rudolph Giuliani</p><p>Mayor, City of New York, 1994–2001</p>
+<p>John Gordon</p><p>Deputy Director of Central Intelligence, 1997–2000</p>
```

Forty-three blocks' worth of the appendix, from `Ralph Eberhart` to `Thomas Pickard`. Page 451
itself is unchanged, because its one merged row still bridges the gutter; what this does for that
page is make the reading right for when #270's cut reaches it.

**Project Blue Book, three documents of twenty.** Its questionnaire codebook reads a header row
across instead of down (`X Variable y 0 1 In car 2 Outdoors …` becomes `Variable X`, `y 0`,
`1 In car`), and 191 characters of OCR debris move across a spine boundary from chapter 18 to
chapter 19. No text is gained or lost: 40,189 + 536 before, 39,998 + 727 after.

**The CDC graphic novel, one page, and this is a cost.** Page 23 stands two speech balloons side
by side, and each one's lines fall on the other's rows, so they are now dealt out line by line:

```
-<p>do you think they have f o o d at one o f th ese s a fe z o n es?</p>
+<p>do you think they</p><p>stay ruNBd fo r a l/st o f sa fb</p><p>have f o o d at one</p>
```

Its character count is unchanged, and that page's balloons were already read wrongly — the line
above joins two of them (`…thby Are reAdy. stay ruNBd fo r a l/st o f s`) — which is what #168's
split-balloon leftover and #18's panel order track. It is a different wrong reading of an
already-wrong page, against forty-three entries recovered in a gated contract book, and it is
recorded on #168 rather than left in this record alone.

A fifth condition was tried for it — that the cells step down at one leading, the third of a body
`TableRegionDetector.rowBlocks` allows — and it is wrong for this shape: a two-column list whose
entries wrap steps 11.25 points at one row and 22.5 at the next, so it refuses page 451 as well.

## Coverage

`aTableOfNamesIsReadRowByRowOnceItsMergedRowIsDivided` divides page 451's merged row as #270's
rule would and holds every name against its own office; with the guard disabled it fails with
`Colin Powell is missing, or stands before son Dale Watson`, and with
`Thomas Pickering Colin Powell` and `Condoleezza Rice Bill Richardson` in one block, which is the
defect this issue reports. It also holds the page as PDFKit actually hands it over, where the
merged row bridges the gutter and nothing changes.
`aStackOfCellsIsThreeUnnumberedRowsBesideAColumnOfProse` is the rule's five bounds one at a time:
three rows, two rows, both sides substantial, two stacks of cells, and a numbered grid.
