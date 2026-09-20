# A wrapped paragraph printed over a picture reflows (#239)

`LayoutReconstructor.blocks` removes from the reflowed text every line a figure crop intersects.
For a picture's own lettering that is right — a diagram's labels, a chart's axis, a legend's
entries are part of the picture, the crop preserves them where they belong, and putting them into
the reading order is what `TextLayerPlausibility.carriesDrawnText` decided against (#176). It is
wrong for prose a page prints *on* a photograph: `LayoutReconstructor.expanded` trims a crop off
any text it can, but a run inside the artwork cannot be cut away from it without losing the
artwork, so the crop keeps the words and the book loses them.

That is what #239 reports. Reading a figure's footprint at its clipped extent (#52, #98) moved two
pages out of `PageDiagnosis.imageBackedText`, and their text was then inside a correct crop.

## The two pages are not the same case

**`usda-ars-agresearch-2012-11` page 4 gets its words back.** The photograph is a placed raster
image clipped to 540 × 619 pt, 69% of the page. Inside it, at x = 55.1, the magazine sets seven
rows at 7.8 pt on a 9.8 pt leading, each but the last between 84% and 100% of the run's widest
line, reading "At the Center for Medical, Agricultural, and Veterinary Entomology in Gainesville,
Florida, scientists set up a tent previously used in Iraq…". Sixty words, all 52 the lexicon
judges are English words (the other eight are names), and no token carries a digit. That is the magazine's caption — the page's
own prose, set in a text frame over the picture — and nothing about it belongs to the photograph.
The page also paints every one of those rows twice, one copy exactly over the other, for a
knockout against the photograph.

**`faa-phak-8083-25c` page 374 does not.** Its 71 words were never the page's text: they were
Vision's reading of the airport diagram's own labels, which the page reached only because a
footprint read past its clip made the whole page a full-page image and #93 replaced its two-line
layer with recognition. The page sets no prose. Its extracted layer is one caption and one folio,
and the caption stands *beneath* the diagram — the line box overlaps the picture's padded foot by
1.7 pt, which is a caption grazing a figure, not prose printed over one. The diagram's labels are
the picture's lettering; recovering them would put a taxiway sign legend into the reading order,
which is exactly #176's ruling. Page 374 keeps 0 reflowed words, and the diagram is preserved with
its caption.

## The union-area `coversPage`: rejected, on the evidence

The filing agent's first candidate was to judge `imageBackedText` on the page's combined painted
footprint. It restores USDA (union 76%) and not FAA (51%), so it matches the ruling above by
outcome. It is still the wrong instrument, for three reasons that are about evidence, not taste:

1. **The margin is not defensible.** USDA page 4's union is 76.3% against a 75% threshold: 1.3
   points of slack, on a quantity that is the sum of a photograph (69.0%), a masthead panel
   (6.1%) and two rules (1.2%) whose recorded extents each carry the reader's own 2-point padding
   and a bounding-box approximation of the clip. Removing the padding alone moves the union by
   more than the margin. No measurement in this repository claims that kind of precision for a
   footprint, and the clip record says so explicitly ("the tracked clip is a bounding box, so a
   non-rectangular clip path is over-approximated").
2. **It decides the wrong question.** `imageBackedText` means "this page is a scan carrying an
   inherited text layer". A magazine page that prints a photograph and a masthead is not a scan.
   Passing it would give the page a source-page reference, drop *all* its crops, clear the
   structure tags off every line, and expose it to #93's plausibility judgment — four consequences
   none of which page 4 needs. The defect is one line of prose handling, and repairing it by
   reclassifying the page as a scan buys the right words at the price of the wrong diagnosis.
3. **It does not generalize.** It restores exactly the pages whose art happens to tile three
   quarters of the sheet. `usda-ars-agresearch-2012-11` pages 7, 8, 11, 12, 15, 16, 18 and 19 and
   twenty NOAA pages lose prose to the same mechanism with unions well under 75%, and the union
   test leaves every one of them where it is.

The rule implemented instead asks what the run is, not how much of the page is painted.

## What was implemented

`PageDiagnosis.proseOverPictures` returns the lines a crop takes that still reflow. The crop is
unchanged and still shown; only the removal from prose is reconsidered. A line qualifies when

- it lies wholly inside one placed raster XObject (`PageContent.pictures`, the subset of the
  painted regions #176 already separates) that covers no more than `pageSizedGraphicFraction` of
  the page — a picture that covers the page *is* the page, a scan whose layer #93 and #176 already
  decide; and
- its run reads as a wrapped paragraph: at least 3 rows on one left edge (within a quarter of the
  type size), at one size (within a tenth) and one leading (0.8 to 2.2 type sizes, and within a
  quarter of the run's own first gap); every row but the last at least 0.8 of the run's widest
  row; at least 20 words; fewer than `TextLayerPlausibility.maximumNumericShare` of the tokens
  carrying digits; and at least `TextLayerPlausibility.minimumEnglishShare` of the judged words
  being English words. Only books declared English are judged, as #93's and #176's readings are.

Rows at an identical rectangle are one row of the paragraph, and that row reflows once: the
knockout copy stays inside the crop. Both word thresholds are the inherited layer's own, so the
rule introduces no new statistical constant.

`GraphicsReader`'s placed-image list now travels on `PageContent` rather than only on
`ExtractedPage`, so reconstruction can see it; `ExtractedPage.placedImages` is a computed view of
it and every existing caller is unchanged.

## Whole-book effect, before → after

Built from `41ce33a` for "before" and from the change for "after", macOS 27 arm64 release CLI,
library defaults and reproducible packaging:

```sh
swift build -c release
.build/release/pdf-reflow corpus/cache/November-December2012.pdf book.epub \
  --package-identifier urn:uuid:test --modification-date 2026-01-01T00:00:00Z
```

Counts come from the produced EPUBs (`measurements/clipped-footprints/tools/count-pages.py` and
`compare-counts.py`): per source-page marker, the whitespace-separated words of the following
markup with tags and figure captions removed, and the `<img>` elements attributed to that page.

| case | reflowed words | images | pages with no reflowed text |
| --- | --- | --- | --- |
| `usda-ars-agresearch-2012-11` | 4,253 → 4,855 | 75 → 75 | 7 → 6 |
| `noaa-nca5-2023` | 711,188 → 712,854 | 2,410 → 2,410 | 8 → 5 |

The other eighteen corpus documents — `arxiv-replay-clocks-2023`, `cdc-zombie-pandemic-2011`,
`census-rrs2002-01`, `cia-blue-book-14-1955`, `dga-2025-2030`, `faa-phak-8083-25c`,
`fed-explained-2021`, `gpo-911-2004`, `gpo-our-flag-2003`, `gpo-warren-1964`,
`gpo-warren-1964-suspect-text-excerpt`, `irs-p596-zhs-2025`, `nbs-jres-geltman-1977`,
`ntrs-20180003024-earthdata-slides-2018`, `scotus-loper-bright-2024`, `uscis-m618-arabic-2015`,
`usgs-mcs2025-copper` and `wallace-algebra-2010` — are unchanged in words, images and pages with
no reflowed text. **No page in any of the twenty loses a word.**

`gpo-warren-1964` and `noaa-nca5-2023` exceed the default image-output ceiling (#5), so both were
converted with `--maximum-output-bytes unlimited` and `jpeg:0.7` images, which changes neither
reflowed words nor image counts.

The changed pages, words before → after:

| case | page | before | after |
| --- | --- | --- | --- |
| `usda-ars-agresearch-2012-11` | 4 | 3 | 63 |
| | 7 | 8 | 169 |
| | 8 | 91 | 241 |
| | 11 | 387 | 434 |
| | 12 | 287 | 316 |
| | 15 | 611 | 655 |
| | 16 | 0 | 23 |
| | 18 | 482 | 531 |
| | 19 | 476 | 515 |
| `noaa-nca5-2023` | 4, 22, 24, 29, 31, 37, 48, 50, 55, 56 | 2, 16, 12, 14, 1, 8, 8, 175, 9, 143 | 44, 46, 57, 46, 168, 72, 129, 313, 34, 273 |
| | 58, 60, 61, 63, 64, 65, 67, 72, 75, 78 | 3, 59, 0, 83, 288, 0, 32, 0, 24, 172 | 135, 97, 34, 160, 346, 133, 148, 84, 138, 258 |

Page 4 gains its caption read once (60 words), not twice (120): the page paints each row twice and
the repetition stays in the crop. USDA pages 11 and 12 are the pull quotes of #158; NOAA pages 48,
50, 56, 58, 63 and 67 are the trapped columns and figure captions of #181. NOAA page 48 now reads
"How the United States Is Experiencing Climate Change / Global greenhouse gas emissions from human
activities continue to increase…", which is the page's own order.

## Positive controls

Every one is a real corpus page, and all are unchanged:

- **`cdc-zombie-pandemic-2011`** (2,706 words, 42 images, unchanged). The comic's speech balloons
  are its artwork; every page's picture covers the page, so the rule never looks at them.
- **`cia-blue-book-14-1955`** (168,660 words, unchanged). Page 136's four table rows share a left
  edge and a leading as a paragraph's do and read 11 of 18 judged words as English, but 46% of
  their tokens carry digits and the scan covers the page. Two independent conditions exclude them.
- **`faa-phak-8083-25c`** (246,850 words, 619 images, unchanged): page 374 stays at 0 words; page
  475's airport-sign legend, set inside the picture it explains, stays in its crop, because a
  whole entry stands between rows; and every page the clip change recovered keeps its gain.
- **`wallace-algebra-2010`** and **`gpo-911-2004`** (unchanged): exercise figures, chart labels and
  the "ON Boston Center" chart annotation stay where they are.

## Tests

`Tests/PDFReflowLibTests/ProseOverPicturesTests.swift` holds nine tests over pages built from
geometry and text measured on the source PDFs by `PageReader`, never from converted output. USDA
page 4's caption reflows once and its photograph is still cropped and shown; FAA page 374's
caption beneath the diagram, FAA page 475's legend, a page-sized picture (the CDC comic and the
CIA scan), a numeric table's rows and a chart's axis labels are all left in their crops; a book
not declared English is not judged; and the same three caption rows set a line further apart are
no longer one paragraph.

## Gates

`scripts/check-all.sh --fast` passes (ten gates), `swift test` runs 368 tests, and all 18
`corpus/regressions.json` cases pass (`tools/run_corpus_regressions.py`, EPUBCheck 5.x from
Homebrew); `gpo-warren-1964` and `noaa-nca5-2023` remain the two documented non-covered cases.

## Limits

Counts are not fidelity. The rule adds text to pages whose reading order is already wrong: USDA
pages 11 and 12 interleave their two columns before this change and still do after it, so the
pull quote they recover is woven into that interleaving. The rule reads only English books and
only runs wholly inside a placed raster image, so prose over a vector ground — the tinted panels
of #166, the shaded callouts of #181 — is untouched; those want the seed-side repair the
coordination branch made (`bff0a046c`, `0fa57f3b9`) and this change is not it. A run's words are
judged by the system lexicon, so a page of names or of another language's prose set over a
photograph would not be recovered.
