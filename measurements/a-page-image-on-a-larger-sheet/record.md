# A page image printed on a larger sheet (#289)

Tier: deterministic Apple PDF stack, isolated macOS arm64 release CLI.
Corpus: every cached source, with *Loper Bright Enterprises v. Raimondo* as the subject.
Build: `main` at `2603d90` with this change, Xcode 27.0, macOS 27.0 (Darwin 27.0.0).
Baseline: `2603d90` alone.

## The defect

`FurnitureDetector.collect`'s candidate band is a share of the **sheet**: the top tenth of the
paper. A Supreme Court slip opinion is typeset on a six-by-nine page centred on US Letter, so its
text never reaches that tenth, and none of its running heads was ever a candidate for `resolve` to
weigh. All 210 survived, on 114 of the book's 228 pages — 29% of its blocks.

Captured with `tools/probes/capture-layout-fixture.swift`, the topmost line of a page:

| book | sheet | type area, as a share of the sheet | topmost line | in the 0.90 band |
| --- | --- | --- | ---: | --- |
| 9/11 report, p100 | 396 × 612 | 0.108 … 0.926 | 0.926 | yes |
| FAA handbook, p100 | 594 × 774 | 0.052 … 0.937 | 0.937 | yes |
| *The Fed Explained*, p30 | 612 × 792 | 0.169 … 0.951 | 0.951 | yes |
| **Loper Bright, p20** | 612 × 792 | **0.210 … 0.850** | **0.850** | **no** |

## What says a page is printed this way

Not the top inset — every book has one. **The symmetry and the depth of the side insets.** Over
all 114 of Loper Bright's pages that print text, the left inset is 156.19 to 156.25 points and the
right 155.95 to 156.15, on a 612-point sheet: a quarter of the sheet on each side, agreeing to a
tenth of a point. Against that:

| book | left | right | sheet | left as a share | difference |
| --- | ---: | ---: | ---: | ---: | ---: |
| **Loper Bright** | **156.24** | **156.13** | 612 | **25.5%** | **0.11** |
| 9/11 report | 39.7 | 44.2 | 396 | 10.0% | 4.5 |
| FAA handbook | 72.0 | 35.9 | 594 | 12.1% | 36.1 |
| *The Fed Explained* | 58.8 | 92.7 | 612 | 9.6% | 33.9 |

So the rule asks both insets to reach a seventh of the sheet and the two to agree within a
fiftieth of it. Loper Bright is the only book in the corpus that does, by a wide margin on both
counts, and the synthetic control in `furnitureRequiresStablePositionStyleAndNearbyDistinctPages`
— a repeated line above the body, inset 40 left and 160 right on a 600-point sheet — is refused by
the symmetry test, which is what keeps that contract intact.

It is read **per page**, because the evidence arrives one page at a time
([decision 0008](../../doc/decisions/0008-streamed-blocks-to-the-writer.md)): `DocumentEvidence`
calls `collect` as each page is extracted, with no document to consult. One page's own symmetry
removes nothing by itself — what `resolve` removes still has to repeat, in the same place and at
the same size, on neighbouring pages.

## What moved

**Twenty-one of the twenty-two cached sources are byte-identical**, every document of every one.
Loper Bright moves in all six of its spine documents:

| | baseline | with this change |
| --- | ---: | ---: |
| blocks | 731 | 522 |
| marks | 198,473 | 195,124 |

209 blocks and 3,349 marks, and **every one of them is furniture**. No block's count rises; not one
block is added, split or reworded. What goes:

| text | before | after |
| --- | ---: | ---: |
| `Cite as: 603 U. S. ____ (2024)` | 57 | 0 |
| `LOPER BRIGHT ENTERPRISES v. RAIMONDO` | 38 | 0 |
| `2 LOPER BRIGHT ENTERPRISES v. RAIMONDO`, `4 …`, `6 …`, `8 …` and the rest | 5, 5, 4, 4, … | 0 |
| bare folios `1`, `3`, `5`, `7`, `9`, `10`, … | 7, 7, 4, 4, 3, 3, … | 2, 2, 0, 0, 0, 0, … |

The two `1`s and two `3`s that stay are the opinions' own section numbers in the body, which is
what they are.

## What is not fixed

**The head's second row.** Each page sets `Cite as: …` or the case name on one row and the
opinion's name — `Opinion of the Court`, `GORSUCH, J., concurring`, `KAGAN, J., dissenting`,
`Syllabus` — on another, and 111 of those remain. They are not reached, and not by a threshold
that could be nudged:

- `outermost` is false for them, because the first row stands above; every candidate rule asks
  that, and `admitSlotEvidence` asks it too.
- `recordStack` would take them as a stacked band, but it grows the band only while the gap to the
  next row is under one line height. On page 3 the gap is 10.86 points against a line height of
  10.81 — the two rows are set **two leadings apart**, not solid, so they are genuinely two rows
  and not one band. Reaching them means a rule for a second margin row that repeats in its own
  slot, which is a different rule from this one and is measured by nobody yet.

`recordStack`'s own inward-edge test is moved onto the page image for consistency with the band,
since it is the same reading; it changes nothing here, because the band never forms.

## Gates

`scripts/check-all.sh --fast` passes, exit status read directly. The corpus lane passes 18 of 18
covered cases, every case's `runPassed` and content assessment read from its own `result.json` and
`content-assessment.json`. All 684 Swift tests pass, including
`furnitureRequiresStablePositionStyleAndNearbyDistinctPages` and
`lowerMarginOutsideExistingFooterBandKeepsLayoutEvidence`, which are the two controls a widened
band breaks and this one does not.

The foot is left exactly as it was: its band is narrower on purpose — a lower-margin number takes
part in the whitespace cuts around an illustrated row, and widening it changes reading order in
*Our Flag* even where the number is furniture — and this rule has no evidence about that.

## What is not claimed

The removals were read as the table above, and the per-book comparison is by document hash; no
page of Loper Bright was read against its own rendering. A seventh of the sheet and a fiftieth of
it are where this corpus's one page image separates from its four ordinary margins, with nothing
in between; a book inset less deeply, or unevenly, keeps the band it had.
