import Foundation
import PDFKit

/// Builds a logical document without choosing a publication format. The caller owns the
/// workspace and must keep its assets alive until the chosen writer finishes.
enum PDFReflowLibPipeline {
    struct Result: Sendable {
        /// The collected document, when no consumer took the stream. A streaming caller gets
        /// nil, having already seen every part.
        var document: ReflowDocument?
        var pageCount: Int
        var reflowedPageCount: Int
        var recognizedPageCount: Int
        var imageCount: Int
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
    ///
    /// Reconstruction emits its parts to `emit` as it makes them, so a writer can consume the
    /// document without anyone holding it whole. Only the trailing block is held back, because
    /// the next page can still join its paragraph to it. A caller that passes no consumer gets
    /// the whole document in `Result.document` instead, collected from the same stream, so the
    /// streamed and collected forms cannot diverge.
    static func reconstruct(from source: URL, options: ConversionOptions, workspace: URL,
                            recognize: Recognizer? = nil,
                            emit: (@Sendable (ReflowPart) async throws -> Void)? = nil,
                            progress: @Sendable (ConversionProgress) async -> Void) async throws -> Result {
        let document = try PDFPageSource(url: source, password: options.password)
        let total = document.pageCount
        guard total <= options.maximumPages else { throw ConversionError.resourceLimit("page count") }
        guard options.reviewedPanelImagePages.allSatisfy({ (1...total).contains($0) }) else {
            throw ConversionError.invalidOptions("reviewed panel pages must exist in the source PDF")
        }
        try FileManager.default.createDirectory(at: workspace.appendingPathComponent("assets"),
                                                 withIntermediateDirectories: true)

        // Tagged-text association happens once per page; the index is released after extraction.
        var structure: StructureTreeReader.Index? = try StructureTreeReader.read(source, password: options.password)
        var warnings: [ConversionWarning] = []
        if structure?.rejected == true {
            warnings.append(ConversionWarnings.structureTreeFallback())
        }
        var evidence = DocumentEvidence(chapterCandidates: try ChapterBoundaryReader.read(source, password: options.password), language: options.language)
        // The author's own contents, for navigation only; it manufactures no heading (#249).
        let outline = try OutlineReader.read(source, password: options.password)
        let store = PageStore(directory: workspace.appendingPathComponent("pages"))
        let judge = RecognitionJudge.english(language: options.language)
        /// Pages whose type, if any, arrives inside an image: no text layer, or text over a
        /// page-sized graphic. The encoding classifier reads a typeset full-page raster of such a
        /// page as a scan rather than born-digital text (#193).
        var pagesDrawnFromImage: Set<Int> = []
        /// The page numbers the source prints, where they differ from the physical index (#248).
        var pageLabels: [Int: String] = [:]

        for i in 0..<total {
            try Task.checkCancellation()
            let extracted = try PageReader.read(pageIndex: i, from: document,
                                                limit: options.maximumCharacters - evidence.characters,
                                                options: options, structure: structure)
            warnings += extracted.warnings.map { ConversionWarnings.warning($0, page: i + 1, options: options) }
            if let printed = extracted.printedLabel { pageLabels[i + 1] = printed }
            // Both ink tests share one rendering of the page, made only when a judgment needs it.
            let ink = PageInkMeasurer(bounds: extracted.content.bounds, lines: extracted.content.lines) {
                try autoreleasepool {
                    try TextLayerPlausibility.inkImage(page: try document.page(at: i), bounds: extracted.content.bounds,
                                                       options: options)
                }
            }
            let pageEvidence = try PageDiagnosis.assess(extracted, options: options, measureInk: ink.measure)
            if !pageEvidence.hasText || pageEvidence.imageBackedText { pagesDrawnFromImage.insert(i) }
            if options.reviewedPanelImagePages.contains(i + 1) {
                // This is an explicit source-review decision, not a classifier: text geometry
                // alone cannot tell a balloon stack from a prose column (#18). Keep the source
                // image and do not emit OCR that would claim an unverified narrative order.
                var content = extracted.content
                content.lines = []
                content.requiresPageImage = true
                warnings.append(ConversionWarnings.warning(.reviewedPanelImage, page: i + 1, options: options))
                try evidence.collect(content, pageIndex: i, suppliesVocabulary: false, options: options)
                try store.store(content, at: i)
                await progress(.init(stage: .extracting,
                    fractionCompleted: ProgressBudget.pipeline(extractedPages: i + 1, of: total),
                    page: i + 1, totalPages: total))
                continue
            }
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
                    let reading: OCRReader.Result
                    if let recognize { reading = try await recognize(try document.page(at: i), options) }
                    else {
                        reading = try await OCRReader.read(page: try document.page(at: i), options: options,
                                                           wordPositions: pageEvidence.drawnText)
                    }
                    outcome = .read(pageEvidence.drawnText
                        ? DrawnTextRecovery.reading(reading, on: extracted.content) : reading)
                } catch is CancellationError { throw CancellationError() }
                catch {
                    try Task.checkCancellation()
                    outcome = .failed
                }
            }
            let resolution = RecognitionPolicy.resolve(plan, evidence: pageEvidence, outcome: outcome, judge: judge)
            resolution.disposition.apply(to: &content)
            if pageEvidence.drawnText, case .replaced = resolution.disposition {
                DrawnTextRecovery.preserveArtwork(in: &content, extracted: extracted.content)
            }
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
        // The blocks a later page can still amend: `appendPage` joins a continued paragraph to the
        // paragraph at the tail, stepping over the images that stand between them, so everything
        // before that paragraph is final and can be handed on (#203).
        var pending: [ReflowBlock] = []
        var collector = ReflowDocument.Collector()
        let send: (ReflowPart) async throws -> Void = { part in
            if let emit { try await emit(part) } else { collector.accept(part) }
        }
        // Verified bulleted and numbered runs become real list items on their way out, once
        // every join that can grow a block has been made; the pass holds a block only while a
        // run it may belong to can still change (#292).
        var lists = ListBuilder()
        let sendBlock: (ReflowBlock) async throws -> Void = { block in
            for final in lists.accept(block) { try await send(.block(final)) }
        }
        // Client values win over the document's own, exactly as `options.title` always has; what
        // the document states fills the rest (#253).
        let stated = document.metadata
        let title = options.title ?? stated.title ?? source.deletingPathExtension().lastPathComponent
        try await send(.start(.init(title: title.isEmpty ? "Untitled" : title, language: options.language,
                                    author: options.author ?? stated.author, summary: stated.summary,
                                    keywords: stated.keywords, created: stated.created,
                                    pageLabels: pageLabels, outline: outline),
                              chapterStartPages: evidence.chapterStartPages))
        let assets = PageAssetWriter(workspace: workspace, options: options)
        var sentAssets = 0
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
                    let path = try assets.save(page: page, rect: content.bounds, fullPage: true, rotate: true,
                                               drawnFromImage: pagesDrawnFromImage.contains(i))
                    pageBlocks = [LayoutReconstructor.imageBlock(assetID: path, page: i + 1)]
                    warnings.append(ConversionWarnings.warning(.pageImageFallback, page: i + 1, options: options))
                } else {
                    var images: [(CGRect, String)] = []
                    var imageMath: [String: [MathExpression]] = [:]
                    var pageGlyphs: MathRecognizer.PageGlyphs?
                    for region in LayoutReconstructor.graphicsWithLabels(content, language: options.language) {
                        var glyphs: MathRecognizer.PageGlyphs?
                        if !content.recognized, !content.hasSyntheticTextStyle,
                           !content.links.contains(where: { $0.rect.intersects(region) }),
                           let reference = page.pageRef {
                            glyphs = try pageGlyphs ?? NativeTextReader.withExtractionLock {
                                MathRecognizer.glyphs(on: reference)
                            }
                            pageGlyphs = glyphs
                        }
                        let body = LayoutReconstructor.bodySize(content.lines)
                        let wholeRows = glyphs.flatMap { glyphs in
                            MathRecognizer.rows(in: region, page: glyphs, graphics: content.graphics,
                                                lines: content.lines, body: body)
                                ?? MathRecognizer.workedRows(in: region, page: glyphs,
                                    graphics: content.graphics, lines: content.lines, body: body)
                        }
                        let slices = wholeRows == nil ? glyphs.flatMap {
                            MathRecognizer.radicalExerciseSlices(in: region, page: $0,
                                graphics: content.graphics, lines: content.lines, body: body)
                        } ?? [region] : [region]
                        for rect in slices {
                            if let glyphs {
                                let rows = rect == region ? wholeRows : MathRecognizer.rows(in: rect,
                                    page: glyphs, graphics: content.graphics, lines: content.lines, body: body)
                                if let rows {
                                    let expressions = try rows.map { row in
                                        MathExpression(label: row.label, node: row.node,
                                                       fallbackAssetID: try assets.save(page: page, rect: row.rect,
                                                           drawnFromImage: pagesDrawnFromImage.contains(i)),
                                                       note: row.note)
                                    }
                                    if MathRecognizer.pairedExerciseColumn(rows, body: body) {
                                        // Each source-numbered row owns its own fallback crop.
                                        // Keep those rows as layout elements so the neighbouring
                                        // column can be read between them (Wallace p347, #29).
                                        for (row, expression) in zip(rows, expressions) {
                                            images.append((row.rect, expression.fallbackAssetID))
                                            imageMath[expression.fallbackAssetID] = [expression]
                                        }
                                        continue
                                    }
                                    let id = expressions[0].fallbackAssetID
                                    images.append((rect, id))
                                    imageMath[id] = expressions
                                    continue
                                }
                            }
                            images.append((rect, try assets.save(page: page, rect: rect,
                                                                drawnFromImage: pagesDrawnFromImage.contains(i))))
                        }
                    }
                    if images.contains(where: { imageMath[$0.1] == nil }) {
                        warnings.append(ConversionWarnings.warning(.imageRegion(.regionCrops), page: i + 1, options: options))
                    }
                    // One warning per table the page's recognition located and did not
                    // transcribe, beside the picture that preserves it (#31).
                    for table in content.recognizedTables where !table.cellsWereRead {
                        warnings.append(ConversionWarnings.warning(.unreadTableCells(table), page: i + 1,
                                                                   options: options))
                    }
                    pageBlocks = LayoutReconstructor.blocks(page: content, images: images, context: resolved.context,
                                                            formOutline: resolved.formOutline[i + 1] ?? [],
                                                            formOutlineBaseLevel: resolved.formOutlineBaseLevel,
                                                            formOutlineOuterTier: resolved.formOutlineOuterTier,
                                                            warnings: &warnings)
                    if resolved.context.slideDeck {
                        pageBlocks = SlideDeck.notesLast(pageBlocks, on: content)
                    }
                    for index in pageBlocks.indices {
                        guard case var .image(image) = pageBlocks[index].content else { continue }
                        if let expressions = imageMath[image.assetID] { image.math = expressions }
                        if image.math.isEmpty,
                           let alt = figureAlt(for: image.assetID, images: images,
                                               figures: content.taggedFigures) {
                            image.alternativeText = alt
                        }
                        pageBlocks[index].content = .image(image)
                    }
                    if pageBlocks.contains(where: \.hasReflowedText) {
                        reflowed += 1
                    }
                    let includeReference = options.referenceImages == .always
                        || (options.referenceImages == .automatic && content.preservePageReference)
                    if includeReference {
                        for rect in content.recognizedArtwork {
                            pageBlocks.append(LayoutReconstructor.imageBlock(
                                assetID: try assets.save(page: page, rect: rect,
                                    drawnFromImage: pagesDrawnFromImage.contains(i)),
                                page: i + 1, describing: "Drawn writing from page \(i + 1)"))
                        }
                        pageBlocks.append(LayoutReconstructor.imageBlock(
                            assetID: try assets.save(page: page, rect: content.bounds, fullPage: true,
                                                     drawnFromImage: pagesDrawnFromImage.contains(i)),
                            page: i + 1, reference: true))
                        warnings.append(ConversionWarnings.warning(.imageRegion(.pageReference), page: i + 1, options: options))
                    } else if content.preservePageReference {
                        warnings.append(ConversionWarnings.warning(.referenceImageOmitted, page: i + 1, options: options))
                    }
                }
                LayoutReconstructor.appendPage(pageBlocks, page: content, previousPage: previousPage,
                    to: &pending, hyphens: resolved.context.hyphens, warnings: &warnings)
            }
            previous = content
            // An asset is always sent before the block that names it: this page's images were
            // saved above, and its blocks are still behind the tail.
            while sentAssets < assets.assets.count {
                try await send(.asset(assets.assets[sentAssets]))
                sentAssets += 1
            }
            while pending.count > LayoutReconstructor.amendableTail(of: pending) {
                try await sendBlock(pending.removeFirst())
            }
            await progress(.init(stage: .reconstructing, fractionCompleted: ProgressBudget.pipeline(reconstructedPages: i + 1, of: total),
                page: i + 1, totalPages: total))
        }
        for block in pending { try await sendBlock(block) }
        for block in lists.finish() { try await send(.block(block)) }
        document.releaseCachedPages()
        store.finish()
        warnings.insert(contentsOf: furnitureWarnings.sorted { $0.page < $1.page }, at: furnitureWarningIndex)
        return Result(document: emit == nil ? collector.document : nil, pageCount: total, reflowedPageCount: reflowed,
            recognizedPageCount: evidence.recognizedPages, imageCount: assets.assets.count, warnings: warnings)
    }

    /// The crop must contain exactly one tagged image, and no second crop may also claim it.
    /// The author text describes only that image; ambiguous composite regions keep their
    /// generic description instead of borrowing a nearby Figure's Alt text (#17).
    static func figureAlt(for assetID: String, images: [(CGRect, String)],
                          figures: [PageContent.TaggedFigure]) -> String? {
        guard let crop = images.first(where: { $0.1 == assetID })?.0 else { return nil }
        let matches = figures.filter { figure in
            let overlap = crop.intersection(figure.rect)
            return !overlap.isNull
                && overlap.width * overlap.height >= figure.rect.width * figure.rect.height * 0.95
        }
        guard matches.count == 1,
              images.filter({ $0.0.intersects(matches[0].rect) }).count == 1 else { return nil }
        return matches[0].alternativeText
    }
}
