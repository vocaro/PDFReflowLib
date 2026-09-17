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

// Sub-headings set at body size or barely above it (#76). The FAA handbook sets them in 10-point
// Helvetica-Bold and 11-point Times-BoldItalic over its 10-point Times body, one line above the
// paragraph they open. Where tags group them (pages 91 and 199) they stayed separate; on the
// untagged pages 136, 156, 159, 165 and 262 they read into that paragraph.

private func faaStyle(_ size: CGFloat, italic: Bool = false) -> LayoutReconstructor.LabelStyle {
    let line = TextLine(content: InlineText("Radius of Turn", style: italic ? [.bold, .italic] : .bold),
                        rect: CGRect(x: 0, y: 0, width: 70, height: 13), fontSize: size)
    return LayoutReconstructor.LabelStyle(line, body: 10)
}

private let faaSubheadingStyles: Set<LayoutReconstructor.LabelStyle> = [faaStyle(10), faaStyle(11, italic: true)]

@Test func sourceFAASubheadingsOpenTheirParagraphsOnlyWithTheBookStyle() throws {
    for (number, cases) in [
        (136, [("Radius of Turn", "The radius of turn is directly linked to the ROT")]),
        (156, [("Rudder", "The rudder controls movement of the aircraft about its vertical axis"),
               ("V-Tail", "The V-tail design utilizes two slanted tail surfaces"),
               ("Secondary Flight Controls", "Secondary flight control systems may consist of wing flaps"),
               ("Flaps", "Flaps are the most common high-lift devices")]),
        (159, [("Balance Tabs", "The control forces may be excessively high"),
               ("Servo Tabs", "Servo tabs are very similar in operation"),
               ("Antiservo Tabs", "Antiservo tabs work in the same manner"),
               ("Ground Adjustable Tabs", "Many small aircraft have a nonmovable metal trim tab")]),
        (165, [("Fixed-Pitch Propeller", "A propeller with fixed blade angles is a fixed-pitch propeller.")]),
        (262, [("Climb Performance", "If an aircraft is to move, fly, and perform")]),
    ] {
        let page = try faaPage(number)
        // The page alone: each sub-heading is the opening words of its paragraph.
        let plain = reconstruct([page])
        for (title, opening) in cases {
            #expect(!headingTexts(plain).contains(title), "page \(number): \(title)")
            #expect(plain.contains { $0.text.hasPrefix(title + " " + opening) }, "page \(number): \(title) runs in")
        }
        let blocks = reconstruct([page], labelStyles: faaSubheadingStyles)
        for (title, opening) in cases {
            let index = try #require(blocks.firstIndex {
                if case .heading = $0.content { $0.text == title } else { false }
            }, "page \(number): \(title) is a heading")
            #expect(blocks[index + 1].text.hasPrefix(opening), "page \(number): \(title) opens \(blocks[index + 1].text.prefix(60))")
            #expect(blocks[index].headingSize != nil)
        }
        #expect(blocks.map(\.text).joined(separator: " ") == plain.map(\.text).joined(separator: " "),
                "page \(number): only block boundaries change")
    }
}

