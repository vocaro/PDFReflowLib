# Regression testing

Regression coverage across PDF types is the first development priority. Fixes to extraction,
layout or rendering require both a reproducer and positive controls from other layouts.
A valid EPUB can still contain incorrect text, wrong reading order or unreadable images.

## Gates

- `scripts/check-all.sh --fast`: Swift extraction/model/raster/EPUB tests, Python tool tests,
  six small fixture conversions, and a [repeat-run identity](#repeat-run-identity) check that
  converts each fixture twice. No external PDFs are required. The raster tests inspect
  pixels, including crop origins, rotations, annotations and resource ceilings. Preserved-region
  tests also inspect fraction bars, raised exponents and all six cells of a ruled table in actual
  EPUB images at 72/144 DPI, with surrounding-prose and code controls.
- `scripts/check-all.sh --corpus`: the same checks plus 15 complete PDF conversions,
  sequentially, with EPUBCheck, monotonic progress, pinned source identities, memory budgets
  and reviewed page-specific content contracts. All selected cached sources and EPUBCheck
  are required; missing data fails explicitly. The evaluator does not download anything. The lane
  then runs the [repeat-run identity](#repeat-run-identity) check on Fed Explained, Our Flag,
  the CDC comic and Replay Clocks.
- `tools/check_corpus_content.py --case <id> --evaluation <directory>`: run the content contract
  against an existing complete evaluation without reconverting. This is an additional content
  check, not a replacement for the evaluator's EPUB/resource checks.
- `tools/run_corpus_regressions.py --converter <CLI> --epubcheck <executable> --output <new-directory>`:
  run the corpus lane directly. Repeat `--case <id>` to narrow a debugging run; the summary
  lists omitted cases explicitly. A failing case does not hide subsequent results.
- `tools/compare_conversion_runs.py --baseline <evaluation> --candidate <evaluation> --output <json>
  [--allow-different-converters] [--detail]`: compare two probe-backed evaluations of one case
  page by page ([comparing conversion runs](corpus.md#comparing-conversion-runs)). Generated
  identifiers are normalized, so removing one paragraph reports that page rather than every later
  page; pages that differ only in ids, and image assets renamed without a byte change, are
  counted separately (`idOnlyShifts`, `imageRenames`; `--detail` lists them).

Fetch originals explicitly with `tools/fetch_corpus.py --case <id>`. Downloads are cached and
checksum-verified. Publisher-blocked downloads require an owner-supplied matching original;
see [corpus instructions](corpus.md). Large originals and output EPUBs remain gitignored.

### Inspecting large outputs

The content inspector defaults to at most **10,000 ZIP entries and 536,870,912 total
uncompressed bytes (512 MiB)**. For an existing evaluation with a reviewed content contract,
explicitly set `--max-entries 20000 --max-uncompressed-bytes 4294967296` to admit up to
20,000 entries and 4 GiB. Both flags are optional, independent, inclusive ceilings; values
must be positive integers no greater than Python's `sys.maxsize`. There is no unlimited value.
Invalid CLI values exit with status 2; an archive exceeding either ceiling fails inspection.

Python callers can pass the same keyword-only `max_entries` and `max_uncompressed_bytes`
arguments to `read_pages(path, ...)` or `check_evaluation(case, contract, directory, ...)` in
`tools/check_corpus_content.py`. Existing callers keep the defaults. Limits are checked before
reading package/chapter contents, and all duplicate-entry, page-boundary, image-presence and
content-contract checks still apply. ZIP metadata is read when the archive opens; chapters
are parsed individually and page content accumulates in memory. These are admission ceilings,
not process-memory budgets or general EPUB security/conformance validation.

The [large-inspection evidence](../measurements/large-epub-inspection/record.md) exercises
NOAA-scale synthetic data and both retained full NOAA EPUBs with explicit limits. NOAA still
has no passing default-budget content contract: larger inspection ceilings do not change
conversion policies, routine corpus exclusions, or fidelity qualification.

## Repeat-run identity

Conversion must be a function of the source, the options and the converter binary.
`tools/check_reproducibility.py` converts each selected source twice with one binary, pinning
`--package-identifier` and `--modification-date`, and fails on any difference that Vision
cannot explain:

```sh
python3 tools/check_reproducibility.py --converter .build/release/pdf-reflow \
  --output /tmp/repeat --case fed-explained-2021 --case gpo-our-flag-2003
python3 tools/check_reproducibility.py --converter .build/release/pdf-reflow \
  --output /tmp/repeat-fixtures --fixtures [--mode sequential] [--keep-epubs always]
```

`--case` verifies the cached PDF against the manifest; `--pdf` accepts any file. The converter
and source are hashed before the first launch and after the last exit; a change refuses the case
("converter binary changed during the check") rather than comparing two builds, the likely
origin of the unreproduced #68 report. Rules, in order:

1. Both conversions must exit 0. Their reports must be equal except `outputURL`, and warnings
   on pages other than `ocrUsed` pages must match exactly, in order. The set of `ocrUsed` pages
   must be the same in both runs.
2. Byte-identical EPUBs pass (every result so far). Otherwise the check compares the packages:
   every non-content ZIP entry (images, CSS, container, mimetype) byte for byte, ZIP entry dates,
   compression, attributes, order and archive comment; `package.opf` with spine-document items
   removed; spine document heads; and the spine body markup, concatenated and split at page
   markers with same-book file names stripped from links, page by page. Navigation entries are
   compared by target and text.
3. Markup and navigation differences on pages that are `ocrUsed` in both runs, their warnings,
   and a spine packing change that accompanies them are allowed and listed in
   `allowedDifferences`. Everything else fails, naming the page or entry (for an image, the pages
   that reference it). An image on an OCR page is not exempt.

Both conversions launch together by default (`--mode concurrent`): this halves wall time and
also exposes any dependence on concurrent processes (shared staging, services under load), which
is itself a defect. `--mode sequential` is available; on `b9efcc9` both modes gave identical
bytes on every book tried. Passing cases keep reports, logs and `result.json` but delete their
EPUBs (`--keep-epubs failed` is the default). Cost: about 2 s for the six fixtures in every lane
and about 22 s for the four corpus books in `--corpus`.

Both runs launch the same file name and so inherit one Vision model cache. Each `result.json`
records it as `visionModelCache` (executable name, compiled-program fingerprint before and after,
and `changed`). A binary launched under another name, such as a renamed copy, uses a different
cache and can transcribe OCR pages differently (#94); the repeat check does not cover that, and
a pass says nothing about another name's compile.

What this does not prove: determinism across machines, OS or Vision versions, other options,
or other books; that OCR text is stable (OCR pages are exempt by design, so the exemption can
hide a non-Vision defect confined to those pages); or that two runs under different scheduling
than tested agree. Nesting of navigation lists is not compared when bytes differ (heading levels
are, in the page markup). Evidence and negative controls on real output are in
[the reproducibility record](../measurements/reproducibility/record.md).

## Current content coverage

[corpus/regressions.json](../corpus/regressions.json) has 1116 targeted checks on 251 reviewed pages
across 15 documents: FAA, algebra, 9/11, The Fed Explained, Dietary Guidelines, Our Flag, the CDC
comic, Blue Book, and the seven #30 cases (USGS copper tables, Loper Bright footnotes, the Census
unmapped-encoding report, the USCIS Arabic guide, IRS Publication 596 in Simplified Chinese, and
the NBS and Replay Clocks academic papers). They comprise 340 ordered-text, 94 text, 149 paragraph,
97 absent-text, 108 heading, 24 absent-heading, 30 list-item, 17 script, 11 footnote, 27 note-link,
28 paragraph-continuation, 1 list-item-continuation, 5 paragraph-separation, 23 distinct-paragraph,
84 image-presence, 57 warning, 1 absent-warning, 12 source-region, 3 glyph-structure,
3 image-appearance and 2 table-cell checks, counted as `tools/check_corpus_content.py` counts them. All source-page
anchors must also remain complete and ordered, and semantic text must contain no image attachment placeholders.

The checks preserve selected correct words, paragraph semantics and cross-page continuity, paragraph/list order, license attribution, image
presence, source-region content, glyph-level equation and table structure, image scale/contrast/color
and explicit transcription/fallback warnings. They read the actual EPUB spine, track
page boundaries inside styled text, preserve ownership across chapter-file continuations, and
exclude navigation/captions from source-text matching. They do not freeze serialization details
or broken output such as interleaved columns and flattened exponents.

`continuedParagraphs` (`{"end", "next"}` phrases that must share one paragraph element across the
page marker) and `separateParagraphs` (the same shape, which must not: both phrases have to exist
as paragraph text, and no element may carry the first on page N and the second on page N+1) cover
cross-page continuity in both directions, so a page folio that absorbs the next page's text fails
the separation check while the body paragraph's own continuation check protects the real join.

`listItems` and `continuedListItems` are the same two assertions for `<pre>` list items: one item
element must hold a whole phrase, and one must end page N with the first phrase and carry the
second on page N+1. Both read `<pre>` identities, which `continuedParagraphs` does not see, so a
list item that regressed into a paragraph fails the list check rather than quietly satisfying the
paragraph one. See the [list-continuation evidence](../measurements/list-continuations/record.md).

The checker has negative controls for deleted text, text moved to the wrong page, reversed order,
missing images, flattened or misplaced superscripts/subscripts, missing/wrong-page warnings, changed source identity, failed conversion, missing
or duplicate page markers, split or wrongly joined paragraphs across a page marker, and captions
masquerading as source text. A list of assertions without such controls could silently pass
despite a broken checker.

Image-presence checks are weaker than visual fidelity checks. They cannot prove a flag's colors,
a diagram's arrows or mathematical notation is correct. Unit pixel checks, source-image review and
the source-region, glyph-structure and appearance checks below cover selected rendering behavior
on selected regions; robust visual/semantic contracts still need expansion. The corpus
lane does not supply a whole-book quality score or physical-device performance qualification.

Full Warren and NOAA conversions remain explicitly excluded from this successful-conversion lane
because of the known image-output ceiling failure (#5). The pinned Warren excerpt separately
checks its two textless pages. These exclusions are listed in output, never counted as passes.
The manifest consistency test requires every corpus document to be covered or explicitly excluded.

## Source-region image checks

Preserved tables, equations, figures and page fallbacks are images, so text checks cannot see their
content. An `imageRegions` expectation names a committed reference under
`corpus/references/<case>/`. `tools/render_region_reference.py` renders a reviewed source region
(PDF points from the page's top-left) with Poppler at 180 DPI after verifying the source identity,
averages it to 36 DPI grayscale, trims it to ink and writes a sidecar with the region, renderer and
source checksum. Choose regions from the source page, never from converter output.

The checker averages every image on that page the same way at all 25 grid phases and searches all
placements for the highest normalized correlation (`tools/image_regions.py`). A page passes when
some image reaches `minimumCorrelation`, 0.95 by default. The corpus gate needs numpy and Pillow,
not Poppler. References assume the library's default 180 DPI; a changed raster policy must
regenerate them. A conversion at another `rasterDPI` fails every reference-image check by
construction (see the [raster qualification](../measurements/raster-qualification/record.md)).
`--output-root` writes a measurement-only reference outside `corpus/references`, where it never
enters the corpus contract.

Ten references cover the Our Flag flag-size table, three USGS copper tables, three FAA page-121
figures, a Wallace quadratic exercise, the Geltman page-image fallback and CDC's image-only page 13.
Correct crops score 0.982–0.997. Wrong images on the same pages score at most 0.62, a table crop
with its lower half blanked 0.64, erasing the Wallace exercise from its crop 0.44, and a 1.5-pixel
blur still scores 0.96. The check proves
a region is present, complete and aligned; it does not prove every glyph. Erasing one exponent from
the Wallace exercise still scores 0.97, which is why the glyph-structure check below exists. See the
[image-region evidence](../measurements/image-regions/record.md).

## Glyph-structure checks

A `glyphRegions` expectation names a reference rendered with `--kind glyph`: the same Poppler render
kept at the full 180 DPI with a four-pixel white margin. `tools/glyph_structure.py` aligns it in each
page image (36 DPI search, then full-resolution refinement), labels the reference's connected ink
components, splits them into 16-pixel tiles, and requires every tile's footprint to hold at least
`minimumCoverage` (default 0.4) of the reference ink mass while the window carries at most
`maximumExtraInk` (default 0.12) outside the reference's ink. Ink mass is conserved by blur and
resampling but not by erasure, so a 1.5-pixel blur or a 180→120→180 DPI resample still passes.

Three references cover the Wallace page-343 quadratic-formula solution line (exponent, radical sign
and fraction bar), exercise 35 on page 347 and the USGS Salient Statistics table (932 components).
Correct crops score 0.59–1.05 coverage with under 0.01 extra ink. Erasing the b² exponent scores
0.001, the fraction bar 0.000, the radical's check stroke 0.000, exercise 35's final exponent 0.003
and its minus sign 0.064; substituting the similar preceding line or another exercise fails on both
measures. The check proves each reviewed stroke is present with comparable ink in the right place;
it does not prove legibility (an upsampled 60 DPI crop conserves ink and passes; the reported
`sharpness` cannot separate that from a mild blur, so it is gated only when a contract sets
`minimumSharpness`). See the [equation-structure evidence](../measurements/equation-structure/record.md).

## Image appearance checks

An `imageAppearance` expectation names a color reference (`--kind color`, 36 DPI RGB) or an existing
grayscale region reference. `tools/image_appearance.py` locates it and measures scale (the page
image's pixel size against the reviewed region at 180 DPI, minimum 0.95), ink contrast (2nd–98th
percentile spread, minimum 0.4) and, for color references, color agreement (the fraction of colored
reference samples whose converted hue is within 30° with at least half the chroma, minimum 0.8).
The Colorado flag on Our Flag page 33, FAA figure 5-36 and the USGS statistics table are checked.
Correct crops score 0.98–1.00 scale, 0.55–0.70 contrast and 0.99+ color agreement; grayscale,
channel-swapped, level-compressed and downscaled crops fail (agreement ≤ 0.36, contrast ≤ 0.18,
scale ≤ 0.79). Scale is a pixel-dimension check, not a sharpness measure. See the
[image-appearance evidence](../measurements/image-appearance/record.md).

## Table cell checks

A `tableCells` expectation carries a reviewed transcription (`columns`, `rows` with `label`,
`values` and optional `group`, in the shape of `corpus/usgs-mcs2025-copper-review.json`) and passes
only when a `<table>` on that page maps every column through its header path and every row's cells
equal the expected values under those columns, with group rows preceding their members. Swapped,
shifted or merged cells, missing rows or groups, and tables rendered as prose fail. The Fed's
entity/overview table (page 64) and regulation table (page 83) are the first corpus tables emitted
as `<table>` (#54, shaded rows and rules; other tables remain images under #36/#31) and carry
reviewed transcriptions; `tools/test_table_cells.py` keeps the checker's negative controls, and the
spine reader separates cell text with spaces and parses each table into a grid. See the
[table-cells record](../measurements/table-cells/record.md).

## Adding or changing a regression

1. Reproduce the defect using a pinned source. Add a small original synthetic PDF/operator
   fixture when that isolates the mechanism, and retain a source-derived real-document target.
2. Read the source visually before writing expected text, order, cell values or image properties.
   Do not derive expected correctness from the converter being tested.
3. Prove the test fails on the old behavior. Keep known unresolved defects tracked as GitHub
   issues, rather than blessing them as golden output or disguising them as passing tests.
4. Add positive controls for neighboring behaviors and another document type. For example,
   attachment filtering must retain mixed styled text, blank scans, recoverable OCR and images.
5. Run the synthetic and corpus lanes. Review changed content/image counts; increases and decreases
   can both be suspicious. `tools/compare_conversion_runs.py --allow-different-converters` on
   before/after evaluations lists the changed pages and why (`changedPageFields`), without a
   per-change comparison script. Update expectations only after reviewing the source and explaining
   the intended behavior change. Preserve historical measurement receipts.

[Issue-fix measurements](../measurements/quality-and-raster-fixes/record.md) and the
[cross-corpus content run](../measurements/cross-corpus-regressions/record.md) document current evidence.

## Preserved-region fixtures

`PreservedRegionTests.swift` includes original in-memory PDFs and a small, attributed extraction
of algebra page 17. The JSON fixture contains source text and geometry, not the original PDF or
font programs. It runs offline on both platforms and checks whole-line crop containment, exercise
prefix ownership and selectable instructions. It is an internal test schema, not a public
intermediate-format contract. See [evidence and negative controls](../measurements/preserved-region-regressions/record.md).

The detached-fraction regression is enforced normally: its numerator, exponent and denominator
must share one image, surrounding prose stays selectable and the conversion reports image
preservation. The known-failure wrapper is removed. Ordinary rules, underlines, code, connected
table grids and nearby prose supply negative controls; algebra page 479 supplies source-derived
answer-key fraction checks. See [fraction and OCR-typography evidence](../measurements/fractions-and-invisible-text/record.md).
Future unresolved cases must stay explicit rather than becoming passing golden output.

To recapture the algebra geometry with full Xcode selected:

```sh
swiftc Sources/PDFReflowLib/NativeTextReader.swift Sources/PDFReflowLib/ConversionTypes.swift \
  Sources/PDFReflowLib/DocumentModel.swift Sources/PDFReflowLib/ReflowDocument.swift \
  Sources/PDFReflowLib/GraphicsReader.swift Sources/PDFReflowLib/NativeSpacingReader.swift \
  tools/capture-algebra-layout.swift \
  -o /tmp/capture-algebra-layout
/tmp/capture-algebra-layout corpus/cache/Beginning_and_Intermediate_Algebra.pdf /tmp/algebra-17-layout.json
```

The capture tool rejects any source checksum other than the pinned book. Review source and
geometry changes before replacing the bundled fixture; never regenerate it merely to make a test
pass. The extracted text remains Tyler Wallace's CC BY 3.0 material, with attribution in the
fixture and [third-party notices](third-party-notices.md).

## Thin rules beside prose

`RuleAdjacentProseTests.swift` covers [#36](https://github.com/vocaro/PDFReflowLib/issues/36):
PDFKit line rectangles on tight leading overlap, so one section-label underline, column rule
or inline equation used to absorb a whole paragraph or column through transitive whole-line
expansion. Synthetic USGS-like geometry checks that label underlines and column rules leave
tightly leaded prose selectable, that a row of underlined column headers keeps a borderless
statistics table as one image between reflowed paragraphs, and that a single label underline,
a row of underlined links, a left-margin underlined heading or a subheader with fewer than
three numeric rows is not a table. An original in-memory PDF converts end to end: the
underlined labels reflow as prose in order around one table image of bounded size. Our Flag
page 27 supplies the isolated-rule and dot-leader-table control (three regions, headings
outside them).

Source-derived `usgs-{1,2}` and `nbs-7` fixtures require every USGS prose section outside the
crops, the three tables whole inside crops that fit the reviewed reference regions, and the
Geltman closing paragraph reflowed through "on neutral atoms." with the references untouched;
since #51 the inline-equation line there reflows in its paragraph with no crop at all. Fraction
bars sit like underlines beneath their numerators, so a synthetic bar and algebra practice
page 16 (`algebra-16`, 25 fraction bars, 36 crops) require every bar to keep its terms in one
crop. The first eight tests fail against the previous sources. The corpus contract adds ordered prose,
paragraph, absent-cell and image-region checks on USGS pages 1/2 and NBS page 7. See the
[rule-adjacent prose evidence](../measurements/rule-adjacent-prose/record.md).

## Inline mathematics beside formula and figure crops

`InlineFormulaProseTests.swift` covers [#51](https://github.com/vocaro/PDFReflowLib/issues/51),
[#58](https://github.com/vocaro/PDFReflowLib/issues/58),
[#49](https://github.com/vocaro/PDFReflowLib/issues/49) and
[#77](https://github.com/vocaro/PDFReflowLib/issues/77). A line with an `=` or a mathematical
symbol is a displayed formula unless its row reads as prose on its paragraph's measure; a
formula's margin stops at neighbouring prose and at an instruction line of words alone; a
radical's bar inside a prose row is that row's decoration; and a form's bounding box is figure
ink only where its clip lets it show. Source-derived `algebra-288`, `algebra-289`,
`algebra-291`, `faa-227` and `faa-195` fixtures require Wallace's inline-radical sentences, the
page-289 opening sentence, the page-291 `Simplify.` instruction and FAA's `true course desired.`
outside every crop, while the Example 377 table, the displayed product rule, the page-289
derivations, every page-291 exercise, the compass-rose figure and the page-195 pressurization
figure stay inside crops (page 195 also guards a trimming edge that rounding used to miss).
Synthetic controls keep a displayed equation between paragraphs and a stacked full-measure
display without a sentence preserved, and an original in-memory PDF checks the clipped form box
against the same form unclipped. Seven of the nine tests (with the updated Geltman test) fail
against the previous sources, and removing any one rule fails at least one of them. The corpus
contract adds ordered prose and paragraph checks on Wallace pages 288, 289 and 291, FAA page 227
and NBS page 7. See the [inline-formula prose evidence](../measurements/inline-formula-prose/record.md).

## Shaded boxes and text tables

`TintedBoxTests.swift` covers [#54](https://github.com/vocaro/PDFReflowLib/issues/54): a stroked or
filled rectangle behind prose used to seed a crop that swallowed every line inside it. An original
in-memory PDF checks that `GraphicsReader` records rectangle-only paths outside `/Figure` marks as
frames and everything else as ink. Synthetic Fed-like geometry checks that a sidebar frame holding
prose is a tint whose text reflows (and, without tint removal, still the defect), that a chart
inside a box keeps one full-width band image below the prose with its captions and notes, that
bar charts, flowchart nodes, a frame with too little prose and a ratings grid of short fragments
keep their images unchanged, that shaded rows with rules read as a table with the title outside
it, that section rows and PDFKit-merged letter cells read as spanning and joined cells, that a
ruled table with only a shaded header stays one image, that a box beside wrapped prose reads after
the lines beside it without joining them, and that table blocks serialize as `<table>` with
`thead`, `colspan` and inline styles. `PageStoreTests` reloads tints and separators exactly.

Source-derived `fed-{32,40,58,64,83,120}` fixtures carry the painted footprints (`paints`) as well
as the clustered regions, so `content(tinted: false)` reproduces the crop and `content()` the fix:
pages 32 and 58 reflow as a heading and paragraphs with no crop touching a box line, page 40 keeps
one band image under 260 pt tall holding the chart captions and notes while the box prose reflows,
page 64 reads as a two-column table with its header and seven entities, page 83 reads its header,
four section rows and the merged letter cells, and page 120 continues with a section row and no
header. `tools/capture-layout-fixture.swift` now records `paints`; older fixtures keep their
clustered `graphics` and unchanged behaviour. The Fed corpus contract adds headings, paragraphs,
ordered text, `tableCells` transcriptions for pages 64 and 83, a source-rendered region for the
Box 3.3 charts and the reflowed page-46 sidebar; see the
[tinted-box evidence](../measurements/tinted-boxes/record.md).

## Source-derived fidelity controls

`FidelityIssueTests.swift` checks the FAA page-91/511 columns, all ten Our Flag page-27 table
pairs and both headers, and algebra page-343's inline exponent. Positive controls cover spanning
headings/figures, ordinary prose, dot-leader contents entries, code, ellipses and sparse numeric
rows. The 9/11 page-451 name/description fixture protects row associations from narrow-column
cuts. `ListContinuationTests.swift` covers [#50](https://github.com/vocaro/PDFReflowLib/issues/50)
and [#64](https://github.com/vocaro/PDFReflowLib/issues/64) with Wallace page 40, Fed pages 9, 21,
22 and 58 and synthetic wraps; its controls are Loper Bright page 64 (an indented paragraph under a
wrapped citation must not join it), the Warren synthetic-text list, the algebra page-10 and -26
exercises, the 9/11 page-451 rows and the FAA columns, all of which must not change.
`MarkerPieceTests.swift` covers [#69](https://github.com/vocaro/PDFReflowLib/issues/69) and
[#70](https://github.com/vocaro/PDFReflowLib/issues/70): a marker PDFKit splits from its item's text
(9/11 page 365, FAA page 27's bullets, algebra page 101, Loper Bright page 5's `982.`), a `10.August`
marker with no space among spaced siblings (9/11 page 374), and a line broken after a slash (FAA
page 365's `runway/` + `taxiway`). Its controls are table columns, mid-row and differently sized
markers, minus signs, adjacent marker pieces, decimals, section numbers, times, out-of-sequence or
off-edge numbers, spaced slashes (`China /`) and slashes after punctuation (damaged OCR).
`BaselineStyleTests.swift` checks both native baseline-attribute keys, unchanged small
fonts and noisy positioning, a real PDF-to-EPUB superscript/subscript path, and CDC page-5 OCR
line spacing that must not become inline scripts.
`ColumnCutTests.swift` covers [#47](https://github.com/vocaro/PDFReflowLib/issues/47) and
[#56](https://github.com/vocaro/PDFReflowLib/issues/56): the Wallace page-438 title and section
labels precede all three answer columns, page 471's 7.8 section reads whole before chapter 8, and
FAA pages 165, 199 and 262 read a figure-headed left column before the right one with every
character kept. Each guard has a control that fails when the guard is removed: Our Flag page 34's
row-banded state grid keeps row order (the text-measured gutter waits for the horizontal cut), FAA
page 511 with its folio keeps the left column's tail ahead of the right column, CDC page 26's
two-line speech balloons are not heading bands, and a synthetic figure spanning both columns is
never dropped by a gutter measured over text. See the
[column-cut evidence](../measurements/column-cuts/record.md).
The same file covers [#86](https://github.com/vocaro/PDFReflowLib/issues/86) and
[#78](https://github.com/vocaro/PDFReflowLib/issues/78): FAA pages 340, 401, 108, 439 and 392 read a
figure set across both columns' full measure before or after the complete columns, where its crop
comes within points of the columns (formerly interleaved line by line, or left, right, left, right
across aligned paragraph space); Wallace page 487's stacked answer blocks read block by block and
page 448's row-numbered graph grid reads 15–22 in number order. Controls: FAA 194 and 19 keep a
column figure's caption in its column, Wallace 186/429 worked examples keep their notes, Wallace 449's
column-numbered graphs and the two-to-a-row exercise sets (pages 10, 26, 424) keep column order, and
synthetic layouts isolate the remaining guards (short cells under a figure, a figure between column
blocks, a wide band under a head figure, aligned space in prose columns, a column's own tail). See
the [column-order evidence](../measurements/column-order/record.md).

These small JSONs capture native extraction from checksum-pinned sources, not converter output.
They run offline on macOS and iOS. Capture another page with full Xcode selected:

```sh
swiftc Sources/PDFReflowLib/NativeTextReader.swift Sources/PDFReflowLib/ConversionTypes.swift \
  Sources/PDFReflowLib/DocumentModel.swift Sources/PDFReflowLib/ReflowDocument.swift \
  Sources/PDFReflowLib/GraphicsReader.swift Sources/PDFReflowLib/NativeSpacingReader.swift \
  Sources/PDFReflowLib/StructureTreeReader.swift Sources/PDFReflowLib/MarkedTextReader.swift \
  tools/capture-layout-fixture.swift \
  -o /tmp/capture-layout-fixture
/tmp/capture-layout-fixture faa-phak-8083-25c 91 /tmp/faa-91-layout.json
```

Run from the repository root. The tool verifies the cached PDF against the manifest SHA-256.
Paints wholly outside the crop box are not recorded (`GraphicsReader` drops them; FAA pages 474
and 475 share a two-page illustration, #99), and any other non-finite number stops the capture
with the JSON path of the element instead of aborting inside the writer. Where
the page's structure validates, each line also records the tag the pipeline applies (`structure`,
since #89/#90); older fixtures and untagged lines have none, and `SourceLayoutFixture` restores it.
Source review, baseline failures, cross-document safeguards and full-run evidence are retained
in [the three-fix measurement](../measurements/three-fidelity-fixes/record.md). The suite contains
463 Swift tests with no known-issue wrappers, and 204 Python tests.
The comparison tests include a real-Poppler image URL check through the safe HTTP handler
(simple and positioned modes, paths with spaces); absent Poppler is an explicit skip.

`HyphenFragmentTests.swift` covers [#101](https://github.com/vocaro/PDFReflowLib/issues/101): the
NOAA page-553 and page-284 fixtures join `community-resilience-es-` + `timates.html` once the
continuation `timates` is no longer a book word, with controls for compounds opening a
continuation line, words seen elsewhere, Fed page 27 and prose joins. See the
[hyphen-fragment evidence](../measurements/hyphen-fragments/record.md).

`InvisibleTextTests.swift` covers exclusively hidden OCR text, visible Courier and genuine
font-size headings, mixed text modes, saved graphics state, nested forms and malformed modes.
Warren pages 50/910 supply pinned source geometry; ordinary prose/index entries must not become
code/headings, while source points 10/11 retain list formatting. The nine-page real Warren excerpt
is evaluated separately because the full 920-page conversion remains outside the successful
complete-conversion gate. A passing excerpt does not qualify the complete book.

## Conversion policy coverage

`ConversionPolicyTests.swift` exercises reference policies on inherited text, real Vision OCR,
prose, graphical crops and required page fallbacks. It verifies independent page/region JPEG
and PNG bytes with matching EPUB media types, clean/noisy smallest-encoding choices, unchanged
raster dimensions, invalid qualities, and size-failure cleanup without false completion.

`check-conversion-policies.py` runs actual CLI policy combinations through independent
EPUB structure checks, optional EPUBCheck and the internal reader. Invalid and over-budget
requests must fail without output or completion. Header/footer cases require `prose.pdf`'s
running header to be absent by default and with `remove`, present on all three pages with `keep`,
and byte-identical across two `keep` runs with a pinned identifier and date. Invalid values
must name the accepted `remove` and `keep` values. It runs in `check-all.sh` alongside the six
default fixture conversions. Reader tests check JPEG MIME admission and both ZIP/expanded
byte limits while preserving existing active-content and traversal rejection controls.

## Running headers and page numbers

`FurnitureTests.swift` uses 21 checksum-pinned 9/11 source-layout pages to distinguish running
headers from chapter openings and require every other source line to survive. Controls cover
alternating and chapter-local repetition, sparse occurrences, duplicate page identities, typography
and position drift, adjacent prose, body titles, isolated content, offset page bounds, numeric
chapter-page folios, nearby captions and the public header-retention option. Fallback font estimates
must not make FAA folios reappear. Six additional FAA source-layout pages protect shifted
folios and changed page sizes while retaining every surrounding line.

Corpus contracts support `absentText` for reviewed unwanted text and `headings` for phrases that
must remain semantic headings on the correct source page. Reader tests reject headers reintroduced
into prose, headings flattened to paragraphs, headings moved to another page and empty expectations;
heading parsing retains inline styles and page boundaries, including across spine files.
The 9/11 contract protects chapter titles, source body text and removal of four running-header
examples; FAA page-16/91 folios supply cross-document controls.

The [follow-up header qualification](../measurements/report-header-qualification/record.md) adds
seven 9/11 notes-header contracts and the Fed page-50 chapter-title control. Leading/trailing
folios share repetition evidence only with the same physical-page offset; internal chapter digits
remain significant. Seven source fixtures protect the three-page chapter-12 notes run and neighboring
two-page runs. Three additional source fixtures require detached map labels on pages 33/50/51
to remain wholly inside preserved graphic regions and out of standalone prose/heading blocks.
The retained heading audit reports missed sections explicitly; it is not a passing golden for them.

The top candidate band is the outer fifth of the page, and a second header row beneath a wholly
eligible outermost row is removed only with that row (#40). Six checksum-pinned Loper Bright
pages (96–101) require all three running-head lines (`Cite as: …`/`LOPER BRIGHT …` with the
folio, then `KAGAN, J., dissenting`) to go on every page with every other line retained.

A margin line's boundary page number is evidence in its own right (#62): a run of three or more
nearby pages whose margin folios on one edge share a numeral system, the same offset from the
physical page, the same height in the band and the same type size are running heads even where
no three of them repeat any text. `folioValue` reads Arabic, chapter-prefixed and canonical Roman
numerals of two or more letters in 1–400, so ordinary words (`did`, `mill`, `civil`, `mix`) and
initials are not page numbers, and a numbered `Figure`/`Table`/`Plate` label supplies no folio.
A line that is only a folio is never removed on this evidence alone — a chapter opening's lone
page number is not a running head — unless every other line on its row is removed too.
`911-571`/`572`/`573` are the 9/11 reproducer (three heads that share no text but share offset
−18) with chapter opening `911-126` as the control that keeps its foot folio; `loper-44` … `48`
cover the four-page Thomas concurrence, whose alternating heads occur twice each, with page 48
restarting the numbering for the next opinion as the control.
`folioReadingAcceptsOnlyCanonicalPageNumbers` tests the reading in isolation.

`HeadingTests.swift` requires that a separated margin line opening or closing with a page number
is never a heading, whatever furniture removal made of it, with controls for a head carrying no
folio, a folio-bearing line inside the text block and one the body runs straight into. Corpus
contracts support `absentHeadings` for a line the page still carries that must not be in the
navigation. See the [margin-folio record](../measurements/margin-folios/record.md).
Synthetic controls keep a lone section row 8 pt above the body, a repeated section row beneath
unrepeated titles, a row three line heights below the title row, a repeated opening line that
its paragraph follows directly, and a repeated separated line below the band; the 9/11, FAA and
`prose.pdf` controls are unchanged.

[Local-header evidence](../measurements/local-header-regressions/record.md) includes the failing
baseline, complete corpus receipts and before/after text and image comparisons. Corpus assertions
remain selected contracts, not comprehensive quality scores; inspecting differences also catches
regressions outside those selected pages.

Our Flag pages 34/42/43 additionally protect the alphabetical row order of four illustrated entries
and four retained images per page. The footer candidate band stays at the existing outer 7%;
the header band is the outer 20% since #40 (10% held the 9/11 heads; a slip opinion's sit at
82–85%). Wider footer removal needs independent
layout work before it can preserve this reading-order contract.

Blue Book pages 5/12 provide source-derived synthetic-layer margin controls. Existing repeated
edge-artifact cleanup remains separate from native-header inference; the page-12 corpus check
rejects reintroduced margin noise while retaining body text, its source image and uncertainty warning.

## Heading and paragraph semantics

`HeadingTests.swift` uses ten native Fed pages, including 45/46 to protect prose beside preserved tables and
sidebars. Small-font text inside an image must not promote the surrounding ordinary prose to
headings. Synthetic controls preserve real headings and short titles beside images; 9/11 chapter
openings provide independent source-derived heading controls. Six modest-size Fed section titles
have explicit guards against over-suppression.

`NavigationHeadingTests.swift` (#55) uses the pinned Fed pages 5, 8, 14, 24 and 25, rebuilt from
their attributed runs as the pipeline builds them. The chapter openers 8, 14 and 24 must each
yield one heading (`1 Overview of the Federal Reserve System`, with the fused 70-point numeral at
the title's 24-point size and no subscript) and their pull quote as one paragraph above the
chapter's own dot-leader contents; page 25's two-line section title is one heading; page 5 has
`Contents` as its only heading with the chapter entries as paragraphs. Synthetic controls cover
the merge rule (left-aligned, centred and right-aligned pairs, a colon-ended first line; a chapter
label at another size, a numbered section beneath a title, `Part II` / `Chapter 3`, a
sentence-ending first line, prose between, a wide gap and a different alignment stay separate),
the pull-quote rule (a one-line and a two-short-line sentence stay headings, a two-line title
without terminal punctuation merges), the contents rule (`isContentsEntry` positives and
negatives, a lone heading-size entry) and the display-numeral rule (Fed page 8's runs give
`1 Overview of the Federal` at 24 points; `H<sub>2</sub>O`, `x<sup>2</sup>` and a raised note
marker keep their scripts; a numeral on the title's baseline gains no space; an under-twice
numeral and a lettered initial do not change the line's size). The 9/11 page 19 fixture must
merge `“WE HAVE SOME PLANES”` above its `1.1` label. The corpus contract adds Fed pages 5, 8 and
25; see the [navigation-heading evidence](../measurements/navigation-headings/record.md).

The corpus `paragraphs` expectation requires a phrase inside one actual spine paragraph on the
specified source page. A phrase spread over separate paragraphs, headings or preformatted text
cannot pass. The parser preserves inline styles and page boundaries and excludes figure captions.
Tests deliberately replace prose with headings, split it, or move it to another page to verify
that these checks reject semantic regressions.

## Spine packing and navigation

`SpineWriterTests.swift` covers exact serialized body-size boundaries, many tiny paragraphs,
UTF-8 and escaped text, oversized atomic blocks, source-page/heading navigation, trailing empty
pages, headings kept with their content across size splits, semantic-model preservation, ordered
progress and cancellation. The independent EPUB checker enforces the 60,000-byte body target on
every converted fixture and corpus document; an oversized document may contain only one
indivisible content block, its optional preceding source-page marker and up to 6,000 bytes of
headings kept with it. No spine document except the last may end with such a heading run.
Python negative controls reject multi-block overflow, unwrapped text and separated headings.

Corpus contracts can also require `continuedParagraphs`: one paragraph element must end page N
with one phrase and continue page N+1 with the other. The
[continuity evidence](../measurements/spine-continuity/record.md) lists the reviewed page pairs;
known cross-page splits and folio joins are tracked in [#45](https://github.com/vocaro/PDFReflowLib/issues/45).

This target is an EPUB packing policy, not a limit on individual source paragraphs, whole-document
memory, or a promise that spine boundaries correspond to actual book chapters. See the
[packing evidence](../measurements/spine-packing/record.md).

## Page-bottom footnotes

`FootnoteTests.swift` covers [#40](https://github.com/vocaro/PDFReflowLib/issues/40) with
styled source fixtures (`SourceLayoutFixture.styledContent()` restores the native superscript
runs): Loper Bright page 60 (one note, body ending `that controls.`, marker `Ibid.2` kept in
prose, every source character except the separator retained), pages 97/98 through
`appendPage` and `joinContinuedFootnote` (note 2 is one block from `The majority tries` to
`deferential standard.` with `sourcePages == [98]`, placed before page 98's body and note 3),
pages 99/100 (marker-less continuations admitted only after a preceding note), page 13 (the
detached body marker `1` rejoins `Persistence.` as a superscript and its paragraph runs on),
pages 13/14 (that paragraph continues across the note block under #45's `appendPage`, and the
note follows the joined paragraph behind its marker), a synthetic three-page chain in which a
page that is one continuing paragraph leaves an earlier page's note last, a note continuation
after a body join (no second boundary), and pages 61/101. Thirteen source pages without note typography (Loper 2/7/96, 9/11 20/472/532,
algebra 26, FAA 211, Fed 45, Our Flag 27, Warren 910, NBS 7, USGS 1) yield no footnotes.
Synthetic controls refuse a missing size drop, a missing first marker without a preceding
note, `* * *` and two-dash separators, fewer than three body lines, non-sequential or
non-numeric markers, a body-size, monospaced, tagged, displaced, shifted or image element after
the separator, and recognized or synthetic text layers, retaining every character. The writer
test pins `<div class="footnote" role="doc-footnote"><p>…</p></div>` with an inline page
marker and the stylesheet rule; an original two-page PDF with a text-rise marker converts end
to end through PDFKit into two notes joined across the page. Detached-marker controls keep
letters, four digits, body-size digits, distant, overlapping and same-baseline numbers as
separate lines.

`FootnoteTests.swift` also covers [#61](https://github.com/vocaro/PDFReflowLib/issues/61), the
table notes a document sets with no rule above them. USGS copper page 2 yields nine note blocks
in source order (`eEstimated. — Zero.` through note 8, which absorbs its two unmarked
continuation lines); only the numbered notes carry a page-scoped `NoteKey`, the body prose
ending `heat exchangers.` stays body text, the running foot below the block stays prose, and
every source character survives. Synthetic controls refuse a single note, markers that do not
count up, markers that are only letters, a block that is not set off by white space, a block at
or near the body size, a block indented from the body's column, more than a page foot below the
block, a raised marker on a line above the block, and recognized or synthetic text layers.

Corpus contracts support `notes`: a phrase must sit inside one footnote block on that page,
and the same text in ordinary prose or on another page cannot pass. `distinctParagraphs` names
two passages that must open separate paragraphs on one page; `paragraphs` matches a phrase
inside any paragraph, so it cannot see a run-in label swallowed by the paragraph above it.
The Loper Bright contract
adds footnote, separator-absence, running-head-absence, marker-context, note-continuation and
`furnitureRemoved` checks on pages 13, 14, 60, 61, 97 and 98, including the page 13→14 body
continuation (page 13's note is checked on page 14, where it follows the joined paragraph); the
converter before #40 fails 36 of them. The USGS copper contract adds the three note phrases,
the two note links on page 2 and five `distinctParagraphs` pairs across both pages; the
converter before #60/#61 fails nine of them. See the
[page-footnote evidence](../measurements/page-footnotes/record.md) and the
[section lead-in evidence](../measurements/section-lead-ins/record.md).

## Bold run-in section labels

`SectionLeadInTests.swift` covers [#60](https://github.com/vocaro/PDFReflowLib/issues/60). USGS
copper page 2 opens `World Mine and Refinery Production and Reserves:` and `Substitutes:` as
their own paragraphs although the source sets about 0.3 pt between sections, while the Events
section still carries the COMEX paragraph, whose opening line has no bold label: the rule is not
a change to the paragraph-spacing threshold. Page 1 splits `Import Sources (2020–23):` past the
raised `5` that ends the sentence above it, and `Government Stockpile:` from `Depletion
Allowance:`. Synthetic controls keep one paragraph for ordinary bold emphasis, a colon label
that is not bold, a label after a line that does not end a sentence, a label indented inside the
column, and a label set at the leading the paragraph already wraps at. Six source pages that
carry bold emphasis, bulleted definitions, box run-in heads, heading rules, exercises and a dash
separator (FAA 211/212, Fed 32, Our Flag 27, algebra 289, Loper 60) keep every block boundary
they had at `62877e6`.

## Headings beside trailing figures and wide section titles

`HeadingPlacementTests.swift` covers [#63](https://github.com/vocaro/PDFReflowLib/issues/63) and
[#73](https://github.com/vocaro/PDFReflowLib/issues/73). FAA pages 33/34, 49/50 and 201/202 keep
`Selecting a Flight School`, `Human Factors` and `Chapter Summary` directly above the paragraph
that continues onto the next page, after the figure caption that closes the page; a synthetic join
moves only a heading directly above the paragraph. A caption closes at a title set directly
beneath it in larger type but keeps its own 8 → 9 pt wrapped line. FAA page 43's two-line
`Crew Resource Management (CRM) and Single-Pilot Resource Management` is one heading only when the
book's 12-point bold label style is supplied, while page 43's narrower `Hazard and Risk` is a
heading either way; a wide line with sentence punctuation, one wider than the column's prose and
one in another style stay prose, and pages 33, 49 and 201 each supply the style, which counts from
the third page. The FAA contract checks the three orderings and the wide titles on pages 43 and
370; see the [heading-placement evidence](../measurements/heading-placement/record.md).

## Text-free forms, tagged chapter openers and paragraphs tagged in pieces

`TaggedFormAndTitleTests.swift` covers [#75](https://github.com/vocaro/PDFReflowLib/issues/75) and
[#84](https://github.com/vocaro/PDFReflowLib/issues/84). A synthetic tagged page drawing a Form
XObject keeps its tags when the form, or a form nested in it, draws only paths; a form that shows
text directly or through a nested form, or draws a missing resource, still invalidates the page.
FAA page 88's opener (`Chapter 4` and `Principles of Flight`, each a `P` over the `Introduction`
heading) stays two paragraphs without the book's heading styles and becomes two headings with them;
heading evidence counts from the third page and ignores folios such as `C-1`. Our Flag's centred
imprint stays a paragraph beside a different recurring style (and would be a title in its own).
Page 203's `P` over `Introduction`, its paragraph and the next section falls back with its chapter
title first. Two paragraph groups split at a wrapped line (`…AFM/` / `POH.`, a new sentence in a
column spaced by paragraph) read as one paragraph, while even leading, a short last line and a
leader entry keep them apart, and a caption continuation tagged apart falls back with its caption.
Disabling each rule in turn fails the test that covers it. The FAA contract checks the five chapter
openers, page 89's column order and the joined paragraphs on pages 105, 211 and 227; the Dietary
Guidelines contract checks the bullets on pages 3–5. See the
[form and chapter-title evidence](../measurements/form-tags-and-chapter-titles/record.md).

## Paragraphs tagged in pieces beside figures, tagged titles and lettered folios

`TaggedSplitsAndTitlesTests.swift` covers [#89](https://github.com/vocaro/PDFReflowLib/issues/89) and
[#90](https://github.com/vocaro/PDFReflowLib/issues/90) with `faa-N-tagged` fixtures, which carry the
tags the pipeline applies. FAA pages 114 and 127 join a paragraph group onto the untagged paragraph
whose group fell back around a figure, and page 360 an untagged line onto the group above it, while
paragraphs the same pages set apart with space stay apart; page 96 joins in a justified column whose
only space sets off a heading. Controls: the ragged acronym list (page 462), a TAF's change groups
(319) and right-aligned NDB table rows (416) stay separate, and #75's even-leading control still
holds. Tagged titles in the book's bold, bold-italic and 12-point styles are headings (page 27's two
stacked titles stay two, page 72's `Introduction` follows its chapter title, page 429's titles), and
so are one-line italic titles over their paragraphs (pages 45 and 27); pages 54–55 and 152–153 keep
the title directly above its paragraph past the figure (#63). Contents labels over leader entries
(pages 6 and 15), a centred table title and a table header row (416) are not titles, and synthetic
controls refuse an italic line that is not title case, ends a sentence, or heads a list nested deeper
than 2.5 em or an indented line (a list on its edge was refused until #97). Appendix folios `C-1`…`C-4` share one offset and go as furniture, and a lettered folio
in the foot band is never a heading; a broken offset and a two-letter prefix are no run. Disabling
each of 18 parts fails a test that covers it. The FAA contract checks the joined paragraphs and
their distinct neighbours on ten pages, the titles and their order on eleven, the absent contents,
table-title and folio headings; the Our Flag contract checks page 12's joined quotations. See the
[tagged splits and titles evidence](../measurements/tagged-splits-and-titles/record.md).

## FAA heading and folio leftovers

`FAAHeadingLeftoversTests.swift` covers [#97](https://github.com/vocaro/PDFReflowLib/issues/97) with
`faa-N-tagged` fixtures for pages 48, 228, 447, 460 and 512. The book's 10-point italic title style is
recorded from pages 45, 48, 228 and 447 as its bold label styles are, and a bold-italic label keeps the
bold key. Untagged italic titles in that style are headings over their paragraphs (447's `Drugs` …
`Hypoglycemia and Nutritional Deficiency`; 228's `Southerly Turning Errors` and `Acceleration Error`),
and without the style they open their paragraphs. Page 48's
`V = EnVironment` no longer seeds a formula crop, so it and `Weather` are headings, and the tagged
`Airport` and `Airspace` head their bullets. Synthetic controls refuse a line without the style, not
italic, at ordinary leading inside prose, ending a sentence, not in title case, a caption, over italic
text, or over a list nested deeper than 2.5 em; plain-type, product (`F = Ma`), term (`E = mc2`),
multi-letter and operator lines are not mnemonic titles, and a bold equation still crops. The blank
pages 460 and 512 lose their lone folios to the run; a folio that breaks the offset, and a blank page
that also carries a running head, keep their lines. Contents entries end in chapter or lettered folios
(every leader entry on pages 6 and 15); a folio without a leader, an ellipsis before prose, a two-letter
prefix and a three-part number do not. Disabling each of 13 parts fails a test that covers it. The FAA
contract checks the headings and their order on pages 47, 48, 228 and 447, the absent folios on 460 and
512, and controls (page 410's table header, page 447's caption, `E = External Pressures`); the Wallace
contract checks the blank pages 175 and 437. See the
[FAA heading leftovers evidence](../measurements/faa-heading-leftovers/record.md).

## Space-only shows and invisible text inside artifacts

`TaggedRejectionsRemainingTests.swift` covers [#91](https://github.com/vocaro/PDFReflowLib/issues/91)
on a synthetic tagged page with independent line geometry. A show of only spaces costs its paragraph
group nothing wherever it lies: at the next line's origin below every line box (FAA page 18's shape),
past a line's trimmed end, from an unknown cursor or as a `TJ` array; a letter in the same place still
rejects the group. A show is blank only when its simple font says code 32 is a space: through a
ToUnicode map (including Adobe PDF Library's one-byte entries under a `<0000> <FFFF>` codespace) or,
without a map, a standard named encoding. A map sending 32 elsewhere, a built-in encoding, Type3 and
composite fonts, and a map with a two-byte entry are negative controls; an empty show is not blank; the
font is restored with the graphics state; a marked section showing only spaces counts as shown.
Invisible text (`3 Tr`) inside an `/Artifact` costs nothing (the Fed's page-131 shape, and text), and
the mode is restored with the graphics state; invisible text in marked body text, in a nested span,
unmarked, or left on after the artifact still refuses the whole page, and clipping modes still fall
back. On the d63bbbc reader five of the seven tests fail, and removing each of twelve parts fails a
test. The FAA contract checks separated rows, addresses and checklist entries on nine pages and page
318's joined report value; the Dietary Guidelines contract checks pages 2, 4, 8 and 9. See the
[remaining tag rejection evidence](../measurements/tag-rejections-remaining/record.md).

## Text the rendering never shows

`HiddenTextTests.swift` builds in-memory pages for #74 and #85: a running head painted before an
opaque page-sized image (dropped; the chapter title drawn over the image opens the page and the
`unverifiedTextLayer` warning stays) and a two-line caption, set with unpositioned continuation
shows, wholly outside a rectangular clip (dropped; a label inside the clip stays). FAA page 159's
geometry, where the clipped caption's first line overlaps the visible caption's second line 1.2
points lower, is reproduced with the source's native line rectangles, with controls for a visible
run starting inside the line or on its baseline. Kept controls: text over the image; translucent,
multiplied, soft-masked, masked, stencil, slanted and smaller images; a triangular clip; a clip
the text only partly leaves; invisible mode 3 text beneath the image; optional content; a pattern
fill; a page whose covers would hide most of its text (the CDC comic's transcription layer), where
a clip still hides; and a rotated label crossing a hidden line. Opaque solid fills hide; the same
fill at half alpha does not. Placement arithmetic (rise, TJ adjustments, negative character
spacing, leading TJ numbers, path clip bounds) and tagged-group line counts after removal are
tested directly. Disabling the pipeline call, the overprinting-caption exclusion or the
transcription-layer guard fails the tests that cover it. Contracts: Fed page 8 has no running head and
reads title before quote; FAA page 159 has no `Figure 5-16` and keeps `Figure 6-20.` apart from the
body. See the [hidden-text evidence](../measurements/hidden-text/record.md).

## Endnote reference typography and bounded paragraphs

`EndnoteMarkerTests.swift` protects the native superscript 4 after `7:45.` on 9/11 page 20.
The full-corpus script assertion also checks its preceding and following source context.
This is coverage for the existing baseline-offset repair, not a new link or note-ownership feature.
The [original investigation](../measurements/numbered-notes/record.md) retains the previously
rejected prototype. Its raster/OCR drift was subsequently traced to mixed execution environments
under #26. The [compatible-environment recheck](../measurements/numbered-notes/recheck/record.md)
supports a bounded native paragraph repair: a top-margin chapter-note heading, consecutive
indented note starts, and consistent dedented continuations must agree. Ambiguous layouts
retain spatial reconstruction.

`NumberedNoteTests.swift` checks every source line belonging to notes 38–54 on page 472
and notes 3–13 on page 532, including the dedented `5.This` inside note 9. Additional controls
cover styles, repeated chapter numbering, header retention, rejected images/tags/OCR/geometry,
page 473's second paragraph within note 66, and cross-page text/page-marker conservation.
The existing lowercase continuation heuristic is exercised without claiming general note identity.
The full-corpus contract protects selected note paragraphs and the existing raised marker.

`NoteLinkTests.swift` covers the note links of #11. Synthetic `NoteLinker` cases: markers link
to their own chapter's note and never across chapters (two chapters both holding note 4), a
marker outside any chapter or without a note in scope stays plain, two references share one
note, a number two notes claim is ambiguous and stays plain, a marker's page follows inline
boundaries with a page footnote outranking a chapter note, styles and surrounding whitespace
survive, and markers inside notes are never linked. Writer cases pin the markup: the first
reference carries `id="noteref-…"`, a repeated reference links without one, notes get
`id="note-…"` with the return link around their number (appended when the note opens
otherwise), same-file links keep bare fragments, cross-file links carry the file name after a
spine split, unreferenced notes and unlinked markers are unchanged, and 700 cross-file links
still keep every body under the 60,000-byte target. Source cases: 9/11 page 469 (chapter 1's
notes 1–9 with note 1's second paragraph kept separate) receives page 20's raised 4; page 484
switches from chapter 1's note 241 to chapter 2's notes 1–22 under its heading, with a wrong
chapter number or a note-sized heading refusing the page; Loper Bright pages 60 and 13 link
`Ibid.2` and `Persistence.1` to their page footnotes; and an original four-page PDF with a
numbered outline (`1 ALPHA`, `2 BE TA`) converts end to end with note 1 of each chapter linked
to its own `NOTES TO CHAPTER N` page, no spine boundary added, and the labelled reader still
returning nothing. Detector controls: a dedented year ahead of the run does not set the
indent, `p. 11` continuations are admitted, `40. Ibid.` counts, and a lettered list item or a
bare number at the indent refuses the page. `NumberedNoteTests` now expects page 473 accepted
with note 66's second paragraph unkeyed.

Corpus contracts support `noteLinks`: `{marker, before, note, notePage?}` requires a
`doc-noteref` marker with that text and preceding context on the page, follows its href to
the note element (across spine files), requires the note phrase in that element's text (which
accumulates across an inline page marker), the optional page, and a `doc-backlink` in the note
that resolves to a reference to the same note on the marker's page. Python controls reject a
missing target, the wrong chapter's note, a wrong note page, an absent or misdirected return
link and malformed expectations. `tools/check-epubs.py` additionally pairs every
`doc-noteref` with a note holding exactly one `doc-backlink` that resolves to a reference to
that note, and every `doc-backlink` with a `doc-noteref`, on every converted fixture and
corpus document; `test_spine_documents.py` holds its negative controls. The 9/11 contract
links pages 19, 20, 64 and 65 to notes on pages 469 and 484 (the last note of chapter 1 and
the first of chapter 2 share page 484) and checks page 469's note paragraphs; the Loper Bright
contract links pages 13, 60, 97 and 98 to their footnotes. The converter before #11 fails all
eight link checks. See the [note-link evidence](../measurements/note-links/record.md).
Cross-page numbered-note joins beyond the existing lowercase continuation, notes pages with
images or nested lists, and heads naming two chapters remain open under #11.

## Native combined-line word boundaries

`NativeLineBoundaryTests.swift` uses the checksum-pinned DGA cover's attributed title runs to
require the missing space between “Guidelines” and “For Americans”. It tests both native baseline
attribute keys, existing spaces/newlines, line-end hyphens, opposite inline scripts, unequal-size
drop caps and ordinary same-baseline style runs. Ambiguous spaces inside a single run remain
explicitly unchanged. The EPUB corpus contract requires the complete title on physical page 1
and rejects its former concatenation, with the source image retained.

Our Flag physical page 31 supplies a second native case with negative baseline offsets: its
two-line “Burial Flag / for a Veteran” heading must preserve the word boundary and heading
semantics. The source photograph remains; this does not accept its unrelated drop-cap order.

`NativeSpacingTests.swift` adds separate source-derived Type3 spacing evidence for DGA's
“Dairy” and “Vegetables”. The fixture contains the original one-byte ToUnicode map and complete
text-show objects, with source object numbers and checksum provenance. Seven tests require an
exact full-line match and a tiny negative TJ adjustment at each removed space; protect explicit
spaces, genuine word-size gaps, style attributes and ambiguous geometry; and reject unsupported
fonts, transforms, character maps, text state and excessive work (a Form XObject drawn outside a
text object is opaque rather than disqualifying since #43). The original single-run
test still requires unchanged text when source-operator evidence is unavailable.

The complete DGA contract requires the corrected words, the existing title, source image and
`unverifiedTextLayer` warning. The [comparison evidence](../measurements/native-label-spacing/record.md)
uses compatible per-run capability receipts and permits only these two exact literal replacements
in parsed pages and XHTML. It does not claim correct diagram-label ownership or general spacing repair.

## Academic front matter, math-variable spacing and algorithm floats

Four further tests in `NativeSpacingTests.swift` cover the word boundary PDFKit drops after a
mathematical variable set in its own font ([#43](https://github.com/vocaro/PDFReflowLib/issues/43)).
`replay-1-text-operators.json` holds the nine page-1 font dictionaries of Replay Clocks (Subtype,
FirstChar, Widths and decoded ToUnicode streams) and both complete text objects, including the
rotated arXiv stamp; against the pinned `replay-1` layout the reader must decode and measure all 187
upright shows, leave the stamp without evidence, and change exactly the eight reviewed lines
(`𝑒must` → `𝑒 must`, `𝐴and 𝐵that` → `𝐴 and 𝐵 that`, …) while a line PDFKit already spaced stays as
it is. Synthetic two-font pages fix the rule: a font change, the same baseline, at least 0.15 em
between the previous show's measured end and the next origin, and a letter or digit on both sides;
0.14 em, the same font, punctuation, a raised show, unknown widths, an unmapped font, mismatched
text, overlapping line rectangles, a rotated show and unsupported text state are all controls. The
general one-byte CMap parser is tested on bfrange, surrogate-pair, ligature and array-form entries
and rejects inherited maps, two-byte codespaces, duplicates, malformed hex, lone surrogates,
reversed ranges, wrong counts and oversized streams.

`AcademicFrontMatterTests.swift` uses the pinned Replay Clocks pages 1, 3 and 4. Page 1 must drop
the rotated stamp with a `furnitureRemoved` warning, rank `Replay Clocks` (level 2) above the
author names (3) and the `ABSTRACT` / `1 INTRODUCTION` labels (4), and keep the abstract,
introduction, affiliations and ACM reference as paragraphs. Page 3 must join the split `3.1` /
`Limitations of Existing Clocks for Replay` row into one heading, keep the `Algorithm 1` caption as
text and its nine listing lines inside one crop under 90 points tall; page 4 must yield three
algorithm regions holding all 32 numbered lines with the captions and the prose reference
`… in Algorithm 2.` outside them. Synthetic controls cover the float rule (no closing rule, a
caption not directly beneath its rule, a `Table` caption, a mismatched extent), the stamp rule
(inner rotated labels stay paragraphs, short margin credits such as the 9/11 report's photo credits
stay, rotated pages and two-character marks are ignored), document-wide heading tiers (a later
page's label gets the opening page's label level, a tagged heading keeps its level, one size gives
level 2 everywhere), and the label rule (size
band, capital or digit start, no sentence punctuation, clear space above, capitals or a short line,
dotted section numbers only, list markers, folio-ending contents entries, recognized pages).
Source controls: 9/11 chapter titles outrank their `1.1` / `2.1` section labels, Fed and Our Flag
headings survive, NBS page 7's inherited OCR prose and Fed page 13's 8-point lines gain no
headings, and the algebra, Our Flag, USGS and NBS fixtures have no algorithm floats. The corpus
contract adds the reviewed headings, paragraphs, spacing phrases, absent stamp/listing text and
the page-1 warning; see the [front-matter evidence](../measurements/academic-front-matter/record.md).


## Styles in lists and code

`PreformattedStyleTests.swift` protects superscripts, subscripts and emphasis in numbered,
lettered and bulleted lines, including a minus-prefixed mathematical line. Monospaced code
retains indentation and literal markup; ordinary lists keep their separate blocks and hyphens.
Source-derived algebra page 26 checks both exponents in exercise 80. FAA pages 211/212 provide
independent V-speed subscript cases. Packaging tests protect inline page navigation, model
immutability and counting style wrappers toward the spine body-size target.

The corpus checker rejects flattened or misplaced scripts inside `<pre>`, including nested
emphasis. Full-book contracts check both algebra exponents and four FAA V-speed subscripts in
source context. This preserves detected styles; it does not validate every script inference,
repair exercise grouping, reconstruct semantic lists or establish chapter-scoped endnote links.
See [the source review and complete corpus comparison](../measurements/preformatted-styles/record.md).

## Exercise and answer-key numbering

`ExerciseNumberingTests.swift` uses five checksum-pinned Wallace algebra pages. Page 10 (section
0.1 exercises) must keep all 44 numbers as separate blocks, each column in order, with the
instruction lines in place; page 438 (its answers) must keep 60 separate entries, including the
negative ones that extract as `1)− 2` with no space after the marker, and every exercise number
must have exactly one answer entry with reviewed pairs agreeing. Page 291 (8.1 square roots)
must keep every radical exercise inside a preserved region with no stray number; page 289 must
keep the three worked derivations as images between their `Example` labels while the prose
reflows; page 471 must keep the thirty dimensional-analysis answers in column order. A synthetic
control keeps `5.This` note continuations and `2)(3)` prose out of the list branch. The corpus
contract pins those pages, the page-289 derivation against a source-rendered reference, and
`imageRegion` warnings. Column-major page order, the displaced chapter heading on page 438 and
fraction entries split between a marker stub and an image are recorded as open defects in the
[numbering evidence](../measurements/exercise-numbering/record.md), not blessed.

## Citation-leading wrapped lines

`CitationContinuationTests.swift` uses four checksum-pinned Loper Bright source pages (2, 7, 13
and 60) whose wrapped lines begin with `v.`, a year, `F.` or `U. S.` followed by a period. Each
line must remain inside its paragraph with no preformatted block on the page, page 2 must keep
its four syllabus paragraphs in source order, and every source character must survive the join.
Synthetic controls keep genuine lists separate after a short introduction, after terminal
punctuation (including closing quotes and brackets), across a paragraph gap, with an indented
marker, after an unwrapped OCR line, when fewer than three lines establish the right edge, and
for bullet, minus and hyphen markers. Algebra page 26 and Warren page 50 supply source-derived
list controls: every spaced numbered marker stays its own block. The Loper Bright corpus
contract requires the joined text inside one paragraph on all four pages; the checker's existing
fragment negative control rejects the same phrase split across blocks. See the
[continuation evidence](../measurements/citation-continuations/record.md). Ragged-right columns
and hanging-indent continuations remain outside this rule.


## Damaged text encodings

`DamagedEncodingTests.swift` covers [#38](https://github.com/vocaro/PDFReflowLib/issues/38): the
Census report's LaTeX pages render correctly but extract with every letter shifted by three,
because their Type 1C fonts use `Differences` names such as `G108` with no `ToUnicode` map. An
original in-memory fixture reproduces the mechanism with a Type3 font whose glyph procedures draw
the right letters through Helvetica while its encoding names each code `G<code + 3>`; PDFKit
extracts `Wzr gdwd ilohv zhuh xvhg1` from it, and the same fixture with a correct `ToUnicode`
CMap extracts `Two data files were used.` The tests require both signals: the font evidence
accepts index-style names (`G108`, `g3`, `c63`, `glyph12`) forming at least half of a simple font's
`Differences`, also inside nested Forms, and rejects standard names, `uniXXXX`, named base
encodings, `ToUnicode` maps and composite fonts; the English statistics flag the checksum-pinned
Census page 3 fixture and a Caesar-shifted paragraph but not the page 1 cover, ordinary prose,
short pages, non-English declarations or the Blue Book OCR, algebra answer-key, 9/11 name-table,
FAA glossary, Our Flag table, CDC comic and USGS table fixtures. End to end, `.never` retains the
unreadable text with `damagedTextEncoding` and a source-page image (or `referenceImageOmitted`),
every automatic policy recognizes the page instead and reports `ocrUsed` with the readable text,
the mapped control is never flagged, and in a two-page book only the damaged page is flagged and
referenced. The bundled prose, scanned, columns, graphics, lists-code and rotated fixtures carry
no evidence.

The corpus contract requires `damagedTextEncoding` and an image on Census pages 2–20, the
reviewed page-3 phrases through OCR with the shifted forms absent, and no damaged-encoding, OCR
or unverified-layer warning on the cover page through the new `absentWarningCodes` expectation,
which the checker tests exercise with a same-page negative control. The
[damaged-encoding evidence](../measurements/damaged-text-encoding/record.md) records the signal
survey over 5,059 pages of the fourteen English corpus documents: the font evidence appears on
19 of 20 Census pages and on no other page, and the text statistics alone would touch four
answer-key and handwriting-OCR pages that the combined rule leaves alone.

## Decorative drop caps

`DropCapTests.swift` uses Our Flag pages 7/9/27/30/31 to protect opening-line order, paragraph
classification, genuine headings, full ink bounds, a preserved numeric table, a mid-page
hyphen continuation and real superscripts beside a drop cap. Synthetic controls reject
ordinary initials/scripts, multi-letter labels, uppercase/short continuations, inconsistent
font/baseline evidence, missing attributes and monospaced text. Offset bounds and inadequate
geometry cannot silently corrupt the source ink rectangle.

The full corpus checks body semantics/order on these pages and fraction scripts on page 30.
The [drop-cap evidence](../measurements/drop-cap-order/record.md) records before failures and a
strict comparison: only the supported Our Flag openings move/change classification, with one
source-reviewed existing hyphen repair; other page content and all image bytes remain unchanged.
This does not qualify tag consumption, initial-word repair or complete paragraph grouping.

The corpus lane also runs `tools/check_structure_memory.py` in a fresh process against the
checksum-verified FAA source. Its 192 MiB Mac RSS ceiling protects the initial structure index
from eager loading of sparse ParentTree arrays; `--maximum-rss-mib` overrides the development
limit. Full conversion retains its separate per-book memory gates. Neither budget qualifies
physical iPhone/iPad performance.


## Concurrent native extraction

Every `check-all.sh` lane runs a fresh-process native-extraction smoke gate (two trials per
fixture, one/eight background workers, 50 independent document opens per worker). It asserts
exact line text and 12/24-point fonts on original RoleMap/MCR and structure-tree-absent fixtures.
It complements the public-API test that overlaps four different conversions and one cancelled
conversion, checking output ownership, styles, images, monotonic progress and staging cleanup.

For a longer native campaign:

```sh
python3 tools/check_pdfkit_concurrency.py --output /tmp/native-stress \
  --modes native --workers 0 1 8 --iterations 1000 --trials 10
```

Worker count zero runs on the main thread; one runs serially on a background thread. Higher
counts start independent threads together; no PDFKit document, selection or attributed string
crosses threads. Each iteration opens its own document inside an autorelease pool. Use
`--optimization debug` for an unoptimized build. The diagnostic compiles the actual native
reader and value types; it does not duplicate the extraction implementation.

For the unmitigated Apple-SDK control, which can deliberately reproduce a process abort:

```sh
python3 tools/check_pdfkit_concurrency.py --output /tmp/pdfkit-sdk-stress \
  --sdk-only --workers 1 8 --iterations 1000 --trials 5
```

This build excludes all library sources and compares plain versus attributed selections.
A new output directory is mandatory. The runner preserves every child exit code, stdout/stderr,
input/producer/binary identity and trial result; it never retries a failed trial. Timeouts kill
and reap the child process group. A zero exit without a complete matching positive-control
receipt is a failure. Python negative tests enforce these properties. A finite passing campaign
is bounded evidence, not proof that all concurrent PDFKit use is safe. The smoke gate runs
only the mitigated native path; raw attributed controls belong to explicit diagnostic runs.

See [measured failures, mitigation and limits](../measurements/pdfkit-concurrency/record.md).

## Page retention between passes

`PageStoreTests.swift` reconstructs every bundled fixture and a mixed recognition book twice
through the spill store and requires identical blocks, metadata, chapter starts, asset
identities and bytes, warnings and counts, with only the assets directory left in the
workspace. It also checks exact reload of a page carrying styles, inline page markers,
structure, drop-cap geometry, null rectangles and every flag, with the page files and
directory removed afterwards; that the furniture ledger applied page by page equals
whole-document stripping on 28 source-derived 9/11 pages plus a synthetic-layer run; and
cancellation during reconstruction. `measurements/page-retention/` adds byte-identity, summary
and profile tools with negative controls, and the
[retention measurement](../measurements/page-retention/record.md) records byte-identical
output against the pre-change converter on all ten complete books for the spill store and
the two retired alternatives, whose sources and tests are retained beside the record.
