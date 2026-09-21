# A column that runs on into a wider measure

The rule was written on `9975bbc` and the measurements that shaped it were taken there. It was
then merged with main at `4d5d86d`, which had taken five fixes in the meantime — #256, #258, #257,
#123 and #130 — three of them in the paragraph and block paths this change feeds. **Every count in
"Before and after", "The rule, and what it is guarded by" and "Verification" below was re-measured
on that merged tree, against a baseline binary built from `4d5d86d` itself**, and the paragraphs
of narrative that describe how each condition was arrived at name the base they were measured on.
macOS 27 arm64, full Xcode throughout.

The subject is corpus `usda-ars-agresearch-2012-11` — *Agricultural Research*, Vol. 60, No. 10,
November/December 2012, USDA Agricultural Research Service, cached as `November-December2012.pdf`,
SHA-256 `2673d1fded74ad89c8b5c59dc325c7884601e1aca5b5755b15a105c1f5b0d761` — printed pages 6 and 17,
raised as [#174](https://github.com/vocaro/PDFReflowLib/issues/174) out of #153. The record that
issue cites, `measurements/column-margin-order/record.md`, was written on the abandoned
coordination branch `claude/fable-agents-coordination-d95da7` and is not reachable from `main`
([decision 0005](../../doc/decisions/0005-abandoned-coordination-branch.md)); the geometry below
was measured afresh.

`tools/dump-order.swift` prints the elements each page hands `LayoutReconstructor.ordered` and the
order it returns them in. It is diagnostic extraction only — no converter output, no crops, no
rasters. Build it beside the library files it calls and run it from the repository root:

```sh
swiftc -O Sources/PDFReflowLib/{AnchorMatcher,BlockAssembler,CGPDFObjects,CJKText,\
ChapterBoundaryReader,ContentStreamWalk,ConversionTypes,ConversionWarnings,DocumentEvidence,\
DocumentModel,EmbeddedImageReader,EnglishText,FractionRegionDetector,FurnitureDetector,\
GlyphIdentityReader,GlyphIndexDecoder,GraphicsReader,HyphenRepair,ImageContentClassifier,\
LayoutReconstructor,MarkedTextReader,NativeSpacingOwnership,NativeSpacingReader,NativeTextReader,\
NumberedNoteDetector,OCRReader,OCRTextCoverage,OutlineReader,PDFPageSource,PageDiagnosis,\
PageRasterizer,PageReader,PageTypography,RecognitionPolicy,ReflowDocument,SourceMetadata,\
StructureTreeReader,TableRegionDetector,TextEncodingCheck,TextLayerPlausibility,TextLineGeometry,\
XMLText}.swift \
  measurements/column-run-order/tools/dump-order.swift -o /tmp/dump-order
/tmp/dump-order corpus/cache/November-December2012.pdf 6,17 /tmp/order.json
```

## What the two pages print

Both pages are set on an 11-point page body (the document body is 11 too) in 10.5-point type on
12.5 points of leading, so every line rectangle is 13.8 points tall and **consecutive rows in one
column overlap by 1.3 points**. That is the first half of the defect: no horizontal whitespace
band exists anywhere on either page, and `ordered`'s horizontal cut needs 1.1 bodies of it.

**Page 6** sets three columns — x 36–208, 220–392, 404–576 — from y 759 down to y 516, and then
the third column runs on into a measure spanning the second and third, x 314–576, from y 517 down
to y 386. Below and left of it stands an L-shaped picture frame, cropped at x 36–299, y 53–508.
The run-on line and the column line above it are the load-bearing pair:

| | x | y |
| --- | --- | --- |
| third column, last line (`deterrent effects of callicarpenal and`) | 404.2–576.1 | 516.3–530.1 |
| the measure it runs on into (`looked at an efficient synthetic approach…`) | 314.3–576.4 | 502.9–516.7 |

The run-on starts 89.9 points to the left of the column it continues, inside the gutter that
column shares with the second (which ends at x 392.2), and its top stands 0.4 points **above** the
bottom of the line it follows. So no straight vertical gutter crosses the page — the run-on
bridges the one at x ≈ 398, and the picture frame bridges the one at x ≈ 214 — and no horizontal
band crosses it either. `ordered` made no cut at all and fell back to its page-wide row-major
sort.

**Page 17** is the same defect the other way up. Its first column (x 36–208) is separated by a
straight cut at x ≈ 214 and was always correct. In what remains, the second column (x 220–348)
runs on into x 220–576 for eight lines (y 338–441) between two pictures cropped at x 360–576, and
then returns to x 220–348 below the lower picture. The wide band hides the gutter at x ≈ 354, so
that group too reached the row-major sort.

## Before and after

Reading order of the reflowable elements, by their measures, top of the page first. `*` marks the
elements that reached the row-major fallback.

| | `4d5d86d` | the fix |
| --- | --- | --- |
| page 6 | `*` rows woven across all three columns: line 1 of column 1, line 1 of column 2, line 1 of column 3, line 2 of column 1, … for 55 rows, then the run-on measure, the captions and the pictures | column 1 (18 lines), column 2 (18), column 3 (19) and its run-on measure (10), the upper caption (4), the left picture and its credit, the lower caption with the right picture and its credit |
| page 17 | column 1 (55 lines, from the straight cut); then `*` the photo credit, the upper picture dropped into the middle of column 2, and the upper caption's four lines woven between column 2's lines at y 440–504 | column 1 (55); the credit, upper picture and its caption (4); column 2 entire — its own measure (25), its run-on band (8), its measure again (19) — then the lower caption, the lower picture and its credit |

On page 6 the article's sentences now run on as printed: `…have developed entirely new classes of`
→ `insecticides out of the DWFP program,` across the first gutter, `…significant repellency
against mosquitoes` → `and ticks. (See…` across the second, and `…deterrent effects of
callicarpenal and` → `looked at an efficient synthetic approach…` into the run-on measure. Before
the fix none of those three joins was adjacent in the output.

## The rule, and what it is guarded by

The fallback is reached by every group the cuts cannot separate, including every ordinary
single-column group, so the rule had to be evidence-led rather than a replacement. It chains the
group's elements into **runs** — each element joins the run standing directly above it, sharing at
least half of the narrower measure and separated by at most a body — and places the runs by the
same row-major comparator, read off each run's own rectangle rather than off its lines. A
single-column group chains into one run and is returned unchanged.

Four conditions gate it. Each of the last three was added because the measurement before it showed
the rule reaching pages it had no business reaching, and each is stated in the terms the cuts
already use:

1. **A run-on measure the run keeps, below a measure it kept.** Some run must widen, part way
   down, by more than a body into a measure another run holds. The widening must be a text line
   of at least twelve bodies — the substance the narrow-gutter cut already demands — and all but
   a body of it must be held by at least two of the run's elements below, and by none of the two
   above. Page 6 keeps the wider measure for ten lines and the narrower for nineteen; page 17,
   eight and twenty-five.
2. **No run of one.** Every run must hold at least two elements. A run of one is an element the
   chaining failed to place, and it is the signature of a group whose rows the page means to be
   read across.
3. **Every run is substantial.** Each run must hold a picture, or at least two text lines of
   twelve bodies — again the narrow cut's own substance test, for its own reason: a stack of
   short cells is a table's column.
4. **The runs stand apart.** No element of one run may touch an element of another. Runs that
   never touch are columns, and reading one out whole before the next is what a reader does with
   them; runs whose elements share a row are that row, however the chaining divided them.

The measurements that forced each one, all of them taken on `9975bbc`, where the rule was
written:

- Condition 1's first half alone changed 12 of the 115 captured layout fixtures. **Condition 2**
  removed eight, every one a page whose rows must stay rows and every one leaving a run of one
  behind: the 9/11 report's two flight timelines (pages 50 and 51, where a time stamp PDFKit read
  as its own line stranded a run), its index of names against descriptions (451, 452), a Wallace
  algebra exercise sheet (26), the USGS copper summary's footnote marker (2) and the Fed's figure
  beside its column (46).
