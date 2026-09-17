import Foundation
import CoreGraphics
import Testing
@testable import PDFReflowLib

// Academic front matter and algorithm floats (#43): the rotated arXiv stamp, heading levels
// ranked by size, modest-size section labels, and listings kept whole. Replay Clocks pages
// 1, 3 and 4 are checksum-pinned source extractions; controls come from other books.

/// One page's blocks with heading levels ranked as the pipeline ranks them over a document.
private func reconstruct(_ page: PageContent) -> (blocks: [ReflowBlock], images: [CGRect], warnings: [ConversionWarning]) {
    let regions = LayoutReconstructor.graphicsWithLabels(page)
    var warnings: [ConversionWarning] = []
    var blocks = LayoutReconstructor.blocks(page: page, images: regions.enumerated().map { ($0.element, "image-\($0.offset)") },
        vocabulary: LayoutReconstructor.vocabulary(in: [page]), warnings: &warnings)
    LayoutReconstructor.rankHeadingLevels(&blocks)
    return (blocks, regions, warnings)
}

private func headings(_ blocks: [ReflowBlock]) -> [(text: String, level: Int)] {
    blocks.compactMap { if case let .heading(_, text, level) = $0.content { (text.text, level) } else { nil } }
}

private func paragraphs(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .paragraph = $0.content { $0.text } else { nil } }
}

private let letter = CGRect(x: 0, y: 0, width: 612, height: 792)

@Test func replayFrontMatterDropsTheStampAndRanksTitleAboveAuthorsAndLabels() throws {
    let page = try SourceLayoutFixture.load("replay-1").content()
    let (blocks, _, warnings) = reconstruct(page)
    let found = headings(blocks)
    #expect(found.map(\.text) == ["Replay Clocks", "Ishaan Lagwankar", "ABSTRACT", "1 INTRODUCTION", "Sandeep S Kulkarni"])
    #expect(found.map(\.level) == [2, 3, 4, 4, 3])
    #expect(!blocks.contains { $0.text.contains("arXiv:2311.07842v1") })
    #expect(warnings.contains { $0.code == .furnitureRemoved && $0.page == 1 && $0.message.contains("Rotated") })
    let body = paragraphs(blocks)
    #expect(body.contains { $0.hasPrefix("In this work, we focus on the problem of replay clocks") })
    #expect(body.contains { $0.hasPrefix("According to the observer effect") })
    #expect(!body.contains { $0.contains("ABSTRACT") || $0.contains("INTRODUCTION") })
    #expect(body.filter { $0.hasPrefix("Michigan State University") }.count == 2)
    #expect(body.contains { $0.hasPrefix("As an illustration, consider two drones") })
    // The reference-format block and e-mail lines are smaller than the body, not labels.
    #expect(body.contains { $0.hasPrefix("ACM Reference Format:") })
}

@Test func replaySectionPagesJoinSplitNumbersAndKeepListingsWhole() throws {
    let page = try SourceLayoutFixture.load("replay-3").content()
    let (blocks, images, _) = reconstruct(page)
    let found = headings(blocks)
    #expect(found.map(\.text) == ["3.1 Limitations of Existing Clocks for Replay", "3.2 Requirements of Replay Clock RepCl",
                                  "4 ALGORITHM FOR REPLAY CLOCK (REPCL)"])
    #expect(found.allSatisfy { $0.level == 2 })
    #expect(!paragraphs(blocks).contains("3.1"))
    #expect(!paragraphs(blocks).contains { $0.hasPrefix("Limitations of") || $0.hasPrefix("4 ALGORITHM") })
    #expect(paragraphs(blocks).contains { $0.hasPrefix("As an example, consider the execution in Figure 1.") })
    // The running header is not a heading and stays out of the label rule (smaller than the body).
    #expect(!found.contains { $0.text == "Replay Clocks" })
    // Algorithm 1: the caption reflows, the listing between the rules is one crop.
    let floats = LayoutReconstructor.algorithmFloats(in: page)
    #expect(floats.regions.count == 1)
    #expect(floats.decorations.count == 1)
    let caption = try #require(page.lines.first { $0.text == "Algorithm 1 ReplayEvents Operation" })
    #expect(paragraphs(blocks).contains(caption.text))
    let listing = page.lines.filter { $0.rect.minY > 466 && $0.rect.maxY < 536 && $0.rect.maxX < 300 }
    #expect(listing.count == 9)
    let crop = try #require(images.first { $0.contains(floats.regions[0]) })
    #expect(listing.allSatisfy { crop.contains($0.rect) })
    #expect(!crop.intersects(caption.rect))
    #expect(crop.height < 90)
}

