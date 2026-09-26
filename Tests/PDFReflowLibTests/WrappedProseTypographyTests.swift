import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

@Test(arguments: [13, 46])
func wrappedProseKeepsItsBodySizeBesideRecoveredSmallText(number: Int) throws {
    let fixture = try SourceLayoutFixture.load("fed-body-\(number)")
    #expect(fixture.sourceSHA256 == "8db8fd9e1de63ac25a6f9585d78ded12f45ab56f0c14c52c199b36b368f84d60")
    #expect(fixture.page == number)
    // Exercise the typography after all source text has been released from decorative
    // crops. Neither the table cells nor footnotes are discarded to repair the estimate.
    var page = fixture.content()
    page.graphics = []; page.pictures = []
    let typography = PageTypography(pageLines: page.lines, reflowableLines: page.lines, documentBody: 10)
    #expect(typography.body == (number == 13 ? 7 : 8))
    #expect(typography.headingBody == 10)
    #expect(typography.additionalLeading[10] == 16)
    #expect(typography.additionalLeading.count == 1)
    for line in page.lines where line.fontSize == 10 {
        #expect(LayoutReconstructor.role(of: line, on: page, in: page.lines, typography: typography,
                                         labels: [], judgesTitleWords: false) != .heading)
    }
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [],
        vocabulary: LayoutReconstructor.vocabulary(in: [page]), warnings: &warnings, documentBody: 10)
    let opening = number == 13 ? "Despite the need for coordination and consistency throughout the Federal Reserve System, geographic distinctions"
        : "funds rate and other short-term interest rates is exercised primarily through the setting of"
    #expect(blocks.contains { block in
        if case .paragraph = block.content { return block.text.hasPrefix(opening) }
        return false
    })
    let small = number == 13 ? "capital surplus" : "reserve balance accounts"
    #expect(blocks.map(\.text).joined(separator: " ").contains(small))

    let title = TextLine(text: "Monetary Policy", rect: CGRect(x: 90, y: 725, width: 220, height: 17), fontSize: 14)
    let withTitle = PageTypography(pageLines: page.lines + [title], reflowableLines: page.lines + [title], documentBody: 10)
    #expect(LayoutReconstructor.role(of: title, on: page, in: page.lines + [title], typography: withTitle,
                                     labels: [], judgesTitleWords: false) == .heading)
}

@Test func wrappedProseFloorRequiresNativeParagraphEvidence() {
    let small = (0..<10).map { index in
        TextLine(text: "These smaller explanatory notes supply most of this page's text and remain readable.",
                 rect: CGRect(x: 30, y: 300 - index * 12, width: 300, height: 10), fontSize: 8)
    }
    let words = ["A larger paragraph begins with ordinary words here",
                 "and continues over several lines at one consistent",
                 "measure, with enough text to establish its own size",
                 "while the many smaller notes remain in the reading."]
    let larger = words.enumerated().map { index, text in
        TextLine(text: text, rect: CGRect(x: 30, y: 600 - index * 16, width: 260, height: 12), fontSize: 10)
    }
    func threshold(_ lines: [TextLine], native: Bool = true) -> CGFloat {
        PageTypography(pageLines: small + lines, reflowableLines: small + lines, documentBody: 10,
                       nativeSizeEvidence: native).headingThreshold
    }
    #expect(threshold(larger) == 11)
    #expect(PageTypography(pageLines: small + larger, reflowableLines: small + larger,
                           documentBody: nil).headingThreshold == 10)
    #expect(threshold(larger, native: false) == 10)
    #expect(threshold(Array(larger.prefix(3))) == 10)
    let bold = larger.map { TextLine(content: InlineText($0.text, style: .bold), rect: $0.rect, fontSize: $0.fontSize) }
    #expect(threshold(bold) == 10)
    var quoted = larger
    quoted[0] = TextLine(text: "“" + words[0], rect: larger[0].rect, fontSize: 10)
    #expect(threshold(quoted) == 10)
    var caption = larger
    caption[0] = TextLine(text: "Figure 1. " + words[0], rect: larger[0].rect, fontSize: 10)
    #expect(threshold(caption) == 10)
    var tagged = larger
    tagged[0].structure = TextStructure(group: 1, order: 1, headingLevel: 2, lineCount: 4)
    #expect(threshold(tagged) == 10)
    var rotated = larger
    for index in rotated.indices { rotated[index].turn = .clockwise }
    #expect(threshold(rotated) == 10)
}