- Conditions 1 and 2 together still changed seven of the algebra book's fifteen spine documents
  and thirteen of the Blue Book's twenty, so the whole-book comparison, not the fixtures, found
  **condition 4**: instrumenting the release converter over the algebra book showed 22 groups
  firing, and their signature is a run standing inside another run's rows — a worked example's
  annotation beside its own working, a figure's labels inside the paragraph that introduces them,
  a column the chaining split in two.
- Instrumenting the widening itself then showed what 18 of the algebra book's remaining firings
  were: `above=84..217 below=84..510`, over and over. That is a paragraph's short last line
  followed by the next paragraph's full-measure first line — a widening in the same shape as a
  run-on, in a single column. Requiring the **narrower** measure to be kept as well, by the two
  elements above, is the second half of condition 1, and it removed them. It also showed that
  page 17's rule had been firing on such a paragraph break rather than on its real run-on, which
  the "kept" test had been missing by 0.05 pt of right edge; measuring "keeps" as all but a body
  of the widening fixed that.
- **Condition 3** came from the last whole-book comparison: the 9/11 report's list of
  illustrations sets its page numbers in one stack against their titles in another, and reading
  those as columns gave `p. 15 p. 15 p. 32–33` ahead of three titles. The census report's table
  of experiment names against their results went the same way. Both stacks are short cells, and
  neither survives the substance test.

