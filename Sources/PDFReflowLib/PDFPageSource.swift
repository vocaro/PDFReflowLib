import Foundation
import PDFKit

/// PDFKit retains parsed page state for a document's lifetime. Keep only a small window alive;
/// the converter carries forward value-type text/geometry, never PDFKit pages or selections.
final class PDFPageSource {
    private let url: URL
    private var document: PDFDocument?
    private var window = 0
    private let windowSize = 8
    let pageCount: Int
    /// What the document states about itself (#253).
    let metadata: SourceMetadata

    init(url: URL) throws {
        self.url = url
        guard let document = autoreleasepool(invoking: { PDFDocument(url: url) }) else {
            throw ConversionError.unreadablePDF
        }
        guard !document.isLocked else { throw ConversionError.encryptedPDF }
        guard document.pageCount > 0 else { throw ConversionError.unreadablePDF }
        self.document = document
        pageCount = document.pageCount
        metadata = SourceMetadata(attributes: document.documentAttributes)
    }

    func page(at index: Int) throws -> PDFPage {
        try autoreleasepool {
            if index / windowSize != window {
                document = nil
                document = PDFDocument(url: url)
                window = index / windowSize
            }
            guard let document, !document.isLocked, document.pageCount == pageCount,
                  let page = document.page(at: index) else {
                throw ConversionError.unreadablePDF
            }
            return page
        }
    }

    func releaseCachedPages() {
        document = nil
        window = -1
    }
}
