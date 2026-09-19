# Regression testing

Regression coverage across PDF types is the first development priority. Fixes to extraction,
layout or rendering require both a reproducer and positive controls from other layouts.
A valid EPUB can still contain incorrect text, wrong reading order or unreadable images.

## Gates

- `scripts/check-all.sh --fast`: Swift extraction/model/raster/EPUB tests, Python tool tests,
  and six small fixture conversions. No external PDFs are required. The raster tests inspect
  pixels, including crop origins, rotations, annotations and resource ceilings. Preserved-region
  tests also inspect fraction bars, raised exponents and all six cells of a ruled table in actual
  EPUB images at 72/144 DPI, with surrounding-prose and code controls.
- `scripts/check-all.sh --corpus`: the same checks plus 15 complete PDF conversions,
  sequentially, with EPUBCheck, monotonic progress, pinned source identities, memory budgets
  and reviewed page-specific content contracts. All selected cached sources and EPUBCheck
  are required; missing data fails explicitly. The evaluator does not download anything.
- `tools/check_corpus_content.py --case <id> --evaluation <directory>`: run the content contract
  against an existing complete evaluation without reconverting. This is an additional content
  check, not a replacement for the evaluator's EPUB/resource checks.
- `tools/run_corpus_regressions.py --converter <CLI> --epubcheck <executable> --output <new-directory>`:
  run the corpus lane directly. Repeat `--case <id>` to narrow a debugging run; the summary
  lists omitted cases explicitly. A failing case does not hide subsequent results.

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

## Current content coverage

[corpus/regressions.json](../corpus/regressions.json) has 404 targeted checks on 95 reviewed pages
across 17 documents: FAA, algebra, 9/11, The Fed Explained, Dietary Guidelines, Our Flag, the CDC
comic, Blue Book, the seven #30 cases (USGS copper tables, Loper Bright footnotes, the Census
unmapped-encoding report, the USCIS Arabic guide, IRS Publication 596 in Simplified Chinese, and
the NBS and Replay Clocks academic papers), a five-page suspect-text-layer excerpt of the Warren
report, and the Earthdata Cloud Analytics Project slide deck. All source-page anchors must also
remain complete and ordered, and semantic text must contain no image attachment placeholders.

The checks preserve selected correct words, paragraph semantics and cross-page continuity, paragraph/list order, license attribution, image
presence and explicit transcription/fallback warnings. They read the actual EPUB spine, track
page boundaries inside styled text, preserve ownership across chapter-file continuations, and
exclude navigation/captions from source-text matching. They do not freeze serialization details
or broken output such as interleaved columns and flattened exponents.

The checker has negative controls for deleted text, text moved to the wrong page, reversed order,
missing images, flattened or misplaced superscripts/subscripts, missing/wrong-page warnings, changed source identity, failed conversion, missing
or duplicate page markers, and captions masquerading as source text. A list of assertions without
such controls could silently pass despite a broken checker.

Image-presence checks are weaker than visual fidelity checks. They cannot prove a flag's colors,
a diagram's arrows or mathematical notation is correct. Unit pixel checks, source-image review and
the source-region checks below cover selected rendering behavior; robust visual/semantic contracts
need expansion. The corpus
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
regenerate them.

Ten references cover the Our Flag flag-size table, three USGS copper tables, three FAA page-121
figures, a Wallace quadratic exercise, the Geltman page-image fallback and CDC's image-only page 13.
Correct crops score 0.982–0.997. Wrong images on the same pages score at most 0.62, a table crop
with its lower half blanked 0.64, erasing the Wallace exercise from its crop 0.44, and a 1.5-pixel
blur still scores 0.96. The check proves
a region is present, complete and aligned; it does not prove every glyph. Erasing one exponent from
the Wallace exercise still scores 0.97. See the [image-region evidence](../measurements/image-regions/record.md).

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
   can both be suspicious. Update expectations only after reviewing the source and explaining
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
  Sources/PDFReflowLib/GraphicsReader.swift tools/capture-algebra-layout.swift \
  -o /tmp/capture-algebra-layout
