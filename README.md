# PDFReflowLib

An independent Swift library that converts local PDFs to reflowable EPUB 3 on iOS, iPadOS and
macOS 27+. Text becomes selectable XHTML; illustrations and recognized difficult regions retain
their appearance as images. Conversion uses PDFKit, Core Graphics, Vision and ImageIO on the
device. It makes no network requests, calls no language model, and requires no account or
shipped model weights.

The only package dependency is ZIPFoundation 0.9.20 (MIT), pinned in the manifest and
resolution file. The macOS `pdf-reflow` executable is a small developer client of the same
public API.

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
JPEG quality, and output size. The defaults are automatic references and automatic image
encoding, `.automatic(jpegQuality: 0.90)`: each image is classified from its own pixels, and
photographs, painted art, tonal scans, full-page mixed references and uncolored images keep the
smaller of PNG and JPEG 0.90 while colored line art, charts, drawn illustration crops and
colored text pages stay PNG. Naming `.png`, `.jpeg(quality:)` or `.smallest(jpegQuality:)`
applies exactly that.

```swift
options.referenceImages = .never          // Supplementary references only
options.fullPageImageEncoding = .jpeg(quality: 0.90)
options.regionImageEncoding = .png        // Independently selectable
options.maximumOutputBytes = .max         // Disable the entry-byte budget
options.maximumEPUBBytes = 512 * 1_024 * 1_024 // Cap the final ZIP file
```

`.smallest(jpegQuality: 0.90)` encodes PNG and JPEG and keeps the smaller file; on its own it
does not assess visual fidelity, which is what the automatic default adds. `.always` adds references on every reconstructed page; `.never` retains
required image-only fallbacks and figure crops, with warnings when recommended references are
omitted. [Conversion options](doc/conversion-options.md#recommended-starting-settings) gives measured starting
settings, provisional recommended ranges, and each control's tradeoffs.

Other options select automatic/disabled/always OCR, opt-in retries of image-backed existing
text (`.automaticIncludingImageBackedText`), or an opt-out that keeps image-backed existing text
even when it fails the plausibility test (`.automaticKeepingImageBackedText`), an opt-in for
the recognizer's language correction (`ocrLanguageCorrection`, off because it damages codes,
dates and names), plus
language, title, author, recurring header/footer removal, raster resolution, and ceilings for
input bytes, pages, characters, raster pixels and uncompressed output bytes. Default ceilings are 256 MiB input, 2,000 pages, 20 million characters,
12 million pixels per raster, 180 DPI and 512 MiB output content. These are input/work bounds,
not a process-memory or wall-clock guarantee: positioned pages are written to the workspace
between extraction and reconstruction, the logical text of the book is retained until writing
finishes, and images are written individually to disk. Failures use
`ConversionError`, `CancellationError`, or the underlying filesystem error.

## Conversion behavior

PDFKit line selections pair text with geometry and preserve bold, italic, superscript and
subscript runs; whitespace cuts recover columns and spanning headings; paragraphs are rebuilt
across hard wraps and page breaks; validated PDF paragraph and heading tags supply grouping and
levels where they are trustworthy; hyphens, recurring headers and footers, code, lists and
headings are decided by bounded, evidence-based rules. Core Graphics scans painted regions so
figures, ruled tables, labels, displayed formulas and fractions are cropped from the original
rendering, and a figure that is exactly one embedded JPEG is written as that JPEG rather than
redrawn. Vision recognizes pages with missing or damaged text, existing text that does not read
as a plausible transcription of its page image, born-digital text without a usable Unicode
mapping, and pages whose only writing is drawn; every such page is warned. Recognition can return
success while leaving whole paragraphs or table columns unread, so each recognized page is
measured against its own text-shaped ink, recognized again in overlapping bands when the reading
does not account for the page, and warned when the writing it left out remains. Output is EPUB 3 with
XHTML chapters split near 60 KB, styles, metadata, the author's own table of contents as
navigation where the document states a usable one and detected headings where it does not, a
source page-list that shows the page numbers the source prints, and an OPF 3.0 package.