@Test func replayPageFourKeepsThreeAlgorithmFloatsWithCaptionsAsText() throws {
    let page = try SourceLayoutFixture.load("replay-4").content()
    let (blocks, images, _) = reconstruct(page)
    let floats = LayoutReconstructor.algorithmFloats(in: page)
    #expect(floats.regions.count == 3)
    for caption in ["Algorithm 2 Shift Operation", "Algorithm 3 Send Message", "Algorithm 4 Receive Message"] {
        #expect(paragraphs(blocks).contains(caption))
    }
    // The prose reference "… in Algorithm 2." is not a caption, and no caption is inside a crop.
    #expect(paragraphs(blocks).contains { $0.hasSuffix("Algorithm 2.") })
    for line in page.lines where line.text.hasPrefix("Algorithm") {
        #expect(!floats.regions.contains { $0.intersects(line.rect) })
    }
    let numbered = page.lines.filter { $0.text.range(of: #"^\d+:"#, options: .regularExpression) != nil }
    #expect(numbered.count == 32)
    #expect(numbered.allSatisfy { line in images.contains { $0.contains(line.rect) } })
    #expect(images.filter { crop in numbered.contains { crop.contains($0.rect) } }.count == 3)
    #expect(headings(blocks).map(\.text) == ["5 PROPERTIES OF REPCL"])
    #expect(paragraphs(blocks).contains { $0.hasPrefix("The MergeSameEpoch function takes two timestamps") })
}

private func floatPage(caption: String = "Algorithm 1 Replay", closing: Bool = true, captionBelowRule: Bool = true,
                       extent: CGFloat = 244) -> PageContent {
    var lines = [TextLine(text: caption, rect: CGRect(x: 52, y: 541, width: 140, height: 8.5), fontSize: 9)]
    lines += (0..<3).map {
        TextLine(text: "\($0 + 1): step \($0 + 1) of the listing", rect: CGRect(x: 60, y: 520 - CGFloat($0) * 11, width: 100, height: 8.5), fontSize: 7)
    }
    lines.append(TextLine(text: "Body prose continues beneath the float and must remain a paragraph.",
                          rect: CGRect(x: 52, y: 470, width: 240, height: 8.4), fontSize: 9))
    var graphics = [CGRect(x: 50, y: captionBelowRule ? 550 : 562, width: 244, height: 4), CGRect(x: 50, y: 536.7, width: 244, height: 4)]
    if closing { graphics.append(CGRect(x: 50, y: 490, width: extent, height: 4)) }
    return PageContent(number: 1, bounds: letter, lines: lines, graphics: graphics)
}

@Test func algorithmFloatNeedsACaptionBetweenRulesAndAClosingRuleOfTheSameExtent() {
    let floats = LayoutReconstructor.algorithmFloats(in: floatPage())
    #expect(floats.regions.count == 1)
    #expect(floats.regions[0].minY < 492 && floats.regions[0].maxY > 538 && floats.regions[0].maxY < 541)
    #expect(floats.decorations == [CGRect(x: 50, y: 550, width: 244, height: 4)])
    let (blocks, images, _) = reconstruct(floatPage())
    #expect(paragraphs(blocks) == ["Algorithm 1 Replay", "Body prose continues beneath the float and must remain a paragraph."])
    #expect(images.count == 1)
    #expect(blocks.filter { if case .preformatted = $0.content { true } else { false } }.isEmpty)
    for page in [floatPage(closing: false), floatPage(captionBelowRule: false), floatPage(caption: "Table 1 Results"),
                 floatPage(caption: "Algorithm listing"), floatPage(extent: 120)] {
        #expect(LayoutReconstructor.algorithmFloats(in: page).regions.isEmpty)
    }
    // Without the float rule the numbered lines reflow as text (colon markers are not list
    // items) and only the two rules are preserved.
    let open = reconstruct(floatPage(closing: false))
    #expect(open.images.allSatisfy { LayoutReconstructor.isThinRule($0) })
    #expect(paragraphs(open.blocks).contains { $0.hasPrefix("1: step 1 of the listing") })
}

@Test func derivationAndTablePagesHaveNoAlgorithmFloats() throws {
    for name in ["algebra-289", "algebra-16", "flag-27", "usgs-1", "nbs-7"] {
        let page = try SourceLayoutFixture.load(name).content()
        #expect(LayoutReconstructor.algorithmFloats(in: page).regions.isEmpty, "\(name)")
    }
}

@Test func rotatedMarginLinesAreStampsOnlyBesideHorizontalText() {
    let prose = (0..<8).map {
        TextLine(text: "Ordinary body prose line number \($0) fills the measure of the column here.",
                 rect: CGRect(x: 60, y: 700 - CGFloat($0) * 12, width: 400, height: 10), fontSize: 10)
    }
    let stamp = TextLine(text: "arXiv:2311.07842v1 [cs.DC] 14 Nov 2023", rect: CGRect(x: 17, y: 232, width: 20, height: 353), fontSize: 20)
    let page = PageContent(number: 1, bounds: letter, lines: prose + [stamp], graphics: [])
    #expect(LayoutReconstructor.rotatedMarginLines(page) == [stamp])
    let (blocks, _, warnings) = reconstruct(page)
    #expect(!blocks.contains { $0.text.contains("arXiv") })
    #expect(headings(blocks).isEmpty)
    #expect(warnings.contains { $0.code == .furnitureRemoved })
    // A right-margin stamp is furniture too; an ordinary page reports nothing.
    let right = TextLine(text: stamp.text, rect: CGRect(x: 580, y: 232, width: 20, height: 353), fontSize: 20)
    #expect(LayoutReconstructor.rotatedMarginLines(PageContent(number: 1, bounds: letter, lines: prose + [right], graphics: [])) == [right])
    #expect(reconstruct(PageContent(number: 1, bounds: letter, lines: prose, graphics: [])).warnings.isEmpty)
    // A rotated label inside the text area is kept, as a paragraph rather than a heading.
    let inner = TextLine(text: "Rotated axis label", rect: CGRect(x: 300, y: 300, width: 20, height: 150), fontSize: 20)
    let innerPage = PageContent(number: 1, bounds: letter, lines: prose + [inner], graphics: [])
    #expect(LayoutReconstructor.rotatedMarginLines(innerPage).isEmpty)
    let innerBlocks = reconstruct(innerPage).blocks
    #expect(headings(innerBlocks).isEmpty)
    #expect(paragraphs(innerBlocks).contains("Rotated axis label"))
    // A short rotated credit beside a photograph (the 9/11 report's "© Reuters 2004") stays a
    // paragraph in the margin; only a line along a quarter of the page height is a stamp.
    let credit = TextLine(text: "© Reuters 2004", rect: CGRect(x: 17, y: 400, width: 9, height: 60), fontSize: 8)
    let creditPage = PageContent(number: 1, bounds: letter, lines: prose + [credit], graphics: [])
    #expect(LayoutReconstructor.rotatedMarginLines(creditPage).isEmpty)
    #expect(paragraphs(reconstruct(creditPage).blocks).contains("© Reuters 2004"))
    #expect(reconstruct(creditPage).warnings.isEmpty)
    // A rotated page (every line tall) has no stamp, and a two-character margin mark is not one.
    let rotated = prose.map { line in
        TextLine(text: line.text, rect: CGRect(x: line.rect.minY, y: line.rect.minX, width: line.rect.height, height: line.rect.width), fontSize: 10)
    }
    #expect(LayoutReconstructor.rotatedMarginLines(PageContent(number: 1, bounds: letter, lines: rotated, graphics: [])).isEmpty)
    let mark = TextLine(text: "A1", rect: CGRect(x: 17, y: 400, width: 20, height: 70), fontSize: 20)
    #expect(LayoutReconstructor.rotatedMarginLines(PageContent(number: 1, bounds: letter, lines: prose + [mark], graphics: [])).isEmpty)
}

@Test func headingTiersRankDistinctSizesAndKeepCloseSizesTogether() {
    #expect(LayoutReconstructor.headingTiers([17.22, 11.96, 11.96, 10.91, 17.3]) == [17.3, 11.96, 10.91])
    #expect(LayoutReconstructor.headingTiers([]).isEmpty)
    #expect(LayoutReconstructor.headingTiers([14, 13.5, 13.2]) == [14])
    // Title 24, section 14, label 12 over 10-point prose: levels 2, 3 and 4; equal sizes share a level.
    var lines = (0..<6).map {
        TextLine(text: "Ordinary body prose remains a paragraph beneath the ranked headings of the page.",
                 rect: CGRect(x: 60, y: 520 - CGFloat($0) * 13, width: 420, height: 10), fontSize: 10)
    }
    lines.append(TextLine(text: "Chapter Title", rect: CGRect(x: 60, y: 700, width: 200, height: 24), fontSize: 24))
    lines.append(TextLine(text: "Continued Title", rect: CGRect(x: 60, y: 672, width: 220, height: 24), fontSize: 24))
    lines.append(TextLine(text: "A Section Heading", rect: CGRect(x: 60, y: 620, width: 180, height: 14), fontSize: 14))
    lines.append(TextLine(text: "1.1 Label", rect: CGRect(x: 60, y: 560, width: 60, height: 12), fontSize: 12))
    let opening = PageContent(number: 1, bounds: letter, lines: lines, graphics: [])
    let found = headings(reconstruct(opening).blocks)
    // The two stacked 24-point lines are one title (#55).
    #expect(found.map(\.text) == ["Chapter Title Continued Title", "A Section Heading", "1.1 Label"])
    #expect(found.map(\.level) == [2, 3, 4])
    // Ranking is document-wide: a later page carrying only the 12-point label style gets the
    // same level as the opening page's label, not level 2 as it would alone.
    var later = lines.filter { $0.fontSize == 10 }
    later.append(TextLine(text: "1.2 Another Label", rect: CGRect(x: 60, y: 560, width: 100, height: 12), fontSize: 12))
    let secondPage = PageContent(number: 2, bounds: letter, lines: later, graphics: [])
    #expect(headings(reconstruct(secondPage).blocks).map(\.level) == [2])
    var warnings: [ConversionWarning] = []
    var document = LayoutReconstructor.blocks(page: opening, images: [], vocabulary: [], warnings: &warnings)
        + LayoutReconstructor.blocks(page: secondPage, images: [], vocabulary: [], warnings: &warnings)
    // A tagged heading carries no size and keeps its validated level through the ranking.
    document.append(ReflowBlock(content: .heading(id: "tagged", text: InlineText("Tagged section"), level: 1), page: 2))
    LayoutReconstructor.rankHeadingLevels(&document)
    #expect(headings(document).map { ($0.text, $0.level) }.map { "\($0.0)=\($0.1)" }
            == ["Chapter Title Continued Title=2", "A Section Heading=3", "1.1 Label=4", "1.2 Another Label=4", "Tagged section=1"])
    // A document whose typographic headings share one size gets level 2 for all of them.
    var single = LayoutReconstructor.blocks(page: secondPage, images: [], vocabulary: [], warnings: &warnings)
    single += LayoutReconstructor.blocks(page: secondPage, images: [], vocabulary: [], warnings: &warnings)
    LayoutReconstructor.rankHeadingLevels(&single)
    #expect(headings(single).map(\.level) == [2, 2])
    #expect(single.compactMap(\.headingSize) == [12, 12])
}

private func labelPage(_ label: String, size: CGFloat = 11, width: CGFloat = 80, gapAbove: CGFloat = 12, gapBelow: CGFloat = 4,
                       recognized: Bool = false) -> PageContent {
    var lines = (0..<4).map {
        TextLine(text: "Prose above the label runs to the full measure of the column and wraps normally.",
                 rect: CGRect(x: 60, y: 700 - CGFloat($0) * 12, width: 300, height: 9), fontSize: 9)
    }
    let top = 700 - 3 * 12.0 - gapAbove - size
    lines.append(TextLine(text: label, rect: CGRect(x: 60, y: top, width: width, height: size), fontSize: size))
    lines += (0..<4).map {
        TextLine(text: "Prose below the label also runs to the full measure of the column and wraps.",
                 rect: CGRect(x: 60, y: top - gapBelow - 9 - CGFloat($0) * 12, width: 300, height: 9), fontSize: 9)
    }
    var page = PageContent(number: 1, bounds: letter, lines: lines, graphics: [])
    page.recognized = recognized
    return page
}

@Test func sectionLabelsNeedSizeShapeAndClearSpaceAbove() {
    #expect(headings(reconstruct(labelPage("ABSTRACT")).blocks).map(\.text) == ["ABSTRACT"])
    #expect(headings(reconstruct(labelPage("1 INTRODUCTION", width: 100)).blocks).map(\.text) == ["1 INTRODUCTION"])
    #expect(headings(reconstruct(labelPage("3.2 Requirements of Replay", width: 180)).blocks).map(\.text) == ["3.2 Requirements of Replay"])
    // A full-measure mixed-case line is prose even with space above; capitals carry the width.
    #expect(headings(reconstruct(labelPage("Requirements of the replay clock are listed", width: 300)).blocks).isEmpty)
    #expect(headings(reconstruct(labelPage("4 ALGORITHM FOR REPLAY CLOCK (REPCL)", width: 300)).blocks).map(\.text)
            == ["4 ALGORITHM FOR REPLAY CLOCK (REPCL)"])
    // Sentence punctuation, a lowercase start, ordinary leading above, body size or a
    // recognized page keep the line in its paragraph.
    for page in [labelPage("The plasma."), labelPage("the plasma"), labelPage("ABSTRACT", gapAbove: 3),
                 labelPage("ABSTRACT", size: 9), labelPage("ABSTRACT", size: 10), labelPage("ABSTRACT", recognized: true),
                 labelPage("Note:"), labelPage("A"), labelPage("1) 6p− 42"), labelPage("1. “WE HAVE SOME PLANES” 1", width: 200),
                 labelPage("• Bulleted item")] {
        #expect(headings(reconstruct(page).blocks).isEmpty, Comment(rawValue: page.lines[4].text))
    }
    // A bare number is a label only as a dotted section number; a lone folio is not.
    #expect(headings(reconstruct(labelPage("339", width: 20)).blocks).isEmpty)
    // One label ending in a folio is a heading; three make a table of contents, which has none.
    #expect(headings(reconstruct(labelPage("Notes 449", width: 70)).blocks).map(\.text) == ["Notes 449"])
    var contents = labelPage("Appendix A: Common Abbreviations 429", width: 200)
    let entry = contents.lines[4].rect
    for (offset, text) in ["Appendix B: Table of Names 431", "Notes 449"].enumerated() {
        contents.lines.insert(TextLine(text: text, rect: CGRect(x: 60, y: entry.minY - 13 * CGFloat(offset + 1), width: 150, height: 11),
                                       fontSize: 11), at: 5 + offset)
    }
    #expect(headings(reconstruct(contents).blocks).isEmpty)
    // A second label line directly beneath the first continues the heading at the same size,
    // and the two lines are one heading (#55).
    var page = labelPage("6 REPRESENTATION OF REPCL AND ITS", width: 240)
    let first = page.lines[4].rect
    page.lines.insert(TextLine(text: "OVERHEAD", rect: CGRect(x: 60, y: first.minY - 13, width: 60, height: 11), fontSize: 11), at: 5)
    #expect(headings(reconstruct(page).blocks).map(\.text) == ["6 REPRESENTATION OF REPCL AND ITS OVERHEAD"])
    // A bare section number joins its title across PDFKit's gap split.
    var split = labelPage("3.1", width: 14)
    let number = split.lines[4].rect
    split.lines.insert(TextLine(text: "Limitations of Existing Clocks", rect: CGRect(x: 86, y: number.minY, width: 150, height: 11), fontSize: 11), at: 5)
    #expect(headings(reconstruct(split).blocks).map(\.text) == ["3.1 Limitations of Existing Clocks"])
}

