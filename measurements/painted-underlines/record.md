# Painted underlines

The 9/11 report underlines single words for emphasis by painting a filled path, not by setting an
underlined font, so nothing in the text layer records it and the emphasis was dropped from the
reflowed book (#235). This record measures what carries it back and what that costs.

Host: macOS 27.0 (26A428), Xcode 27.0 (27A266a), Apple M5 Max, 36 GB. Library source at `19cab5f`
plus this change. Measured 2026-09-20 with the release CLI at library defaults.

## PDFKit's own hit-testing supplies the range

Two selections over the line's box give the range without any glyph measurement: the one over the
rule's horizontal extent is the underlined text, and the one from the line's left edge to the
rule's start is what precedes it, whose length is the offset. `GraphicsReader` pads a region by
two points on each side, which is removed before asking.

| Rule | Selection over it | Selection before it | Range |
| --- | --- | ---: | --- |
| page 161, (117.6, 447.2, 20.9, 4) | `gain` | 19 characters | 19…23 |
| page 161, (227.4, 447.2, 18.8, 4) | `risk` | 46 characters | 46…50 |
| page 526, (240.0, 171.7, 13.3, 4) | `not` | 73 characters | 73…76 |

Position is what resolves the ambiguity: page 161's line reads
`considered "if the gain clearly outweighs the risk"—but at this time no such gains`, so a
substring search for `gain` cannot tell the emphasized word from the one inside `gains`.

## What the book gains

Eight underlines, where the book had none: `gain`, `risk`, `not`, `more`, `pattern`, `before` and
`urgently` twice. The three this issue named are among them; the other five it did not know about.

## What it costs, and the limit

The full corpus lane passes, 18 of 18, and **the reflowed text of all 18 books is
character-for-character identical** to the lane before the change. Nothing is lost, moved or
re-read; the only difference anywhere is the added markup.

Four guards keep the markup off things that are not emphasis, each one measured against a case
that needed it:

- the rule must sit inside the line's own box, not above it — Wallace's radical vincula sit a
  point or two over the line beneath them, and without this they read as its underline;
- it must start inside the measure, not at the line's left edge — an underlined section label is
  the line's own decoration, which is what `underlinedSectionsPDF` in the test suite fixes;
- it must span less than 90% of the measure, so a table's rule is not a word's emphasis;
- the run under it must hold at least two letters, and the line must read as a sentence.

**A known limit remains.** Wallace keeps four marks — `y`, `2`, `− y`, `1` — on inline
mathematics set inside prose lines, where a vinculum lies within the line's own box and the line
around it reads as a sentence. They are visually inert and cost no text, but they are not
emphasis. Separating an inline vinculum from an underline inside one line needs glyph extents
rather than line boxes, which is the same evidence #235's original sketch called for and which
nothing downstream of extraction has.

The IRS Chinese publication gains 33, almost all of them underlined `IRS.gov/…` addresses and
rule references, which that publication does underline.
