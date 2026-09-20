import CoreGraphics
import Testing
@testable import PDFReflowLib

/// The layout seams introduced by the 2026-09-19 review: a page's typography read once, a line's
/// role decided by one function, paragraphs assembled by one value, and hyphens decided by an
/// explicit context. Each rule is exercised on hand-made lines, without a page fixture.
private func line(_ text: String, x: CGFloat = 40, y: CGFloat, width: CGFloat = 300, size: CGFloat = 10,
                  monospaced: Bool = false, wraps: Bool? = nil, bold: Bool = false) -> TextLine {
    TextLine(content: InlineText(text, style: bold ? .bold : []), rect: CGRect(x: x, y: y, width: width, height: size * 1.2),
             fontSize: size, monospaced: monospaced, wraps: wraps)
}

private func page(_ lines: [TextLine], synthetic: Bool = false, recognized: Bool = false) -> PageContent {
    PageContent(number: 3, bounds: CGRect(x: 0, y: 0, width: 400, height: 600), lines: lines, graphics: [],
                recognized: recognized, hasSyntheticTextStyle: synthetic)
}

/// Enough ten-point prose to establish a body: five lines, well over 200 characters.
private let prose: [TextLine] = (0..<5).map {
    line("The quick brown fox jumps over the lazy dog and keeps running across the field.", y: 500 - CGFloat($0) * 12)
}

@Test func typographyReadsThePageOnce() {
    let lines = prose + [line("Title", y: 560, size: 16)]
    let typography = PageTypography(pageLines: lines, reflowableLines: lines, documentBody: 11)
    #expect(typography.body == 10)
    #expect(typography.establishedBody == 10)
    #expect(typography.headingBody == 10)
    #expect(typography.documentFloor == 0)
    #expect(typography.headingThreshold == 12.5)

    // A page too sparse to establish a body takes the document's floor.
    let sparse = [line("Return address", y: 500, size: 9), line("www.example.org", y: 480, size: 9)]
    let bare = PageTypography(pageLines: sparse, reflowableLines: sparse, documentBody: 12)
    #expect(bare.establishedBody == nil)
    #expect(bare.documentFloor == 12 * 1.1)
    #expect(bare.headingThreshold == 12 * 1.1)
    #expect(PageTypography(page: page(sparse)).documentFloor == 0)

    // Text inside images is excluded from the heading body; a larger reflowable body raises it.
    let large = (0..<5).map { line("Twelve point body text that establishes itself with plenty of characters here.", y: 300 - CGFloat($0) * 14, size: 12) }
    let mixed = PageTypography(pageLines: prose + large, reflowableLines: large, documentBody: nil)
    #expect(mixed.body == 12 || mixed.body == 10)
    #expect(mixed.headingBody == max(mixed.body, 12))
    #expect(mixed.headingThreshold == max(mixed.body * 1.25, mixed.headingBody * 1.1))
    #expect(mixed.body == max(4, LayoutReconstructor.bodySize(prose + large)))
    #expect(mixed.headingBody == LayoutReconstructor.headingBodySize(large, pageBody: mixed.body))
}

