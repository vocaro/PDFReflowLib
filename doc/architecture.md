# Architecture

PDFReflowLib converts a local PDF into a reflowable EPUB 3 on iOS, iPadOS and macOS with PDFKit,
Core Graphics, Vision and ImageIO on the device: no network, no language model, no shipped
weights, no application, UI, index, library-store or inference dependency, and ZIPFoundation as
the only package dependency. The `pdf-reflow` executable is a small client of the public API.

`PDFConverter`, a public actor, is the whole public surface: it validates options, owns the
temporary workspace, composes progress, checks the final archive size, cleans up on failure or
cancellation and publishes the EPUB atomically. Beneath it, a reconstruction pipeline produces an
output-independent document and a writer serializes it. The numeric rules every stage applies are
in [behavior.md](behavior.md); why the seams are where they are is under [decisions/](decisions/README.md).

## Two intermediate representations

Both are custom in-memory Swift values, `Sendable` and `Equatable`: not HTML, an XML DOM, a PDFKit
object graph or a serialized interchange file, and under no public persistence or compatibility promise.

`PageContent` (`DocumentModel.swift`) is the spatial extraction representation: one physical
page's bounds, positioned `TextLine` values with font sizes, monospaced and wrap hints, optional
validated structure associations, graphic rectangles and fallback flags. A text line holds
`InlineText`: raw Unicode runs with bold, italic, superscript and subscript flags. Geometry stays
in unrotated PDF page coordinates with a bottom-left origin, keeping the evidence that reading
order, paragraphs, image crops and word joins are inferred from.

`ReflowDocument` (`ReflowDocument.swift`) is the logical representation: metadata (title,
language, optional author); ordered `ReflowBlock` values (paragraph, heading with a logical
identifier and level, preformatted text, list item, table, image, source-page boundary); inline
runs with style flags, interspersed with source-page boundaries; image blocks with an asset
identifier, alternative text and caption; an asset registry (identifier, local file URL, format);
and each block's source page. Source-page boundaries can fall inside a paragraph or a repaired
word and add no visible text, so provenance stays separate from typography. There is no XHTML,
CSS, EPUB namespace, ZIP path or chapter-file boundary; raw `<` and `&` stay raw until a writer
escapes them. Headings form flat navigation. A list item is flat too — its text without the
printed marker, the marker, the printed number of a numbered item, its kind and whether it opens
a list element — because the writer streams blocks and packs spine documents freely, so the
list's tree is the writer's to open and close; nesting is not in the model. Code, table rows set
without rules and list-shaped lines the list pass did not verify are preformatted blocks over the
same runs as paragraphs; tables and equations preserved as images are image references, not
semantic trees.

## The pipeline

`PDFReflowLibPipeline.reconstruct` emits the logical document as a stream of parts — the
document-wide facts, then assets and blocks in the order it makes them — and returns page counts
and warnings. A consumer that takes the stream never holds the document; a caller that passes
none gets it collected from the same stream instead, so the two forms cannot diverge. The caller
supplies a workspace and keeps it alive until serialization finishes. The pipeline runs without
the writer and takes its recognizer as a parameter (Vision by default), so tests drive every
recognition branch with canned readings.

Extraction is one pass over the pages, each through named stages with value types between them:

| Stage | Module | Produces |
| --- | --- | --- |
| Read | `PageReader` over `PDFPageSource`, `NativeTextReader`, `GraphicsReader`, `StructureTreeReader` | `ExtractedPage`: the `PageContent`, placed raster images, unmapped-font flag, the glyphs the decoder read that the lines did not take, reader warnings |
| Diagnose | `PageDiagnosis` with `PageInkMeasurer`, `TextEncodingCheck`, `TextLayerPlausibility`, `OCRTextCoverage`, `EnglishText` | `PageEvidence`: image-backed, damaged encoding, plausibility finding, drawn text, replacement-character counts, a sparse layer's word counts |
| Plan | `RecognitionPolicy.plan` (pure) | `RecognitionPlan`: keep the extracted page, or recognize it replacing, comparing or verifying |
| Recognize | `OCRReader` (Vision) when the plan asks, checking its own reading against the page with `OCRTextCoverage` | `RecognitionOutcome` |
| Resolve | `RecognitionPolicy.resolve` (pure) with `RecognitionJudge` | `PageDisposition` plus the page's `PageWarning`s in report order |
| Fold | `DocumentEvidence`, `PageAssetWriter`, `PageStore` | Document-wide evidence, written assets, the spilled page |

