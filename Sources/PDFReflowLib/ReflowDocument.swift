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

    enum ValidationError: Error, Equatable {
        case emptyDocument, duplicateAsset(String), missingAsset(String), invalidHeadingLevel(Int)
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
    }
}

struct TextStyle: OptionSet, Sendable, Equatable {
    let rawValue: UInt8
    static let bold = TextStyle(rawValue: 1 << 0)
    static let italic = TextStyle(rawValue: 1 << 1)
    static let superscript = TextStyle(rawValue: 1 << 2)
    static let `subscript` = TextStyle(rawValue: 1 << 3)
}

struct InlineText: Sendable, Equatable {
    enum Element: Sendable, Equatable {
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