With all four, and re-measured on the merged tree against a `4d5d86d` baseline, three of the 119
captured layout fixtures change: pages 6 and 17, and FAA handbook page 365, whose two columns the
row-major sort shredded line by line — its headings, sentences and bullets alternated between the
columns mid-phrase — and whose paragraphs the rule now keeps whole. That page prints a paragraph
across its own gutter, so it is the same defect; the improvement is real but is not claimed by
#174, and the columns' blocks still alternate there.

The merge narrowed the rule's reach rather than widening it. Against the `9975bbc` baseline the
algebra book moved one of its fifteen spine documents, and the Blue Book, the 9/11 report and the
census report each moved one or none; against `4d5d86d` all four are byte-identical. #123's
leading rule and #130's line-size and centred-line rules change the geometry of exactly the pages
where this rule was closest to its thresholds, and on the merged tree it no longer engages there
at all.

## Verification

Five `ReadingOrderTests.swift` tests carry `.bug(…/174)`: the two source pages against new layout
fixtures `usda-6` and `usda-17`; straight-cut controls from the FAA handbook (511), the Fed (54)
and the climate assessment (1056); a synthetic table whose one spanning row must not be read as a
column running on, and whose short-celled twin must not be either; and a synthetic worked example
whose annotation stands inside its own working's rows. The worked example was checked by removing
condition 4, which makes it fail; the short-celled table was what condition 3 was written against,
and adding that condition changed its outcome. The pre-existing controls — the FAA's columns, the 9/11
appendix's narrow gutter, the spanning-heading and figure cases — are unchanged, as are 116 of the
119 captured layout fixtures. 520 Swift tests and every `--fast` gate pass on the merged tree.

The corpus lane passes all eighteen cases on the merged tree, first time, and its result was read
case by case from the JSON each case writes rather than from the run's exit code: all eighteen
report `runPassed: true`. (Before the merge, on a machine other agents' gates were loading, the
same lane twice reported four failures that were the memory gate alone declining to trust a
measurement — conversion exit 0, structural check passed, EPUBCheck 0, content contract passed —
and rerunning those four serially passed them. Main has since given the lane its own handling of
a loaded host, `--memory-attempts` and `--settle-seconds`, and an exit code 3 that says so.) The
magazine case now pins both pages' reading order as `orderedText`: seven phrases on page 6 and
eight on page 17, each crossing one of the joins the weaving broke.

Twenty-three of the twenty-four cached sources were converted twice, once with the merged binary
and once with a baseline built from `4d5d86d` itself, packaging pinned
(`--package-identifier urn:uuid:00000000-…-000000000000
--modification-date 2026-01-01T00:00:00Z`), and the spine text compared document by document.
Seventeen are identical. Six move:

| | mid-sentence paragraphs | spine documents changed |
| --- | --- | --- |
| the magazine | 351 of 573 → 325 of 551 | 2 of 3 |
| FAA handbook | 981 of 5,525 → 900 of 5,450 | 5 of 34 |
| climate assessment (NOAA NCA5) | 3,297 of 14,872 → 3,288 of 14,862 | 4 of 132 |
| NASA ground-wind-loads paper | 295 of 358 → 294 of 357 | 1 of 2 |
| IRS Publication 596 (Chinese) | 88 of 247 → 88 of 251 | 3 of 4 |
| The Fed Explained | unchanged | 1 of 6 |

Paragraphs that end mid-sentence are the signature the weaving leaves, and no book ends more of
them than before. The climate assessment's change is the clearest to read: its contributor list
is set in two columns, and the old order wove them, so `Andrea McCarrick, Scientific Technical
Editor, North Carolina State` was followed by `Jamie Genevie, Senior Associate, ICF` and then by
`University`. Each name now keeps its role and its institution. Publication 596's count does not
move because the measure asks whether a paragraph ends in a letter, which every Chinese paragraph
does; reading it instead shows the EITC sidebar (`有没有在线帮助？`) whole rather than split across the
body column. The Fed's one change moves a preserved region 37 words earlier on its page.

The Warren report is the twenty-fourth source and is not compared: its conversion writes a 531 MB
EPUB and was killed twice by host memory pressure from other agents' gates running on this
machine. It is excluded from the corpus lane for its own reasons
(`measurements/image-encoding-default/record.md`).
