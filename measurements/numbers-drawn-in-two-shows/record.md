# One number the page draws in two shows

Measured under [#274](https://github.com/vocaro/PDFReflowLib/issues/274), baseline `86193ac`,
2026-09-22, macOS 27 / Xcode 27, arm64, release CLI at library defaults.

Page 416 of `faa-phak-8083-25c` prints the NDB service-volume table. Its `MH` row reached the book
as `MH Under 50 2 5` where the page prints `MH  Under 50  25`. Split out of
[#210](https://github.com/vocaro/PDFReflowLib/issues/210), whose owner comment classified it as an
extraction defect in the native readers rather than a table one.

## What the page draws

The row, from the page's own content stream:

```
BT 0.402 Tw 10 0 0 10 321 359.5664 Tm (MH )Tj ET
…
BT 10 0 0 10 501 359.5664 Tm (       2)Tj 10 0 0 10 321 359.5664 Tm 23.198 0 Td (5)Tj ET
```

`NativeSpacingReader.read` measures the two shows of the Distance cell at 10-point type:

| x | end | decoded |
| ---: | ---: | --- |
| 501.00 | 551.64 | `       2` |
| 552.98 | 557.98 | `5` |

The gap from the end of the first show's glyph advances to the origin of the second is
**1.34 points, 0.134 em**, and PDFKit reads a space there.

The row sets `Tw 0.402` and no `Tc`, so the gap is not the page's character spacing, and it is not
a `TJ` adjustment either — the two shows are separate text objects. What the page *does* state is
what it means by a space. Its font gives code 32 a width of **0.25 em**, the row widens that to
0.652 em with its own `Tw`, and the page draws that character wherever it means a space: after
`MH`, after `Under 50`, and seven times over to carry the text cursor into the Distance column.
The 0.134-em gap is half the narrowest space this font can draw, and no space glyph stands in it.

## Why the existing repair did not reach it

`Evidence.smallGaps` records boundaries with a positive gap of at most 0.01 em inside one `TJ`
array, and `extraSpaces` removes PDFKit's space only at those, only within one show, and only
between two ASCII letters. This gap is 0.134 em and falls between two shows, so no condition held.
Every insertion rule declined it correctly: the font-change rule needs a font change, `noteReference`
a raised smaller show, `sentenceSpace` sentence punctuation, and `sameFontWordSpace` reads
adjustments inside one show.

## The rule

`closesNumber` closes a boundary, and `apply` removes PDFKit's space at it, when

- the two shows are the same font at the same size (within 1%) on one baseline (within 0.1 em);
- the first ends in a digit and the second opens with one;
- the gap between the first show's last glyph and the second's origin is positive and **narrower
  than the space character that font itself draws** — `Widths[32]`, less any `Tw` that narrows it,
  which is the same `min(value, value + spacing)` reading [#119](https://github.com/vocaro/PDFReflowLib/issues/119)
  already takes of a `TJ` adjustment.

A font that states no width for code 32, or states zero, states nothing here and closes nothing.

## The corpus, measured

Every page of all 20 cached sources was read, and every place found where PDFKit reports a space
between two non-blank characters that the page's own shows do not draw, on lines whose shows spell
PDFKit's reading exactly apart from whitespace. The probe is
[`tools/survey-invented-spaces.swift`](tools/survey-invented-spaces.swift); the digit-to-digit
boundaries it found are [`digit-boundaries.json`](digit-boundaries.json).

| population | sites |
| --- | ---: |
| spaces PDFKit reports that the page's shows do not draw | 87,486 |
| of those, between two shows with a measured gap | 20,457 |
| of those, one font, one size, a digit on each side, a positive gap | 388 |
| **closed by the rule** | **1** |

The one is FAA page 416's `2|5`. Its gap is **0.536** of its font's own space. The next
digit-to-digit boundary in the corpus stands at **3.610** — that book's page 458 performance chart,
whose columns `03,550 7,570 11,980…` are a genuine cell boundary and stay one. Nothing lies between
0.536 and 3.610, so the measured margin either way is a factor of about two and of about seven.

Where the 388 sit, and what their fonts say:

| book | digit-to-digit sites | font states no space width | font states zero |
| --- | ---: | ---: | ---: |
| noaa-nca5-2023 | 222 | 0 | 0 |
| wallace-algebra-2010 | 160 | 140 | 20 |
| faa-phak-8083-25c | 6 | 0 | 0 |

**Wallace's algebra is out of the rule's reach by mechanism, not by threshold.** TeX draws no space
glyph at all — it positions each word — so 140 of that book's 160 boundaries have no width for code
32 in their font and the other 20 state it as zero. A positive gap cannot be less than zero, so no
boundary of the book #119's constraint is about can close, whatever its gap: not `30qpr`, not `5q`,
not `13000 13000`, not the worked examples that set one number under another.

The digit-to-digit restriction is doing measured work. Dropping it and keeping every other
condition admits 22 sites rather than 1, and all 21 of the additions are real word boundaries: 19
NOAA contents-page leaders (`Adaptation..........1` at 0.59–0.80 of the font's space, a period
against a page number), one FAA index leader, and two 9/11 prose boundaries. A period or a comma
against a digit is a leader or a sentence; a digit against a word is what
[#120](https://github.com/vocaro/PDFReflowLib/issues/120)'s font-change rule already weighs.

## Ownership: why a removal is not owned like an insertion

The segmented walk of [#139](https://github.com/vocaro/PDFReflowLib/issues/139) item 1 cannot own
this line, and the reason is the shape of the defect. A page sets a table row by carrying the text
cursor from cell to cell with runs of space glyphs, and PDFKit reports one space for a run, so on
such a row the **source** draws the whitespace the extraction does not. That walk skips only the
extraction's own spaces, so it reads each run as a disagreement, and page 416's row resynchronizes
on nothing: between `MH     Under 50         25` and `MH Under 50 2 5` the longest anchor left is
the nine characters of `Under 50 `, against an anchor length of twelve.

`closedSpaces` therefore owns a removal whole-line and blind to whitespace on both sides: every
non-blank character the shows draw must be the next non-blank character PDFKit read, in order, with
nothing left over either way; the closure must have no whitespace beside it in the source; and
exactly one space must stand at it in the extraction. That is stricter than the segmented walk, not
looser — one character of the line the shows cannot account for supplies no removal at all, where
the segmented walk would still apply what its other segments yielded — and it reaches no insertion.
Insertions keep the walk they already had, unchanged.

## What changed, end to end

The whole corpus was converted with a release CLI built from `86193ac` and with one built from this
branch, and the XHTML of all 150 documents of the 18 covered cases compared character for
character. Four lane runs were taken, two from each binary, because the comparison needs a
same-binary control ([#284](https://github.com/vocaro/PDFReflowLib/issues/284)).

Documents that differ, per comparison:

| comparison | binaries | cdc-zombie | census | faa-phak | warren-excerpt |
| --- | --- | ---: | ---: | ---: | ---: |
| `new1` vs `base1` | two | 2 | 1 | 1 | 1 |
| `new1` vs `base2` | two | 2 | 2 | 1 | — |
| `base2` vs `base1` | **one** | — | 2 | — | 1 |
| `new2` vs `new1` | **one** | 2 | 2 | — | — |

`faa-phak-8083-25c` is the only book that differs in every two-binary comparison and in no
one-binary comparison. Its whole difference is one line of one document:

```
chapter-26.xhtml   <pre>MH Under 50 2 5</pre>   →   <pre>MH Under 50 25</pre>
```

The book loses one character, the space itself, and gains none. Every other book in the table
differs across two runs of a binary that did not change, in scanned pages that Vision recognizes
and for which `NativeSpacingReader` supplies no evidence at all; that is #284, filed from this
work, and for the Warren excerpt
[#269](https://github.com/vocaro/PDFReflowLib/issues/269) and
[#281](https://github.com/vocaro/PDFReflowLib/issues/281). The remaining fourteen cases —
`wallace-algebra-2010` among them — are byte-identical in all four comparisons.

## The gates

`scripts/check-all.sh --fast` passes every gate: 630 Swift tests, the Python tool tests, the
documented probe builds, the fixture EPUBs, and 16 policy conversions with 24 rejection/cleanup
cases. The corpus lane passes 17 of its 18 covered cases with EPUBCheck and no structural failure;
every case's `result.json` reports `runPassed`, and the one content failure is
`gpo-warren-1964-suspect-text-excerpt`, which the unchanged `86193ac` binary also fails on one of
its two runs (#269).

Four Swift tests carry `#274`: the rule over the page's own numbers, the ownership walk over the
page's own two readings, FAA page 416 itself — where the row is repaired and the page's other 91
lines come back exactly as PDFKit read them — and Wallace pages 186, 281 and 343 as the standing
control from #119. The fixtures are `faa-416-layout.json` and `faa-416-spacing.json`, captured with
the reader in its pre-fix state.

## What is left

The rule reads only a boundary between two shows. A space PDFKit reports **inside** one show is a
different mechanism, and the survey found 65,231 of them. 142 have a digit on each side — 125 in
Wallace, whose fonts draw no space, and 17 in the FAA handbook, every one of them a column of the
page 458 and 459 performance charts (`0:00 2:00 4:00`, `03,550 7,570`) that the page means to
separate and PDFKit spaces correctly. So that population holds no known defect of this kind today,
and closing a boundary inside a show would need its own measurement and its own rule: the gap there
is a `TJ` adjustment, which `sameFontWordSpace` already reads in the opposite direction.
