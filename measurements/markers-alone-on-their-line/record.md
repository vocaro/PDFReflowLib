# A list marker the extractor left alone on its line

The four items of [#172](https://github.com/vocaro/PDFReflowLib/issues/172), measured on `main`.

The record the issue cites, `measurements/detached-labels/record.md`, was written on the abandoned
coordination branch and is not in this tree; it is readable as
`git show 2e18b31:measurements/detached-labels/record.md`. **None of its code is on `main`**, which
is the first thing this measurement established and the thing that decides items 1 and 2: `#14`'s
`splitDetachedShows`, `detachedShowGap` and `detachedShowPageShare` appear nowhere in this tree, so
no line PDFKit joins across a page is ever taken apart here
([decision 0005](../../doc/decisions/0005-abandoned-coordination-branch.md), and the last comment on
[#14](https://github.com/vocaro/PDFReflowLib/issues/14#issuecomment-5750338431), which records the
same finding from the other side). Every number below was measured here, on this tree.

Host: macOS 27.0 (26A428), Xcode 27.0 (27A266a), arm64, shared with other agents' conversions.
Library source at `fbc5e1f` (baseline) and at `fbc5e1f` plus this change (candidate). Release CLIs,
library defaults, `--package-identifier urn:uuid:00000000-0000-0000-0000-000000000172
--modification-date 2026-01-01T00:00:00Z` for the standalone conversions.

| Binary | SHA-256 |
| --- | --- |
| baseline, `swift build -c release` at `fbc5e1f` | `801f0de432e7546c6a118925bef6b0b66ca0aed4133f8843f927be93232ed374` |
| candidate, this change | `3cb732c2c570a132202ccd5c7952081fbef4e88f98fe1c973d7229d0e061023f` |

Both binaries converted every case of `tools/run_corpus_regressions.py --jobs 4` with EPUBCheck;
each case's `result.json` was opened and its `runPassed` read individually, never through a pipe.
The per-book comparison reads each EPUB's spine in order, splits it into top-level blocks and
attributes each to the source page whose marker precedes it, then diffs the two runs.
`tools/compare_conversion_runs.py` was not used: it refuses a pair without a capability-probe
receipt, and these lanes were run without one.

A survey tool behind the numbers below dumped, for every page of the 20 cached documents, every
line `NativeTextReader.lines` returns with its rectangle and size, and every text show
`NativeSpacingReader.read` returns with its origin, size and text. It is a single Swift file
compiled against `python3 tools/pdfreflow_tools/swift_sources.py capture-layout-fixture.swift`'s
library list, and it was not committed (decision 0006); it reads nothing the two committed capture
probes do not already read.

## Item 3: `9)` and `10)` are `<p>` where other exercise markers are `<pre>`

### The mechanism

`LayoutReconstructor.isMarked` and `isList` both require **whitespace after the point or bracket**,
because the item's own text follows it there:

```swift
text.range(of: "^(?:[0-9]+|[A-Za-z])[.)]\\s", options: .regularExpression) != nil
```

PDFKit ends a line wherever the page leaves a gap, so an item whose marker the page hangs a little
further out comes back as two lines and the first matches neither test. It is then `.prose`, the
rest of its row joins it as a paragraph by the ordinary `continuesRow` rule, and the item is a `<p>`
in a page of `<pre>` items.

The issue names Wallace page 101's `9)` and `10)`. Those two are one line here — `9) 10)`, 18.62 ems
and 37.4% of the page between the two show origins — because the split that would separate them is
not on `main`. **The same defect is live on the same page**, in two exercises the issue does not
name. PDFKit returns page 101 as:

```
sz=11.96 x= 84.96 y=465.98 w= 16.32  '17)'
sz=11.96 x=105.24 y=465.98 w=116.76  '(− 16,− 14), (11,− 14)'
sz=11.96 x=307.56 y=344.54 w= 16.32  '28)'
sz=11.96 x=327.84 y=344.54 w=105.00  '(− 18,− 5), (14,− 3)'
```

against `11) (− 2, 10), (− 2,− 15)`, `16) (− 3, 6), (− 20, 13)` and every other exercise on the page
as one line each. 3.96 and 3.97 points separate each marker from its coordinates — a third of the
0.75 of a body a column's gutter needs. Rendered at 100 DPI, the page sets exercises 11 to 30 as a
two-column numbered list, one printed line to an item, and 17 and 28 are set exactly as 16 and 27
are; nothing in the source distinguishes them. The baseline emits

```
<pre>16) (− 3, 6), (− 20, 13)</pre>
<p>17) (− 16,− 14), (11,− 14)</p>
<pre>18) (13, 15), (2, 10)</pre>
```

### The rule

A line whose **whole text** is a number or a single letter with a point or a bracket is a marker,
where the page says so. It carries no text of its own to vouch for it and a number with a point is
also how a citation ends, so the page must state it twice over:

- **its row is a row of items, not a row of cells.** Everything the page set to its right on that
  row is either within the gutter — the item's own text — or a marker of the same list again, the
  next column of a grid of items. Wallace sets exercises 17 and 18 on one row, four points and a
  column apart. A piece to the *left* within that gutter means the extractor cut this line out of
  the middle of a row, which is #203's rule unchanged;
- **the page states the list.** Another line of its size, on its own left edge, opens an item of the
  same list — numbered or lettered the same way, closed with the same point or bracket — and carries
  that item's own text after it.

The **rest of an item's own printed row then joins that item**, as two pieces of one row are one
block everywhere else (#57, #137): `17)` and its coordinates are one preformatted item again.

That second half is also [#265](https://github.com/vocaro/PDFReflowLib/issues/265), which #203 left
behind. Both the `.listItem` and the `.markedLine` branch of `BlockAssembler.append` appended a
preformatted block and returned without leaving an open paragraph or setting `previous`, so the
piece that followed started a paragraph of its own. Wallace's converted book holds **243 paragraphs
opening with a minus** on the baseline and **6** on the candidate; the six stand beside an image
crop rather than beside the rest of their row, which is not the shape #265 describes. The 56
preformatted blocks opening with a minus — #203's own class, the pieces that must *not* open an
item — are 56 in both runs.

Both halves are needed, and the survey says by how much. Over the 20 documents, 10,153 lines are a
marker and nothing else. Taking them all as markers would move NOAA's 9,492 hanging reference
numbers and the 9/11 report's and Warren's citation years — the `<p>`-to-`<pre>` direction
[#146](https://github.com/vocaro/PDFReflowLib/issues/146) was closed for. The two conditions above
cut that to 808 lines, of which 686 are NOAA's (see below) and 74 are Wallace's.

### Why the 9/11 report's `2001.` is not a marker

The report leaves a citation's year on a line of its own in its notes:

```
x= 39.66 y=500.80 maxX=351.64  'Mar. 15, 2004; Metropolitan Washington Airports Authority videotape, Dulles main'
x= 39.66 y=492.80 maxX= 55.21  '2001.'
x= 51.66 y=484.80 maxX=351.66  '12. See TSA report, “Selectee Status of September 11th Hijackers,” undated; …'
```

The notes are set with a first-line indent: each note's number stands at 51.66 and its wrapped lines
at 39.66. `2001.` is a wrapped line, and the note numbers that could vouch for it are twelve points
— 1.7 bodies — off its left edge, so nothing on that edge does. It stays the prose it is.

### What moved across the corpus

Per book, over both complete lanes:

| Book | Changed source pages | Blocks on those pages | `<pre>` blocks on them |
| --- | --- | --- | --- |
| *Beginning and Intermediate Algebra* | 35 | 1,755 → 1,508 | 1,017 → 1,047 |
| *Project Blue Book Special Report No. 14* | 18 | 2,569 → 2,544 | 120 → 120 |
| *The 9/11 Commission Report* | 3 | 53 → 53 | 25 → 28 |
| IRS Publication 596 (Chinese) | 2 | 117 → 112 | 8 → 15 |
| The other 14 cases | 0 | — | — |

No page of any book loses or gains a word except the three named below. Wallace's 247 fewer blocks
are its exercises coming back together: the book breaks a row after a raised exponent, so
`73) (8n2` and `− 3n)− (5+ 4n2)` were two blocks and are now one item,

```
<pre>73) (8n2 − 3n)− (5+ 4n2)</pre>
```

on pages 21, 26, 182, 187, 194, 195, 210 and seventeen more. Page 101's `17)` and `28)` are items,
and page 122's `7)` to `12)`, which head graphs and carry no text of their own, are items instead of
paragraphs. The Blue Book's 25 fewer blocks are the pieces of its OCR'd statistical rows rejoining
the row they were cut from.

Three pages break a word where the baseline did not, all of them the same thing and all of them the
library's documented "no list model": an item that **wraps** is one preformatted block per line.

- 9/11 page 365 sets four numbered findings. Items 1 to 3 already read
  `<pre>1. The CTC did not analyze how an aircraft, hijacked or explosives-</pre>` followed by
  `<p>laden, might be used as a weapon. …</p>`; item 4's marker was a line of its own, so the item
  read as two paragraphs with the word whole. It now reads exactly as items 1 to 3 do, with
  `ana-` / `lyzed` broken at the block boundary as `explosives-` / `laden` already is.
- IRS Publication 596 pages 13 and 19 do the same for items `b.`, `c.` and `1.` to `6.`, splitting
  `美元` once on each page at the boundary.

That break is a defect of the library's list handling, not of this rule — it is what every other
wrapped numbered item in the corpus already does — and it is filed separately.

*The Warren Commission Report* and NOAA's Fifth National Climate Assessment are not in the lane
(`corpus/regressions.json`'s `excludedFullConversions`). Warren was converted standalone with both
binaries for this record; the result is below. NOAA's full conversion exceeds the 512 MiB entry
budget at library defaults and was not converted: the survey predicts 686 hanging reference numbers
on 73 pages moving from a `<p>` to a `<pre>`, which is the same move the lane reviewed on the 9/11
report and IRS 596, on entries whose markers PDFKit did not split and which are `<pre>` already.

## Item 1: `Vegetables` and `& Fruits` stay two paragraphs — not reproducible on `main`

The issue's reading of the mechanism is right, and the measurement confirms both halves of it. DGA
page 1's labels are set against the two sides of the food pyramid, and PDFKit returns them as:

```
sz=17.98 x= 39.36 y=464.40 w=110.40 maxX=149.76  'Protein, Dairy'
sz=17.98 x= 39.36 y=446.40 w=532.22 maxX=571.58  '& Healthy Fats & Fruits'
sz=17.98 x=479.19 y=464.40 w= 92.43 maxX=571.62  'Vegetables'
```

The page's body is 17.98. `Vegetables` and the right-hand label share a right edge to within 0.04
points and stand 28.14 points — 1.565 bodies — apart on the left, just past the 1.5 bodies the
column test allows, so a shared left edge cannot join them and nothing else tries.

**But `& Fruits` is not a line on `main`.** It is the tail of `& Healthy Fats & Fruits`, one PDFKit
line 532 points wide, and the content stream puts its show origin at x=507.33 against the left
label's at 39.36. Splitting that line is `#14`'s `splitDetachedShows`, which is not in this tree. So
on `main` the left label does not join either — the page reads `Protein, Dairy`, `Vegetables`,
`& Healthy Fats & Fruits` — and the two-paragraph split the issue describes cannot be reproduced.

A ranged-right paragraph join was written and measured against the survey before being abandoned. A
rule that joins two stacked same-size lines at ordinary leading whose right edges agree within a
quarter of a body, whose left edges differ by more than the 1.5 bodies the column test allows, and
neither of which stands on a left edge another line of its size shares, takes **228 pairs** across
the corpus: 153 in the Arabic USCIS guide, where right-ranged wraps are what the writing system
sets and the joins look correct; 31 in Wallace, where they are the steps of a centered derivation
and the joins are wrong (`− 6+ 60(− 2) Multiply` with `− 6− 120 Subtract`); about 40 in Warren's
OCR'd pages; and the one DGA pair. Unlike #14's own threshold, where every column or cell gap
reached at most 11.5 ems and content set against opposite sides of a page began at 17.8, this
population has no empty band to put a threshold in, and 227 of the 228 pairs are not the label the
issue is about. **Nothing was changed for this item**, and the ranged-right rule is not in the
candidate binary.

## Item 2: the cover reads column-major — not a defect, because it does not happen

`realfood.gov` and `2025–2030` are one PDFKit line on `main`:

```
sz=11.52 x= 38.45 y=35.75 w=535.15  'realfood.gov 2025–2030'
```

with show origins at x=38.45 and x=513.55. Nothing splits it, so neither piece is ever placed in a
cover column and the page reads row by row, top to bottom:

```
<h2>Dietary</h2>
<h2>Guidelines For Americans</h2>
<p>Protein, Dairy</p>
<p>Vegetables</p>
<p>&amp; Healthy Fats &amp; Fruits</p>
<p>Whole Grains</p>
<p>realfood.gov 2025–2030</p>
<figure><img …/><figcaption>Original page 1</figcaption></figure>
```

**Verdict: not a defect.** It is not a defect today, because the reading the issue describes does
not occur; and it would not be one if `#14`'s split were ported, because on a cover with no running
text neither order is wrong, the text is complete either way, and each label would be with its own
side of the art. Nothing should be tracked for it. If column detection is ever built for a page that
does have running text, this cover is a case to look at then, not a reason to build it.

## Item 4: the FAA's beacon table and Wallace's columns belong to the table readers

Confirmed, and measured here rather than taken on trust. PDFKit returns the NDB table on FAA page
416 as one line per row, cells and all:

```
x=321.00 y=381.78 w=216.75  'Class (Watts) (Miles)'
x=321.00 y=369.57 w=237.00  'Compass Locator Under 25 15'
x=321.00 y=357.07 w=236.98  'MH Under 50 2 5'
x=321.00 y=344.57 w=145.50  'H 50–1999'
x=542.55 y=344.57 w= 15.45  '*50'            (7-point, a line of its own)
x=321.00 y=332.07 w=236.98  'HH 2000 or more 75'
```

The widest gap between two show origins inside a row is **10.55 ems and 17.8% of the page**
(`Class` to the wattage column on the header row; 8.52 to 9.83 ems on the data rows) — under both
halves of the threshold #14 measured, and in any case that rule is not on `main`. Wallace's answer
and graph columns are the same shape at 9.6 and 9.9 ems on the branch's own survey. Nothing in this
change touches any of them: the rule above refuses exactly this geometry, because a piece standing a
column away on a marker's row is what makes its row a row of cells. These are
[#210](https://github.com/vocaro/PDFReflowLib/issues/210)'s, and this issue does not reach for them.

## Tests and contracts

`Tests/PDFReflowLibTests/LayoutEvidenceTests.swift`, two tests carrying `.bug()` traits for #172,
on hand-made lines with no page fixture:

- `aMarkerAloneOnItsLineIsAMarkerWhereThePageSaysSo`: the reproducer, Wallace page 101's geometry,
  and the page evidence taken away one piece at a time — no item of its list on its left edge (the
  9/11 report's shape), an item of another list (lettered, or numbered with a point), a piece a
  column away on its row (NOAA's shape), a piece to its left within the gutter (#203's shape) — plus
  `1.5`, `A.M. flight` and `17) ` against the marker reader itself.
- `theRestOfAnItemsRowJoinsTheItem`: the item and its row's next piece are one preformatted block;
  a bulleted item takes its row the same way; a piece a gutter away, a line on another row, and a
  second prose line beneath the item each stay their own block.

Both fail on `fbc5e1f`'s behavior with four recorded issues between them.

`corpus/regressions.json` gains Wallace page 101: `17) (− 16,− 14), (11,− 14)` and
`28) (− 18,− 5), (14,− 3)` must each be one preformatted block, beside `16)` and `27)` as the
controls that already were, with the four in reading order after
`Find the slope of the line through each pair of points.` The two new expectations fail on the
baseline evaluation with

```
Page 101: missing preformatted block '17) (− 16,− 14), (11,− 14)'
Page 101: missing preformatted block '28) (− 18,− 5), (14,− 3)'
```

`preformatted` is a new contract check type, the mirror of `paragraphs`: a phrase inside one `<pre>`
block, which a paragraph, two adjacent items or the page's running text cannot satisfy. Its negative
controls are in `tools/test_corpus_content.py`.
