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
JPEG quality, and output size. The defaults are automatic references and automatic image
encoding, `.automatic(jpegQuality: 0.90)`: each image is classified, and photographs, painted
art, tonal scans, full-page mixed references and uncoloured images keep the smaller of PNG and
JPEG 0.90 while coloured line art, charts, drawn illustration crops and coloured text pages stay
PNG. Naming `.png`, `.jpeg(quality:)` or `.smallest(jpegQuality:)` applies exactly that.

```swift
options.referenceImages = .never          // Supplementary references only
options.fullPageImageEncoding = .jpeg(quality: 0.90)
options.regionImageEncoding = .png        // Independently selectable
options.maximumOutputBytes = .max         // Disable the entry-byte budget
options.maximumEPUBBytes = 512 * 1_024 * 1_024 // Cap the final ZIP file
```

`.smallest(jpegQuality: 0.90)` encodes PNG and JPEG and keeps the smaller file; on its own it
does not assess visual fidelity, which is what the automatic default adds. `.always` adds
references on every reconstructed page; `.never` retains required image-only fallbacks and figure crops, with warnings when recommended references are
omitted. [Conversion options](doc/conversion-options.md#recommended-starting-settings) gives measured starting
settings, provisional recommended ranges, and each control's tradeoffs.

Other options select automatic/disabled/always OCR, opt-in retries of all image-backed existing
text (`.automaticIncludingImageBackedText`) or keeping even implausible image-backed text
(`.automaticKeepingImageBackedText`), language, title, author, recurring header/footer
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
  adjustment with matching character-map, text and placement evidence, and a source-measured
  gap of at least 0.15 em at a font change between letters (a mathematical variable set in its
  own font) restores the word space PDFKit drops there; ambiguous spacing remains.
- Validated PDF paragraph and H1–H6 tags supply grouping and heading levels. Complete tagged
  text groups can follow logical order inside spatial barriers. Unsupported or ambiguous tags
  report `structureFallback`; figures, lists, captions and OCR retain spatial reconstruction.
  Tagged list items (`L`, `LI`, `Lbl`, `LBody`) are read as evidence of item boundaries, depth and
  list identity.
  This is bounded tag support, not full tagged-PDF or accessibility reconstruction.
- Soft hyphens are removed at wraps. A hard hyphen is removed only when the unbroken word occurs
  elsewhere in the book and there is no evidence of the corresponding compound. The remainder of
  a broken word at the start of a line is not counted as a book word. Inside a web
  address, the book's own unbroken addresses decide instead of prose compounds. Ambiguous
  joins retain the hyphen and produce a warning. A book that prints hundreds of line-end word
  breaks as `=` (the 9/11 report's chapters 5–9) has them treated as its hyphen. A hyphen inside
  an alphanumeric code (`265A-NY-` + `280350-HQ`) joins without a space.
- Short recurring headers and footers can be removed when at least three pages support the
  decision, including a two-row running head (title row with folio, section row) in the outer
  fifth of the page. Page-bottom footnotes under a dash separator, set smaller than the body and
  opening with raised numeric markers, become separate note blocks (`div.footnote` with
  `role="doc-footnote"`) after the page's body; a note continued on the next page is joined to
  its start with the page boundary inside it, and the separator is not emitted. Notes are not
  linked to their references. Monospaced code retains line breaks and indentation; list markers (including a
  numeric marker set tight against a minus sign, as in answer keys) retain their
  source breaks, except that a wrapped line of justified prose that merely begins with an
  initial, a citation abbreviation or a year followed by a period continues its paragraph.
  Visible typography supplies flat heading navigation: heading sizes rank into levels across
  the whole document so equal sizes share a level and a title outranks the author names beneath
  it, modestly larger section labels (`ABSTRACT`,
  `1.1 INSIDE THE FOUR FLIGHTS`) become headings separate from their paragraphs, a title set
  over several lines is one heading and a chapter opener's display numeral is part of it rather
  than a subscript, a multi-line display sentence (a pull quote) reflows as prose, a contents
  page's dot-leader entries are never headings, a rotated
  margin stamp is omitted, and an `Algorithm N` listing set between rules is preserved whole
  beneath its reflowed caption. Exclusively invisible
  text over scan images does not supply reliable code or heading typography.
- Core Graphics scans placed images, nested forms and painted paths. The original page renderer
  supplies crops containing figures, ruled tables, labels and recognizable displayed formulas,
  including bounded detached fractions.
  Numeric dot-leader tables with supported geometry, borderless tables with underlined column
  headers, and OCR table regions also become images. A rule that merely underlines a label or
  sits beside a paragraph does not rasterize that prose. Images preserve compositing and appearance rather than
  exposing raw image resources with missing masks or detached labels.
- Vision recognizes pages with missing/damaged text by default. OCR text is explicitly reported
  as transcription, with an accompanying original-page image by default. The recognition request
  pins revision 1 and writes out its text options at their macOS/iOS 27 defaults (language
  correction off). The book `language` selects the recognition language Vision lists for it
  (`en` → `en-US`, `fr` → `fr-FR`, `zh-TW` → `zh-Hant`); a language Vision does not list keeps
  its default, US English with automatic detection, and the first `ocrUsed` warning says so
  ([#106](measurements/ocr-language/record.md)). Transcription can still differ between processes: separate compiles of
  Vision's models can read the same page differently, and processes with the same executable
  name reuse one cached compile ([#94](measurements/ocr-location/record.md)).
  Vision can also report success while leaving whole paragraphs or table cells out, so each
  recognized page is checked for rows of text-shaped ink outside every recognized line. A page
  that fails is recognized once more in two overlapping bands, kept when it covers more (its table
  regions only where the first recognition also found a table,
  [#129](measurements/ocr-retry-side-effects/record.md)); the
  `ocrUsed` message then adds "The first recognition left text-shaped ink outside every
  recognized line, so the page was recognized again in two overlapping bands." If text-shaped
  ink is still uncovered it adds "About N% of the page's text-shaped ink is still outside every
  recognized line, so some text may be missing; compare the original page image." (or "compare
  the source PDF." without references) ([#116](measurements/ocr-text-loss/record.md)).
  Existing text over a page-sized graphic retains a source reference image by default and reports
  `unverifiedTextLayer`: transcription, tables, numbers and reading order need human review.
  This conservative signal is not an OCR confidence score; it can also flag illustrated pages
  with valid text. A page-sized graphic counts when one paint that is not the page's own
  background (a scan, a photograph, a full-page border) covers
  most of the page, when any text is invisible, or when the page's own crops would still cover
  the page or hold more than a tenth of its words; a born-digital layout whose bands, icons,
  callout boxes and rules merely cluster that large reflows beside its crops without the signal
  ([#117](measurements/dga-preservation/record.md)). A page whose only page-sized paint is a flat
  fill paints its own backdrop: that fill, the boxes it paints behind its own text and the marks
  inside them seed no crop, and the page is a picture of itself only when the crops that remain
  hold most of its words. Where such a page's own figures would still take a word of it (a slide's
  icons drawn over their labels), it keeps a source-page image instead of crops and reflows its
  whole text, without the warning ([#164](measurements/page-backdrops/record.md)). Validated structure tags still apply to visible native text over such a
  background (a chapter opener's photograph); pages with invisible text keep spatial reconstruction. When an inherited OCR layer marks what it could not transcribe with inline images (Adobe Paper Capture), those marks are evidence only: each grows over the scan's ink to a whole figure ending above its `FIGURE N.` caption, or to a whole display-equation row with its number, and a figure that cannot grow without reaching prose keeps the page image. Smaller graphics and undetected scans can still contain transcription errors.
- Born-digital text whose fonts carry a custom `Differences` encoding of index-style glyph
  names (`G108`, `c63`) with no `ToUnicode` map extracts as the wrong characters even though
  the page renders correctly. When such a font is present and the page's extracted words also
  fail English function-word and letter-pair statistics, the page reports `damagedTextEncoding`.
  First, a font whose glyphs are named by index (`G87`) is decoded where the document's own words
  establish one constant offset as English (the Census report's EC text fonts), and lines drawn only
  in decoded fonts are rewritten and reflow natively; math fonts without such an offset, and pages
  of numeric table rows no table path reconstructs, keep the warning.
  Automatic OCR policies recognize the page image instead; `.never` keeps the unreadable text
  with a source-page reference. The English statistics are embedded (no dictionary download or
  model); pages declared in another language, pages with fewer than 20 words, composite (CID)
  fonts and wrong-but-present `ToUnicode` maps are not judged. Either signal alone never flags a page.
- Existing text over a page-sized graphic is also tested for plausibility (#93): fewer than half
  of at least 20 judged words in the system English lexicon (irregular capitals such as `sreANee`
  and stray letters from letter-spaced text count against it; layers where a fifth of the tokens
  hold digits are not judged), or lines that leave at least 75% of the page's text-shaped ink
  uncovered in seven or more rows while holding fewer English words than those rows. A failing page
  reports `implausibleTextLayer` with what failed and what was done. By default the layer is
  replaced by OCR of the page image (the CDC comic's garbled, half-missing dialogue);
  `.automaticKeepingImageBackedText` and `.never` keep it. On the English corpus it fails 27 CDC
  pages and seven Warren pages and no other page
  ([measurements](measurements/text-layer-plausibility/record.md)).
- A page whose text layer holds no letter at all — nothing, or only a folio — reflows nothing, so
  if its own drawing (not its photographs) carries at least two rows of text-shaped ink outside
  that layer, it is recognized like a page with no text layer, and its words reach the reading
  order. Ink is read against the page's own background, so a slide printed white on dark blue is
  not mistaken for a blank one. Decorative art, charts and answer keys of bare surds are left with
  their crops ([measurements](measurements/image-only-pages/record.md)).
- Rotated pages, unsupported drawing operations and pages without recoverable text use an
  explicitly warned whole-page image fallback. An annotation that changes what a reader sees (a
  bordered link, a stamp, a checked box, a filled or signed field) gets a source reference image
  by default; one that draws nothing beyond the printed page (a borderless link, an unfilled
  field, a form button) does not. Either way the page warns that its link and form interactions
  are not reconstructed.
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
Cropped text is neither reflowable nor accessible as text. A preserved image's alternative text is
the caption the source prints beside it, or else the kind of content its evidence shows (an
illustration, a mathematical expression, a table or text kept as an image); it never invents a
description of the picture, and its source page is in its `title`. Review warnings and compare
the source before distributing a derived book. [Architecture](doc/architecture.md) describes
the internal seams and extension points.

## Development and regression tests

For changes to extraction, layout or rendering, run `scripts/check-all.sh --corpus` before
pushing. This opt-in lane converts <!-- counts:documents -->20<!-- counts:end --> complete cached documents and checks reviewed content,
EPUB conformance, progress and resource budgets, then converts four of them twice with one binary
and requires identical output. Missing sources fail with acquisition instructions; there are no
automatic downloads. `scripts/check-all.sh --fast` remains the offline synthetic lane (it also
converts each fixture twice and requires byte-identical EPUBs).
Python tool tests and the source-region, glyph-structure and image-appearance checks require numpy
and Pillow. Poppler is needed only to render new region references. The reviewed contracts hold
<!-- counts:contract-summary -->3655 checks on 585 pages of 20 documents<!-- counts:end -->, including full-resolution stroke checks for equations and a
table, scale/contrast/color checks for a flag and an FAA figure, and <!-- counts:table-cell-checks -->14<!-- counts:end --> cell checks on tables
emitted as text. See [regression testing](doc/regression-testing.md) for coverage, limitations and
adding a case.

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
`ReflowDocument`: metadata, ordered paragraphs/headings/preformatted blocks/list items, styled text runs,
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
Blue Book scanned-table report, and five smaller sources for borderless tables, page-bottom
footnotes, damaged text encodings, and scanned and born-digital two-column academic papers,
by exact byte identity. The corpus is English-only for now: the library's right-to-left and CJK
handling stays, but no corpus document exercises it until non-English support is taken up again.
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
