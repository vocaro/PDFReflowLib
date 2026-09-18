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

    /// Whether a paint covers more than 75% of a page of `bounds`.
    private static func coversPage(_ rect: CGRect, _ bounds: CGRect) -> Bool {
        rect.width * rect.height > bounds.width * bounds.height * 0.75
    }

    /// Whether `rect` lies for the most part inside `container`, as `TintDetector` reads it.
    private static func mostlyInside(_ rect: CGRect, _ container: CGRect) -> Bool {
        let overlap = rect.intersection(container)
        return !overlap.isNull && overlap.width * overlap.height >= rect.width * rect.height * 0.5
    }

    /// Whether the only page-sized thing the page paints is its own backdrop (#164): a flat fill,
    /// not an image and not an outline. A scan, a photograph printed to the edges (the Fed's
    /// chapter openers, #72) and a page-sized rule or frame (the Fed's colophon, which draws a
    /// border around its tint) are pictures of the page; a background colour is not, whoever
    /// paints it — a slide deck gives every slide a full-bleed fill, and the Earthdata deck's
    /// 21 slides are the corpus's only such pages besides the DGA cover.
    static func paintsOnlyItsBackdrop(_ paints: [GraphicsReader.Paint], bounds: CGRect) -> Bool {
        let pageSized = paints.filter { coversPage($0.rect, bounds) }
        return !pageSized.isEmpty && pageSized.allSatisfy { $0.filled && !$0.image }
    }

    /// What such a page draws beside its backdrop, or `nil` when it is not one (#164).
    ///
    /// A presentation tool paints a fill behind every text placeholder as well as behind the
    /// slide, so the page's own art is buried in fills that are nothing but the ground its text
    /// stands on: the Earthdata deck's title and body placeholders, its diagram panels and its
    /// box outlines each hold the lines drawn over them, and clustered they cover the slide, so
    /// the crop that grows from them takes the slide's whole text. Three kinds are set aside:
    ///
    /// - the page-sized backdrop fill;
    /// - any other vector paint holding a line the page reflows (a placeholder, a panel, a box);
    /// - a vector paint drawn inside one of those boxes that holds no line (the deck's arrows
    ///   between its pipeline boxes), which is part of the box's decoration.
    ///
    /// Everything else keeps its crop: every image (the NASA insignia, the photographs, the chart
    /// rasters and the icons), and vector art holding no text that stands on its own — slide 5's
    /// question, drawn as outlines with no text layer, and the DGA cover's outlined lettering.
    static func artBesideBackdrops(_ paints: [GraphicsReader.Paint], lines: [TextLine],
                                   bounds: CGRect) -> [GraphicsReader.Paint]? {
        guard paintsOnlyItsBackdrop(paints, bounds: bounds) else { return nil }
        func isBackdrop(_ paint: GraphicsReader.Paint) -> Bool {
            guard !paint.image else { return false }
            return coversPage(paint.rect, bounds) || lines.contains { mostlyInside($0.rect, paint.rect) }
        }
        let boxes = paints.filter { isBackdrop($0) && !coversPage($0.rect, bounds) }.map(\.rect)
        return paints.filter { paint in
            if paint.image { return true }
            guard !isBackdrop(paint) else { return false }
            return !boxes.contains { $0 != paint.rect && $0.contains(paint.rect) }
        }
    }

    /// What a page's own crops (`graphicsWithLabels` of the composed page) would take out of its
    /// text: the words they meet, the words the page carries, and whether one covers the page.
    static func cropOutcome(_ content: PageContent) -> (taken: Int, total: Int, coversPage: Bool) {
        func words(_ lines: [TextLine]) -> Int {
            lines.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
        }
        let crops = LayoutReconstructor.graphicsWithLabels(content)
        return (words(content.lines.filter { line in crops.contains { $0.intersects(line.rect) } }),
                words(content.lines),
                crops.contains { coversPage($0, content.bounds) })
    }

    /// Whether a page whose painted regions cluster into a page-sized one is a born-digital layout
    /// rather than text over a picture of the page (#117). The review signal stays for a page with
    /// any invisible text (an inherited OCR layer), with one page-sized paint that is not its
    /// backdrop fill (a scan, a photograph, the Fed colophon's full-page border, #164), or whose
    /// own crops do not come apart: `content` is the page after tint composition, and its crops
    /// must neither cover 75% of the page nor take more than a tenth of its words. DGA pages 3–5
    /// cluster section bands, icons, callout boxes and a margin timeline into one region whose
    /// crops leave only the running foot; NOAA's photo-and-chart pages, whose crops would still
    /// hold their text, keep the reference.
    ///
    /// A page that paints only its backdrop (#164) writes its own text over a background colour,
    /// so its crops are its figures rather than pieces of a picture, and a figure may hold its
    /// own label: such a page is a picture of itself only when its crops hold *most* of its words.
    /// The DGA cover's crops hold 10 of its 16 (its title is drawn as art over a full-page fill,
    /// and the text layer is a Type 3 transcription that paints nothing); the busiest slide of
    /// the Earthdata deck reaches 5 of 20.
    static func layoutComesApart(_ content: PageContent, graphics: GraphicsReader.Result) -> Bool {
        let backdrop = paintsOnlyItsBackdrop(graphics.paints, bounds: content.bounds)
        guard !graphics.hasInvisibleText,
              backdrop || !graphics.paints.contains(where: { coversPage($0.rect, content.bounds) })
        else { return false }
        let outcome = cropOutcome(content)
        guard !outcome.coversPage else { return false }
        return outcome.taken * (backdrop ? 2 : 10) <= outcome.total
    }

    /// Whether lines form a numeric grid (#143): at least three rows, each holding at least two
    /// decimal numbers (`0.8861`, `158.950`) that make up at least half its words. Census's table rows
    /// (`rnkswp05 0.8861 0.9620`, `46.11 47.06 46.66 49.90 50.85 49.45`) qualify; its prose, numbered
    /// fields (`12. Aged exemption flag`) and references (`B, 39 (1977) 1–38.`) do not.
    static func holdsNumericGrid(_ lines: [TextLine]) -> Bool {
        let decimal = try! NSRegularExpression(pattern: #"^[-−+]?\d+\.\d+%?$"#)
        var rows = 0
        for line in lines {
            let words = line.text.split(whereSeparator: \.isWhitespace)
            let numbers = words.filter { word in
                let text = String(word)
                return decimal.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
            }.count
            if numbers >= 2, numbers * 2 >= words.count { rows += 1 }
            if rows >= 3 { return true }
        }
        return false
    }

    /// Whether lines hold a numeric grid (`holdsNumericGrid`) outside every table of aligned
    /// columns layout reads (`BorderlessTableDetector.alignedTables`, #150). Extraction has split
    /// such a table's rows into cells, which no longer hold two numbers each.
    static func holdsUnreadNumericGrid(_ lines: [TextLine]) -> Bool {
        guard holdsNumericGrid(lines) else { return false }
        let read = BorderlessTableDetector.alignedTables(in: lines).flatMap(\.ownedLines)
        return holdsNumericGrid(lines.filter { !read.contains($0) })
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
        // Characters of fonts that name glyphs by index, established from the whole document's
        // words before any page is read (#143).
        let glyphDecodings = try GlyphIndexDecoder.read(source, language: options.language)
        var chapterStartPages: Set<Int> = []
        /// Pages whose type, if any, arrives inside an image: no text layer, or text over a
        /// page-sized graphic. The encoding classifier reads a typeset full-page raster of such a
        /// page as a scan rather than born-digital text (#193).
        var pagesDrawnFromImage: Set<Int> = []
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
            throws -> (content: PageContent, attemptsOCR: Bool, damagedEncoding: Bool,
                       implausibleLayer: TextLayerPlausibility.Finding?, drawnText: Bool) {
            // The pool includes every PDFKit accessor, not only string extraction. Page
            // references and annotation arrays also carry autoreleased rendering resources.
            let glyphReport = NativeTextReader.IndexGlyphReport()
            var (content, unmappedFont, pageSizedGraphic, graphics, visibleAnnotations,
                 backdropReference) = try autoreleasepool {
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
                // A form's ruled blanks are printed structure (#152): a line PDFKit reads across
                // one is cut there, and the rules seed no crops.
                let blanks = native ? AnnotationEvidence.blanks(on: page, paints: graphics.paints.map(\.rect)) : []
                var content = PageContent(number: i + 1, bounds: bounds,
                    lines: try NativeTextReader.lines(on: page, limit: limit, includeStyle: native,
                        columnJoints: native ? GraphicsReader.columnJoints(graphics.paints.map(\.rect)) : [],
                        borderlessTableInk: native ? graphics.paints.map(\.rect) : nil,
                        blanks: blanks, glyphDecodings: glyphDecodings, report: glyphReport),
                    graphics: graphics.regions)
                content.blanks = blanks
                if !requiresPageImage && !syntheticStyle && options.ocr != .always, let structure {
                    let tags = structure.pages[i + 1] ?? [:]
                    // Tagged list items annotate lines (#194); an unvalidated set is dropped silently,
                    // since list roles form no groups whose fallback a warning would report.
                    var listTags = structure.listTags[i + 1] ?? [:]
                    if !listTags.isEmpty, !StructureTreeReader.validates(listTags,
                        owners: structure.listOwners[i + 1] ?? [:], page: reference) { listTags = [:] }
                    if !tags.isEmpty, !(StructureTreeReader.validates(tags, owners: structure.owners[i + 1] ?? [:], page: reference)
                                       && MarkedTextReader.apply(tags, listTags: listTags, page: reference, lines: &content.lines)) {
                        warnings.append(.init(code: .structureFallback, page: i + 1,
                            message: "Some tagged text could not be matched unambiguously to native lines; spatial reconstruction is retained for those groups."))
                    } else if tags.isEmpty, !listTags.isEmpty {
                        _ = MarkedTextReader.apply([:], listTags: listTags, page: reference, lines: &content.lines)
                    }
                }
                // Text the rendering never shows (beneath a later opaque image or fill, or wholly
                // outside the clip) is not reflowed (#74, #85). After tag association, so a hidden
                // line cannot cost its page a structure fallback it would otherwise not report.
                if !requiresPageImage && !syntheticStyle {
                    _ = HiddenTextFilter.removeHidden(&content.lines, graphics: graphics)
                }
                // Rectangles behind prose (sidebar frames, tint bands, cell shading) stop
                // seeding crops once the text shows they are decoration; everything else
                // clusters exactly as the reader's regions did. A page that paints nothing
                // page-sized but its own backdrop composes the art beside that backdrop (#164),
                // so a slide's placeholders and boxes do not take the text drawn on them.
                if !requiresPageImage {
                    let paints = graphics.paints.filter { paint in !blanks.contains { $0.rule.contains(paint.rect) } }
                    let art = artBesideBackdrops(paints, lines: content.lines, bounds: bounds)
                    let composed = TintDetector.compose(art ?? paints, lines: content.lines, bounds: bounds)
                    content.graphics = composed.graphics
                    content.tints = composed.tints
                    content.separators = composed.separators
                    // List bullets drawn as shapes open their lines as `•`, not as crops (#167).
                    if !syntheticStyle { DrawnBulletReader.apply(&content, paints: graphics.paints) }
                }
                content.requiresPageImage = requiresPageImage
                content.hasSyntheticTextStyle = syntheticStyle
                if graphics.unsupported {
                    warnings.append(.init(code: .unsupportedGraphics, page: i + 1,
                        message: "Unsupported or excessive drawing operations require the original page image."))
                }
                // Only annotations that change what a reader sees earn a reference (#151); links and
                // form fields that draw nothing beyond the printed page lose only their interaction.
                let annotations = try AnnotationEvidence.judge(page, bounds: bounds)
                if !requiresPageImage && !syntheticStyle {
                    AnnotationEvidence.markBoxes(annotations.boxes, in: &content.lines)
                }
                if annotations.visible > 0 {
                    content.preservePageReference = true
                    warnings.append(.init(code: .annotationsNotConverted, page: i + 1,
                        message: options.referenceImages == .never
                            ? "Visible annotations and link/form interactions are not reconstructed; supplementary references are disabled."
                            : "A page image preserves visible annotations. Link and form interactions are not reconstructed."))
                } else if !annotations.isEmpty {
                    warnings.append(.init(code: .annotationsNotConverted, page: i + 1,
                        message: AnnotationEvidence.interactionMessage(annotations)))
                }
                // Structural font evidence is read here; the text judgment follows outside the pool.
                // The page-sized-graphic signal reads the painted regions before tint removal, so a
                // full-page background still clusters into such a region. A born-digital layout
                // whose art only clusters into one is exempt (`layoutComesApart`), and so, unless
                // its crops hold most of its words, is a page that paints only its backdrop (#164).
                let pageArea = bounds.width * bounds.height
                let pageSized = graphics.regions.contains { $0.width * $0.height > pageArea * 0.75 }
                    && (requiresPageImage || !layoutComesApart(content, graphics: graphics))
                // Such a page reflows its whole text even when a figure of its own would take a
                // word of it: the deck's pipeline icons are drawn in boxes over their labels, so
                // preserving them as regions would take those labels out of the slide. The page
                // then keeps a source-page reference and no crop, as an unverified page does,
                // but its native text is not in doubt and it reports no review warning.
                let backdropReference = !requiresPageImage && !pageSized && !content.lines.isEmpty
                    && paintsOnlyItsBackdrop(graphics.paints, bounds: bounds)
                    && cropOutcome(content).taken > 0
                // The font evidence stands unless line repair read the page's index-glyph shows and
                // repaired every line (#143): a show in an undecoded font, or a glyph without an
                // established character, leaves its line unrepaired or its show unplaced, so such a
                // page drew only established characters. A repaired page holding a numeric grid that
                // no table reads also keeps it, since its rows would reflow as run-together cells
                // while recognition keeps the table as an image; the grids layout reads as tables
                // (`BorderlessTableDetector.alignedTables`, Census pages 12 and 15, #150) do not.
                let repaired = glyphReport.repairedLines > 0 && glyphReport.unrepairedLines == 0
                    && !holdsUnreadNumericGrid(content.lines)
                return (content, !content.lines.isEmpty && !requiresPageImage && !repaired && TextEncodingCheck.hasUnmappedFont(reference),
                        pageSized, graphics, annotations.visible, backdropReference)
            }
            // A page that paints nothing and renders as white paper keeps only its boundary: no
            // recognition, no page image (#132).
            if content.lines.isEmpty, try autoreleasepool(invoking: {
                let page = try document.page(at: i)
                guard BlankPageDetector.drawsNothing(lines: content.lines, graphics: graphics,
                                                     annotations: visibleAnnotations),
                      let reference = page.pageRef else { return false }
                return BlankPageDetector.rendersWhite(reference, bounds: content.bounds)
            }) {
                content.requiresPageImage = false
                return (content, false, false, nil, false)
            }
            let invisibleText = graphics.hasInvisibleText
            let bounds = content.bounds
            let raw = content.lines.map(\.text).joined()
            let damaged = raw.unicodeScalars.filter { $0.value == 0xFFFD || $0.value == 0xFFFC }.count
            // Index-style glyph names without ToUnicode make PDFKit report indexes as characters.
            // Flag only when the extracted words also fail the declared language's statistics, judged
            // on PDFKit's own text where some lines were repaired (#143).
            let judgedText = glyphReport.repairedLines > 0
                ? glyphReport.nativeText.joined(separator: "\n") : content.lines.map(\.text).joined(separator: "\n")
            let damagedEncoding = unmappedFont
                && TextEncodingCheck.isImplausible(judgedText, language: options.language)
            // Share the same conservative page-sized-graphic signal with the review warning.
            // It identifies a candidate for re-recognition, not an erroneous transcription.
            let imageBackedText = !content.lines.isEmpty && pageSizedGraphic
            // Inherited text over the image that does not read as English, or leaves most of the
            // page's text-shaped ink uncovered, is not a plausible transcription of it (#93). Judged
            // under every policy, so the page is reported whether or not its text is replaced.
            let implausibleLayer = imageBackedText && !content.requiresPageImage && !damagedEncoding
                ? try TextLayerPlausibility.judge(lines: content.lines, language: options.language) {
                    try autoreleasepool {
                        try TextLayerPlausibility.measureInk(page: try document.page(at: i), bounds: bounds,
                                                             lines: content.lines, options: options)
                    }
                } : nil
            let automaticOCR = options.ocr == .automatic || options.ocr == .automaticIncludingImageBackedText
                || options.ocr == .automaticKeepingImageBackedText
            let noText = raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if noText || imageBackedText { pagesDrawnFromImage.insert(i) }
            // A page that reflows no word of its own, but draws writing over its ground, has no
            // text layer to judge: its sentence is artwork (#176). Such a page is recognized like
            // a page with no text layer at all, under every automatic policy, so its words reach
            // the reading order instead of being lost with the art that carries them. A page whose
            // art forms no row of text-shaped ink — a chart, a diagram of symbols — keeps its crops
            // untouched, and so does a page whose only rows are inside a photograph, which is a
            // picture of the world rather than writing the page set. Pages with no text at all are
            // already recognized above, and image-backed text is #93's question, so neither is
            // rendered again here.
            let drawsText = !noText && !imageBackedText && !damagedEncoding && !content.requiresPageImage
                && automaticOCR
            let placedImages = graphics.paints.filter(\.image).map(\.rect) + graphics.inlineImages
            let drawnText = try drawsText
                && TextLayerPlausibility.judgeImageOnly(lines: content.lines, language: options.language) {
                    try autoreleasepool {
                        try TextLayerPlausibility.measureInk(page: try document.page(at: i), bounds: bounds,
                                                             lines: content.lines, excluding: placedImages,
                                                             options: options)
                    }
                }
            let needsOCR = options.ocr == .always || (automaticOCR &&
                (noText || damaged > max(2, raw.count / 50) || damagedEncoding || drawnText))
                || (options.ocr == .automaticIncludingImageBackedText && imageBackedText)
                || (options.ocr == .automatic && implausibleLayer != nil)
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
            if attemptsOCR { return (content, true, damagedEncoding, implausibleLayer, drawnText) }
            if damagedEncoding {
                content.preservePageReference = true
                for index in content.lines.indices {
                    content.lines[index].structure = nil
                    content.lines[index].listTag = nil
                }
            }
            // Inline images over an inherited OCR layer mark what recognition could not transcribe:
            // evidence for whole figures and display rows, not crops (#37). On such a page only the
            // page-sized scan is background; what is drawn over it keeps its crop. Every other
            // image-backed page clears its graphics as before: art behind visible text (DGA, CDC)
            // would otherwise take that text into crops.
            var retainedGraphics: [CGRect] = []
            if !content.requiresPageImage, imageBackedText, invisibleText, !graphics.inlineImages.isEmpty {
                // A path with no extent (`0 0 m 0 0 l S`, NBS) is only the reader's 2-point
                // margin around a point: nothing distinguishable from the scan's own ink.
                let paints = graphics.paints.filter {
                    $0.rect.width * $0.rect.height <= bounds.width * bounds.height * 0.75
                        && ($0.rect.width > 4.01 || $0.rect.height > 4.01)
                        && !graphics.inlineImages.contains($0.rect)
                }
                let grown: [(rect: CGRect, display: Bool)]? = try autoreleasepool {
                    guard let reference = try document.page(at: i).pageRef,
                          let ink = ScanEvidenceRegions.inkMap(reference, bounds: bounds) else { return nil }
                    return ScanEvidenceRegions.classifiedRegions(evidence: graphics.inlineImages, lines: content.lines,
                                                                 bounds: bounds, ink: ink)
                }
                if let grown {
                    retainedGraphics = TintDetector.compose(paints, lines: content.lines, bounds: bounds).graphics
                        + grown.map(\.rect)
                    content.graphicKinds = Dictionary(grown.filter(\.display).map { ($0.rect, .equation) },
                                                      uniquingKeysWith: { first, _ in first })
                } else {
                    // A figure that cannot be grown whole is never cropped in pieces.
                    content.requiresPageImage = true
                }
            }
            if !content.requiresPageImage, imageBackedText {
                // A scan with an existing OCR layer must still reflow. Keep its visual page as a
                // reference rather than treating the full-page scan as one figure covering all text.
                content.preservePageReference = true
                // Tags describe the text they mark. Invisible text over a scan is inherited
                // transcription whose tags (if any) cannot be trusted; visible native text drawn
                // over a background image or tint keeps the roles `MarkedTextReader` validated.
                if invisibleText {
                    for index in content.lines.indices {
                        content.lines[index].structure = nil
                        content.lines[index].listTag = nil
                    }
                }
                // A rule the page draws across its whole measure is furniture evidence, not art:
                // *Agricultural Research* rules its running foot off under every column, and that
                // rule is what admits the foot where a photo credit stands closer than a line
                // height (`FurnitureDetector.ruledOff`, #159). Clearing it with the page's
                // graphics left the foot unrecognized on the two pages whose columns stand over a
                // page-wide gradient, which broke the document's run of feet and printed the foot
                // on those pages and on the index pages after them. Keeping it as a separator
                // preserves the evidence while the page still keeps no crop of its own.
                let boundaryRules = content.graphics.filter {
                    LayoutReconstructor.isPageWideRule($0, bounds: content.bounds)
                }
                content.graphics = retainedGraphics
                content.tints = []
                content.separators = boundaryRules
                warnings.append(.init(code: .unverifiedTextLayer, page: i + 1,
                    message: "Text overlapping a page-sized graphic has not been verified against the source. "
                        + "Transcription, tables, numbers and reading order may be inaccurate. "
                        + (options.referenceImages == .never
                            ? "Check the source PDF before relying on the reflowed text; supplementary references are disabled."
                            : "Check the accompanying source-page image before relying on the reflowed text.")))
            }
            // A page that paints only its backdrop keeps every word: where its own figures would
            // take one, the source-page reference carries the art instead of a crop (#164). The
            // text is native and complete, so no review warning follows.
            if !content.requiresPageImage, !imageBackedText, backdropReference {
                content.preservePageReference = true
                content.graphics = []
                content.tints = []
                content.separators = []
            }
            if content.lines.isEmpty && !content.requiresPageImage {
                content.requiresPageImage = true
            }
            return (content, false, damagedEncoding, implausibleLayer, drawnText)
        }

        let store = PageStore(directory: workspace.appendingPathComponent("pages"))

        var vocabulary: Set<String> = []
        /// The previous page's last line, so a word the page break cut in half is no vocabulary (#148).
        var previousLine: String?
        /// Line ends showing the book prints its hyphen as `=` (#126).
        var equalsHyphens = LayoutReconstructor.EqualsHyphenEvidence()
        /// Pages whose narrow section labels are set in each style (#73).
        var labelEvidence: [LayoutReconstructor.LabelStyle: Int] = [:]
        /// Pages whose heading-size lines are set in each style (#84).
        var headingEvidence: [LayoutReconstructor.LabelStyle: Int] = [:]
        /// The gaps each page's text wraps at, by body size (#181).
        var wrapEvidence: [Int: [CGFloat]] = [:]
        /// Characters per type size over the native pages: the document's body (#186).
        var bodyWeights: [Int: Int] = [:]
        var furniture = FurnitureDetector.Ledger()
        /// Each page's numbered and lettered line markers, by page number (#146).
        var listMarkers: [Int: [LayoutReconstructor.PageMarker]] = [:]
        /// Pages headed `NOTES TO CHAPTER N`, by chapter number.
        var numberedNotePages: [Int: ClosedRange<Int>] = [:]
        /// Slide-deck evidence (#165): the pages carrying text, those of them that read as a slide
        /// (`LayoutReconstructor.isSlide`), and whether every page so far shares one landscape size.
        var textPages = 0
        var slidePages = 0
        var uniformLandscape = true
        var deckBounds: CGRect?
        var recognizedPages = 0
        var characters = 0
        for i in 0..<total {
            try Task.checkCancellation()
            let extracted = try extractPage(i, limit: options.maximumCharacters - characters, warnings: &warnings)
            var content = extracted.content
            // The implausible-layer warning states what became of the layer, known only after recognition.
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
                        reportImplausibleLayer(recognized.lines.isEmpty ? .pageImage : .replaced)
                        content.lines = recognized.lines
                        content.recognized = true
                        content.hasSyntheticTextStyle = false
                        content.preservePageReference = content.preservePageReference || !recognized.lines.isEmpty
                        content.graphics = recognized.tables
                        content.graphicKinds = Dictionary(recognized.tables.map { ($0, .table) },
                                                          uniquingKeysWith: { first, _ in first })
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
                    }
                } catch is CancellationError { throw CancellationError() }
                catch {
                    try Task.checkCancellation()
                    if keepsCropsIfUnread {
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
            if let chapter = noteChapterCandidates.first(where: { $0.page == content.number }),
               ChapterBoundaryReader.matches(chapter, page: content) {
                matchedNoteChapters.insert(chapter.number)
            }
            // Retain heading evidence before removing furniture, after all extraction/OCR work.
            // Retained unreadable text supplies no hyphen-repair vocabulary.
            if !extracted.damagedEncoding || content.recognized {
                LayoutReconstructor.addVocabulary(of: content, to: &vocabulary, after: &previousLine)
                equalsHyphens.add(content)
                for style in LayoutReconstructor.labelEvidence(on: content) { labelEvidence[style, default: 0] += 1 }
                for style in LayoutReconstructor.headingEvidence(on: content) { headingEvidence[style, default: 0] += 1 }
                if let wrap = LayoutReconstructor.wrapEvidence(on: content) { wrapEvidence[wrap.size, default: []].append(wrap.gap) }
                if !content.recognized, !content.hasSyntheticTextStyle, !content.requiresPageImage {
                    LayoutReconstructor.addBodyWeights(of: content.lines, to: &bodyWeights)
                }
            } else {
                // An unread page carries no word across its far edge either.
                previousLine = nil
            }
            // Slide-deck evidence, read from the page as extracted: before furniture removal (a
            // slide's folio is in neither band a title stands in) and before reconstruction.
            if let bounds = deckBounds, bounds != content.bounds { uniformLandscape = false }
            deckBounds = content.bounds
            if content.bounds.width <= content.bounds.height { uniformLandscape = false }
            if !content.lines.isEmpty {
                textPages += 1
                if LayoutReconstructor.isSlide(content) { slidePages += 1 }
            }
            let markers = LayoutReconstructor.listMarkers(on: content)
            if !markers.isEmpty { listMarkers[content.number] = markers }
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
        let bookWraps = LayoutReconstructor.bookWraps(from: wrapEvidence)
        wrapEvidence = [:]
        let documentBody = LayoutReconstructor.bodySize(weights: bodyWeights)
        // An English document's word breaks may consult the system lexicon where its own words are silent (#186).
        if TextEncodingCheck.supports(language: options.language) { vocabulary.insert(LayoutReconstructor.englishLexiconKey) }
        // A deck: at least three pages, every one the same landscape size, and two thirds of the
        // pages carrying text read as slides. A landscape book (NOAA's, 1,834 letter pages on
        // their side) sets thousands of characters to a slide's few hundred and heads its pages
        // with a running head, so almost none of its pages is a slide (#165).
        let slideDeck = total >= 3 && uniformLandscape && textPages > 0 && slidePages * 3 >= textPages * 2
        // Furniture warnings keep their place between extraction and reconstruction warnings.
        let furnitureWarningIndex = warnings.count
        var furnitureWarnings: [ConversionWarning] = []
        var blocks: [ReflowBlock] = [], assets: [ReflowDocument.Asset] = []
        var reflowed = 0
        var imageBytes: Int64 = 0
        var previous: PageContent?
        var previousRegions: [CGRect] = []
        // Up to two pages after `previous` that hold only figures; a paragraph may continue past them.
        var figurePages: [(page: PageContent, images: [CGRect])] = []
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
            LayoutReconstructor.joinDropCapInitials(&content, vocabulary: vocabulary)
            LayoutReconstructor.closeSpacedCompounds(&content, vocabulary: vocabulary)
            let previousPage = i > 0 && !chapterStartPages.contains(content.number) ? previous : nil
            var regions: [CGRect] = []
            var onlyFigures = false
            try autoreleasepool {
                let page = try document.page(at: i)
                func saveImage(_ rect: CGRect, fullPage: Bool = false, rotate: Bool = false) throws -> String {
                    try Task.checkCancellation()
                    let assetID = "image-\(assets.count + 1)"
                    let encoded = try autoreleasepool {
                        // `.automatic` is decided here, where the image's role and its page are known,
                        // from the raster's own buffer (#193).
                        let requested = fullPage ? options.fullPageImageEncoding : options.regionImageEncoding
                        var measured: ImageContentClassifier.Features?
                        let image = try PageRasterizer.image(page: page, rect: rect, options: options, applyRotation: rotate,
                            inspect: requested.isAutomatic ? { measured = ImageContentClassifier.features($0,
                                width: $1, height: $2, bytesPerRow: $3) } : nil)
                        // Only a supplementary reference sits beside its page's reflowed text; a required
                        // fallback (the rotated page) is the page's only copy and is judged like a crop,
                        // as the survey measured it.
                        let encoding = ImageContentClassifier.resolve(requested, role: fullPage && !rotate ? .page : .region,
                            pageDrawnFromImage: pagesDrawnFromImage.contains(i),
                            features: measured ?? ImageContentClassifier.features(of: image))
                        return try PageRasterizer.encode(image, at: workspace.appendingPathComponent("assets/" + assetID),
                            encoding: encoding)
                    }
                    imageBytes += Int64(try encoded.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
                    guard imageBytes <= options.maximumOutputBytes else { throw ConversionError.resourceLimit("image output bytes") }
                    assets.append(.init(id: assetID, fileURL: encoded.url, format: encoded.format))
                    return assetID
                }
                var pageBlocks: [ReflowBlock]
                if content.requiresPageImage {
                    let path = try saveImage(content.bounds, fullPage: true, rotate: true)
                    pageBlocks = [LayoutReconstructor.imageBlock(assetID: path, page: i + 1, kind: .page)]
                    warnings.append(.init(code: .pageImageFallback, page: i + 1,
                        message: "This page is preserved as an image and does not reflow."))
                } else {
                    var images: [(CGRect, String)] = []
                    var imageKinds: [String: PreservedImageKind] = [:]
                    let classified = LayoutReconstructor.classifiedGraphics(content)
                    for (rect, kind) in classified {
                        let assetID = try saveImage(rect)
                        images.append((rect, assetID))
                        imageKinds[assetID] = kind
                    }
                    regions = images.map(\.0)
                    // The caption the page prints beside a crop describes it better than its kind
                    // can (#187); it stays in the reading text as its own block either way.
                    let captioned = LayoutReconstructor.sourceCaptions(for: regions, in: content)
                    let imageCaptions = Dictionary(uniqueKeysWithValues:
                        images.compactMap { rect, assetID in captioned[rect].map { (assetID, $0) } })
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
                        labelStyles: labelStyles, headingStyles: headingStyles,
                        neighbouringMarkers: (listMarkers[content.number - 1] ?? []) + (listMarkers[content.number + 1] ?? []),
                        slideDeck: slideDeck, imageKinds: imageKinds, imageCaptions: imageCaptions,
                        bookWraps: bookWraps, documentBody: documentBody)
                    if pageBlocks.contains(where: \.hasReflowedText) {
                        reflowed += 1
                    }
                    onlyFigures = LayoutReconstructor.holdsOnlyFigures(pageBlocks, page: content)
                    let includeReference = options.referenceImages == .always
                        || (options.referenceImages == .automatic && content.preservePageReference)
                    if includeReference {
                        pageBlocks.append(LayoutReconstructor.imageBlock(assetID: try saveImage(content.bounds, fullPage: true),
                            page: i + 1, kind: .sourcePage))
                        warnings.append(.init(code: .imageRegion, page: i + 1,
                            message: "A source-page reference image accompanies reflowed text to preserve all visual content."))
                    } else if content.preservePageReference {
                        warnings.append(.init(code: .referenceImageOmitted, page: i + 1,
                            message: "Client policy omits a supplementary source-page image recommended for this page. "
                                + "Compare the source PDF for visual content and transcription accuracy."))
                    }
                }
                LayoutReconstructor.appendPage(pageBlocks, page: content, images: regions, previousPage: previousPage,
                    previousImages: previousRegions, skippedPages: previousPage == nil ? [] : figurePages,
                    to: &blocks, vocabulary: vocabulary, continuesNote: continuesNote, warnings: &warnings)
                if previousPage != nil {
                    LayoutReconstructor.joinContinuedFootnote(&blocks, page: content.number,
                        vocabulary: vocabulary, warnings: &warnings)
                }
            }
            // A figure-only page keeps the last body page as `previous`, unless it opens a
            // chapter or two such pages already stand between.
            if onlyFigures, previousPage != nil, figurePages.count < 2 {
                figurePages.append((content, regions))
            } else {
                previous = content
                previousRegions = regions
                figurePages = []
            }
            await progress(.init(stage: .reconstructing, fractionCompleted: 0.6875 + 0.3125 * Double(i + 1) / Double(total),
                page: i + 1, totalPages: total))
        }
        document.releaseCachedPages()
        store.finish()
        // Typographic heading levels need every page's sizes; tagged levels are already final.
        LayoutReconstructor.rankHeadingLevels(&blocks, slideDeck: slideDeck)
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
        // Verified bulleted and numbered runs become real list items once every join and link is
        // made; everything else list-shaped stays preformatted (#194).
        ListBuilder.build(&blocks)
        // The PDF's own title is extracted text too, so it is spelled out as the pages are (#189).
        let title = options.title ?? document.title.map { InlineText.spellingOutLigatures($0) }
            ?? source.deletingPathExtension().lastPathComponent
        let reflowedDocument = ReflowDocument(metadata: .init(title: title.isEmpty ? "Untitled" : title,
            language: options.language, author: options.author), blocks: blocks, assets: assets,
            chapterStartPages: chapterStartPages)
        return Result(document: reflowedDocument, pageCount: total, reflowedPageCount: reflowed,
            recognizedPageCount: recognizedPages, warnings: warnings, noteLinks: noteLinks)
    }
}
