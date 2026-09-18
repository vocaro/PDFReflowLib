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
            if case let .image(image) = block.content {
                for asset in [image.assetID] + image.math.map(\.fallbackAssetID) where !identifiers.contains(asset) {
                    throw ValidationError.missingAsset(asset)
                }
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

    /// The Latin typographic ligatures U+FB00–U+FB06.
    static func isLigature(_ character: Character) -> Bool {
        character.unicodeScalars.contains { (0xFB00...0xFB06).contains($0.value) }
    }

    /// Text with the Latin typographic ligatures U+FB00–U+FB06 written as the letters they join
    /// (#189): `ﬀ ﬁ ﬂ ﬃ ﬄ ﬅ ﬆ` become `ff fi fl ffi ffl ſt st`, their Unicode compatibility
    /// decompositions. A ligature is the font's business, not the text's: Wallace's EC fonts give
    /// `ﬀ` and `ﬃ` their own code points, and a reading font without a glyph for them (Charter,
    /// Times New Roman, Avenir Next, the system font) draws them from a fallback font, which a
    /// reader saw as `Diﬀ erent`. The letters also search and speak as words. Nothing else of
    /// Unicode compatibility mapping is applied: superscripts, fractions and full-width forms stay.
    static func spellingOutLigatures<S: StringProtocol>(_ text: S) -> String {
        // By scalar, so a ligature carrying a combining mark (`ﬁ́`) is spelled out too.
        var result = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0xFB00: result += "ff".unicodeScalars
            case 0xFB01: result += "fi".unicodeScalars
            case 0xFB02: result += "fl".unicodeScalars
            case 0xFB03: result += "ffi".unicodeScalars
            case 0xFB04: result += "ffl".unicodeScalars
            case 0xFB05: result += "\u{017F}t".unicodeScalars
            case 0xFB06: result += "st".unicodeScalars
            default: result.append(scalar)
            }
        }
        return String(result)
    }

    /// The same runs, styles and source-page boundaries, with each run's ligatures spelled out.
    func spellingOutLigatures() -> InlineText {
        InlineText(elements: elements.map {
            switch $0 {
            case let .text(value, style): .text(Self.spellingOutLigatures(value), style)
            case let .noteReference(value, style, key): .noteReference(Self.spellingOutLigatures(value), style, key)
            case .sourcePage: $0
            }
        })
    }

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

/// One printed row of a preserved crop that `MathRecognizer` read as mathematics (#190): the
/// exercise label printed before it, if any, and the expression, with the crop of the row as
/// the fallback image for a reading system that does not render MathML.
struct MathExpression: Sendable, Equatable {
    /// The structures the recognizer proves; anything else keeps its crop.
    indirect enum Node: Sendable, Equatable {
        case number(String)
        /// A variable: one letter set in a maths italic font.
        case identifier(String)
        case `operator`(String)
        /// A run of nodes: the whole expression, a bracketed group (brackets included), or a
        /// numerator, denominator or exponent of more than one node.
        case row([Node])
        /// A numerator over a denominator. `display` where the book sets both terms at body size
        /// (a displayed fraction) rather than in the smaller type of a fraction inside a line.
        case fraction(Node, Node, display: Bool = false)
        case superscript(Node, Node)
    }
    /// The printed label (`52)`), which stays text beside the expression.
    var label: String?
    var node: Node
    var fallbackAssetID: String

    /// The expression as linear text, for `alttext`: `27/3`, `(−1)/9 ÷ (−1)/2`, `x^2`.
    var linearText: String { Self.linear(node) }

    private static func linear(_ node: Node) -> String {
        switch node {
        case let .number(value), let .identifier(value): return value
        case let .operator(value): return value
        case let .row(nodes):
            var text = ""
            for (index, child) in nodes.enumerated() {
                // A binary operator or relation stands apart; a sign before its operand does not.
                if case let .operator(symbol) = child, !"()".contains(symbol), index > 0,
                   !isOpening(nodes[index - 1]) {
                    text += " \(symbol) "
                } else {
                    text += linear(child)
                }
            }
            return text
        case let .fraction(numerator, denominator, _):
            return grouped(numerator) + "/" + grouped(denominator)
        case let .superscript(base, script):
            return grouped(base) + "^" + grouped(script)
        }
    }

