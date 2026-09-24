import Foundation

/// One entry of the table of contents a document states for itself, which `OutlineReader` reads
/// and the writer renders as navigation (#249). The model owns the type so that it carries no
/// dependency on how the outline was read.
struct OutlineEntry: Sendable, Equatable {
    var title: String
    /// One-based physical page. Nil where the entry resolves to no page of this document and
    /// only groups the entries under it.
    var page: Int?
    var children: [OutlineEntry] = []
}

/// The output-independent logical document. Assets are file-backed for the conversion's lifetime.
/// This is an internal value model, not a public interchange schema.
struct ReflowDocument: Sendable, Equatable {
    struct Metadata: Sendable, Equatable {
        var title: String
        var language: String
        var author: String?
        /// `dc:description`: the source's `/Subject`, or a client's own summary.
        var summary: String?
        /// One `dc:subject` each: the source's `/Keywords`.
        var keywords: [String] = []
        /// `dcterms:created`: the source's `/CreationDate`.
        var created: Date?
        /// The page number the source prints, by physical page, where the two differ (#248).
        /// A page absent here is labeled with its physical number.
        var pageLabels: [Int: String] = [:]
        /// The author's own table of contents, where the document states a usable one (#249).
        /// Empty leaves navigation to the headings the layout pass detected.
        var outline: [OutlineEntry] = []
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
        case emptyDocument, duplicateAsset(String), missingAsset(String), invalidHeadingLevel(Int),
             invalidChapterBoundary(Int), invalidTable
    }

    /// The document as the stream a producer emits, in production order.
    var parts: [ReflowPart] {
        [.start(metadata, chapterStartPages: chapterStartPages)]
            + assets.map { .asset($0) } + blocks.map { .block($0) }
    }

    /// Model validation over a whole document. A streamed document is validated part by part by
    /// `Validation`, which this runs over the same stream so the two cannot disagree.
    func validate() throws {
        var validation = Validation()
        for part in parts { try validation.accept(part) }
        try validation.finish()
    }

    /// Model validation of one part at a time, for a consumer that never holds the document.
    /// Per-part checks reject a block as it arrives; the checks that need the whole document —
    /// that it has blocks at all, and that every chapter boundary reached a standalone page
    /// marker — run in `finish`.
    struct Validation {
        private var identifiers: Set<String> = []
        private var unmatchedChapterStarts: Set<Int> = []
        private var blocks = 0

        init() {}

        mutating func accept(_ part: ReflowPart) throws {
            switch part {
            case let .start(_, chapterStartPages):
                unmatchedChapterStarts = chapterStartPages
            case let .asset(asset):
                guard identifiers.insert(asset.id).inserted else { throw ValidationError.duplicateAsset(asset.id) }
            case let .block(block):
                blocks += 1
                switch block.content {
                case let .heading(_, _, level):
                    guard (1...6).contains(level) else { throw ValidationError.invalidHeadingLevel(level) }
                case let .image(image):
                    guard identifiers.contains(image.assetID) else { throw ValidationError.missingAsset(image.assetID) }
                    for expression in image.math where !identifiers.contains(expression.fallbackAssetID) {
                        throw ValidationError.missingAsset(expression.fallbackAssetID)
                    }
                case let .sourcePage(number):
                    unmatchedChapterStarts.remove(number)
                case let .table(table):
                    // A table is a rectangle of cells or it is not a table: every row covers the
                    // same number of columns, and the header rows are rows it has (#210). A
                    // ragged table would serialize as markup no reading system can align.
                    let widths = table.rows.map { $0.reduce(0) { $0 + max(0, $1.columns) } }
                    guard let width = widths.first, width >= 2, widths.allSatisfy({ $0 == width }),
                          table.rows.allSatisfy({ $0.allSatisfy { $0.columns >= 1 } }),
                          (0...table.rows.count).contains(table.headerRows)
                    else { throw ValidationError.invalidTable }
                case .paragraph, .quotation, .aside, .preformatted, .listItem:
                    break
                }
            }
        }

        func finish() throws {
            guard blocks > 0 else { throw ValidationError.emptyDocument }
            // Lowest page first, so the reported boundary does not depend on set iteration order.
            if let page = unmatchedChapterStarts.min() { throw ValidationError.invalidChapterBoundary(page) }
        }
    }

    /// Rebuilds a whole document from its parts, for a caller that can hold the model.
    struct Collector {
        private(set) var document = ReflowDocument(metadata: .init(title: "", language: ""), blocks: [], assets: [])

