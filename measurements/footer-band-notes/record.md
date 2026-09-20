# A footer band taking the notes beside it

`dga-2025-2030` page 2 prints four numbered footnotes in two columns and paints a full-measure
band across the foot of the page beneath them. Two of the four notes never reached the reflowed
EPUB. This record measures why, and what the fix costs the rest of the corpus (#246).

Host: macOS 27.0 (26A428), Xcode 27.0 (27A266a), Apple M5 Max, 36 GB. Library source at `9e5758c`
plus this change. Measured 2026-09-20 with the release CLI at library defaults.

## What was lost

| Note | URL | Before | After |
| ---: | --- | --- | --- |
| 1 | `cdc.gov/chronic-disease/data-research/…` | present | present |
| 2 | `cdc.gov/nchs/fastats/obesity-overweight.htm` | **lost** | present |
| 3 | `gis.cdc.gov/grasp/diabetes/diabetesatlas-spotlight.html` | present | present |
| 4 | `cdc.gov/physical-activity/php/military-readiness/unfit-to-serve.html` | **lost** | present |

Not furniture removal: `--repeated-headers-and-footers keep` lost the same two.

## Why

PDFKit returns the notes as four lines, the surviving pair at y 87.99–95.96 and the lost pair at
y 77.49–85.46. `GraphicsReader` reports the band as a seed of `(0, 0, 612, 80.12)`.

The band's top edge reaches 2.63 points into the lost lines — a third of their 7.96-point height,
and the part of the line the glyphs' descenders occupy. `expanded` looks for a cut that avoids the
line while still containing the region's core; a full-measure band admits no such cut, so the
fallback admitted the line instead and the crop grew from y=80.12 to **y=87.46**, which is the
lost line's `maxY` plus the two-point inset the admission applies. `blocks` then dropped every
line the crop intersected.

The crop image the book shipped shows it plainly: the two lost notes sit at the top of the
picture on white, entirely above the cream band, beside the USDA and HHS logos that are the
band's actual content.

## The rule

A region that spans at least 90% of the page's measure and is flush against its top or bottom edge
is the page's own furniture. Such a region keeps its own extent rather than growing into a line it
merely grazes, and `takes` — a crop takes the lines whose middle it holds — leaves that line in
the prose. Every other region keeps the whole-line growth of #36.

Three earlier attempts are recorded here because each failed in a way that shaped the rule:

1. Applying "takes the lines whose middle it holds" to `blocks` alone did not free the notes: the
   crop had already grown past them.
2. Applying it to `captures` as well did not free them either: the fallback still admitted them.
3. Applying it to the fallback for every region freed them and broke
   `algebraExerciseLayoutPreservesWholeNumberedExpressions` in 14 places and
   `algebraPracticeFractionsKeepEveryBarWithItsTerms`. The clipped lines were Wallace's fraction
   numerators and denominators — `37)− 2÷ 7`, `4`, `43)− 1÷ 2`, `3` — whose middles lie outside
   their seed by construction, because a fraction bar owns the terms above and below it. Gating
   the restraint on `isThinRule` did not help, since `graphicsWithLabels` has already unioned a
   fraction bar with its terms by then and the seed is no longer thin. The page-edge test is what
   separates the two cases.

## What it costs

The full corpus lane passes, 18 of 18. Comparing the reflowed text of every case against the same
lane before the change, **17 of the 18 books are character-for-character identical**; only
`dga-2025-2030` differs.

That book gains 196 non-whitespace characters and loses none. Besides the two notes, the change
consolidates paragraphs another edge band had been fragmenting: `+ Consume less alcohol for better
overall health.` and `+ People who should completely avoid alcohol include pregnant women, …` are
now single lines where the output had held `overall health.`, `medications or with medical
conditions`, `+ People who should completely avoid` and `that can interact with alcohol. For
those` as separate interleaved fragments.
