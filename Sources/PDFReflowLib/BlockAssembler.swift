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
    /// One printed row of a table the page set without rules, which keeps its break. The pieces
    /// the extractor left standing side by side on that row rejoin into it, and so does a cell
    /// that wrapped onto the next line, which the block's own left edge tells apart from the row
    /// beneath it (#137, #210).
    case tableRow(continuation: Bool)
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
        // A bulleted line is an item of a list, whatever size its text is set in: a page that
        // draws a bullet has said the line belongs to a list, which a heading does not (#254).
        // This is what lets the line's size be read from its text in both directions; a numbered
        // or lettered marker is not evidence of the same kind, because a heading can be numbered.
        // The rest of such an item carries no marker of its own — the marker is on the line above
        // it — so the page states the relationship instead, in the indent it hangs under (#256).
        if !page.hasSyntheticTextStyle, !opensWithBullet(line.text),
           isTitleSized(line, in: lines, typography: typography, judgesTitleWords: judgesTitleWords)
            || labels.contains(line),
           !hangsUnderBullet(line, in: lines) {
            return .heading
        }
        if !page.hasSyntheticTextStyle && line.monospaced { return .code }
        if isMarked(line.text) { return .markedLine(markerColumn(of: line, in: lines, body: typography.body)) }
        if isList(line.text) { return .listItem }
        return .prose
    }

    /// A line a page opens with a bullet glyph and a space. The alphanumeric markers `isList`
    /// also accepts are deliberately not here: `1. Introduction` is a heading in many books.
    static func opensWithBullet(_ text: String) -> Bool {
        text.range(of: "^[•*−–—-]\\s", options: .regularExpression) != nil
    }

    /// Whether the page hung this line under a bulleted line: it is the rest of that item, and an
    /// item is not a heading whatever size its text is set in (#254, #256). The marker that says
    /// so is on the line above, so the page states the relationship in its indent instead. IRS
    /// Publication 596 sets the starred footnotes under its EIC table at 8 points over a table
    /// whose body is 5.69, and the footnote that wraps reaches the page's heading threshold on
    /// size alone.
    ///
    /// The evidence is the hanging indent the marker leaves, and it is the page's own: a line
    /// carrying no marker itself, at the marked line's size, directly beneath it within the
    /// leading `continuesBrokenItem` already reads, standing between 0.8 and 3 of its size in
    /// from that line's left edge — the window `NumberedNoteDetector` reads for the same
    /// relationship in a numbered note. The marked line must also fill a measure, at least twelve
    /// of its own sizes wide, because a line that wrapped is a line that ran out of room: a short
    /// bulleted item above an indented one is two items, not one wrapped over two lines.
    static func hangsUnderBullet(_ line: TextLine, in lines: [TextLine]) -> Bool {
        guard !isList(line.text) else { return false }
        let size = max(line.fontSize, 4)
        return lines.contains { above in
            guard opensWithBullet(above.text), above.hasSize(line.fontSize), above.wraps != false,
                  above.rect.width >= size * 12 else { return false }
            let indent = line.rect.minX - above.rect.minX
            guard indent >= size * 0.8, indent <= size * 3 else { return false }
            let gap = above.rect.minY - line.rect.maxY
            return gap >= -size * 0.6 && gap <= size * 0.8
        }
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
///
/// There is one paragraph in progress, whether the structure tree named it or the page's
/// geometry did. A page whose tags apply only in part (#67) hands the assembler tagged and
/// untagged lines of one printed paragraph in turn, so a second, parallel slot for tagged text
/// would break that paragraph at every crossing — and strand `previous` and the open paragraph
/// that `continuesWrapped` reads (#238).
struct BlockAssembler {
    let page: Int
    let body: CGFloat
    /// The leading this page's own text states, or nil where it states none (#123).
    let leading: CGFloat?
    let hyphens: HyphenContext
    private(set) var blocks: [ReflowBlock] = []
    /// Uncertain-hyphen warnings the joins raised, one per page.
    private(set) var warnings: [ConversionWarning] = []
    private var note: (group: Int, text: InlineText)?
    private var paragraph = InlineText()
    /// The structure group the open paragraph belongs to, when the tags named one. A tagged and
    /// an untagged line of the same printed paragraph arrive at one assembler — a page whose
    /// tags partly apply interleaves them (#67) — so the open paragraph is one slot, and the tag
    /// travels with it rather than holding a second, parallel one (#238).
    private var paragraphTag: TextStructure?
    private var previous: TextLine?
    /// The line of the heading block last appended, for a heading the page breaks over two lines
    /// with no space at the break (#42).
    private var headingLine: TextLine?
    /// The line of the last preformatted block appended, for an item whose last word the page
    /// broke over the block boundary (#245).
    private var itemLine: TextLine?
    private var codeOrigin: CGFloat?
    /// The table row the last block holds, while more pieces of that printed row can still join
    /// it (#137, #210). Anything else the page hands over closes the row.
    private var rowInProgress: TextLine?

    /// Assets the page's own links cover, by asset path (#247).
    private let imageLinks: [String: LinkTarget]
    /// The wrapped second line of each entry the page hangs, by the entry it carries on (#160).
    private let hangingEntries: [CGRect: CGRect]

    init(page: Int, body: CGFloat, leading: CGFloat? = nil, hyphens: HyphenContext,
         imageLinks: [String: LinkTarget] = [:], hangingEntries: [CGRect: CGRect] = [:]) {
        self.page = page
        self.body = body
        self.leading = leading
        self.hyphens = hyphens
        self.imageLinks = imageLinks
        self.hangingEntries = hangingEntries
    }

    private func headingID() -> String { "heading-\(page)-\(blocks.count)" }

    private mutating func join(_ left: InlineText, _ right: InlineText) -> InlineText {
        LayoutReconstructor.join(left, right, hyphens: hyphens, page: page, warnings: &warnings)
    }

    private mutating func flushNote() {
        if let note { blocks.append(ReflowBlock(content: .paragraph(note.text), page: page)) }
        note = nil
    }

    /// The heading level the tags gave the open paragraph; zero for an untagged one and for a
    /// tagged paragraph, which is what `TextStructure` already means by zero.
    private var paragraphHeadingLevel: Int { paragraphTag?.headingLevel ?? 0 }

    private mutating func flushParagraph() {
        if !paragraph.elements.isEmpty {
            let level = paragraphHeadingLevel
            let content: ReflowBlock.Content = level == 0 ? .paragraph(paragraph)
                : .heading(id: headingID(), text: paragraph, level: level)
            blocks.append(ReflowBlock(content: content, structureGroup: paragraphTag?.group, page: page))
        }
        paragraph = InlineText()
        paragraphTag = nil
        previous = nil
    }

    /// A line of a numbered note; consecutive lines of one `group` join into one paragraph.
    mutating func appendNote(group: Int, _ line: TextLine) {
        flushParagraph()
        codeOrigin = nil
        rowInProgress = nil
        if note?.group != group { flushNote() }
        if let current = note {
            note = (group, join(current.text, line.content))
        } else {
            note = (group, line.content)
        }
    }

    mutating func appendImage(_ assetID: String) {
        flushNote()
        flushParagraph()
        codeOrigin = nil
        rowInProgress = nil
        blocks.append(LayoutReconstructor.imageBlock(assetID: assetID, page: page,
                                                     link: imageLinks[assetID]))
    }

    /// A line the structure tree tagged; consecutive lines of one group join into one block. A
    /// group the tags name is a paragraph boundary the source states, so it always opens its own
    /// block: an untagged paragraph left open before it is flushed, whatever the geometry says.
    mutating func appendTagged(_ tag: TextStructure, _ line: TextLine) {
        flushNote()
        codeOrigin = nil
        rowInProgress = nil
        if paragraphTag?.group != tag.group { flushParagraph() }
        if paragraph.elements.isEmpty {
            paragraph = line.content
            paragraphTag = tag
        } else {
            paragraph = join(paragraph, line.content)
        }
        previous = line
    }

    /// Whether a heading line carries on from the one above it: East Asian writing that sets no
    /// space at the break, at the same size, on the page's own leading (#42). Latin headings are
    /// untouched, because a break between two Latin words is a space and says nothing about
    /// whether the lines are one title or two.
    private func continuesHeading(_ above: TextLine, _ line: TextLine) -> Bool {
        guard CJKText.setsNoSpace(between: above.text, and: line.text),
              above.hasSize(line.fontSize), line.rect.maxY < above.rect.maxY else { return false }
        // A display line's PDFKit box carries enough leading that two stacked lines of a title
        // overlap: the cover's two 31-point lines overlap by 12.9 points. The bound is the size
        // itself, which still separates a stack from a heading a measure further down the page.
        let gap = above.rect.minY - line.rect.maxY
        return gap >= -line.fontSize && gap <= line.fontSize * 0.8
    }

    /// Whether a prose line finishes a word the item above it broke: the item ends in a hyphen or
    /// a soft hyphen, the line opens in lowercase, and it sits directly beneath the item on the
    /// page's own leading. The hyphen goes with the join, as `HyphenRepair` removes one it can
    /// decide; here the page's own break is the evidence and the item's own words are the rest of
    /// it (#245).
    private func continuesBrokenItem(_ above: TextLine, _ line: TextLine, text: InlineText) -> Bool {
        let broken = text.text.hasSuffix("-") || text.text.hasSuffix("\u{00ad}")
            || hyphens.lineEndSubstitute.map { text.text.last == $0 } == true
        guard broken,
              line.text.first?.isLowercase == true, above.hasSize(line.fontSize) else { return false }
        let gap = above.rect.minY - line.rect.maxY
        let size = max(line.fontSize, 4)
        return gap >= -size * 0.6 && gap <= size * 0.8
    }

    mutating func append(_ line: TextLine, as role: LineRole) {
        flushNote()
        if case .heading = role {} else { headingLine = nil }
        if case .listItem = role {} else if case .prose = role {} else { itemLine = nil }
        // An untagged line never extends a tagged heading: the tags said where that heading ends,
        // and prose set beneath it at the column's leading is the text it heads, not more of the
        // heading. The roles below that open a block of their own flush the paragraph themselves.
        if paragraphHeadingLevel > 0 { flushParagraph() }
        if !line.monospaced { codeOrigin = nil }
        if case .tableRow = role {} else { rowInProgress = nil }
        switch role {
        case .heading:
            flushParagraph()
            // East Asian writing breaks a heading between two characters of one word, so the
            // second line is the rest of the first: IRS Publication 596's cover sets
            // `低收入家庭福利优` and `惠 (EIC)` as two lines of one title. The page's own leading
            // and the absence of a space at the break are the evidence (#42).
            if let above = headingLine, let last = blocks.last, last.page == page,
               case let .heading(id, text, level) = last.content, continuesHeading(above, line) {
                var combined = text
                combined.append(line.content)
                blocks[blocks.count - 1].content = .heading(id: id, text: combined, level: level)
            } else {
                blocks.append(ReflowBlock(content: .heading(id: headingID(), text: line.content), page: page))
            }
            headingLine = line
            return
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
            itemLine = line
            return
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
        case let .tableRow(continuation):
            // One block per printed row. A row the extractor split at its column gap arrives as
            // two lines on one baseline, and the second joins the first rather than opening a row
            // of its own: `H 50–1999` and its note-marked `*50` are one row of the FAA's beacon
            // table, not two. A cell that wrapped joins its row the way any wrapped line joins
            // its paragraph, so the 9/11 report's `10:03:11 Flight 93 crashes in field in` keeps
            // `Shanksville, PA` and the FAA's conterminous-states row keeps its altitudes.
            let piece = rowInProgress.map { $0.sharesRow(with: line) && line.rect.minX >= $0.rect.maxX } ?? false
            if rowInProgress != nil, piece || continuation,
               let last = blocks.last, case let .preformatted(text) = last.content {
                blocks[blocks.count - 1].content = .preformatted(piece ? {
                    var combined = text
                    combined.append(InlineText(" "))
                    combined.append(line.content)
                    return combined
                }() : join(text, line.content))
            } else {
                flushParagraph()
                blocks.append(ReflowBlock(content: .preformatted(line.content), page: page))
            }
            rowInProgress = line
        case .prose:
            // An item the page broke mid-word keeps the rest of its word. The 9/11 report sets
            // its recommendations as items and breaks one over the block boundary, so
            // `• …supervise the planning and direc-` was followed by `tion of the operation;` as
            // a paragraph of its own, with the word split between them (#245).
            if let above = itemLine, let last = blocks.last, last.page == page,
               case let .preformatted(text) = last.content, paragraph.elements.isEmpty,
               continuesBrokenItem(above, line, text: text) {
                var combined = text
                combined.removeLastCharacter()
                combined.append(line.content)
                blocks[blocks.count - 1].content = .preformatted(combined)
                itemLine = line
                return
            }
            if let prev = previous, !continuesParagraph(prev, line) { flushParagraph() }
            if paragraph.elements.isEmpty { paragraph = line.content }
            else { paragraph = join(paragraph, line.content) }
            previous = line
        }
    }

    /// Whether `line` continues the paragraph `previous` is part of: the previous line wraps, the
    /// two are stacked at ordinary leading, are two pieces of one printed row, or are an entry and
    /// the wrap the page hangs under it, and the previous line is not a short line the page has
    /// already closed.
    private func continuesParagraph(_ prev: TextLine, _ line: TextLine) -> Bool {
        guard prev.wraps != false else { return false }
        // A short line ending a sentence closes its paragraph however the two lines stand.
        let short = prev.rect.width < line.rect.width * 0.65
        guard !(short && prev.text.last.map { ".!?".contains($0) } == true) else { return false }
        if continuesRow(prev, line) { return true }
        let verticalGap = prev.rect.minY - line.rect.maxY
        // A list the page hangs sets its wraps further in than one column's lines ever stand
        // apart; `LayoutReconstructor.hangingEntries` reads which ones the page hung (#160).
        let hangs = hangingEntries[line.rect] == prev.rect
        guard verticalGap >= -body * 0.4, verticalGap < body * 0.9, onStatedLeading(prev, line),
              abs(prev.rect.minX - line.rect.minX) < body * 1.5 || centered(prev, line) || hangs
        else { return false }
        // Prose fills its measure, so a line that used under half of the one beneath it ended
        // something, and a line the page then sets further in begins the next thing. #39 already
        // reads a marker set in past the line above it as the opening of an item rather than a
        // wrap; this is the same step under a stub of prose, and it never contradicts #39, whose
        // own test refuses exactly the lines this one closes.
        //
        // The Blue Book's observer questionnaire is the case it answers (#130). Page 273 sets the
        // spaced answer row `Yes or No` under question 7 and the instruction `IF you answered
        // YES, then complete the following questions:` a body further in beneath it. The row ends
        // no sentence, so its punctuation says nothing about it; the step the page takes does.
        //
        // Half is where the same book's contents stand: page 5 hangs each entry's wrapped line
        // six points in under an opening that fills three fifths of it, and an entry that runs
        // over is one paragraph. Two thirds — what the sentence-ending rule above asks — would
        // break those; a stub under half the measure is not a line that ran out of room.
        return !(prev.rect.width < line.rect.width * 0.5 && line.rect.minX - prev.rect.minX >= body * 0.5)
    }

    /// Whether the two lines are stacked on one center: a balloon, a box or a caption the page
    /// set centered, whose lines share no left edge to be read as a column (#130). The CDC graphic
    /// novel letters every speech balloon this way, so page 34's `I'VE BEEN` / `THINKING... WE` /
    /// `SHOULD REALLY` / `MAKE AN` / `EMERGENCY KIT` stand on five left edges spread over 18
    /// points and on one center, within 1.7 points of each other on a ten-point page.
    ///
    /// A shared left edge is a column the page itself sets, and stands as evidence on its own. A
    /// shared center does not: a title, its author and its date are centered on one axis and are
    /// three separate lines. So a centered stack joins only where the reading also states that the
    /// line wraps to the next one. Vision states it for every line it recognizes; PDFKit's native
    /// reading states nothing, which leaves every natively extracted page exactly as it was.
    private func centered(_ prev: TextLine, _ line: TextLine) -> Bool {
        prev.wraps == true && abs(prev.rect.midX - line.rect.midX) <= body * 0.6
    }

    /// Whether the page set `line` on the leading its own text states, rather than a further part
    /// of a line down: a line the page pushed down is a line the page set apart (#123).
    ///
    /// Wallace page 64 hangs `writing the second part plus the first` under a bulleted item and
    /// then sets its example, `Three more than a number becomes x + 3`, 21.72 points below it,
    /// where the page's own leading — every wrapped line of prose on it — is 14.40. Measured as
    /// white between the rectangles that is 9.74 points, under the 10.76 this rule already
    /// allowed, so the example was appended to the item's own sentence and the page's separation
    /// of the two was lost. The item below it loses its example the same way, and so do the
    /// paragraph breaks this book sets with a further half-line on 22 of its other pages.
    ///
    /// Two fifths of a line is the slack. A page whose leading varies by a point between
    /// paragraphs still reads as one measure; a page that opens half a line of white has said
    /// something, and here it said 1.51 times its own leading. A page that states no leading
    /// (`statedLeading`) is judged by the gap alone, as before, and so is a pair of lines set at
    /// different sizes, whose tops are not one ascent above their baselines and so cannot be
    /// compared this way.
    private func onStatedLeading(_ prev: TextLine, _ line: TextLine) -> Bool {
        guard let leading, prev.hasSize(line.fontSize) else { return true }
        return prev.rect.maxY - line.rect.maxY <= leading * BlockAssembler.paragraphLeadingSlack
    }

    /// How far past the page's own leading two lines may stand and still be one paragraph.
    static let paragraphLeadingSlack: CGFloat = 1.4

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
        flushParagraph()
        return blocks
    }
}
