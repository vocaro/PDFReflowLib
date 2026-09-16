# PDFReflowLib

An independent Swift library that converts local PDFs to reflowable EPUB 3 on iOS, iPadOS and
macOS 27+. Text becomes selectable XHTML; illustrations and recognized difficult regions retain
their appearance as images. Conversion uses PDFKit, Core Graphics, Vision and ImageIO on the
device. It makes no network requests, calls no language model, and requires no account or
shipped model weights.

The only package dependency is ZIPFoundation
0.9.20 (MIT), pinned in the manifest and resolution file. The macOS `pdf-reflow` executable is a
small developer client of the same public API.

SwiftPM directories use `Sources/` and `Tests/` with target-matching subdirectories.
Supporting directories (`corpus/`, `tools/`, `scripts/`, `doc/`, `measurements/`) use lowercase names.

## Swift API

Add `https://github.com/vocaro/PDFReflowLib.git` as a Swift package dependency and link the
`PDFReflowLib` product. Pin a commit for reproducible builds. Swift 6.2 or newer and the Xcode 27
SDK are required; the minimum runtime is iOS/iPadOS 27 and macOS 27.

```swift
import PDFReflowLib

var options = ConversionOptions()
options.title = "My book"
options.language = "en"

let converter = PDFConverter()
let report = try await converter.convert(
    from: inputPDF,
    to: newEPUB,
    options: options
) { event in
    await MainActor.run {
        // Update your UI's progress state here.
        print(event.stage, event.fractionCompleted)
    }
}

for warning in report.warnings {
    print("Page \(warning.page): \(warning.message)")
}
```

`PDFConverter` is an actor. PDF parsing, reconstruction and compression run outside the main
actor. The async, Sendable progress callback is awaited in order for each conversion; keep it
short. Its fraction is a monotonic work estimate, not a remaining-time estimate, and reaches
1 only after the finished EPUB appears at the destination. Source page numbers are one-based.
The report distinguishes pages with reflowed text, pages sent through OCR, and emitted images;
a successful archive is not a claim that every source page reflows.

Run conversion inside a Swift `Task` and cancel that task to stop. Cancellation is cooperative
at page, line and archive-chunk boundaries; an in-progress system PDF rendering or recognition
operation may take time to return. Conversions waiting for the library's native-text extraction
lock check cancellation between timed waits. Cancellation or failure removes staging files. An existing
output is never overwritten. Input and output must be local file URLs. The caller keeps any
security-scoped access alive until conversion returns and owns the destination's lifetime.

Clients independently control reference inclusion, full-page and cropped-region encoding,
JPEG quality, and output size. Existing defaults remain automatic references and PNG.

```swift
options.referenceImages = .never          // Supplementary references only
options.fullPageImageEncoding = .jpeg(quality: 0.90)
options.regionImageEncoding = .png        // Independently selectable
options.maximumOutputBytes = .max         // Disable the entry-byte budget
options.maximumEPUBBytes = 512 * 1_024 * 1_024 // Cap the final ZIP file
```

