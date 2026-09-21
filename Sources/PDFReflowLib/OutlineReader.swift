import Foundation
import PDFKit

/// The table of contents an author stated, read as navigation and nothing else (#249).
///
/// An outline entry is not a heading in the text, and manufacturing one would put words on the
/// page the page does not print — `ChapterBoundaryReader` keeps that rule, and so does this. But
/// navigation is a separate structure that EPUB models separately, and a hierarchical contents
/// with explicit destinations is better navigation than a flat list of detected headings.
///
/// Not every outline is a contents. Four of the twelve corpus outlines are machine artifacts:
/// the FAA handbook's is a tagged-structure dump eleven levels deep with 7,689 entries for 522
/// pages, the CIA report's is 313 entries all labeled `Figure`, the Warren report's is a single
/// entry labeled `Test`, and the copper summary's is one entry. `isNavigation` is the gate that
/// tells those from the eight that are real, on shape alone; a rejected outline leaves the
/// detected headings in place, which is what every document had before.
enum OutlineReader {
    /// One entry, with the entries it introduces. An entry that resolves to no page and
    /// introduces none is dropped, so every entry here names something.
    typealias Entry = OutlineEntry

    /// The whole walk's budget, as `ChapterBoundaryReader`'s root walk has always had.
    static let maximumEntries = 10_000
    /// A printed contents rarely passes three levels; an outline deeper than this is a structure
    /// tree written out as bookmarks.
    static let maximumDepth = 4
    static let maximumTitleCharacters = 512
    /// No printed contents lists three entries for every page of the book.
    static let maximumEntriesPerPage = 3

    /// The shape of one outline, which is all `isNavigation` judges it on.
    struct Shape: Equatable {
        var entries = 0
        var distinctTitles = 0
        var depth = 0
    }

    /// The document's outline as navigation, or `[]` where it states none or states one that is
    /// not a contents.
    static func read(_ url: URL, password: ConversionOptions.Password? = nil) throws -> [Entry] {
        try autoreleasepool {
            try Task.checkCancellation()
            guard let document = SourceDocument.open(url, password: password), !document.isLocked,
                  let root = document.outlineRoot, root.numberOfChildren <= maximumEntries else { return [] }
            var titles: [String] = []
            var depth = 0
            let entries = try children(of: root, level: 0, document: document, titles: &titles, depth: &depth)
            let shape = Shape(entries: titles.count, distinctTitles: Set(titles).count, depth: depth)
            return isNavigation(shape, pageCount: document.pageCount) ? entries : []
        }
    }

    /// Whether an outline of this shape reads as a table of contents rather than as a machine's
    /// index of the file. Judged on shape alone: nothing here reads the pages.
    static func isNavigation(_ shape: Shape, pageCount: Int) -> Bool {
        shape.entries >= 2                                          // one entry is not navigation
            && shape.entries <= maximumEntries
            && shape.entries <= pageCount * maximumEntriesPerPage   // not an entry for every page
            && shape.depth < maximumDepth                           // not a structure tree
            && shape.distinctTitles * 2 > shape.entries             // not one title repeated
    }

    /// The entries under `item`, with the titles seen and the depth reached. An entry that
    /// resolves to no page and introduces nothing is dropped; one that resolves to no page but
    /// introduces entries is kept, to group them.
    private static func children(of item: PDFOutline, level: Int, document: PDFDocument,
                                 titles: inout [String], depth: inout Int) throws -> [Entry] {
        guard item.numberOfChildren > 0 else { return [] }
        depth = max(depth, level)
        // Past the depth bound the outline is already rejected; stop rather than walk a tree
        // whose only purpose is to fail the gate.
        guard level < maximumDepth else { return [] }
        var entries: [Entry] = []
        for index in 0..<item.numberOfChildren {
            try Task.checkCancellation()
            guard titles.count < maximumEntries, let child = item.child(at: index) else { break }
            guard let title = title(child.label) else { continue }
            titles.append(title)
            let nested = try children(of: child, level: level + 1, document: document,
                                      titles: &titles, depth: &depth)
            let page = page(of: child, in: document)
            guard page != nil || !nested.isEmpty else { continue }
            entries.append(Entry(title: title, page: page, children: nested))
        }
        return entries
    }

    /// The one-based physical page an entry aims at, or nil. A remote or non-`GoTo` action
    /// resolves to nothing, as it always has.
    private static func page(of item: PDFOutline, in document: PDFDocument) -> Int? {
        guard item.action == nil || item.action is PDFActionGoTo,
              let destination = item.destination ?? (item.action as? PDFActionGoTo)?.destination,
              let page = destination.page, page.document === document else { return nil }
        let index = document.index(for: page)
        guard index != NSNotFound, index < document.pageCount else { return nil }
        return index + 1
    }

    /// One entry's title: XML-safe, whitespace collapsed (the USCIS guide wraps one over two
    /// lines), bounded. Nil where the entry states no title.
    static func title(_ label: String?) -> String? {
        guard let label, label.count <= maximumTitleCharacters * 4 else { return nil }
        let collapsed = String(String.UnicodeScalarView(label.unicodeScalars.filter(isXMLCharacter)))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !collapsed.isEmpty, collapsed.count <= maximumTitleCharacters,
              collapsed.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
        return collapsed
    }
}
