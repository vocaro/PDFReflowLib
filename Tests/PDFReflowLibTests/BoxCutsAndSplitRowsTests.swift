import Foundation
import Testing
@testable import PDFReflowLib

/// One page's blocks, as the pipeline makes them: the crops `graphicsWithLabels` finds become
/// image blocks under stable identifiers, so a test reads the same order the writer serializes.
private func pageBlocks(_ page: PageContent, warnings: inout [ConversionWarning]) -> [ReflowBlock] {
    let images = LayoutReconstructor.graphicsWithLabels(page).enumerated()
        .map { ($0.element, "page-\(page.number)-region-\($0.offset)") }
    return LayoutReconstructor.blocks(page: page, images: images, vocabulary: [], warnings: &warnings)
}

private func captions(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case let .image(image) = $0.content { image.caption } else { nil } }
}

/// The Fed sets Box 3.5 at the foot of page 47, and the paragraph that names it runs on to page
/// 48. The join steps over the box, and the box is placed before the paragraph it interrupts —
/// where it also reads before the sentence that refers to it. Placing it after the paragraph
/// would carry page-47 content past the page-48 marker, which the join sets inside the
/// paragraph (#203).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/203"))
func aBoxAtTheFootOfAPageIsPlacedBeforeTheParagraphItInterrupts() throws {
    let first = try SourceLayoutFixture.load("fed-47")
    let second = try SourceLayoutFixture.load("fed-48")
    #expect(first.sourceSHA256 == "8db8fd9e1de63ac25a6f9585d78ded12f45ab56f0c14c52c199b36b368f84d60")
    #expect(second.sourceSHA256 == first.sourceSHA256)
    var start = first.content(), next = second.content()
    // Exclude the running heads and folios, which the full-document furniture pass removes.
    start.lines.removeAll { $0.text == "Conducting Monetary Policy 43" }
    next.lines.removeAll { $0.text == "44" || $0.text == "The Fed Explained: What the Central Bank Does" }

    var warnings: [ConversionWarning] = []
    let startBlocks = pageBlocks(start, warnings: &warnings)
    // The page's own order: the paragraph that names the box, then the box at its foot.
    let broken = try #require(paragraphTexts(startBlocks).last)
    #expect(broken.hasSuffix("The vast major-"))
    #expect(broken.contains("(See box 3.5 for more details"))
    #expect(startBlocks.last?.isImage == true)

    var blocks: [ReflowBlock] = []
    // The book's own vocabulary closes the broken word, as it does in a conversion; that rule is
    // #123's and is not what this test measures.
    let vocabulary: Set<String> = ["majority"]
    LayoutReconstructor.appendPage(startBlocks, page: start, previousPage: nil, to: &blocks,
                                   vocabulary: vocabulary, warnings: &warnings)
    LayoutReconstructor.appendPage(pageBlocks(next, warnings: &warnings), page: next, previousPage: start,
                                   to: &blocks, vocabulary: vocabulary, warnings: &warnings)

    let joined = try #require(paragraphTexts(blocks).first { $0.contains("(See box 3.5 for more details") })
    #expect(joined.contains("The vast majority of the Federal Reserve’s assets are securities holdings."))
    #expect(joined.hasSuffix("increases the level of reserves."))
    // The page boundary stays inside the paragraph, where the join put it.
    if case let .paragraph(text) = try #require(blocks.first { $0.text == joined }).content {
        #expect(text.sourcePages == [48])
    } else { Issue.record("the continued paragraph") }
    // The box is before the paragraph, and no standalone page-48 marker remains.
    let index = try #require(blocks.firstIndex { $0.text == joined })
    #expect(blocks[..<index].last?.isImage == true)
    #expect(!blocks.contains { $0.content == .sourcePage(48) })
    // Every image the page made is still in the book, and none moved to the other page.
    #expect(captions(blocks) == captions(startBlocks) + captions(pageBlocks(next, warnings: &warnings)))
}

