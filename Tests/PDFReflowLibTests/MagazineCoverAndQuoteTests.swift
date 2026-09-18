import CoreGraphics
import Foundation
import Testing
import ZIPFoundation
@testable import PDFReflowLib

// #201, read against renders of USDA ARS *Agricultural Research*, November/December 2012:
//
// - the cover's 14-point tagline, alone in the page's foot band, was a heading;
// - the back cover's ARS logo, set level with the four lines of the return address, was ordered by
//   its middle and fell between the address's second and third lines;
// - the pull quotes on pages 11, 12 and 14 close on their speaker's name (`…per night.”—Douglas
//   Burkett`), which the pull-quote rule did not read as a sentence's end, so each was a heading or two;
// - `unquestion=` + `ably` (the 9/11 report's page 172) kept its hyphen: the vocabulary recorded the
//   `=` break's first half as a word. `launder-` + `ings` and `nonagri-` + `cultural` kept theirs: the
//   lexicon lists `laundering` and `agricultural`, not the words printed.
//
// Fixtures `usda-1`, `usda-11`, `usda-12` and `usda-24` are captured from the
// checksum-pinned source (text and geometry only); expected text was read against 50 DPI Poppler renders.

private let usdaSHA256 = "2673d1fded74ad89c8b5c59dc325c7884601e1aca5b5755b15a105c1f5b0d761"

private func usdaPage(_ number: Int) throws -> PageContent {
    let fixture = try SourceLayoutFixture.load("usda-\(number)")
    #expect(fixture.sourceSHA256 == usdaSHA256)
    var pages = [fixture.styledContent()]
    _ = LayoutReconstructor.stripFurniture(&pages)
    return pages[0]
}

/// The magazine's columns are set at 10.5 points, the document's body the pipeline measures.
private func reflow(_ page: PageContent, documentBody: CGFloat? = 10.5, regions keeping: Bool = true) -> [ReflowBlock] {
    let regions = keeping ? LayoutReconstructor.graphicsWithLabels(page) : []
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: regions.enumerated().map { ($0.element, "image-\($0.offset)") },
                                      vocabulary: [], warnings: &warnings, documentBody: documentBody)
}

private func headings(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .heading = $0.content { $0.text } else { nil } }
}

private func paragraphs(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .paragraph = $0.content { $0.text } else { nil } }
}

private func pullQuotes(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .pullQuote = $0.content { $0.text } else { nil } }
}

// MARK: - Pull quotes

@Test func magazinePullQuotesClosingOnTheirSpeakerAreAsides() throws {
    for (number, opening, closing) in [
        (11, "“I was one of those guys deployed to Iraq in 2003. I’m an entomologist.", "between 100 and 1,000 bites per night.”—Douglas Burkett"),
        (12, "“Whenever you get a new compound that works well in the laboratory,", "useful in the real world.” —Dan Kline"),
    ] {
        let blocks = reflow(try usdaPage(number))
        let quotes = pullQuotes(blocks)
        #expect(quotes.count == 1, "page \(number): \(quotes)")
        #expect(quotes.first.map { $0.hasPrefix(opening) && $0.hasSuffix(closing) } == true, "page \(number): \(quotes)")
        // None of its lines heads anything, and none is prose of the column around it.
        #expect(!headings(blocks).contains { $0.contains("“") || $0.contains("—") }, "page \(number): \(headings(blocks))")
        #expect(!paragraphs(blocks).contains { $0.contains(closing) }, "page \(number)")
    }
}

@Test func anAttributionClosesAQuotedSentence() {
    for text in ["…per night.”—Douglas Burkett", "…the real world.” —Dan Kline", "It works!—J. R. Smith", "Done.” – Ken Linthicum"] {
        #expect(LayoutReconstructor.endsAttributedSentence(text), Comment(rawValue: text))
    }
    // A title's dash, a dash inside the sentence and an attribution with no sentence before it are no such close.
    for text in ["Remarks—John Smith", "Plants—and the insects that eat them", "He said.—then left the room",
                 "A sentence ends here. And another—Begins with a lowercase tail after it now"] {
        #expect(!LayoutReconstructor.endsAttributedSentence(text), Comment(rawValue: text))
    }
}

/// Display lines at 14 points over body prose, as the Fed's chapter openers set their summary.
private func displayPage(_ lines: [String]) -> PageContent {
    var page: [TextLine] = lines.enumerated().map { index, text in
        TextLine(text: text, rect: CGRect(x: 167, y: 700 - CGFloat(index) * 16.8, width: 290, height: 16), fontSize: 14)
    }
    for row in 0..<8 {
        page.append(TextLine(text: "Ordinary body prose of the column, set well below the display lines, row \(row).",
                             rect: CGRect(x: 72, y: 560 - CGFloat(row) * 12, width: 440, height: 10), fontSize: 9))
    }
    return PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: page, graphics: [])
}

