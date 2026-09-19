import Foundation

/// Packs serialized blocks into spine documents near a byte target. A document closes when its
/// body reaches the target, except that a short trailing run of headings (with any standalone
/// page markers between them) travels into the next document, so a heading never ends one
/// document while its content begins the next. Oversized single blocks are never split. A
/// validated chapter start always begins a new document. Navigation entries are kept as
/// structured values and rendered once every document has its final name.
struct SpinePacker {
    /// A finished spine document, ready to be written.
    struct Document: Equatable {
        var name: String
        var body: String
    }

    /// A navigation entry: the document it points into, the fragment, and the escaped text.
    struct Entry: Equatable {
        var file: String
        var fragment: String
        var text: String

        var markup: String { "<li><a href=\"\(file)#\(fragment)\">\(text)</a></li>" }
    }

    /// A serialized block: its markup, the source pages it carries (for the page list), and its
    /// heading entry, if it is a heading.
    struct Piece {
        var markup: String
        var sourcePages: [Int]
        var heading: (id: String, text: String)?
    }

    let bodyTargetBytes: Int
    let chapterStartPages: Set<Int>
    private(set) var documentNames: [String] = []
    private(set) var toc: [Entry] = []
    private(set) var pages: [Entry] = []
    private var body = ""
    private var bodyBytes = 0
    private var pendingPage: (number: Int, markup: String)?
    /// Headings at the end of the body, with any standalone page markers between them, and the
    /// navigation entries they added. A size split carries them into the next document.
    private var trailingHeadings: (bodyBytes: Int, toc: Int, pages: Int)?

    init(bodyTargetBytes: Int, chapterStartPages: Set<Int>) {
        self.bodyTargetBytes = bodyTargetBytes
        self.chapterStartPages = chapterStartPages
    }

    var nextDocumentName: String { "chapter-\(documentNames.count + 1).xhtml" }

    /// Only a short heading run is kept with its content; a long run of headings packs normally.
    private func keepsTrailingHeadings() -> Bool {
        guard let trailing = trailingHeadings else { return false }
        return bodyBytes - trailing.bodyBytes <= bodyTargetBytes / 10
    }

    private mutating func finishDocument(carryingTrailingHeadings: Bool = false) -> Document? {
        guard !body.isEmpty else { return nil }
        let name = nextDocumentName
        var carried = ""
        var carriedEntries: (toc: [Entry], pages: [Entry]) = ([], [])
        if carryingTrailingHeadings, keepsTrailingHeadings(), let trailing = trailingHeadings, trailing.bodyBytes > 0 {
            let utf8 = Array(body.utf8)
            carried = String(decoding: utf8[trailing.bodyBytes...], as: UTF8.self)
            body = String(decoding: utf8[..<trailing.bodyBytes], as: UTF8.self)
            carriedEntries = (Array(toc[trailing.toc...]), Array(pages[trailing.pages...]))
            toc.removeSubrange(trailing.toc...)
            pages.removeSubrange(trailing.pages...)
        }
        let document = Document(name: name, body: body)
        documentNames.append(name)
        body = carried; bodyBytes = carried.utf8.count
        trailingHeadings = carried.isEmpty ? nil : (0, toc.count, pages.count)
        let next = nextDocumentName
        toc += carriedEntries.toc.map { var entry = $0; entry.file = next; return entry }
        pages += carriedEntries.pages.map { var entry = $0; entry.file = next; return entry }
        return document
    }

    /// Adds markup to the body, closing documents as the target requires. `budgetRemaining` is
    /// the uncompressed byte budget still available; a block larger than it is refused.
    private mutating func append(_ markup: String, sourcePages: [Int], heading: (id: String, text: String)? = nil,
                                 standaloneMarker: Bool = false, budgetRemaining: Int64) throws -> [Document] {
        try Task.checkCancellation()
        let size = markup.utf8.count
        guard Int64(size) <= budgetRemaining else { throw ConversionError.resourceLimit("EPUB text size") }
        var finished: [Document] = []
        // A body holding only headings stays open for the content they introduce.
        if bodyBytes > 0, bodyBytes + size > bodyTargetBytes,
           !(keepsTrailingHeadings() && trailingHeadings?.bodyBytes == 0),
           let document = finishDocument(carryingTrailingHeadings: true) {
            finished.append(document)
        }
        if heading != nil, trailingHeadings == nil {
            trailingHeadings = (bodyBytes, toc.count, pages.count)
        } else if heading == nil, !standaloneMarker {
            trailingHeadings = nil
        }
        let name = nextDocumentName
        for number in sourcePages {
            pages.append(Entry(file: name, fragment: "page-\(number)", text: "\(number)"))
        }
        if let heading {
            toc.append(Entry(file: name, fragment: xml(heading.id), text: xml(heading.text)))
        }
        body += markup; bodyBytes += size
        // Never split an atomic block merely to satisfy the target. Oversized blocks are
        // isolated, retain their styles and anchors, and still obey the total budget. A heading
        // waits for its following content before the document is closed.
        if bodyBytes >= bodyTargetBytes, !keepsTrailingHeadings(), let document = finishDocument() {
            finished.append(document)
        }
        return finished
    }

    /// A source-page boundary. Consecutive boundaries describe empty source pages; only the last
    /// needs to travel with the following content, so earlier ones pack normally. A validated
    /// chapter start closes the current document first.
    mutating func add(sourcePage number: Int, markup: String, budgetRemaining: Int64) throws -> [Document] {
        var finished: [Document] = []
        if let pendingPage {
            finished += try append(pendingPage.markup, sourcePages: [pendingPage.number], standaloneMarker: true,
                                   budgetRemaining: budgetRemaining)
        }
        if chapterStartPages.contains(number) {
            trailingHeadings = nil
            if let document = finishDocument() { finished.append(document) }
        }
        pendingPage = (number, markup)
        return finished
    }

    /// A content block. A pending page boundary is prepended so it stays with this content.
    mutating func add(_ piece: Piece, budgetRemaining: Int64) throws -> [Document] {
        let finished = try append((pendingPage?.markup ?? "") + piece.markup,
                                  sourcePages: pendingPage.map { [$0.number] + piece.sourcePages } ?? piece.sourcePages,
                                  heading: piece.heading, budgetRemaining: budgetRemaining)
        pendingPage = nil
        return finished
    }

    /// Flushes a trailing page boundary and the open body.
    mutating func finish(budgetRemaining: Int64) throws -> [Document] {
        var finished: [Document] = []
        if let pendingPage {
            finished += try append(pendingPage.markup, sourcePages: [pendingPage.number], standaloneMarker: true,
                                   budgetRemaining: budgetRemaining)
            self.pendingPage = nil
        }
        if let document = finishDocument() { finished.append(document) }
        return finished
    }
}
