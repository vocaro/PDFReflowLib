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
                case let .sourcePage(number):
                    unmatchedChapterStarts.remove(number)
                case .paragraph, .preformatted:
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

struct InlineText: Sendable, Equatable, Codable {
    enum Element: Sendable, Equatable, Codable {
        case text(String, TextStyle)
        /// A source boundary can occur inside a paragraph or even inside a repaired word.
        case sourcePage(Int)
    }
    var elements: [Element] = []

    init(_ text: String = "", style: TextStyle = []) {
        if !text.isEmpty { elements = [.text(text, style)] }
    }
    init(elements: [Element]) { self.elements = elements }

    var text: String {
        elements.map { if case let .text(value, _) = $0 { value } else { "" } }.joined()
    }
    var sourcePages: [Int] {
        elements.compactMap { if case let .sourcePage(page) = $0 { page } else { nil } }
    }

    mutating func append(_ other: InlineText) { elements += other.elements }

    /// Replaces the last character in place, keeping the run's style. The line-end hyphen repair
    /// uses it to put back the hyphen a book's font drew but encoded as another character (#233).
    mutating func replaceLastCharacter(with character: Character) {
        for index in elements.indices.reversed() {
            if case let .text(value, style) = elements[index], !value.isEmpty {
                elements[index] = .text(String(value.dropLast()) + String(character), style)
                return
            }
        }
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

struct ReflowBlock: Sendable, Equatable {
    struct Image: Sendable, Equatable {
        var assetID: String
        var alternativeText: String
        var caption: String
    }
    enum Content: Sendable, Equatable {
        case paragraph(InlineText)
        case heading(id: String, text: InlineText, level: Int = 2)
        case preformatted(InlineText)
        case image(Image)
        case sourcePage(Int)
    }
    var content: Content
    /// Validated source paragraph identity, used to avoid heuristic joins across tag boundaries.
    var structureGroup: Int?
    /// Physical PDF page where this block begins; inline markers record later page boundaries.
    var page: Int

    var text: String {
        switch content {
        case let .paragraph(text), let .heading(_, text, _): text.text
        case let .preformatted(text): text.text
        case .image, .sourcePage: ""
        }
    }
    var sourcePages: [Int] {
        switch content {
        case let .paragraph(text), let .heading(_, text, _): text.sourcePages
        case let .sourcePage(page): [page]
        case let .preformatted(text): text.sourcePages
        case .image: []
        }
    }
    var hasReflowedText: Bool {
        switch content {
        case .paragraph, .heading, .preformatted: true
        case .image, .sourcePage: false
        }
    }
}
