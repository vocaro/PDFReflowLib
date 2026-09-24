import Foundation
import PDFKit

/// One page as the PDFKit and Core Graphics readers deliver it, before any judgment about
/// whether its text can be trusted. Everything here is a value; no framework object survives
/// the reader's autorelease pool.
struct ExtractedPage: Equatable, Sendable {
    var content: PageContent
    /// Placed raster image XObjects, which the drawn-text ink test sets aside (#176) and over
    /// which a page can print prose of its own (#239). Carried on the page, so reconstruction
    /// still has them after the extraction pass.
    var placedImages: [CGRect] { content.pictures }
    /// A simple font with an index-style `Differences` encoding and no `ToUnicode` map is
    /// present (#38). Structural evidence only; `PageDiagnosis` adds the word statistics.
    var hasUnmappedFont: Bool
    /// Glyphs of such a font whose decoded characters the extracted text does not carry, because
    /// their line was left as PDFKit read it (`GlyphIndexDecoder.unreadGlyphs`). Zero on every
    /// page without an index-glyph font.
    var unreadGlyphs: Int
    /// The page number the source prints on this page, where it states one and it differs from
    /// the physical index (#248). Nil leaves the physical index to speak for the page.
    var printedLabel: String?
    /// Warnings the readers raised, in emission order.
    var warnings: [PageWarning]
}