@Test(arguments: [1691, 1712, 1730])
func wrappedDisplaySummaryDoesNotRaiseOrdinaryHeadingSize(number: Int) throws {
    let fixture = try SourceLayoutFixture.load("noaa-body-\(number)")
    #expect(fixture.sourceSHA256 == "1942cbf346dc2c711fea413d6d6543edb8bc1e3a88d4c3a85e733c6b6d3577bf")
    #expect(fixture.page == number)
    let page = fixture.content()
    // These pages have 14 pt summaries above 10 pt prose and genuine 14 pt headings.
    // A long, lowercase-continuing summary is not corroborated by the document's body.
    for documentBody: CGFloat? in [nil, 10] {
        let typography = PageTypography(pageLines: page.lines, reflowableLines: page.lines,
                                        documentBody: documentBody)
        #expect(typography.body == 10)
        #expect(typography.headingBody == 10)
        let expected = number == 1691 ? ["What Are Compound Events?"]
            : number == 1712 ? ["The Impact of Climate on Infectious Diseases", "Interactions Between COVID-19"]
            : ["Why So Blue, Carbon?", "The Carbon Benefits"]
        for phrase in expected {
            let line = try #require(page.lines.first { $0.text.hasPrefix(phrase) })
            #expect(LayoutReconstructor.role(of: line, on: page, in: page.lines, typography: typography,
                                             labels: [], judgesTitleWords: false) == .heading)
        }
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/314"))
func smallerProseKeepsItsOwnLeadingBesideALargerWrappedRun() {
    // Hebrew Shakespeare page 87 in miniature: a letter at 9.5 points on 13, then 7-point notes on
    // 9, the last opening with its number 12.75 below the note above it. Once the letter's row
    // that PDFKit split at a note number is whole, the letter qualifies as wrapped prose too; the
    // notes keep their own leading, and the numbered note stays a paragraph of its own rather
    // than run on from `The Publisher.` under the letter's 13 points.
    func line(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat) -> TextLine {
        TextLine(text: text, rect: CGRect(x: x, y: y, width: width, height: size * 0.96), fontSize: size)
    }
    let letter = [
        "with his book, which I have called by the", "title So He Drove Out the Man, because",
        "wondrous things can be seen in it which", "have not been devised in any nation until",
        "this day. It is not so with Shakespeare; his", "books are read in the four corners of the",
        "world in seventy languages, and viewers can",
    ].enumerated().map { line($0.element, x: 68, y: 437 - CGFloat($0.offset) * 13, width: 162, size: 9.5) }
    let notes = [
        "matter is desirable and acceptable to all readers,", "and moreover the translator has succeeded greatly",
        "in his work. He can trust that this translation will", "be a desirable offering for all those who love the",
    ].enumerated().map { line($0.element, x: 82, y: 121.5 - CGFloat($0.offset) * 9, width: 142, size: 7) }
        + [line("language of their forefathers – The Publisher.", x: 82, y: 85.5, width: 129.5, size: 7),
           line("18 The title of the translation is a citation of the beginning of Gen. 3:24, in which God",
                x: 82, y: 72.75, width: 304, size: 7),
           line("drives Adam and Eve out of the Garden of Eden.", x: 82, y: 63.75, width: 160, size: 7)]
    let page = PageContent(number: 87, bounds: CGRect(x: 0, y: 0, width: 459, height: 649),
                           lines: letter + notes, graphics: [])
    let typography = PageTypography(pageLines: page.lines, reflowableLines: page.lines, documentBody: 10)
    #expect(typography.leading == 13)
    #expect(typography.additionalLeading[7] == 9)
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: LayoutReconstructor.vocabulary(in: [page]),
                                            warnings: &warnings, documentBody: 10)
    #expect(blocks.contains { $0.text.hasSuffix("forefathers – The Publisher.") })
    #expect(blocks.contains { $0.text.hasPrefix("18 The title of the translation") })
}

@Test func secondaryBodyLeadingDoesNotLoosenSmallerText() {
    func line(_ text: String, y: CGFloat, size: CGFloat) -> TextLine {
        TextLine(text: text, rect: CGRect(x: 30, y: y, width: 240, height: size * 1.2), fontSize: size)
    }
    var assembler = BlockAssembler(page: 1, body: 8, leading: 10, additionalLeading: [10: 16],
                                   hyphens: HyphenContext())
    assembler.append(line("The larger body continues", y: 100, size: 10), as: .prose)
    assembler.append(line("on its own wider leading.", y: 84, size: 10), as: .prose)
    assembler.append(line("A smaller note stands here", y: 50, size: 8), as: .prose)
    assembler.append(line("another note starts further below.", y: 34, size: 8), as: .prose)
    #expect(assembler.finish().map(\.text) == [
        "The larger body continues on its own wider leading.",
        "A smaller note stands here", "another note starts further below."])
}

