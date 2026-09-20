import CoreGraphics
import Foundation

/// What one spatial line becomes in the logical document.
enum LineRole: Equatable, Sendable {
    /// A heading-size line, or a recurring bold sub-heading label.
    case heading
    /// Monospaced code, which keeps its line breaks and indentation.
    case code
    /// A line opening with a bullet, which keeps its break.
    case listItem
    /// A line opening with a number or a single letter and a point. It opens a list item, or it
    /// is a wrapped line whose first word is an initial, a citation or a year (`W. Bush`,
    /// `U. S. 760`, `2016.`) and belongs to the paragraph above it (#39, #238). Only the
    /// assembler knows what the previous line did, and only the page knows the column this line
    /// sits in, so the page's half of the evidence travels with the role.
    case markedLine(MarkerColumn)
    /// Ordinary prose, joined into paragraphs.
    case prose
}

/// Where a marker-leading line sits in the column of same-size lines around it: the page-level
/// evidence that separates the opening of a list item from a wrapped continuation (#39).
struct MarkerColumn: Equatable, Sendable {
    /// Whether the line stands on the left edge most of its column shares. A hanging list marker
    /// beside dedented continuation lines does not.
    let onMajorityEdge: Bool
    /// The right edge at least three same-size lines of the column reach, when the column is
    /// justified; nil when ragged item lengths establish no margin to fill.
    let justifiedRight: CGFloat?
}

extension LayoutReconstructor {
    /// Whether a line reads as a heading by its size: at or above the heading threshold, under
    /// 200 characters, opening with a capital, a digit or a mark unless it stacks with another
    /// display-size line (#186), and, on a recognized page in an English book, reading as words
    /// (#7).
    static func isTitleSized(_ line: TextLine, in lines: [TextLine], typography: PageTypography,
                             judgesTitleWords: Bool) -> Bool {
        line.fontSize >= typography.headingThreshold && line.text.count < 200
            && (line.text.first?.isLowercase != true || stacksWithDisplay(line, in: lines, typography: typography))
            && (!judgesTitleWords || EnglishText.readsAsWords(line.text))
    }

    /// A heading-size line standing alone that opens in lowercase is display text that heads
    /// nothing: a magazine cover's title line "From Insects" can be followed by a lowercase
    /// cross-reference line "pages 2, 4-14" set at the same size, which is not itself a title
    /// (#186). A line stacked with another of its size, above or below, is part of a title or a
    /// pull quote and keeps its size's reading.
    static func stacksWithDisplay(_ line: TextLine, in lines: [TextLine], typography: PageTypography) -> Bool {
        lines.contains { other in
            other != line && other.fontSize >= typography.headingThreshold
                && (stacksUnderHeading(line, after: other) || stacksUnderHeading(other, after: line))
        }
    }

    /// The role of an untagged line outside any note group. A synthetic-style page (invisible
    /// text over a scan) supplies no typography, so its lines are prose or list items only;
    /// `labels` are the page's recurring bold sub-headings, already empty on such pages.
    static func role(of line: TextLine, on page: PageContent, in lines: [TextLine], typography: PageTypography,
                     labels: [TextLine], judgesTitleWords: Bool) -> LineRole {
        if !page.hasSyntheticTextStyle
            && (isTitleSized(line, in: lines, typography: typography, judgesTitleWords: judgesTitleWords) || labels.contains(line)) {
            return .heading
        }
        if !page.hasSyntheticTextStyle && line.monospaced { return .code }
        if isMarked(line.text) { return .markedLine(markerColumn(of: line, in: lines, body: typography.body)) }
        if isList(line.text) { return .listItem }
        return .prose
    }

    static func isList(_ text: String) -> Bool {
        text.range(of: "^(?:[•*−-]|[0-9]+[.)]|[A-Za-z][.)])\\s", options: .regularExpression) != nil
    }

    /// The list markers a wrapped line of prose can also begin with: a number or a single letter
    /// followed by a point or a bracket. A bullet, a minus or a hyphen never opens a sentence's
    /// continuation, so those keep the plain `listItem` reading.
    static func isMarked(_ text: String) -> Bool {
        text.range(of: "^(?:[0-9]+|[A-Za-z])[.)]\\s", options: .regularExpression) != nil
    }