Recognition is the one stage that judges its own product. Vision can return success while leaving
part of the page unread, so `OCRReader` measures the writing on the raster it handed over against
the lines it got back, recognizes the page again in overlapping bands when the reading does not
account for the page, and keeps whichever reading covers more. What the reading finally left out
travels with it as evidence; deciding whether that is worth reporting stays with
`RecognitionPolicy`, and saying it stays with `ConversionWarnings`.

`NativeTextReader` obtains PDFKit line selections, geometry and attributed runs and copies them
into values at once. The content-stream readers (`NativeSpacingReader`, `GlyphIdentityReader`,
`ExtensionDelimiterReader`, `GlyphIndexDecoder`, `MarkedTextReader`, `GlyphPlacementReader`) are visitors on one driver, `ContentStreamWalk`, which owns the scanner
lifecycle, graphics-state stack, matrices, text-object state, show operators, operation budget
and cancellation check; a reader keeps only the state its evidence needs and differs from the
others only in `ContentStreamWalk.Options`. `NativeSpacingReader` keeps the text matrix itself,
apart from the walk's line matrix, because only a reader that measures glyph advances knows where
a show that draws straight after another begins; `NativeSpacingOwnership` holds how much of a
PDFKit line the shows must account for before their boundaries apply, so the rule layer and the
ownership rule can be read, reviewed and reverted apart. `CGPDFObjects` holds the typed dictionary accessors,
inherited-resources walk and font enumeration they share; `AnchorMatcher` matches a show origin
to the one native line it lies in. `GlyphIndexDecoder` is the one reader whose evidence is the
whole document rather than one page: a font that names its glyphs by index states no character
anywhere in the file, so the characters are established from the document's own words and read
back once per document, and `GlyphIdentityReader` rewrites an affected line from them. Where one
show draws a whole printed row that PDFKit splits into a line per column, the glyphs the leftmost
line cannot take are carried along `NativeTextReader`'s own line loop to the next line of that row
(#237): the loop is the only place that sees every line's text in reading order, since the readers
are handed one line at a time. A page whose fonts it cannot establish keeps the damaged-encoding
diagnosis and its recognition.
`GraphicsReader` keeps its own paint-oriented scan over the same helpers, tracking the clip in
force so that what it records for a figure is what the page lets show rather than how far the
artwork was drawn, and spending its own budget so a page cannot ask for unbounded work.
`StructureTreeReader` parses tagged-PDF structure into value-only page/MCID
associations, and no Core Graphics object survives its parsing pool. `ConversionWarnings`
composes every warning's prose from a `PageWarning` kind in one place.

Reconstruction is a second pass. `PageStore` reloads one page at a time, and a page needs only
itself and its stripped predecessor for cross-page continuation. `FurnitureDetector` is phased to
match (`collect`, `resolve`, `apply`; `strip` runs the phases over an array so the two paths
cannot diverge). `LayoutReconstructor.blocks` reads a page's typography once into
`PageTypography`, classifies each line with `role(of:)` into a `LineRole`, and hands the ordered
elements to a `BlockAssembler`. A role can carry the page-level evidence a decision needs that the
assembler, reading one line at a time in reading order, cannot see for itself: a line opening with
a number or a letter and a point is either a list item or a wrapped line whose first word is an
initial, a citation or a year, and telling them apart takes both the column the whole page
establishes and what the line before this one did. The page measures the column when it
classifies; the assembler supplies the rest. Everything the pages share arrives as one `DocumentContext`
(the `HyphenContext`, language, document body size, recurring label styles, the `HeadingRank`
the book's own tags establish, numbered-note pages), so a new document-wide signal is a field,
not a parameter. `HeadingRank` is the one such signal with a file of its own: its tally is
folded in page by page during extraction, resolved once with the rest of `DocumentEvidence`,
and consulted by the reconstructor where a page's tags contradict it. `HyphenRepair` edits text runs only;
the geometric predicates the rules share (`hasSize`, `overlapsHorizontally`, `sharesColumn`,
`sharesRow`) live on `TextLine` in `TextLineGeometry`. `TableRegionDetector`,
`FractionRegionDetector` and `NumberedNoteDetector` are bounded detectors that hand regions or
groups to the assembler; `PageFootnotes` is the one that also owns references, tying the notes a
page sets at its foot to the raised numbers above them and linking those after assembly; `ChapterBoundaryReader` supplies validated chapter-start pages.
`ListBuilder` is the one pass that reads blocks rather than lines: it sits between reconstruction
and the writer, on the stream of finished blocks, and turns a verified run of marker-opened
blocks into list items. A run crosses pages and is verified whole, so the pass holds a block only
while a run it may belong to can still change — at most three pages past the run's end — and
what a decision reads from further back travels as a count or a marker, never as blocks
([decision 0008](decisions/0008-streamed-blocks-to-the-writer.md)).
What seeds a crop is separate from how far the crop grows. A thin painted rule that underlines
prose is that text's decoration and seeds nothing, a bar over or under one glyph is that glyph's
accent and is read into its line (`PaintedAccents`), while a rule carrying a fraction, a rule
inside a short word-free mathematical line, a rule clear of every line and a row of header
underlines over numeric rows each remain evidence of something to preserve. A crop then admits
only the lines its seed captures and the other pieces of those lines' rows, and is trimmed away
from the lines it merely touches, because line rectangles include leading and overlap: chaining
from line to line through that overlap let one underline or one mistaken relation rasterize a
whole column of prose.

## Reconstruction boundary

Every PDFKit and Core Graphics call for a page happens inside `PageReader.read`, in one
autorelease pool, and the synchronous native-text step runs under a process-wide extraction gate
(`NativeTextReader.withExtractionLock`) shared by every converter instance, because PDFKit can
throw an `NSFont` exception under concurrent attributed extraction. The gate drains what the
step autoreleased before it unlocks, is released before progress callbacks, OCR, graphics work
and writing, and checks cancellation while a waiter is queued. Host PDFKit, CoreText or font
work outside the library does not participate, so this is a bounded mitigation, not a
framework-wide guarantee. Tests make their fonts, CoreText drawings and PDFKit reads through the
same gate (`pdfKitGated`), and `tools/check_pdfkit_gate.py` fails the build on a call left
outside it ([decision 0002](decisions/0002-pdfkit-extraction-gate.md)).

`PDFPageSource` keeps only a small window of PDFKit pages alive and reopens the document between
extraction and reconstruction; the converter carries value types forward, never PDFKit pages or
selections. The structure index is released after extraction.

## Serialization and resource lifetime

Assets live under a neutral workspace directory, outside the EPUB layout; the model holds URLs
and identifiers, never decoded images or large byte buffers. `PageAssetWriter` owns the asset
registry and the image-byte budget; `PageRasterizer` renders source-composited regions to
bounded rasters and encodes them under client policy.

Client policy independently selects PNG, a JPEG quality or the smaller encoding for full-page
images and for cropped regions, or leaves the default, `.automatic(jpegQuality: 0.90)`, which is
decided per image. `PageAssetWriter.save` resolves it, because it is the one place that
knows the two things `PageRasterizer` does not: the image's role (a supplementary page reference,
or a crop — a required fallback is its page's only copy and is judged as a crop) and whether the
page draws its type from an image, which the pipeline records during extraction from
`PageEvidence`. `ImageContentClassifier` reads the raster through `PageRasterizer.image`'s
`inspect` hook, from the bitmap context's own buffer before the `CGImage` is made, because
reading a finished image's pixels copies them. It permits lossy for neutral images, photographs,
tonal scans, continuous-tone art (except crops that are drawn illustration) and full-page `mixed`
references, and hands `PageRasterizer.encode` `.smallest` there and `.png` elsewhere, so `encode`
keeps its contract and a named encoding never reaches the classifier. Rasters are written without
their constant alpha plane, relabeled opaque over their own pixel buffer at write time, so a PNG
records three channels; the raster recognition sees keeps the format Vision is measured against.
See [conversion options](conversion-options.md#automatic-encoding).

`EPUBTextEncoder` owns XML escaping, block and inline tags, list and page markers and figure
markup; it is the only place that knows XHTML. `SpinePacker` owns spine splitting and navigation
entries as structured values, tested without files or ZIP. `EPUBWriter` owns OPF metadata, CSS,
resource naming and ZIPFoundation packaging, assigns archive paths from counters (asset
identifiers are opaque and cannot choose paths), streams asset files straight into ZIP entries,
and writes each spine document as the packer closes it, keeping one current body string plus
navigation lists. It gathers the items of a list, and any page boundary that arrives among them,
until the list closes, and packs the list as one piece, because a list element may hold only items
and a spine document may not end inside one.
It consumes the document part by part as reconstruction produces it, and finishes navigation,
package metadata and the archive when the stream ends, so neither side holds the block list.
`ProgressBudget` holds every stage's share of the progress fraction; serializing a block counts
as the work of the pass that made it, and only publication emits completion. Validation rejects
missing or duplicate assets and empty documents, block by block as they arrive. Another writer
could consume the model without touching extraction or reconstruction; a public non-EPUB API or
a persistent model would need an explicit resource-lifetime contract. There is no writer registry.

## Invariants

- **Format knowledge lives in the writer.** Nothing before `EPUBWriter` knows XHTML, CSS, EPUB
  namespaces, ZIP paths or chapter files. New output syntax belongs in writers; richer PDF
  understanding belongs in reconstruction.
- **The caller owns the workspace.** The pipeline writes assets and spilled pages into a
  directory it is given and never publishes; `PDFConverter` stages beside the destination,
  publishes atomically, never overwrites an existing output, and removes staging on every failure
  and cancellation path.
- **Byte identity is the refactoring gate.** A change that claims to preserve behavior must
  produce byte-identical EPUB entries and CLI reports, with packaging pinned, on every corpus,
  policy-variant and fixture conversion that completes under default budgets
  (`tools/epub_identity.py`; [decision 0004](decisions/0004-byte-identity-gate.md)).
- **Measurements are records, not captures.** `measurements/` holds each experiment's record and
  the small summaries it quotes; raw captures stay out, gate tooling lives under `tools/`, and
  records cite the paths and commits they measured in prose ([decisions 0006](decisions/0006-measurements-are-records.md)
  and [0007](decisions/0007-records-cite-commits-in-prose.md)).
- **PDFKit is entered through one gate**, by library and test code alike, and **cancellation is
  cooperative**, checked at page, line and archive-chunk boundaries.

## Repository layout and further reading

Source and tests follow SwiftPM conventions (`Sources/PDFReflowLib/`, `Sources/PDFReflowLibCLI/`,
`Tests/PDFReflowLibTests/` with a lowercase `fixtures/` directory). Supporting directories are
lowercase: `corpus/` (manifest, review points, content contracts, region references; sources in
ignored `corpus/cache/`), `tools/` (gates, probes, the shared `pdfreflow_tools` package),
`scripts/`, `measurements/` and `doc/`. Corpus acquisition is separate from the runtime: a
standard-library Python fetcher verifies pinned identities into the cache, and conversion and
tests stay offline unless a developer runs it.

[Behavior specification](behavior.md): every rule, threshold and warning code, by module.
[Decisions](decisions/README.md): why the seams and conventions are what they are.
[Regression testing](regression-testing.md): running the gates, adding a case, capturing fixtures.
Also [conversion options](conversion-options.md), [corpus](corpus.md), [memory testing](memory-testing.md),
[comparison harness](comparison.md), [test reader](test-reader.md) and [research notes](research-notes.md).
