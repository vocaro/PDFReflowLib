# Regression testing

Regression coverage across PDF types is the first development priority. A fix to extraction,
layout or rendering needs a reproducer and positive controls from other layouts, because a valid
EPUB can still contain wrong text, wrong reading order or unreadable images. This is the runbook:
how to run each gate, what it checks, and how to add a case or a fixture. What each rule is and
why is in [behaviour](behaviour.md) and [decisions](decisions/README.md); the tests themselves
carry their issue linkage as `.bug()` traits.

## Gates

| Lane | Command | Runs |
| --- | --- | --- |
| Fast | `scripts/check-all.sh --fast` | Swift suite, release build, Python tool tests, measurements policy, documented builds, documentation counts, issue citations, PDFKit concurrency smoke gate, six fixture conversions with structural checks, conversion-policy cases |
| Full | `scripts/check-all.sh` | Fast, plus the FAA memory gate when `corpus/cache/faa-h-8083-25c.pdf` (or `PDFREFLOW_REAL_PDF`) exists; absence is printed as a skip |
| Corpus | `scripts/check-all.sh --corpus` | Fast, plus the structure-memory gate, the repeated-conversions gate and <!-- counts:corpus-documents -->18<!-- counts:end --> complete cached conversions with EPUBCheck. Requires `epubcheck` on `PATH` and every cached source; missing data fails explicitly, and nothing is downloaded |

The gate scripts share their plumbing through the `tools/pdfreflow_tools/` package: `corpus.py`
(the repository root, manifest and contract loading, byte-count and SHA-256 identities),
`converter.py` (fresh converter and EPUBCheck processes), `epub.py` (archive admission and package
parsing) and `swift_sources.py` (the library files each standalone probe under `tools/probes/`
compiles against).

Run from the repository root with a full Xcode selected. Python tool tests and the source-region
image checks need numpy and Pillow; Poppler is needed only to render new region references.
Fetch sources with `tools/fetch_corpus.py --case <id>` (checksum-verified, cached in ignored
`corpus/cache/`); publisher-blocked downloads need an owner-supplied original ([corpus](corpus.md)).

What the individual gates check:

- `swift test`: <!-- counts:swift-tests -->359 Swift Testing tests<!-- counts:end --> with no known-issue wrappers, using the real Apple
  PDF/OCR stack. They cover extraction, the document model, layout, raster pixels (crop origins,
  rotations, annotations, resource ceilings), preserved regions (fraction bars, raised exponents
  and all six cells of a ruled table in actual EPUB images at 72/144 DPI, with prose and code
  controls), the writer, progress, cancellation before and during packaging, invalid input,
  resource limits, output protection, fixture identities and chapter navigation. The public-API
  concurrency test overlaps four conversions and one cancelled conversion, checking ownership,
  styles, images, monotonic progress and staging cleanup. For iOS:
  `xcodebuild test -scheme PDFReflowLib-Package -destination 'platform=iOS Simulator,name=iPhone 18 Pro' CODE_SIGNING_ALLOWED=NO`.
- `python3 -m unittest discover -s tools -p 'test_*.py' -v`: <!-- counts:python-tests -->210 Python tests<!-- counts:end --> over the tools,
  including the checker's negative controls, the identity tool, the memory-gate instrumentation
  (real child allocations above and below a ceiling, source verification, isolation from an
  earlier child's high-water mark), the comparison and reader servers (no Poppler or socket
  needed; a real-Poppler image-URL check through the safe HTTP handler in simple and positioned
  modes, with paths containing spaces, skips explicitly when Poppler is absent), and
  `tools/test_pdfkit_gate.py`, which runs `tools/check_pdfkit_gate.py` over `Sources/` and
  `Tests/` and fails on any font, CoreText or PDFKit call made outside
  `NativeTextReader.withExtractionLock` or `pdfKitGated` (`Tests/PDFReflowLibTests/PDFKitGate.swift`).