@Test func sourceFAATaggedPageSubheadingsReadTheSameWithoutTags() throws {
    // Pages 91 and 199 set the same styles; their fixtures carry no tags, so the spatial reading
    // alone must agree with the separate lines the tagged pages already had.
    for (number, titles) in [(91, ["Pressure Altitude", "Density Altitude", "Effect of Pressure on Density",
                                   "Effect of Temperature on Density"]),
                             (199, ["Pulse Oximeters", "Servicing of Oxygen Systems"])] {
        let found = headingTexts(reconstruct([try faaPage(number)], labelStyles: faaSubheadingStyles))
        for title in titles { #expect(found.contains(title), "page \(number): \(title) in \(found)") }
    }
    // The wide 12-point titles of #73 are unchanged beside the sub-heading styles.
    let wide = headingTexts(reconstruct([try faaPage(43)], labelStyles: faaSubheadingStyles.union([faaTitleStyle])))
    #expect(wide.contains("Crew Resource Management (CRM) and Single-Pilot Resource Management"))
    #expect(wide.contains("Hazard and Risk"))
}

@Test func subheadingNeedsBoldStyleClearSpaceAndAParagraphBeneath() throws {
    let page = try faaPage(165)
    let index = try #require(page.lines.firstIndex { $0.text == "Fixed-Pitch Propeller" })
    let below = try #require(page.lines.firstIndex { $0.text.hasPrefix("A propeller with fixed blade angles") })
    let original = page.lines[index], opening = page.lines[below]
    func labels(_ page: PageContent, styles: Set<LayoutReconstructor.LabelStyle> = faaSubheadingStyles) -> [String] {
        LayoutReconstructor.sectionLabels(in: page.lines, body: 10, headingThreshold: 12.5, page: page, styles: styles).map(\.text)
    }
    #expect(labels(page).contains("Fixed-Pitch Propeller"))
    // Only a style the book repeats counts, and recording admits the line without one.
    #expect(!labels(page, styles: [faaTitleStyle]).contains("Fixed-Pitch Propeller"))
    #expect(LayoutReconstructor.sectionLabels(in: page.lines, body: 10, headingThreshold: 12.5, page: page,
                                              recordingSubheadings: true).map(\.text).contains("Fixed-Pitch Propeller"))
    // Plain type, sentence punctuation, a line as wide as the prose, and a size below the body,
    // each even with its own style supplied.
    for replacement in [
        TextLine(text: "Fixed-Pitch Propeller", rect: original.rect, fontSize: 11),
        TextLine(content: InlineText("Fixed-Pitch Propeller.", style: [.bold, .italic]), rect: original.rect, fontSize: 11),
        TextLine(content: InlineText("Fixed-Pitch Propeller", style: [.bold, .italic]),
                 rect: CGRect(x: original.rect.minX, y: original.rect.minY, width: 230, height: original.rect.height), fontSize: 11),
        TextLine(content: InlineText("Fixed-Pitch Propeller", style: .bold), rect: original.rect, fontSize: 9),
    ] {
        var changed = page
        changed.lines[index] = replacement
        #expect(!labels(changed, styles: faaSubheadingStyles.union([LayoutReconstructor.LabelStyle(replacement, body: 10)]))
            .contains(replacement.text), "\(replacement.text) \(replacement.fontSize) \(replacement.rect.width)")
    }
    // The line beneath must open a paragraph on the label's edge, in ordinary body type, directly under it.
    for replacement in [
        TextLine(text: opening.text, rect: opening.rect.offsetBy(dx: 20, dy: 0), fontSize: 10),
        TextLine(content: InlineText(opening.text, style: .bold), rect: opening.rect, fontSize: 10),
        TextLine(text: opening.text, rect: opening.rect.offsetBy(dx: 0, dy: -12), fontSize: 10),
    ] {
        var changed = page
        changed.lines[below] = replacement
        #expect(!labels(changed).contains("Fixed-Pitch Propeller"), "beneath: \(replacement.rect)")
    }
    // Without clear space above, it is a line of the paragraph over it.
    var crowded = page
    crowded.lines[index].rect.origin.y += 10
    crowded.lines[below].rect.origin.y += 10
    #expect(!labels(crowded).contains("Fixed-Pitch Propeller"))
}

@Test func subheadingEvidenceRecordsTheBookStylesAndRanksBelowTitles() throws {
    var pages: [LayoutReconstructor.LabelStyle: Int] = [:]
    // Each page records the styles of its own sub-headings; a style counts from its third page.
    for (number, recorded) in [(136, [faaStyle(10)]), (165, [faaStyle(11, italic: true)]), (262, [faaStyle(10)]),
                               (159, [faaStyle(11, italic: true)]), (199, [faaStyle(10)])] {
        let evidence = LayoutReconstructor.labelEvidence(on: try faaPage(number))
        #expect(evidence == Set(recorded), "page \(number): \(evidence)")
        for style in evidence { pages[style, default: 0] += 1 }
    }
    #expect(LayoutReconstructor.labelStyles(from: pages) == [faaStyle(10)])
    for style in LayoutReconstructor.labelEvidence(on: try faaPage(156)) { pages[style, default: 0] += 1 }
    #expect(LayoutReconstructor.labelStyles(from: pages) == faaSubheadingStyles)
    // Heading levels: the 12-point titles rank above both sub-heading tiers.
    var blocks = reconstruct([try faaPage(43)], labelStyles: [faaTitleStyle])
        + reconstruct([try faaPage(165), try faaPage(262)], labelStyles: faaSubheadingStyles)
    LayoutReconstructor.rankHeadingLevels(&blocks)
    func level(_ title: String) -> Int? {
        blocks.lazy.compactMap { block -> Int? in
            if case let .heading(_, text, level) = block.content, text.text == title { level } else { nil }
        }.first
    }
    let title = try #require(level("Hazard and Risk"))
    let italic = try #require(level("Fixed-Pitch Propeller"))
    let bold = try #require(level("Climb Performance"))
    #expect(title < italic && italic <= bold, "\(title) \(italic) \(bold)")
}

