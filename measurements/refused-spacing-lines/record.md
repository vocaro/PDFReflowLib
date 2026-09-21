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
