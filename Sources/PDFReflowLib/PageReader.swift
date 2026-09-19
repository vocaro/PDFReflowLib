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
            if !page.annotations.isEmpty {
                content.preservePageReference = true
                warnings.append(.annotationsNotConverted)
            }
            // Structural font evidence is read here; the text judgment follows outside the pool.
            let unmappedFont = !content.lines.isEmpty && !requiresPageImage && TextEncodingCheck.hasUnmappedFont(reference)
            return ExtractedPage(content: content, placedImages: graphics.images,
                                 hasUnmappedFont: unmappedFont, warnings: warnings)
        }
    }
}
