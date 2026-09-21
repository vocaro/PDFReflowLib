# A sideways line's size, a stub's block boundary, and a centred stack

Measured under [#130](https://github.com/vocaro/PDFReflowLib/issues/130), baseline `97df92a`,
2026-09-20, macOS 27.0 (26A428), Xcode 27.0 (27A266a), Apple M5 Max, 36 GB, release CLI at library
defaults. The record the issue cites (`measurements/fallback-blocks-and-ligatures/record.md`) was
written on the abandoned coordination branch and is not in this tree
([decision 0005](../../doc/decisions/0005-abandoned-coordination-branch.md)); the three pages were
measured again here, on `main`.

The issue's own triage said items 2 and 3 no longer reproduced. Both still do on `97df92a`, in the
words the current readings give: Blue Book page 273 reads
`Yes or No IF you answered YES, then complete the following questions: 7.1 What directionwere you
moving?` as one paragraph, and CDC page 34's balloon reads as four
(`I'VE BEEN THINKING... WE SHOULD REALLY MAKE AN` / `EMERGENCY KIT` / `IN CASE` /
`SOMETHINS HAPPENED®`). The particular split the issue quotes for page 34
(`what Are you L o o k in g` / `f o r ?`) is indeed gone: Vision now reads that balloon as
`WHAT ARE YOU` / `LOOKING FOR?` and the pair joins on its left edges. The defect is the
rule, not those two lines.

## Three mechanisms

**A sideways line's box height is its length.** A recognized line's rectangle is axis-aligned, so
a line the page letters downward has a rectangle as tall as the line is long. CDC page 17 is
nothing but three such lines, at −90°:

| Line | Box height | Thickness across the quadrilateral |
| --- | ---: | ---: |
| `SEVERAL DAYS LATER AT THE CENTERS FOR` | 224.8 | 8.9 |
| `DISEASE CONTROL AND PREVENTION IN` | 201.8 | 10.2 |
| `ATLANTA, GEORGIA...` | 106.0 | 8.9 |

The page's body came out 225, putting its heading threshold at 281 or more, beyond anything
printed on it.
`OCRReader.recognize` now keeps the offset from the foot of Vision's quadrilateral to its head,
and the type size is the length of that offset whenever it runs more across the page than up it —
half a right angle is the boundary, so a line within that of vertical keeps its rectangle's height
to the bit. The band retry scales the offset's vertical part with its band and leaves its
horizontal part alone, because a band is the page's full width.

**A stub of prose had only punctuation to close it.** `continuesParagraph` ended a paragraph at a
short line only when that line ended a sentence. Blue Book page 273 sets the spaced answer row
`Yes or No` (x 112.05, 132.5 wide) under question 7 (x 88.89, 431.9 wide) and the instruction
`IF you answered YES, then complete the following questions:` (x 125.18, 353.7 wide) beneath it.
The row leaves question 7 on the left edges alone — 23.2 points apart, past the one and a half
bodies a column allows — and joins the instruction, because it ends in `No`. A line under half the
width of the one beneath it, with that line set at least half a body further in, now opens a new
block. #39 already reads a marker set in past the line above it as an item's opening rather than a
wrap, and its own guard (`prev.rect.minX - line.rect.minX > -body * 0.5`) is the exact complement
of this one, so no marked line changes.

Half is where the same book's contents stand. Page 5 hangs each wrapped contents line about six
points in — `Frequency of Object Sightings and Unknown Object Evaluations by` (251.7 wide) over
`Months, 1947-1952. 23` (412.9 wide, leaders to the margin) — and an entry that runs over is one
paragraph. At two thirds, the ratio the sentence rule uses, that entry and three more like it in
the Blue Book broke; at half they do not.

**A centred stack shares no left edge.** The paragraph join asks for left edges within one and a
half bodies. CDC letters every balloon centred, so page 34's five lines stand on five left edges
spread over 18 points and on one centre, within 1.7 points of each other on a ten-point page. Two
lines whose mid points agree within 0.6 of a body now join at the same leading — but only where
the reading also says the first line wraps. A shared centre is weaker evidence than a shared left
edge: Blue Book page 272 heads its questionnaire with `TENTATIVE` / `OBSERVERS QUESTIONNAIRE` /
`SECTION A`, whose centres agree to a hundredth of a point and which are three separate lines.
Vision states `shouldWrapToNextLine` for every line it recognizes and PDFKit's native reading
states nothing, so the centre joins nothing on a natively extracted page — page 272 included.

## What each change costs, across the whole corpus

Blocks are paragraphs, headings and preformatted blocks, counted in spine order. Both lanes ran
`tools/run_corpus_regressions.py --jobs 4` with EPUBCheck 5.3.0; all 18 cases report
`runPassed: true` in every lane below, and no book's text changes by a character in any of them
(concatenated block text, whitespace removed, is identical to the baseline for 17 books, and a
permutation of it for CDC).

**The size alone** (`OCRReader` only, `BlockAssembler` untouched) moves one page of one book:

| Book | Blocks | Change |
| --- | ---: | --- |
| cdc-zombie-pandemic-2011 | 516 → 516 | page 16's three sideways logo fragments reorder |
| the other 17 | unchanged | identical |

CDC page 16 is the publisher's logo lettered sideways, which Vision reads as
`УďпG` / `CONTROL ARD PREVE` / `CERTERG` / `FOE` / `JCDC`. Its body size falls from 150 to 12, and
the whitespace cuts that order the page use the body as their gutter width, so the fragments come
out in a different order. Neither order is the page; the page is a logo.

**All three changes together:**

| Book | Blocks | What moved |
| --- | ---: | --- |
| gpo-911-2004 | 4,574 → 5,045 | paragraphs that ran together now break at the first-line indent |
| cdc-zombie-pandemic-2011 | 516 → 481 | centred balloons join; page 16 reorders |
| irs-p596-zhs-2025 | 951 → 969 | `示例 1——…` examples and bulleted lines leave the paragraph above |
| scotus-loper-bright-2024 | 717 → 734 | a page's carried-over tail leaves the paragraph that opens beneath it |
| cia-blue-book-14-1955 | 22,564 → 22,573 | page 273's answer row; eight table cells and rule marks unglue |
| usda-ars-agresearch-2012-11 | 1,099 → 1,102 | `What To Wear` leaves its text; one index head splits |
| faa-phak-8083-25c | 8,538 → 8,539 | one table row's two cells separate |
| arxiv-replay-clocks-2023 | 194 → 195 | `Local/Send event.` opens its own paragraph |
| census-rrs2002-01 | 373 → 372 | reference [18]'s two recognized lines join on their centre |
| the other 9 | unchanged | identical |

The 9/11 report carries the change: it sets a first-line indent and its paragraphs ran together
wherever the previous one ended on something other than a full stop — a footnote marker, most
often. Page 20 went from five blocks to seventeen, each of the twelve new ones a paragraph the
printed page sets on its own. Of the 720 blocks that are new in the book, 711 open with a capital,
a digit or a mark; the nine that open lowercase are tails of paragraphs carried over from the
previous page, which now stop where the page's own next paragraph begins (`found.75` on page 286
is the shortest of them). *Loper Bright*'s two lowercase openings (`exercise.8` on page 40,
`the same Congress … resounding "yes."` on page 91) and *Agricultural Research*'s one
(`that down."` on page 8) are the same thing.

