import Foundation

/// The output-independent logical document. Assets are file-backed for the conversion's lifetime.
/// This is an internal value model, not a public interchange schema.
struct ReflowDocument: Sendable, Equatable {
    struct Metadata: Sendable, Equatable {
        var title: String
        var language: String
        var author: String?
    }

    struct Asset: Sendable, Equatable {
        enum Format: Sendable {
            case png, jpeg
            var mediaType: String { switch self { case .png: "image/png"; case .jpeg: "image/jpeg" } }
            var fileExtension: String { switch self { case .png: "png"; case .jpeg: "jpg" } }
        }
        var id: String
        var fileURL: URL
        var format: Format = .png
    }

    var metadata: Metadata
    var blocks: [ReflowBlock]
    var assets: [Asset]
    /// Validated chapter starts, always represented by standalone source-page blocks.
    var chapterStartPages: Set<Int> = []

    enum ValidationError: Error, Equatable {
        case emptyDocument, duplicateAsset(String), missingAsset(String), invalidHeadingLevel(Int), invalidChapterBoundary(Int)
    }

    func validate() throws {
        guard !blocks.isEmpty else { throw ValidationError.emptyDocument }
        var identifiers: Set<String> = []
        for asset in assets {
            guard identifiers.insert(asset.id).inserted else { throw ValidationError.duplicateAsset(asset.id) }
        }
        for block in blocks {
            if case let .heading(_, _, level) = block.content, !(1...6).contains(level) {
                throw ValidationError.invalidHeadingLevel(level)
            }
            if case let .image(image) = block.content, !identifiers.contains(image.assetID) {
                throw ValidationError.missingAsset(image.assetID)
            }
        }
        for page in chapterStartPages {
            guard blocks.contains(where: { $0.content == .sourcePage(page) }) else {
                throw ValidationError.invalidChapterBoundary(page)
            }
        }
    }
}

struct TextStyle: OptionSet, Sendable, Equatable, Codable {
    let rawValue: UInt8
    static let bold = TextStyle(rawValue: 1 << 0)
    static let italic = TextStyle(rawValue: 1 << 1)
    static let superscript = TextStyle(rawValue: 1 << 2)
    static let `subscript` = TextStyle(rawValue: 1 << 3)
}

/// A note's identity for reference links: its printed number within the scope that makes
/// the number unique. Chapter endnotes (`NOTES TO CHAPTER 3`, note 4) are scoped by chapter;
/// page-bottom footnotes by their physical page. Equal numbers in different scopes are
/// different notes, so a key never joins notes across chapters.
struct NoteKey: Hashable, Sendable, Codable {
    enum Scope: Hashable, Sendable, Codable {
        case chapter(Int)
        case page(Int)
    }
    var number: Int
    var scope: Scope

    /// A content-derived fragment (`c3-4`, `p60-2`) that stays stable however a writer splits
    /// the document into files.
    var identifier: String {
        switch scope {
        case let .chapter(chapter): "c\(chapter)-\(number)"
        case let .page(page): "p\(page)-\(number)"
        }
    }
}

struct InlineText: Sendable, Equatable, Codable {
    enum Element: Sendable, Equatable, Codable {
        case text(String, TextStyle)
        /// A source boundary can occur inside a paragraph or even inside a repaired word.
        case sourcePage(Int)
        /// A raised reference marker (its visible digits, with the run's other styles)
        /// resolved to the note it cites. Reconstruction links markers last, after every
        /// join; unresolved markers stay superscript text.
        case noteReference(String, TextStyle, NoteKey)
    }
    var elements: [Element] = []

    init(_ text: String = "", style: TextStyle = []) {
        if !text.isEmpty { elements = [.text(text, style)] }
    }
    init(elements: [Element]) { self.elements = elements }

    var text: String {
        elements.map {
            switch $0 {
            case let .text(value, _), let .noteReference(value, _, _): value
            case .sourcePage: ""
            }
        }.joined()
    }
    var sourcePages: [Int] {
        elements.compactMap { if case let .sourcePage(page) = $0 { page } else { nil } }
    }

