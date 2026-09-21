# The spacing evidence a line already had, applied

Measured under [#120](https://github.com/vocaro/PDFReflowLib/issues/120) and
[#139](https://github.com/vocaro/PDFReflowLib/issues/139), baseline `840ec23`, 2026-09-20,
macOS 27 / Xcode 27, arm64, release CLI at library defaults.

Both issues describe the same family: the source separates two tokens, the reader's rules have
already admitted the boundary, and the space does not reach the book. `#225`'s port of partial-line
ownership (`NativeSpacingOwnership`) fixed most of it — the FAA chart row `1,6852,599`, Wallace's
`toboth sides` on four pages, Replay Clocks' `𝑒must`, Wallace's `6)when` math punctuation, and
nine of the ten 9/11 appendix `(a.k.a.` lines all read correctly on this baseline. What remained
is measured here.

## Three mechanisms, and what each cost

**A show the reader cannot decode discarded the whole line.** `line(of:)` returned nothing at all
for a line holding one show whose text it could not read, so every boundary the rules had already
computed went with it. Wallace page 120 sets `5− 2x 11 Subtract 5from both sides`; one radical
made the line undecodable and the font change between `5` and `from`, which the rules had
admitted, never reached the text. The show is now a hole in the source's reading: the walk
resynchronizes across it, and nothing is read across the hole, because the show after it has no
predecessor to compute a boundary against.

**An anchor of eight characters resynchronized into the wrong half of a row.** The 9/11 appendix
draws `Abu Bara al Yemeni (a.k.a.Abu al Bara al Ta’izi,…` as one row, which PDFKit splits into two
lines. Walking the second line against the row, the correct alignment skips 19 source characters
to `(a.k.a.A`; `Bara al ` matches after 16, in the row's first half, and the walk resumed there
and applied nothing. The two readings diverge at the ninth character, so the anchor is now twelve.

**A number set against a word closes at a tighter gap than the font-change rule wanted.** Wallace
sets `8cent stamps`, `3times as many` and `3places` with a font change and a gap of 0.12 to 0.13
em, where the rule asks 0.15. The narrower gap is admitted only where the run after the number
opens with an English word of three letters or more, which is what keeps it off the same book's
algebra: `30qpr` and `5q` open with no word at all and stay as they are.

## What changed

| Book | Digit-then-word fusions | `(a.k.a.` fused |
| --- | ---: | ---: |
| wallace-algebra-2010 | 15 → **6** | — |
| gpo-911-2004 | 2 → 2 | 1 → **0** |
| every other corpus book | unchanged | unchanged |

One of Wallace's six is `30qpr`, which is algebra and correctly closed. Wallace gains 44
characters — the spaces themselves — and no book loses any; no other book's text changes at all,
which is the check that matters against [#119](https://github.com/vocaro/PDFReflowLib/issues/119)'s
constraint that a threshold must not invent spaces in mathematics.

The 9/11 report's two remaining digit-then-word tokens are `120city` and `60minutes`, which are
a table's own cells rather than fused prose.

The corpus lane passes 16 of 18 covered, with no content-contract and no structural failures.

## What is left

Five Wallace lines, all digit-then-word, where `owningShows` refuses the line outright because its
superscripts put some shows' origins on other baselines — `Convert 8cubic feet`, `Move 3and b`,
`6and− 1`, `1· 6and 2· 3`, `scored 6for every 7`. That is a fourth mechanism, filed as
[#258](https://github.com/vocaro/PDFReflowLib/issues/258).

# The fourth mechanism: a line that holds another row's shows

Measured under [#258](https://github.com/vocaro/PDFReflowLib/issues/258), baseline `ec7e943`,
2026-09-20, macOS 27 / Xcode 27, arm64, release CLI at library defaults.

## What the refusal actually was

`anchoredShows` refuses a line when any show whose origin its rectangle holds lies in a second
line's rectangle too. The filed issue read that as a superscript's origin falling into a
*neighbouring* line's rectangle. A probe of `owningShows` against the book's own pages shows it is
the reverse: the rectangle that grows is the line's own. PDFKit's rectangle for a line carrying an
exponent, a raised index or a stacked fraction spans everything the line carries, so it swallows
the rectangles of the rows drawn inside it, and those rows' shows are then held by two rectangles.

Wallace page 281 sets `Convert 8cubic feet to yd3 Write 8ft3 as fraction, put it over 1` as one
PDFKit line whose rectangle is x[88.20, 393.72] y[77.87, 147.08] — 69 points tall over a 12-point
baseline, because the fraction rows `8ft3 / 1` and `To clear ft3, put them in denominator` are
drawn inside it. Twelve shows on the line's own baseline at y 136.78 spell its text exactly,
including the `8|cubic` font change at a gap of 1.94 points over an 11.96-point size, 0.16 em,
which the font-change rule already admits at 0.15. Eight further shows, at y 88.90 to 113.26,
belong to the rows inside and are held by lines 46 and 47 as well. All twenty were discarded.

Page 186 shows the adjacent-line form the issue described: the exponent of `b0` sits at y 711.10,
inside both its own line's rectangle (y[703.78, 717.08]) and the rectangle of the prose line above
it, so that one show refused both lines.

## The rule, and why it is the conservative one

A show two rectangles hold is now a hole in each line's reading rather than the end of it — the
same hole [#120](https://github.com/vocaro/PDFReflowLib/issues/120) already makes of a show the
reader cannot decode. The segmented walk resynchronizes across it and the show after it has no
predecessor, so no boundary is computed against a character the line may not have drawn. A line
every rectangle shares holds only holes and supplies nothing, exactly as before.

Nothing else moved. No threshold changed, no rule was added, and a boundary is still applied only
where both of its characters matched PDFKit's own reading inside one agreeing segment.

## What changed, measured over every cached source

Every line of all 24 cached sources was read with the baseline reader and with this one, and the
two sets of repaired lines compared line by line.

| Book | Lines the reader repairs | Spaces gained |
| --- | ---: | ---: |
| wallace-algebra-2010 | 295 → **324** | 31 |
| faa-phak-8083-25c | 8 → **9** | 1 |
| every other cached source | unchanged | 0 |

No line the baseline repaired is repaired differently or left alone. The FAA gain is the chart row
`Spc Range 0.165 0.1780.199`, whose rectangle the row beneath reaches into; its page is preserved
as an image, so that row's text does not reach the EPUB and the gain is in extraction alone.

End to end, the whole corpus was converted twice with the same CLI built from the two readers, and
the XHTML of all 150 documents compared character for character. Four lines differ, all in Wallace:

```
chapter-6.xhtml   Move 3and b to denominator…        → Move 3 and b to denominator…
chapter-8.xhtml   Home team scored 6for every 7…     → Home team scored 6 for every 7…
chapter-9.xhtml   Convert 8cubic feet to yd3…        → Convert 8 cubic feet to yd3…
chapter-12.xhtml  , put over 1so we have proportion  → , put over 1 so we have proportion
```

The book gains four characters, the spaces themselves. Every other book's text is identical to the
baseline's, which is the check that matters against #119's constraint that a threshold must not
invent spaces in mathematics — and the book that constraint is about gains only spaces its own
prose asked for. The other twenty-five newly repaired Wallace lines reach the EPUB in neither
reading: each sits inside a worked example the converter preserves as an image.

## The gates

492 Swift tests on macOS, 227 Python tests, eight fixture conversions, 16 policy conversions and
24 rejection/cleanup cases. The corpus lane passes all 18 of its cases with 558 content checks over
126 reviewed pages, EPUBCheck and no structural failures.

Four Swift tests carry `#258`: the hole rule over synthetic geometry, beside the predecessor's
refusal of the same geometry; Wallace page 281's tall rectangle; Wallace page 186's shared
exponent, where the two lines that share it keep PDFKit's own reading; and, as a positive control
from the other producer, the FAA page 459 chart, which gains its one column gap and no other line.
The fixtures are `algebra-{186,281}` and `faa-459`, captured with the baseline reader.

## What is left after this

Two of the five lines #258 listed were never this defect. `owningShows` returns evidence for both
on the baseline; each fails later, in `segmentedInsertions`, and for a different reason.

`6and− 1, split the middle term` on page 223 is the tail of a row PDFKit split at a wide gap: line
17 holds the first digit of the show `66` and line 18 holds the second. The source therefore reads
`66and−1,…` against PDFKit's `6and− 1,…`, and the walk, which takes offset 0 on faith where every
later alignment must match twelve characters, pairs the show's first digit with the line's second.
It disagrees at the next character, resynchronizes to source offset 2 — the boundary itself — and
drops it as a boundary against a disagreeing region's edge. Aligned one character over, the same
line yields the boundary.

`1· 6and 2· 3` on page 224 holds two undecodable `·` shows. Its source reads `16and23`: seven
characters against an anchor of twelve, so nothing can resynchronize across the first hole and the
walk ends having applied nothing.

Both are filed as [#260](https://github.com/vocaro/PDFReflowLib/issues/260). Both reach the EPUB,
and they are what the segmented walk still refuses on lines it does own; every line #258's
ownership refusal held back now reads with the space its own evidence held.
