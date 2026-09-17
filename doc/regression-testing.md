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
- `scripts/check-all.sh --corpus`: the same checks plus <!-- counts:documents -->21<!-- counts:end --> complete PDF conversions,
  sequentially, with EPUBCheck, monotonic progress, pinned source identities,
  [memory budgets](corpus.md) (the lowest peak of up to two conversions, since
  one measurement of a book's peak resident size varies by about 100 MiB under load, #140)
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

<!-- counts:coverage -->
[corpus/regressions.json](../corpus/regressions.json) has 3103 targeted checks on 539 reviewed pages
across 21 documents: *Pilot's Handbook of Aeronautical Knowledge*, *Beginning and Intermediate
Algebra*, *The 9/11 Commission Report*, *The Fed Explained*, *Dietary Guidelines for Americans*,
*Our Flag*, *Preparedness 101*, *Project Blue Book Special Report No. 14*, *Mineral Commodity
Summaries 2025*, *Loper Bright Enterprises v. Raimondo*, *Disclosure Risk Assessment in Perturbative
Microdata Protection*, *Welcome to the United States*, *Publication 596*, *Stimulated Multiphoton
Bremsstrahlung in Electron-Ion Collisions*, *Replay Clocks*, *Complaint for a Civil Case*,
*Investigation of Atmospheric Boundary-Layer Effects on Launch-Vehicle Ground Wind Loads*, *A
Scheduling Algorithm Compatible with a Distributed Management of Arrivals in the National Airspace
System*, *Agricultural Research*, *Earthdata Cloud Analytics Project* and *Tank Health Monitoring*.
They comprise 1083 ordered-text, 205 text, 381 paragraph, 244 absent-text, 249 heading,
20 heading-level, 50 absent-heading, 82 list-item, 1 preformatted-lines, 28 script, 6 absent-script,
11 footnote, 34 note-link, 61 paragraph-continuation, 1 list-item-continuation,
8 paragraph-separation, 81 distinct-paragraph, 189 image-presence, 35 captioned-image,
86 page-reference, 102 warning, 111 absent-warning, 17 source-region, 5 glyph-structure,
4 image-appearance and 9 table-cell checks, counted as `tools/check_corpus_content.py` counts them.
<!-- counts:end -->

All source-page anchors must also remain complete and ordered, and semantic text must contain no image attachment placeholders.

Counts between `<!-- counts:… -->` markers here and in the README are generated. After changing
contracts or tests, run `python3 tools/update_doc_counts.py`; `scripts/check-all.sh --fast` fails
while they are stale.

The checks preserve selected correct words, paragraph semantics and cross-page continuity, paragraph/list order, license attribution, image
presence, a caption's place beside its figure, source-region content, glyph-level equation and table structure, image scale/contrast/color
and explicit transcription/fallback warnings. They also pin what a conversion must not do to a page:
`absentWarningCodes` on every reviewed page of the born-digital documents refuses fresh recognition,
a damaged or implausible text layer and a whole-page image fallback, and `pageReference` refuses a
source-page image nothing on the page needs. They read the actual EPUB spine, track
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

`preformattedLines` names two or more lines that one `<pre>` block on the page must hold, each as a
whole line of its own (its line breaks are read before whitespace is normalized) and in the order
given. A block whose lines merged into one, split into separate elements or became paragraphs
fails, as does a named line that is only a prefix of a block line. FAA page 319's TAF uses it: the
report is one block and each change group stays its own line
([coded-report evidence](../measurements/list-bullets-and-coded-reports/record.md)).

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

A page that reflows beside its source-page reference image carries every region inside that image,
which also satisfies a region reference (0.98–0.99 on NBS). `"excludePageReference": true` on an
`imageRegions` expectation skips the page's `Original page N` image, so only a crop can pass. Five
such references cover NBS figures 1 and 2 and display equations (4), (11) and (15): the converter's
crops score 0.985–0.998, while the Paper Capture evidence boxes alone, half of figure 1 or equation
(4) without its number cannot be placed at all. See the
[scan-figure evidence](../measurements/scan-figure-regions/record.md).

## Glyph-structure checks

A `glyphRegions` expectation names a reference rendered with `--kind glyph`: the same Poppler render
kept at the full 180 DPI with a four-pixel white margin. `tools/glyph_structure.py` aligns it in each
page image (36 DPI search, then full-resolution refinement), labels the reference's connected ink
components, splits them into 16-pixel tiles, and requires every tile's footprint to hold at least
`minimumCoverage` (default 0.4) of the reference ink mass while the window carries at most
`maximumExtraInk` (default 0.12) outside the reference's ink. Ink mass is conserved by blur and
resampling but not by erasure, so a 1.5-pixel blur or a 180→120→180 DPI resample still passes.

Five references cover the Wallace page-343 quadratic-formula solution line (exponent, radical sign
and fraction bar), exercise 35 on page 347, the USGS Salient Statistics table (932 components), the
USGS page-2 world production and reserves table (every figure of nineteen country rows under
spanning headers, with the raised estimate markers and underlined totals) and the Our Flag page-27
flag-size table, whose every digit #36 keeps as an image (coverage 0.73 and 0.97, no extra ink;
erasing one country's figures, the spanning headers or one row's flag size scores 0.000).
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
The Colorado flag on Our Flag page 33, FAA figure 5-36, the USGS statistics table and the CDC comic's
image-only page 13 are checked; page 13 is the first colour check on artwork rather than a chart or a
flag (the lamp's yellow glow over blue-grey night panels), and its crop scores 1.00 scale, 0.99
contrast and 1.00 agreement over 1,247 colored samples.
Correct crops score 0.98–1.00 scale, 0.55–0.99 contrast and 0.99+ color agreement; grayscale,
channel-swapped, level-compressed and downscaled crops fail (agreement ≤ 0.36, contrast ≤ 0.18,
scale ≤ 0.79). Scale is a pixel-dimension check, not a sharpness measure. Glyph structure stays a
born-digital check: a scanned NBS display equation keeps 0.84 of its reference ink but carries 0.44
extra ink, because Paper Capture's background is grey rather than white, so no glyph reference was
committed for it. See the
[image-appearance evidence](../measurements/image-appearance/record.md) and the
[caption-pairing and page-policy evidence](../measurements/figure-captions-and-page-policy/record.md).

## Table cell checks

A `tableCells` expectation carries a reviewed transcription (`columns`, `rows` with `label`,
`values` and optional `group`, in the shape of `corpus/usgs-mcs2025-copper-review.json`) and passes
only when a `<table>` on that page maps every column through its header path and every row's cells
equal the expected values under those columns, with group rows preceding their members. Swapped,
shifted or merged cells, missing rows or groups, and tables rendered as prose fail. A header cell
that spans a label column and an amount column names each column beneath it as
`{"header", "span", "column"}`; the header path must end in a cell with exactly that colspan, so an
unspanned or wider header fails. A row whose label sits under such a column names it with
`labelColumn`. An optional `caption` lists the table's caption paragraphs, which must equal the
paragraphs of that table's `<caption>` in order, so a title emitted as prose or merged with its
description fails (#113, #114). Caption paragraphs are also page paragraphs, never headings. An
optional `rowHeaders` (boolean) checks the matched rows' cell kinds: when true each row's first grid
cell is `<th scope="row">` if it holds text (an empty one stays `<td>`) and no other cell of the row
is a header; when false no cell of the row is a header. An optional `headerCells` (boolean) requires
the header rows to be written as `<th>` (true) or the table to have none (false), since without it a
first row of `<td>` cells still serves as the header (#121). With `rowHeaders` true, an optional
`rowHeaderColumns` lists the 1-based columns whose cells name their rows instead of the first grid
cell, for side-by-side label/value lists. An optional `groupHeaders` (boolean) checks the group rows
named by `group`: when true the group row nearest before each matched row must be
`<th scope="rowgroup">` cells opening their own `<tbody>`, when false data cells (#124). An optional
`scriptCells` (boolean) checks inline markup in every cell of the table: when false no cell may hold a
`<sup>` or `<sub>` element, when true some cell must, since the cell text is compared without markup
(#138). The Fed's
entity/overview table (page 64) and regulation table (page 83) are the first corpus tables emitted
as `<table>` (#54, shaded rows and rules; other tables remain images under #36/#31) and carry
reviewed transcriptions; `tools/test_table_cells.py` keeps the checker's negative controls, and the
spine reader separates cell text with spaces and parses each table into a grid. See the
[table-cells record](../measurements/table-cells/record.md).

A `pageReference` expectation (a boolean) requires the page to carry, or not to carry, the
converter's `Original page N` image, independently of its region crops (#151). Since #27's coverage
pass it also covers every page of the TechPort print and the IEEEtran paper, pages 2–20 of the Word
paper and eight more magazine pages (all false: their annotations draw nothing), and all seven NBS
pages (true: the scan keeps its source page beside the inherited OCR).

## Figure and caption pairing

A caption a reading-order defect moves away from its figure still satisfies `text`, `orderedText`
and `paragraphs`, which ask only that the page holds the phrase. A `captionedImages` expectation
(`{"caption"}`, with an optional `"position"` of `after` — the default — or `before`) adds the
placement: the reader records each page's own outermost blocks (`p`, `pre`, `li`, `table`,
`h1`–`h6`) and its images in document order, and some block holding the phrase must be the
immediate neighbour of an image on that side. The converter's generic `<figcaption>` never enters
that sequence, so a preserved region's own caption cannot separate a figure from the caption the
source printed; a block a page marker interrupts keeps only the text it holds on the page it opened,
so a caption is judged on its own page.

Thirty-five pairs are checked: 23 FAA `Figure N-M.` captions on sixteen pages, the Word paper's
Figure 3 and its five appendix captions, the IEEEtran paper's Fig. 1 (below its figure) and the
TABLE I and TABLE III captions (above their tables), the TechPort Figure 1 and NBS Figures 1 and 2.
Python controls reject a stray block pushed between figure and caption, a removed figure whose
caption survives, a removed caption, a caption on the wrong side and a caption on another page; the
same mutations on real output fail on FAA page 262, the Word paper's page 14, the IEEEtran page 7
and NBS page 2. The check proves the pairing survived, not that a caption sits beside the right
figure. See the [caption-pairing and page-policy evidence](../measurements/figure-captions-and-page-policy/record.md).

A `maximumImages` expectation (a non-negative integer) fails a page with more images than that,
including source-page reference images; it pins decoration that must not become an image. The Fed
contract uses it on pages 32, 46, 47, 64 and 120 and Our Flag on pages 12 and 54, where the
running-header or top-margin rule used to be a crop (#66), with `tableCells` transcriptions of Fed
Table 3.1 (page 46) and of Box 3.5's Table A (page 47, whose amounts are cells under headers
spanning a label and an amount column; #65, #114). Pages 46, 47, 64, 83, 97, 109 and 120 check
each table's caption. Pages 46, 47, 64, 83, 109 and 120 require row-header first cells, and page 97
a `<th>` header row over data cells; FAA page 131 transcribes the borderless load-factor table with
a `<th>` header and no row headers (#121). Page 47 also requires the liabilities labels (column 3)
as row headers, and pages 82, 83 and 120 require their section rows as rowgroup headers, each
opening its own body (#124). Pages 82, 83 and 109 require the regulation tables' cells to hold no
superscript or subscript: the 12-point regulation letters are cell text, not scripts of their 8-point
names (#138). See the
[ruled-table and header-rule evidence](../measurements/ruled-tables-and-header-rules/record.md), the
[table caption and tag evidence](../measurements/table-captions-and-tags/record.md) and the
[table header and borderless-table evidence](../measurements/table-headers-and-borderless/record.md) and the
[table leftovers evidence](../measurements/table-leftovers/record.md) and the
[cell-label script evidence](../measurements/cell-label-scripts/record.md).

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
  Sources/PDFReflowLib/FontWeightReader.swift Sources/PDFReflowLib/PrivateUseDecoder.swift \
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
[tinted-box evidence](../measurements/tinted-boxes/record.md). The `fed-46` and `fed-83` fixtures were recaptured
with the column-joint split (#65): page 46's merged `Tool Definition In practice` header is three
lines and page 83's regulation letters are separate from their names;
`RuledTablesAndHeaderRulesTests.swift` re-merges page 46's header to reproduce the crop and builds
a synthetic ruled PDF whose header PDFKit merges.

`TableCaptionTests.swift` covers table captions (#113) with source-derived `fed-{46,47,64,83,97,109,120}`
fixtures (each table's title, then its description, is its caption and reads nowhere else; Box
3.5's prose above Table A stays outside it), synthetic controls for the caption rule (no title,
two lines in a row, an offset or resized description, a wide gap, a long introduction, four title
lines, text above the caption) and caption serialization. `fed-47` and `fed-97` are new captures;
`fed-77` and `fed-109` were recaptured (#114): they gain `paints`, the column-joint split and the
tags the pipeline now applies, and their heading and body checks also hold with the tags removed.

`TableHeadersAndBorderlessTests.swift` (#121) reads `fed-97`'s header on two column bands as the
header row, with controls that edit those bands (too narrow together, running down through the
body, one band, overlapping) and keep the first row as data cells; checks row-header first cells on
`fed-{46,47,64,83,109,120}` (not header rows, section rows or Table A's empty asset label), with
synthetic controls for one labelled row, repeated labels, a label without a value and numeric
labels, and their serialization. A new `faa-131` capture reads the load-factor table as a
four-row table between its introduction and footnote; re-merging its rows reproduces the scrambled
paragraphs. Synthetic lines control the borderless reader (title-case heading, one body row, a
missing value, a label crossing the gap, prose, another size or a tag under the heading, distant
headings or rows), and a synthetic PDF set like page 131 reproduces PDFKit's merged rows and the
split, with a title-case heading, a drawn rule and a row too tight for a common gutter as controls.

`TableLeftoversTests.swift` (#124) reads the section rows of `fed-83` and `fed-120` as header cells
spanning the table, each written `<th scope="rowgroup">` at the start of its own `<tbody>`, with the
other rows' cell kinds unchanged; synthetic tables check the serialization, with a spanning data
cell, a row header spanning part of the table and a spanning header row as controls. `fed-47`'s
liabilities labels (column 3) are row headers beside the asset labels, the Treasury row's empty
asset label a data cell; synthetic rows check that each list under a spanning header cell is judged
alone (repeated labels or a label without its own value cost only that list its headers), with a
header cell over one column, a single spanning header cell and spans short of the body's columns as
controls that keep the first-column rule.

## Labels joined across a page

`DetachedLabelTests.swift` covers [#14](https://github.com/vocaro/PDFReflowLib/issues/14): PDFKit
returns content set against opposite sides of a page as one line (the *Dietary Guidelines* cover's
`& Healthy Fats` and `& Fruits`, which label the two sides of the food pyramid, joined by a space
glyph 343 pt wide), and its character positions on that page no longer follow the text, so no cut
can be found by walking characters. `NativeTextReader.splitDetachedShows` proposes a cut where a
text show in the content stream begins at least eight ems and a quarter of the page beyond the
previous show, and takes it only when PDFKit's own rectangle selections show pieces that spell the
line, stand on their own sides of the cut and leave every neighbouring pair that distance apart
with more empty page between them than their own ink. Column gaps, cells and word spaces leave far
less: the corpus's own merged lines put every column, cell and graph-label gap at or below 11.5 ems
and 19% of the page, and every gap across a page at or above 17.8 ems and 35%.

Original in-memory PDFs supply the reproducer (two labels on one baseline, a three-label row, a
split label's styled run) and every control: a table row's column gap, a row whose pieces carry
more ink than the space between them, prose with ordinary word spaces, a line narrower than a
quarter of the page, labels already on separate baselines, a font without widths (so the spacing
reader supplies no shows, the state of every fixture captured before #14) and an unmodelled text
mode. Removing the page share fails the table-row and short-line controls; removing the ink test
fails the ink-heavy row. The corpus contracts add DGA page 1 (`Protein, Dairy & Healthy Fats`,
`& Fruits`, `realfood.gov` and `2025–2030` present, `& Healthy Fats & Fruits` and
`realfood.gov 2025–2030` absent, each pair distinct paragraphs) and Wallace page 101 (exercises
`9)` and `10)` distinct paragraphs, in order before their instruction); Our Flag page 4's
two-column committee entries are the corpus control that must stay whole. Across all 21 documents
this adds four split lines and changes no word space; see the
[detached-label evidence](../measurements/detached-labels/record.md).

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
  Sources/PDFReflowLib/FontWeightReader.swift Sources/PDFReflowLib/PrivateUseDecoder.swift \
  tools/capture-layout-fixture.swift \
  -o /tmp/capture-layout-fixture
/tmp/capture-layout-fixture faa-phak-8083-25c 91 /tmp/faa-91-layout.json
```

Since #125 an attributed run drawn in a bold font resource that PDFKit does not name bold (a
`Dm`, `Demi` or `Semibold` face, or any embedded font PDFKit reports as `Helvetica`) records
`"bold": true`; fixtures captured before carry no such field and replay PDFKit's runs alone.
Since #133 a run drawn in an italic text font resource that PDFKit does not name italic records
`"italic": true` the same way.

Run from the repository root. The tool verifies the cached PDF against the manifest SHA-256.
Paints wholly outside the crop box are not recorded (`GraphicsReader` drops them; FAA pages 474
and 475 share a two-page illustration, #99), and any other non-finite number stops the capture
with the JSON path of the element instead of aborting inside the writer. Where
the page's structure validates, each line also records the tag the pipeline applies (`structure`,
since #89/#90); older fixtures and untagged lines have none, and `SourceLayoutFixture` restores it.
Source review, baseline failures, cross-document safeguards and full-run evidence are retained
in [the three-fix measurement](../measurements/three-fidelity-fixes/record.md). The suite contains
<!-- counts:swift-tests -->826 Swift tests<!-- counts:end --> with no known-issue wrappers, and <!-- counts:python-tests -->242 Python tests<!-- counts:end -->.
The comparison tests include a real-Poppler image URL check through the safe HTTP handler
(simple and positioned modes, paths with spaces); absent Poppler is an explicit skip.

`HyphenFragmentTests.swift` covers [#101](https://github.com/vocaro/PDFReflowLib/issues/101): the
NOAA page-553 and page-284 fixtures join `community-resilience-es-` + `timates.html` once the
continuation `timates` is no longer a book word, with controls for compounds opening a
continuation line, words seen elsewhere, Fed page 27 and prose joins. See the
[hyphen-fragment evidence](../measurements/hyphen-fragments/record.md).

`FallbackBlocksAndLigaturesTests.swift` covers [#122](https://github.com/vocaro/PDFReflowLib/issues/122)
and [#123](https://github.com/vocaro/PDFReflowLib/issues/123) items 1–2. CDC pages 14, 23 and 34
(`cdc-14`, `cdc-23`, `cdc-34`) read a speech balloon and the caption box beside it whole, the left
unit first; synthetic controls isolate each guard (a name beside its description, left-aligned
columns off each other's baselines, uncentred units, a third unit, a box that begins at the
balloon's last line, close centres, a list line, shared baselines, an overhanging row piece).
`cdc-17-ocr` is Vision output captured with `tools/capture-ocr-layout-fixture.swift`, which now
records each rotated line's `readingDirection`; its sideways caption reads in line order, and
synthetic lines check both rotations, mixed directions, upright text, the direction's threshold, its
scaling in a retry band and its page-store encoding. Wallace pages 50 and 218 (`algebra-50`,
`algebra-218`) join `dif-` + `ferent` on the book's `diﬀerent`, and page 64 (`algebra-64`) keeps its
spaced example lines out of the list items, with and without crops; synthetic controls keep a
wrapped line at the ordinary gap, a spaced line opening lowercase and a page with no measurable gap
in the item. The CDC contract adds pages 14, 17, 23 and 34 and the Wallace contract pages 50, 64 and
218. Since #93 CDC pages 14, 23 and 34 are recognized by default, so their contract checks the same
balloon-before-broadcast order in the recognized text; the fixtures still hold the native layer. See the [fallback-block and ligature evidence](../measurements/fallback-blocks-and-ligatures/record.md).

`EqualsHyphenTests.swift` covers [#126](https://github.com/vocaro/PDFReflowLib/issues/126) and
[#127](https://github.com/vocaro/PDFReflowLib/issues/127). 9/11 fixtures 172, 210, 235 and 313
crop a body line and its note marker at a `=` line end as extracted, and have no crop and a linked
marker once the book's `=` hyphens are restored (255 is the control #119 already freed). Pages 172,
235 and 242 run the restored breaks through the hyphen policy. The book evidence has threshold and
ratio controls, and the Wallace 110/288/289/291, NBS 7 and FAA 227 fixtures carry none. Code joins
cover FBI serials within page 546 and across 550→551, with prose-compound, citation-range and
folio controls. The 9/11 contract checks the four recovered links, their pages' image counts, joined
and kept breaks and serials. See the
[equals-hyphen and code evidence](../measurements/equals-hyphen-and-codes/record.md).

`SplitRowsAndLostHyphensTests.swift` covers
[#148](https://github.com/vocaro/PDFReflowLib/issues/148) and item 1 of
[#157](https://github.com/vocaro/PDFReflowLib/issues/157). 9/11 fixtures 145, 220 and 438 are rows
PDFKit split outside mathematics, at a raised note marker or at a justified line's word space; FAA
367 is the short split row that must not read as prose. Fed 22 is a paragraph a sidebar cuts,
with `nextLineInColumn` asserted on the two halves; Loper Bright 11→12 is the cross-page word
break whose anchor line is under half letters. Fed 95 and FAA 73 are mid-line compounds the source
spaced, one closed on the book's own compound and one on the book's own em dash. Our Flag 5 and 9
are line-end hyphens PDFKit lost, with `real ity` — which the book never prints joined — as the
control. Synthetic rows, blocks, measures and vocabularies carry the negative controls: a junction
wider than a word space, a sentence end, a piece of the page in the junction, a row short of the
measure, a continuation in another column or with a line between, a suspended hyphen, a number, an
address, a ragged column and a recognized page. The 9/11, Fed, Loper Bright, FAA and Our Flag
contracts check the joined paragraphs and their spaced forms' absence. See the
[split-row and lost-hyphen evidence](../measurements/split-rows-and-lost-hyphens/record.md).

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
A `headingLevels` expectation (`{"heading", "level"}`) additionally pins the rank a heading is
written at: every heading on the page holding the phrase must be that `<h1>`–`<h6>`, and at least
one must exist, so a heading flattened to a paragraph and a heading ranked one tier off both fail.
Python negative controls cover a re-ranked heading, a flattened one, the same text on another page,
two headings holding the phrase at different levels, and malformed entries.
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
with one phrase and continue page N+1 with the other. An optional integer `nextPage` greater than
N+1 names the continuation's page when the pages between hold only figures (#118); each of those
pages must exist and carry no text at all, and Python negative controls reject a page between with
text, a missing page, a split paragraph, the same output without `nextPage`, and a `nextPage` that
is not a later integer. The
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

## Hanging-indent entries

`HangingEntryTests.swift` covers [#134](https://github.com/vocaro/PDFReflowLib/issues/134). The 9/11
report's hearings appendix lists each panel's witnesses one to an entry, flush left, and wraps an entry
or a panel title one em into a hanging indent. A page edge qualifies when a line that ends no sentence
wraps into such an indent and no line ending a sentence (or a colon) sits over a first-line indent
there. On such an edge a line opens a new entry after an entry's wrapped continuation, or after a line
that ended early, and a bold title in the book's label style may wrap into the indent or head entries
narrower than itself. Source fixtures of pages 458 and 462 check the titles as headings and one
paragraph per witness, including a wrapped entry and one continued from the previous page. Synthetic
controls reject paragraph openings, lines above the body size, a rule over an indented note, index
sub-entries, centred lines, wider steps and list lines as evidence. They also keep justified prose, a
lowercase or hyphenated continuation and a paragraph's indented first line whole, and read neither
title without a wrapped entry. The 9/11 contract checks pages 41 (transcript turns), 458 and 462. See
the [hanging-entries evidence](../measurements/hanging-entries/record.md).

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

## Headings left below columns, stacked sections and Roman front-matter folios

`DGABulletsAndContentsFolioTests.swift` covers [#103](https://github.com/vocaro/PDFReflowLib/issues/103)
and [#105](https://github.com/vocaro/PDFReflowLib/issues/105). The `dga-4` fixture, reconstructed without
graphics as the pipeline does for its page-sized background, must read the right column's last bullet,
its `- Vegetables` and `- Fruits` sub-items, `Incorporate Healthy Fats` and that section's first bullet
consecutively. The `dga-9` fixture must read `Older Adults`, its band, then the bullet as one paragraph
(its left column's five lines continue at the right column's head since #111), with the tagged sections
still whole. Synthetic
controls: a title over two columns and a heading 14 pt beneath them with 15 pt beneath the heading
(`trailingHeading`), where a body-type line, a list line or a heading without its own 1.1-body band
stays; and stacked sections joined by a heading row with its band (`headingRow`), refused without a
figure in the row, with body-type text, with a figure reaching into the lines above, or with nothing
below. `faa-5`, `faa-6-tagged`, `faa-7` and `faa-8` must lose `vii`, `viii` and `ix` and nothing else,
while page 5's `v`, whose offset no other page shares, stays, and two pages are no run. Synthetic
controls accept one-letter numerals and a folio shifted within the band, and refuse a changing
offset, `iiii`, a word, a folio above the footer band and an Arabic folio of equal value. With the two
rules disabled and `FurnitureDetector` restored to `d333b4d`, all six tests fail; removing each of eleven
guards fails a test. The Dietary
Guidelines contract checks page 4's order and page 9's columns, and the FAA contract checks the absent
folios on pages 7, 12 and 15. See the
[DGA bullets and contents folio evidence](../measurements/dga-bullets-and-contents-folio/record.md).

## Titles over art, worked-example prose and same-page column continuations

`TitlesAndProseInCropsTests.swift` covers [#111](https://github.com/vocaro/PDFReflowLib/issues/111) and
[#112](https://github.com/vocaro/PDFReflowLib/issues/112). Source-derived `faa-{3,461,473,477}-title-art`
fixtures must keep each title (and page 461's first body line) outside every crop and read it as a
heading, with page 473's figure still one crop; `faa-453-title-art` keeps the performance figure whole
with its in-frame table title while the appendix title reflows. `dga-9` must keep each section band
only beyond its title (the `Older Adults` band unchanged) and read all four titles as headings, and
`dga-7` must keep `Special Populations & Considerations` a heading over the section title it
introduces. `faa-251-worked-example` must reflow steps 2 and 3 with the quoted `“weight x arm =
moment.”` and keep both figure crops; `faa-298-worked-example` must reflow the closing sentence while
every displayed line stays cropped. `dga-9` must join the `Older Adults` bullet across its columns
beneath the section band and refuse the join without the bands' crops. Synthetic controls refuse title
art for a figure extending below the title, art the title covers for less than 60% (also within its
extent), art reaching more than one type size beyond it (then a trimmed band), a shadow another line
overlaps, a band touching another line, a band taller than twice the title row and body-size text; they
refuse the formula-margin sentence without a capital and full stop or with a term, and the wrapped
sentence end under a closed sentence or opening with a term; and they refuse the column join for a
closed sentence, an uppercase continuation, an unfilled last line, two validated identities, and
swallowed prose below the foot, between the columns or above the head (accepted beneath a band that
crosses the gutter). Against the previous `LayoutReconstructor.swift` all fifteen new and updated tests
fail, and each of 23 single-guard mutations fails at least one. The FAA contract checks the titles on
pages 3, 453, 461, 473 and 477, the steps and sentence on pages 251 and 298, joins on pages 17, 103,
211 and 350 and the reordered captions on 165, 199 and 262; the DGA contract checks the headings on
pages 7–10 and the joins on 7, 9 and 10. See the
[titles and prose in crops evidence](../measurements/titles-and-prose-in-crops/record.md).

## Born-digital illustrated pages

`IllustratedPageTests.swift` covers [#117](https://github.com/vocaro/PDFReflowLib/issues/117). A synthetic
page whose icons, footer band and margin timeline cluster into a page-sized region must reflow its two
sections without `unverifiedTextLayer` or a source-page reference; the same page over a page-sized image,
over a full-page fill, in invisible text, or with the timeline set against the prose (so its crops keep
the text) must keep both. `layoutComesApart` is checked directly: a crop over 75% of the page refuses
even without text in it, crops taking 15% of the words refuse and 5% do not, and invisible text or one
page-sized paint refuse whatever the crops. `GraphicsReader` must mark image XObjects `image` and paths
painted by `f`, `f*`, `B` and `b` (not `S` or `s`) `filled`. Source-derived `dga-{2,3,4,5,6,8}-illustrated`
fixtures now record those flags (`tools/capture-layout-fixture.swift`; older fixtures read both as false):
pages 3–5 must come apart with only the running foot in a crop (and not without composition); the `Gut
Health`, `Sodium` and infant-feeding callouts must read their tab titles as headings followed by their
first bullets, with Sodium's three age items; page 6's first bullet row and title must leave the icon's
crop; page 4 must read `+ If preferred, flavor with salt, spices, and herbs.` whole, its sections in
column order and each icon just before its title (not when the icons are moved beyond two bodies or
stretched beyond three title lines), and page 5 its two-line title as one heading after its icon; page
2's footnotes 2 and 4 must stay out of the footer crop (and not without composition). Synthetic controls
refuse a callout shape that is stroked, holds other paint, is an image or holds two prose lines, a tab
whose title sticks out, a connector rule within two bodies of a line, a cluster with no prose or one
escaped line, a thick bar, an underline spanning two lines, a title backdrop that is a rectangle frame,
lies inside a box or is an image, and a stacked title at cluster level or from two left edges.
`sectionBandsKeepOnlyTheirPartBesideTheTitle` now reads the untrimmed bands from the reader's regions.
`vectorDensePagesStayBoundedAndKeepTheirClustering` composes 4,021 overlapping filled marks with a title
band (past the 500-candidate limit the band stays, the clustering equals the reader's, and a 21-mark
control still drops it) and clusters 2,400 isolated strokes clear of the text, each within 3 s.
Each of 24 single-guard mutations fails at least one test except the icon distance guard, which the
column cut makes redundant on these pages. The DGA contract checks the absent warning, preserved images
and headings on pages 3–5, the callouts and first bullet row on pages 6 and 8, and page 2's footnotes;
the baseline fails exactly those 17 checks. See the
[DGA preservation evidence](../measurements/dga-preservation/record.md).

## Columns a folio, a running foot or a spanning figure leaves uncut

`ColumnMarginOrderTests.swift` covers [#153](https://github.com/vocaro/PDFReflowLib/issues/153) with
source-derived fixtures from the Word IEEE paper, the IEEEtran paper and the USDA magazine. `gwl-2`
must read the left column whole before the right with the folio last, where the folio sits 6 pt
under the columns in their 18-pt gutter; `gwl-1` must read the abstract down each column across the
10.4-pt band both columns break at, with the contents entries' leaders discounted as column content;
`dasc-9` must read the summary and both appendices before the right column's quadratic program;
`dasc-10` must keep Table III's caption whole beside the references, a preserved table counting as
column content; `dasc-4` must read the left column and Figure 1's caption before Figure 2's, the cut
moving past a crop that overhangs the gutter by 4 pt; and `usda-15` must open the article in the left
column, the cut falling to the second gutter where the display photo covers the first. Negative
controls: `dga-3-illustrated` must keep its stacked sections in order, since the right column ends
52 pt above the band under the protein section, and `algebra-263` must keep each formula crop beside
its note rather than reading the crops as a column. Synthetic controls refuse the margin bands for a
scanned table's halves of figures and for lines that merge a margin rule into the text beside them,
and refuse the moved cut where notes stand beside formula crops. The Word paper's contract checks
pages 1, 2, 5, 7, 9 and 11, the IEEEtran contract pages 4, 9 and 10, and the magazine's pages 9, 11,
15 and 18. See the [column margin order evidence](../measurements/column-margin-order/record.md).

## Sentences split around figures at column and page breaks

`ColumnContinuationRecountTests.swift` covers [#118](https://github.com/vocaro/PDFReflowLib/issues/118)
with source-derived FAA fixtures. `faa-21-continuation` must join `…then, now, and into` / `the
future.` past figure 1-10's wrapped 9-pt caption line, with the caption after the paragraph;
`faa-68`/`faa-69` join across the page past figure 2-24's wrapped caption; `faa-230` joins `…twisted`
/ `into a helix.`, the next line of the column, past the gauge beside it; `faa-411` joins `…by means
of the` / `course select knob.` beneath the figure heading the right column; `faa-286`/`faa-287` join
`…every` / `1,000 feet` with figure 12-2 kept ahead; and `faa-45-continuation`, `faa-46`, `faa-47`
join `…weather,` / `capabilities, etc.` past the full-page form, both page markers at the boundary
and the form after the paragraph (refused when joining only adjacent pages). Negative controls:
`faa-341` must not join `…the threshold for` to the 9-pt caption fragment `14 with collocated…`,
and the existing `faa-19` fixture, whose crop swallows the right column's first lines, must not
join `…this system. The` to `standard beacon tower`. Synthetic controls refuse a capital, digit or
quote after a word that can end a sentence, a next line at a paragraph pitch, indented, in another
size, above or beside, or with a line between; a head below the foot without a figure over it,
beside a tinted box, under a figure ending below the foot, or in caption type; a short capital head
line that does not close its sentence, on the same page and across pages, and a full line in other
type; a caption's wrapped line in body type; and a figure page holding prose, a caption-only page or
a third figure page (two figure pages join with every marker inline). All 26 single-rule and
single-guard mutations fail at least one test. The FAA contract checks the joins on pages 19, 21,
45 (with `nextPage` 47), 68, 126, 145, 230, 235, 286, 341 and 411 and re-expresses page 286's order.
See the [column continuation recount evidence](../measurements/column-continuation-recount/record.md).

`CaptionWrapsAndOpenSentencesTests.swift` covers [#145](https://github.com/vocaro/PDFReflowLib/issues/145),
the six FAA splits left after #118. `faa-391`/`faa-392` and `faa-341`/`faa-342` keep figure 16-4's,
14-8's and 14-9's wrapped lines in their captions, which releases `…an hour is lost when` / `flying
eastward` and `…the threshold for` / `Runway 36 is to the right.`; `faa-221`/`faa-222` and
`faa-438`/`faa-439` join a column's last line that ends short on a comma; `faa-169`/`faa-170` join
past an open parenthesis (`…= 38.89` / `Celsius degrees)`); `faa-24-tagged` and
`faa-20-tagged`/`faa-21-tagged` join a capital where one structure-tree paragraph holds both lines.
Negative controls: `fed-13-tagged` keeps the Fed's 8-point description apart from the `Figure 1.4.`
title it sits under (read in sequence and split by the paragraph rule), `nbs-1` does not continue
the 3-point footnote `…of thi s paper,` into the next column, `ntrs-9` keeps the NASA paper's body sentence
opening `Figure 14. These peak values…` from taking the body lines beneath, and the untagged or retagged
page 24 refuses. Synthetic controls refuse a caption wrap off the caption's edge and centre, below a
paragraph space, above it, larger, or with a line between; a caption that closes its sentence or a
second caption, a later paragraph not on the line beneath, or lines read in sequence; a comma line without a comma after a word, with too few words, too narrow, or
before a capital (also after an open parenthesis), across pages and between columns; a parenthesis
opened in an earlier sentence; and a heading or different tag group. All 29 single-rule and
single-guard mutations fail at least one test. The FAA contract checks pages 20, 21, 24, 169, 221,
320, 341, 391, 397 and 438, and the Loper Bright contract the open-parenthesis joins on pages 3 and
34. See the [caption wrap and open sentence evidence](../measurements/caption-wraps-and-open-sentences/record.md).

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

## Annotations and source-page references

`AnnotationPageImageTests.swift` covers #151 with synthetic annotated pages. A borderless link, an
empty text field with a push button, a white stamp, unchecked boxes over printed glyphs and a
Hidden stamp take no reference image, no `imageRegion` and no `referenceImageOmitted`, and their
`annotationsNotConverted` messages name the lost interaction (the hidden page warns nothing).
Controls keep the reference with the original message: a one-point bordered link, a field holding a
value the page does not print, a checked box and a stamp; under `.never` exactly those pages report
`referenceImageOmitted` and no asset is written. `AnnotationEvidence.judge` is also checked
directly, including a field whose value the page does print beneath it, and `markBoxes` rewrites
`’` as `☐`/`☒` only where every occurrence in the line lies under a checkbox (`the Clerk’s Office`
is untouched). Negative controls: the old "any annotation" rule fails 11 expectations, and judging
every annotation by ink alone, with widget values and annotation flags ignored, fails 13.
Contracts: Pro Se 1 pages 1–5, all 20 NASA ground-wind-loads pages, all ten IEEEtran pages, all five
TechPort pages (its 27 borderless links), USDA pages 2–12, 14–19 and 22–24, Fed 5, 11,
109 and 123, 9/11 581–583, FAA 6, 7, 12, 15 and 362 and Replay Clocks 1, 3, 4, 6 and 10 carry no
page reference; 9/11 pages 570 and 571, whose links draw a border, still do, and all seven NBS pages
keep theirs beside the inherited OCR. See the
[annotation evidence](../measurements/annotation-page-images/record.md).

## Blank pages

`BlankPageTests.swift` covers #132 with in-memory pages. An empty content stream, a white fill and a
rotated empty page keep only their page boundaries, with no image, recognition or warning, under
`never`, `automatic` and `always` OCR, and a converted EPUB carries the empty page's marker without
an `<img>`. Controls keep their page images: a 0.97 gray tint, a quarter-point hairline, a near-white
scan, a pure-white scan (painted), and an annotation; 0.99 gray text reflows. The detector's render
threshold (no channel below 254 at one pixel per point) passes a 0.9985 gray fill and fails 0.99 gray,
a 0.1-point hairline, a faint scan and a pale pink tint. Disabling the pipeline call fails both
pipeline tests. Contracts: 9/11 pages 162 and 342 and Fed pages 23 and 134 have no image and neither
`pageImageFallback` nor `ocrUsed`; Fed page 7, a light photograph without text, keeps its image. See
the [blank-page evidence](../measurements/blank-pages/record.md).

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

Two tests cover simple-font maps written by Adobe PDF Library, one-byte entries under a two-byte
`<0000> <FFFF>` codespace ([#104](https://github.com/vocaro/PDFReflowLib/issues/104)).
`NativeSpacingReader.simpleFontUnicodeMap` reads that codespace as one byte for both the spacing
reader and `MarkedTextReader`'s space codes. The synthetic two-font page must decode, measure and
repair `event emust` whichever font uses the Adobe form; it fails against the strict parser. A
0.14 em gap and a map with a two-byte entry stay controls. The helper must equal the strict parse
of the one-byte form, and it rejects FAA's mixed `<0020>` entries, the two-range symbol codespace
`<00> <EF> <F000> <FFFF>` (Loper Bright, Fed), other two-byte codespaces, a second codespace
block, inherited maps and oversized streams. A Type3 font with the Adobe form authorizes no
removal. The [census](../measurements/spacing-one-byte-maps/record.md) shows that no corpus output
changes. The reader's unmodeled-state gates disqualify every FAA, DGA and Fed page whatever the
map: `gs` first (a nonzero `Tc` on one FAA page), then `Tc`, `Tw` and unpositioned shows.

Three tests cover Wallace's missing word spaces after a digit
([#110](https://github.com/vocaro/PDFReflowLib/issues/110),
[survey](../measurements/missing-spaces-survey/record.md)).
`wallaceDigitBeforeTextFontRestoresItsWordSpaceAndMathStaysJoined` reproduces page 29's
`Subtract 7 from`: WinAnsi-encoded Type1 fonts without ToUnicode, a `/R7 gs` that sets no font, and a
digit show that ends with a trailing adjustment (`[(7)178.413]TJ`). The shows must decode and
measure, and the line must be repaired. Its control, page 24's `5y` at 0.05 em, must stay joined.
It fails if the trailing adjustment shortens the show's end, as it once did in formulas.
`graphicsStateWithoutAFontKeepsEvidenceAndAnyOtherDisqualifies` accepts a font-free ExtGState
before or inside text. An ExtGState with a `Font` entry, a missing or non-dictionary resource, a
bare `gs`, and nonzero `Tc` or `Tw` still yield no evidence.
`onlyWinAnsiEncodedType1FontsWithoutToUnicodeDecodeThroughTheirEncoding` pins the WinAnsi table
(ASCII 32–126, `Differences` quotes, ligatures and digit names; an unknown name removes its code;
malformed and oversized arrays fail). It also checks what does not decode: MacRoman, Standard or
missing base encodings, TrueType, unknown names, a name before any code, and a font whose ToUnicode
map is present but rejected. The Wallace contract pins pages 34, 40 and 230.

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
`imageRegion` warnings. Column-major page order and the displaced chapter heading on page 438 are
recorded as open defects in the [numbering evidence](../measurements/exercise-numbering/record.md),
not blessed.

`SplitDisplayRowTests.swift` covers the crop side of the same lane. PDFKit breaks a displayed row
at a raised exponent or a fraction, and a crop's edge could fall in the break, so a derivation's
leading term reflowed beside its own image (Wallace page 343's `x2 +`) and an answer entry was
split between a marker stub and its fraction (page 471's `22)− 2,`). A crop now takes a piece that
stands under three quarters of a point from its edge, shares a row it already holds, carries no
word and is not a bare list marker. Pages 343, 16, 471 and 424 are pinned from checksum-pinned
fixtures, with controls on the rule at measured distances: a piece a word space clear, a bare entry
number, a worded explanation, a monospaced piece and a piece on another row all keep their text.
See [the split-display-row evidence](../measurements/split-display-rows/record.md).

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

The corpus contract required `damagedTextEncoding` and an image on Census pages 2–20 and the
reviewed page-3 phrases through OCR (since #143, below, pages 3 and 17 reflow natively), and
requires no damaged-encoding, OCR or unverified-layer warning on the cover page through the
`absentWarningCodes` expectation,
which the checker tests exercise with a same-page negative control. The
[damaged-encoding evidence](../measurements/damaged-text-encoding/record.md) records the signal
survey over 5,059 pages of the fourteen English corpus documents: the font evidence appears on
19 of 20 Census pages and on no other page, and the text statistics alone would touch four
answer-key and handwriting-OCR pages that the combined rule leaves alone.

## Index-named glyphs

`GlyphIndexDecodingTests.swift` covers [#143](https://github.com/vocaro/PDFReflowLib/issues/143):
the Census report's EC text fonts name their glyphs `G<n>` with no `ToUnicode`, and PDFKit reports
U+n, three letters on. `fixtures/census-text-operators.json` (captured by
`measurements/glyph-index-decoding/capture.swift`, source checksum pinned) holds Census pages 2, 3,
12, 17 and 20 as font dictionaries, graphics states, content streams and PDFKit's lines, rebuilt
with non-embedded fonts. The tests require that exactly `dcr`, `dcbx` and `dcti` decode (+3 passes;
the case-swapped +35 and the unshifted reading fail), with French, the table page alone and the math
page alone as controls; that every line of pages 3, 12 and 17 is rewritten (ligatures, dashes,
figures, table rows PDFKit splits in two, reference numbers read as their own lines) while page 2's
e-mail line and title mark and every line of page 20 stay unrepaired, and that nothing is rewritten
without decodings; that page 12's repaired rows form a numeric grid and pages 2, 3 and 17 do not;
and that compensated character spacing restores `2 Data Files` and `Journal of
Oﬃcial Statistics`. Synthetic controls reject a permutation, capitals only, lowercase only, a short
text, two-letter mathematics and a capital heading font; place dropped ligatures inside their word
and refuse one between gaps; carry and abandon a split row; and pin the Cork, shared and PDFKit name
tables. End to end, Type1 fonts at a constant offset reflow natively under `.never` and `.automatic`,
a page with an undecodable index font alone reports `damagedTextEncoding` (and OCR) with its
decodable lines retained repaired, a line mixing a decoded and a WinAnsi font is repaired, and German
decodes nothing, and a page of numeric table rows in a decoded font keeps #38's path (and OCR)
rather than reflowing its cells run together. #38's Type3 reproducer still reports damage because PDFKit reads its five shows as
one line, which a test records. Disabling each of fifteen parts fails at least one test.

The Census contract now requires native text without `damagedTextEncoding` or `ocrUsed` on pages 3
and 17 (ordered phrases with ligatures and references) with no image; on the table pages 12 and 15,
`damagedTextEncoding`, three images and none of the run-together rows a native reflow writes (Table
2's `0.9620 rnkswp10`, Table 7's `13.85 add01_sw`); and `damagedTextEncoding` with an image on the
other body pages. The
[index-glyph evidence](../measurements/glyph-index-decoding/record.md) surveys every English corpus
book (no other index-glyph font and no shifted text), reviews Census against renders, and records the
9/11 pages whose letter-spaced lines and citations gain spaces from the compensated-spacing rule.

## Implausible inherited text layers

`TextLayerPlausibilityTests.swift` covers [#93](https://github.com/vocaro/PDFReflowLib/issues/93).
Unit tests sort words with an injected lexicon (English, irregular capitals, stray letters,
unknown lower-case words, names, symbols, clitics, digits), hold each word-test boundary (20
judged words, exactly half English, a fifth of the tokens with digits) and each ink-test boundary
(seven rows, 75% uncovered, as many English words as rows), and count renders: a caption layer is
rendered, a 32-word layer, another language and a word failure are not. With the system lexicon,
the checksum-pinned CDC pages 5, 14, 23, 26, 34 and 37 and Warren's handwritten page 553 fail the
word test, while Warren pages 50 (prose), 520 (a witness list at 0.65 English, the nearest
plausible layer in the survey) and 910 (index) and Blue Book pages 5 and 12 pass. Blue Book page
149 (a handwritten table) and Warren page 885 (notes) are the digit guard's negative control: both
read under half English and are exempt only through their digits. Both warning messages are
pinned, with the page-image outcome. End to end, an original PDF whose page-sized image shows ten lines of dialogue under an
invisible garbled layer reports `implausibleTextLayer` under all five policies; `.automatic`,
`.automaticIncludingImageBackedText` and `.always` recognize `strange virus` and drop `sreANee`
with `ocrUsed`, `.automaticKeepingImageBackedText` and `.never` keep the garbled text with
`unverifiedTextLayer`; over a blank image recognition finds nothing and the message says the page
is preserved as an image; the same image under a faithful layer is neither reported nor recognized.
A layer holding only the last line fails the ink test and is recognized by default and kept by
the opt-out policy; the complete layer is not reported. With `TextLayerPlausibility.judge` forced to
return nil, both end-to-end tests and the render-count test fail; with the digit guard removed, the Blue Book and Warren notes
controls fail. `check-conversion-policies.py` adds `--ocr keep-image-backed`, which still
recognizes the scanned fixture's absent text.

The CDC contract requires `implausibleTextLayer` and the reviewed recognized dialogue on pages 5,
7, 14, 20, 23, 31 and 34, with the damaged native forms absent, and no `implausibleTextLayer` or
`ocrUsed` on the plausible page-39 checklist. It fails on the pre-#93 conversion on all seven
pages. The [plausibility evidence](../measurements/text-layer-plausibility/record.md) records the
survey of all 1,353 image-backed pages in the English corpus and the review of every failing page.

## Slide decks

`SlideDeckTests.swift` covers [#165](https://github.com/vocaro/PDFReflowLib/issues/165) on nine
pinned source-layout fixtures: seven Earthdata slides (slide 19 twice), and NOAA page 100, the
corpus's one landscape book. Slide 3's two-line title is one heading although the page's character-weighted body size is
the title's own 32-point type, and outside a deck the same page has no heading and two paragraphs;
slide 10's 26-point title over a 28-point statement is its title although it is *smaller* than the
body; slide 19's boxes are paragraphs, with the reproducer (the overprinted fixture read as a book)
giving six headings including `Cumulus Cumulus Data Archive`, and either rule alone leaving one.
Slide 1, the title slide, centres its title instead of setting it in the head band and so keeps the
ordinary size rule, in a deck and out of one. Three slide titles of 52, 32 and 28 points rank 2, 2,
2 as a deck and 2, 3, 4 by size tiers. NOAA page 100 is no slide portrait or turned on its side
(2,781 characters), while six slides are. The repeated `¹ Analytics Optimized Data Store` survives
`FurnitureDetector.strip` over slides 12–14 with no warning, and is removed from all three again
once the `AODS¹` marker on each slide is written as ordinary text. `slides-19-overprints`, captured
with `capture-layout-fixture --keep-overprints`, holds PDFKit's 26 lines: `withoutOverprints` keeps
23, one `Cumulus` and one `Interpretation` of two each and two of the three `End-User` lines (the
third stands on its own rectangle), and matches the deduplicated fixture line for line; controls
keep both lines for a copy offset 0.3 pt (fake bold), one offset 60 pt, different text on one
rectangle and a one-point size change. Synthetic landscape pages hold the head band and the
clearance under the title apart, which the deck's own slides cannot: slide 1 misses the band by
50 pt *and* clears its byline by 24.3 pt against a 24.4 pt bar, so either guard alone refuses it.

The corpus contract adds the 20 slide titles as `headingLevels` at level 2, the note kept on
slides 12–14 and 16–21, `absentText` for `Cumulus Cumulus` on 13–21 and for the doubled end-user
labels on 19–20, and `absentHeadings` for the five box labels on 19–20. The baseline fails 54 of
them. See the [slide-deck evidence](../measurements/slide-decks/record.md).

## Symbol-font characters and shifted script bases

`SymbolFontCharacterTests.swift` covers [#155](https://github.com/vocaro/PDFReflowLib/issues/155):
symbol fonts give PDFKit private-use code points. The font dictionaries and ToUnicode maps are copied
from the sources (no font program is embedded, so PDFKit reads the maps alone): Word's `SymbolMT`
(alpha U+F061, bullet U+F0B7, descriptor `Nonsymbolic`), the Supreme Court's `BDGFGH+SymbolMT`
(`Symbolic`, family `Symbol`), a family-only subset name and a Symbol font inside a Form XObject all
decode; the same map under another name, with or without the `Symbolic` flag, and a name that only
begins like Symbol's do not. Wallace's `CMEX10` decodes U+F8EB, U+F8F6 and U+F8F0 from its
`Differences` names (`parenlefttp`, `uni23A3`), index names decode nothing, the DASC paper's built-in
Type 1 encoding and a descriptor `CharSet` decode their pieces, a built-in `Symbol` font claims every
Adobe piece, and a font naming no piece claims none. A Symbol and a Wingdings font that give one page
the same code point leave it undecoded, while each alone decodes (`♣`, `▪➢`); a Wingdings pictograph
outside Word's bullet table stays. Unit checks pin the 188-entry Symbol encoding, the family names and
that decoding keeps attribute ranges.

`ShiftedScriptBaseTests.swift` covers [#144](https://github.com/vocaro/PDFReflowLib/issues/144).
Wallace page 255's `6a2b` denominator, 7.8 points below the comment beside it, becomes
`6a<sup>2</sup>b` (source fixture `algebra-255`), as do a raised numerator's exponent, the slope
formula's `y<sub>2</sub>− y<sub>1</sub>` and FAA page 262's `v<sup>2</sup>`. Controls keep the stated
offsets: a base on the selection's baseline (`H₂O`, `8x³`), a smaller run at offset zero beside a
larger shifted one (#138's Fed letter), runs separated by a space, a script followed by a run on a
third baseline, an equal-size run, opposite-side shifts and a nested index (the DASC paper's `STA`
with `n` raised and `i` raised again, #163). The Supreme Court's Symbol bullets (`scotus-86`) and the
spaces after them are list marks, not superscripts, while a raised note marker opening a line, a
raised degree sign (Wallace's `29◦`) and a raised bullet inside a line stay superscripts. NASA page 13
(`ntrs-13`) reflows its five decoded bullets as five list items, each with its wrapped line.
`LineEndCompoundTests.swift` adds `45-` + `degree-increment`: a hyphen after a number is a compound
hyphen, not a word break.

The corpus contracts require the decoded characters and list items on NASA pages 4 and 13 (with
`45degree` and the private-use code points absent), the bullet items and no `<sup>` bullet on Supreme
Court pages 86–87, Wallace page 255's `6a<sup>2</sup>b` and page 96's slope subscripts with the old
`<sub>`/`<sup>` runs absent, no `<sub>` period after `(foreign nation)` on Pro Se 1 page 3 (#138's fix,
guarded), and no private-use pieces on DASC pages 3 and 9. `absentScripts` is a new expectation type:
a `sup`/`sub` tag and text, with optional `before`/`after` context, that the page must not hold.
See the [symbol-font and script-base evidence](../measurements/symbol-fonts-and-script-bases/record.md).

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
This does not qualify tag consumption or complete paragraph grouping.

`DropCapJoinTests.swift` covers #135: the initial joins its word on Our Flag pages 7, 9, 27, 29, 30
and 31 (`The`, `Constituents`, `Any`) and the line keeps its reading rectangle and body size. The Fed's
chapter numerals, the Blue Book's large OCR `I` beside capitals and a split line without drop-cap
evidence stay unchanged; `A`, `I` and `O` keep a space only when the vocabulary holds the fragment and
not the joined word, and a drop-cap fragment (`ny`) never enters the vocabulary. The Our Flag contract
requires the joined openings on pages 5, 7, 13, 27 and 31, with page 47's `On July 4` as the control.
See the [drop-cap word evidence](../measurements/drop-cap-words/record.md).

The corpus lane also runs `tools/check_structure_memory.py` in a fresh process against the
checksum-verified FAA source. Its 192 MiB Mac RSS ceiling protects the initial structure index
from eager loading of sparse ParentTree arrays; `--maximum-rss-mib` overrides the development
limit. Full conversion retains its separate per-book memory gates. Neither budget qualifies
physical iPhone/iPad performance.

## Font styles PDFKit renames

`FontWeightDetectionTests.swift` covers [#125](https://github.com/vocaro/PDFReflowLib/issues/125)
(bold) and [#133](https://github.com/vocaro/PDFReflowLib/issues/133) (italic, Libertine weights,
undecoded mixed lines and split runs). Name classification lists italic faces (`Bembo-Italic`,
`FranklinGothicLTPro-BkIt`, `TimesNewRoman,Italic`, TeX `cmti`/`dcti`/`SFTI`, `LinLibertineTI`)
and upright ones whose descriptor leans (`CMSY10`), with math italic (`CMMI12`, `LibertineMathMI`,
`NewTXMI`, `txmiaX`) and script faces (`SnellRoundhand-BoldScript`) never italic, and Libertine's
`TB`/`TZ` and cm-super's `sfbx` bold. Synthetic PDFs read italic through PDFKit's `Helvetica`
names, mark only the italic word of a mixed line (also under PScript5's two-range codespace), and
decode an `Identity-H` Type0 show two bytes per code; controls leave undecoded lines, math italic,
script faces and upright names unmarked. A leading marker without a letter in a style its item does
not share gains no emphasis, and adjacent same-style runs are written as one element, with page
boundaries, note references and other styles kept apart. `*-styles` source fixtures, each with a
`fontWeights: false` negative control: the Supreme Court's italic case names (page 9), 9/11's ship
names (171), the Fed's chapter summary (8), Replay Clocks' Libertine titles and italic venue beside
unstyled math italic (1), Wallace's `World View Note:` opening its own paragraph (18) and its
upright variables (23), DGA's unemphasised bullets (3), and Our Flag's script title without italic
beside its italic quotation (7). Disabling each of ten parts fails a test that covers it. See the
[font style evidence](../measurements/font-style-detection/record.md).


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