/// The control: a page whose last block is an image no paragraph continues past keeps its own
/// source marker, and the image keeps its place. An intervening figure only stops being a
/// barrier when a paragraph on each side of it asks to be joined (#57, #203).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/203"))
func anImageBetweenTwoPagesThatDoNotContinueKeepsItsPlaceAndItsMarker() {
    let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
    func line(_ text: String, y: Double) -> TextLine {
        TextLine(text: text, rect: CGRect(x: 40, y: y, width: 300, height: 12), fontSize: 10)
    }
    let previous = PageContent(number: 1, bounds: bounds, lines: [line("A closed sentence.", y: 40)], graphics: [])
    let current = PageContent(number: 2, bounds: bounds, lines: [line("A new sentence follows.", y: 740)], graphics: [])
    var blocks = [ReflowBlock(content: .sourcePage(1), page: 1),
                  ReflowBlock(content: .paragraph(InlineText("A closed sentence.")), page: 1),
                  LayoutReconstructor.imageBlock(assetID: "box", page: 1)]
    var warnings: [ConversionWarning] = []
    LayoutReconstructor.appendPage([.init(content: .paragraph(InlineText("A new sentence follows.")), page: 2)],
                                   page: current, previousPage: previous, to: &blocks,
                                   vocabulary: [], warnings: &warnings)
    #expect(blocks.map(\.text) == ["", "A closed sentence.", "", "", "A new sentence follows."])
    #expect(blocks[2].isImage)
    #expect(blocks[3].content == .sourcePage(2))
}

/// A block the join reaches past a picture is being called a paragraph the page interrupted, so
/// it must read as the page's prose. The 9/11 report prints the folio `145` under the column on
/// page 163 and page 164 opens with a crop, and that folio would otherwise take page 164's first
/// words: `145 school, KSM left Kuwait to enroll at Chowan College`. The block directly before a
/// boundary is still reached whatever it holds, which leaves #45's own defect exactly as it was
/// (#45, #203).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/203"))
func aFolioIsNotAParagraphAPictureInterrupted() {
    let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
    func line(_ text: String, y: Double, width: Double = 300) -> TextLine {
        TextLine(text: text, rect: CGRect(x: 40, y: y, width: width, height: 12), fontSize: 10)
    }
    let previous = PageContent(number: 163, bounds: bounds,
                               lines: [line("following his graduation from secondary", y: 60), line("145", y: 40, width: 18)],
                               graphics: [])
    let current = PageContent(number: 164, bounds: bounds,
                              lines: [line("school, KSM left Kuwait.", y: 740)], graphics: [])
    let opening = [LayoutReconstructor.imageBlock(assetID: "crop", page: 164),
                   ReflowBlock(content: .paragraph(InlineText("school, KSM left Kuwait.")), page: 164)]
    var warnings: [ConversionWarning] = []

    var blocks = [ReflowBlock(content: .paragraph(InlineText("following his graduation from secondary")), page: 163),
                  ReflowBlock(content: .paragraph(InlineText("145")), page: 163)]
    LayoutReconstructor.appendPage(opening, page: current, previousPage: previous, to: &blocks,
                                   vocabulary: [], warnings: &warnings)
    #expect(paragraphTexts(blocks) == ["following his graduation from secondary", "145", "school, KSM left Kuwait."])
    #expect(blocks.contains { $0.content == .sourcePage(164) })

    // The control: the same page without the folio joins, because its last paragraph is prose.
    var prose = [ReflowBlock(content: .paragraph(InlineText("following his graduation from secondary")), page: 163)]
    LayoutReconstructor.appendPage(opening, page: current, previousPage: previous, to: &prose,
                                   vocabulary: [], warnings: &warnings)
    #expect(paragraphTexts(prose) == ["following his graduation from secondary school, KSM left Kuwait."])
    #expect(!prose.contains { $0.content == .sourcePage(164) })
}