@Test func modalFedBodyKeepsItsLeadingBesideSmallerFigureNotes() throws {
    let fixture = try SourceLayoutFixture.load("fed-body-95")
    #expect(fixture.sourceSHA256 == "8db8fd9e1de63ac25a6f9585d78ded12f45ab56f0c14c52c199b36b368f84d60")
    #expect(fixture.page == 95)
    var original = fixture.content()
    original.lines = original.lines.map { line in
        guard let attributed = fixture.attributedLines.first(where: { $0.text == line.text }) else { return line }
        return TextLine(content: NativeTextReader.inlineText(from: attributed.attributedString()), rect: line.rect,
                        fontSize: line.fontSize, monospaced: line.monospaced)
    }
    let page = TextBackdrop.compose(original, graphics: .init(regions: original.graphics,
        unsupported: false, images: original.pictures, paints: fixture.paints))
    let typography = PageTypography(pageLines: page.lines, reflowableLines: page.lines, documentBody: 10)
    #expect(typography.body == 10)
    #expect(typography.headingBody == 10)
    #expect(typography.leading == 10)
    #expect(typography.additionalLeading == [10: 16])
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page,
        images: crops.enumerated().map { ($0.element, "image-\($0.offset)") },
        vocabulary: LayoutReconstructor.vocabulary(in: [page]), warnings: &warnings, documentBody: 10)
    let paragraph = try #require(blocks.first { block in
        if case .paragraph = block.content { return block.text.hasPrefix("In 2003, Congress passed") }
        return false
    })
    #expect(paragraph.text.contains("facilitated electronic check processing"))
    #expect(paragraph.text.contains("digital images of checks electronically to banks"))
    #expect(paragraph.text.hasSuffix("By creating widespread opportunities for"))
    let smaller = page.lines.filter { $0.fontSize == 8 }
    let uncorroborated = PageTypography(pageLines: page.lines, reflowableLines: smaller,
                                      documentBody: 10)
    #expect(uncorroborated.additionalLeading[10] == nil)
    let synthetic = PageTypography(pageLines: page.lines, reflowableLines: page.lines,
                                   documentBody: 10, nativeSizeEvidence: false)
    #expect(synthetic.additionalLeading.isEmpty)
}

private func fedShortBodyPage() throws -> PageContent {
    let fixture = try SourceLayoutFixture.load("fed-short-body-47")
    #expect(fixture.sourceSHA256 == "8db8fd9e1de63ac25a6f9585d78ded12f45ab56f0c14c52c199b36b368f84d60")
    struct Capture: Decodable { var nativePage: PageContent }
    return try JSONDecoder().decode(Capture.self,
        from: Data(contentsOf: fixtureURL("fed-short-body-47-layout.json"))).nativePage
}

@Test func twoShortBodyParagraphsKeepTheirOwnLeadingBesideARecoveredBox() throws {
    let page = try fedShortBodyPage()
    let typography = PageTypography(pageLines: page.lines, reflowableLines: page.lines, documentBody: 10)
    #expect(typography.body == 9)
    #expect(typography.leading == 11)
    #expect(typography.headingBody == 9)
    #expect(typography.additionalLeading == [9: 11, 10: 16])
    let body = page.lines.filter { $0.fontSize == 10 && $0.rect.minY > 600 }
        .sorted { $0.rect.maxY > $1.rect.maxY }
    #expect(body.count == 5)
    let expected = [body.prefix(2).map(\.text).joined(separator: " "), body.suffix(3).map(\.text).joined(separator: " ")]
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page,
        images: crops.enumerated().map { ($0.element, "image-\($0.offset)") },
        vocabulary: LayoutReconstructor.vocabulary(in: [page]), warnings: &warnings, documentBody: 10)
    let paragraphs = blocks.filter { if case .paragraph = $0.content { true } else { false } }
    for text in expected { #expect(paragraphs.contains { $0.text == text }) }
    let first = try #require(paragraphs.first { $0.text == expected[0] })
    let encoded = try EPUBTextEncoder.payload(first, imagePaths: [:])
    #expect(encoded.contains("href="))
    #expect(encoded.contains("Global Pandemic"))
    #expect(blocks.contains { if case .heading = $0.content {
        $0.text == "Box 3.5. Gauging Monetary Policy through the Fed’s Balance Sheet"
    } else { false } })
    #expect(blocks.contains { $0.text.contains("The table below shows the major asset and liability categories") })
}

@Test func shortParagraphLeadingNeedsIndependentAlignedNativeProse() throws {
    let page = try fedShortBodyPage()
    let body = page.lines.filter { $0.fontSize == 10 && $0.rect.minY > 600 }
        .sorted { $0.rect.maxY > $1.rect.maxY }
    let small = page.lines.filter { $0.fontSize < 10 }
    func leading(_ rows: [TextLine], document: CGFloat? = 10, native: Bool = true) -> CGFloat? {
        PageTypography(pageLines: small + rows, reflowableLines: small + rows,
                       documentBody: document, nativeSizeEvidence: native).additionalLeading[10]
    }
    #expect(leading(body) == 16)
    #expect(leading(Array(body.suffix(3))) == nil)
    #expect(leading(body, document: nil) == nil)
    #expect(leading(body, document: 9) == nil)
    #expect(leading(body, native: false) == nil)
    for mode in 0..<5 {
        var changed = body
        switch mode {
        case 0:
            changed = body.map { TextLine(content: InlineText($0.text, style: .bold), rect: $0.rect, fontSize: $0.fontSize) }
        case 1:
            for index in changed.indices {
                changed[index].structure = TextStructure(group: 1, order: 0, headingLevel: 2, lineCount: 5)
            }
        case 2:
            for index in 2..<5 { changed[index].rect.origin.x += 100 }
        case 3:
            changed[3].rect.origin.y += 3
        default:
            for index in changed.indices { changed[index].rect.size.width = 80 }
        }
        #expect(leading(changed) == nil, "negative control \(mode)")
    }
}
