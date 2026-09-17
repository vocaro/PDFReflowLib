import Foundation
import Testing
@testable import PDFReflowLib

private func headingBlocks(_ page: PageContent) -> [ReflowBlock] {
    let images = LayoutReconstructor.graphicsWithLabels(page).enumerated().map { ($0.element, "image-\($0.offset)") }
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: images,
        vocabulary: LayoutReconstructor.vocabulary(in: [page]), warnings: &warnings)
}

private func headings(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .heading = $0.content { $0.text } else { nil } }
}

@Test func fedTableTypographyDoesNotPromoteSurroundingProse() throws {
    let page = try SourceLayoutFixture.load("fed-46").content()
    let blocks = headingBlocks(page)
    // The sidebar's own 8-point title is the page's only heading (#100); no prose line is one.
    #expect(headings(blocks) == ["Learn more about how the Fed uses “ample reserves”"])
    let paragraphs = blocks.compactMap { block -> String? in
        if case .paragraph = block.content { return block.text }; return nil
    }
    #expect(paragraphs.contains { $0.contains("funds rate and other short-term interest rates is exercised primarily through the setting of") })
    #expect(paragraphs.contains { $0.contains("risks to the economic outlook were implemented") })
    #expect(blocks.filter { if case .image = $0.content { true } else { false } }.count >= 2)
}

@Test func neighboringFedProseAndSourceChapterTitlesKeepTheirSemantics() throws {
    let page = try SourceLayoutFixture.load("fed-45").content()
    #expect(headings(headingBlocks(page)).isEmpty)
    for (name, title) in [("911-19", "WE HAVE"), ("911-65", "THE FOUNDATION")] {
        let blocks = headingBlocks(try SourceLayoutFixture.load(name).content())
        #expect(headings(blocks).contains { $0.contains(title) })
    }
}

private func mixedTypographyPage(bodyLines: Int = 6) -> PageContent {
    var lines = (0..<12).map { i in
        TextLine(text: "Small table text repeated to dominate page typography and character counts.",
                 rect: CGRect(x: 40, y: 40 + i * 12, width: 500, height: 9), fontSize: 8)
    }
    lines += (0..<bodyLines).map { i in
        TextLine(text: "Ordinary body prose remains a paragraph outside the preserved table region.",
                 rect: CGRect(x: 40, y: 600 - i * 16, width: 400, height: 12), fontSize: 10)
    }
    lines.append(TextLine(text: "A legitimate heading", rect: CGRect(x: 40, y: 670, width: 250, height: 18), fontSize: 16))
    return PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 600, height: 800),
                       lines: lines, graphics: [CGRect(x: 30, y: 30, width: 530, height: 170)])
}

@Test func imageTextCannotSetHeadingThresholdButRealHeadingSurvives() {
    let blocks = headingBlocks(mixedTypographyPage())
    #expect(headings(blocks) == ["A legitimate heading"])
    #expect(blocks.contains { if case .paragraph = $0.content { $0.text.contains("Ordinary body prose") } else { false } })
}

@Test func imageBesideShortTitleDoesNotEraseTitleEvidence() {
    #expect(headings(headingBlocks(mixedTypographyPage(bodyLines: 0))) == ["A legitimate heading"])
}

@Test func noPreservedRegionsKeepExistingHeadingEvidence() {
    var page = mixedTypographyPage()
    page.graphics = []
    // Without preservation the 8-point material remains reflowable body text.
    #expect(headings(headingBlocks(page)).contains("A legitimate heading"))
}

@Test func modestSourceSectionHeadingsSurviveSmallTableText() throws {
    let titles = [(32, "How the FOMC Determines the Appropriate Stance of Monetary Policy"),
                  (54, "Asset Valuations and Risk Appetite"), (77, "Examination Report"),
                  (103, "Establishing and Maintaining a Reliable U.S. Currency"),
                  (109, "Expedited Funds Availability Act"), (123, "Interagency Initiatives")]
    for (number, title) in titles {
        let blocks = headingBlocks(try SourceLayoutFixture.load("fed-\(number)").content())
        #expect(headings(blocks).contains(title))
    }
}