        init() {}

        mutating func accept(_ part: ReflowPart) {
            switch part {
            case let .start(metadata, chapterStartPages):
                document.metadata = metadata
                document.chapterStartPages = chapterStartPages
            case let .asset(asset): document.assets.append(asset)
            case let .block(block): document.blocks.append(block)
            }
        }
    }
}

/// One piece of a logical document as its producer finishes it: the document-wide facts first,
/// then assets and blocks in production order. An asset always precedes the block that
/// references it, and a block is final when it is emitted — nothing later amends it.
enum ReflowPart: Sendable {
    case start(ReflowDocument.Metadata, chapterStartPages: Set<Int>)
    case asset(ReflowDocument.Asset)
    case block(ReflowBlock)
}

struct TextStyle: OptionSet, Sendable, Equatable, Codable {
    let rawValue: UInt8
    static let bold = TextStyle(rawValue: 1 << 0)
    static let italic = TextStyle(rawValue: 1 << 1)
    static let superscript = TextStyle(rawValue: 1 << 2)
    static let `subscript` = TextStyle(rawValue: 1 << 3)
    /// A rule the page paints under a run of words, which is emphasis the font does not carry
    /// (#235). Not a link: the writer emits `<u>`, which states appearance without claiming one.
    static let underline = TextStyle(rawValue: 1 << 4)
}

/// Where a link the source draws points (#247).
///
/// A target is a payload rather than a flag, so it cannot join `TextStyle`. External targets are
/// already checked against the scheme allowlist when one is made; an internal target is a
/// one-based physical page of this document, which only the writer can turn into a file name.
enum LinkTarget: Sendable, Equatable, Codable {
    case external(String)
    case page(Int)
}

struct InlineText: Sendable, Equatable, Codable {
    enum Element: Sendable, Equatable, Codable {
        case text(String, TextStyle)
        /// A run the source links, with the text it covers (#247). A link never nests another:
        /// the reader marks a run once, from one annotation.
        case link(LinkTarget, InlineText)
        /// A source boundary can occur inside a paragraph or even inside a repaired word.
        case sourcePage(Int)
    }
    var elements: [Element] = []
    /// A source-font census identifies this trailing literal hyphen as a discretionary break
    /// for exactly this joined word. Kept separate from text and style; known compounds still
    /// take priority when the actual next line arrives. Optional for older encoded inline text.
    var sourceDiscretionaryWord: String?

    init(_ text: String = "", style: TextStyle = []) {
        if !text.isEmpty { elements = [.text(text, style)] }
    }
    init(elements: [Element]) { self.elements = elements }

    var text: String {
        elements.map { element in
            switch element {
            case let .text(value, _): value
            case let .link(_, text): text.text
            case .sourcePage: ""
            }
        }.joined()
    }
    var sourcePages: [Int] {
        elements.flatMap { element -> [Int] in
            switch element {
            case let .sourcePage(page): [page]
            case let .link(_, text): text.sourcePages
            case .text: []
            }
        }
    }
    /// Every link this text carries, in order, with the text each covers.
    var links: [(target: LinkTarget, text: String)] {
        elements.compactMap { if case let .link(target, text) = $0 { (target, text.text) } else { nil } }
    }

    mutating func append(_ other: InlineText) {
        elements += other.elements
        if !other.text.isEmpty { sourceDiscretionaryWord = other.sourceDiscretionaryWord }
    }

    /// Replaces the last character in place, keeping the run's style. The line-end hyphen repair
    /// uses it to put back the hyphen a book's font drew but encoded as another character (#233).
    mutating func replaceLastCharacter(with character: Character) {
        sourceDiscretionaryWord = nil
        for index in elements.indices.reversed() {
            switch elements[index] {
            case let .text(value, style) where !value.isEmpty:
                elements[index] = .text(String(value.dropLast()) + String(character), style)
                return
            // A word a page breaks can end inside a link, so the repair reaches into one (#247).
            case let .link(target, text) where !text.text.isEmpty:
                var inner = text
                inner.replaceLastCharacter(with: character)
                elements[index] = .link(target, inner)
                return
            default: continue
            }
        }
    }