@Test func aDisplaySentenceIsAnAsideOnlyWhenItQuotesSomeone() {
    // A quotation is set apart; the same sentence without quotation marks stays the paragraph it was (#55).
    let quoted = reflow(displayPage(["“The Federal Reserve sets U.S. monetary policy to",
                                     "promote maximum employment and stable prices", "in the U.S. economy.”"]), documentBody: nil)
    #expect(pullQuotes(quoted) == ["“The Federal Reserve sets U.S. monetary policy to promote maximum employment and stable prices in the U.S. economy.”"])
    #expect(headings(quoted).isEmpty)
    let plain = reflow(displayPage(["The Federal Reserve sets U.S. monetary policy to",
                                    "promote maximum employment and stable prices", "in the U.S. economy."]), documentBody: nil)
    #expect(pullQuotes(plain).isEmpty)
    #expect(paragraphs(plain).contains("The Federal Reserve sets U.S. monetary policy to promote maximum employment and stable prices in the U.S. economy."))
    // A two-line title without terminal punctuation stays one heading.
    let title = reflow(displayPage(["Recycling Ammonia Emissions", "as Fertilizer on the Farm"]), documentBody: nil)
    #expect(headings(title) == ["Recycling Ammonia Emissions as Fertilizer on the Farm"])
    #expect(pullQuotes(title).isEmpty)
}

@Test func aPullQuoteIsWrittenAsAnAsideOutsideTheNavigation() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let book = ReflowDocument(metadata: .init(title: "Quotes", language: "en"), blocks: [
        ReflowBlock(content: .sourcePage(1), page: 1),
        ReflowBlock(content: .paragraph(InlineText("Body prose.")), page: 1),
        ReflowBlock(content: .pullQuote(InlineText("“Quoted words.”—A Speaker")), page: 1),
    ], assets: [])
    let output = try await EPUBWriter.write(book, maximumOutputBytes: .max, directory: dir) { _ in }
    let archive = try Archive(url: output, accessMode: .read)
    func entry(_ path: String) throws -> String {
        var data = Data()
        let item = try #require(archive[path])
        _ = try archive.extract(item) { data += $0 }
        return String(decoding: data, as: UTF8.self)
    }
    let html = try entry("EPUB/chapter-1.xhtml")
    #expect(html.contains("<p>Body prose.</p>\n<aside class=\"pullquote\" role=\"doc-pullquote\"><p>“Quoted words.”—A Speaker</p></aside>"))
    #expect(html.range(of: "<h[1-6]", options: .regularExpression) == nil)
    #expect(!(try entry("EPUB/nav.xhtml")).contains("Quoted words"))
}

// MARK: - The cover's tagline

@Test func aTaglineAloneInABarePagesFootHeadsNothing() throws {
    // The cover's photograph fills the page; the pipeline keeps it in the page's reference image and
    // reflows the lines over it, so no region takes them here either.
    let page = try usdaPage(1)
    let tagline = "Agricultural Research Service • Solving Problems for the Growing World"
    let blocks = reflow(page, regions: false)
    #expect(headings(blocks) == ["Keeping Our Troops Safe", "From Insects"], "\(headings(blocks))")
    #expect(paragraphs(blocks).contains(tagline), "\(paragraphs(blocks))")
    // Control: a page that states no document body keeps its old reading, the tagline a heading.
    #expect(headings(reflow(page, documentBody: nil, regions: false)).contains(tagline))
}

@Test func aHeadingAtTheFootOfRunningTextStillHeadsTheNextPage() {
    // A section title set at the foot of a page of prose heads the section the next page opens (#103).
    var lines = (0..<30).map { row in
        TextLine(text: "Ordinary body prose that fills the column of this page from top to bottom, row \(row).",
                 rect: CGRect(x: 72, y: 720 - CGFloat(row) * 20, width: 440, height: 12), fontSize: 10.5)
    }
    lines.append(TextLine(text: "Getting Products to Troops", rect: CGRect(x: 72, y: 40, width: 200, height: 16), fontSize: 14))
    let page = PageContent(number: 3, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines, graphics: [])
    #expect(headings(reflow(page)) == ["Getting Products to Troops"])
    // On a bare page, a title set above the foot band and a foot-band line with text beneath it
    // still head; only the page's last line in its foot band does not.
    var bare = (0..<3).map { row in
        TextLine(text: "Prepared by the staff, part \(row)", rect: CGRect(x: 200, y: 300 - CGFloat(row) * 11, width: 150, height: 10), fontSize: 9)
    }
    bare += [
        TextLine(text: "Part Two", rect: CGRect(x: 200, y: 400, width: 200, height: 30), fontSize: 24),
        TextLine(text: "The Second Part", rect: CGRect(x: 150, y: 90, width: 300, height: 18), fontSize: 16),
        TextLine(text: "Of the Report", rect: CGRect(x: 150, y: 50, width: 300, height: 18), fontSize: 16),
        TextLine(text: "Printed in the United States", rect: CGRect(x: 150, y: 20, width: 200, height: 10), fontSize: 9),
    ]
    let blocks = reflow(PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: bare, graphics: []))
    #expect(headings(blocks) == ["Part Two", "The Second Part", "Of the Report"], "\(headings(blocks))")
    let closing = reflow(PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: bare.dropLast(), graphics: []))
    #expect(headings(closing) == ["Part Two", "The Second Part"], "\(headings(closing))")
}

