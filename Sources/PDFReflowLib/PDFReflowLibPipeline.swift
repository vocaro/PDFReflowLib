import Foundation
import PDFKit

/// Builds a logical document without choosing a publication format. The caller owns the
/// workspace and must keep its assets alive until the chosen writer finishes.
enum PDFReflowLibPipeline {
    struct Result: Sendable {
        var document: ReflowDocument
        var pageCount: Int
        var reflowedPageCount: Int
        var recognizedPageCount: Int
        var warnings: [ConversionWarning]
    }

    /// Progress covers extraction/reconstruction only, from zero to one.
    ///
    /// Extraction is one pass over every page that keeps only document-wide evidence:
    /// vocabulary, margin-furniture candidates, note-heading pages and chapter matches.
    /// Reconstruction is a second pass that needs one page and its predecessor. Pages are
    /// spilled to the workspace between the passes, so retained page memory is bounded.
    static func reconstruct(from source: URL, options: ConversionOptions, workspace: URL,
                            progress: @Sendable (ConversionProgress) async -> Void) async throws -> Result {
        let document = try PDFPageSource(url: source)
        let total = document.pageCount
        guard total <= options.maximumPages else { throw ConversionError.resourceLimit("page count") }
        try FileManager.default.createDirectory(at: workspace.appendingPathComponent("assets"),
                                                 withIntermediateDirectories: true)

        let structureIndex = try StructureTreeReader.read(source)
        // Tagged-text association happens once per page; the index is released after extraction.
        var structure: StructureTreeReader.Index? = structureIndex
        let chapterCandidates = try ChapterBoundaryReader.read(source)
        var chapterStartPages: Set<Int> = []
        var warnings: [ConversionWarning] = []
        if structureIndex.rejected {
            warnings.append(.init(code: .structureFallback, page: 1,
                message: "Some PDF structure tags are invalid or outside supported paragraph/heading roles; spatial reconstruction remains in use for that content."))
        }

        /// Every extraction step except recognition. `limit` only guards the character budget;
        /// it never truncates a page.
        func extractPage(_ i: Int, limit: Int, warnings: inout [ConversionWarning]) throws
            -> (content: PageContent, attemptsOCR: Bool, implausibleLayer: TextLayerPlausibility.Finding?,
                comparesLayer: Bool, drawnText: Bool) {
            // The pool includes every PDFKit accessor, not only string extraction. Page
            // references and annotation arrays also carry autoreleased rendering resources.
            var (content, placedImages) = try autoreleasepool {
                let page = try document.page(at: i)
                guard let reference = page.pageRef else {
                    throw ConversionError.unreadablePDF
                }
                let bounds = page.bounds(for: .cropBox)
                guard bounds.isFinite, bounds.width > 0, bounds.height > 0,
                      bounds.width <= 100_000, bounds.height <= 100_000 else {
                    throw ConversionError.resourceLimit("page geometry")
                }
                let graphics = GraphicsReader.read(reference)
                let requiresPageImage = graphics.unsupported || page.rotation % 360 != 0
                let syntheticStyle = graphics.hasOnlyInvisibleText && graphics.regions.contains {
                    $0.width * $0.height > bounds.width * bounds.height * 0.75
                }
                // Invisible text over a scan supplies transcription, not source typography.
                // Fallback pages contribute vocabulary and furniture evidence, but their
                // formatting is never emitted. Avoid decoding attributed image attachments.
                var content = PageContent(number: i + 1, bounds: bounds,
                    lines: try NativeTextReader.lines(on: page, limit: limit,
                        includeStyle: !requiresPageImage && !syntheticStyle), graphics: graphics.regions)
                if !requiresPageImage && !syntheticStyle && options.ocr != .always, let structure,
                   let tags = structure.pages[i + 1], !tags.isEmpty,
                   !(StructureTreeReader.validates(tags, owners: structure.owners[i + 1] ?? [:], page: reference)
                     && MarkedTextReader.apply(tags, page: reference, lines: &content.lines)) {
                    warnings.append(.init(code: .structureFallback, page: i + 1,
                        message: "Some tagged text could not be matched unambiguously to native lines; spatial reconstruction is retained for those groups."))
                }
                content.requiresPageImage = requiresPageImage
                content.hasSyntheticTextStyle = syntheticStyle
                if graphics.unsupported {
                    warnings.append(.init(code: .unsupportedGraphics, page: i + 1,
                        message: "Unsupported or excessive drawing operations require the original page image."))
                }
                if !page.annotations.isEmpty {
                    content.preservePageReference = true
                    warnings.append(.init(code: .annotationsNotConverted, page: i + 1,
                        message: options.referenceImages == .never
                            ? "Visible annotations and link/form interactions are not reconstructed; supplementary references are disabled."
                            : "A page image preserves visible annotations. Link and form interactions are not reconstructed."))
                }
                return (content, graphics.images)
            }
            let bounds = content.bounds
            let raw = content.lines.map(\.text).joined()
            let damaged = raw.unicodeScalars.filter { $0.value == 0xFFFD || $0.value == 0xFFFC }.count
            // Share the same conservative page-sized-graphic signal with the review warning.
            // It identifies a candidate for re-recognition, not an erroneous transcription.
            let imageBackedText = !content.lines.isEmpty && content.graphics.contains {
                $0.width * $0.height > bounds.width * bounds.height * 0.75
            }
            // Inherited text over the image that does not read as English, misreads its words in
            // place, or leaves most of the page's text-shaped ink uncovered, is not a plausible
            // transcription of it (#93). Judged under every policy, so the page is reported whether
            // or not its text is replaced.
            let implausibleLayer = imageBackedText && !content.requiresPageImage
                ? try TextLayerPlausibility.judge(lines: content.lines, language: options.language) {
                    try autoreleasepool {
                        try TextLayerPlausibility.measureInk(page: try document.page(at: i), bounds: bounds,
                                                             lines: content.lines, options: options)
                    }
                } : nil
            let automaticOCR = options.ocr == .automatic || options.ocr == .automaticIncludingImageBackedText
                || options.ocr == .automaticKeepingImageBackedText
            let noText = raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            // A page that reflows no word of its own, but draws writing over its ground, has no
            // text layer to judge: its sentence is artwork (#176). Such a page is recognized like
            // a page with no text layer at all, under every automatic policy, so its words reach
            // the reading order instead of being lost with the art that carries them. A page whose
            // art forms no row of text-shaped ink — a chart, a diagram of symbols — keeps its crops
            // untouched, and so does a page whose only rows are inside a photograph, which is a
            // picture of the world rather than writing the page set. Pages with no text at all are
            // already recognized below. `judgeImageOnly` gates on `reflowsNoWords`, which only a
            // page with no letters at all passes, so it never fires on #93's territory (a layer
            // with real judged words); candidacy here does not exclude `imageBackedText`, since a
            // born-digital page with a full-bleed background paint reads as image-backed on this
            // signal exactly like a scan does, with no distinction between them to gate on.
            let drawsTextCandidate = !noText && !content.requiresPageImage && automaticOCR
            let drawnText = try drawsTextCandidate
                && TextLayerPlausibility.judgeImageOnly(lines: content.lines, language: options.language) {
                    try autoreleasepool {
                        try TextLayerPlausibility.measureInk(page: try document.page(at: i), bounds: bounds,
                                                             lines: content.lines, excluding: placedImages,
                                                             options: options)
                    }
                }
            let needsOCR = options.ocr == .always || (automaticOCR &&
                (noText || damaged > max(2, raw.count / 50) || drawnText))
                || (options.ocr == .automaticIncludingImageBackedText && imageBackedText)
                || (options.ocr == .automatic && implausibleLayer != nil)
            let attemptsOCR = needsOCR && !content.requiresPageImage
            // A layer that reads as English but misreads its words in place (#7) is recognized
            // again, and the better reading kept: recognition of a faint carbon typescript misreads
            // as much as the layer does, of a photographed document far less. The layer is
            // extracted as an unverified page would be below, so it can stand if it wins.
            var comparesLayer = false
            if attemptsOCR, options.ocr == .automatic, case .misreadWords? = implausibleLayer {
                comparesLayer = true
            }
            if attemptsOCR, !comparesLayer { return (content, true, implausibleLayer, false, drawnText) }
            if !content.requiresPageImage, imageBackedText {
                // A scan with an existing OCR layer must still reflow. Keep its visual page as a
                // reference rather than treating the full-page scan as one figure covering all text.
                content.preservePageReference = true
                for index in content.lines.indices { content.lines[index].structure = nil }
                content.graphics = []
                warnings.append(.init(code: .unverifiedTextLayer, page: i + 1,
                    message: "Text overlapping a page-sized graphic has not been verified against the source. "
                        + "Transcription, tables, numbers and reading order may be inaccurate. "
                        + (options.referenceImages == .never
                            ? "Check the source PDF before relying on the reflowed text; supplementary references are disabled."
                            : "Check the accompanying source-page image before relying on the reflowed text.")))
            }
            if content.lines.isEmpty && !content.requiresPageImage {
                content.requiresPageImage = true
            }
            return (content, attemptsOCR, implausibleLayer, comparesLayer, drawnText)
        }

        let store = PageStore(directory: workspace.appendingPathComponent("pages"))

        var vocabulary: Set<String> = []
        var furniture = FurnitureDetector.Ledger()
        var numberedNotePages: Set<Int> = []
        var recognizedPages = 0
        var characters = 0
        for i in 0..<total {
            try Task.checkCancellation()
            let extracted = try extractPage(i, limit: options.maximumCharacters - characters, warnings: &warnings)
            var content = extracted.content
            // The implausible-layer warning states what became of the layer, known only after
            // recognition is attempted (or, for a retained layer, never attempted at all).
            func reportImplausibleLayer(_ outcome: TextLayerPlausibility.Outcome) {
                guard let finding = extracted.implausibleLayer else { return }
                warnings.append(.init(code: .implausibleTextLayer, page: i + 1,
                    message: TextLayerPlausibility.message(finding, outcome: outcome,
                                                           referencesDisabled: options.referenceImages == .never)))
            }
            if !extracted.attemptsOCR { reportImplausibleLayer(.retained) }
            if extracted.attemptsOCR {
                await progress(.init(stage: .recognizing, fractionCompleted: 0.6875 * Double(i) / Double(total),
                    page: i + 1, totalPages: total))
                // A page recognized only because its art is writing (#176) already carries that art
                // in its own crops, which the reader can still look at. When recognition reads
                // nothing there is no transcription to put in their place, so the page keeps the
                // crops it was extracted with instead of becoming one page-sized image.
                let keepsCropsIfUnread = extracted.drawnText
                // Recognition read nothing from a page whose art is its only writing: say so, and
                // leave the extracted page (its crops and its folio) exactly as it was.
                func unreadDrawnText() {
                    warnings.append(.init(code: .ocrFailed, page: i + 1,
                        message: "This page reflows no text of its own and its artwork holds writing, but recognition "
                            + "of the page failed or found no text; the artwork is preserved as images and its "
                            + "writing does not reflow."))
                }
                var kept = false
                do {
                    let recognized = try await OCRReader.read(page: try document.page(at: i), options: options)
                    if recognized.lines.isEmpty, keepsCropsIfUnread {
                        unreadDrawnText()
                        kept = true
                    } else {
                        // Recognition that does not read as English is noise, not a transcription
                        // (#7): a reader is better served by the page image than by text made of it.
                        let implausibleRecognition = TextLayerPlausibility.judgeRecognized(lines: recognized.lines,
                                                                                           language: options.language)
                        if let finding = implausibleRecognition, !extracted.comparesLayer {
                            warnings.append(.init(code: .implausibleRecognition, page: i + 1,
                                message: TextLayerPlausibility.recognitionMessage(finding)))
                        }
                        if extracted.comparesLayer, case .misreadWords(let misread, let words, _)? = extracted.implausibleLayer,
                           !TextLayerPlausibility.readsBetter(recognized.lines, than: misread, of: words, language: options.language) {
                            // The damaged layer stands: recognition read no better. `content` is
                            // already the unverified-layer version extracted above.
                            reportImplausibleLayer(.keptOverRecognition)
                        } else if implausibleRecognition != nil {
                            reportImplausibleLayer(.implausibleRecognition)
                            content.lines = []
                            content.requiresPageImage = true
                        } else {
                            reportImplausibleLayer(recognized.lines.isEmpty ? .pageImage : .replaced)
                            // The layer extracted for comparison lost: so does its review warning.
                            if extracted.comparesLayer {
                                warnings.removeAll { $0.code == .unverifiedTextLayer && $0.page == i + 1 }
                            }
                            content.lines = recognized.lines
                            content.recognized = true
                            content.hasSyntheticTextStyle = false
                            content.preservePageReference = content.preservePageReference || !recognized.lines.isEmpty
                            content.graphics = recognized.tables
                            content.requiresPageImage = recognized.lines.isEmpty
                            warnings.append(.init(code: .ocrUsed, page: i + 1,
                                message: "Text is OCR transcription. " + (options.referenceImages == .never && !recognized.lines.isEmpty
                                    ? "Supplementary references are disabled; compare unrecognized visual content with the source PDF."
                                    : "The original page image preserves unrecognized visual content.")))
                        }
                    }
                } catch is CancellationError { throw CancellationError() }
                catch {
                    try Task.checkCancellation()
                    if extracted.comparesLayer {
                        reportImplausibleLayer(.keptOverRecognition)
                        warnings.append(.init(code: .ocrFailed, page: i + 1,
                            message: "OCR failed; the existing text layer is retained."))
                    } else if keepsCropsIfUnread {
                        unreadDrawnText()
                        kept = true
                    } else {
                        content.requiresPageImage = true
                        reportImplausibleLayer(.pageImage)
                        warnings.append(.init(code: .ocrFailed, page: i + 1,
                            message: "OCR failed; the source page is preserved as an image."))
                    }
                }
                if !kept, content.lines.isEmpty, !content.requiresPageImage {
                    content.requiresPageImage = true
                }
            }
            characters += content.lines.reduce(0) { $0 + $1.text.count }
            guard characters <= options.maximumCharacters else { throw ConversionError.resourceLimit("document text") }
            if let chapter = chapterCandidates.first(where: { $0.page == content.number }),
               ChapterBoundaryReader.matches(chapter, page: content) {
                chapterStartPages.insert(content.number)
            }
            // Retain heading evidence before removing furniture, after all extraction/OCR work.
            LayoutReconstructor.addVocabulary(of: content, to: &vocabulary)
            if NumberedNoteDetector.hasHeading(on: content) { numberedNotePages.insert(content.number) }
            if options.removeRepeatedHeadersAndFooters { FurnitureDetector.collect(content, pageIndex: i, into: &furniture) }
            if content.recognized { recognizedPages += 1 }
            try store.store(content, at: i)
            await progress(.init(stage: .extracting, fractionCompleted: 0.6875 * Double(i + 1) / Double(total),
                page: i + 1, totalPages: total))
        }
        document.releaseCachedPages()
        structure = nil
        let furniturePlan = options.removeRepeatedHeadersAndFooters ? FurnitureDetector.resolve(furniture) : nil
        furniture = FurnitureDetector.Ledger()
        // Furniture warnings keep their place between extraction and reconstruction warnings.
        let furnitureWarningIndex = warnings.count
        var furnitureWarnings: [ConversionWarning] = []
        var blocks: [ReflowBlock] = [], assets: [ReflowDocument.Asset] = []
        var reflowed = 0
        var imageBytes: Int64 = 0
        var previous: PageContent?
        for i in 0..<total {
            try Task.checkCancellation()
            var content = try store.load(at: i)
            if let furniturePlan, let warning = FurnitureDetector.apply(furniturePlan, to: &content, pageIndex: i) {
                furnitureWarnings.append(warning)
            }
            let previousPage = i > 0 && !chapterStartPages.contains(content.number) ? previous : nil
            try autoreleasepool {
                let page = try document.page(at: i)
                func saveImage(_ rect: CGRect, fullPage: Bool = false, rotate: Bool = false) throws -> String {
                    try Task.checkCancellation()
                    let assetID = "image-\(assets.count + 1)"
                    let encoded = try autoreleasepool {
                        let image = try PageRasterizer.image(page: page, rect: rect, options: options, applyRotation: rotate)
                        return try PageRasterizer.encode(image, at: workspace.appendingPathComponent("assets/" + assetID),
                            encoding: fullPage ? options.fullPageImageEncoding : options.regionImageEncoding)
                    }
                    imageBytes += Int64(try encoded.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
                    guard imageBytes <= options.maximumOutputBytes else { throw ConversionError.resourceLimit("image output bytes") }
                    assets.append(.init(id: assetID, fileURL: encoded.url, format: encoded.format))
                    return assetID
                }
                var pageBlocks: [ReflowBlock]
                if content.requiresPageImage {
                    let path = try saveImage(content.bounds, fullPage: true, rotate: true)
                    pageBlocks = [LayoutReconstructor.imageBlock(assetID: path, page: i + 1)]
                    warnings.append(.init(code: .pageImageFallback, page: i + 1,
                        message: "This page is preserved as an image and does not reflow."))
                } else {
                    var images: [(CGRect, String)] = []
                    for rect in LayoutReconstructor.graphicsWithLabels(content) {
                        images.append((rect, try saveImage(rect)))
                    }
                    if !images.isEmpty {
                        warnings.append(.init(code: .imageRegion, page: i + 1,
                            message: "Graphical regions retain source appearance as images; their internal text does not reflow."))
                    }
                    pageBlocks = LayoutReconstructor.blocks(page: content, images: images,
                        vocabulary: vocabulary, warnings: &warnings,
                        numberedNotePage: numberedNotePages.contains(content.number), language: options.language)
                    if pageBlocks.contains(where: \.hasReflowedText) {
                        reflowed += 1
                    }
                    let includeReference = options.referenceImages == .always
                        || (options.referenceImages == .automatic && content.preservePageReference)
                    if includeReference {
                        pageBlocks.append(LayoutReconstructor.imageBlock(assetID: try saveImage(content.bounds, fullPage: true),
                            page: i + 1, reference: true))
                        warnings.append(.init(code: .imageRegion, page: i + 1,
                            message: "A source-page reference image accompanies reflowed text to preserve all visual content."))
                    } else if content.preservePageReference {
                        warnings.append(.init(code: .referenceImageOmitted, page: i + 1,
                            message: "Client policy omits a supplementary source-page image recommended for this page. "
                                + "Compare the source PDF for visual content and transcription accuracy."))
                    }
                }
                LayoutReconstructor.appendPage(pageBlocks, page: content, previousPage: previousPage,
                    to: &blocks, vocabulary: vocabulary, warnings: &warnings)
            }
            previous = content
            await progress(.init(stage: .reconstructing, fractionCompleted: 0.6875 + 0.3125 * Double(i + 1) / Double(total),
                page: i + 1, totalPages: total))
        }
        document.releaseCachedPages()
        store.finish()
        warnings.insert(contentsOf: furnitureWarnings.sorted { $0.page < $1.page }, at: furnitureWarningIndex)
        let title = options.title ?? document.title
            ?? source.deletingPathExtension().lastPathComponent
        let reflowedDocument = ReflowDocument(metadata: .init(title: title.isEmpty ? "Untitled" : title,
            language: options.language, author: options.author), blocks: blocks, assets: assets,
            chapterStartPages: chapterStartPages)
        return Result(document: reflowedDocument, pageCount: total, reflowedPageCount: reflowed,
            recognizedPageCount: recognizedPages, warnings: warnings)
    }
}
