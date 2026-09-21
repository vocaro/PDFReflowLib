import CoreGraphics
import Foundation

struct TextStructure: Equatable, Codable {
    var group: Int
    var order: Int
    /// Zero denotes a paragraph; 1...6 denote the corresponding heading level.
    var headingLevel: Int
    var lineCount: Int = 0
}

// All geometry is in unrotated PDF page space (bottom-left origin). OCR is mapped back here.
struct TextLine: Equatable {
    let content: InlineText
    // Layout repeatedly inspects plain text. Cache it once; immutable content prevents drift.
    let text: String
    var rect: CGRect
    var fontSize: CGFloat
    var monospaced = false
    var wraps: Bool?
    // Reading order may use the body line beside a drop cap. Ink bounds remain in rect.
    var readingRect: CGRect?
    var structure: TextStructure?

    init(text: String, rect: CGRect, fontSize: CGFloat, monospaced: Bool = false, wraps: Bool? = nil) {
        self.init(content: InlineText(text), rect: rect, fontSize: fontSize, monospaced: monospaced, wraps: wraps)
    }

    init(content: InlineText, rect: CGRect, fontSize: CGFloat, monospaced: Bool = false, wraps: Bool? = nil) {
        self.content = content
        self.text = content.text
        self.rect = rect
        self.fontSize = fontSize
        self.monospaced = monospaced
        self.wraps = wraps
    }
}

// Extracted pages can be held outside memory between the extraction and reconstruction
// passes. This encoding serves one conversion's workspace; it is not a persistent or public
// schema, and the cached plain text is rebuilt from the styled content rather than stored.
extension TextLine: Codable {
    private enum CodingKeys: String, CodingKey {
        case content, rect, fontSize, monospaced, wraps, readingRect, structure
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(content: try values.decode(InlineText.self, forKey: .content),
                  rect: try values.decode(CGRect.self, forKey: .rect),
                  fontSize: try values.decode(CGFloat.self, forKey: .fontSize),
                  monospaced: try values.decode(Bool.self, forKey: .monospaced),
                  wraps: try values.decodeIfPresent(Bool.self, forKey: .wraps))
        readingRect = try values.decodeIfPresent(CGRect.self, forKey: .readingRect)
        structure = try values.decodeIfPresent(TextStructure.self, forKey: .structure)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(content, forKey: .content)
        try values.encode(rect, forKey: .rect)
        try values.encode(fontSize, forKey: .fontSize)
        try values.encode(monospaced, forKey: .monospaced)
        try values.encodeIfPresent(wraps, forKey: .wraps)
        try values.encodeIfPresent(readingRect, forKey: .readingRect)
        try values.encodeIfPresent(structure, forKey: .structure)
    }
}

/// A link the page draws: the rectangle it covers, and where it points (#247).
struct PageLink: Equatable, Codable, Sendable {
    var rect: CGRect
    var target: LinkTarget
}

/// A table a page draws, divided into cells by `TableReader` (#210).
///
/// The reader works in page space: a cell is a rectangle, and its text is what the page's own
/// extraction reads inside that rectangle. Reconstruction turns the rows into a `ReflowBlock`
/// and keeps the crop that used to preserve the table as a picture from being made at all.
struct PageTable: Equatable, Codable, Sendable {
    struct Cell: Equatable, Codable, Sendable {
        /// The cell's reading. Where the cell is exactly one of the page's extracted lines it is
        /// that line's own content, with the repairs and styles the rest of the pipeline gives it;
        /// otherwise it is the plain characters the page reads inside the cell's rectangle.
        var content: InlineText
        var rect: CGRect
        /// How many of the table's columns this cell covers. A spanning header covers several.
        var columns: Int = 1

        var text: String { content.text }
    }
    /// The block the table occupies: the union of its rows, which claims those rows' lines.
    var rect: CGRect
    /// Printed rows top down, each row's cells left to right. Every row covers every column.
    var rows: [[Cell]]
    /// How many of `rows` the page set as its column headers, from the top.
    var headerRows: Int = 0
    /// The table's columns, which every row divides into.
    var columns: Int { rows.first?.reduce(0) { $0 + $1.columns } ?? 0 }
}

struct PageContent: Equatable, Codable {
    var number: Int
    var bounds: CGRect
    var lines: [TextLine]
    var graphics: [CGRect]
    /// The placed raster image XObjects among `graphics`: the page's pictures (#176, #239).
    var pictures: [CGRect] = []
    var requiresPageImage = false
    var recognized = false
    var hasSyntheticTextStyle = false
    var preservePageReference = false
    /// The link annotations this page draws, in the order it lists them (#247).
    var links: [PageLink] = []
    /// The tables this page draws, read as cells (#210). Empty on every page whose printed rows
    /// state no column grid of their own.
    var tables: [PageTable] = []
    /// The tables a recognition of this page located, and how much of each one it transcribed
    /// (#31). They are among `graphics`, so each is already preserved as a picture; this is what
    /// that picture holds, and which of those pictures the recognizer could not read. A scanned
    /// page states no grid of its own, so `tables` above is empty wherever these are not.
    var recognizedTables: [TableCellEvidence.Reading] = []
}

func union(_ rects: [CGRect]) -> CGRect {
    rects.reduce(CGRect.null) { $0.union($1) }
}

func clusters(_ rects: [CGRect], distance: CGFloat) -> [CGRect] {
    var result: [CGRect] = []
    for rect in rects where !rect.isNull && rect.isFinite {
        var merged = rect
        var previousCount = -1
        while previousCount != result.count {
            previousCount = result.count
            result.removeAll { existing in
                if existing.insetBy(dx: -distance, dy: -distance).intersects(merged) {
                    merged = merged.union(existing)
                    return true
                }
                return false
            }
        }
        result.append(merged)
    }
    return result
}

extension CGRect {
    var isFinite: Bool {
        origin.x.isFinite && origin.y.isFinite && width.isFinite && height.isFinite
    }
}
