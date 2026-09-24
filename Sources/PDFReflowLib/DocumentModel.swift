import CoreGraphics
import Foundation

struct TextStructure: Equatable, Codable {
    var group: Int
    var order: Int
    /// Zero denotes a paragraph; 1...6 denote the corresponding heading level.
    var headingLevel: Int
    var lineCount: Int = 0
}

/// The quarter turn a page set a line at: which way the line's own writing runs (#130, #263).
///
/// Every rectangle a reader hands over is axis-aligned, so a line the page letters sideways
/// arrives as a rectangle as tall as the line is long and as wide as its type is thick. The
/// rectangle says nothing about which end of it the line starts at, or which of its neighbors is
/// the next line down. The reading's own quadrilateral does, and `OCRReader.turn` reads it off; a
/// reader that states no direction leaves every line `upright`, which is what a natively extracted
/// page and a hand-made line in a test carry.
enum QuarterTurn: String, Codable, Sendable {
    /// The page set the line the way the page itself is read: the writing runs left to right and
    /// the line's thickness stands up the page.
    case upright
    /// The page turned the line a quarter clockwise: the writing runs down the page and the tops
    /// of the letters face right. The CDC graphic novel letters page 17's caption this way.
    case clockwise
    /// The page turned the line a quarter counterclockwise: the writing runs up the page and the
    /// tops of the letters face left, as a spine or a tall table's column head is set.
    case counterclockwise

    /// `rect` in the frame the line's own writing runs in: the page turned until the line stands
    /// upright, so that its writing runs left to right and its thickness up the page (#263).
    ///
    /// The turn is taken about the page's origin, which puts a sideways line's rectangle outside
    /// the page. Nothing is lost by that: every rule that reads this frame compares two lines of
    /// one turn with each other — a gap, a shared edge, a shared row, a shared center — and a
    /// rotation about any fixed point leaves all of those exactly as they were.
    func upright(_ rect: CGRect) -> CGRect {
        switch self {
        case .upright:
            return rect
        // Writing that runs down the page stands upright once the page is turned
        // counterclockwise: (x, y) becomes (-y, x).
        case .clockwise:
            return CGRect(x: -rect.maxY, y: rect.minX, width: rect.height, height: rect.width)
        // Writing that runs up the page stands upright once the page is turned clockwise:
        // (x, y) becomes (y, -x).
        case .counterclockwise:
            return CGRect(x: rect.minY, y: -rect.maxX, width: rect.height, height: rect.width)
        }
    }

    /// The one turn every item of `items` was set at, when they agree on a turn that is not
    /// upright and there are at least two of them; nil otherwise (#263). A group the page set
    /// sideways is read in its own frame; a group holding an upright line, a picture or a table
    /// is read in the page's.
    static func shared<Item>(by items: [Item], turn: (Item) -> QuarterTurn?) -> QuarterTurn? {
        guard items.count > 1, let first = items.first.flatMap(turn), first != .upright,
              items.allSatisfy({ turn($0) == first }) else { return nil }
        return first
    }
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
    // Which way the page set this line's writing running (#263). `rect` is axis-aligned whatever
    // the turn, so the turn is the only statement of where the line starts and which line is the
    // next one down; a reader that states no direction leaves it upright.
    var turn: QuarterTurn = .upright
    // Reading order may use the body line beside a drop cap. Ink bounds remain in rect.
    var readingRect: CGRect?
    var structure: TextStructure?

    init(text: String, rect: CGRect, fontSize: CGFloat, monospaced: Bool = false, wraps: Bool? = nil,
         turn: QuarterTurn = .upright) {
        self.init(content: InlineText(text), rect: rect, fontSize: fontSize, monospaced: monospaced,
                  wraps: wraps, turn: turn)
    }

    init(content: InlineText, rect: CGRect, fontSize: CGFloat, monospaced: Bool = false, wraps: Bool? = nil,
         turn: QuarterTurn = .upright) {
        self.content = content
        self.text = content.text
        self.rect = rect
        self.fontSize = fontSize
        self.monospaced = monospaced
        self.wraps = wraps
        self.turn = turn
    }
}

