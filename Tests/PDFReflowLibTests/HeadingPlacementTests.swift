import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// Section titles stay with the paragraph they open (#63), and a title set nearly the column's
// width is still a label where the book's typography says so (#73). Source pages are from the
// checksum-pinned FAA handbook; expected text was read against the rendered pages.

private let faaSHA256 = "247929cace0ab56b376e683eba540cc4c8f39f199ab35414e8b604e24f395cb7"

private func faaPage(_ number: Int) throws -> PageContent {
    let fixture = try SourceLayoutFixture.load("faa-\(number)")
    #expect(fixture.sourceSHA256 == faaSHA256)
    return fixture.styledContent()
}

/// The FAA handbook's section-title style: 12-point bold over a 10-point body.
private let faaTitleStyle: LayoutReconstructor.LabelStyle = {
    let line = TextLine(content: InlineText("Human Factors", style: .bold),
                        rect: CGRect(x: 0, y: 0, width: 90, height: 16), fontSize: 12)
    return LayoutReconstructor.LabelStyle(line, body: 10)
}()

/// The pipeline's reconstruction pass: preserved regions, per-page blocks, cross-page joins.
private func reconstruct(_ pages: [PageContent], labelStyles: Set<LayoutReconstructor.LabelStyle> = []) -> [ReflowBlock] {
    var blocks: [ReflowBlock] = []
    var warnings: [ConversionWarning] = []
    var previous: PageContent?
    var previousRegions: [CGRect] = []
    for page in pages {
        let regions = LayoutReconstructor.graphicsWithLabels(page)
        let images = regions.enumerated().map { ($0.element, "image-\(page.number)-\($0.offset)") }
        let pageBlocks = LayoutReconstructor.blocks(page: page, images: images, vocabulary: [],
                                                    warnings: &warnings, labelStyles: labelStyles)
        LayoutReconstructor.appendPage(pageBlocks, page: page, images: regions, previousPage: previous,
            previousImages: previousRegions, to: &blocks, vocabulary: [], warnings: &warnings)
        previous = page
        previousRegions = regions
    }
    return blocks
}

private func kind(_ block: ReflowBlock) -> String {
    switch block.content {
    case .heading: "heading"
    case .paragraph: "paragraph"
    case .image: "image"
    case .sourcePage: "sourcePage"
    default: "other"
    }
}

private func headingTexts(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .heading = $0.content { $0.text } else { nil } }
}

@Test func sourceFAAHeadingsStayWithTheirParagraphAcrossTrailingFigures() throws {
    // Each section opens at the foot of a column and continues on the next page, while a figure
    // and its caption close the page. The figure keeps its place ahead of the joined paragraph;
    // the title moves with the paragraph instead of staying above the figure.
    for (first, title, opening, continuation) in [
        (33, "Selecting a Flight School", "Selecting a flight school is an important consideration",
         "flight training for the private pilot certificate"),
        (49, "Human Factors", "Why are human conditions, such as fatigue", ""),
        (201, "Chapter Summary", "All aircraft have a requirement for essential systems",
         "environmental control systems to support flight"),
    ] {
        let blocks = reconstruct([try faaPage(first), try faaPage(first + 1)])
        let heading = try #require(blocks.firstIndex {
            if case .heading = $0.content { $0.text == title } else { false }
        }, "\(title) is a heading")
        let next = blocks[blocks.index(after: heading)]
        #expect(next.text.hasPrefix(opening), "\(title) is followed by \(next.text.prefix(60))")
        if !continuation.isEmpty {
            #expect(next.text.contains(continuation) && next.sourcePages == [first + 1], "\(title) paragraph joins page \(first + 1): \(next.sourcePages) \(next.text.suffix(80))")
        }
        // The page's figure caption precedes the title and never absorbs it.
        let caption = try #require(blocks.firstIndex { $0.text.hasPrefix("Figure") && $0.page == first && $0.text.contains(title) == false })
        #expect(caption < heading)
        #expect(!blocks.contains { $0.text.hasPrefix("Figure") && $0.text.contains(title) })
    }
}

@Test func joinedParagraphWithoutAHeadingKeepsTrailingBlocksAhead() {
    // Only headings directly above the joined paragraph move; an earlier paragraph stays put.
    let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
    func line(_ text: String, y: CGFloat, width: CGFloat = 480) -> TextLine {
        TextLine(text: text, rect: CGRect(x: 60, y: y, width: width, height: 12), fontSize: 10)
    }
    let previous = PageContent(number: 1, bounds: bounds, lines: [
        line("The section ends a paragraph here.", y: 700, width: 200),
        line("The section continues onto the next page and this contin-", y: 90),
    ], graphics: [])
    let current = PageContent(number: 2, bounds: bounds, lines: [
        line("uation runs on without a break.", y: 720),
    ], graphics: [])
    var blocks = [
        ReflowBlock(content: .sourcePage(1), page: 1),
        ReflowBlock(content: .heading(id: "h", text: InlineText("Section"), level: 2), page: 1),
        ReflowBlock(content: .paragraph(InlineText("The section ends a paragraph here.")), page: 1),
        ReflowBlock(content: .paragraph(InlineText("The section continues onto the next page and this contin-")), page: 1),
        LayoutReconstructor.imageBlock(assetID: "figure", page: 1),
    ]
    var warnings: [ConversionWarning] = []
    LayoutReconstructor.appendPage([ReflowBlock(content: .paragraph(InlineText(
        "uation runs on without a break.")), page: 2)],
        page: current, previousPage: previous, to: &blocks, vocabulary: [], warnings: &warnings)
    #expect(blocks.map(kind) == ["sourcePage", "heading", "paragraph", "image", "paragraph"])
    #expect(blocks.last?.sourcePages == [2])

    // With the heading directly above the continuing paragraph, it moves past the figure.
    var headed = [
        ReflowBlock(content: .sourcePage(1), page: 1),
        ReflowBlock(content: .paragraph(InlineText("The section ends a paragraph here.")), page: 1),
        ReflowBlock(content: .heading(id: "h", text: InlineText("Section"), level: 2), page: 1),
        ReflowBlock(content: .paragraph(InlineText("The section continues onto the next page and this contin-")), page: 1),
        LayoutReconstructor.imageBlock(assetID: "figure", page: 1),
    ]
    LayoutReconstructor.appendPage([ReflowBlock(content: .paragraph(InlineText(
        "uation runs on without a break.")), page: 2)],
        page: current, previousPage: previous, to: &headed, vocabulary: [], warnings: &warnings)
    #expect(headed.map(kind) == ["sourcePage", "paragraph", "image", "heading", "paragraph"])
}

