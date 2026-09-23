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

## The row behind the head

Each page sets `Cite as: …` or the case name on one row and the opinion's name — `Opinion of the
Court`, `GORSUCH, J., concurring`, `KAGAN, J., dissenting`, `Syllabus`, `THOMAS, J., concurring` —
on another. 111 of those stayed when only the outer row went, and no threshold reaches them:

- `outermost` is false for every one, because the first row stands above. Every candidate rule
  asks that, and `admitSlotEvidence` asks it too, so the slot this book keeps page after page is
  never consulted for them.
- `recordStack` grows a band only while the gap to the next row is under one line height. On page
  3 that gap is 10.86 points against a 10.81-point row: the two are set **two leadings apart**,
  not solid, so they are genuinely two rows and calling them one band would be wrong.

So `recordSecondRow` admits a line where **everything further out than it is already a candidate**,
it stands in the same band, and it is set apart from the body. One row deep and no more: the
outward set is read against the candidates the outermost-row loop found, so a third row sees the
second and is refused.

It is asked **half** the white an outermost row must keep. A row behind a head is bounded by the
head above it as well as by the body below, and this page gives it 9.53 points of a 10.81-point
line — where its own body lines touch, leaving nothing at all between them. What settles that it
is furniture is not its margin but its recurrence: `resolve` still removes it only where its words
and its place repeat on neighbouring pages, which is the whole of the evidence a head behind a
head has.

**The head only.** At the foot this reaches a line standing over a folio, and the folio-offset
signature then groups it across pages although its words differ page by page: `Caption 1` over
`4-1` and `Caption 2` over `4-2` normalize to one `Caption #(offset=0)`. That is what
`chapterPageFoliosSurviveNearbyFigureTextWithoutEnteringProse` pins, and #289 is a head in any
case.

## What moved, with both rows

| | baseline | with this change |
| --- | ---: | ---: |
| blocks | 731 | 409 |
| marks | 198,473 | 193,092 |

Forty-six distinct texts lose count, 324 blocks in all, and **forty-two of them are furniture**:

| text | before | after |
| --- | ---: | ---: |
| `Cite as: 603 U. S. ____ (2024)` | 57 | 0 |
| `LOPER BRIGHT ENTERPRISES v. RAIMONDO` | 38 | 0 |
| `Opinion of the Court` | 35 | 0 |
| `GORSUCH, J., concurring` | 34 | 1 |
| `KAGAN, J., dissenting` | 33 | 1 |
| `Syllabus` | 9 | 2 |
| `THOMAS, J., concurring` | 4 | 0 |
| `2 LOPER BRIGHT ENTERPRISES v. RAIMONDO` and its siblings | 5, 5, 4, 4 | 0 |
| the bare folios `1` to `35` | 7, 7, 4, 4, 3 × 25, 2, 1 | 2, 2, 0 … |

The handful that stay are leftovers on pages where the run did not reach, not errors; the two `1`s
and two `3`s are the opinions' own section numbers.

The other four are **two footnotes, each now continued across the page the head used to stand in
the middle of**. Removing the head let `appendPage` reach the other half:

```
6 It should be recalled that, when Justice Scalia launched the Chevron revolution, …   781 → 1,044 chars
—————— the early 20th century, the Court stated that it would afford “great weight” …  861 → 1,120 chars
```

Their two continuations — `criticisms of Chevron. Buffington, 598 U. S., at ___–___ …` and
`law.” Id., at 131. 6 Recall here that even the majority accepts …` — are the blocks that go with
them. Nothing else in the book is added, split or reworded, and no block's count rises apart from
those two joins.

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