Every rule, threshold and warning code is specified in the
[behavior specification](doc/behavior.md); the modules and seams are described in
[architecture](doc/architecture.md). PDF structure is ambiguous: untagged borderless tables,
arbitrary equations, complex magazine layouts, footnote relationships, vertical/RTL reading order
and damaged font encodings still need broader qualification, and fonts, original colors, full
tagged-PDF semantics and form interactions are not reproduced. Cropped text is neither
reflowable nor accessible as text. Review warnings and compare the source before distributing a
derived book.

## Development and regression tests

For changes to extraction, layout or rendering, run `scripts/check-all.sh --corpus` before
pushing. This opt-in lane converts <!-- counts:corpus-documents -->24<!-- counts:end --> complete cached documents and checks reviewed content,
EPUB conformance, progress and resource budgets. Missing sources fail with acquisition instructions;
there are no automatic downloads. `scripts/check-all.sh --fast` remains the offline synthetic lane.
Python tool tests and source-region image checks require numpy and Pillow. Poppler is needed only
to render new region references. See [regression testing](doc/regression-testing.md) for each
gate, adding a case and capturing fixtures.

```sh
swift test
xcodebuild test -scheme PDFReflowLib-Package \
    -destination 'platform=iOS Simulator,name=iPhone 18 Pro' CODE_SIGNING_ALLOWED=NO
swift run pdf-reflow input.pdf output.epub
swift run pdf-reflow scanned.pdf output.epub --no-ocr
```

Run from this directory with a full Xcode selected. The CLI prints progress to stderr and the
conversion report as JSON to stdout. Paths with spaces must be shell-quoted.

Eight original, redistributable-with-the-project PDFs (eleven pages) are bundled with the tests:

| Fixture | Regression coverage |
| --- | --- |
| `prose.pdf` | Hard wraps, discretionary/real hyphens, page continuation, furniture, headings |
| `columns.pdf` | Two columns under a spanning heading; left-before-right order |
| `graphics.pdf` | Nested image/vector form, detached label, ruled table, superscript formula |
| `lists-code.pdf` | Lists, code indentation, source markup escaping, bold/italic |
| `rotated.pdf` | Explicit appearance-preserving whole-page fallback |
| `scanned.pdf` | Real Vision OCR plus original page containing a figure |
| `encrypted.pdf` | A locked document (40-bit RC4, password `reflow`) that converts once unlocked |
| `links.pdf` | External, mailto, refused-scheme, two-line and figure links, and a cross-reference |

Tests use the real Apple PDF/OCR stack, not mocks, and download no external documents; the
fixture manifest records byte counts and SHA-256 identities. `tools/generate_fixtures.py`
regenerates the fixtures and manifest (ReportLab, Pillow, Poppler; development-only, with the
locked one built from the standard library alone), and
`tools/check_epubs.py` runs independent content/ZIP/XML/link checks and official EPUB 3.3
validation with EPUBCheck; both are described in the regression-testing guide.

Reconstruction uses two custom in-memory Swift representations, positioned `PageContent` and the
output-independent `ReflowDocument`; the EPUB writer alone knows XHTML, chapter boundaries,
navigation and ZIP layout. The model is internal, not a public interchange format; see
[architecture](doc/architecture.md).

## Real-document corpus and memory gates

`corpus/manifest.json` registers <!-- counts:registered-documents -->24 real documents<!-- counts:end --> by exact byte identity, from the 522-page
FAA Pilot's Handbook and the 1,834-page Fifth National Climate Assessment to two-page borderless
tables, scanned and born-digital academic papers, Arabic and Simplified Chinese layouts, a comic,
a slide deck and a magazine. Fetch originals with `python3 tools/fetch_corpus.py --all`; verified
copies live in gitignored `corpus/cache/`, tests never download, and some publisher endpoints
require a manually supplied cache copy. The [corpus guide](doc/corpus.md) indexes every case
with its coverage, review points, attribution and commands; the manifest lists known
reading-order and raster defects so a successful conversion is not mistaken for a fidelity
qualification.

`tools/evaluate_real_document.py` checks source identity, runs a fresh converter process, checks
EPUB structure and progress, and enforces a configurable peak-memory ceiling, retaining reports
and memory traces. [Memory testing](doc/memory-testing.md) explains the Mac budgets, the
commands, physical-device limitations and the standalone PDFKit leak investigation tools.

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