    mutating func removeLastCharacter() {
        sourceDiscretionaryWord = nil
        for index in elements.indices.reversed() {
            switch elements[index] {
            case let .text(value, style) where !value.isEmpty:
                let shortened = String(value.dropLast())
                if shortened.isEmpty { elements.remove(at: index) }
                else { elements[index] = .text(shortened, style) }
                return
            case let .link(target, text) where !text.text.isEmpty:
                var inner = text
                inner.removeLastCharacter()
                if inner.elements.isEmpty { elements.remove(at: index) }
                else { elements[index] = .link(target, inner) }
                return
            default: continue
            }
        }
    }

    /// Joins runs of one link that a line break separated (#247).
    ///
    /// A sentence one link covers over two printed lines arrives as two link elements with the
    /// space the join inserted between them. They are one link in the source and one anchor in
    /// the output, so they become one element here rather than two anchors a reader's cursor
    /// falls out of mid-sentence. Only a run of whitespace may lie between them; anything else
    /// is text the link does not cover.
    mutating func mergeAdjacentLinks() {
        var merged: [Element] = []
        for element in elements {
            guard case let .link(target, text) = element else { merged.append(element); continue }
            // The text runs between this link and the last one, which must all be whitespace.
            var between: [Element] = []
            var index = merged.count
            while index > 0, case let .text(value, _) = merged[index - 1],
                  value.allSatisfy(\.isWhitespace) {
                index -= 1
                between.insert(merged[index], at: 0)
            }
            guard index > 0, case let .link(previous, before) = merged[index - 1], previous == target else {
                merged.append(element)
                continue
            }
            var joined = before
            joined.elements += between + text.elements
            merged.removeSubrange((index - 1)...)
            merged.append(.link(target, joined))
        }
        elements = merged
    }

    func trimmingCharacters(in set: CharacterSet) -> InlineText {
        var result = self
        func matches(_ character: Character) -> Bool { character.unicodeScalars.allSatisfy(set.contains) }
        while let first = result.elements.first {
            switch first {
            case let .text(value, style):
                let trimmed = String(value.drop(while: matches))
                if trimmed.isEmpty { result.elements.removeFirst(); continue }
                result.elements[0] = .text(trimmed, style)
            case let .link(target, text):
                let trimmed = text.trimmingCharacters(in: set)
                if trimmed.elements.isEmpty { result.elements.removeFirst(); continue }
                result.elements[0] = .link(target, trimmed)
            case .sourcePage: break
            }
            break
        }
        while let last = result.elements.last {
            let index = result.elements.count - 1
            switch last {
            case let .text(value, style):
                let trimmed = String(value.reversed().drop(while: matches).reversed())
                if trimmed.isEmpty { result.elements.removeLast(); continue }
                result.elements[index] = .text(trimmed, style)
            case let .link(target, text):
                let trimmed = text.trimmingCharacters(in: set)
                if trimmed.elements.isEmpty { result.elements.removeLast(); continue }
                result.elements[index] = .link(target, trimmed)
            case .sourcePage: break
            }
            break
        }
        if !result.text.hasSuffix("-") { result.sourceDiscretionaryWord = nil }
        return result
    }
}

struct ReflowBlock: Sendable, Equatable {
    struct Image: Sendable, Equatable {
        struct SelectableLabel: Sendable, Equatable {
            var text: String
            /// Source line bounds normalized to the preserved image's width and height.
            var left: Double
            var top: Double
            var width: Double
            var height: Double
        }
        var assetID: String
        var alternativeText: String
        var caption: String
        /// Where the source links this figure, if it does (#247).
        var link: LinkTarget?
        /// Source-proven expressions rendered as MathML, each with a row crop as fallback (#206).
        var math: [MathExpression] = []
        /// Transparent native text over its rasterized source glyphs, for selection (#212).
        var selectableLabels: [SelectableLabel] = []
    }
    /// A table the source draws, as rows of cells rather than as a picture or as rows of text
    /// (#210). The model carries the association a reader needs — which value stands under which
    /// column heading — which neither a crop nor a line of text can carry.
    struct Table: Sendable, Equatable {
        struct Cell: Sendable, Equatable {
            var text: InlineText
            /// How many columns the cell covers; a spanning heading covers several.
            var columns: Int = 1
        }
        /// Rows top down, cells left to right. Every row covers the table's whole width.
        var rows: [[Cell]]
        /// How many of `rows` the page set as its column headers, from the top. The writer emits
        /// those as `<th scope="col">` inside a `<thead>`.
        var headerRows: Int = 0

