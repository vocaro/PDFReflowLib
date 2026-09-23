# Every measure a page takes of a sideways line (#276)

Tier: deterministic Apple PDF stack, isolated macOS arm64 release CLI.
Corpus: every cached source.
Build: `main` at `6dd9c70` with this change, Xcode 27.0, macOS 27.0 (Darwin 27.0.0).
Baseline: `6dd9c70` alone.

## The question

[#263](https://github.com/vocaro/PDFReflowLib/issues/263) reads a sideways line's *order* and its
*paragraph joins* along the line's own direction. [#276](https://github.com/vocaro/PDFReflowLib/issues/276)
lists everything else the page takes of such a line and still reads off its axis-aligned
rectangle — which, for a sideways line, makes its length a height and its thickness a width:

| rule | what it measures |
| --- | --- |
| `LayoutReconstructor.statedLeading` | the step between two lines of one column |
| `LayoutReconstructor.ordinaryLineHeight`, `ordinaryLineHeights`, `ordinaryLineGap` | a line's own depth, and the white under it |
| `LayoutReconstructor.hangingEntries` | the indent a wrap hangs at, and the measure its entry fills |
| `LayoutReconstructor.stacksUnderHeading` | whether two display lines stack |
| `LayoutReconstructor.markerColumn` | a marker's edge and the margin its column justifies to |
| `TableRegionDetector.rowBlocks`, `columnHeaders` | a page's printed rows and its column boundary |
| `BlockAssembler.continuesHeading`, `continuesBrokenItem`, the `.tableRow` piece test | a pair of lines, along the writing |

The issue also asks for a page that exercises each of them before the rule is moved, "because a
rotation about the page's origin is only sound where every rectangle a rule compares carries the
same turn, and these rules compare a line against a *column* or a *page* measure rather than
against one other line."

## The rule

`LayoutReconstructor.ownFrame(of:)` answers exactly that. A **group** measure is taken in the
frame the group's own writing runs in only where `QuarterTurn.shared` says every line of the group
was set at one turn that is not upright; a group holding an upright line, or lines at two turns,
reads on the page, as before. A **pair** measure asks the narrower question the pair allows —
`above.turn == line.turn` — and reads `uprightRect` when it holds, which for two upright lines is
the page's own rectangle, to the bit.

The two geometric predicates the rules are written through, `overlapsHorizontally` and
`sharesRow`, move with them for the same reason: a sideways line's rectangle is as tall as the
line is long, so on the page every sideways line of a caption shares a row with every other.

`rowBlocks` and `columnHeaders` read in the turned frame and hand back **the page's own
rectangles**, because that is what a crop is tested against; they do it by giving each line its
own upright rectangle and reading it as upright from there, and mapping the result back.

## What moved

**Nothing.** Every one of the twenty-two cached sources is byte-identical, every document of every
one, which is what #276 predicts: "None of this is reachable on the captured corpus." The only
sideways writing in it is the CDC graphic novel's pages 16 and 17, and page 17's caption is three
lines — under the four pairs `statedLeading` needs and the three entries `hangingEntries` needs —
carries no marker, and stands in no table.

That is the whole safety argument for a change of this reach: it is confined, by construction and
by measurement, to pages the corpus does not have.

## What exercises it

Five tests in `Tests/PDFReflowLibTests/SidewaysReadingOrderTests.swift`, each built on one claim:
**a page turned is read the way the page is.** `turnedClockwise` takes a layout set upright and
turns every rectangle a quarter clockwise about the page's origin, carries it back onto the page,
and gives each line that turn — so `uprightRect` returns the rectangle the upright page had, moved
by one page width in x, and every rule here compares differences.

Each test asserts the turned page reads exactly as the upright one, and each carries its own
control: the same rectangles with the turn stripped, which is the reading before this change.

| test | what it pins |
| --- | --- |
| `aPageSetSidewaysStatesWhatTheSamePageSetUprightStates` | `statedLeading` (14 points either way), `ordinaryLineHeights`, `hangingEntries` (three entries either way), `stacksUnderHeading`, `markerColumn`'s three answers |
| `theSameRectanglesReadAsUprightStateNothing` | the control: read as upright, that page states no leading, hangs nothing, stacks nothing |
| `aTableSetSidewaysIsReadAsATable` | `rowBlocks` finds the same run, and the regions it returns lie on the page |
| `columnHeadersAreReadAcrossTheWriting` | `columnHeaders` finds the same header band, on the page's own rectangle |
| `theAssemblerReadsASidewaysPageAsItReadsAnUprightOne` | `continuesHeading` and the `.tableRow` piece test, each against its upright control |

Every assertion was checked against the code without this change: `statedLeading`,
`ordinaryLineHeights`, `hangingEntries`, `stacksUnderHeading`, `markerColumn` (all three),
`rowBlocks`, `columnHeaders`, `continuesHeading` and the `.tableRow` piece all fail there, which is
what a test of this shape has to do to be worth anything.

## What is not claimed

`continuesBrokenItem`'s frame moves with the others and is **not** separately pinned. The shapes
that would exercise it are reached by #280's block-level carry, which reads no geometry at all, so
a test of it through the assembler passes either way; it is moved for consistency with the rules
beside it rather than on evidence of its own.

The pages that exercise this are built in the tests, not captured from a book. #276 asked for a
captured one — a landscape table, a spine title, a sideways column of entries — and the corpus
still has none; [#44](https://github.com/vocaro/PDFReflowLib/issues/44) is where that is tracked.
What is measured here is narrower and, for a change that moves nothing in twenty-two books, is
what there is: each rule reads the frame the writing runs in, each is pinned by a page turned
against the same page upright, and the reading of every book the corpus holds is unchanged to the
byte.