/// Every PDFKit and Core Graphics access for one page: geometry, graphics, native text, tagged
/// structure, annotations and font resources. `limit` guards the character budget only; it never
/// truncates a page.
enum PageReader {
    static func read(pageIndex i: Int, from document: PDFPageSource, limit: Int, options: ConversionOptions,
                     structure: StructureTreeReader.Index?) throws -> ExtractedPage {
        // The pool includes every PDFKit accessor, not only string extraction. Page
        // references and annotation arrays also carry autoreleased rendering resources.
        try autoreleasepool {
            let page = try document.page(at: i)
            guard let reference = page.pageRef else {
                throw ConversionError.unreadablePDF
            }
            let bounds = page.bounds(for: .cropBox)
            guard bounds.isFinite, bounds.width > 0, bounds.height > 0,
                  bounds.width <= 100_000, bounds.height <= 100_000 else {
                throw ConversionError.resourceLimit("page geometry")
            }
            var warnings: [PageWarning] = []
            let graphics = GraphicsReader.read(reference)
            let requiresPageImage = graphics.unsupported || page.rotation % 360 != 0
            let syntheticStyle = graphics.hasOnlyInvisibleText
                && graphics.regions.contains { PageDiagnosis.coversPage($0, bounds: bounds) }
            // Link annotations convert to anchors (#247), so they are read before the text: the
            // reader marks the runs they cover as it builds each line. A page whose appearance is
            // preserved whole, or whose text is an invisible transcription of a scan, keeps
            // neither styles nor links, so its links are counted as unconverted with the rest.
            let styled = !requiresPageImage && !syntheticStyle
            var links: [PageLink] = []
            var unconvertedAnnotations: [PDFAnnotation] = []
            for annotation in page.annotations {
                if styled, let link = link(annotation, on: page) { links.append(link) }
                else { unconvertedAnnotations.append(annotation) }
            }
            // Invisible text over a scan supplies transcription, not source typography.
            // Fallback pages contribute vocabulary and furniture evidence, but their
            // formatting is never emitted. Avoid decoding attributed image attachments.
            // The page's own text-showing operations, read once and used twice: the spacing
            // repair reads the word boundaries it carries, and `TableReader` reads the ink the
            // page put on each printed row (#210).
            let shows = styled ? page.pageRef.map(NativeSpacingReader.read) ?? [] : []
            let rules = graphics.regions.filter(LayoutReconstructor.isThinRule)
            let fieldBlanks = styled ? AnnotationEvidence.blanks(on: page, paints: graphics.paints.map(\.rect)) : []
            var content = PageContent(number: i + 1, bounds: bounds,
                lines: try NativeTextReader.lines(on: page, limit: limit, includeStyle: styled,
                    rules: rules, links: links, preserveInvisibleWordGaps: syntheticStyle, shows: shows), graphics: graphics.regions,
                pictures: graphics.images)
            content.blanks = fieldBlanks
            if styled, !SlideDeck.title(in: content).isEmpty {
                content.lines = try NativeTextReader.separateSlideLabels(content.lines, on: page)
            }
            content.links = links
            content = TextBackdrop.compose(content, graphics: graphics)
            if !requiresPageImage, PageBackdrop.eligible(graphics, bounds: bounds),
               ImageAlphaBounds.fitsPageBudget(ImageAlphaBounds.sampleCounts(on: reference)) {
                let trimmed = GraphicsReader.read(reference) { imageIndex, dictionary in
                    guard ImageAlphaBounds.mask(in: dictionary) != nil else { return nil }
                    return document.imageAlphaBounds(page: i, image: imageIndex)
                }
                if let composed = PageBackdrop.compose(content, graphics: trimmed) { content = composed }
            }
            if styled {
                // A pair of boxes printed at the ends of form labels is page content, not a
                // little illustration. Emit selectable marks and remove only the region made
                // wholly of their outlines and connecting rules (#211).
                let drawnBoxes = DrawnCheckboxReader.read(lines: content.lines, paints: graphics.paints,
                                                          regions: content.graphics)
                let outlines = drawnBoxes.flatMap(\.regions)
                content.graphics.removeAll { outlines.contains($0) }
                for row in drawnBoxes.flatMap(\.rows) {
                    let label = content.lines[row.labelIndex]
                    var reading = label.content
                    reading.append(InlineText(" ☐"))
                    var merged = TextLine(content: reading, rect: label.rect.union(row.box),
                                          fontSize: label.fontSize, monospaced: label.monospaced,
                                          wraps: false, turn: label.turn)
                    merged.structure = label.structure
                    content.lines[row.labelIndex] = merged
                }
                content.blanks += FormBlank.printed(paints: graphics.paints.map(\.rect),
                                                   lines: content.lines, fields: fieldBlanks)
                content.lines = try NativeTextReader.splitAtBlanks(content.lines, blanks: content.blanks, on: page)
                let blankRules = content.blanks.map(\.rule)
                content.graphics.removeAll { region in
                    let marks = graphics.paints.filter { region.contains($0.rect) }
                    return !marks.isEmpty && marks.allSatisfy { paint in
                        blankRules.contains { $0.contains(paint.rect) }
                    }
                }
                let body = max(4, LayoutReconstructor.bodySize(content.lines))
                // A printed form can keep its running head as text, yet the thin double rule
                // touching that small head is still decoration, not a figure crop (#211).
                // Require several widget-backed blanks to scope this to an actual form.
                if fieldBlanks.count >= 3,
                   let header = content.lines.filter({ line in
                       line.rect.minY >= bounds.minY + bounds.height * 0.9
                           && line.fontSize <= body * 0.9 && line.text.count < 100
                   }).max(by: { $0.rect.midY < $1.rect.midY }) {
                    let dividers = FurnitureDetector.rulesSettingOff(header,
                        kept: content.lines.filter { $0 != header }, on: content)
                    content.graphics.removeAll { dividers.contains($0) }
                }
                for blank in content.blanks where blank.field.height > body * 2.5 {
                    let area = blank.field.union(blank.rule).insetBy(dx: 2, dy: 2)
                    guard !content.lines.contains(where: { $0.rect.insetBy(dx: 1, dy: 1).intersects(area) }),
                          !content.graphics.contains(where: { $0.intersects(area) }) else { continue }
                    let rule = blank.rule.insetBy(dx: 2, dy: 0)
                    content.lines.append(TextLine(text: FormBlank.text,
                        rect: CGRect(x: rule.minX, y: rule.midY, width: rule.width, height: body),
                        fontSize: body, wraps: false))
                }
            }
            if !requiresPageImage && !syntheticStyle && options.ocr != .always, let structure,
               let tags = structure.pages[i + 1], !tags.isEmpty,
               !(StructureTreeReader.validates(tags, owners: structure.owners[i + 1] ?? [:], page: reference)
                 && MarkedTextReader.apply(tags, page: reference, lines: &content.lines)) {
                warnings.append(.structureFallback)
            }
            content.requiresPageImage = requiresPageImage
            content.hasSyntheticTextStyle = syntheticStyle
            if !requiresPageImage, !syntheticStyle,
               try OutlinedInitial.recover(on: page, content: &content, paints: graphics.paints, options: options) {
                warnings.append(.outlinedInitialUsed)
            }
            // The tables the page draws, read from the same shows after the lines are final, so a
            // table's rows are the rows the rest of the pipeline sees (#210). A page whose
            // appearance is preserved whole states no columns this reader can trust.
            if styled {
                let ruled = try RuledTableReader.tables(on: page, lines: content.lines, paints: graphics.paints)
                content.tables = ruled + (try TableReader.tables(on: page, lines: content.lines,
                                                        shows: shows, rules: rules, filledCells: graphics.filledCells)).filter { table in
                    !ruled.contains { $0.rect.intersects(table.rect) }
                }
            }
            content.lines = LeaderRows.joined(content, paints: graphics.paints)
            // A form widget with no new visible content needs no page picture merely because
            // its interaction cannot be reproduced. Read the printed value under a widget
            // before deciding whether its appearance adds anything (#151, #170).
            let annotationEvidence = try AnnotationEvidence.judge(unconvertedAnnotations, on: page, bounds: bounds)
            if styled { AnnotationEvidence.markBoxes(annotationEvidence.boxes, in: &content.lines) }
            let unconvertedCount = annotationEvidence.visible + annotationEvidence.links
                + annotationEvidence.formFields + annotationEvidence.invisible
            if graphics.unsupported {
                warnings.append(.unsupportedGraphics)
            }
            // Only an annotation that did not convert still needs the page's own picture, which
            // is what `annotationsNotConverted` has always claimed and now means (#247).
            let annotated = !links.isEmpty || unconvertedCount > 0
            if unconvertedCount > 0 {
                content.preservePageReference = annotationEvidence.visible > 0
                warnings.append(.annotationsNotConverted(converted: links.count,
                                                         unconverted: unconvertedCount,
                                                         imagePreserved: annotationEvidence.visible > 0))
            }
            // A page whose content stream paints nothing: no extracted text, no visible text
            // operator, no painted region (a white ground is not one) and no annotation. The
            // judgment belongs here, on the extracted page, rather than after recognition:
            // recognition cannot read writing the page never drew, so this reading of "empty"
            // is both the earlier and the stable one, and it stays the same under every OCR
            // policy. A blank page still becomes a page image, so `pageImageFallback`
            // accompanies this warning; `emptyPage` says why that image is blank (#224).
            if content.lines.isEmpty, !annotated, !graphics.unsupported,
               graphics.regions.isEmpty, !graphics.visibleText {
                warnings.append(.emptyPage)
            }
            // Structural font evidence is read here; the text judgment follows outside the pool.
            let unmappedFont = !content.lines.isEmpty && !requiresPageImage && TextEncodingCheck.hasUnmappedFont(reference)
            // What the decoder read but the page's lines did not take. Read here, beside the
            // font evidence, because it compares the document's own reading with the extracted
            // text and needs neither PDFKit's line geometry nor its extraction gate.
            let unread = unmappedFont
                ? GlyphIndexDecoder.unreadGlyphs(on: reference, in: content.lines.map(\.text).joined(separator: "\n"))
                : 0
            // PDFKit resolves the `/PageLabels` number tree — roman, arabic, prefixed, restarting
            // — so the reader never parses it. A document that declares none labels its pages
            // with their own physical numbers, which is what the writer falls back to anyway.
            let printed = SourceMetadata.pageLabel(page.label)
            return ExtractedPage(content: content, hasUnmappedFont: unmappedFont,
                                 unreadGlyphs: unread,
                                 printedLabel: printed == "\(i + 1)" ? nil : printed,
                                 warnings: warnings)
        }
    }