/tmp/capture-algebra-layout corpus/cache/Beginning_and_Intermediate_Algebra.pdf /tmp/algebra-17-layout.json
```

The capture tool rejects any source checksum other than the pinned book. Review source and
geometry changes before replacing the bundled fixture; never regenerate it merely to make a test
pass. The extracted text remains Tyler Wallace's CC BY 3.0 material, with attribution in the
fixture and [third-party notices](third-party-notices.md).

## Source-derived fidelity controls

`FidelityIssueTests.swift` checks the FAA page-91/511 columns, all ten Our Flag page-27 table
pairs and both headers, and algebra page-343's inline exponent. Positive controls cover spanning
headings/figures, ordinary prose, dot-leader contents entries, code, ellipses and sparse numeric
rows. The 9/11 page-451 name/description fixture protects row associations from narrow-column
cuts. `BaselineStyleTests.swift` checks both native baseline-attribute keys, unchanged small
fonts and noisy positioning, a real PDF-to-EPUB superscript/subscript path, and CDC page-5 OCR
line spacing that must not become inline scripts.

These small JSONs capture native extraction from checksum-pinned sources, not converter output.
They run offline on macOS and iOS. Capture another page with full Xcode selected:

```sh
swiftc Sources/PDFReflowLib/NativeTextReader.swift Sources/PDFReflowLib/ConversionTypes.swift \
  Sources/PDFReflowLib/DocumentModel.swift Sources/PDFReflowLib/ReflowDocument.swift \
  Sources/PDFReflowLib/GraphicsReader.swift tools/capture-layout-fixture.swift \
  -o /tmp/capture-layout-fixture