`.smallest(jpegQuality: 0.90)` encodes PNG and JPEG and keeps the smaller file; it does not
assess visual fidelity. `.always` adds references on every reconstructed page; `.never` retains
required image-only fallbacks and figure crops, with warnings when recommended references are
omitted. [Conversion options](doc/conversion-options.md#recommended-starting-settings) gives measured starting
settings, provisional recommended ranges, and each control's tradeoffs.

Other options select automatic/disabled/always OCR or opt-in retries of image-backed existing
text (`.automaticIncludingImageBackedText`), language, title, author, recurring header/footer
removal, raster resolution, and ceilings for input bytes, pages, characters, raster pixels and
uncompressed output bytes. Default ceilings are 256 MiB input, 2,000 pages, 20 million characters,
12 million pixels per raster, 180 DPI and 512 MiB output content. These are input/work bounds,
not a process-memory or wall-clock guarantee: positioned pages are written to the workspace
between extraction and reconstruction, the logical text of the book is retained until writing
finishes, and images are written individually to disk. PDF documents are
reopened in eight-page windows, synchronous page work drains autoreleased objects, and pages
that fall back to images skip unused attributed-text decoding. Failures use
`ConversionError`, `CancellationError`, or the underlying filesystem error.

## Conversion behavior

- PDFKit line selections pair text with geometry; font runs preserve bold and italic emphasis.
  Image attachment placeholders are excluded from semantic text and reflow counts; their
  visible content remains in images. Placeholder-only pages follow the selected OCR policy.
  Whitespace cuts recover ordinary columns and spanning headings. Paragraph reconstruction
  joins hard wraps and narrowly supported cross-page continuations.
  A bounded Type3 source-text check removes an extra native space only at a tiny kerning
  adjustment with matching character-map, text and placement evidence; ambiguous spacing remains.
- Validated PDF paragraph and H1–H6 tags supply grouping and heading levels. Complete tagged
  text groups can follow logical order inside spatial barriers. Unsupported or ambiguous tags
  report `structureFallback`; figures, lists, captions and OCR retain spatial reconstruction.
  This is bounded tag support, not full tagged-PDF or accessibility reconstruction.
- Soft hyphens are removed at wraps. A hard hyphen is removed only when the unbroken word occurs
  elsewhere in the book and there is no evidence of the corresponding compound. Ambiguous
  joins retain the hyphen and produce a warning.
- Short recurring headers and footers can be removed when at least three pages support the
  decision. Monospaced code retains line breaks and indentation; list markers retain their
  source breaks, except that a wrapped line of justified prose that merely begins with an
  initial, a citation abbreviation or a year followed by a period continues its paragraph.
  Visible typography supplies flat heading navigation. Exclusively invisible
  text over scan images does not supply reliable code or heading typography.
- Core Graphics scans placed images, nested forms and painted paths. The original page renderer
  supplies crops containing figures, ruled tables, labels and recognizable displayed formulas,
  including bounded detached fractions.
  Numeric dot-leader tables with supported geometry and OCR table regions also become images. Images preserve compositing and appearance rather than
  exposing raw image resources with missing masks or detached labels.
- Vision recognizes pages with missing/damaged text by default. OCR text is explicitly reported
  as transcription, with an accompanying original-page image by default.
  Existing text over a page-sized graphic retains a source reference image by default and reports
  `unverifiedTextLayer`: transcription, tables, numbers and reading order need human review.
  This conservative signal is not an OCR confidence score; it can also flag illustrated pages
  with valid text. Smaller graphics and undetected scans can still contain transcription errors.
- Rotated pages, unsupported drawing operations and pages without recoverable text use an
  explicitly warned whole-page image fallback. Visible annotations get a source reference
  image by default; link/form interactions are not reconstructed.
- EPUB output includes XHTML chapters, styles, metadata, heading navigation, a source page-list,
  an OPF 3.0 package, and the required first/uncompressed `mimetype` ZIP entry. Chapter files
  split near 60 KB at block boundaries and start at [validated numbered chapter bookmarks](doc/architecture.md).
  XML escapes source markup; source scripts, attachments,
  actions and remote resources are not copied into the EPUB.

PDF structure is ambiguous. The synthetic regression suite and initial FAA handbook evaluation
do not establish general textbook fidelity. Untagged borderless tables, arbitrary equations, complex
magazine layouts, footnote relationships, vertical/RTL reading order, and damaged font encodings
still need broader qualification. The detector cannot identify every difficult region. Fonts,
original colors, full tagged-PDF semantics, links and interactive elements are not reproduced.
Cropped text is neither reflowable nor accessible as text; generic image descriptions identify
its source page rather than inventing a description of the picture. Review warnings and compare
the source before distributing a derived book. [Architecture](doc/architecture.md) describes
the internal seams and extension points.

## Development and regression tests

For changes to extraction, layout or rendering, run `scripts/check-all.sh --corpus` before
pushing. This opt-in lane converts 15 complete cached documents and checks reviewed content,
EPUB conformance, progress and resource budgets. Missing sources fail with acquisition instructions;
there are no automatic downloads. `scripts/check-all.sh --fast` remains the offline synthetic lane.
Python tool tests and source-region image checks require numpy and Pillow. Poppler is needed only
to render new region references. See [regression testing](doc/regression-testing.md) for coverage,
limitations and adding a case.

```sh
swift test
xcodebuild test -scheme PDFReflowLib-Package \
    -destination 'platform=iOS Simulator,name=iPhone 18 Pro' CODE_SIGNING_ALLOWED=NO
swift run pdf-reflow input.pdf output.epub
swift run pdf-reflow scanned.pdf output.epub --no-ocr
```

Run from this directory with a full Xcode selected. The CLI prints progress to stderr and the
conversion report as JSON to stdout. Paths with spaces must be shell-quoted.

Six original, redistributable-with-the-project PDFs (eight pages) are bundled with the tests:

| Fixture | Regression coverage |
| --- | --- |
| `prose.pdf` | Hard wraps, discretionary/real hyphens, page continuation, furniture, headings |
| `columns.pdf` | Two columns under a spanning heading; left-before-right order |
| `graphics.pdf` | Nested image/vector form, detached label, ruled table, superscript formula |
| `lists-code.pdf` | Lists, code indentation, source markup escaping, bold/italic |
| `rotated.pdf` | Explicit appearance-preserving whole-page fallback |
| `scanned.pdf` | Real Vision OCR plus original page containing a figure |

Tests also cover monotonic progress, cancellation before/during packaging, invalid input,
resource limits, output protection, fixture identities and chapter navigation. They use the real
Apple PDF/OCR stack, not mocks. No external test documents are downloaded. The fixture manifest
records byte counts and SHA-256 identities.

For independent content/ZIP/XML/link checks and official EPUB 3.3 validation, install the optional
development tool EPUBCheck and run:

```sh
swift build
python3 tools/check-epubs.py --converter .build/debug/pdf-reflow \
    --output /tmp/pdfreflow-validation --epubcheck /opt/homebrew/bin/epubcheck
```

The output directory must be new. Omitting `--epubcheck` runs only the independent structural and
content checks. The command retains EPUBs, per-book validator logs and JSON reports. Recorded
elapsed time includes the validator and is not a conversion benchmark.

`tools/generate-fixtures.py` regenerates the corpus and manifest using ReportLab, Pillow and
Poppler's `pdftoppm`, available only for development. It uses original text/drawings and references
standard PDF fonts without embedding font programs. These tools are not runtime dependencies.
Pass `--renderer /absolute/path/to/pdftoppm` when needed. Regenerate PDFs and their manifest
together, then inspect every rendered page and rerun both suites.

## Intermediate document model

Reconstruction uses two custom in-memory Swift representations. `PageContent` holds positioned
text, font/style evidence and graphic regions. `PDFReflowLibPipeline` turns these into a
`ReflowDocument`: metadata, ordered paragraphs/headings/preformatted blocks, styled text runs,
source-page markers and image references. Images remain in temporary files; the model holds
small asset records pointing to them. The spatial representation is released before writing.

The logical model contains no HTML or EPUB paths. Word repair and page continuation operate on
text runs and source markers. The EPUB writer handles escaping, markup, chapter boundaries,
navigation and ZIP layout. Tests can inspect reconstruction directly or construct a logical
document to test serialization independently. The model is internal rather than a public
interchange format; the supported public output remains EPUB 3. See
[architecture](doc/architecture.md) for its structure and resource lifetime.

## Real-document corpus and memory gates

`corpus/manifest.json` registers the 522-page FAA Pilot's Handbook of Aeronautical Knowledge
(FAA-H-8083-25C), Tyler Wallace's 489-page Beginning and Intermediate Algebra, and the
920-page scanned Warren Commission report, the 585-page digital 9/11 Commission report, and
135-page The Fed Explained, plus the 10-page illustrated Dietary Guidelines for Americans
(2025–2030), the 1,834-page Fifth National Climate Assessment, the 56-page Our Flag booklet, the 42-page CDC Zombie Pandemic comic, the 312-page
Blue Book scanned-table report, and seven smaller sources for borderless tables, page-bottom
footnotes, damaged text encodings, Arabic and Simplified Chinese layouts, and scanned and
born-digital two-column academic papers,
by exact byte identity.
Fetch originals with
`python3 tools/fetch_corpus.py --all`; verified copies live in gitignored `corpus/cache/`.
Tests do not download documents. Some publisher endpoints require a manually supplied cache
copy; the corpus guide records current fetch limitations.
[Corpus guide](doc/corpus.md) lists their coverage, attribution and review commands. The manifest lists review points and known reading-order/raster defects, so a
successful conversion is not mistaken for a fidelity qualification.

`tools/evaluate-real-document.py` checks source identity, runs a fresh converter process,
checks EPUB structure and progress, and enforces a configurable peak-memory ceiling. It retains
reports and memory traces. [Memory testing](doc/memory-testing.md) explains the initial Mac
budget, commands, physical-device limitations and standalone PDFKit leak investigation tool.
The small allocation-control tests run without the FAA PDF.

## Side-by-side quality review

The optional [comparison harness](doc/comparison.md) runs the release CLI and an independently
installed Poppler, then shows the EPUB alongside `pdftohtml` simple or positioned HTML. Source
page navigation, reading widths, an original-page raster, warnings and exportable review notes
support manual fidelity checks. Both tools consume the same local PDF snapshot. Poppler is an
external development comparator, not a package or app dependency.

From the repository root:

```sh
scripts/compare-pdf-reflow.sh --pdf /path/to/faa-h-8083-25c.pdf \
  --pages 1,16,91,121,176,401,511 --output /tmp/faa-comparison --serve
```

Open the printed localhost URL. The output directory must be new; omit `--pages` to prepare
every page. Conversion retains whole-book context even when reviewing only selected pages.
See the harness guide for the direct Python command.

## EPUB test reader

For human reading of a complete output book, the independent [EPUB test reader](doc/test-reader.md)
provides contents, source-page jumps, chapter navigation, text size and reading width. It uses
the pinned MIT foliate-js parser and local browser rendering, without importing into an external book library:

```sh
python3 tools/view_epub.py /path/to/output.epub
```

## Distribution

The library, original test fixtures and development tools are distributed under the
[MIT license](LICENSE). [Third-party notices](doc/third-party-notices.md) cover dependencies.
The bundled algebra text/geometry test fixture retains CC BY 3.0 attribution in those notices.
Separately supplied corpus documents retain their own rights status; see [corpus guide](doc/corpus.md).

`PDFReflowLib` is the package, library product and Swift module name. The command-line executable
is `pdf-reflow`. The library has no affiliation with the
[PDFreflow e-reader](https://www.pdfreflow.com/).