    /// The schemes an external link may use. Everything else — `javascript:`, `file:`, an
    /// embedded-file or launch action — is dropped and counted as unconverted (#247).
    static let linkSchemes: Set<String> = ["http", "https", "mailto"]
    /// A link's target is written into an attribute of the output document; a URL longer than a
    /// reader would ever follow is not carried.
    static let maximumTargetCharacters = 2_000

    /// One annotation as a link, or nil where it is not a link this converter reproduces.
    static func link(_ annotation: PDFAnnotation, on page: PDFPage) -> PageLink? {
        guard annotation.type == "Link" else { return nil }
        let rect = annotation.bounds
        guard rect.isFinite, rect.width > 0, rect.height > 0 else { return nil }
        if let url = (annotation.action as? PDFActionURL)?.url ?? annotation.url {
            return externalTarget(url).map { PageLink(rect: rect, target: $0) }
        }
        guard let destination = annotation.destination ?? (annotation.action as? PDFActionGoTo)?.destination,
              let document = page.document, let target = destination.page, target.document === document else {
            return nil
        }
        let index = document.index(for: target)
        guard index != NSNotFound, index < document.pageCount else { return nil }
        return PageLink(rect: rect, target: .page(index + 1))
    }

    /// An external target, where its scheme is one this converter reproduces and its text can be
    /// written into an XML attribute as it stands.
    static func externalTarget(_ url: URL) -> LinkTarget? {
        let text = url.absoluteString
        guard let scheme = url.scheme?.lowercased(), linkSchemes.contains(scheme),
              !text.isEmpty, text.count <= maximumTargetCharacters,
              text.unicodeScalars.allSatisfy(isXMLCharacter),
              !text.contains(where: { $0.isWhitespace || $0.isNewline }) else { return nil }
        return .external(text)
    }
}