@Test func lineRolesFollowTheHeadingRules() {
    let content = page(prose)
    let typography = PageTypography(page: content)
    func role(_ line: TextLine, on page: PageContent = content, labels: [TextLine] = [], lines: [TextLine]? = nil,
              judges: Bool = false) -> LineRole {
        LayoutReconstructor.role(of: line, on: page, in: lines ?? page.lines, typography: PageTypography(page: page),
                                 labels: labels, judgesTitleWords: judges)
    }
    #expect(role(line("Chapter One", y: 560, size: 13)) == .heading)
    #expect(role(line("Chapter One", y: 560, size: 12)) == .prose)
    #expect(role(line("1 Numbers head too", y: 560, size: 13)) == .heading)
    #expect(role(line(String(repeating: "long ", count: 45), y: 560, size: 13)) == .prose)
    // A lone lowercase display line heads nothing; stacked under a title of its size it is part of it.
    let lowercase = line("pages 2, 4-14", y: 540, size: 14)
    #expect(role(lowercase) == .prose)
    let title = line("From Insects", y: 556, size: 14)
    #expect(role(lowercase, lines: prose + [title, lowercase]) == .heading)
    #expect(role(line("let x = 1", y: 300, monospaced: true)) == .code)
    #expect(role(line("1. First item", y: 300)) == .listItem)
    #expect(role(line("• Bullet", y: 300)) == .listItem)
    #expect(role(line("Plain prose", y: 300)) == .prose)
    // A recurring bold label is a heading whatever its size.
    let label = line("Fighting Filth Flies", y: 300, bold: true)
    #expect(role(label, labels: [label]) == .heading)
    // Synthetic typography supplies no heading or code evidence.
    let synthetic = page(prose, synthetic: true)
    #expect(role(line("Chapter One", y: 560, size: 13), on: synthetic) == .prose)
    #expect(role(line("let x = 1", y: 300, monospaced: true), on: synthetic) == .prose)
    #expect(role(line("1. First item", y: 300), on: synthetic) == .listItem)
    _ = typography
}

@Test func recognizedTitlesMustReadAsWords() throws {
    guard EnglishText.lexiconContains("chapter") == true else { return }
    let recognized = page(prose, recognized: true)
    func role(_ text: String) -> LineRole {
        LayoutReconstructor.role(of: line(text, y: 560, size: 13), on: recognized, in: recognized.lines,
                                 typography: PageTypography(page: recognized), labels: [], judgesTitleWords: true)
    }
    #expect(role("Chapter One") == .heading)
    #expect(role("Xq zzv qpr") == .prose)
    // Without the English gate the same noise would be a heading.
    #expect(LayoutReconstructor.role(of: line("Xq zzv qpr", y: 560, size: 13), on: recognized, in: recognized.lines,
                                     typography: PageTypography(page: recognized), labels: [], judgesTitleWords: false) == .heading)
}

@Test func assemblerBreaksParagraphsOnGeometry() {
    func paragraphs(_ lines: [TextLine]) -> [String] {
        var assembler = BlockAssembler(page: 3, body: 10, hyphens: HyphenContext())
        for line in lines { assembler.append(line, as: .prose) }
        return assembler.finish().map(\.text)
    }
    let first = line("First line of the", y: 500), second = line("paragraph continues", y: 488)
    #expect(paragraphs([first, second]) == ["First line of the paragraph continues"])
    // A gap of nine tenths of the body or more is a paragraph break.
    #expect(paragraphs([first, line("Next paragraph", y: 500 - 12 - 9)]) == ["First line of the", "Next paragraph"])
    // A different column breaks; so does a line the reader says does not wrap.
    #expect(paragraphs([first, line("Other column", x: 60, y: 488)]) == ["First line of the", "Other column"])
    #expect(paragraphs([line("Ends here.", y: 500, wraps: false), second]) == ["Ends here.", "paragraph continues"])
    // A short line ending a sentence closes its paragraph.
    #expect(paragraphs([line("The end.", y: 500, width: 100), second]) == ["The end.", "paragraph continues"])
    #expect(paragraphs([line("The end.", y: 500, width: 250), second]) == ["The end. paragraph continues"])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/57"))
func assemblerJoinsTwoPiecesOfOnePrintedRow() {
    func paragraphs(_ lines: [TextLine]) -> [String] {
        var assembler = BlockAssembler(page: 3, body: 10, hyphens: HyphenContext())
        for line in lines { assembler.append(line, as: .prose) }
        return assembler.finish().map(\.text)
    }
    // PDFKit can report the end of a printed line as a line of its own, a word's width from the
    // line it ends. The two pieces are one paragraph.
    let opening = line("the line ends with the word", y: 500, width: 292)
    #expect(paragraphs([opening, line("told", x: 336, y: 500, width: 16)])
        == ["the line ends with the word told"])
    // A column gutter's width apart they are separate blocks: a table's two cells, or a running
    // header and the folio at the other end of its row.
    #expect(paragraphs([opening, line("told", x: 340, y: 500, width: 16)]).count == 2)
    #expect(paragraphs([opening, line("49", x: 347, y: 500, width: 10)]).count == 2)
    // A short line on its own row still opens its own block, whatever stands above it.
    #expect(paragraphs([opening, line("108", x: 40, y: 470, width: 14)]).count == 2)
    // Only what follows the line joins it; a piece to its left is another block.
    #expect(paragraphs([line("told", x: 336, y: 500, width: 16), opening]).count == 2)
}