// Extracted pages can be held outside memory between the extraction and reconstruction
// passes. This encoding serves one conversion's workspace; it is not a persistent or public
// schema, and the cached plain text is rebuilt from the styled content rather than stored.
extension TextLine: Codable {
    private enum CodingKeys: String, CodingKey {
        case content, rect, fontSize, monospaced, wraps, turn, readingRect, structure
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(content: try values.decode(InlineText.self, forKey: .content),
                  rect: try values.decode(CGRect.self, forKey: .rect),
                  fontSize: try values.decode(CGFloat.self, forKey: .fontSize),
                  monospaced: try values.decode(Bool.self, forKey: .monospaced),
                  wraps: try values.decodeIfPresent(Bool.self, forKey: .wraps),
                  turn: try values.decodeIfPresent(QuarterTurn.self, forKey: .turn) ?? .upright)
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
        // An upright line is every natively extracted line and every line a test makes by hand;
        // it is left out so that no page's spill grows by a field it never uses.
        if turn != .upright { try values.encode(turn, forKey: .turn) }
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
    struct TaggedFigure: Equatable, Codable {
        var rect: CGRect
        var alternativeText: String
    }
    var number: Int
    var bounds: CGRect
    var lines: [TextLine]
    var graphics: [CGRect]
    /// The placed raster image XObjects among `graphics`: the page's pictures (#176, #239).
    var pictures: [CGRect] = []
    /// Validated author Alt text for a single marked raster figure (#17).
    var taggedFigures: [TaggedFigure] = []
    /// A flat painted head band, recorded before decoration leaves the crop seeds.
    var headerBackdrop: CGRect?
    var outlinedInitialRows: [CGRect]?
    var sidebarValueRows: [CGRect]?
    var nativeTextPanels: [CGRect]?
    /// Complete source-painted rule frames; ownership only, not permission to recover text.
    var closedNativeFrames: [CGRect]?
    /// Rules on which a form reader writes, with or without interactive fields (#197, #211).
    var blanks: [FormBlank] = []
    var requiresPageImage = false
    var recognized = false
    var hasSyntheticTextStyle = false
    var preservePageReference = false
    /// Local source crops of recognized outline writing, kept outside semantic figure regions
    /// so their transcription still reflows (#192).
    var recognizedArtwork: [CGRect] = []
    /// Proven text panels over a flat page ground. Their native writing may reflow while
    /// the surrounding vector diagram is retained as a source crop (#182).
    var backdropTextPanels: [CGRect]? = nil
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

extension PageContent {
    private enum CodingKeys: String, CodingKey {
        case number, bounds, lines, graphics, pictures, taggedFigures, headerBackdrop, outlinedInitialRows
        case sidebarValueRows, nativeTextPanels, closedNativeFrames, blanks, requiresPageImage
        case recognized, hasSyntheticTextStyle, preservePageReference, recognizedArtwork
        case backdropTextPanels, links, tables, recognizedTables
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        number = try values.decode(Int.self, forKey: .number)
        bounds = try values.decode(CGRect.self, forKey: .bounds)
        lines = try values.decode([TextLine].self, forKey: .lines)
        graphics = try values.decode([CGRect].self, forKey: .graphics)
        pictures = try values.decode([CGRect].self, forKey: .pictures)
        taggedFigures = try values.decodeIfPresent([TaggedFigure].self, forKey: .taggedFigures) ?? []
        headerBackdrop = try values.decodeIfPresent(CGRect.self, forKey: .headerBackdrop)
        outlinedInitialRows = try values.decodeIfPresent([CGRect].self, forKey: .outlinedInitialRows)
        sidebarValueRows = try values.decodeIfPresent([CGRect].self, forKey: .sidebarValueRows)
        nativeTextPanels = try values.decodeIfPresent([CGRect].self, forKey: .nativeTextPanels)
        closedNativeFrames = try values.decodeIfPresent([CGRect].self, forKey: .closedNativeFrames)
        // The earlier captured page fixtures have no form evidence field (#211).
        blanks = try values.decodeIfPresent([FormBlank].self, forKey: .blanks) ?? []
        requiresPageImage = try values.decode(Bool.self, forKey: .requiresPageImage)
        recognized = try values.decode(Bool.self, forKey: .recognized)
        hasSyntheticTextStyle = try values.decode(Bool.self, forKey: .hasSyntheticTextStyle)
        preservePageReference = try values.decode(Bool.self, forKey: .preservePageReference)
        recognizedArtwork = try values.decode([CGRect].self, forKey: .recognizedArtwork)
        backdropTextPanels = try values.decodeIfPresent([CGRect].self, forKey: .backdropTextPanels)
        links = try values.decode([PageLink].self, forKey: .links)
        tables = try values.decode([PageTable].self, forKey: .tables)
        recognizedTables = try values.decode([TableCellEvidence.Reading].self, forKey: .recognizedTables)
    }
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