@Test func graphicDominatedFedPagesRetainBodyAsParagraphs() throws {
    let phrases = [(13, "Despite the need for coordination and consistency"),
                   (54, "These vulnerability assessments inform internal"),
                   (75, "By statute, state member banks must be examined"),
                   (77, "BHCs and SLHCs with less than $100 billion"),
                   (103, "Although the issuance of paper money"),
                   (109, "During the last two decades, Congress has directed")]
    for (number, phrase) in phrases {
        let blocks = headingBlocks(try SourceLayoutFixture.load("fed-\(number)").content())
        #expect(blocks.contains { if case .paragraph = $0.content { $0.text.contains(phrase) } else { false } })
        #expect(!headings(blocks).contains { $0.contains(phrase) })
    }
}

/// #62's floor: whatever furniture removal makes of a running head — the client can switch it
/// off entirely — a separated margin line that opens or closes with the page's own number is
/// never a heading. `blocks` sees the page as extraction hands it over, before any removal.
@Test func foliobearingMarginLinesAreNeverHeadings() throws {
    let page = try SourceLayoutFixture.load("911-572").content()
    let head = try #require(page.lines.max { $0.rect.midY < $1.rect.midY })
    #expect(head.text == "554 NOTES TO CHAPTERS 9-10")
    // It clears the page's heading threshold: 9.5 pt over the notes' 7 pt body.
    #expect(head.fontSize >= LayoutReconstructor.bodySize(page.lines) * 1.25)
    let blocks = headingBlocks(page)
    #expect(!headings(blocks).contains { $0.contains("NOTES TO CHAPTERS") })
    // It keeps its text as a paragraph; the rule decides navigation, not retention.
    #expect(blocks.contains { $0.text.contains("554 NOTES TO CHAPTERS 9-10") })
}

@Test func marginFolioHeadingRuleNeedsTheBandTheFolioAndTheSeparation() {
    func page(_ text: String, y: Double, gap: Double = 60) -> PageContent {
        PageContent(number: 572, bounds: CGRect(x: 0, y: 0, width: 600, height: 800), lines: [
            TextLine(text: text, rect: CGRect(x: 40, y: y, width: 250, height: 14), fontSize: 14),
        ] + (0..<8).map { i in
            TextLine(text: "Ordinary body prose fills the measure of this page and sets its body size.",
                     rect: CGRect(x: 40, y: y > 400 ? y - gap - Double(i) * 12 : y + gap + Double(i) * 12,
                                  width: 500, height: 10), fontSize: 10)
        }, graphics: [])
    }
    func isHeading(_ content: PageContent) -> Bool {
        var warnings: [ConversionWarning] = []
        return LayoutReconstructor.blocks(page: content, images: [],
            vocabulary: LayoutReconstructor.vocabulary(in: [content]), warnings: &warnings)
            .contains { if case .heading = $0.content { true } else { false } }
    }
    // Both margins, leading and trailing folio, Arabic and Roman.
    #expect(!isHeading(page("572 NOTES TO CHAPTERS 9-10", y: 740)))
    #expect(!isHeading(page("NOTES TO CHAPTERS 9-10 572", y: 740)))
    #expect(!isHeading(page("dlxxii NOTES TO CHAPTERS", y: 740)))
    #expect(!isHeading(page("572 NOTES TO CHAPTERS 9-10", y: 40)))
    // Positive controls: a heading with no folio at its edge; a page number that is not this
    // page's; a folio-bearing line inside the text block; and one the body runs straight into.
    #expect(isHeading(page("NOTES TO CHAPTERS NINE AND TEN", y: 740)))
    #expect(isHeading(page("572 NOTES TO CHAPTERS 9-10", y: 600)))
    #expect(isHeading(page("572 NOTES TO CHAPTERS 9-10", y: 740, gap: 12)))
    // Scope: `blocks` reconstructs one page and does not know the document's folio offset, so
    // any number at the edge of a separated line in the outer tenth reads as this page's
    // number. A title set that far into the head margin and clear of the body is a running
    // head in all six corpus books; no corpus heading is lost to this (see the record).
    #expect(!isHeading(page("CHAPTER 9 AND CHAPTER 10", y: 740)))
    #expect(isHeading(page("CHAPTER 9 AND CHAPTER TEN", y: 740)))
}