// MARK: - The back cover's logo

@Test func aLogoLevelWithTheReturnAddressReadsBeforeIt() throws {
    let blocks = reflow(try usdaPage(24))
    let address = "U.S. Department of Agriculture Agricultural Research Magazine 5601 Sunnyside Ave. Beltsville, MD 20705-5129"
    let index = try #require(blocks.firstIndex { $0.text == address }, "\(blocks.map(\.text))")
    // The logo (x 36–72) stands left of the address (x 80), level with it: it reads first, not between its lines.
    #expect(index == 1)
    #expect({ if case .image = blocks[0].content { true } else { false } }())
}

// MARK: - Word breaks

@Test func theBooksEqualsHyphenLeavesNoFragmentInTheVocabulary() {
    // 9/11 page 172: `…is unquestion=` over `ably very significant…`.
    let lines = [
        TextLine(text: "approve this specific proposal. Atef’s role in the entire operation is unquestion=",
                 rect: CGRect(x: 72, y: 500, width: 440, height: 12), fontSize: 10),
        TextLine(text: "ably very significant but tends to fade into the background, in part because Atef",
                 rect: CGRect(x: 72, y: 488, width: 440, height: 12), fontSize: 10),
    ]
    let vocabulary = LayoutReconstructor.vocabulary(in: [PageContent(number: 172, bounds: CGRect(x: 0, y: 0, width: 612, height: 792),
                                                                      lines: lines, graphics: [])])
    #expect(!vocabulary.contains("unquestion") && !vocabulary.contains("ably"))
    #expect(vocabulary.contains("operation"))
    guard TextLayerPlausibility.lexiconContains("unquestionably") == true else { return }
    let english = vocabulary.union([LayoutReconstructor.englishLexiconKey])
    var warnings: [ConversionWarning] = []
    #expect(LayoutReconstructor.join("is unquestion-", "ably very", vocabulary: english, page: 172, warnings: &warnings)
            == "is unquestionably very")
    #expect(warnings.isEmpty)
    // The defect: with the fragment recorded as a book word, both halves read as words.
    var kept: [ConversionWarning] = []
    #expect(LayoutReconstructor.join("is unquestion-", "ably very", vocabulary: english.union(["unquestion"]), page: 172,
                                     warnings: &kept) == "is unquestion-ably very")
    #expect(kept.map(\.code) == [.uncertainHyphen])
}

@Test func theLexiconVouchesForAnInflectionOrAPrefixedWord() {
    guard TextLayerPlausibility.lexiconContains("laundering") == true,
          TextLayerPlausibility.lexiconContains("launderings") == false,
          TextLayerPlausibility.lexiconContains("nonagricultural") == false else { return }
    let english: Set<String> = [LayoutReconstructor.englishLexiconKey]
    for (left, right, joined) in [("after 20 and 50 launder-", "ings. So far", "after 20 and 50 launderings. So far"),
                                  ("in managing nonagri-", "cultural pests", "in managing nonagricultural pests")] {
        var warnings: [ConversionWarning] = []
        #expect(LayoutReconstructor.join(left, right, vocabulary: english, page: 11, warnings: &warnings) == joined)
        #expect(warnings.isEmpty)
    }
    // A break at the prefix may be the compound's own hyphen; halves that are both words, and a word
    // the lexicon lists in no form (`pyrethroids`), keep the hyphen and warn.
    for (left, right) in [("non-", "agricultural pests"), ("bite-protection as-", "say to test"), ("pyre-", "throids and")] {
        var warnings: [ConversionWarning] = []
        #expect(LayoutReconstructor.join(left, right, vocabulary: english, page: 8, warnings: &warnings) == left + right,
                Comment(rawValue: left + right))
        #expect(warnings.map(\.code) == [.uncertainHyphen], Comment(rawValue: left + right))
    }
    #expect(LayoutReconstructor.inflectionStems("launderings") == ["laundering", "launderinge"])
}