- `tools/update_doc_counts.py --check --swift-list`: the suite counts in `README.md` and this
  document are generated, not typed. Each lives between `<!-- counts:NAME -->` markers and is
  computed from the suites themselves — the contract counts from the check-type table in
  `tools/check_corpus_content.py` that `assess` verifies its own running total against, the
  Python count from the same `unittest` discovery this file runs, the Swift count from the
  `@Test` declarations, which `--swift-list` requires to equal what `swift test list` reports.
  A stale number fails here with the diff and the command that fixes it, and a merge conflict
  confined to a generated region is resolved by rerunning `python3 tools/update_doc_counts.py`
  (a conflict that also touches prose is reported, not guessed at). Counts were hand-typed until
  #156: they collided on nearly every parallel merge and drifted between them.
- `tools/check_issue_citations.py`: no `README.md` or `doc/**` file may cite a closed issue as the
  live tracker for a gap. Twelve did, for defects this library still has, because the branch that
  closed them was merged with the `ours` strategy and its content never arrived (#234, #231). A
  citation of a closed issue must appear in the gate's `ALLOWED` table with the reason it is
  historical, and an entry marked `branch-only` must name, in every document that cites the issue,
  the branch commit that holds the unported fix. An entry no document cites fails too, so the
  table cannot outlive the prose. `doc/decisions/**` is exempt by directory: a decision record is
  a dated record of what was weighed, not a tracker, and editing its citations to stay current
  would falsify it. The issue states are the checked-in snapshot `doc/issue-states.json`, so the
  gate needs no network and never passes merely because GitHub was unreachable; refresh it with
  `python3 tools/check_issue_citations.py --refresh` and commit the result. The snapshot's one
  blind spot — an issue closed after its capture date — is printed on every run with the
  snapshot's age, and the first citation of an issue newer than the snapshot fails until it is
  refreshed.
- `tools/check_measurements.py`: no raw capture and at most two megabytes added under
  `measurements/` relative to the base branch ([decision 0006](decisions/0006-measurements-are-records.md)).
- `tools/check_documented_builds.py`: compiles every probe under `tools/probes/` from the source
  list in `tools/pdfreflow_tools/swift_sources.py`, and then runs each `swiftc` command the
  runbooks print — `doc/corpus.md`'s capability probe, `doc/memory-testing.md`'s PDFKit memory
  probe and the two capture commands below — exactly as written, with only the `-o` target moved
  into a scratch directory. A probe the library has outgrown, and a documented build renamed,
  deleted or repointed, fail here instead of the next time somebody follows the runbook (#204).
- `tools/check_pdfkit_concurrency.py --modes native --workers 1 8 --trials 2 --iterations 50`:
  fresh-process native extraction on original RoleMap/MCR and structure-tree-absent fixtures,
  asserting exact line text and 12/24-point fonts. It runs alone because contention from other
  gates would change the interleavings it samples.
- `tools/check_epubs.py`: converts the six bundled fixtures and runs independent content, ZIP,
  XML and link checks plus EPUBCheck when given `--epubcheck`. It enforces the 60,000-byte spine
  body target on every converted fixture and corpus document: an oversized document may hold only
  one indivisible block, its optional preceding source-page marker and up to 6,000 bytes of
  headings kept with it, and no document but the last may end with such a heading run. Python
  negative controls reject multi-block overflow, unwrapped text and separated headings.
- `tools/check_conversion_policies.py`: actual CLI policy combinations through the structure
  checks, optional EPUBCheck and the internal reader. Invalid and over-budget requests must fail
  without output or completion. `prose.pdf`'s running header must be absent by default and with
  `--repeated-headers-and-footers remove`, present on all three pages with `keep`, and
  byte-identical across two `keep` runs with a pinned identifier and date; invalid values must
  name `remove` and `keep`. `--ocr keep-image-backed` must still recognize the scanned fixture's
  absent text. Reader tests check JPEG MIME admission and both ZIP/expanded byte limits.
- `tools/check_structure_memory.py` (corpus lane): a fresh process against the
  checksum-verified FAA source under a 192 MiB Mac RSS ceiling, protecting the structure index
  from eager loading of sparse ParentTree arrays; `--maximum-rss-mib` overrides it.
- `tools/check_repeated_conversions.py` (corpus lane): converts the Fed three times in one
  process through the public API with pinned packaging and runs `leaks` after each round. Every
  round must reproduce the first round's EPUB, and leaked objects added per conversion must stay
  within 30 per page (`--maximum-leaked-objects-per-page`); leaked bytes are reported, not gated.
  See [memory testing](memory-testing.md#repeated-conversions-in-one-process).
- `scripts/check-pdf-reflow-memory.sh` (full lane): the FAA conversion under its manifest
  ceiling; see [memory testing](memory-testing.md).
- `tools/run_corpus_regressions.py` (corpus lane): the [corpus lane](#the-corpus-lane) below.

### Parallel gates

`check-all.sh` runs its gates in three steps. The Swift suite and the release build run one after
the other, because they share `.build`'s lock, alongside the Python tool tests and the
measurements policy. The PDFKit concurrency smoke gate then runs alone. Every remaining gate
then starts at once, each in its own processes with its own log under the printed results
directory; the corpus lane converts `PDFREFLOW_CORPUS_JOBS` (default 6) cases at a time, largest
source first. A failed gate prints its log's tail; the others still finish, and the script ends
with a table of every gate's seconds. A failure in the first step stops the run, since later
gates need its build.

`PDFREFLOW_CHECKS_SERIAL=1` runs every gate and corpus case one at a time, with output on the
terminal: the reference to check a failure seen only in the parallel run against.

The converter is single-threaded (CPU seconds match wall seconds on every corpus case), so cases
in separate processes scale with cores. Peak RSS is measured per process, so concurrent cases do
not share a reading. Under host memory pressure macOS compresses and pages out resident memory,
and a conversion could come in under a ceiling it would exceed on an unloaded host, so the
evaluator samples `kern.memorystatus_vm_pressure_level` throughout each conversion, records
`peakMemoryPressureLevel` and `concurrentEvaluations` in `result.json`, and fails the memory gate
when pressure rises above normal. Every current ceiling together totals 7.5 GiB. Serial and
six-job runs on one commit agree on every case under `tools/compare_conversion_runs.py` and in
their content assessments; in parallel, peak RSS reads 1–13% higher, not lower, and conversion
times include contention ([record](../measurements/parallel-gates/record.md)).

### Inspecting large outputs

The content inspector defaults to at most 10,000 ZIP entries and 536,870,912 total uncompressed
bytes (512 MiB). For an existing evaluation with a reviewed contract, set
`--max-entries 20000 --max-uncompressed-bytes 4294967296` to admit up to 20,000 entries and
4 GiB. Both flags are optional, independent, inclusive ceilings; values must be positive
integers no greater than Python's `sys.maxsize`; there is no unlimited value. Invalid values
exit with status 2; an archive over either ceiling fails inspection. Python callers pass the
same keyword-only `max_entries` and `max_uncompressed_bytes` to `read_pages(path, ...)` or
`check_evaluation(case, contract, directory, ...)` in `tools/check_corpus_content.py`. Limits
are checked before reading package or chapter contents; duplicate-entry, page-boundary,
image-presence and contract checks still apply. ZIP metadata is read when the archive opens;
chapters are parsed individually and page content accumulates in memory. These are admission
ceilings, not process budgets or EPUB security validation. The
[large-inspection evidence](../measurements/large-epub-inspection/record.md) exercises NOAA-scale
synthetic data and both retained full NOAA EPUBs; NOAA still has no passing default-budget
contract, and larger ceilings change no conversion policy or exclusion.

## The corpus lane

```sh
tools/run_corpus_regressions.py --converter <CLI> --epubcheck <executable> --output <new-directory>
```

Repeat `--case <id>` to narrow a debugging run; the summary lists omitted cases explicitly, and a
failing case does not hide later results. `--jobs N` evaluates N cases at once (default 1).
Each case verifies the pinned source identity, converts in a fresh release process, checks EPUB
structure, EPUBCheck, monotonic progress, the manifest memory ceiling and the reviewed content
contract in [corpus/regressions.json](../corpus/regressions.json):
<!-- counts:contract-coverage -->490 checks on 110 reviewed pages across 18 documents<!-- counts:end -->.
All source-page anchors must remain complete and ordered, and semantic text must
contain no image-attachment placeholders. The manifest consistency test requires every corpus
document to be covered or explicitly excluded; full Warren and NOAA conversions are excluded for
the known image-output ceiling failure (#5), listed in output and never counted as passes.

<!-- counts:contract-breakdown -->
Those 490 checks are 4 `spineContinuity`, 72 `text`, 184 `orderedText`, 32 `absentText`,
29 `headings`, 36 `paragraphs`, 6 `continuedParagraphs`, 16 `scripts`, 17 `imageRegions`,
69 `minimumImages`, 20 `warningCodesAnyOf` and 5 `absentWarningCodes`, counted as
`tools/check_corpus_content.py` counts them.
<!-- counts:end -->

Contract expectations per page: `orderedText` and `text` (selected correct words in order),
`paragraphs` (a phrase inside one spine paragraph on that source page; a phrase spread over
separate paragraphs, headings or preformatted text cannot pass), `continuedParagraphs` (one
paragraph element ends page N with one phrase and continues page N+1 with the other),
`headings` (phrases that must remain semantic headings on the correct page; the parser keeps
inline styles and page boundaries, including across spine files), `absentText` (reviewed
unwanted text such as running headers), `scripts` (superscripts and subscripts, including
inside `<pre>` and nested emphasis), `warningCodesAnyOf` and `absentWarningCodes`,
`minimumImages` (presence only), and `imageRegions` (below). The checks read the actual spine,
track page boundaries inside styled text, preserve ownership across chapter-file continuations
and exclude navigation and captions from source-text matching; they do not freeze serialization
or bless broken output such as interleaved columns. The checker has negative controls for
deleted text, text moved to the wrong page, reversed order, missing images, flattened or
misplaced scripts, missing or wrong-page warnings, changed source identity, failed conversion,
missing or duplicate page markers, headers reintroduced into prose, headings flattened or moved,
empty expectations and captions masquerading as source text.

One expectation belongs to the book rather than to a page. A case may carry `spineContinuity`, a
list of reviewed spine-document boundaries. Each entry names the source pages on both sides and
the phrases the source sets on either side of a join: every phrase must occur exactly once in the
whole book and the phrases must run in order, either inside one spine document or with the
earlier ones in one document and the later ones in the very next, and the documents at both ends
must carry the reviewed source pages. `contiguous` additionally forbids any word between the last
phrase before the join and the first one after it, so text may be neither dropped nor inserted
there. Blocks are atomic, so a paragraph never straddles two spine documents; what this protects
is that the reading order runs on across the seam.

Where the packer ends a document is deliberately not pinned. It follows from the serialized byte
target, so any change to the block stream moves it, and a contract that demanded a boundary at a
named place would fail for a book whose text is perfectly intact — as the Wallace entries did the
first time the layout changed under them. A join the packer keeps inside one document therefore
passes, held to the same text. The assessment reports `spineBoundariesCrossed`, the number of
entries that did straddle a boundary, so a lane that has stopped exercising one is visible instead
of silently green; today the Fed entries cross and the Wallace entries do not. Negative controls
cover the reverse order, a boundary two documents away, a repeated tail, a dropped opening, an
inserted sentence on either side of a seam, wrong source pages and malformed expectations, over
built archives and over a real converted EPUB whose seam was edited
([record](../measurements/spine-continuity/record.md)).

`tools/check_corpus_content.py --case <id> --evaluation <directory>` reruns the contract on an
existing evaluation without reconverting; `tools/check_corpus_quality.py --case <id> --evaluation <directory>`
applies a manifest's opt-in quality expectation (page-specific warnings on a valid conversion, or
an explicitly approved quality-refusal diagnostic with no output and no false completion; no
refusal API exists yet, so this contract exposes gaps without changing runtime behaviour).
Image-presence checks are weaker than visual fidelity checks, and the lane supplies no
whole-book quality score or device qualification.

Evidence for the current state of the lane: [cross-corpus-regressions](../measurements/cross-corpus-regressions/record.md),
[quality-and-raster-fixes](../measurements/quality-and-raster-fixes/record.md).

### Source-region image checks

Preserved tables, equations, figures and page fallbacks are images, so text checks cannot see
them. An `imageRegions` expectation names a committed reference under `corpus/references/<case>/`.
`tools/render_region_reference.py` renders a reviewed source region (PDF points from the page's
top-left) with Poppler at 180 DPI after verifying the source identity, averages it to 36 DPI
grayscale, trims it to ink and writes a sidecar with the region, renderer and source checksum.
Choose regions from the source page, never from converter output. The checker averages every
image on that page the same way at all 25 grid phases and searches all placements for the
highest normalized correlation (`tools/image_regions.py`); a page passes when some image reaches
`minimumCorrelation`, 0.95 by default. References assume the library's default 180 DPI; a changed
raster policy must regenerate them.

Seventeen references cover the Our Flag flag-size table, three USGS copper tables, three FAA
page-121 figures, the FAA page-19 airmail map beside recovered column prose, a Wallace quadratic
exercise, the Geltman page-image fallback, CDC's image-only page 13, and six rows and columns
inside the two table crops. Correct crops score 0.982–0.997; wrong images on the same pages score
at most 0.62, a table crop with its lower half blanked 0.64,
erasing the Wallace exercise from its crop 0.44, and a 1.5-pixel blur still scores 0.96. The check
proves a region is present, complete and aligned, not every glyph: erasing one exponent from the
Wallace exercise still scores 0.97 ([record](../measurements/image-regions/record.md)).

A whole-table reference is insensitive to one row or one cell, so tables are also pinned row by
row and column by column: a row reference holds one row's label and all its cells, a column
reference the column's header and every value under it. Erasing a row scores 0.676 (USGS) and
0.870 (Our Flag) against its row reference, while the whole-table reference scores 0.954 and
0.927 and so misses the USGS row; erasing one cell scores 0.870–0.919 against its row reference
and 0.951–0.986 against the whole table, which misses it. A value moved to another row scores
0.890 against the column reference and 0.962 against the whole table. Two cells of similar shape
exchanged inside a row or a column are not caught at 0.95 (0.957–0.983 measured), so row and
column references qualify completeness and grouping, not the identity of an individual cell.

#### Why there is no colour or pixel appearance gate

A region reference is rendered `-gray` and every converted image is converted to `L` before
comparison, so colour never reaches the statistic. Recolouring CDC's page-13 comic to its
complementary hues in CIE Lab, which keeps lightness and changes 23% of the pixels by more than
20 levels in some channel, moves the score from 0.9972 to 0.9970. The check therefore cannot
speak for a flag's colours or a diagram's colour coding, and the contracts do not claim to.

Tightening it is not simply a matter of comparing colours or raising the floor. The reference
comes from Poppler and the converted image from Core Graphics, so the two never agree exactly:
correct crops sit at 0.982–0.997 against a 0.95 floor, and about 0.03 of that margin is renderer
disagreement rather than fidelity. The same converter binary on one Mac already produces images
that differ between execution environments — 36 of CDC's images differ in decoded RGB between the
host and a sandbox, with mean absolute channel differences near 0.4–0.6 out of 255
([record](../measurements/raster-environment/record.md)) — so any exact-pixel or exact-colour
comparison is drift, not a defect. Scale is pinned too: references assume the default 180 DPI, and
a device that trips a pixel ceiling rescales every image and fails every reference.

What would make an appearance gate possible, in the order it would have to be built: render the
reference through the library's rasterizer as well as Poppler and measure how far the two
disagree per page, so the floor can be set from measured renderer drift instead of a single
hand-chosen constant; add a colour statistic robust to that drift, such as the mean hue and
chroma of the few largest flat regions of a crop, which would catch a flag's canton turning the
wrong colour without asserting any pixel; and record the raster policy (DPI and any binding
ceiling) in the sidecar so a run under another policy skips the reference explicitly instead of
failing it. Until those are measured, the lane keeps presence, completeness and alignment, and
image legibility and colour stay unqualified.

## Adding or changing a regression

1. Reproduce the defect using a pinned source. Add a small original synthetic PDF or operator
   fixture when that isolates the mechanism, and retain a source-derived real-document target.
2. Read the source visually before writing expected text, order, cell values or image
   properties. Never derive expected correctness from the converter being tested.
3. Prove the test fails on the old behaviour. Keep unresolved defects as GitHub issues rather
   than blessing them as golden output or disguising them as passing tests.
4. Add positive controls for neighbouring behaviours and another document type (attachment
   filtering, for example, must retain mixed styled text, blank scans, recoverable OCR and images).
5. Run the fast and corpus lanes. Review changed content and image counts; increases and
   decreases can both be suspicious. Update expectations only after reviewing the source and
   explaining the intended change. Preserve historical measurement receipts
   ([decision 0007](decisions/0007-records-cite-commits-in-prose.md)).

A new corpus document gets a manifest entry (identity, rights, coverage, review pages, memory
ceiling), a `corpus/<id>-review.json` of review points, a contract in `regressions.json` whose
`basis` says what was reviewed against the source and how, and a baseline record under
`measurements/<id>/`. A rights constraint on committed rasters (USCIS, the USDA magazine's page
24, the NASA insignia on every Earthdata slide) means no `imageRegions` or `minimumImages` for
that case.

Run a case alone and review it against the source:

```sh
python3 tools/fetch_corpus.py --case <id>
swift build -c release --scratch-path .build/corpus-cli
python3 tools/evaluate_real_document.py --case <id> --pdf corpus/cache/<file>.pdf \
  --converter .build/corpus-cli/release/pdf-reflow --output /tmp/<id>-baseline \
  --epubcheck /opt/homebrew/bin/epubcheck
python3 tools/compare_pdf.py --pdf corpus/cache/<file>.pdf \
  --converter .build/corpus-cli/release/pdf-reflow --output /tmp/<id>-review --serve
```

Output directories must be new. [corpus.md](corpus.md) lists each case's review pages and
commands; [comparison.md](comparison.md) describes the side-by-side viewer.

## Capturing a layout fixture

Source-derived layout JSONs under `Tests/PDFReflowLibTests/fixtures/` capture native extraction
(text, geometry, attributed runs; never converter output, never the PDF or font programs) from
checksum-pinned sources, so the layout tests run offline on macOS and iOS. The schema is an
internal test schema (`SourceLayoutFixture`, versioned; captures without a version decode as
version 1), not a public intermediate-format contract. With full Xcode selected, from the
repository root (`tools/pdfreflow_tools/swift_sources.py` lists the library files each probe under
`tools/probes/` compiles against):

```sh
swiftc $(python3 tools/pdfreflow_tools/swift_sources.py capture-layout-fixture.swift) \
  -o /tmp/capture-layout-fixture
/tmp/capture-layout-fixture faa-phak-8083-25c 91 /tmp/faa-91-layout.json
```

The tool verifies the cached PDF against the manifest SHA-256. `capture-algebra-layout.swift`
captures the Wallace algebra pages (it rejects any source checksum other than the pinned book)
and `capture-ocr-layout-fixture.swift` captures Vision extraction:

```sh
swiftc $(python3 tools/pdfreflow_tools/swift_sources.py capture-algebra-layout.swift) \
  -o /tmp/capture-algebra-layout
/tmp/capture-algebra-layout corpus/cache/Beginning_and_Intermediate_Algebra.pdf /tmp/algebra-17-layout.json
```

A layout capture records PDFKit's own reading, which the spacing reader then repairs; capture one
with the reader in the state whose defect the test pins, and never recapture a fixture to make a
repaired line agree with itself.

`capture-spacing-source.swift` captures the other half of a spacing test: one page's own content
stream and the font metadata the reader reads from it (subtype, font matrix, first code, widths,
encoding, `ToUnicode`), plus the names of the other resources the stream mentions. No font program
is captured, so the rebuilt page places text exactly as the source does and draws nothing, which
is all the reader measures. `SpacingSourceFixture.document()` rebuilds it through a byte-exact
Latin-1 writer, because the captured stream and CMaps hold bytes outside ASCII.

```sh
swiftc $(python3 tools/pdfreflow_tools/swift_sources.py capture-spacing-source.swift) \
  -o /tmp/capture-spacing-source
/tmp/capture-spacing-source gpo-911-2004 19 /tmp/911-19-spacing.json
```

Review source and geometry changes before replacing a bundled fixture; never regenerate one
merely to make a test pass. The algebra fixtures remain Tyler Wallace's CC BY 3.0 material and
the government-document fixtures keep their publisher provenance; both are listed in
[third-party notices](third-party-notices.md). Each fixture records its publisher URL, title and
source checksum.

## Regenerating the bundled fixtures

Six original PDFs (eight pages) are bundled with the tests and listed in the README's fixture
table. `tools/generate_fixtures.py` regenerates them and their manifest (byte counts and
SHA-256 identities) with ReportLab, Pillow and Poppler's `pdftoppm`, using original text and
drawings and standard PDF fonts without embedding font programs; pass
`--renderer /absolute/path/to/pdftoppm` when needed. Regenerate the PDFs and the manifest
together, inspect every rendered page, and rerun both suites. These tools are development-only.

## Validating EPUBs

```sh
swift build
python3 tools/check_epubs.py --converter .build/debug/pdf-reflow \
    --output /tmp/pdfreflow-validation --epubcheck /opt/homebrew/bin/epubcheck
```

The output directory must be new. Omitting `--epubcheck` runs only the independent structural and
content checks. The command retains EPUBs, per-book validator logs and JSON reports; its elapsed
time includes the validator and is not a conversion benchmark.

## Concurrency campaigns

For a longer native campaign than the smoke gate:

```sh
python3 tools/check_pdfkit_concurrency.py --output /tmp/native-stress \
  --modes native --workers 0 1 8 --iterations 1000 --trials 10
```

Worker count zero runs on the main thread; one runs serially on a background thread; higher
counts start independent threads together, and no PDFKit document, selection or attributed string
crosses threads. Each iteration opens its own document inside an autorelease pool. Use
`--optimization debug` for an unoptimized build. The diagnostic compiles the actual native reader
and value types. For the unmitigated Apple-SDK control, which can deliberately reproduce a
process abort:

```sh
python3 tools/check_pdfkit_concurrency.py --output /tmp/pdfkit-sdk-stress \
  --sdk-only --workers 1 8 --iterations 1000 --trials 5
```

This build excludes all library sources and compares plain versus attributed selections. A new
output directory is mandatory. The runner preserves every child exit code, stdout/stderr,
input/producer/binary identity and trial result; it never retries a failed trial; timeouts kill
and reap the child process group; a zero exit without a complete matching positive-control
receipt is a failure, and Python negative tests enforce these properties. A finite passing
campaign is bounded evidence, not proof that all concurrent PDFKit use is safe. See
[decision 0002](decisions/0002-pdfkit-extraction-gate.md).

## Comparing runs across environments

Rasters and OCR can differ between builds launched from different execution environments on the
same Mac. For a strict drift comparison, run both evaluations with the same compiled capability
probe and compare them with `tools/compare_conversion_runs.py`; the procedure and its receipt
rules are in [corpus.md](corpus.md#comparing-conversion-runs). Byte identity for refactors is a
separate, stricter check on one host ([decision 0004](decisions/0004-byte-identity-gate.md)).