        /// Every cell's text in reading order, which the block's `text` reports.
        var text: String {
            rows.map { $0.map(\.text.text).filter { !$0.isEmpty }.joined(separator: " ") }
                .filter { !$0.isEmpty }.joined(separator: "\n")
        }
    }
    /// One item of a real list (#292). Items stream as a sequence with source-derived depth;
    /// the writer nests a child run inside the preceding item (#219).
    struct ListItem: Sendable, Equatable {
        enum Kind: Sendable, Equatable {
            /// A bulleted item: `<ul>`, whose own marker replaces the printed glyph.
            case unordered
            /// A numbered item in a run whose printed numbers ascend by one: `<ol>`, numbered
            /// from the opening item's `ordinal`.
            case ordered
            /// A lettered sequence rendered by an ordered list with alphabetic markers.
            case lettered(uppercase: Bool)
        }
        /// The item's text with its printed marker removed; the list renders its own.
        var text: InlineText
        /// The printed marker (`•`, `3.`), kept for provenance.
        var marker: String
        /// The printed number of an ordered item.
        var ordinal: Int?
        var kind: Kind
        /// Indentation level measured against the containing list's marker edge.
        var level = 0
        /// The first item of its list element. A following item that does not open a list
        /// continues the one open before it.
        var opensList = true
    }
    enum Content: Sendable, Equatable {
        case paragraph(InlineText)
        case quotation(InlineText)
        case aside(InlineText)
        case heading(id: String, text: InlineText, level: Int = 2)
        /// Text whose line breaks are significant: monospaced code, a row of a table the page
        /// set without rules, and a list-shaped line `ListBuilder` did not verify as an item.
        case preformatted(InlineText)
        case listItem(ListItem)
        case image(Image)
        case table(Table)
        case sourcePage(Int)
    }
    var content: Content
    /// Validated source paragraph identity, used to avoid heuristic joins across tag boundaries.
    var structureGroup: Int?
    /// Physical PDF page where this block begins; inline markers record later page boundaries.
    var page: Int
    /// Whether reconstruction opened this preformatted block on a list marker (#292): a bullet
    /// through `LineRole.listItem`, or a number or a letter through `LineRole.markedLine` on an
    /// edge the page sets a list on. `ListBuilder` decides from it and the text whether the block
    /// is a list item; the joins that grow the block keep it. Nil on code, on a table row and on
    /// every other block.
    var listEvidence: ListEvidence?
    struct ListEvidence: Sendable, Equatable {
        /// Whether the line's text is a transcription of a scan: recognized by OCR, or an
        /// inherited invisible text layer over the page image.
        var recognized = false
        /// The source marker's writing edge and size, when a line opened this block.
        var edge: CGFloat? = nil
        var fontSize: CGFloat? = nil
    }
    /// Whether a crop took text the page printed *before* this block, so the page's own text
    /// does not begin here. Set only on the first block a page reflows, and read by the
    /// cross-page join, which must not call such a block the continuation of the page before
    /// ([#267](https://github.com/vocaro/PDFReflowLib/issues/267)).
    var followsCroppedText = false
    /// Complete page-local source-container membership, assigned only after assembly closes
    /// every owned block. Partial or inconsistent groups are barriers to page continuation.
    struct ClosedUnit: Sendable, Equatable {
        var id: Int
        var position: Int
        var count: Int
    }
    var closedUnit: ClosedUnit?

    var text: String {
        switch content {
        case let .paragraph(text), let .quotation(text), let .aside(text), let .heading(_, text, _): text.text
        case let .preformatted(text): text.text
        case let .listItem(item): item.text.text
        case let .table(table): table.text
        case .image, .sourcePage: ""
        }
    }
    var sourcePages: [Int] {
        switch content {
        case let .paragraph(text), let .quotation(text), let .aside(text), let .heading(_, text, _): text.sourcePages
        case let .sourcePage(page): [page]
        case let .preformatted(text): text.sourcePages
        case let .listItem(item): item.text.sourcePages
        case let .table(table): table.rows.flatMap { $0.flatMap(\.text.sourcePages) }
        case .image: []
        }
    }
    var hasReflowedText: Bool {
        switch content {
        case .paragraph, .quotation, .aside, .heading, .preformatted, .listItem, .table: true
        case .image, .sourcePage: false
        }
    }
    /// A preserved region, a cropped figure or a page kept as a picture: content that shows
    /// rather than reads, which a paragraph can be printed around (#203).
    var isImage: Bool {
        if case .image = content { true } else { false }
    }
}
