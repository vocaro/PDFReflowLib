# Columns a folio, a running foot or a spanning figure leaves uncut (#153)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 (26A428) arm64, Xcode 27.0
(27A266a), release CLI, host terminal. The work began on `cb58264` and was carried to `1a18b7a`
(#93, #141) and `b1c7043` (#151) by merging each tip and reapplying the uncommitted patch (no
commits). Baseline: `b1c7043` with `LayoutReconstructor.swift` restored from `b1c7043`; candidate:
`b1c7043` plus the working tree. [identity.json](identity.json) pins both CLIs, the capability
probe, the sources, the new fixtures and the commands. No PDF or EPUB is committed.

## What was wrong

`LayoutReconstructor.ordered()` cuts recursively: the widest gutter over all elements (with #47's
`headingBand` and #78's `stackedBlocks`), the widest horizontal band (with #86's `spanningFigures`
and #103's `trailingHeading`), #56's gutter measured over text lines, `spanningFigures` again,
#103's `headingRow`, #64's `bulletColumns`, #122's `interleavedBlocks`, then the reading-order sort.
A cut was kept only at the middle of the widest band and only when no element of the region crossed
it, so one small element in the gutter discarded the page's only column evidence. Captured geometry
(`tools/capture-layout-fixture.swift`) and a temporary trace of the region at each depth give the
cause on each reported page.

**Word IEEE paper** (`corpus/cache/20200002975.pdf`, `a98e4fcd…`), pages 1, 2, 5, 7–11.

- The printed folio sits centred in the gutter (`2` at x 303.1–309.1, the columns at 297.1 | 315.1)
  6 pt under the columns' last lines. Furniture removal keeps it (#154), so neither the gutter over
  all elements nor #56's gutter measured over text can be cut, no horizontal band of 1.1 body
  exists, and the page falls to the sort, which alternates the columns line by line. Pages 5, 7, 9
  and 11 add a figure across both columns with its caption; the folio still refuses every cut.
- **Page 1** also breaks the abstract at the same height in both columns: 10.4 pt of paragraph
  space, wider than 1.1 body (9.9), so the horizontal cut fired first and the left column's last
  two paragraphs read after the right column's continuation.
- **Page 10** is two columns of text over a full-width Figure 16. The page-9 paragraph continues
  through both of page 10's columns into page 11, so page 10's marker lies inside the joined text
  and #45 placed the figure, its caption and the folio ahead of that paragraph — inside page 9.

**IEEEtran paper** (`corpus/cache/20190030725.pdf`, `7c213709…`).

- **Page 4.** Figure 1's crop (x 80.7–310.4) overhangs the left column's measure (300) and reaches
  1.6 pt short of the right column's caption (312). The middle of the text gutter (306) is crossed
  by the crop, so #56's cut was refused and the Figure 2 caption interleaved with the left column.
- **Page 9.** Display crops narrow the whole-element gutter to 6 pt (302 | 308), under 0.75 body,
  and the appendices break both columns 14.8 pt apart, so the horizontal cut read the right
  column's `The quadratic objective function is` between the summary and `APPENDIX A`.
- **Page 10.** Table III's crop under its two-line caption stands beside the references with a
  12-pt gutter. A narrow gutter needed two text lines at least 12 bodies wide on each side; the
  caption's `of section V.` is short and a crop is not a line, so the page fell to the sort and
  `REFERENCES` split the caption.

**USDA magazine** (`corpus/cache/November-December2012.pdf`, `2673d1fd…`), pages 8, 9, 11–13, 15,
18 and 19. The running foot's rule (x 34.5–578.5) crosses every gutter at the page foot, and on
pages 11 and 15 a photo also covers one gutter of the three-column grid (page 11's crop overhangs
by 6 pt; page 15's display photo covers the first gutter entirely). Every such page fell to the
sort, so its three columns read a line at a time.

## What changed

`Sources/PDFReflowLib/LayoutReconstructor.swift` only (+232/−36). No public API, option, default or
warning changed.

1. **`whitespaceCut`** replaces the inline `gap` closure. It collects every band over the measured
   elements, widest first, and for each takes the middle when the region leaves it clear; where
   prose runs beside prose it may move the cut inside the band to a line nothing crosses (DASC
   page 4's 4-pt overhang, USDA page 11's 6 pt); otherwise it falls to the next widest band (USDA
   page 15's second gutter). A narrow gutter's prose test now counts a preserved figure or table at
   a column's measure beside at least one such line (DASC page 10).
2. **`marginBands`**, tried after `bulletColumns` and before the sort: the region's whitespace
   bands from the top and from the bottom (eight from each end) are tried in turn; what lies above
   a head band and below a foot band is set aside, and what remains must be cut by its
   text-measured gutter into prose columns running beside each other while the region as a whole is
   not. The set-aside content must cross that gutter and hold no prose beside prose.
3. **`proseBesideProse`**: at least two lines 12 bodies wide on each side, carrying two thirds of
   that side's characters, four fifths of them letters or spaces once contents leaders are
   discounted (`withoutLeaders`), and set in the page's body type (the wide lines' median size
   within a quarter of it), with the two sides running beside each other.
4. **A band no wider than paragraph spacing gives way to the gutter** (`marginBands(across:)`),
   after `spanningFigures` and `trailingHeading`: both columns must hold content on both sides of
   the band, the whitespace around it must reach no more than 4.5 bodies on each side, and the
   first line of each column's measure beneath it must be body text near that column's edge
   (`breaksBothColumns`).
5. **`appendPage`**: a figure or caption on a page the joined paragraph already runs into follows
   that paragraph, as a skipped page's figures do (#118). A folio keeps its place.

Designs tried and rejected, each on survey evidence:

- Counting any wide element as column content read Wallace's step tables (pages 81, 82) as two
  columns, all crops then all notes; a wide line is now required beside the figure.
- Moving the cut inside a band without the prose test moved 16 Wallace pages (81, 104, 146, 181,
  263, 380, 393, 424–436, 479) to crops-then-notes order and 2 more on the Blue Book.
- Margin bands without the word and body-type tests read the Blue Book's scanned statistical tables
  (13 pages) half by half and its contents pages by their `Figure N` labels, where OCR merges the
  margin rule into the line beside it (font sizes 31–42 against a 7-pt body).
- The band rule without `breaksBothColumns` read DGA pages 3 and 4 as two columns across their
  section breaks; without the running-column test it broke the synthetic DGA page-4 control in
  `DGABulletsAndContentsFolioTests`.
- Letting the crossed-page rule move folios as well as figures moved Warren pages 265/267's folio
  into the following page; it is limited to images and captions.

## Before and after

Every English corpus book was converted with both CLIs (19 books before the two new NTRS documents
arrived, 21 after) and compared block by block, page by page
([survey-changed-pages.txt](survey-changed-pages.txt)); the lane cases were then compared with
`tools/compare_conversion_runs.py --allow-different-converters --detail`
([page-comparison/](page-comparison/)). No image bytes change in any book, page markers are equal
everywhere, no OCR page changes, and the Vision programs are identical. **Every changed page was
read against a `pdftoppm` render (60–80 DPI).**

| Book | Changed pages | Fixed | Improved | Neutral | Regression |
| --- | --- | --- | --- | --- | --- |
| ntrs-20200002975-gwl-2020 | 9 | 8 | 1 | 0 | 0 |
| usda-ars-agresearch-2012-11 | 8 | 8 | 0 | 0 | 0 |
| ntrs-20190030725-dasc-2019 | 3 | 3 | 0 | 0 | 0 |
| faa-phak-8083-25c | 5 | 5 | 0 | 0 | 0 |
| noaa-nca5-2023 | 2 | 2 | 0 | 0 | 0 |
| arxiv-replay-clocks-2023 | 2 | 1 | 1 | 0 | 0 |
| wallace-algebra-2010 | 2 | 2 | 0 | 0 | 0 |
| gpo-warren-1964 | 1 | 0 | 0 | 1 | 0 |
| cia-blue-book-14-1955, cdc, census, dga, fed, 9/11, Our Flag, NBS, SCOTUS, USGS, pro se, slides, TechPort | 0 | | | | |

**Word IEEE paper.** Fixed: pages 1, 2, 5, 7, 8, 9 and 11 read the complete left column, then the
right, with the folio beyond them and each figure beside its own caption (page 11's Figures 17a,
17b and 18 in column order; page 7's `Surface roughness` paragraph after the Wind-Tunnel Conditions
paragraph it belongs to, not inside the Vibration Characteristics section). Page 12 changes only in
paragraph identifiers. Improved: page 10's Figure 16, its caption and the folio now follow the
paragraph that runs from page 9 through page 10 into page 11, so they no longer read inside page 9;
they land in page 11's range, the placement #118 gives a skipped page's figures.

**USDA magazine.** Fixed: pages 8, 9, 11, 12, 13, 15, 18 and 19 read column by column (page 15 from
the article's opening `Applying pesticides is no simple task.`, page 18 from the lead-in `“People
blame cows…”`), with the running foot beyond the columns. Two `uncertainHyphen` notices are added
(pages 11 and 15) where a hyphenated word now joins across the gutter (`as-say`, `compli-ance`);
retaining those hyphens is #159.

**IEEEtran paper.** Fixed: page 4 (left column and Figure 1's caption, then Figure 2's), page 9
(summary, both appendices, then the quadratic program) and page 10 (Table III's caption whole,
then `REFERENCES`).

**FAA.** Fixed: 230 (the Chapter Summary follows the OAT paragraph, ahead of the gauge figure),
341 (each of Figures 14-7, 14-8 and 14-9 beside its own caption), 391 (Figure 16-4 with its caption
before the right column's prose), 397 (Figure 16-16 with its caption before `To summarize:`) and
461 (the acronym glossary reads down each column: `A/C`, `A/FD`, `A/G`… instead of alternating
`A/C`, `ADIZ`, `A/FD`, `ADJ`…).

**NOAA.** Fixed: page 25 (the left column's Key Messages and Confidence prose whole, then Tables 1
and 2) and page 53 (each region's statements whole beside their icons instead of split across the
two columns). NOAA is outside the lane (image ceiling, #5); the comparison is the survey.

**Replay Clocks.** Fixed: page 7 reads section 7.1 and both `Varying` paragraphs whole instead of
44 one-line paragraphs alternating between the columns. Improved with a residual: the footnote
`<pre>` item at the head of the right column now absorbs that column's first paragraph (block
classification, #146/#154), and page 6 differs only in a paragraph identifier.

**Wallace.** Fixed: pages 125 and 126 read each of the two caption blocks under the number lines
whole (`As the graphs overlap, we take the largest graph for our solution.`).

**Warren.** Neutral: page 636 is a typewritten exhibit scan; two garbled handwriting lines swap.

## Tests

`Tests/PDFReflowLibTests/ColumnMarginOrderTests.swift` (12 tests) with new fixtures `gwl-1`,
`gwl-2`, `gwl-10`, `gwl-11`, `dasc-4`, `dasc-9`, `dasc-10`, `usda-15` and `algebra-263`, and the
existing `dga-3-illustrated` and `ntrs-9`. Controls: DGA page 3's stacked sections, Wallace page
263's formula crops beside their notes, a scanned table's halves, lines that merge a margin rule,
a section heading under one column and a column that ends above the band. Each of ten single-guard
mutations fails at least one test ([guard-mutations.log](guard-mutations.log)).

Against the baseline CLI the three books' contracts fail exactly the 37 new order checks
([before-contracts.json](before-contracts.json)): 23 on the Word paper (including page 9's new
`absentText` for Figure 16), 2 on the IEEEtran paper and 12 on the magazine.

## Gates

`swift test` (751 tests) and `scripts/check-all.sh --fast` pass. `tools/run_corpus_regressions.py`,
one case per call with the capability probe: the three reported books plus FAA, Wallace, Replay
Clocks, Fed, 9/11, Census, NBS, USGS and the two new NTRS documents all pass. The baseline lane
fails only the three books' new order checks.

## Known residuals

- USDA pages 6 and 17 still interleave: a column that continues into a wider measure below (an
  L-shaped text frame around a photo) leaves no straight gutter and no whitespace band, since the
  magazine's line rectangles overlap their neighbours by 1.3 pt. No rule here addresses it.
- The Word paper's page-10 figure reads inside page 11's range; a figure cannot sit between two
  page markers that both lie inside one paragraph.
- Replay Clocks page 7's footnote item absorbs the right column's first paragraph (#146/#154).