// A caption ends at its own last line when the next line leaves its alignment (#82). FAA page
// 159 carries a `Figure 5-16.` caption the page never paints (it lies outside the placed
// figure's clip), indented 3.5 points from the body text set 2.8 points beneath it.

@Test func sourceFAACaptionEndsWhereBodyTextLeavesItsAlignment() throws {
    let texts = reconstruct([try faaPage(159)]).map(\.text)
    let caption = try #require(texts.firstIndex { $0.hasPrefix("Figure 5-16.") })
    #expect(texts[caption] == "Figure 5-16. The movement of the elevator is opposite to the direction of movement of the elevator trim tab.")
    #expect(texts[caption + 1].hasPrefix("control pressures that may exist for that flight condition."))
    #expect(texts.contains("Figure 6-20. The movement of the elevator is opposite to the direction of movement of the elevator trim tab."))
    // Wrapped captions whose lines grow from the 8-point label line to 9-point text stay whole.
    for (number, opening, ending) in [
        (107, "Figure 5-15. When the vortices of larger aircraft sink close to the ground", "toward another runway (bottom)."),
        (343, "Figure 14-11. (A) Taxiway Bravo location sign", ""),
    ] {
        let page = try faaPage(number)
        let found = try #require(reconstruct([page]).map(\.text).first { $0.hasPrefix(opening) }, "page \(number)")
        let first = try #require(page.lines.first { $0.text.hasPrefix(String(opening.prefix(12))) })
        // Every 9-point line set beneath the caption on its left edge belongs to it.
        let wrapped = page.lines.filter {
            $0.fontSize == 9 && abs($0.rect.minX - first.rect.minX) < 1 && $0.rect.maxY <= first.rect.minY + 2
                && first.rect.minY - $0.rect.maxY < 40
        }
        #expect(!wrapped.isEmpty, "page \(number)")
        for line in wrapped { #expect(found.contains(line.text.prefix(30)), "page \(number): \(line.text)") }
        if !ending.isEmpty { #expect(found.hasSuffix(ending), "page \(number): \(found.suffix(80))") }
    }
}

@Test func captionKeepsABodySizeLineOnItsOwnEdge() {
    // The alignment rule alone: the same 9 → 10 point step continues a caption when the line
    // keeps its left edge, and ends it when the line starts and centres elsewhere.
    let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
    var body: [TextLine] = []
    for index in 0..<8 {
        body.append(TextLine(text: "Body prose runs across the column in ordinary ten point type line \(index)",
            rect: CGRect(x: 72, y: 700 - CGFloat(index) * 12.5, width: 237, height: 11.5), fontSize: 10))
    }
    func blocks(captionX: CGFloat) -> [String] {
        let caption = TextLine(text: "Figure 5-16. The movement of the elevator is opposite to the",
            rect: CGRect(x: captionX, y: 426, width: 220, height: 9.9), fontSize: 9)
        let wrapped = TextLine(text: "direction of movement of the elevator trim tab.",
            rect: CGRect(x: captionX, y: 415.2, width: 166.7, height: 9.7), fontSize: 9)
        let next = TextLine(text: "control pressures that may exist for that flight condition. As",
            rect: CGRect(x: 72, y: 400.9, width: 237, height: 11.5), fontSize: 10)
        let page = PageContent(number: 159, bounds: bounds, lines: body + [caption, wrapped, next], graphics: [])
        var warnings: [ConversionWarning] = []
        return LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings).map(\.text)
    }
    #expect(blocks(captionX: 75.5).contains("Figure 5-16. The movement of the elevator is opposite to the direction of movement of the elevator trim tab."))
    #expect(blocks(captionX: 72).contains { $0.hasPrefix("Figure 5-16.") && $0.contains("control pressures") })
}