@Test func captionEndsAtALargerTitleButKeepsItsWrappedLines() {
    let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
    var body: [TextLine] = []
    for index in 0..<8 {
        body.append(TextLine(text: "Body prose runs across the column in ordinary ten point type line \(index)",
            rect: CGRect(x: 60, y: 700 - CGFloat(index) * 12, width: 480, height: 12), fontSize: 10))
    }
    // A caption whose lines fill most of the column, a title set directly beneath it with no
    // clear space, and the title's body. Neither a short last line nor a label test splits them.
    let caption = TextLine(content: InlineText(elements: [.text("Figure 1-1.", .bold),
        .text(" A caption that runs across most of the column and", .italic)]),
        rect: CGRect(x: 60, y: 400, width: 420, height: 11), fontSize: 8)
    let wrapped = TextLine(content: InlineText("wraps onto a second line of the caption.", style: .italic),
        rect: CGRect(x: 60, y: 389, width: 400, height: 11), fontSize: 9)
    let title = TextLine(content: InlineText("Section Title Set Wide Across The Column", style: .bold),
        rect: CGRect(x: 60, y: 374, width: 470, height: 16), fontSize: 12)
    let opening = TextLine(text: "The section's own prose begins under its title here.",
        rect: CGRect(x: 60, y: 361, width: 480, height: 12), fontSize: 10)
    let page = PageContent(number: 5, bounds: bounds, lines: body + [caption, wrapped, title, opening], graphics: [])
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings)
    let texts = blocks.map(\.text)
    #expect(texts.contains("Figure 1-1. A caption that runs across most of the column and wraps onto a second line of the caption."))
    #expect(!texts.contains { $0.hasPrefix("Figure") && $0.contains("Section Title") })
}

@Test func sourceFAAWideTwoLineTitleIsOneHeadingOnlyWithTheBookLabelStyle() throws {
    let page = try faaPage(43)
    let title = "Crew Resource Management (CRM) and Single-Pilot Resource Management"
    // The first line runs 95% of the column's prose, so the page alone does not make it a label.
    #expect(!headingTexts(reconstruct([page])).contains(title))
    let blocks = reconstruct([page], labelStyles: [faaTitleStyle])
    #expect(headingTexts(blocks).contains(title))
    let index = try #require(blocks.firstIndex { $0.text == title })
    #expect(blocks[index + 1].text.hasPrefix("While CRM focuses on pilots operating in crew environments"))
    // The page's narrower title is unchanged either way.
    #expect(headingTexts(blocks).contains("Hazard and Risk"))
    #expect(headingTexts(reconstruct([page])).contains("Hazard and Risk"))
}

@Test func wideLabelStyleStillNeedsEveryOtherLabelTest() throws {
    var page = try faaPage(43)
    let index = try #require(page.lines.firstIndex { $0.text == "Crew Resource Management (CRM) and" })
    let original = page.lines[index]
    // A sentence, a line wider than the column's prose and a different style stay prose.
    for replacement in [
        TextLine(content: InlineText("Crew Resource Management (CRM) ends here.", style: .bold),
                 rect: original.rect, fontSize: 12),
        TextLine(content: InlineText("Crew Resource Management (CRM) and", style: .bold),
                 rect: CGRect(x: original.rect.minX, y: original.rect.minY, width: 260, height: original.rect.height), fontSize: 12),
        TextLine(content: InlineText("Crew Resource Management (CRM) and"),
                 rect: original.rect, fontSize: 12),
    ] {
        page.lines[index] = replacement
        let labels = LayoutReconstructor.sectionLabels(in: page.lines, body: 10, headingThreshold: 12.5,
                                                       page: page, styles: [faaTitleStyle])
        #expect(!labels.contains(replacement), "\(replacement.text) width \(replacement.rect.width)")
    }
    page.lines[index] = original
    let labels = LayoutReconstructor.sectionLabels(in: page.lines, body: 10, headingThreshold: 12.5,
                                                   page: page, styles: [faaTitleStyle])
    #expect(labels.map(\.text).contains("Crew Resource Management (CRM) and"))
    #expect(labels.map(\.text).contains("Single-Pilot Resource Management"))
}

@Test func labelEvidenceComesFromNarrowTitlesOnThreePages() throws {
    var pages: [LayoutReconstructor.LabelStyle: Int] = [:]
    for number in [33, 49, 201] {
        let evidence = LayoutReconstructor.labelEvidence(on: try faaPage(number))
        #expect(evidence.contains(faaTitleStyle), "page \(number)")
        for style in evidence { pages[style, default: 0] += 1 }
        #expect(LayoutReconstructor.labelStyles(from: pages).contains(faaTitleStyle) == (number == 201))
    }
    // Recognized pages have no typography to trust and give no evidence.
    var recognized = try faaPage(33)
    recognized.recognized = true
    #expect(LayoutReconstructor.labelEvidence(on: recognized).isEmpty)
}
