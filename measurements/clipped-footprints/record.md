# A painted footprint is bounded by its clip (#52, #98)

`GraphicsReader.paint()` recorded `path.insetBy(dx: -2, dy: -2)` and never consulted `State.clip`,
although the clip was already tracked and already bounded shadings a few lines away. A figure's
footprint was therefore how far its artwork was *drawn*, not what the page lets *show*: FAA page 19
places a 338 by 400 pt map under a 207 by 129 pt frame and the rest of it reached 43 pt into the
left column, so the crop swallowed the column's prose and the page read with its columns
interleaved (#52); page 96's streamlines run past a frame that starts 64 pt to their right, and
two sentences beside the figure appeared in no text block at all (#98).

The change is a hand port of the abandoned branch's `de0df61a5` onto `main`'s current reader
([decision 0005](../../doc/decisions/0005-abandoned-coordination-branch.md)), not a copy of its
code; `main`'s reader had since gained placed-image reporting (#176), a form-box region for a
figure's labels and the seed and expansion rewrite of `fde7193`. Two adaptations were needed that
the branch's version did not have, and both were found by measurement rather than by reading:

- **Pad before clipping, against a clip padded the same.** A horizontal rule is a path of no
  height, and an unpadded rectangle of no area intersects nothing, so clipping the raw path
  discarded every rule on the page. Clipping the padded path instead, but against the raw clip,
  shaves the two-point tolerance off every edge a clip touches and moves crops the clip does not
  really cut. Both orders were measured: the first fails the Our Flag flag-size table and the
  Wallace exercise image references and loses two Fed paragraphs; the second perturbs five IRS
  p596 pages and one FAA page by a word or two. Padding the footprint and widening the clip by
  the same two points leaves both unchanged.
- **Three clip states are distinguished.** The clip is now optional: `nil` means nothing clips,
  which is how a page with no usable crop box starts; a clip path that reached no coordinate
  (`W n` with nothing constructed) and a form box that transforms to no area leave the clip
  alone rather than emptying it, because over-approximating costs a crop that is too wide while
  under-approximating erases artwork. `q`/`Q` save and restore it, `descend` intersects each
  form's own box under that form's matrix and restores the caller's clip afterwards.

## Method

The macOS 27 arm64 release CLI was built from `12225ab` for the "before" column and from the
recorded change for "after", both with library defaults and reproducible packaging:

```sh
swift build -c release
.build/release/pdf-reflow corpus/cache/faa-h-8083-25c.pdf book.epub \
  --package-identifier urn:uuid:test --modification-date 2026-01-01T00:00:00Z
```

Counts come from the produced EPUBs: for each source-page marker (`id="page-N"`), the
whitespace-separated words of the following markup with tags and figure captions removed, and the
`<img>` elements attributed to that page (`tools/count-pages.py`, `tools/compare-counts.py`).
They are counts, not fidelity scores.

## Whole-book effect, before → after

Both figures below are this change alone; the operation budget is measured separately in
[operation-budget](../operation-budget/record.md).

| case | reflowed words | images | pages with no reflowed text |
| --- | --- | --- | --- |
| `faa-phak-8083-25c` | 240,582 → 245,116 | 596 → 617 | 5 → 6 |
| `fed-explained-2021` | 29,884 → 29,923 | 315 → 317 | 12 → 12 |
| `gpo-911-2004` | 287,264 → 287,264 | 100 → 101 | 12 → 12 |
| `gpo-our-flag-2003` | 13,276 → 13,277 | 147 → 147 | 1 → 1 |
| `wallace-algebra-2010` | 70,022 → 70,025 | 2,150 → 2,151 | 7 → 7 |
| `usda-ars-agresearch-2012-11` | 4,373 → 4,253 | 71 → 75 | 7 → 7 |

The other twelve corpus documents — `arxiv-replay-clocks-2023`, `cdc-zombie-pandemic-2011`,
`census-rrs2002-01`, `cia-blue-book-14-1955`, `dga-2025-2030`,
`gpo-warren-1964-suspect-text-excerpt`, `irs-p596-zhs-2025`, `nbs-jres-geltman-1977`,
`ntrs-20180003024-earthdata-slides-2018`, `scotus-loper-bright-2024`, `uscis-m618-arabic-2015`
and `usgs-mcs2025-copper` — are unchanged in words, images and pages with no reflowed text.

The FAA pages the two issues name, and the largest of the rest (words, images):

| page | before | after |
| --- | --- | --- |
| 19 | 373, 2 | 607, 2 |
| 96 | 249, 1 | 404, 1 |
| 108 | 398, 2 | 655, 2 |
| 130 | 633, 1 | 765, 1 |
| 146 | 471, 1 | 681, 2 |
| 191 | 281, 1 | 643, 1 |
| 195 | 233, 2 | 433, 2 |
| 351 | 222, 3 | 327, 3 |
| 361 | 241, 2 | 312, 2 |
| 367 | 138, 2 | 486, 2 |
| 394 | 214, 2 | 458, 2 |

Sixty-eight FAA pages change in words or images; none loses a word. `fed-explained-2021` page 135
gains 39 words, `gpo-our-flag-2003` page 36 one, and Wallace pages 100 and 105 three between them.

## The two pages that lose words

Both lose them for one mechanism, and it is not the clip itself. `PageDiagnosis.imageBackedText`
asks whether one recorded graphic covers more than 75% of the page; a page that passes is treated
as a scan with an inherited text layer, keeps its page as a reference image and has its figure
crops dropped entirely, so all its text reflows. Reading a footprint at its true extent moves two
pages out of that class, and their text is then taken by the figure crop it sits inside.

- **`usda-ars-agresearch-2012-11` page 4**, 123 → 3 words, 1 → 5 images. The photograph is placed
  across the whole page and clipped to the 540 by 619 pt area below the masthead: 83% of the page
  before, 69% after. Its sixty-word caption is printed over the photograph, and now goes into the
  crop with it. The whole page is still shown, as a page reference image.
- **`faa-phak-8083-25c` page 374**, 71 → 0 words, 1 → 1 image. The airport diagram is drawn over
  the whole page and clipped to the top two thirds (100% before, 51% after), which is what the
  page prints. Its 71 words were Vision's reading of the diagram's own labels, recovered because
  the page had become a full-page image; the diagram is still preserved, now as a correctly
  bounded figure with its caption, and nothing is recognized because the page is no longer a
  fallback. No prose is lost: the page sets none.

Neither loss is the clip reading too tightly — the ink check below covers both pages — and neither
is repaired by anything inside `GraphicsReader`. They are filed as #239.

## No artwork is lost

The stronger question is whether a clip read too tightly leaves real artwork outside the crops.
`tools/dump-crops.swift` writes every page's reconstructed crops and extracted line boxes for the
six changed documents, with the old reader and with the new one; `tools/inkdelta.py` renders each
page whose crops changed with Poppler at 72 DPI and counts the dark pixels (below 200 of 255)
outside the crops and outside every line box, under the old crops and under the new ones.

Over the 223 pages whose crops changed: **no page leaves more ink uncovered than before, and the
total newly uncovered is zero pixels.** Fifteen pages leave a little uncovered under both readers
— FAA page 276 leaves 1,218 pixels of 63,517 and fourteen others one to nine pixels each — which
is a pre-existing condition on identical crops, not this change.

## Tests

`ClippedFootprintTests` holds eleven tests over original one-page PDFs, each an operator sequence
a real page uses (`Tests/PDFReflowLibTests/Support/OperatorPDF.swift`). Seven fail on the old
reader: a path bounded by its clip, a path wholly outside it, an image placed far larger than its
frame (page 19's shape), a clip restored by `Q`, nested clips, a form box bounded by the clip in
force, and a form's own box bounding its content. Four pass either way and are the positive
controls: a rule of no height inside its clip is still recorded, a `W n` that reached no
coordinate leaves the clip alone, a frame drawn exactly on its clip keeps its tolerance, and a
clip set inside a form does not outlive it.

The source-derived targets are corpus contracts on the two pages the issues name. FAA page 19 must
reflow its whole left column before its right and page 96 its two sentences beside the figure;
both fail on the converter built from `12225ab`. Page 19 also carries an `imageRegions` reference
rendered from the source map, `corpus/references/faa-phak-8083-25c/page-19-figure-1-6-map.png`,
which the crop must still cover completely — a positive control that passes on both converters and
would fail if the clip cut the figure short.

## Gates

`scripts/check-all.sh --fast` passes, and all 18 `corpus/regressions.json` cases pass
(`tools/run_corpus_regressions.py`, EPUBCheck 5.x from Homebrew).

## Limits

Counts are not fidelity. Only the pages named above were reviewed against the source; the reading
order of the other sixty-odd recovered FAA pages is not re-qualified here. The ink check is a
presence test at 72 DPI with a one-pixel slack: it would not see a crop that cuts a few pixels off
an edge, and it says nothing about whether a crop is *too large*. The tracked clip is a bounding
box, so a non-rectangular clip path is over-approximated and a figure drawn into a circular or
polygonal window still reports the window's box.
