import Foundation
import PDFKit

/// Opening the source document. Every path that opens it again — the page window here, the
/// outline read and the structure tree — goes through one of these, so a caller's password is
/// applied at every open and nowhere else (#252).
enum SourceDocument {
    /// The document at `url`, unlocked with `password` where it is locked and one is supplied.
    /// Nil means the file is not a readable PDF; a document that is still locked is returned as
    /// it is, so the caller can tell a wrong password from an unreadable file.
    static func open(_ url: URL, password: ConversionOptions.Password?) -> PDFDocument? {
        guard let document = PDFDocument(url: url) else { return nil }
        if document.isLocked, let password { _ = document.unlock(withPassword: password.value) }
        return document
    }

    /// The same for Core Graphics, which the structure tree reads. Nil where the file is not a
    /// readable PDF or stays locked; an encrypted document CGPDFDocument opened is unusable
    /// until it is unlocked.
    static func openCore(_ url: URL, password: ConversionOptions.Password?) -> CGPDFDocument? {
        guard let document = CGPDFDocument(url as CFURL) else { return nil }
        if !document.isUnlocked, let password { _ = document.unlockWithPassword(password.value) }
        return document.isUnlocked ? document : nil
    }
}

/// PDFKit retains parsed page state for a document's lifetime. Keep only a small window alive;
/// the converter carries forward value-type text/geometry, never PDFKit pages or selections.
final class PDFPageSource {
    private let url: URL
    private let password: ConversionOptions.Password?
    private var document: PDFDocument?
    private var window = 0
    private let windowSize = 8
    let pageCount: Int
    /// What the document states about itself (#253).
    let metadata: SourceMetadata

    init(url: URL, password: ConversionOptions.Password? = nil) throws {
        self.url = url
        self.password = password
        guard let document = autoreleasepool(invoking: { SourceDocument.open(url, password: password) }) else {
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
                document = SourceDocument.open(url, password: password)
                window = index / windowSize
            }
            guard let document, !document.isLocked, document.pageCount == pageCount,
                  let page = document.page(at: index) else {
                throw ConversionError.unreadablePDF
            }
            return page
        }
    }

    /// Decode only one mask in a short-lived Core Graphics document (#182). Returning only
    /// its value rectangle releases the decoder's retained samples before the next image.
    func imageAlphaBounds(page index: Int, image imageIndex: Int) -> CGRect? {
        autoreleasepool {
            guard let document = SourceDocument.openCore(url, password: password),
                  let page = document.page(at: index + 1) else { return nil }
            let images = EmbeddedImageReader.placements(page)
            guard images.indices.contains(imageIndex),
                  let dictionary = CGPDFStreamGetDictionary(images[imageIndex].stream) else { return nil }
            return ImageAlphaBounds.read(dictionary)
        }
    }

    func releaseCachedPages() {
        document = nil
        window = -1
    }
}