@Test func replayNumberedTitleContinuesOnAHangingIndent() throws {
    // Replay Clocks page 6 sets `OVERHEAD` under the title text, past `6 ` (#83).
    let page = try SourceLayoutFixture.load("replay-6").content()
    #expect(try SourceLayoutFixture.load("replay-6").sourceSHA256 == SourceLayoutFixture.load("replay-1").sourceSHA256)
    let (blocks, _, _) = reconstruct(page)
    #expect(headings(blocks).map(\.text) == ["6 REPRESENTATION OF REPCL AND ITS OVERHEAD", "7 SIMULATION RESULTS"])
    #expect(!paragraphs(blocks).contains("OVERHEAD"))
    #expect(paragraphs(blocks).contains { $0.hasPrefix("In this section, we identify how") })
    // The 9/11 report hangs its section titles the same way, 18 points in at 12 points.
    let report = headings(reconstruct(try SourceLayoutFixture.load("911-91").content()).blocks).map(\.text)
    #expect(report.contains("3.2 ADAPTATION—AND NONADAPTATION—IN THE LAW ENFORCEMENT COMMUNITY"), "\(report)")
    #expect(!report.contains("LAW ENFORCEMENT COMMUNITY"))

    func stacked(_ title: String, next: String, x: CGFloat) -> [String] {
        var page = labelPage(title, width: 240, gapBelow: 17)
        let first = page.lines[4].rect
        page.lines.insert(TextLine(text: next, rect: CGRect(x: x, y: first.minY - 13, width: 60, height: 11), fontSize: 11), at: 5)
        return headings(reconstruct(page).blocks).map(\.text)
    }
    // At 11 points `6` may hang the next line up to 17.6 points in (0.6 em and an em for the
    // space) and `6.2` up to 30.8; Replay sets 16.5 at 10.9 points, the 9/11 report 18.1 at 12.
    #expect(stacked("6 REPRESENTATION OF REPCL AND ITS", next: "OVERHEAD", x: 76.5) == ["6 REPRESENTATION OF REPCL AND ITS OVERHEAD"])
    #expect(stacked("6.2 REPRESENTATION OF REPCL AND", next: "OVERHEAD", x: 88) == ["6.2 REPRESENTATION OF REPCL AND OVERHEAD"])
    // An unnumbered title, an indent past the number's width, or a line opening its own number
    // stay separate headings.
    #expect(stacked("REPRESENTATION OF REPCL AND ITS", next: "OVERHEAD", x: 74.5).count == 2)
    #expect(stacked("6 REPRESENTATION OF REPCL AND ITS", next: "OVERHEAD", x: 80).count == 2)
    #expect(stacked("6.2 REPRESENTATION OF REPCL AND", next: "OVERHEAD", x: 93).count == 2)
    #expect(stacked("6 REPRESENTATION OF REPCL AND ITS", next: "6.1 OVERHEAD", x: 74.5).count == 2)
    // Two titles on one row far apart (two columns' headings) are not the pieces of one row.
    var row = labelPage("RUNWAY SAFETY AREA", width: 120)
    let left = row.lines[4].rect
    row.lines.insert(TextLine(text: "BOUNDARY SIGN", rect: CGRect(x: 250, y: left.minY, width: 90, height: 11), fontSize: 11), at: 5)
    #expect(headings(reconstruct(row).blocks).map(\.text) == ["RUNWAY SAFETY AREA", "BOUNDARY SIGN"])
}