    /// Where `line` sits among the same-size, proportional lines within one and a half body sizes
    /// of its left edge: whether it is on that column's majority left edge, and the right edge at
    /// least three of those lines reach. Two lines agreeing on a right edge are not a justified
    /// margin, and ragged item lengths establish none at all.
    static func markerColumn(of line: TextLine, in lines: [TextLine], body: CGFloat) -> MarkerColumn {
        let size = Int(line.fontSize.rounded())
        let column = lines.filter {
            !$0.monospaced && Int($0.fontSize.rounded()) == size && abs($0.rect.minX - line.rect.minX) < body * 1.5
        }
        let onEdge = column.count { abs($0.rect.minX - line.rect.minX) < body * 0.5 }
        guard let right = column.map(\.rect.maxX).max() else {
            return MarkerColumn(onMajorityEdge: false, justifiedRight: nil)
        }
        let justified = column.count { $0.rect.maxX >= right - body * 0.25 }
        return MarkerColumn(onMajorityEdge: onEdge * 2 > column.count,
                            justifiedRight: justified >= 3 ? right : nil)
    }
}

/// Builds one page's logical blocks from its ordered elements: paragraphs from prose lines,
/// preformatted blocks from code and list lines, headings, images, and the tagged and numbered
/// note groups that arrive already grouped. It owns the paragraph in progress and the code
/// block's origin; every `append` decides what the previous block was and flushes it.
struct BlockAssembler {
    let page: Int
    let body: CGFloat
    let hyphens: HyphenContext
    private(set) var blocks: [ReflowBlock] = []
    /// Uncertain-hyphen warnings the joins raised, one per page.
    private(set) var warnings: [ConversionWarning] = []
    private var note: (group: Int, text: InlineText)?
    private var tagged: (tag: TextStructure, text: InlineText)?
    private var paragraph = InlineText()
    private var previous: TextLine?
    private var codeOrigin: CGFloat?

    init(page: Int, body: CGFloat, hyphens: HyphenContext) {
        self.page = page
        self.body = body
        self.hyphens = hyphens
    }

    private func headingID() -> String { "heading-\(page)-\(blocks.count)" }

    private mutating func join(_ left: InlineText, _ right: InlineText) -> InlineText {
        LayoutReconstructor.join(left, right, hyphens: hyphens, page: page, warnings: &warnings)
    }

    private mutating func flushNote() {
        if let note { blocks.append(ReflowBlock(content: .paragraph(note.text), page: page)) }
        note = nil
    }

    private mutating func flushTagged() {
        guard let tagged else { return }
        let content: ReflowBlock.Content = tagged.tag.headingLevel == 0 ? .paragraph(tagged.text)
            : .heading(id: headingID(), text: tagged.text, level: tagged.tag.headingLevel)
        blocks.append(ReflowBlock(content: content, structureGroup: tagged.tag.group, page: page))
        self.tagged = nil
    }

    private mutating func flushParagraph() {
        if !paragraph.elements.isEmpty {
            blocks.append(ReflowBlock(content: .paragraph(paragraph), page: page))
        }
        paragraph = InlineText()
        previous = nil
    }

    /// A line of a numbered note; consecutive lines of one `group` join into one paragraph.
    mutating func appendNote(group: Int, _ line: TextLine) {
        flushTagged()
        flushParagraph()
        codeOrigin = nil
        if note?.group != group { flushNote() }
        if let current = note {
            note = (group, join(current.text, line.content))
        } else {
            note = (group, line.content)
        }
    }

    mutating func appendImage(_ assetID: String) {
        flushNote()
        flushTagged()
        flushParagraph()
        codeOrigin = nil
        blocks.append(LayoutReconstructor.imageBlock(assetID: assetID, page: page))
    }

    /// A line the structure tree tagged; consecutive lines of one group join into one block.
    mutating func appendTagged(_ tag: TextStructure, _ line: TextLine) {
        flushNote()
        flushParagraph()
        codeOrigin = nil
        if tagged?.tag.group != tag.group { flushTagged() }
        if let current = tagged {
            tagged = (current.tag, join(current.text, line.content))
        } else {
            tagged = (tag, line.content)
        }
    }

