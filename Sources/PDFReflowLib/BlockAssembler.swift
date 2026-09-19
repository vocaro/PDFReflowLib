import CoreGraphics
import Foundation

/// What one spatial line becomes in the logical document.
enum LineRole: Equatable, Sendable {
    /// A heading-size line, or a recurring bold sub-heading label.
    case heading
    /// Monospaced code, which keeps its line breaks and indentation.
    case code
    /// A line opening with a list marker, which keeps its break.
    case listItem
    /// Ordinary prose, joined into paragraphs.
    case prose
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
        if isList(line.text) { return .listItem }
        return .prose
    }

    static func isList(_ text: String) -> Bool {
        text.range(of: "^(?:[•*−-]|[0-9]+[.)]|[A-Za-z][.)])\\s", options: .regularExpression) != nil
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
        case .prose:
            if let prev = previous, !continuesParagraph(prev, line) { flushParagraph() }
            if paragraph.elements.isEmpty { paragraph = line.content }
            else { paragraph = join(paragraph, line.content) }
            previous = line
        }
    }

    /// Whether `line` continues the paragraph `previous` is part of: the previous line wraps,
    /// the two share a column at ordinary leading, and the previous line is not a short line
    /// ending a sentence.
    private func continuesParagraph(_ prev: TextLine, _ line: TextLine) -> Bool {
        let verticalGap = prev.rect.minY - line.rect.maxY
        let sameColumn = abs(prev.rect.minX - line.rect.minX) < body * 1.5
            && verticalGap >= -body * 0.4 && verticalGap < body * 0.9
        let shortEnding = prev.rect.width < line.rect.width * 0.65
            && prev.text.last.map { ".!?".contains($0) } == true
        return prev.wraps != false && sameColumn && !shortEnding
    }

    mutating func finish() -> [ReflowBlock] {
        flushNote()
        flushTagged()
        flushParagraph()
        return blocks
    }
}
