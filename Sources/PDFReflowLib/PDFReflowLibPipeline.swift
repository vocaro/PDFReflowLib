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
    static func reconstruct(from source: URL, options: ConversionOptions, workspace: URL,
                            progress: @Sendable (ConversionProgress) async -> Void) async throws -> Result {
        let document = try PDFPageSource(url: source)
        let total = document.pageCount
        guard total <= options.maximumPages else { throw ConversionError.resourceLimit("page count") }
        try FileManager.default.createDirectory(at: workspace.appendingPathComponent("assets"),
                                                 withIntermediateDirectories: true)

        var pages: [PageContent] = []
        var warnings: [ConversionWarning] = []
        var characters = 0
        for i in 0..<total {
            try Task.checkCancellation()
            // The pool includes every PDFKit accessor, not only string extraction. Page
            // references and annotation arrays also carry autoreleased rendering resources.
            var content = try autoreleasepool {
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
                    lines: try NativeTextReader.lines(on: page, limit: options.maximumCharacters - characters,
                        includeStyle: !requiresPageImage && !syntheticStyle), graphics: graphics.regions)
                content.requiresPageImage = requiresPageImage
                content.hasSyntheticTextStyle = syntheticStyle
                if graphics.unsupported {
                    warnings.append(.init(code: .unsupportedGraphics, page: i + 1,
                        message: "Unsupported or excessive drawing operations require the original page image."))
                }
                if !page.annotations.isEmpty {
                    content.preservePageReference = true
                    warnings.append(.init(code: .annotationsNotConverted, page: i + 1,
                        message: "A page image preserves visible annotations. Link and form interactions are not reconstructed."))
                }
                return content
            }
            let bounds = content.bounds
            let raw = content.lines.map(\.text).joined()
            let damaged = raw.unicodeScalars.filter { $0.value == 0xFFFD || $0.value == 0xFFFC }.count
            let needsOCR = options.ocr == .always || (options.ocr == .automatic &&
                (raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || damaged > max(2, raw.count / 50)))
            if needsOCR && !content.requiresPageImage {
                await progress(.init(stage: .recognizing, fractionCompleted: 0.6875 * Double(i) / Double(total),
                    page: i + 1, totalPages: total))
                do {
                    let recognized = try await OCRReader.read(page: try document.page(at: i), options: options)
                    content.lines = recognized.lines
                    content.recognized = true
                    content.hasSyntheticTextStyle = false
                    content.preservePageReference = content.preservePageReference || !recognized.lines.isEmpty
                    content.graphics = recognized.tables
                    content.requiresPageImage = recognized.lines.isEmpty
                    warnings.append(.init(code: .ocrUsed, page: i + 1,
                        message: "Text is OCR transcription. The original page image preserves unrecognized visual content."))
                } catch is CancellationError { throw CancellationError() }
                catch {
                    try Task.checkCancellation()
                    content.requiresPageImage = true
                    warnings.append(.init(code: .ocrFailed, page: i + 1,
                        message: "OCR failed; the source page is preserved as an image."))
                }
            } else if !content.requiresPageImage, !content.lines.isEmpty,
                      content.graphics.contains(where: { $0.width * $0.height > bounds.width * bounds.height * 0.75 }) {
                // A scan with an existing OCR layer must still reflow. Keep its visual page as a
                // reference rather than treating the full-page scan as one figure covering all text.
                content.preservePageReference = true
                content.graphics = []
                warnings.append(.init(code: .unverifiedTextLayer, page: i + 1,
                    message: "Text overlapping a page-sized graphic has not been verified against the source. "
                        + "Transcription, tables, numbers and reading order may be inaccurate. "
                        + "Check the accompanying source-page image before relying on the reflowed text."))
            }
            if content.lines.isEmpty && !content.requiresPageImage {
                content.requiresPageImage = true
            }
            characters += content.lines.reduce(0) { $0 + $1.text.count }
            guard characters <= options.maximumCharacters else { throw ConversionError.resourceLimit("document text") }
            pages.append(content)
            await progress(.init(stage: .extracting, fractionCompleted: 0.6875 * Double(i + 1) / Double(total),
                page: i + 1, totalPages: total))
        }
        document.releaseCachedPages()
        let vocabulary = LayoutReconstructor.vocabulary(in: pages)
        if options.removeRepeatedHeadersAndFooters { warnings += LayoutReconstructor.stripFurniture(&pages) }
        var blocks: [ReflowBlock] = [], assets: [ReflowDocument.Asset] = []
        var reflowed = 0
        var imageBytes: Int64 = 0
        for (i, content) in pages.enumerated() {
            try Task.checkCancellation()
            try autoreleasepool {
                let page = try document.page(at: i)
                func saveImage(_ rect: CGRect, rotate: Bool = false) throws -> String {
                    try Task.checkCancellation()
                    let assetID = "image-\(assets.count + 1)"
                    let url = workspace.appendingPathComponent("assets/" + assetID + ".png")
                    try autoreleasepool {
                        let image = try PageRasterizer.image(page: page, rect: rect, options: options, applyRotation: rotate)
                        try PageRasterizer.write(image, to: url)
                    }
                    imageBytes += Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
                    guard imageBytes <= options.maximumOutputBytes else { throw ConversionError.resourceLimit("image output bytes") }
                    assets.append(.init(id: assetID, fileURL: url))
                    return assetID
                }
                var pageBlocks: [ReflowBlock]
                if content.requiresPageImage {
                    let path = try saveImage(content.bounds, rotate: true)
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
                        vocabulary: vocabulary, warnings: &warnings)
                    if pageBlocks.contains(where: \.hasReflowedText) {
                        reflowed += 1
                    }
                    if content.preservePageReference {
                        pageBlocks.append(LayoutReconstructor.imageBlock(assetID: try saveImage(content.bounds),
                            page: i + 1, reference: true))
                        warnings.append(.init(code: .imageRegion, page: i + 1,
                            message: "A source-page reference image accompanies reflowed text to preserve all visual content."))
                    }
                }
                LayoutReconstructor.appendPage(pageBlocks, page: content, previousPage: i > 0 ? pages[i - 1] : nil,
                    to: &blocks, vocabulary: vocabulary, warnings: &warnings)
            }
            await progress(.init(stage: .reconstructing, fractionCompleted: 0.6875 + 0.3125 * Double(i + 1) / Double(total),
                page: i + 1, totalPages: total))
        }
        document.releaseCachedPages()
        let title = options.title ?? document.title
            ?? source.deletingPathExtension().lastPathComponent
        let reflowedDocument = ReflowDocument(metadata: .init(title: title.isEmpty ? "Untitled" : title,
            language: options.language, author: options.author), blocks: blocks, assets: assets)
        return Result(document: reflowedDocument, pageCount: total, reflowedPageCount: reflowed,
            recognizedPageCount: pages.filter(\.recognized).count, warnings: warnings)
    }
}
