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

    /// Recognizes one page image. The default is Vision; tests substitute canned readings.
    typealias Recognizer = @Sendable (PDFPage, ConversionOptions) async throws -> OCRReader.Result

    /// Progress covers extraction/reconstruction only, from zero to one.
    ///
    /// Extraction is one pass over every page: `PageReader` reads it, `PageDiagnosis` judges its
    /// text, `RecognitionPolicy` decides whether to recognize the page image and reconciles the
    /// outcome, and `DocumentEvidence` keeps only document-wide evidence before the page is
    /// spilled to a `PageStore`. Reconstruction is a second pass that needs one page and its
    /// predecessor, so retained page memory is bounded.
    static func reconstruct(from source: URL, options: ConversionOptions, workspace: URL,
                            recognize: Recognizer = { try await OCRReader.read(page: $0, options: $1) },
                            progress: @Sendable (ConversionProgress) async -> Void) async throws -> Result {
        let document = try PDFPageSource(url: source)
        let total = document.pageCount
        guard total <= options.maximumPages else { throw ConversionError.resourceLimit("page count") }
        try FileManager.default.createDirectory(at: workspace.appendingPathComponent("assets"),
                                                 withIntermediateDirectories: true)

        // Tagged-text association happens once per page; the index is released after extraction.
        var structure: StructureTreeReader.Index? = try StructureTreeReader.read(source)
        var warnings: [ConversionWarning] = []
        if structure?.rejected == true {
            warnings.append(ConversionWarnings.structureTreeFallback())
        }
        var evidence = DocumentEvidence(chapterCandidates: try ChapterBoundaryReader.read(source), language: options.language)
        let store = PageStore(directory: workspace.appendingPathComponent("pages"))
        let judge = RecognitionJudge.english(language: options.language)

        for i in 0..<total {
            try Task.checkCancellation()
            let extracted = try PageReader.read(pageIndex: i, from: document,
                                                limit: options.maximumCharacters - evidence.characters,
                                                options: options, structure: structure)
            warnings += extracted.warnings.map { ConversionWarnings.warning($0, page: i + 1, options: options) }
            // Both ink tests share one rendering of the page, made only when a judgment needs it.
            let ink = PageInkMeasurer(bounds: extracted.content.bounds, lines: extracted.content.lines) {
                try autoreleasepool {
                    try TextLayerPlausibility.inkImage(page: try document.page(at: i), bounds: extracted.content.bounds,
                                                       options: options)
                }
            }
            let pageEvidence = try PageDiagnosis.assess(extracted, options: options, measureInk: ink.measure)
            let plan = RecognitionPolicy.plan(pageEvidence, policy: options.ocr)
            var content = extracted.content
            // A page whose text stands, or is compared with recognition, is prepared as a kept
            // layer first; a replaced page skips it.
            if !plan.recognizes || plan.compares {
                PageDiagnosis.prepareExtracted(&content, evidence: pageEvidence)
            }
            var outcome: RecognitionOutcome?
            if plan.recognizes {
                await progress(.init(stage: .recognizing, fractionCompleted: ProgressBudget.pipeline(extractedPages: i, of: total),
                    page: i + 1, totalPages: total))
                do {
                    outcome = .read(try await recognize(try document.page(at: i), options))
                } catch is CancellationError { throw CancellationError() }
                catch {
                    try Task.checkCancellation()
                    outcome = .failed
                }
            }
            let resolution = RecognitionPolicy.resolve(plan, evidence: pageEvidence, outcome: outcome, judge: judge)
            resolution.disposition.apply(to: &content)
            warnings += resolution.warnings.map { ConversionWarnings.warning($0, page: i + 1, options: options) }
            // Retained unreadable text supplies no hyphen-repair vocabulary (#38).
            try evidence.collect(content, pageIndex: i, suppliesVocabulary: !pageEvidence.damagedEncoding || content.recognized,
                                 options: options)
            try store.store(content, at: i)
            await progress(.init(stage: .extracting, fractionCompleted: ProgressBudget.pipeline(extractedPages: i + 1, of: total),
                page: i + 1, totalPages: total))
        }
        document.releaseCachedPages()
        structure = nil
        let resolved = evidence.resolved(options: options)
        // Furniture warnings keep their place between extraction and reconstruction warnings.
        let furnitureWarningIndex = warnings.count
        var furnitureWarnings: [ConversionWarning] = []
        var blocks: [ReflowBlock] = []
        let assets = PageAssetWriter(workspace: workspace, options: options)
        var reflowed = 0
        var previous: PageContent?
        for i in 0..<total {
            try Task.checkCancellation()
            var content = try store.load(at: i)
            if let furniturePlan = resolved.furniturePlan,
               let warning = FurnitureDetector.apply(furniturePlan, to: &content, pageIndex: i) {
                furnitureWarnings.append(warning)
            }
            let previousPage = i > 0 && !evidence.chapterStartPages.contains(content.number) ? previous : nil
            try autoreleasepool {
                let page = try document.page(at: i)
                var pageBlocks: [ReflowBlock]
                if content.requiresPageImage {
                    let path = try assets.save(page: page, rect: content.bounds, fullPage: true, rotate: true)
                    pageBlocks = [LayoutReconstructor.imageBlock(assetID: path, page: i + 1)]
                    warnings.append(ConversionWarnings.warning(.pageImageFallback, page: i + 1, options: options))
                } else {
                    var images: [(CGRect, String)] = []
                    for rect in LayoutReconstructor.graphicsWithLabels(content) {
                        images.append((rect, try assets.save(page: page, rect: rect)))
                    }
                    if !images.isEmpty {
                        warnings.append(ConversionWarnings.warning(.imageRegion(.regionCrops), page: i + 1, options: options))
                    }
                    pageBlocks = LayoutReconstructor.blocks(page: content, images: images, context: resolved.context,
                                                            warnings: &warnings)
                    if pageBlocks.contains(where: \.hasReflowedText) {
                        reflowed += 1
                    }
                    let includeReference = options.referenceImages == .always
                        || (options.referenceImages == .automatic && content.preservePageReference)
                    if includeReference {
                        pageBlocks.append(LayoutReconstructor.imageBlock(
                            assetID: try assets.save(page: page, rect: content.bounds, fullPage: true),
                            page: i + 1, reference: true))
                        warnings.append(ConversionWarnings.warning(.imageRegion(.pageReference), page: i + 1, options: options))
                    } else if content.preservePageReference {
                        warnings.append(ConversionWarnings.warning(.referenceImageOmitted, page: i + 1, options: options))
                    }
                }
                LayoutReconstructor.appendPage(pageBlocks, page: content, previousPage: previousPage,
                    to: &blocks, hyphens: resolved.context.hyphens, warnings: &warnings)
            }
            previous = content
            await progress(.init(stage: .reconstructing, fractionCompleted: ProgressBudget.pipeline(reconstructedPages: i + 1, of: total),
                page: i + 1, totalPages: total))
        }
        document.releaseCachedPages()
        store.finish()
        warnings.insert(contentsOf: furnitureWarnings.sorted { $0.page < $1.page }, at: furnitureWarningIndex)
        let title = options.title ?? document.title
            ?? source.deletingPathExtension().lastPathComponent
        let reflowedDocument = ReflowDocument(metadata: .init(title: title.isEmpty ? "Untitled" : title,
            language: options.language, author: options.author), blocks: blocks, assets: assets.assets,
            chapterStartPages: evidence.chapterStartPages)
        return Result(document: reflowedDocument, pageCount: total, reflowedPageCount: reflowed,
            recognizedPageCount: evidence.recognizedPages, warnings: warnings)
    }
}
