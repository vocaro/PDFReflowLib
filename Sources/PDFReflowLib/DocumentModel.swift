import CoreGraphics
import Foundation

struct TextStructure: Equatable, Codable {
    var group: Int
    var order: Int
    /// Zero denotes a paragraph; 1...6 denote the corresponding heading level.
    var headingLevel: Int
    var lineCount: Int = 0
    /// Set by `LayoutReconstructor.joiningMarkerPieces` when a list marker PDFKit split from its
    /// text is rejoined inside this group: the group's validated content opens with that item.
    var opensWithSplitMarker = false
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

struct PageContent: Equatable, Codable {
    var number: Int
    var bounds: CGRect
    var lines: [TextLine]
    var graphics: [CGRect]
    /// Rectangles painted behind reflowed text (sidebar frames, tint bands, cell shading).
    /// They seed no crops; the table detector reads their grid.
    var tints: [CGRect] = []
    /// Thin rules inside those tinted blocks that separate rows and columns rather than
    /// drawing a figure. They seed no crops either; the table detector reads row edges from them.
    var separators: [CGRect] = []
    var requiresPageImage = false
    var recognized = false
    var hasSyntheticTextStyle = false
    var preservePageReference = false
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
