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
    /// Emphasis italic: the slope the book sets to stress a word, name a title or mark a
    /// foreign term. Written `<em>`.
    static let italic = TextStyle(rawValue: 1 << 1)
    static let superscript = TextStyle(rawValue: 1 << 2)
    static let `subscript` = TextStyle(rawValue: 1 << 3)
    /// A mathematical variable's slope (#142): text set in a maths italic font (`CMMI12`,
    /// `LibertineMathMI`). It is notation, not emphasis, so it is a style of its own and is
    /// written `<i>`, never `<em>`. A run is never both italics: one font sets it.
    static let mathItalic = TextStyle(rawValue: 1 << 4)
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

/// What a preserved image holds, as far as the evidence that made it can say (#187).
///
/// Alternative text has to describe content, and the only thing the converter knows about a crop
/// is which detector seeded it. These are those detectors' claims, not a picture classifier:
/// `artwork` covers every drawn or placed illustration, because a vector chart, a line diagram
/// and a photograph are one kind of evidence to a converter that never decodes the image.
enum PreservedImageKind: String, Sendable, Equatable, Codable {
    /// A displayed formula, a stacked fraction or another mathematical display.
    case equation
    /// A table the layout could not read as text: aligned numeric rows, underlined columns.
    case table
    /// A typeset algorithm listing between its rules.
    case listing
    /// Drawn or placed art: a diagram, a chart, a map, an illustration or a photograph.
    case artwork
    /// Lines that read as words, kept inside a crop that no drawing, table or listing seeded.
    case text
    /// A whole page that does not reflow at all.
    case page
    /// A whole-page picture that accompanies the page's own reflowed text.
    case sourcePage

    /// The alternative text for an image of this kind with no printed caption beside it. Short,
    /// and true of every crop the kind admits: naming a chart, a photograph or a graph would
    /// claim more than the seed evidence establishes. A screen reader announces the image role
    /// itself, so only kinds whose content a reader would expect as text (a table, running text,
    /// a whole page) say that it is kept as an image: its words cannot be read out.
    var alternativeText: String {
        switch self {
        case .equation: "Mathematical expression"
        case .table: "Table kept as an image"
        case .listing: "Algorithm listing"
        case .artwork: "Illustration"
        case .text: "Text kept as an image"
        case .page: "Whole page kept as an image"
        case .sourcePage: "The printed page, for comparison"
        }
    }
}

struct ReflowBlock: Sendable, Equatable {
    /// A preserved image. It has no caption of its own (#187): a caption the source prints stays
    /// the block the source set beside the figure, which is where `captionedImages` checks it and
    /// where a sighted reader already reads it, and the converter has no caption to add. What it
    /// carries instead is alternative text naming the content and provenance for `title`.
    struct Image: Sendable, Equatable {
        var assetID: String
        var alternativeText: String
        /// Where the image came from, for the reader that wants it: `title`, never `alt` (#187).
        var provenance: String = ""
    }
    /// A text table: rows of cells in column order, each cell spanning one or more columns
    /// (a section row is one cell spanning them all). Header rows precede the body. Cell text
    /// keeps inline styles and source-page boundaries.
    struct Table: Sendable, Equatable {
        struct Cell: Sendable, Equatable {
            var text: InlineText
            var span = 1
            /// A body cell that names its row (`th scope="row"`); header rows' cells are headers
            /// through `Row.header`.
            var header = false
        }
        struct Row: Sendable, Equatable {
            var cells: [Cell]
            var header: Bool
        }
        var columns: Int
        var rows: [Row]
        /// Caption paragraphs in reading order (the title, then its description); empty when the
        /// table has no caption of its own.
        var caption: [InlineText] = []
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
    /// The tier of an outline section label a heading was read from (0 Roman, 1 lettered, 2
    /// numbered; `LayoutReconstructor.outlineSectionLabels`), ranked by tier beneath the size scale.
    var outlineDepth: Int?

    var text: String {
        switch content {
        case let .paragraph(text), let .heading(_, text, _): text.text
        case let .preformatted(text), let .footnote(text): text.text
        case let .table(table): (table.caption.map(\.text) + table.rows.flatMap(\.cells).map(\.text.text)).joined(separator: " ")
        case .image, .sourcePage: ""
        }
    }
    var sourcePages: [Int] {
        switch content {
        case let .paragraph(text), let .heading(_, text, _): text.sourcePages
        case let .sourcePage(page): [page]
        case let .preformatted(text), let .footnote(text): text.sourcePages
        case let .table(table): table.caption.flatMap(\.sourcePages) + table.rows.flatMap(\.cells).flatMap(\.text.sourcePages)
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