    mutating func append(_ line: TextLine, as role: LineRole) {
        flushNote()
        flushTagged()
        if !line.monospaced { codeOrigin = nil }
        switch role {
        case .heading:
            flushParagraph()
            blocks.append(ReflowBlock(content: .heading(id: headingID(), text: line.content), page: page))
        case .code:
            flushParagraph()
            if let origin = codeOrigin, let last = blocks.last, case let .preformatted(previousText) = last.content {
                let indent = min(80, max(0, Int(((line.rect.minX - origin) / (line.fontSize * 0.6)).rounded())))
                var combined = previousText
                combined.append(InlineText("\n" + String(repeating: " ", count: indent)))
                combined.append(line.content)
                blocks[blocks.count - 1].content = .preformatted(combined)
            } else {
                codeOrigin = line.rect.minX
                blocks.append(ReflowBlock(content: .preformatted(line.content), page: page))
            }
        case .listItem:
            flushParagraph()
            // Preserve significant breaks and native styles; do not rewrite list markers or code.
            blocks.append(ReflowBlock(content: .preformatted(line.content), page: page))
        case .markedLine(let column):
            // A wrapped line whose first word is an initial, a citation or a year belongs to the
            // paragraph above it; anything else opens an item and keeps its own block (#39).
            if let prev = previous, !paragraph.elements.isEmpty, continuesWrapped(prev, line, column) {
                paragraph = join(paragraph, line.content)
                previous = line
            } else {
                flushParagraph()
                blocks.append(ReflowBlock(content: .preformatted(line.content), page: page))
            }
        case .prose:
            if let prev = previous, !continuesParagraph(prev, line) { flushParagraph() }
            if paragraph.elements.isEmpty { paragraph = line.content }
            else { paragraph = join(paragraph, line.content) }
            previous = line
        }
    }

    /// Whether `line` continues the paragraph `previous` is part of: the previous line wraps,
    /// the two share a column at ordinary leading or are two pieces of one printed row, and the
    /// previous line is not a short line ending a sentence.
    private func continuesParagraph(_ prev: TextLine, _ line: TextLine) -> Bool {
        let verticalGap = prev.rect.minY - line.rect.maxY
        let sameColumn = abs(prev.rect.minX - line.rect.minX) < body * 1.5
            && verticalGap >= -body * 0.4 && verticalGap < body * 0.9
        let shortEnding = prev.rect.width < line.rect.width * 0.65
            && prev.text.last.map { ".!?".contains($0) } == true
        return prev.wraps != false && (sameColumn || continuesRow(prev, line)) && !shortEnding
    }

    /// Whether a line opening with a number or a single letter and a point is a wrapped
    /// continuation of the open paragraph rather than the opening of a list item (#39, #238).
    /// It must first continue the paragraph the way any prose line would, and then:
    ///
    /// - not be indented past the previous line's text start, because a marker set in from the
    ///   text above it hangs a new item, while a marker to the left of it is the ordinary
    ///   outdent of a wrap under an indented opening line;
    /// - stand on the majority left edge of its column, in a column justified to a right edge
    ///   at least three of its lines reach, which the previous line also reaches: a line that
    ///   stops short of the margin ended its own thought, and a list's ragged items fill nothing;
    /// - follow a line that does not end a sentence, ignoring closing quotes and brackets;
    /// - follow a line that reads as prose rather than symbols, which an exercise or a formula
    ///   above a numbered answer does not.
    private func continuesWrapped(_ prev: TextLine, _ line: TextLine, _ column: MarkerColumn) -> Bool {
        guard continuesParagraph(prev, line), prev.rect.minX - line.rect.minX > -body * 0.5,
              column.onMajorityEdge, let right = column.justifiedRight,
              prev.rect.maxX >= right - body * 0.25 else { return false }
        let closing: Set<Character> = ["\u{201D}", "\u{2019}", "\"", "'", ")", "]"]
        guard let ending = prev.text.reversed().first(where: { !$0.isWhitespace && !closing.contains($0) }),
              !".!?:;".contains(ending) else { return false }
        return prev.text.split(whereSeparator: { !$0.isLetter }).count { $0.count >= 2 } >= 3
    }

    /// Whether `line` is the rest of the printed line `prev` begins. PDFKit splits a row at a
    /// wide gap, and on the 9/11 report's page 254 it splits the page's last line a word from
    /// its end, leaving `told` a line, a paragraph and — as the page's last block — the anchor a
    /// cross-page join would have to read (#57). Two pieces of one row are one paragraph.
    ///
    /// The pieces must stand side by side, `line` to the right of `prev`, closer than the gutter
    /// a column needs (`LayoutReconstructor.ordered`'s three quarters of a body). A table's cells,
    /// and a running header and the folio at the other end of its row, stand further apart than
    /// that and stay separate blocks, as does anything on another row.
    private func continuesRow(_ prev: TextLine, _ line: TextLine) -> Bool {
        prev.sharesRow(with: line) && line.rect.minX >= prev.rect.maxX
            && line.rect.minX - prev.rect.maxX < body * 0.75
    }

    mutating func finish() -> [ReflowBlock] {
        flushNote()
        flushTagged()
        flushParagraph()
        return blocks
    }
}