/tmp/capture-layout-fixture faa-phak-8083-25c 91 /tmp/faa-91-layout.json
```

Run from the repository root. The tool verifies the cached PDF against the manifest SHA-256.
Source review, baseline failures, cross-document safeguards and full-run evidence are retained
in [the three-fix measurement](../measurements/three-fidelity-fixes/record.md). The suite contains
82 Swift tests with no known-issue wrappers, and 55 Python tests.
The comparison tests include a real-Poppler image URL check through the safe HTTP handler
(simple and positioned modes, paths with spaces); absent Poppler is an explicit skip.

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

## Implausible inherited text layers

`TextLayerPlausibilityTests.swift` covers [#93](https://github.com/vocaro/PDFReflowLib/issues/93)
and [#7](https://github.com/vocaro/PDFReflowLib/issues/7). Unit tests sort words with an injected
lexicon (English, irregular capitals, stray letters, unknown lower-case words, names, symbols,
clitics, digits, letters of another script), hold each word-test boundary (20 judged words,
exactly half English, a fifth of the tokens with digits, a tenth of all words misread in place)
and each ink-test boundary (seven rows, 75% uncovered, as many English words as rows), and count
renders: a caption layer is rendered, a 32-word layer, another language and a word failure are
not. With the system lexicon, the checksum-pinned CDC comic page 5 fails the word test while
Warren pages 50 (prose), 910 (index) and Blue Book pages 5 and 12 pass; Warren page 636's carbon
typescript and CDC page 4 both misread their words in place. Both warning messages are pinned,
with the page-image and kept-over-recognition outcomes. `otherScriptsAreDamageAndRecognizedTitlesMustReadAsWords`
pins the heading rule (`readsAsWords`) on table titles and month names (kept) and on cells, digit
strings and mixed-script readings (refused).
`recognitionIsJudgedByItsEnglishShareUnlessItIsAnotherLanguage` pins `judgeRecognized` on
handwriting (discarded), a French passage in an English book (kept) and a comic reading that
misreads a tenth of its words (kept), and `readsBetter`.

End to end, an original PDF whose page-sized image shows ten lines of dialogue under an invisible
garbled layer reports `implausibleTextLayer` under all five policies; `.automatic`,
`.automaticIncludingImageBackedText` and `.always` recognize `strange virus` and drop `sreANee`
with `ocrUsed`, `.automaticKeepingImageBackedText` and `.never` keep the garbled text with
`unverifiedTextLayer`; over a blank image recognition finds nothing and the message says the page
is preserved as an image; the same image under a faithful layer is neither reported nor
recognized. A layer holding only the last line fails the ink test and is recognized by default and
kept by the opt-out policy; the complete layer is not reported. `check-conversion-policies.py`
adds `--ocr keep-image-backed`, which still recognizes the scanned fixture's absent text (a page
with no native text at all is not exempted by the opt-out, which only covers existing text over
a page-sized graphic).

This ports the `TextLayerPlausibility` mechanism and its unit/end-to-end coverage from an
abandoned integration branch onto current `main`'s simpler pipeline. `gpo-warren-1964-suspect-text-excerpt`
(below) gates five real Warren pages against this mechanism, each reviewed against its source
raster. The CDC comic's own corpus-level content contract, which the original work reviewed page
by page, is not re-verified here: see [corpus.md](corpus.md#preparedness-101-zombie-pandemic) for
what remains open there.

### Warren suspect-text excerpt

`gpo-warren-1964-suspect-text-excerpt` gates physical pages 549, 553, 556, 636 and 664 of the
pinned `gpo-warren-1964` source — issue #7's own reproduction path, which sidesteps the full
920-page book's separate image-output ceiling failure (#5) rather than resolving it. The excerpt
is prepared by `measurements/gpo-warren-1964-suspect-text-excerpt/prepare-excerpt.py` (pypdf),
which verifies the pinned source identity before extracting; it is registered in
`corpus/manifest.json` as its own document (`identity.suppliedBy: "derived"`, no `downloadURL`),
so `tools/fetch_corpus.py --case gpo-warren-1964-suspect-text-excerpt` only ever reports a cache
hit against a locally-regenerated file, never a download. Each of the five pages was converted and
its source raster read directly (`tools/compare_pdf.py --serve`). Pages 1-3 (549, 553, 556) are
cursive Parkland Memorial Hospital admission notes and a death-declaration statement, confirmed
illegible by reading the rasters: both the inherited layer and fresh recognition fail the English
test and the pages fall back to page images, which is the correct outcome, not a defect. Page 4
(636) is a faint carbon typescript whose misread layer (`tcld`/`ftboot`-style damage) is replaced
by recognition that reads better; two phrases read directly off its source raster, "and he told me
about the things at" and "At 6:00 PM I instructed the officers to bring", are pinned verbatim, and
the discarded layer's `ftboot` is confirmed absent from the replacement. Page 5 (664) is a clean
typewritten exhibit whose misread layer is nonetheless kept, because recognition read no better;
its kept (still garbled) text was read and confirmed to be a corrupted rendering of the same
clearly legible source content, not something else. Peak converter RSS measured about 724 MiB
against a 1024 MiB ceiling.

### Pages whose writing is drawn

`ImageOnlyPageTests.swift` covers [#176](https://github.com/vocaro/PDFReflowLib/issues/176) on
synthetic slides built from real glyph outlines: a 720×405 page with a dark full-bleed fill, a
folio drawn as text and a sentence drawn as filled glyph paths is recognized under `.automatic`
and `.automaticKeepingImageBackedText` and not under `.never`; the same page printed dark on
light is recognized too. Three negative controls are left alone: the same slide with discs
instead of writing, the same slide with its sentence inside a placed raster (the photograph
case), and a slide whose sentence is ordinary visible text. Unit tests pin the letter-less
predicate (`reflowsNoWords`: a folio, a section folio and an answer key of surds reflow no words;
`5 Goals` does), the two-row threshold (`carriesDrawnText`), the English gate and the one render
it allows (`judgeImageOnly`), and the ink polarity: white writing on a dark ground reads three
rows only once the page is measured against its own background, the same writing dark on light
reads three without inversion, and a mostly dark page whose printed text already forms rows is
never inverted.

Porting this onto main required one adaptation `TextLayerPlausibilityTests.swift` did not:
`GraphicsReader.Result` gained an `images` field (placed raster XObjects specifically, alongside
the existing undifferentiated `regions`) so the pipeline can exclude a page's photographs from
the ink test, the same way the branch's richer graphics model already could. The pipeline's
`drawsTextCandidate` gate also does not require `!imageBackedText` the way the branch's did:
main has no equivalent of `layoutComesApart` (#117, not ported), so an ordinary slide with a
full-bleed background paint already reads as image-backed here, and gating this check out on
that signal would leave it unable to fire on the exact case it exists for. `reflowsNoWords`
(no letters at all) is what actually keeps it out of the implausible-layer check's territory
instead; see [architecture.md](architecture.md) for why that is safe.

`ntrs-20180003024-earthdata-slides-2018` gates this end to end: the Earthdata slide deck that
motivated #176 upstream is now fetched, converted and reviewed against Poppler rasters of its 21
slides, with slide 5's recognized question checked word-for-word against its source raster; see
[corpus.md](corpus.md#earthdata-cloud-analytics-project) for what is and is not pinned there.

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
short pages, non-English declarations, or the Blue Book, 9/11 and FAA source fixtures already on
main (the original branch's controls also included Wallace algebra answer-key and USGS
numeric-table fixtures; those corpus documents are not fetched in this port). End to end, `.never`
retains the unreadable text with `damagedTextEncoding` and a source-page image (or
`referenceImageOmitted`), every automatic policy recognizes the page instead and reports
`ocrUsed` with the readable text, the mapped control is never flagged, and in a two-page book
only the damaged page is flagged and referenced. The bundled prose, scanned, columns, graphics,
lists-code and rotated fixtures carry no evidence.

Porting this onto main needed no pipeline adaptation beyond fitting it alongside the #93/#7/#176
logic already there: the structural/text-statistics check itself (`TextEncodingCheck.swift`) is
unchanged from the abandoned branch, since it has no dependency on anything else that evolved.
`implausibleLayer` (#93) and `drawsTextCandidate` (#176) are each additionally gated on
`!damagedEncoding`, so a page this check explains is never also judged by those; `reflowsNoWords`
already excludes real letter content from #176's territory, so this gate is defence in depth
rather than load-bearing, matching how the abandoned branch kept it too even after #93/#176 were
layered on.

The `census-rrs2002-01` corpus contract requires `damagedTextEncoding` on pages 2-20 (verified
present on exactly those 19 pages, not the cover), the reviewed page-3 phrases through OCR
(`Data Files`, `Two data files were used.`, all 16 numbered fields), page 2's title/byline/heading,
and no `damagedTextEncoding` on the cover page through the new `absentWarningCodes` expectation,
which `check_corpus_content.py`'s own unit tests exercise with a same-page negative control. See
[corpus.md](corpus.md#issue-30-coverage-expansion) for what was reviewed on the real document and
what remains unverified beyond the warning/recognition pattern.

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

[Local-header evidence](../measurements/local-header-regressions/record.md) includes the failing
baseline, complete corpus receipts and before/after text and image comparisons. Corpus assertions
remain selected contracts, not comprehensive quality scores; inspecting differences also catches
regressions outside those selected pages.

Our Flag pages 34/42/43 additionally protect the alphabetical row order of four illustrated entries
and four retained images per page. The footer candidate band stays at the existing outer 7%;
the header band extends to 10% for the 9/11 source. Wider footer removal needs independent
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
Multi-paragraph/cross-page ownership, chapter-scoped reference links, multiple-reference
relationships and return navigation remain open under #11.

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
fonts, transforms, Forms, character maps, text state and excessive work. The original single-run
test still requires unchanged text when source-operator evidence is unavailable.

The complete DGA contract requires the corrected words, the existing title, source image and
`unverifiedTextLayer` warning. The [comparison evidence](../measurements/native-label-spacing/record.md)
uses compatible per-run capability receipts and permits only these two exact literal replacements
in parsed pages and XHTML. It does not claim correct diagram-label ownership or general spacing repair.


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
