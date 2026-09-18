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

/// A tagged list's validated membership for one marked-content item (#194): the `L` element
/// (`list`, document-wide), its `LI` (`item`), how many `L` elements enclose it (`depth`, 0 for a
/// top-level list) and whether the content sits in the item's `Lbl`, its printed label. List tags
/// never form paragraph groups; they annotate lines so the list pass can check item and list
/// boundaries, nesting and the label/body split against the document's own structure.
struct ListTag: Hashable, Codable, Sendable {
    var list: Int
    var item: Int
    var depth: Int
    var label: Bool
}

// All geometry is in unrotated PDF page space (bottom-left origin). OCR is mapped back here.
struct TextLine: Equatable {
    private(set) var content: InlineText
    // Layout repeatedly inspects plain text. Cache it once; content changes only through
    // `replaceContent`, which refreshes the cache, so the two cannot drift.
    private(set) var text: String
    var rect: CGRect
    var fontSize: CGFloat
    var monospaced = false
    var wraps: Bool?
    // Reading order may use the body line beside a drop cap. Ink bounds remain in rect.
    var readingRect: CGRect?
    var structure: TextStructure?
    /// The unit direction in which a recognized line's text runs, in page space, when it is set
    /// more than 45° from left to right (a rotated caption, #122); nil for native and upright text.
    /// `rect` is then the rotated line's axis-aligned bounds, which do not say which way it reads.
    var readingDirection: CGVector?
    /// The extraction reported a word space at the end of this line, which `text` no longer
    /// carries (#180). A line PDFKit ended at a line break carries none, so a piece that does is
    /// one PDFKit cut inside a line, at a space it had already measured.
    var trailingSpace = false
    /// The tagged list item this line's marked content belongs to (#194), when every tagged show on
    /// the line names one item. `label` is the first show's: a line whose first show is an `Lbl`
    /// opens its item.
    var listTag: ListTag?
    /// Where the text begins on a line opened by a list marker drawn as a shape rather than set in
    /// type (`DrawnBulletReader`, #167). The line's `rect` starts at the marker; this is the item's
    /// text edge, from which the list pass measures a nested marker.
    var markerTextEdge: CGFloat?

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

    /// Replaces the line's text and styles, keeping every other property (geometry, size, reading
    /// rectangle, structure and direction) as it was.
    mutating func replaceContent(_ content: InlineText) {
        self.content = content
        text = content.text
    }

    /// Writes the line's ligature characters as letters (`InlineText.spellingOutLigatures`, #189).
    /// Extraction ends with this, native and recognized alike, so every rule after it and the
    /// EPUB see letters only.
    mutating func spellOutLigatures() {
        guard text.contains(where: InlineText.isLigature) else { return }
        replaceContent(content.spellingOutLigatures())
    }
}

// Extracted pages can be held outside memory between the extraction and reconstruction
// passes. This encoding serves one conversion's workspace; it is not a persistent or public
// schema, and the cached plain text is rebuilt from the styled content rather than stored.
extension TextLine: Codable {
    private enum CodingKeys: String, CodingKey {
        case content, rect, fontSize, monospaced, wraps, readingRect, structure, readingDirection
        case trailingSpace, listTag, markerTextEdge
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
        readingDirection = try values.decodeIfPresent(CGVector.self, forKey: .readingDirection)
        trailingSpace = try values.decodeIfPresent(Bool.self, forKey: .trailingSpace) ?? false
        listTag = try values.decodeIfPresent(ListTag.self, forKey: .listTag)
        markerTextEdge = try values.decodeIfPresent(CGFloat.self, forKey: .markerTextEdge)
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
        try values.encodeIfPresent(readingDirection, forKey: .readingDirection)
        if trailingSpace { try values.encode(true, forKey: .trailingSpace) }
        try values.encodeIfPresent(listTag, forKey: .listTag)
        try values.encodeIfPresent(markerTextEdge, forKey: .markerTextEdge)
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
    /// Ruled fill-in blanks (`AnnotationEvidence.blanks`, #152): printed structure, not figures.
    /// They seed no crops; a blank set in a row of type takes its place in that row's text.
    var blanks: [FormBlank] = []
    /// What the step that placed a graphic already knows it holds, where the paint alone would
    /// read as art (#187): a scan's evidence grown as a display row is an equation
    /// (`ScanEvidenceRegions.classifiedRegions`), and a table Vision recognized is a table.
    var graphicKinds: [CGRect: PreservedImageKind] = [:]
    var requiresPageImage = false
    var recognized = false
    var hasSyntheticTextStyle = false
    var preservePageReference = false
}

/// A ruled grid's column boundary at `x`, spanning the rule rows between `minY` and `maxY`
/// (`GraphicsReader.columnJoints`). Extraction splits table cells PDFKit merges across it (#65).
struct ColumnJoint: Equatable {
    var x: CGFloat
    var minY: CGFloat
    var maxY: CGFloat
}

/// A ruled fill-in blank (#152): the thin rule a form's text or choice field is drawn over.
struct FormBlank: Equatable, Codable {
    /// The rule as painted (every thin paint under the field, after `GraphicsReader`'s padding).
    var rule: CGRect
    /// The field's rectangle. A one-line field spans the row of type its blank is set in.
    var field: CGRect

    /// How the blank reads in text: the form's own printed blanks are runs of underscores.
    static let text = "____"

    /// The blanks a page's form fields make of its painted rules. A form prints a rule for every
    /// field, and a reader of the printed page writes on it; the field's rectangle is the form's
    /// own statement of where that blank stands. Every rule under a field is part of one blank,
    /// whether the form draws it as one paint or several (the US Courts form draws some twice,
    /// overlapping).
    ///
    /// A rule is a padded 1-point line as `LayoutReconstructor.isThinRule` reads one: at most six
    /// points tall, at least twelve long and three times its height. It belongs to a field when
    /// at least four fifths of its width lie across the field and its middle lies in the field's
    /// lower half or up to three points beneath it: a one-line field's rule runs along its bottom
    /// edge, and an answer area's closes it. Rules outside every field — a running head's rule, an
    /// underline, a table rule — are no blank, and nothing about them changes.
    static func blanks(fields: [CGRect], paints: [CGRect]) -> [FormBlank] {
        fields.compactMap { field in
            guard field.isFinite, !field.isNull, field.width > 0, field.height > 0 else { return nil }
            let rules = paints.filter { paint in
                guard paint.height <= 6, paint.width >= max(12, paint.height * 3) else { return false }
                let across = min(paint.maxX, field.maxX) - max(paint.minX, field.minX)
                return across >= paint.width * 0.8
                    && paint.midY >= field.minY - 3 && paint.midY <= field.minY + field.height * 0.5
            }
            return rules.isEmpty ? nil : FormBlank(rule: union(rules), field: field)
        }
    }

    /// Whether the field holds one line of the type on `row` (a line beside it or around it), so
    /// that its blank belongs to that row. A taller field is an answer area whose rule closes it.
    func sharesRow(with row: CGRect) -> Bool {
        let overlap = min(field.maxY, row.maxY) - max(field.minY, row.minY)
        return field.height <= row.height * 2 && overlap >= min(field.height, row.height) * 0.5
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
