import Foundation
import PDFKit

/// One page as the PDFKit and Core Graphics readers deliver it, before any judgment about
/// whether its text can be trusted. Everything here is a value; no framework object survives
/// the reader's autorelease pool.
struct ExtractedPage: Equatable, Sendable {
    var content: PageContent
    /// Placed raster image XObjects, which the drawn-text ink test sets aside (#176).
    var placedImages: [CGRect]
    /// A simple font with an index-style `Differences` encoding and no `ToUnicode` map is
    /// present (#38). Structural evidence only; `PageDiagnosis` adds the word statistics.
    var hasUnmappedFont: Bool
    /// Glyphs of such a font whose decoded characters the extracted text does not carry, because
    /// their line was left as PDFKit read it (`GlyphIndexDecoder.unreadGlyphs`). Zero on every
    /// page without an index-glyph font.
    var unreadGlyphs: Int
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
                warnings.append(.structureFallback)
            }
            content.requiresPageImage = requiresPageImage
            content.hasSyntheticTextStyle = syntheticStyle
            if graphics.unsupported {
                warnings.append(.unsupportedGraphics)
            }
            let annotated = !page.annotations.isEmpty
            if annotated {
                content.preservePageReference = true
                warnings.append(.annotationsNotConverted)
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
            return ExtractedPage(content: content, placedImages: graphics.images,
                                 hasUnmappedFont: unmappedFont, unreadGlyphs: unread, warnings: warnings)
        }
    }
}
