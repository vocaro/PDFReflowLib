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
        var noteLinks = NoteLinker.Summary()
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
        // Chapter evidence for note references: the spine's labelled chapters, or an outline
        // that numbers its chapters without the word. Each candidate must still match its page.
        let noteChapterCandidates = chapterCandidates.isEmpty
            ? try ChapterBoundaryReader.read(source, scheme: .numbered) : chapterCandidates
        var matchedNoteChapters: Set<Int> = []
        var warnings: [ConversionWarning] = []
        if structureIndex.rejected {
            warnings.append(.init(code: .structureFallback, page: 1,
                message: "Some PDF structure tags are invalid or outside supported paragraph/heading roles; spatial reconstruction remains in use for that content."))
        }

        /// Every extraction step except recognition. `limit` only guards the character budget;
        /// it never truncates a page.
        func extractPage(_ i: Int, limit: Int, warnings: inout [ConversionWarning])
            throws -> (content: PageContent, attemptsOCR: Bool, damagedEncoding: Bool) {
            // The pool includes every PDFKit accessor, not only string extraction. Page
            // references and annotation arrays also carry autoreleased rendering resources.
            var (content, unmappedFont, pageSizedGraphic, invisibleText) = try autoreleasepool {
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
                // A ruled grid's column joints split table cells PDFKit merges into one line (#65),
                // and so does the column gap of a borderless table with capital headings (#121).
                let native = !requiresPageImage && !syntheticStyle
                var content = PageContent(number: i + 1, bounds: bounds,
                    lines: try NativeTextReader.lines(on: page, limit: limit, includeStyle: native,
                        columnJoints: native ? GraphicsReader.columnJoints(graphics.paints.map(\.rect)) : [],
                        borderlessTableInk: native ? graphics.paints.map(\.rect) : nil),
                    graphics: graphics.regions)
                if !requiresPageImage && !syntheticStyle && options.ocr != .always, let structure,
                   let tags = structure.pages[i + 1], !tags.isEmpty,
                   !(StructureTreeReader.validates(tags, owners: structure.owners[i + 1] ?? [:], page: reference)
                     && MarkedTextReader.apply(tags, page: reference, lines: &content.lines)) {
                    warnings.append(.init(code: .structureFallback, page: i + 1,
                        message: "Some tagged text could not be matched unambiguously to native lines; spatial reconstruction is retained for those groups."))
                }
                // Text the rendering never shows (beneath a later opaque image or fill, or wholly
                // outside the clip) is not reflowed (#74, #85). After tag association, so a hidden
                // line cannot cost its page a structure fallback it would otherwise not report.
                if !requiresPageImage && !syntheticStyle {
                    _ = HiddenTextFilter.removeHidden(&content.lines, graphics: graphics)
                }
                // Rectangles behind prose (sidebar frames, tint bands, cell shading) stop
                // seeding crops once the text shows they are decoration; everything else
                // clusters exactly as the reader's regions did.
                if !requiresPageImage {
                    let composed = TintDetector.compose(graphics.paints, lines: content.lines, bounds: bounds)
                    content.graphics = composed.graphics
                    content.tints = composed.tints
                    content.separators = composed.separators
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
                // Structural font evidence is read here; the text judgment follows outside the pool.
                // The page-sized-graphic signal keeps reading the painted regions before tint
                // removal, so a full-page background still earns the review warning and reference.
                return (content, !content.lines.isEmpty && !requiresPageImage && TextEncodingCheck.hasUnmappedFont(reference),
                        graphics.regions.contains { $0.width * $0.height > bounds.width * bounds.height * 0.75 },
                        graphics.hasInvisibleText)
            }
            let bounds = content.bounds
            let raw = content.lines.map(\.text).joined()
            let damaged = raw.unicodeScalars.filter { $0.value == 0xFFFD || $0.value == 0xFFFC }.count
            // Index-style glyph names without ToUnicode make PDFKit report indexes as characters.
            // Flag only when the extracted words also fail the declared language's statistics.
            let damagedEncoding = unmappedFont
                && TextEncodingCheck.isImplausible(content.lines.map(\.text).joined(separator: "\n"), language: options.language)
            // Share the same conservative page-sized-graphic signal with the review warning.
            // It identifies a candidate for re-recognition, not an erroneous transcription.
            let imageBackedText = !content.lines.isEmpty && pageSizedGraphic
            let automaticOCR = options.ocr == .automatic || options.ocr == .automaticIncludingImageBackedText
            let needsOCR = options.ocr == .always || (automaticOCR &&
                (raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || damaged > max(2, raw.count / 50)
                 || damagedEncoding))
                || (options.ocr == .automaticIncludingImageBackedText && imageBackedText)
            let attemptsOCR = needsOCR && !content.requiresPageImage
            if damagedEncoding {
                warnings.append(.init(code: .damagedTextEncoding, page: i + 1,
                    message: "Native text has no usable Unicode mapping (custom font encoding without ToUnicode) "
                        + "and does not read as the declared language. "
                        + (attemptsOCR ? "Recognition of the page image replaces it."
                            : "The unreadable native text is retained; "
                            + (options.referenceImages == .never
                                ? "supplementary references are disabled, so read the source PDF instead."
                                : "read the accompanying source-page image instead."))))
            }
            if attemptsOCR { return (content, true, damagedEncoding) }
            if damagedEncoding {
                content.preservePageReference = true
                for index in content.lines.indices { content.lines[index].structure = nil }
            }
            if !content.requiresPageImage, imageBackedText {
                // A scan with an existing OCR layer must still reflow. Keep its visual page as a
                // reference rather than treating the full-page scan as one figure covering all text.
                content.preservePageReference = true
                // Tags describe the text they mark. Invisible text over a scan is inherited
                // transcription whose tags (if any) cannot be trusted; visible native text drawn
                // over a background image or tint keeps the roles `MarkedTextReader` validated.
                if invisibleText {
                    for index in content.lines.indices { content.lines[index].structure = nil }
                }
                content.graphics = []
                content.tints = []
                content.separators = []
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
            return (content, false, damagedEncoding)
        }

        let store = PageStore(directory: workspace.appendingPathComponent("pages"))

        var vocabulary: Set<String> = []
        /// Line ends showing the book prints its hyphen as `=` (#126).
        var equalsHyphens = LayoutReconstructor.EqualsHyphenEvidence()
        /// Pages whose narrow section labels are set in each style (#73).
        var labelEvidence: [LayoutReconstructor.LabelStyle: Int] = [:]
        /// Pages whose heading-size lines are set in each style (#84).
        var headingEvidence: [LayoutReconstructor.LabelStyle: Int] = [:]
        var furniture = FurnitureDetector.Ledger()
        /// Pages headed `NOTES TO CHAPTER N`, by chapter number.
        var numberedNotePages: [Int: ClosedRange<Int>] = [:]
        var recognizedPages = 0
        var characters = 0
        for i in 0..<total {
            try Task.checkCancellation()
            let extracted = try extractPage(i, limit: options.maximumCharacters - characters, warnings: &warnings)
            var content = extracted.content
            if extracted.attemptsOCR {
                await progress(.init(stage: .recognizing, fractionCompleted: 0.6875 * Double(i) / Double(total),
                    page: i + 1, totalPages: total))
                do {
                    let recognized = try await OCRReader.read(page: try document.page(at: i), options: options)
                    content.lines = recognized.lines
                    content.recognized = true
                    content.hasSyntheticTextStyle = false
                    content.preservePageReference = content.preservePageReference || !recognized.lines.isEmpty
                    content.graphics = recognized.tables
                    content.tints = []
                    content.separators = []
                    content.requiresPageImage = recognized.lines.isEmpty
                    warnings.append(.init(code: .ocrUsed, page: i + 1,
                        message: "Text is OCR transcription. " + (options.referenceImages == .never && !recognized.lines.isEmpty
                            ? "Supplementary references are disabled; compare unrecognized visual content with the source PDF."
                            : "The original page image preserves unrecognized visual content.")
                            + OCRReader.coverageNote(retriedInBands: recognized.retriedInBands,
                                uncoveredTextFraction: recognized.uncoveredTextFraction,
                                referencesDisabled: options.referenceImages == .never)
                            // Once per conversion, on the first recognized page (#106).
                            + (warnings.contains { $0.code == .ocrUsed } ? "" : OCRReader.languageFallbackNote(for: options.language))))
                } catch is CancellationError { throw CancellationError() }
                catch {
                    try Task.checkCancellation()
                    content.requiresPageImage = true
                    warnings.append(.init(code: .ocrFailed, page: i + 1,
                        message: "OCR failed; the source page is preserved as an image."))
                }
                if content.lines.isEmpty && !content.requiresPageImage {
                    content.requiresPageImage = true
                }
            }
            characters += content.lines.reduce(0) { $0 + $1.text.count }
            guard characters <= options.maximumCharacters else { throw ConversionError.resourceLimit("document text") }
            if let chapter = chapterCandidates.first(where: { $0.page == content.number }),
               ChapterBoundaryReader.matches(chapter, page: content) {
                chapterStartPages.insert(content.number)
            }
            if let chapter = noteChapterCandidates.first(where: { $0.page == content.number }),
               ChapterBoundaryReader.matches(chapter, page: content) {
                matchedNoteChapters.insert(chapter.number)
            }
            // Retain heading evidence before removing furniture, after all extraction/OCR work.
            // Retained unreadable text supplies no hyphen-repair vocabulary.
            if !extracted.damagedEncoding || content.recognized {
                LayoutReconstructor.addVocabulary(of: content, to: &vocabulary)
                equalsHyphens.add(content)
                for style in LayoutReconstructor.labelEvidence(on: content) { labelEvidence[style, default: 0] += 1 }
                for style in LayoutReconstructor.headingEvidence(on: content) { headingEvidence[style, default: 0] += 1 }
            }
            if let chapters = NumberedNoteDetector.chapters(on: content) { numberedNotePages[content.number] = chapters }
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
        let labelStyles = LayoutReconstructor.labelStyles(from: labelEvidence)
        let equalsMarksHyphens = equalsHyphens.marksHyphens
        let headingStyles = LayoutReconstructor.labelStyles(from: headingEvidence)
        // Furniture warnings keep their place between extraction and reconstruction warnings.
        let furnitureWarningIndex = warnings.count
        var furnitureWarnings: [ConversionWarning] = []
        var blocks: [ReflowBlock] = [], assets: [ReflowDocument.Asset] = []
        var reflowed = 0
        var imageBytes: Int64 = 0
        var previous: PageContent?
        var previousRegions: [CGRect] = []
        // A numbered list inside a note still open at the previous page's end (#87).
        var openNoteList: NumberedNoteDetector.OpenList?
        // The note the previous page's last line belongs to, which this page may continue (#11).
        var openNote: NumberedNoteDetector.Layout.Note?
        for i in 0..<total {
            try Task.checkCancellation()
            let continuingNoteList = openNoteList, continuingNote = openNote
            openNoteList = nil
            openNote = nil
            var continuesNote = false
            var content = try store.load(at: i)
            if let furniturePlan, let warning = FurnitureDetector.apply(furniturePlan, to: &content, pageIndex: i) {
                furnitureWarnings.append(warning)
            }
            if equalsMarksHyphens { LayoutReconstructor.restoreEqualsHyphens(&content) }
            let previousPage = i > 0 && !chapterStartPages.contains(content.number) ? previous : nil
            var regions: [CGRect] = []
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
                    regions = images.map(\.0)
                    if !images.isEmpty {
                        warnings.append(.init(code: .imageRegion, page: i + 1,
                            message: "Graphical regions retain source appearance as images; their internal text does not reflow."))
                    }
                    pageBlocks = LayoutReconstructor.blocks(page: content, images: images,
                        vocabulary: vocabulary, warnings: &warnings,
                        noteChapter: numberedNotePages[content.number]?.lowerBound,
                        noteLastChapter: numberedNotePages[content.number]?.upperBound,
                        continuingNoteList: continuingNoteList,
                        noteLayout: { layout in
                            openNoteList = layout?.openList
                            openNote = layout?.lastNote
                            continuesNote = layout?.continuesParagraph == true
                        },
                        continuingNote: continuingNote,
                        continuesNote: previousPage != nil && blocks.last?.isFootnote == true,
                        labelStyles: labelStyles, headingStyles: headingStyles)
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
                LayoutReconstructor.appendPage(pageBlocks, page: content, images: regions, previousPage: previousPage,
                    previousImages: previousRegions, to: &blocks, vocabulary: vocabulary, continuesNote: continuesNote,
                    warnings: &warnings)
                if previousPage != nil {
                    LayoutReconstructor.joinContinuedFootnote(&blocks, page: content.number,
                        vocabulary: vocabulary, warnings: &warnings)
                }
            }
            previous = content
            previousRegions = regions
            await progress(.init(stage: .reconstructing, fractionCompleted: 0.6875 + 0.3125 * Double(i + 1) / Double(total),
                page: i + 1, totalPages: total))
        }
        document.releaseCachedPages()
        store.finish()
        // Typographic heading levels need every page's sizes; tagged levels are already final.
        LayoutReconstructor.rankHeadingLevels(&blocks)
        warnings.insert(contentsOf: furnitureWarnings.sorted { $0.page < $1.page }, at: furnitureWarningIndex)
        // A body page's chapter is the last matched chapter opening at or before it; an
        // outline entry that failed to match leaves its pages unknown, and a page headed
        // `NOTES TO CHAPTER N` is not body.
        // A notes page whose printed head contradicts its numbering from both sides is keyed by
        // the numbering (#87); the decision is recorded in the link summary.
        let rescoped = NumberedNoteDetector.scopeByContinuity(&blocks, heads: numberedNotePages)
        var noteLinks = NoteLinker.link(&blocks) { page in
            guard numberedNotePages[page] == nil,
                  let candidate = noteChapterCandidates.last(where: { $0.page <= page }),
                  matchedNoteChapters.contains(candidate.number) else { return nil }
            return candidate.number
        }
        noteLinks.rescopedPages = rescoped
        let title = options.title ?? document.title
            ?? source.deletingPathExtension().lastPathComponent
        let reflowedDocument = ReflowDocument(metadata: .init(title: title.isEmpty ? "Untitled" : title,
            language: options.language, author: options.author), blocks: blocks, assets: assets,
            chapterStartPages: chapterStartPages)
        return Result(document: reflowedDocument, pageCount: total, reflowedPageCount: reflowed,
            recognizedPageCount: recognizedPages, warnings: warnings, noteLinks: noteLinks)
    }
}