    mutating func append(_ other: InlineText) { elements += other.elements }

    mutating func removeLastCharacter() {
        for index in elements.indices.reversed() {
            if case let .text(value, style) = elements[index], !value.isEmpty {
                let shortened = String(value.dropLast())
                if shortened.isEmpty { elements.remove(at: index) }
                else { elements[index] = .text(shortened, style) }
                return
            }
        }
    }

    func trimmingCharacters(in set: CharacterSet) -> InlineText {
        var result = self
        func matches(_ character: Character) -> Bool { character.unicodeScalars.allSatisfy(set.contains) }
        while let first = result.elements.first, case let .text(value, style) = first {
            let trimmed = String(value.drop(while: matches))
            if trimmed.isEmpty { result.elements.removeFirst() }
            else { result.elements[0] = .text(trimmed, style); break }
        }
        while let last = result.elements.last, case let .text(value, style) = last {
            let trimmed = String(value.reversed().drop(while: matches).reversed())
            if trimmed.isEmpty { result.elements.removeLast() }
            else { result.elements[result.elements.count - 1] = .text(trimmed, style); break }
        }
        return result
    }
}

struct ReflowBlock: Sendable, Equatable {
    struct Image: Sendable, Equatable {
        var assetID: String
        var alternativeText: String
        var caption: String
    }
    /// A text table: rows of cells in column order, each cell spanning one or more columns
    /// (a section row is one cell spanning them all). Header rows precede the body. Cell text
    /// keeps inline styles and source-page boundaries.
    struct Table: Sendable, Equatable {
        struct Cell: Sendable, Equatable {
            var text: InlineText
            var span = 1
        }
        struct Row: Sendable, Equatable {
            var cells: [Cell]
            var header: Bool
        }
        var columns: Int
        var rows: [Row]
    }
    enum Content: Sendable, Equatable {
        case paragraph(InlineText)
        case heading(id: String, text: InlineText, level: Int = 2)
        case preformatted(InlineText)
        /// A page-bottom note; its own raised marker, when present, opens the text. Body
        /// prose is never placed in one, and a note is not linked to its reference.
        case footnote(InlineText)
        case image(Image)
        case table(Table)
        case sourcePage(Int)
    }
    var content: Content
    /// Validated source paragraph identity, used to avoid heuristic joins across tag boundaries.
    var structureGroup: Int?
    /// The note this block opens: a chapter endnote paragraph or a page-bottom footnote with
    /// its printed number. A note's further paragraphs and marker-less continuations carry none.
    var note: NoteKey?
    /// Physical PDF page where this block begins; inline markers record later page boundaries.
    var page: Int
    /// Font size of a heading, ranked into levels document-wide once every page is reconstructed.
    var headingSize: CGFloat?
    /// The validated role of a block built from a structure group: zero for a paragraph, 1...6 for
    /// a heading, which it keeps unless the document ranks a larger heading no higher (see
    /// `LayoutReconstructor.rankHeadingLevels`). Nil where no group vouches for the block.
    var taggedLevel: Int?

    var text: String {
        switch content {
        case let .paragraph(text), let .heading(_, text, _): text.text
        case let .preformatted(text), let .footnote(text): text.text
        case let .table(table): table.rows.flatMap(\.cells).map(\.text.text).joined(separator: " ")
        case .image, .sourcePage: ""
        }
    }
    var sourcePages: [Int] {
        switch content {
        case let .paragraph(text), let .heading(_, text, _): text.sourcePages
        case let .sourcePage(page): [page]
        case let .preformatted(text), let .footnote(text): text.sourcePages
        case let .table(table): table.rows.flatMap(\.cells).flatMap(\.text.sourcePages)
        case .image: []
        }
    }
    var hasReflowedText: Bool {
        switch content {
        case .paragraph, .heading, .preformatted, .footnote, .table: true
        case .image, .sourcePage: false
        }
    }
    var isFootnote: Bool {
        if case .footnote = content { return true }
        return false
    }
}
