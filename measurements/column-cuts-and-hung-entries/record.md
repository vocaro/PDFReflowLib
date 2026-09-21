# A picture across the measure, and the wrapped entries of a hung list

Measured under [#160](https://github.com/vocaro/PDFReflowLib/issues/160), baselines `4074668`,
`4d5d86d`, `49e4586` and finally `b474f64`,
2026-09-20, macOS 27 (26A428) / Xcode 27 (27A266a), arm64, Swift 6.4, release CLI at library
defaults with a fixed package identifier and modification date. Block counts are every `<p>`,
`<pre>` and `<h*>` of the converted book outside its navigation document; character counts are the
non-whitespace characters inside those blocks. The page traces below were taken against `4074668`,
the commit this work branched from, and re-taken against `4d5d86d` after merging it; the geometry
and the blocks are the same on both.

The issue names three defects. Two are fixed here and one is not; what follows is what each page
actually does, measured rather than assumed, because the record the issue cites
(`measurements/caption-wraps-and-open-sentences/record.md`) was written on the abandoned
coordination branch and is not in this repository
([decision 0005](../../doc/decisions/0005-abandoned-coordination-branch.md)).

## 1. FAA pages 341, 391 and 397 — read row by row

The issue says the column test does not count a preserved image as column content. **It does not
hold.** `LayoutReconstructor.ordered`'s narrow-gutter guard asks each side for two text lines at
least twelve bodies wide, and on both of the pages that are actually wrong the right column has
three: on page 341 `Figure 14-8…` (237 pt), `Figure 14-9…` (237 pt) and `14 with collocated…`
(174 pt); on page 391 the left column has `Figure 16-3. World aeronautical chart.` (142 pt) and
`Figure 16-4. Meridians and parallels…` (237 pt). The guard passes on both. It is never reached.

The pages were traced with a probe that runs `PageReader`, `graphicsWithLabels` and
`LayoutReconstructor.blocks` over one page and prints the extracted geometry, the crops and the
blocks. Three separate findings:

**Page 391** opens with a figure crop at `x[34.0..524.3] y[363.6..730.0]` — 490.3 pt of a 490 pt
measure — and nothing printed above it. The `#137` picture cut demanded content on *both* sides
(`!above.isEmpty && !below.isEmpty`), so it declined. With the picture still in the group its own
x-interval spans both columns, so `gap(horizontal:)` finds no gutter; the widest band of
whitespace across the page is the 24.5 pt above the folio, and after that cut no band reaches the
1.1 bodies a horizontal cut needs (the largest is 8.0 pt). The group fell through to the row sort,
and the left column's captions interleaved with the right column's prose:

```
Figure 16-4. Meridians and parallels—the basis of measuring time,
be completed before dark. Remember, an hour is lost when
distance, and direction.
```

**Page 341** does the same with a figure at `y[462.3..729.8]`, and cutting at the picture alone
does not help: the page sets that figure's caption, `Figure 14-6. (A) Displaced runway threshold
drawing. (B) Displaced threshold for Runway 17 at Albuquerque International Airport (ABQ).`, at
`x[72.0..557.7]` — 485.7 pt of the same measure — 7.7 pt beneath it. The caption bridges the
columns exactly as the picture does.

**Page 397 is already in column order** and was before this change. Its spanning figure at
`y[375.0..541.1]` has the page's other spanning figure and its caption above it, so the `#137`
rule already fired. Its blocks are the top figure and caption, the left column's two figures and
captions, the folio, and then the right column's `To summarize:` and its seven bullets, in that
order. The folio sits in the middle because column order puts it at the foot of the left column,
which is where the page prints it.

### The rule, and why it is tried last

A picture across at least 90% of the block's measure with everything else on **one** side of it is
lifted out and the rest of the block re-read. A **line** across the same measure, within one body
of the picture's own top or bottom edge, joins the band and crosses the cut with the picture,
because it is that picture's label and bridges the columns the same way. The band grows only from
the picture's two edges and only while the partition still holds, so:

- on page 341 the caption joins (`y[443.8..729.8]`, everything else at `maxY ≤ 435.8`), and
- on the same page's right-hand group the picture at `y[277.0..435.8]` keeps its band to itself:
  adding `Figure 14-8…` would grow it to `y[260.7..435.8]`, and `on Taxiway Kilo` at
  `y[251.3..261.5]` then lies on neither side, so the extension is refused and the picture cuts
  alone.

A one-column page, whose every line spans its block, gives up at most the line above and the line
below the picture, never a chain of them, and the cut it makes is the order the row sort would have
produced anyway. Only a picture seeds a band: cutting at every line of a one-column page would
reach the 32-level depth limit and report the page unread.

It runs **after** every straight cut and after `columnRuns` (#174), immediately before the
row-major sort, and that position is measured, not chosen. Tried where #137's own cut is, it costs
the handbook's appendix of abbreviations: page 461 opens under a full-measure banner and sets two
columns of short entries beneath it, with an intro paragraph across both, so no gutter is found and
no whitespace band crosses the page. `columnRuns` reads the two columns as runs and the left column
is read out before the right. Cutting the banner out first leaves what remains to the row-major
sort:

```
A
ADIN—AUTODIN service ADIZ—air defense identification zone
A/C—aircraft
ADJ—adjacent
A/FD—airport/facility directory
```

one entry of each column at a time, over the appendix's pages: +53 blocks against the baseline.
Tried last, the page keeps its runs, and the handbook instead loses 13 blocks — pages 341 and 391,
the vertical-card compass page, and a glossary page whose `Baro-aiding…` now follows
`Balance tab…` instead of a page of unrelated text about aeronautical decision-making.

## 2. Blue Book pages 5–7 — the list of illustrations

Page 6 sets `Figure 14 Distribution of Object Sightings by Months Among the Eight Duration` from
`x = 80.8` and hangs its wrap, `Groups for All Years`, at `x = 129.3`: 48.5 pt at 7.8-point type,
six times the size. `BlockAssembler.continuesParagraph` allows two lines of one column 1.5 bodies
(10.5 pt here), so every wrapped entry closed its paragraph at the wrap. Eighteen of page 6's
twenty-four entries wrap, so twenty-four illustrations reflowed as forty-two paragraphs, with the
page numbers read afterwards in their own column and nothing at all between the halves.

The other two pages are a different defect and this rule does not reach them:

- **Page 5** sets the `Figure N` label in a column of its own and the titles from `x ≈ 124.8`,
  with wraps at `x ≈ 130.3` — 5.5 pt, inside the column window. Its titles were already whole.
- **Page 7** mixes both, and most of its lines are unusable: the book paints a rule down its
  margin and the inherited OCR layer merges that `I` into the line beside it, which gives a
  7.8-point line a 31.5-point box. `I South Farwest Region . 54` (`y[645.9..677.4]`) therefore
  sorts *above* the entry it continues, `Figure 38 …of the` (`y[656.8..663.8]`), and no join rule
  can reach it. The two entries the page hangs cleanly — `Figure 40 …Intervals` / `of 10 Degrees
  of Angle.` and `Table XI …on the Basis of` / `Duration of Ob~ervation 73` — are the only two on
  their edge, below the three this rule requires, and stay split. Filed as
  [#264](https://github.com/vocaro/PDFReflowLib/issues/264).

### The rule, and why the indent alone proves nothing

*Agricultural Research* opens every paragraph on a ten-point first-line indent in a 10.5-point
column, which sets the same two left edges in the same alternation as a hung list.
`firstLineIndentRun`, which exists to read exactly that, **returns true for Blue Book page 6**, so
it cannot be used as the control. What separates the two is what the line above does: a paragraph
ends on a short line that has run out of words, and an entry that wrapped ran out of room.

`LayoutReconstructor.hangingEntries` therefore requires all of: the wrap stands directly beneath
its entry, at the entry's size, on the page's own leading, set in further than 1.5 bodies (so the
rule speaks only where the column test is silent); the entry reads as a sentence, fills its
measure at twelve of its own sizes, and ends none past closing quotes and brackets; the wrap
carries at least two letters and stops a whole body short of the entry's right edge; and the page
hangs at least three entries on one and the same continuation edge.

The last three were added from measurement. A probe ran the detector over every page of all
twenty-four cached sources and printed each pair it offered. Without them it offered 465 pairs and
three of the Blue Book's own pages were wrong:

| Page | Entry offered | Wrap offered |
| ---: | --- | --- |
| 14 | `stimulated by the popular press. I` | `I` |
| 14 | `data. I` | `I` |
| 22 | `preceding identifications. An explanation of their use follows: I` | `was assigned to a report when, upon final con­ I` |
| 22 | `PSYCHOLOGICAL MANIFESTATIONS - This identification I` | `although it was well established that the ob­ I` |

All four are the merged margin rule again: it leaves both lines ending at the same right margin
and gives them boxes a type size too tall, so page 22's hanging *definitions* looked like entries
and their wraps, skipping the term between them. Requiring the wrap to stop a whole body short of
the entry's right edge refuses every one, because both lines end on the same `I`. With the three
guards the detector offers 313 pairs, and what remains is bibliographies (*Our Flag*'s, the NBS
paper's, the Census paper's), lists of tables (the Blue Book's appendix), a poem and a contributor
list (NOAA), memorandum headings and an autopsy report (Warren), and hanging list items (the FAA
handbook's and Wallace's).

## What moved

Every covered corpus book was converted with a release binary built from `4d5d86d` and with this
change, and each book's blocks and characters compared, then again with the cut alone so the two
halves can be told apart; the table below is the last of those measurements, over `b474f64`, which
merged #174's column runs, #203's picture-interrupted paragraphs and #171. Three books move on the
cut and two on the hung entry; the two sets are disjoint, and thirteen of the eighteen do not move
at all. The same five books, and the same block counts for each of them, came out of the same
comparison over `49e4586`.

| case | blocks `b474f64` | blocks, this change | characters `b474f64` | characters, this change |
| --- | ---: | ---: | ---: | ---: |
| `arxiv-replay-clocks-2023` | 194 | 194 | 39,855 | 39,855 |
| `cdc-zombie-pandemic-2011` | 481 | 481 | 12,639 | 12,639 |
| `census-rrs2002-01` | 371 | 371 | 33,612 | 33,612 |
| `cia-blue-book-14-1955` | 25,001 | **24,926** | 608,818 | 608,818 |
| `dga-2025-2030` | 133 | 133 | 13,485 | 13,485 |
| `faa-phak-8083-25c` | 8,387 | **8,374** | 1,414,314 | 1,414,314 |
| `fed-explained-2021` | 845 | 845 | 170,290 | 170,290 |
| `gpo-911-2004` | 5,022 | 5,022 | 1,585,147 | 1,585,147 |
| `gpo-our-flag-2003` | 546 | **540** | 63,281 | 63,281 |
| `gpo-warren-1964-suspect-text-excerpt` | 17 | 17 | 4,331 | 4,331 |
| `irs-p596-zhs-2025` | 954 | **935** | 36,346 | 36,346 |
| `nbs-jres-geltman-1977` | 38 | 38 | 3,017 | 3,017 |
| `ntrs-20180003024-earthdata-slides-2018` | 170 | 170 | 3,510 | 3,510 |
| `scotus-loper-bright-2024` | 731 | 731 | 198,473 | 198,473 |
| `uscis-m618-arabic-2015` | 1,257 | 1,257 | 90,736 | 90,736 |
| `usda-ars-agresearch-2012-11` | 1,078 | **961** | 52,155 | **52,146** |
| `usgs-mcs2025-copper` | 21 | 21 | 5,260 | 5,260 |
| `wallace-algebra-2010` | 7,561 | 7,561 | 312,562 | 312,562 |

**The cut** moves the FAA handbook, IRS Publication 596 and *Agricultural Research*. The magazine
gains most: its three-column feature pages open under a full-bleed photograph and were being read
row by row, one printed line per paragraph, and 117 blocks become 7 whole paragraphs. Its nine lost
characters are nine line-end hyphens `HyphenRepair` can resolve once the halves rejoin —
`Ento-`+`mology`, `Pro-`+`tecting`, `Pro-`+`tection”`, `Re-`+`search`, `ap-`+`plication`,
`develop-`+`ing`, `indi-`+`viduals`, `pres-`+`sure`, `prod-`+`ucts` — while `insect-transmitted`,
`nonagri-cultural` and `stored-product` keep theirs and the page warns, as the hyphen rule says it
should. IRS Publication 596's Chinese two-column pages join the same way, 19 blocks fewer. No text
is added or lost in any of the three books but those nine hyphens.

**The hung entry** moves the Blue Book and *Our Flag*. The Blue Book loses exactly the 75 blocks
the detector offers in that book; *Our Flag* 6 of its 12, the other 6 being bibliography entries
whose opening line the page marks, so they open a preformatted block and never reach
`continuesParagraph`. That is also why the FAA handbook does not move on this rule at all: all 55
pairs it offers are bulleted or numbered items. No book's characters change.

**What Vision does to this measurement.** Over `4d5d86d` the same comparison also moved
`cdc-zombie-pandemic-2011`, `census-rrs2002-01` and `gpo-warren-1964-suspect-text-excerpt`, and
none of it was this change's. Converted with `--no-ocr`, a fixed package identifier and a fixed
modification date, the two binaries produce a **byte-identical** EPUB of each of the three — the
Warren excerpt's is `aca72714f9698d69be192ff013582c723521a4b2b62841612b398a1ba2cbd816` — while
*Our Flag* and *Agricultural Research* differ, as they should. What moved in the three is what
Vision read. With `--ocr always`, so the text is the recognition and nothing else, the two binaries
disagreed on the Warren excerpt's *words*: `Omvald` against `Osvald`, `Painels` against `Paind's`,
`Houcide` against `Hodeide`, and about forty more on page 4 alone; each binary gave the same EPUB
SHA-256 twice in a row, so each was stable, at a different reading. The whole extraction pass,
recognition decisions included, runs before any block is reconstructed, so nothing in this change
can reach it. On that build `4d5d86d` failed that case's content contract five runs of five — four
errors, all on page 4 — and this work passed it eight of eight, for the same reason and with as
little to do with either build. Over `49e4586` the three agree again. Filed as
[#269](https://github.com/vocaro/PDFReflowLib/issues/269).

## 3. Proper nouns — not fixed, and not what the issue describes

The issue's example is FAA `The FAA` / `Safety Team`, and it says the join fails "when there's no
tag". Traced, the page says the opposite. Page 24's left column ends
`…through training, outreach, and education. The FAA` and its right column opens
`Safety Team (FAASTeam) exemplifies this commitment.`; the structure tree gives them
`TextStructure(group: 1004, order: 3227)` and `(group: 1004, order: 3228)` — consecutive lines of
one paragraph the source itself states, 12 lines long. **The tag is there and the paragraph splits
anyway**, because the page's figure crop `x[70.1..310.9] y[89.1..244.2]` stands at the foot of the
left column and its caption `Figure 1-13. Atlanta Flight Standards District Office (FSDO).` beside
it, so in reading order both fall between the paragraph's two halves, and `appendImage` and a
caption line of another group each close the open paragraph:

```
FAA Safety Team (FAASTeam) The FAA is dedicated to … and education. The FAA
[image]
Figure 1-13. Atlanta Flight Standards District Office (FSDO).
Safety Team (FAASTeam) exemplifies this commitment. The FAASTeam has replaced …
```

So the remedy the issue proposes — a vocabulary of multi-word names — is not what is missing
either: the paragraph's identity is already stated, and no lexicon would be consulted. Closing
this means carrying an open paragraph across an interposed picture and caption, or moving such a
picture out of a stated paragraph's run in reading order; either is a change to the reading-order
path, which #174 is holding, and neither is what the issue asks for. Nothing is changed for it
here and #160 stays open on this item alone.

No untagged instance was located. The record that would have named one does not exist.

## Gates

`scripts/check-all.sh --fast`, exit 0: python-tool-tests, measurements-policy, swift-tests (538,
seven new), release-build, pdfkit-concurrency, documented-builds, doc-counts, issue-citations,
fixture-epubs, conversion-policies. The corpus lane
(`tools/run_corpus_regressions.py --jobs 4`) passes 18 of 18 covered cases, every case's
`runPassed` read from its own `result.json` and true, with no content-contract and no structural
failures, and `b474f64` passes the same 18. Warning counts are unchanged book for book except
`uncertainHyphen`, which rises by one in the FAA handbook and one in *Agricultural Research* — one
page each where a rejoined word's hyphen is now visible and undecidable.
