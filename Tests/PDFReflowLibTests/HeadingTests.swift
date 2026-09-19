import Foundation
import Testing
@testable import PDFReflowLib

private func headingBlocks(_ page: PageContent) -> [ReflowBlock] {
    let images = LayoutReconstructor.graphicsWithLabels(page).enumerated().map { ($0.element, "image-\($0.offset)") }
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: images,
        vocabulary: LayoutReconstructor.vocabulary(in: [page]), warnings: &warnings)
}


@Test func fedTableTypographyDoesNotPromoteSurroundingProse() throws {
    let page = try SourceLayoutFixture.load("fed-46").content()
    let blocks = headingBlocks(page)
    #expect(headingTexts(blocks).isEmpty)
    let paragraphs = blocks.compactMap { block -> String? in
        if case .paragraph = block.content { return block.text }; return nil
    }
    #expect(paragraphs.contains { $0.contains("funds rate and other short-term interest rates is exercised primarily through the setting of") })
    #expect(paragraphs.contains { $0.contains("risks to the economic outlook were implemented") })
    #expect(blocks.filter { if case .image = $0.content { true } else { false } }.count >= 2)
}

@Test func neighboringFedProseAndSourceChapterTitlesKeepTheirSemantics() throws {
    let page = try SourceLayoutFixture.load("fed-45").content()
    #expect(headingTexts(headingBlocks(page)).isEmpty)
    for (name, title) in [("911-19", "WE HAVE"), ("911-65", "THE FOUNDATION")] {
        let blocks = headingBlocks(try SourceLayoutFixture.load(name).content())
        #expect(headingTexts(blocks).contains { $0.contains(title) })
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
    #expect(headingTexts(blocks) == ["A legitimate heading"])
    #expect(blocks.contains { if case .paragraph = $0.content { $0.text.contains("Ordinary body prose") } else { false } })
}

@Test func imageBesideShortTitleDoesNotEraseTitleEvidence() {
    #expect(headingTexts(headingBlocks(mixedTypographyPage(bodyLines: 0))) == ["A legitimate heading"])
}

@Test func noPreservedRegionsKeepExistingHeadingEvidence() {
    var page = mixedTypographyPage()
    page.graphics = []
    // Without preservation the 8-point material remains reflowable body text.
    #expect(headingTexts(headingBlocks(page)).contains("A legitimate heading"))
}

@Test func modestSourceSectionHeadingsSurviveSmallTableText() throws {
    let titles = [(32, "How the FOMC Determines the Appropriate Stance of Monetary Policy"),
                  (54, "Asset Valuations and Risk Appetite"), (77, "Examination Report"),
                  (103, "Establishing and Maintaining a Reliable U.S. Currency"),
                  (109, "Expedited Funds Availability Act"), (123, "Interagency Initiatives")]
    for (number, title) in titles {
        let blocks = headingBlocks(try SourceLayoutFixture.load("fed-\(number)").content())
        #expect(headingTexts(blocks).contains(title))
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
        #expect(!headingTexts(blocks).contains { $0.contains(phrase) })
    }
}
