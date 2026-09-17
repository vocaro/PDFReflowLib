# Headings below columns, stacked sections and Roman front-matter folios (#103, #105)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, Xcode 27.0, release CLIs.
Diagnosis ran on `36c6265`. The change was then carried onto `d333b4d` (after #106 `9116393`, #95/#71
`3fcc218` and #104) by fast-forwarding and re-applying the same patch, which applied cleanly. Every figure
below compares an unmodified `d333b4d` release build with this tree.

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline | `d333b4d` | `5390c43c…` |
| candidate | `d333b4d` plus this change | `45d60756…` |

Corpus: `dga-2025-2030` (`corpus/cache/DGA.pdf`, `c34f1bec…`) and `faa-phak-8083-25c`
(`corpus/cache/faa-h-8083-25c.pdf`, `247929ca…`). Fed, 9/11 and Our Flag serve as controls. Pinned
conversions used `--package-identifier urn:uuid:00000000-0000-4000-8000-000000000001 --modification-date
2026-01-01T00:00:00Z`. No PDF or EPUB is committed.

## Diagnosis

Layouts were captured with `tools/capture-layout-fixture.swift` (tags applied where they validate) and
replayed through `LayoutReconstructor.blocks`, with a temporary trace of the spatial and tag-ordered
element sequences. Pages were read against `pdftoppm` renders.

**DGA page 4: the spatial cut, not the tag order.** The pipeline reflows this page without graphics
(its text overlaps a page-sized graphic: `unverifiedTextLayer`, reference image). The `+` bullets are
not list lines, so their paragraph groups keep their tags. The `- Vegetables` / `- Fruits` sub-items
are list lines, so their groups fall back (#81) and act as a barrier between tagged runs.
`ordered()` found no gutter (the 18-pt titles span it) and cut horizontally at the widest band.
`Incorporate Healthy Fats` stands 13.89 pt under the columns before it and 13.91 pt over its own
bullets, so the cut below it won by 0.02 pt. In the upper part the title band is cut off first, and the
gutter cut then reads the heading with the left column. The heading has no columns beneath it inside
that region, so `headingBand` cannot claim it. The spatial order was: left column, heading, right column,
sub-items. The tag sort then reordered the uninterrupted tagged run (title, left bullets, heading,
right bullets) by tag order, which put the heading after the right column's last bullet. The untagged
sub-items stayed behind it, giving `…caloric requirements:`, `Incorporate Healthy Fats`,
`- Vegetables`, `- Fruits`. The tags are correct; the spatial cut handed them a heading inside the
wrong run.

**DGA page 9: the spatial cut.** The page stacks four sections. Each is a heading and a full-measure
decorative band over two columns whose bullet flows from the left column into the right. Rows sit
8–11 pt apart, under the 1.1-body (13.2 pt) whitespace cut. The bands hide the gutter and #86's
`spanningFigures` does not move a figure between blocks of columns, so the region fell to the
reading-order sort. The tags repair the first three sections. `Older Adults`' group is rejected (a
short marker in two lines, #91's record), so its one bullet interleaved line by line.
(The first three section titles are inside their band crops in both runs; see *Defects to file*.)

**FAA page 7 (#105): the numeral reading, not position or run length.** Pages 3–15 carry a bare Roman
folio at the foot: `iii`, `iv`, `v` at offset 0 (pages 3–5), then `vii` … `xvi` at offset +1 (pages 6–15).
All sit at 5.2% of the page height except page 13's `xiv` at 2.8%, all 12.3 pt tall and separated from
the text above by 15–441 pt. The baseline emitted every one as a paragraph, not only `viii`. Two paths
remove folios, and neither reads these. The text-group rule normalizes a boundary number only when
`Int(word)` parses, so a bare Roman folio groups with identical text alone and never reaches three pages.
#62's `resolveFolios` does establish the offset run, but by design never removes a bare folio on that
evidence. `folioValue` also refuses one-letter numerals (`v`, `x`), which would split the offset-0 run.

## Change

No public API, option, default or warning code changed.

- **`LayoutReconstructor.trailingHeading`** (the horizontal-cut branch of `ordered()`). After the widest
  band is chosen, the part above it is checked. If everything beneath its lowest band of more than
  1.1 body is one or two heading-type lines, the cut moves to that band, so the heading reads first in
  the part below. Heading type (`isHeadingType`) means at least 1.25 body (the threshold `blocks` uses),
  not monospaced and not a list line.
- **`LayoutReconstructor.headingRow`** (tried after `spanningFigures`, before `bulletColumns`). A
  heading-type line forms a row with the elements overlapping its height, and the row must contain a
  figure (not a tinted box). If nothing else reaches into the row's extent and there is content both
  above and below it, the region is read as above, row, below, and each part is ordered on its own.
- **`FurnitureDetector.collect`**. A line that is only a canonical Roman numeral in 1–400 (`romanValue`,
  one letter included) is a bare folio (`isFolio`). It is keyed `roman-#(offset=N)` beside its text
  group, exactly as a bare Arabic folio is keyed `#(offset=N)`. The existing three-page, band, 0.04
  position and 25% size rules decide it. `folioValue` (head text beside a folio) still requires two
  letters.

Designs considered and not built: breaking the 0.02-pt tie in the band choice (coincidental geometry);
teaching `headingBand` to find a heading below columns (a widowed column-foot heading flowing to the next
column's head would then read after that column); and cutting at any full-measure figure between column
blocks (#86 deliberately leaves such figures in place, since columns may flow around them). The heading
in the row is the evidence of a section break.

## Before and after (`d333b4d` → candidate)

`tools/run_corpus_regressions.py --epubcheck /opt/homebrew/bin/epubcheck --environment-probe <probe>
--execution-context host-terminal --case <id>`, one case per call, then `tools/compare_conversion_runs.py
--allow-different-converters` ([lane-summaries/](lane-summaries/)). Every run passed EPUBCheck and the
progress and memory gates. No memory-gate failure occurred.

| Case | Content checks | Baseline | Candidate | Changed pages | Images, navigation, page markers |
| --- | ---: | --- | --- | --- | --- |
| dga-2025-2030 | 35 | 4 fail (all new) | pass | 4, 9 | unchanged |
| faa-phak-8083-25c | 342 | 3 fail (all new) | pass | 3–15 | unchanged |
| fed-explained-2021 | 147 | pass | pass | none | unchanged |
| gpo-911-2004 | 191 | pass | pass | none | unchanged |
| gpo-our-flag-2003 | 70 | pass | pass | none | unchanged |

Hand review of every changed page ([block-diff-dga-2025-2030.txt](block-diff-dga-2025-2030.txt),
[block-diff-faa-phak-8083-25c.txt](block-diff-faa-phak-8083-25c.txt)):

- **DGA 4**, fixed. `+ Vegetables and fruits serving goals…caloric requirements:`, `- Vegetables: 3
  servings per day`, `- Fruits: 2 servings per day`, `h4 Incorporate Healthy Fats`, then its three
  bullets. The render shows the sub-items indented under the right column's last bullet and the section
  band beneath both columns. Nothing else on the page moved.
- **DGA 9**, fixed (ordering). Before, `Older Adults` produced ten one-line paragraphs alternating
  columns. After, the left column is one paragraph (`+ Some older adults…dairy, meats, seafood,`) and the
  right column another (`eggs, legumes…medical supervision.`). The render shows one bullet flowing
  across the gutter; the break at the column is a separate joining defect (below). The three tagged
  sections are unchanged. The report's `scripts` field changes only because the B12 subscript's context
  is now in reading order.
- **FAA 3–15**, fixed. Exactly one block is removed per page: the bare `iii`, `iv`, `v`, `vii`, `viii`,
  `ix`, `x`, `xi`, `xii`, `xiii`, `xiv`, `xv`, `xvi`. Each page gains `furnitureRemoved` (506 → 519
  warnings). Page 7's render shows `viii` as the contents page's foot folio. Page 16's `1-1` and every
  contents entry are unchanged.
- **Controls with no change**: DGA pages 1–3, 5–8 and 10 (including #91's pages 2, 3, 5 and 8); FAA
  lists and every FAA page past 15; Fed's bullet columns (page 58) and the whole book; 9/11's Roman
  front-matter heads (#62) and the whole book; Our Flag's margin numbers and the whole book.

## Tests and contracts

`Tests/PDFReflowLibTests/DGABulletsAndContentsFolioTests.swift`, six tests. Fixtures are
`dga-4`, `dga-9`, `faa-5`, `faa-7` and `faa-8` (new) and `faa-6-tagged` (existing):

- `dgaHeadingFollowsTheLastBulletsSubItemsAndPrecedesItsOwnBullets` and `dgaOlderAdultsReadsEachColumnWhole`
  are source reproducers, with the page's other headings and tagged sections as controls.
- `headingAtTheFootOfACutReadsWithThePartBelow` reproduces page 4's sequence synthetically. Controls: a
  body-type line, a list line, and a heading without its own 1.1-body band.
- `headingRowWithAFigureSeparatesStackedSections`: controls are no figure in the row, body-type text, a
  figure reaching into the lines above, and nothing below.
- `faaFrontMatterRomanFoliosAreFurniture`: pages 6–8 lose exactly `vii`, `viii`, `ix`; page 5's `v`
  (offset 0, one page) stays; two pages are no run; page 7's blocks keep `Chapter 3`.
- `bareRomanFoliosNeedTheRunBandAndCanonicalSpelling`: one-letter numerals and a folio shifted within the
  band (FAA 13) are removed. Controls: a changing offset, `iiii`, `did`, a line above the footer band,
  and an Arabic folio of equal value.

Negative control ([negative-tests.txt](negative-tests.txt)): with both `ordered()` calls disabled and
`FurnitureDetector.swift` restored to `d333b4d`, all six tests fail (13 issues). Guard mutations
([mutations.txt](mutations.txt), [tools/mutate.py](tools/mutate.py)): removing each of eleven guards
fails at least one test, and `ListContinuation`, `ColumnCut` and `Furniture` tests still pass
throughout. The bare-folio flag's only isolating control is the band-shift case, added after the first
mutation pass survived.

Contracts (`corpus/regressions.json`, [tools/addcontract.py](tools/addcontract.py)): DGA page 4's
`orderedText` extended with the sub-items and the next bullet; DGA page 9's `orderedText` and two
column `paragraphs`; FAA `absentText` for `viii` (7), `xiii` (12) and `xvi` (15), numerals no word on
those pages contains. The baseline fails exactly these (DGA 4, FAA 3) and nothing else.

## Verification

- `swift test`: 480 tests pass (474 at `d333b4d` plus 6).
- `scripts/check-all.sh --fast`: exit 0 (480 Swift, 204 Python, 8/8 concurrency processes, fixture
  repeats byte-identical, 13 policy conversions and 22 rejection/cleanup cases).
- Corpus lane: the table above.

## Defects to file

1. **Prose does not continue from one column's foot to the next column's head on the same page.**
   DGA page 9, `Older Adults`: the left column ends `…dairy, meats, seafood,` and the right column opens
   `eggs, legumes…`, one sentence, but they are two paragraphs. Expected: one bullet. Tagged sections
   are joined by their tags; untagged prose has no within-page cross-column join (row joining, prose
   branch).
2. **Section titles inside their band crops** (DGA page 9). `Young Adulthood`, `Pregnant Women` and
   `Lactating Women` span x 36–159, and their decorative bands start under them at x 103–104.
   `graphicsWithLabels` expands each band's crop over the title it touches (crop from x 34), so the titles
   are image-only and absent from the text and navigation. `Older Adults` ends at x 126.0, 0.9 pt clear
   of its band at 126.9, and survives. Expected: headings over their bands (figure crop bounds).
