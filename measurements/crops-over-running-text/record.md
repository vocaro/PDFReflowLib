# Crops that held a page's running text (#158, #166)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, Xcode 27.0, release CLI. Work began on
`1a18b7a`, was carried to `bd80eb2` (the TechPort and Slides corpus cases, needed for #166), then to `b1c7043`
(#151), then to `73cbdfe` (opaque page rasters and the gated NOAA assessment), and finally rebased onto `34914f5`
(#159's first-line-indent paragraphs, furniture rules and corner credits, over #180, #107 and #178/#179); every
measurement below was re-taken against `34914f5`. No PDF, EPUB, raster or crop of
either case is committed: the TechPort insignia is on every page and the magazine's back cover carries agency logos
(see the manifest rights notes). The fixtures hold extracted text and geometry only.

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline | `34914f5` | `f49e2601…` |
| candidate | `34914f5` plus this change | `4d6c6b7a…` |

Corpus: `usda-ars-agresearch-2012-11` (`November-December2012.pdf`) and `ntrs-20210020887-techport-thm-2021`;
controls every other English document in the manifest. Tools in [`tools/`](tools/) ran from a scratch directory;
paths inside them are those of the run. The Swift tools compile the library sources (minus `EPUBWriter` and
`PDFConverter`) with the tool (`tools/build.sh`).

## Diagnosis

`tools/diag.swift` and `tools/steps.swift` print a page's paints, each composition step, the composed crops and the
lines each takes; `tools/cropsurvey.swift` does the same for every page of a document. Six mechanisms, all in crop
seeding and growth, kept 45,000 of the magazine's 70,000 source characters and a third of TechPort's inside images.

1. **A transparency group's box read as solid ink.** InDesign wraps an object carrying a drop shadow, a tint or an
   opacity effect in a form whose `BBox` is exactly what the object paints, and `GraphicsReader` recorded that box
   as a second, unclassified footprint. `TintDetector` treats a non-rectangle footprint as solid ink, so the
   masthead box (page 3), every caption box over a photograph (pages 4, 8, 16, 20, 21) and the pull-quote boxes
   (pages 11, 12, 14) failed the tint evidence: the lines they held were "touched by ink".
2. **Backgrounds under the columns.** Pages 5, 7, 8, 10, 13 and 14 print a faded flag across the text area, page 4
   sets its column over the screenhouse photograph, and NOAA's front matter sets its columns over decorative line
   art. The image seeded a crop that took every line over it; page 13's two images covered the page, so it also
   took the review warning and a source-page reference.
3. **A bounding box bridging art across text.** `clusters` grows hulls, so the index pages' holly ornament joined
   the rule under the title across three columns of entries, the FORUM page's signature box joined the
   running-foot rule across the foot of three columns, and TechPort's gallery joined three pictures across the
   captions beneath the shorter two.
4. **Text on a filled band or panel with too little prose.** `isProse` needs four words on 40% of the block's
   width, and the tint rule needs three such lines in a third of the block. TechPort's header band (three lines,
   one of them the document's title) and its page-height sidebars (headings, labelled fields, a contents list)
   never reached it, so the band repeated as an identical crop on all five pages and the sidebars were
   page-height crops.
5. **A crop growing over a column.** Whole-line expansion admits every line a seed intersects. The index rule ends
   a tenth of a point inside the first entry of a column and the holly ornament a half point inside the title
   beside it; each grew a crop that then had no cut available and swallowed the page.
6. **A page-wide gradient forcing a page image.** Pages 20 and 21 paint an axial shading over 80% of the page;
   `GraphicsReader.shading` refused it (`unsupportedGraphics`), so both articles became page images with no text
   at all.

## Change

No public API, option, default or warning code changed.

- **`GraphicsReader`**: a form's box records no footprint where the form's own paints cover it (within two points),
  marking the widest of them `grouped` instead; `Paint` gains that flag, which `TintDetector.withoutTitleBackdrops`
  uses to keep judging a title box that used to be judged through its duplicate. A shading across the whole page is
  recorded as a paint rather than refusing the page.
- **`TintDetector.blockText`**: the page's blocks of running text — a run of at least three lines of one size, each
  within nine tenths of a line of the one above, overlapping its measure, standing on the block's left edge give or
  take three sizes, of which at least two read as prose (four words of two letters) or open in mid sentence with
  two words. A page of more than 2,000 lines has none.
- **`TintDetector.withoutTextBackdrops`** (before clustering): an image holding at least three body-size prose
  lines that make up a third of the lines inside it seeds nothing when less than half of it lies beyond that text
  or another image covers what does; keeps only the part beyond the text when the text's block runs on past the
  image; and is otherwise left with the text inside it. An image a title or prose line crosses but lies mostly
  beyond gives up that side, and so does one under a caption set on its own filled band, while it keeps at least
  half of itself.
- **`TintDetector.clustersKeepingText`**: where a hull takes block text that no part of it takes, its parts are
  clustered again, joining two groups only where the box around them takes none of that text.
- **`TintDetector.seedClusters`**: a horizontal rule at least half the text's width that strikes no line is a
  divider and may be dropped from a hull, on the same escaped-prose evidence as #117's margin rules.
- **`TintDetector.composeTints`**: two more kinds of tint after the existing prose and ruled-table evidence — a
  banner band (four fifths of the page wide, against its top or bottom edge, rows of three words or a title, one of
  them a title, art clear of the lines) and a panel holding at least three lines of block text that all stand on
  one edge with the panel's other lines and no grid of rules. Art inside a tinted block that stands beside its text
  rather than between its lines keeps its own extent instead of the block's full-width band.
- **`LayoutReconstructor`**: a crop captures a line only where it overlaps it by more than a point in both
  directions; where trimming cannot cut a crop away from a line of block text, the crop gives up the outermost
  point of its own art (`textCut`) rather than the column that line opens; and two crops that do not overlap stay
  apart when the box around them would take block text that neither takes.
- **Furniture evidence a reflowed page used to lose** (found by the `34914f5` rebase, see "The running foot #159
  rules off"): a page that keeps a source-page reference instead of its crops now keeps its page-wide rules as
  separators rather than clearing them with its graphics (`PDFReflowLibPipeline`, `LayoutReconstructor
  .isPageWideRule`), and `FurnitureDetector.ruledOff` reads a page's graphics and separators alike.
- Tests: `CropsOverRunningTextTests.swift` (17 tests), seven `usda-*`/`thm-*` fixtures, `capture-layout-fixture.swift`
  and `SourceLayoutFixture` record `grouped`. `ShadingTests`, `IllustratedPageTests` and
  `RuledTablesAndHeaderRulesTests` were updated where the behaviour they pinned changed (see Tests). Docs:
  `doc/architecture.md`, `doc/regression-testing.md`; counts regenerated.

### Designs measured and rejected

- **Capturing against a cluster's parts rather than its bounding box.** Principled, and it fixed one case the
  divider rule later covered, but across the English corpus it changed only two pages (Wallace 312, Census 18) and
  took *more* text into those crops. Removed.
- **Never capturing a line of block text unless the art holds it.** It freed the magazine's drop-cap crop (46
  words), at the cost of 161 changed NOAA pages, 22 Wallace pages and an FAA page in one step. Rejected as
  unreviewable for the benefit.
- **Judging frames as title backdrops (#117's per-paint rule without its frame exclusion).** Fixed the magazine's
  title box but changed 18 Fed pages and 99 NOAA pages; the `grouped` flag reproduces the pre-existing behaviour
  exactly instead.
- **Accepting a panel of running text before the ruled-table rule** (branch order): Fed page 46's Table 3.1 lost
  its table reading and 236 words to a crop. The panel rule is now the last resort, and a grid of rules refuses it.
- **Ignoring small ink inside a ruled table** so TechPort's role icons would not block the table reader: no page in
  the corpus changed, so the tables there are not read as tables for another reason. Reverted.

## Before and after

### The two cases

Characters are non-whitespace characters per page, `pdftotext` against the EPUB's page markers
(`tools/srccmp.py`); the EPUB totals from `tools/chars.py` count every text node.

| | source layer | baseline | candidate |
| --- | --- | --- | --- |
| Agricultural Research, non-whitespace | 70,247 | 24,495 | 69,629 |
| Agricultural Research, EPUB text characters | — | 28,602 | 80,998 |
| TechPort, non-whitespace | 6,702 | 5,375 | 6,579 |
| TechPort, EPUB text characters | — | 6,226 | 7,557 |

The magazine's candidate now tracks its source layer to 618 characters of 70,247; every page gains or holds, none
loses. Per page (non-whitespace, base → cand): page 2 48 → 4,311, page 3 94 → 3,440, page 5 48 → 3,652, page 7 72
→ 3,015, page 8 483 → 2,841, page 10 47 → 2,658, page 14 25 → 3,513, page 16 68 → 3,419, page 20 25 → 3,010, page
21 25 → 2,862, page 22 50 → 6,080, page 23 25 → 6,195. TechPort: page 1 2,005 → 2,395, page 4 515 → 606, page 5
207 → 748. The remaining gap against the source layer is the running foot `34914f5` now rules off every page
(#159) and the captions listed under "Remaining gaps".

Against `b1c7043` the magazine's candidate stood at 72,116, above its own source layer of 70,247, because PDFKit returned
each shadowed caption and pull quote twice. **That is fixed upstream and must not be re-fixed here.** The magazine
draws each of those lines twice at an identical `Tm` (page 4's caption at `7.8 0 0 7.8 55.08 131.3734 Tm`, page
11's pull quote at `15.3 0 0 15.3 226.44 739.1012 Tm`, once each side of the shadow form), so #165's exact-overprint
rule in `withoutOverprints` already removes the second draw: magazine 55 overprints removed, Blue Book 1,315,
slides 15, Fed 9, NBS 6, Census 1. Two scanners over the candidate EPUBs find no shadow duplication left — the only
repeated blocks are genuine furniture (the magazine's running foot on 14 pages, a repeated URL, TechPort's header
band on all five pages, which is defect 4). Widening the rule to tolerate an offset was measured and rejected: over
all 21 English documents, same text and size with an offset above 0.05 pt and up to 0.35 em, it would newly remove
only the magazine's page-23 running foot (0.04 em apart) and four Blue Book scan-OCR fragments (`I I`, 0.26–0.27 em)
— furniture and noise, and nothing else in the corpus.

Warnings, magazine: `pageImageFallback` on pages 20 and 21 → none, `unsupportedGraphics` on the same two → none,
`unverifiedTextLayer` pages 1 and 13 → pages 1, 20 and 21 (page 13 loses it; 20 and 21 gain it with their reflowed
text over the page-wide gradient), `imageRegion` 22 → 24 pages, `uncertainHyphen` 7 → 14 pages (more text to
repair), `furnitureRemoved` on pages 2–23 in both, images 52 → 64, reflowed pages 17 → 24. TechPort's warnings are
identical; images 37 → 39 (the gallery is three crops).

### Every English document

`tools/cropsurvey.swift` lists each page's composed crops and the lines they take, for both builds, and
`tools/sdiff.py` diffs them ([`survey/`](survey/); the pipeline's page-sized clearing is not applied, so the survey
is a superset of what the EPUB shows).

| Document | Pages changed | Words inside crops on them (base → cand) | Review |
| --- | --- | --- | --- |
| Agricultural Research | 19 | 7,326 → 1,246 | the issue's pages; see below |
| TechPort | 5 | 311 → 150 | header band, sidebar photo caption, gallery |
| NOAA | 28 | 3,659 → 2,724 | front matter, reference lists, box titles, one chart statement freed |
| Fed | 9 | 825 → 257 | eight are page-image pages (cleared, output identical); page 86's figure title reflows |
| FAA | 18 | 2,232 → 2,188 | seventeen are chapter openers (cleared); page 374's `Figure 14-60.` caption reflows |
| CDC, Our Flag | 9, 1 | 1,148 → 0, 327 → 0 | page-image pages only; output identical |
| Wallace | 8 | 1,217 → 1,085 | worked-example annotations and a table's prose leave their crops |
| NASA DASC | 2 | 545 → 530 | two formula crops tighten to the formula |
| DGA, USGS, NBS, arXiv, Census, US Courts, GWL, Slides, 9/11, Blue Book, Warren, Loper Bright | 0 | — | unchanged |

Renders reviewed at 50 DPI with every crop outlined (`tools/overlay.py`): magazine pages 2, 3, 4, 5, 7, 8, 9, 13,
14, 15, 16, 18, 20, 21, 22 and 23; TechPort 1, 2, 4 and 5; NOAA 411; Fed 86; DASC 6; Wallace 49, 310 and 373. The
magazine keeps the flag banner, the signature box, every photograph (page 4's minus its caption strip, page 16's
minus the title and caption band), the holly ornaments and the index title's art; pages 20 and 21 keep a
source-page reference instead of a page image. TechPort keeps the insignia, the sidebar photograph, the map, the
TRL chart, the tables and the three gallery pictures.

### Lanes

`tools/pair.sh <case>` runs `run_corpus_regressions.py` with EPUBCheck, the environment probe and the memory gate,
one case per call for each build, then `compare_conversion_runs.py --allow-different-converters --detail`
([`lane/`](lane/); EPUBs deleted after each comparison).

| Case | Contract (base → cand) | Changed pages | Peak RSS (base → cand) |
| --- | --- | --- | --- |
| usda-ars-agresearch-2012-11 | base fails 31 (exactly the new checks), cand passes 242 | 1–24 | 310 → 301 MB |
| ntrs-20210020887-techport-thm-2021 | base fails 8 (the new checks), cand passes 72 | 1–5 | 45 → 42 MB |
| faa-phak-8083-25c | both pass 560 | 138, 151, 165, 374, 408 | 920 → 839 MB |
| wallace-algebra-2010 | both pass 283 | 49, 310, 318, 370, 373, 374, 376, 377, 476 | 90 → 88 MB |
| ntrs-20190030725-dasc-2019 | both pass 246 | 6, 10 | 51 MB both |
| noaa-nca5-2023 | both pass 28 | 24 with content changes (4, 31, 32, 36, 42, 53, 65, 71, 79, 285, 351, 405, 411, 687, 863, 981, 982, 1000, 1019, 1049, 1273, 1402, 1531, 1549); 1,005 more differ only in `headingRanks` | 1,042 → 1,030 MB |
| gpo-911-2004, ntrs-20200002975-gwl-2020, dga-2025-2030, fed-explained-2021, cdc-zombie-pandemic-2011, usgs-mcs2025-copper, gpo-our-flag-2003, nbs-jres-geltman-1977, ntrs-20180003024-earthdata-slides-2018, census-rrs2002-01 | both pass (306, 286, 96, 201, 60, 51, 134, 64, 224, 74) | none: byte-identical | within run-to-run spread |

On FAA pages 138, 151, 165 and 408 and Wallace 476 the crop rectangle shifts by a fraction of a point (the group
box no longer pads the seed), so the same figure rasterizes with a sub-pixel offset: same pixel dimensions, 0.2–0.6%
of pixels differing. FAA page 374 loses the strip its caption sat on and gains that caption as text.

NOAA has a gated eight-page assessment (`73cbdfe`), so it runs in the lane rather than the survey alone; it costs
about 500 MB of output per side and was run last, with each side deleted as soon as it was compared. Its 24
content-changed pages are the survey's 28 minus pages 26, 34, 67 and 1485, where the crop rectangle moves but the
page-sized clearing makes the output identical (the survey is a superset). Heading ranks are document-wide
ordinals, so the 24 changed pages renumber the ranks on 1,005 later pages; `idOnlyShifts` reports 802 pages whose
only other difference is a generated identifier. Warren stays excluded from full conversions (#5).

### The running foot #159 rules off

Rebasing onto `34914f5` turned up a real interaction, which the magazine lane caught: the candidate failed #159's
new `absentText` check on page 22, printing `Agricultural Research l November/December 2012` on pages 20–23.

The magazine rules its running foot off under every column and sets a six-point photo credit just above that rule,
so the foot's nearest neighbour is 8.2 pt away — nearer than a line height — and only the rule admits it as
furniture (`FurnitureDetector.ruledOff`). Pages 20 and 21 set their columns over a page-wide gradient. Once this
change reflows them, they take the image-backed path that keeps a source-page reference and clears the page's
graphics, tints and separators — and the rule went with them. The foot was then recorded on pages 2–19, 22 and 23
but not on 20 and 21, which broke the run of consecutive pages: the tail 22–23 is two pages against the three a
run needs, so neither was resolved and both printed their foot. In the baseline the same two pages are whole-page
images, so nothing of theirs printed and the check passed vacuously.

The fix keeps the evidence without keeping a crop: a page that clears its graphics now keeps its page-wide rules
(`LayoutReconstructor.isPageWideRule`: `isThinRule` and at least 60% of the page's width) as separators, and
`ruledOff` reads graphics and separators alike. Pages 20–23 lose their foot again, the lane passes 242 checks with
no errors, and no other case changed. Instrumented runs of the real pipeline are what located this: `ruledOff`
saw `graphics []` on pages 20 and 21 and the rule on every other page.

A page-23 remnant is left over and is filed below: the magazine draws that page's foot twice, 0.17 pt apart at
12.33 and 11.98 pt tall, so #165's exact-overprint rule keeps both draws and the ledger removes only the one it
recorded.

## Tests and contracts

- `swift test`: 887 pass (870 plus 17). `scripts/check-all.sh --fast`: exit 0, including the generated doc counts
  (`tools/update_doc_counts.py` moves the contract summary to 3,306 checks and the Swift test count to 887).
- `CropsOverRunningTextTests.swift`: seven source-derived fixtures with the defect as a control on each
  (`usda-2` FORUM columns, `usda-3` masthead, `usda-14` flag and pull quote, `usda-16` title box and caption band,
  `usda-22` index, `thm-1` header band and sidebar, `thm-5` gallery), plus synthetic positives and controls for
  `blockText`, constrained clustering, backgrounds and overhanging titles, caption bands, banner bands, panels, the
  grazing corner and the text cut, and two original in-memory PDFs (the covered group box, the page-wide gradient).
- Updated pins: `ShadingTests.shadingRejectsMissingResourcesAndUnboundedRegions` now records the page-wide gradient
  as a paint; `IllustratedPageTests.marginRulesBridgeNoArtAcrossProse` counts the rule as a surviving seed rather
  than the hull, since any bridge across running text is now split; `RuledTablesAndHeaderRulesTests` checks the
  grid's crop rather than its seed, because the grid's parts now seed separate regions that whole-line expansion
  joins again.
- `aRuledOffFootSurvivesAsASeparatorWhenAPageClearsItsGraphics`: three magazine pages whose foot is ruled off and
  whose credit stands nearer than a line height, once with the rule among the page's graphics and once with the
  page cleared and the rule kept as a separator. Both must lose the foot and keep the credit; with `ruledOff`
  reading graphics only, the cleared half fails on all three pages.
- Mutations ([mutants.log](mutants.log), `tools/mutate.py`): 28 of 28 single-guard mutations fail at least one
  test. Two survived a first pass (the grazing corner and the text cut, which cover the same magazine page from
  different sides) until the synthetic control isolated each. Re-run after the `73cbdfe` rebase: 28 of 28 killed
  again, no survivors. All 28 anchors still apply unchanged on `34914f5`; the mutations were not re-run there.
- Contract (`tools/addcontract.py`): 39 checks on 12 pages. Magazine pages 2 (columns in order, the signature box
  still absent from the text), 3 (masthead and contents), 13 (no review warning), 14, 16 (heading and caption), 20
  and 21 (headings, text, no `pageImageFallback` or `unsupportedGraphics`), 22 and 23 (index entries); TechPort
  page 1 (band title, contents list) and page 5 (gallery captions). The baseline fails exactly those 39. Column
  order on the interleaved pages is not approved (#153), so they are checked by phrase.

## Cost

`#117`'s bounds are unchanged (`titleBackdropCandidateLimit`, `seedClusterWorkLimit`), the new backdrop, banner and
clustering rules are bounded by the same work limit, and `blockText` returns nothing above 2,000 lines. Composition
and crop growth per page (`tools/composetime.swift`, release, best of five, base → candidate):

| Page | Paints | Lines | compose | graphicsWithLabels |
| --- | --- | --- | --- | --- |
| FAA 448 | 10,000 | 70 | 9.2 → 9.4 ms | 0.6 → 0.9 ms |
| FAA 226 | 5,130 → 5,124 | 54 | 5.2 → 5.4 ms | 0.4 → 0.7 ms |
| FAA 288 | 3,763 → 3,736 | 60 | 3.2 → 3.5 ms | 0.5 → 0.9 ms |
| NOAA 1834 | 10,000 | 7 | 82.5 → 83.0 ms | 0.1 ms both |
| Our Flag 48 | 1,247 | 17 | 0.5 ms both | 0.2 → 0.3 ms |
| Fed 67 | 857 | 19 | 0.5 → 0.6 ms | 0.3 → 0.4 ms |
| Magazine 2 | 190 → 138 | 138 | 0.5 → 1.0 ms | 13.0 → 1.7 ms |
| Magazine 22 | 7 → 6 | 181 | 0.4 → 0.7 ms | 25.3 → 11.9 ms |
| TechPort 1 | 23 | 59 | 0.2 → 0.5 ms | 0.6 → 0.9 ms |

Crop growth on the magazine's text-heavy pages is faster than the baseline's, not slower: on `34914f5` the
baseline spends 13.0 ms on page 2 and 25.3 ms on page 22 growing crops that swallow the page, and the candidate's
split crops cost 1.7 and 11.9 ms. The four busiest pages were measured alternating the two binaries over two warm
rounds, which agreed to 0.5 ms.

The reader pays for the union over a form's own paints (`tools/readtime.swift`, best of five): FAA 448 220.7 →
220.5 ms, FAA 226 29.5 → 28.9 ms, NOAA 1834 26.2 → 26.1 ms, magazine 2 1.0 ms both.

Whole conversions (lane timings, same machine): FAA 48.4 → 47.9 s, NOAA 127.9 → 127.7 s, Wallace 28.8 → 26.4 s,
9/11 13.6 → 15.4 s, CDC 12.9 → 12.8 s, Census 5.9 → 5.8 s, Fed 5.4 s both, magazine 5.2 → 4.9 s, TechPort 0.4 →
0.3 s. Differences are within this machine's run-to-run spread.

## Remaining gaps

- The magazine's page-8 sand-fly caption (26 words), page-9 fly-photo caption (14), page-19 water-sampling caption
  (38), page-5 mosquito captions (24) and page-2 signature box (19) stay inside their crops: each sits inside the
  photograph or inside a drop-shadow frame that overlaps it, with no band of its own.
- Page 16's drop cap is a filled outline that overlaps the first three lines of its paragraph, which it keeps.
- TechPort's page-2 and page-3 sidebars (58 and 24 words) hold labelled fields and a TRL chart rather than blocks
  of running text, and its page-4 tables (62 words) are neither shaded rows the table reader accepts nor a panel.
- NOAA's photo-and-chart pages still keep the review signal (#117's gap); this change did not revisit it.

## Defects to file

1. ~~**Shadowed text is extracted twice.**~~ Withdrawn: fixed upstream by #165's exact-overprint rule before this
   change landed on `73cbdfe`. The magazine's shadowed captions and pull quotes are drawn twice at an identical
   `Tm`, which `withoutOverprints` already removes, and the candidate's non-whitespace total now sits below its
   source layer (69,629 of 70,247) rather than 1,869 above it. Do not re-file this and do not widen the rule to
   tolerate an offset: measured over the corpus, a 0.35 em tolerance would newly remove only a running foot and
   four Blue Book OCR fragments (see "Before and after").
2. **A page's running foot is drawn twice.** Page 23 draws `Agricultural Research l November/December 2012` twice,
   0.17 pt apart and 12.33 against 11.98 pt tall, so #165's exact-overprint rule keeps both and the furniture
   ledger removes only the draw it recorded: the page prints its foot once in the reflowed text. Expected: one
   foot, whatever a page draws twice. (Widening overprint removal to a tolerance is measured and rejected above;
   the fix belongs in furniture removal, which could take every draw of a line it removes.)
3. **A pull quote becomes a heading.** Pages 11, 12 and 14 set their pull quotes at 15 pt over the body's 10.5 pt,
   so each line is a heading and enters the navigation. Expected: an `<aside>` or `<blockquote>`, or at least
   prose.
4. **Three-column pages read row by row.** The index (pages 22 and 23), the boxed-title articles (20 and 21) and
   several DWFP pages reflow every word but interleave their three columns, and TechPort's gallery captions
   interleave the same way (#153 covers two columns).
5. **The TechPort header band repeats on every page.** Its three lines are now text, but furniture removal does not
   recognize an 87-point band as a running head, so the division, title and state repeat five times (#166 asked for
   a repeated header or a single title).
