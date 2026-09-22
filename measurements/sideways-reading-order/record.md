# A sideways line's reading order and its paragraph joins

Measured under [#263](https://github.com/vocaro/PDFReflowLib/issues/263), baseline `a1bbea8`,
2026-09-22, macOS 27.0 (26A428), Xcode 27.0 (27A266a), Apple M5 Max, 36 GB, release CLI at library
defaults. It carries on from [#130](https://github.com/vocaro/PDFReflowLib/issues/130)
(`measurements/sideways-and-centered-lines/record.md`), which took the *size* of a sideways line
off Vision's quadrilateral and left the *order* to this issue.

## What the page says and what the library read

CDC *Preparedness 101: Zombie Pandemic*, physical page 17 (392.15 x 613.2 points), is three
sideways lines and nothing else. The geometry below is
`tools/probes/capture-ocr-layout-fixture.swift` on `a1bbea8`, in the page's own points:

| Line | x | y | Box | Size | `shouldWrapToNextLine` |
| --- | --- | --- | --- | ---: | --- |
| `SEVERAL DAYS LATER AT THE CENTERS FOR` | 355.11…364.05 | 24.27…249.11 | 8.94 x 224.84 | 8.94 | false |
| `DISEASE CONTROL AND PREVENTION IN` | 342.33…352.55 | 47.27…249.12 | 10.22 x 201.85 | 10.22 | true |
| `ATLANTA, GEORGIA...` | 332.11…341.05 | 143.08…249.11 | 8.94 x 106.03 | 8.94 | false |

Every quadrilateral runs from its top-left corner at y 0.4063 to its top-right at the foot of the
page, so the writing runs *down* and the tops of the letters face right: the page turned each line
a quarter clockwise. All three reach the same top edge, to a hundredth of a point, and stand 1.4
and 2.5 points apart across the page.

Read as though the writing ran along those rectangles, the three lines are one column of the page,
ordered by their midpoints: 196.10, 148.20, 136.69. The shortest line is the topmost, so it came
first; and the other two overlap by 106 points, more than half the shorter one's height, so
`sharesRow` called them one printed row and the 2.5 points between them is inside the three
quarters of a body `continuesRow` allows, so they were joined — in the order the sort had already
reversed. On `a1bbea8` the page emitted

```
<p>ATLANTA, GEORGIA...</p>
<p>DISEASE CONTROL AND PREVENTION IN SEVERAL DAYS LATER AT THE CENTERS FOR</p>
```

## The mechanism

A recognized line now carries the quarter turn the page set it at (`TextLine.turn`), read off the
same foot-to-head offset its type size is: the offset points the way the tops of the letters face,
so right is clockwise and the writing runs down the page, left is counterclockwise and it runs up,
and anything within half a right angle of upright — including a line read upside down — is
upright, exactly as #130's size boundary is. A natively extracted line states no direction and is
upright, so no page of native text carries a turn at all.

`QuarterTurn.upright(_:)` takes a rectangle into the frame that turn stands upright in, by rotating
about the page's origin: `(x, y)` becomes `(-y, x)` for a clockwise line and `(y, -x)` for a
counterclockwise one. Two things read that frame:

- **`LayoutReconstructor.ordered`.** Where a group's every element is a line and they all agree on
  one turn that is not upright, the group's rectangles are turned and the same cuts and the same
  row-major sort are made in the turned frame; the elements come back in that order, unchanged.
  The cuts have already isolated the group by the time this is asked, so the turn applies to every
  rectangle being compared, and a rotation about a fixed point changes no gap, no shared edge and
  no overlap — only the axis each is measured on. A group holding an upright line, a picture, a
  table, or two opposite turns is read on the page as before.
- **`BlockAssembler`.** `continuesParagraph`, `continuesRow`, `centered`, `onStatedLeading`,
  `startEdge` and the first-line-indent step compare two lines in the frame their own writing runs
  in. For an upright line that frame is the page and the rectangle is returned to the bit, so
  every one of these measures is identical on a page of upright writing.

Turned, the caption's three lines stand on one left edge at x -249.11, -249.12 and -249.11, in
lengths 224.84, 201.85 and 106.03, each 1.3 and 1.4 points below the one before it. None of them
shares a row with another. The page now emits

```
<p>SEVERAL DAYS LATER AT THE CENTERS FOR</p>
<p>DISEASE CONTROL AND PREVENTION IN ATLANTA, GEORGIA...</p>
```

which is the caption in the order the page letters it, joined where the reading itself says the
line wraps.

## What is not fixed

The caption is two paragraphs rather than one because Vision states
`shouldWrapToNextLine == false` for `SEVERAL DAYS LATER AT THE CENTERS FOR`. That flag governs
every paragraph join in the library, and #130 already refused to override it for the weaker
geometry of a centered stack (CDC page 23's broadcast balloon is the same refusal). Overriding it
here would give a turned column a licence an upright one does not have.

Every *other* measure the page takes of a sideways line still reads its axis-aligned rectangle:
the page's stated leading, the entries it hangs, a marker's column, the printed rows a table
region detector finds, and the heading stack. None of them is reachable on the captured corpus —
page 17's three lines are under the four pairs `statedLeading` needs and the three entries
`hangingEntries` needs, carry no marker and stand in no table — so this is a latent reading rather
than a measured defect, and it is filed as
[#276](https://github.com/vocaro/PDFReflowLib/issues/276) with the list of rules and why each one
needs a captured page before it moves.

## What the change costs, across the whole corpus

Blocks are paragraphs, headings, preformatted blocks, list items and figure captions, counted in
spine order over every XHTML document of the book. Both lanes ran
`tools/run_corpus_regressions.py --jobs 4` with EPUBCheck 5.3.0; all 18 cases report
`runPassed: true` in both, every `content-assessment.json` reports `passed: true` with no errors,
and the two lanes make the same 611 content checks over the same review pages.

Seventeen of the eighteen books are identical block for block and character for character. One
moves:

| Book | Blocks | What moved |
| --- | ---: | --- |
| cdc-zombie-pandemic-2011 | 653 → 653 | page 17's caption is read in its own order and joined along it; page 16's five logo fragments reorder |
| the other 17 | unchanged | identical, block for block |

CDC page 16 is the publisher's logo, lettered sideways and read as `УďпG` / `JCDC` / `CERTERG` /
`FOE` / `CONTROL ARD PREVE`. All five fragments are clockwise, so the page is turned and they come
out in a different order; none of them wraps, so no block joins or splits, and the page's block
count is what it was. Neither order is the page; the page is a logo, and #130's record made the
same observation about the size change that moved it before.

The whole corpus diff of the change is those two pages:

```
 <p> УďпG
+<p> JCDC
 <p> CERTERG
+<p> FOE
 <p> CONTROL ARD PREVE
-<p> JCDC
-<p> FOE
 <figcaption> Original page 16
-<p> ATLANTA, GEORGIA...
-<p> DISEASE CONTROL AND PREVENTION IN SEVERAL DAYS LATER AT THE CENTERS FOR
+<p> SEVERAL DAYS LATER AT THE CENTERS FOR
+<p> DISEASE CONTROL AND PREVENTION IN ATLANTA, GEORGIA...
```

## Reproducing

```sh
swift build -c release
python3 tools/run_corpus_regressions.py \
  --converter "$(swift build -c release --show-bin-path)/pdf-reflow" \
  --epubcheck "$(command -v epubcheck)" --output /tmp/corpus-263 --jobs 4
```

The per-page geometry was read with `tools/probes/capture-ocr-layout-fixture.swift` (CDC pages 16
and 17), built from `tools/pdfreflow_tools/swift_sources.py`. Vision's compiled models decide what
any one page reads (#173), so the recognized geometry is evidence about this machine; the
library's own tests carry these measurements on hand-made lines.