One split is arguably worse: *Agricultural Research*'s index on page 22 separates the head `Fruit`
from its first sub-entry, which the baseline ran together as
`Fruit card catalog collection at National Agricultural Library,`. Neither reads as the printed
index, which sets the head over its indented sub-entries. It is the only change in the corpus that
reads worse than what it replaced.

## What is not fixed

CDC page 23's broadcast balloon still reads as four paragraphs. Vision reports
`shouldWrapToNextLine == false` at each of its sentence ends (`...CONTINUES TO SPREAD.`,
`TO PRACTICE ISOLATION.`, `STAY IN YOUR HOMES.`), and that flag already governs every other
paragraph join in the library; overriding it for centred lines alone would give the weaker
geometry the stronger licence. What the centre recovers on that page is
`ALMOST A WEEK, TODD, AND WE HAVEN'T LEFT THE` + `HOUSE!` and
`STAY TUNED FOR A LIST OF SAFE` + `ZONES IN YOUR AREA...`.

Page 17's caption still reads in reverse — `ATLANTA, GEORGIA...` first, then the other two lines
joined as one paragraph in the wrong order — because the reading order and the paragraph join both
treat a sideways line's rectangle as though the writing ran along it. That is the order, not the
size, and it is filed as
[#263](https://github.com/vocaro/PDFReflowLib/issues/263). The direction each recognized line runs
in is now carried on the line for whoever takes it.

## Reproducing

```sh
swift build -c release
python3 tools/run_corpus_regressions.py \
  --converter "$(swift build -c release --show-bin-path)/pdf-reflow" \
  --epubcheck "$(command -v epubcheck)" --output /tmp/corpus-130 --jobs 4
```

The per-page geometry above was read with `tools/probes/capture-ocr-layout-fixture.swift`
(CDC pages 16, 17, 23, 34) and `tools/probes/capture-layout-fixture.swift` (Blue Book pages 5,
272, 273), both built from `tools/pdfreflow_tools/swift_sources.py`. Vision's compiled models
decide what any one page reads (#173), so the recognized geometry is evidence about this machine;
the library's own tests for all three rules use hand-made lines carrying these measurements.