@Test func assemblerKeepsCodeIndentationAndListBreaks() {
    var assembler = BlockAssembler(page: 3, body: 10, hyphens: HyphenContext())
    assembler.append(line("func run() {", x: 40, y: 300, monospaced: true), as: .code)
    assembler.append(line("return 1", x: 58, y: 288, monospaced: true), as: .code)
    assembler.append(line("}", x: 40, y: 276, monospaced: true), as: .code)
    assembler.append(line("Prose between.", y: 260), as: .prose)
    assembler.append(line("second block", x: 58, y: 240, monospaced: true), as: .code)
    assembler.append(line("• one", y: 220), as: .listItem)
    assembler.append(line("• two", y: 208), as: .listItem)
    let blocks = assembler.finish()
    #expect(blocks.map(\.text) == ["func run() {\n   return 1\n}", "Prose between.", "second block", "• one", "• two"])
    if case .preformatted = blocks[0].content {} else { Issue.record("code is preformatted") }
    if case .preformatted = blocks[3].content {} else { Issue.record("list items are preformatted") }
}

@Test func assemblerFlushesGroupsInOrderWithStableHeadingIdentifiers() {
    var assembler = BlockAssembler(page: 3, body: 10, hyphens: HyphenContext())
    assembler.append(line("Title", y: 560, size: 14), as: .heading)
    assembler.appendNote(group: 1, line("1. A note that", y: 500))
    assembler.appendNote(group: 1, line("continues.", y: 488))
    assembler.appendNote(group: 2, line("2. Another.", y: 476))
    assembler.appendImage("image-4")
    let tag = TextStructure(group: 7, order: 1, headingLevel: 2)
    assembler.appendTagged(tag, line("Tagged", y: 300))
    assembler.appendTagged(tag, line("heading", y: 288))
    assembler.append(line("Prose", y: 200), as: .prose)
    let blocks = assembler.finish()
    #expect(blocks.map(\.text) == ["Title", "1. A note that continues.", "2. Another.", "", "Tagged heading", "Prose"])
    #expect(blocks[0].content == .heading(id: "heading-3-0", text: InlineText("Title"), level: 2))
    if case .heading(let id, let text, let level) = blocks[4].content {
        #expect(id == "heading-3-4" && text.text == "Tagged heading" && level == 2)
    } else { Issue.record("tagged heading") }
    #expect(blocks[4].structureGroup == 7)
    if case .image(let image) = blocks[3].content { #expect(image.assetID == "image-4") } else { Issue.record("image block") }
}

/// Two type sizes carrying the same weight must not let Dictionary iteration order, which Swift
/// seeds per process, decide a page's body size (#140).
@Test func bodySizeBreaksATieOnTheSmallerTypeDeterministically() {
    #expect(LayoutReconstructor.bodySize(weights: [10: 500, 12: 500]) == 10)
    #expect(LayoutReconstructor.bodySize(weights: [12: 500, 10: 500]) == 10)
    #expect(LayoutReconstructor.bodySize(weights: [9: 300, 11: 300, 24: 299]) == 9)
    // A clear winner still wins, whatever its size.
    #expect(LayoutReconstructor.bodySize(weights: [10: 499, 12: 500]) == 12)
    #expect(LayoutReconstructor.bodySize(weights: [:]) == nil)
    // Insertion order must never change the answer.
    for _ in 0..<64 {
        var weights: [Int: Int] = [:]
        for size in [8, 10, 12, 14, 18].shuffled() { weights[size] = 400 }
        #expect(LayoutReconstructor.bodySize(weights: weights) == 8)
    }
}