    /// Whether a node opens an operand position: an operator (other than a closing bracket).
    private static func isOpening(_ node: Node) -> Bool {
        if case let .operator(symbol) = node { return symbol != ")" }
        return false
    }

    /// A fraction's term or a script in linear text: bracketed unless it is one token or already a
    /// bracketed group.
    private static func grouped(_ node: Node) -> String {
        switch node {
        case .number, .identifier: return linear(node)
        case let .row(nodes):
            if case .operator("(")? = nodes.first, case .operator(")")? = nodes.last { return linear(node) }
            return "(" + linear(node) + ")"
        default: return "(" + linear(node) + ")"
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
        /// The crop read as mathematics (#190), one expression per printed row, in reading order.
        /// When present it is written instead of the picture; each expression names its own row's
        /// crop as the fallback image, and `assetID` is the first of them.
        var math: [MathExpression] = []
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
    /// One item of a real list (#194). Items are a flat sequence rather than a tree: the writer
    /// streams blocks and packs spine documents freely, so each item carries its depth and whether
    /// it opens a list element, and the writer opens and closes `<ul>`/`<ol>` as those change.
    struct ListItem: Sendable, Equatable {
        enum Kind: Sendable, Equatable {
            /// A bulleted item: `<ul>`, whose own marker replaces the printed glyph.
            case unordered
            /// A numbered item in a run whose printed numbers ascend by one: `<ol>`, numbered from
            /// the opening item's `ordinal`.
            case ordered
        }
        /// The item's text with its printed marker removed; the list renders its own.
        var text: InlineText
        /// The printed marker (`•`, `3.`), kept for provenance.
        var marker: String
        /// The printed number of an ordered item.
        var ordinal: Int?
        var kind: Kind
        /// Nesting depth, 0 for a top-level list.
        var level = 0
        /// The first item of its list element at this level. A following item that does not open
        /// a list continues the one open at its level.
        var opensList = true
    }
    enum Content: Sendable, Equatable {
        case paragraph(InlineText)
        case heading(id: String, text: InlineText, level: Int = 2)
        /// Text whose line breaks and marker are significant: monospaced code, a coded weather
        /// report, and a list-shaped line the list pass did not verify as a list item (#194).
        case preformatted(InlineText)
        case listItem(ListItem)
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
    /// Where reconstruction read a list item's marker line (#194). Set on every preformatted block
    /// opened by a list marker; `ListBuilder` decides from it and the text whether the block is a
    /// list item. Joins that grow the block keep it.
    var listEvidence: ListEvidence?
    struct ListEvidence: Sendable, Equatable {
        /// The marker line's left edge and type size, in its page's space.
        var edge: CGFloat
        var fontSize: CGFloat
        /// Whether the line's text is a transcription of a scan: recognized by OCR, or an inherited
        /// invisible text layer over the page image.
        var recognized = false
        /// The tagged list item the marker line belongs to, when the PDF tags it.
        var tag: ListTag?
    }

    var text: String {
        switch content {
        case let .paragraph(text), let .heading(_, text, _): text.text
        case let .preformatted(text), let .footnote(text): text.text
        case let .listItem(item): item.text.text
        case let .table(table): (table.caption.map(\.text) + table.rows.flatMap(\.cells).map(\.text.text)).joined(separator: " ")
        case .image, .sourcePage: ""
        }
    }
    var sourcePages: [Int] {
        switch content {
        case let .paragraph(text), let .heading(_, text, _): text.sourcePages
        case let .sourcePage(page): [page]
        case let .preformatted(text), let .footnote(text): text.sourcePages
        case let .listItem(item): item.text.sourcePages
        case let .table(table): table.caption.flatMap(\.sourcePages) + table.rows.flatMap(\.cells).flatMap(\.text.sourcePages)
        case .image: []
        }
    }
    var hasReflowedText: Bool {
        switch content {
        case .paragraph, .heading, .preformatted, .listItem, .footnote, .table: true
        case .image, .sourcePage: false
        }
    }
    var isFootnote: Bool {
        if case .footnote = content { return true }
        return false
    }
}