@Test func sourceHeadingControlsKeepTheirSemanticsUnderRankingAndLabels() throws {
    // 9/11 chapter openings: the chapter title outranks the numbered section label beneath it.
    let opening = headings(reconstruct(try SourceLayoutFixture.load("911-19").content()).blocks)
    #expect(opening.contains { $0.text.contains("WE HAVE") && $0.level == 2 })
    #expect(opening.contains { $0.text.contains("SOME PLANES") && $0.level == 2 })
    #expect(opening.contains { $0.text == "1.1 INSIDE THE FOUR FLIGHTS" && $0.level == 3 })
    let foundation = headings(reconstruct(try SourceLayoutFixture.load("911-65").content()).blocks)
    #expect(foundation.contains { $0.text.contains("THE FOUNDATION") && $0.level == 2 })
    #expect(foundation.contains { $0.text == "2.1 A DECLARATION OF WAR" && $0.level == 3 })
    // Fed and Our Flag headings survive; two lines of one title share a level.
    let fed = headings(reconstruct(try SourceLayoutFixture.load("fed-32").content()).blocks)
    #expect(fed.contains { $0.text == "How the FOMC Determines the Appropriate Stance of Monetary Policy" })
    let flag = headings(reconstruct(try SourceLayoutFixture.load("flag-27").content()).blocks)
    #expect(flag.contains { $0.text == "Care of Your Flag" })
    #expect(flag.contains { $0.text == "Sizes of Flags" })
    // An inherited OCR layer whose prose runs 20% over its reference body has no labels.
    #expect(headings(reconstruct(try SourceLayoutFixture.load("nbs-7").content()).blocks).isEmpty)
    // Fed page 13's 8-point running header and summary line stay out of headings.
    let fed13 = reconstruct(try SourceLayoutFixture.load("fed-13").content()).blocks
    #expect(!headings(fed13).contains { $0.text.contains("Overview of the Federal Reserve System") })
    #expect(!headings(fed13).contains { $0.text.contains("transfers its net earnings") })
    // Algebra exercise headings and answer keys keep their existing headings.
    #expect(headings(reconstruct(try SourceLayoutFixture.load("algebra-10").content()).blocks).contains { $0.text == "0.1 Practice - Integers" })
}