/// Reconstruction may hand a block on only once no later page can amend it. The join reaches
/// past the images at the tail to the paragraph beneath them, so that paragraph and those images
/// are all still open; a page that opens no paragraph puts its own marker at the tail, and the
/// tail is one block again (#203, decision 0008).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/203"))
func theAmendableTailHoldsTheParagraphAPictureStandsOver() {
    let paragraph = ReflowBlock(content: .paragraph(InlineText("open")), page: 1)
    let heading = ReflowBlock(content: .heading(id: "h", text: InlineText("Title")), page: 1)
    let image = LayoutReconstructor.imageBlock(assetID: "box", page: 1)
    let marker = ReflowBlock(content: .sourcePage(2), page: 2)
    #expect(LayoutReconstructor.amendableTail(of: [paragraph]) == 1)
    #expect(LayoutReconstructor.amendableTail(of: [paragraph, paragraph]) == 1)
    #expect(LayoutReconstructor.amendableTail(of: [paragraph, image]) == 2)
    #expect(LayoutReconstructor.amendableTail(of: [paragraph, image, image, image]) == 4)
    // Only a paragraph can be joined; a heading, a marker or nothing at all stops the walk.
    #expect(LayoutReconstructor.amendableTail(of: [heading, image]) == 1)
    #expect(LayoutReconstructor.amendableTail(of: [paragraph, image, marker, image]) == 1)
    #expect(LayoutReconstructor.amendableTail(of: [image, image]) == 1)
    #expect(LayoutReconstructor.amendableTail(of: []) == 1)
}

/// Wallace breaks a printed row after a raised exponent, so `8x²` is one extracted line and
/// `− 3x + 7− 2x² +4x− 3` the next, standing 1.89 points to its right on the same baseline. The
/// minus the page printed between two terms read as a list marker, and the rest of the row
/// became an item of a list in a `<pre>` block of its own (#203).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/203"))
func aRowSplitAfterAnExponentIsNotAListItem() throws {
    let fixture = try SourceLayoutFixture.load("algebra-23")
    #expect(fixture.sourceSHA256 == "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678")
    let page = fixture.content()
    let left = try #require(page.lines.first { $0.text == "8x2" })
    let right = try #require(page.lines.first { $0.text.hasPrefix("− 3x + 7") })
    #expect(left.sharesRow(with: right) && right.rect.minX > left.rect.maxX)
    #expect(right.rect.minX - left.rect.maxX < 2)

    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings)
    let texts = blocks.map(\.text)
    #expect(texts.contains { $0.hasPrefix("8x2 − 3x + 7− 2x2 +4x− 3") })
    #expect(texts.contains { $0.hasPrefix("Combine like terms 8x2 − 2x2 and− 3x +4x and 7− 3") })
    // Both pieces read as prose, so neither half is preformatted any more.
    let preformatted = blocks.compactMap { if case .preformatted = $0.content { $0.text } else { nil } }
    #expect(!preformatted.contains { $0.hasPrefix("− 3x + 7") || $0.hasPrefix("− 2x2 and") })
    // The control on the page itself: a row that *opens* with the minus has nothing to its left,
    // so it still keeps its break.
    #expect(preformatted.contains { $0.hasPrefix("− 7(5x− 6)") })
    #expect(preformatted.contains { $0.hasPrefix("− 3x +5y Our Solution") })
}

/// Positive controls from other books: a page that sets a real bulleted list still sets one.
/// The pieces of a split row stand within three quarters of a body of each other, and a page's
/// columns and a table's cells stand further apart than that (#203).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/203"), arguments: ["911-583", "faa-364", "fed-77"])
func aBulletedListIsStillAList(name: String) throws {
    let fixture = try SourceLayoutFixture.load(name)
    let page = fixture.content()
    let bulleted = page.lines.filter { LayoutReconstructor.isList($0.text) }
    #expect(bulleted.count >= 5)
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings)
    let preformatted = blocks.compactMap { if case .preformatted = $0.content { $0.text } else { nil } }
    for line in bulleted {
        #expect(preformatted.contains { $0.hasPrefix(line.text.prefix(24)) })
    }
}
