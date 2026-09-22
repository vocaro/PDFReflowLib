import Foundation
import Testing
@testable import PDFReflowLib

/// One page's blocks, as the pipeline makes them: the crops `graphicsWithLabels` finds become
/// image blocks under stable identifiers, so a test reads the order the writer serializes.
private func cropBlocks(_ page: PageContent, warnings: inout [ConversionWarning]) -> [ReflowBlock] {
    let images = LayoutReconstructor.graphicsWithLabels(page).enumerated()
        .map { ($0.element, "page-\(page.number)-region-\($0.offset)") }
    return LayoutReconstructor.blocks(page: page, images: images, vocabulary: [], warnings: &warnings)
}

/// Wallace's page 430 opens `b are the other two sides (legs), then we can use the following
/// formula, a² + b² = c²`, and the display that formula is set in takes the whole row. What is
/// left to reflow is `to find a missing side.`, so the cross-page join saw page 429's
/// `…the Pythagorean Theorem states that if c is the hypotenuse of the triangle, and a and`
/// standing beside an opening it could join, and read two fragments the crop had already broken
/// as one paragraph. The page printed two lines in between, so the halves were never
/// consecutive: the block a crop's prose stands before is not where the page's text begins, and
/// the join does not reach it (#267).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/267"))
func aBlockACropTookThePagesOpeningLinesFromIsNotJoinedAcross() throws {
    let first = try SourceLayoutFixture.load("algebra-429")
    let second = try SourceLayoutFixture.load("algebra-430")
    #expect(first.sourceSHA256 == "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678")
    #expect(second.sourceSHA256 == first.sourceSHA256)
    var start = first.content(), next = second.content()
    // Exclude the folios, which the full-document furniture pass removes.
    start.lines.removeAll { $0.text == "429" }
    next.lines.removeAll { $0.text == "430" }

    var warnings: [ConversionWarning] = []
    let startBlocks = cropBlocks(start, warnings: &warnings)
    let nextBlocks = cropBlocks(next, warnings: &warnings)
    // The page before ends its paragraph mid-sentence, which is what invited the join.
    let open = try #require(paragraphTexts(startBlocks).last)
    #expect(open.hasSuffix("and a and"))
    // Page 430's first reflowed block is not its first printed line: the display took that.
    let opening = try #require(nextBlocks.first { $0.hasReflowedText })
    #expect(opening.text.hasPrefix("to find a missing side."))
    #expect(opening.followsCroppedText)
    #expect(!next.lines.contains { $0.text.contains("b are the other two sides") && $0.rect.minY < 700 })

    var blocks: [ReflowBlock] = []
    LayoutReconstructor.appendPage(startBlocks, page: start, previousPage: nil, to: &blocks,
                                   vocabulary: [], warnings: &warnings)
    LayoutReconstructor.appendPage(nextBlocks, page: next, previousPage: start, to: &blocks,
                                   vocabulary: [], warnings: &warnings)
    // The two fragments stay two blocks, and the boundary keeps a marker of its own.
    #expect(!blocks.contains { $0.text.contains("and a and to find a missing side.") })
    #expect(blocks.contains { $0.content == .sourcePage(430) })
    #expect(paragraphTexts(blocks).contains { $0.hasSuffix("and a and") })
    // No word moves: every block either page made is still here, in its own order.
    #expect(blocks.filter(\.hasReflowedText).map(\.text)
        == (startBlocks + nextBlocks).filter(\.hasReflowedText).map(\.text))
}

/// The same defect along a printed row rather than down the page. Wallace's page 344 opens
/// `values into x =` at the measure and sets the quadratic formula beside it, so the crop takes
/// the opening of the page's very first row and `and we will get our two solutions.` is what
/// reflows. Page 343 ends `…we can substitute those`, and the join read the two as one sentence
/// with the formula they are about missing from between them (#267).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/267"))
func aCropThatTookTheOpeningOfThePagesFirstRowRefusesTheJoin() throws {
    let first = try SourceLayoutFixture.load("algebra-343")
    let second = try SourceLayoutFixture.load("algebra-344")
    #expect(second.sourceSHA256 == first.sourceSHA256)
    var start = first.content(), next = second.content()
    start.lines.removeAll { $0.text == "343" }
    next.lines.removeAll { $0.text == "344" }

    var warnings: [ConversionWarning] = []
    let startBlocks = cropBlocks(start, warnings: &warnings)
    let nextBlocks = cropBlocks(next, warnings: &warnings)
    #expect(paragraphTexts(startBlocks).last?.hasSuffix("we can substitute those") == true)
    let opening = try #require(nextBlocks.first { $0.hasReflowedText })
    #expect(opening.text.hasPrefix("and we will get our two solutions."))
    // `values into x =` is two words, so no prose test reaches it; what marks it is that the
    // page began this printed row inside the crop.
    #expect(!LayoutReconstructor.readsAsSentence("values into x =− b ± b2"))
    #expect(opening.followsCroppedText)

    var blocks: [ReflowBlock] = []
    LayoutReconstructor.appendPage(startBlocks, page: start, previousPage: nil, to: &blocks,
                                   vocabulary: [], warnings: &warnings)
    LayoutReconstructor.appendPage(nextBlocks, page: next, previousPage: start, to: &blocks,
                                   vocabulary: [], warnings: &warnings)
    #expect(!blocks.contains { $0.text.contains("substitute those and we will get") })
    #expect(blocks.contains { $0.content == .sourcePage(344) })
}

/// The positive control, and the reason this reads the *later* page alone. The Fed sets Box 3.5
/// over the foot of page 47 — a crop whose own prose stands below the paragraph that names it —
/// and page 48 opens with that page's running-head rule and then the paragraph. The crop on page
/// 48 holds no text, so the paragraph is where page 48's text begins and #203's join still runs,
/// broken word and all. A test that asked the same of the *earlier* page would refuse this join
/// and the eleven like it (#203, #267).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/267"))
func aBoxAtTheFootOfThePageBeforeStillJoins() throws {
    let first = try SourceLayoutFixture.load("fed-47")
    let second = try SourceLayoutFixture.load("fed-48")
    #expect(first.sourceSHA256 == "8db8fd9e1de63ac25a6f9585d78ded12f45ab56f0c14c52c199b36b368f84d60")
    var start = first.content(), next = second.content()
    start.lines.removeAll { $0.text == "Conducting Monetary Policy 43" }
    next.lines.removeAll { $0.text == "44" || $0.text == "The Fed Explained: What the Central Bank Does" }

    var warnings: [ConversionWarning] = []
    let startBlocks = cropBlocks(start, warnings: &warnings)
    let nextBlocks = cropBlocks(next, warnings: &warnings)
    // Page 47's crop holds the box's own prose, and it stands below the paragraph, not before it.
    #expect(startBlocks.last?.isImage == true)
    #expect(!startBlocks.contains { $0.followsCroppedText })
    let opening = try #require(nextBlocks.first { $0.hasReflowedText })
    #expect(opening.text.hasPrefix("ity of the Federal Reserve"))
    #expect(!opening.followsCroppedText)

    var blocks: [ReflowBlock] = []
    LayoutReconstructor.appendPage(startBlocks, page: start, previousPage: nil, to: &blocks,
                                   vocabulary: ["majority"], warnings: &warnings)
    LayoutReconstructor.appendPage(nextBlocks, page: next, previousPage: start, to: &blocks,
                                   vocabulary: ["majority"], warnings: &warnings)
    #expect(paragraphTexts(blocks).contains {
        $0.contains("The vast majority of the Federal Reserve’s assets are securities holdings.")
    })
    #expect(!blocks.contains { $0.content == .sourcePage(48) })
}

/// The second control. Page 103 sets figure 6.9 over its foot and page 104 opens with the
/// running head and then `and Printing (BEP), and the United States Secret Service…`, which
/// continues `…the Fed works with the Bureau of Engraving`. A figure's title and its callouts
/// are not the page's prose and stand on the page before in any case (#203, #267).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/267"))
func aFigureAtTheFootOfThePageBeforeStillJoins() throws {
    let first = try SourceLayoutFixture.load("fed-103")
    let second = try SourceLayoutFixture.load("fed-104")
    #expect(second.sourceSHA256 == first.sourceSHA256)
    var start = first.content(), next = second.content()
    start.lines.removeAll {
        $0.text == "Fostering Payment and Settlement System Safety and Efficiency" || $0.text == "99"
    }
    next.lines.removeAll { $0.text == "100" || $0.text == "The Fed Explained: What the Central Bank Does" }

    var warnings: [ConversionWarning] = []
    let startBlocks = cropBlocks(start, warnings: &warnings)
    let nextBlocks = cropBlocks(next, warnings: &warnings)
    let opening = try #require(nextBlocks.first { $0.hasReflowedText })
    #expect(opening.text.hasPrefix("and Printing (BEP)"))
    #expect(!opening.followsCroppedText)

    var blocks: [ReflowBlock] = []
    LayoutReconstructor.appendPage(startBlocks, page: start, previousPage: nil, to: &blocks,
                                   vocabulary: [], warnings: &warnings)
    LayoutReconstructor.appendPage(nextBlocks, page: next, previousPage: start, to: &blocks,
                                   vocabulary: [], warnings: &warnings)
    #expect(paragraphTexts(blocks).contains {
        $0.contains("Bureau of Engraving and Printing (BEP), and the United States Secret Service")
    })
    #expect(!blocks.contains { $0.content == .sourcePage(104) })
}

/// The third control, and the one the measure is for. The 9/11 report runs its boxed list of
/// *Operational Opportunities* over the foot of page 373 and the head of page 374, and the crop
/// on page 374 holds twenty-one lines of prose standing above the first line the page reflows.
/// All of it is indented onto the box's own measure, 24 points in from the body, so the page's
/// own text still begins where it reads and `…the deputy director argued that all involved were`
/// / `responsible for making it work.` is the join the page asks for (#203, #267).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/267"))
func aBoxedListSetOnItsOwnMeasureStillJoins() throws {
    let first = try SourceLayoutFixture.load("911-373")
    let second = try SourceLayoutFixture.load("911-374")
    #expect(second.sourceSHA256 == first.sourceSHA256)
    var start = first.content(), next = second.content()
    start.lines.removeAll { $0.text == "FORESIGHT—AND HINDSIGHT 355" }
    next.lines.removeAll { $0.text == "356 THE 9/11 COMMISSION REPORT" }

    var warnings: [ConversionWarning] = []
    let startBlocks = cropBlocks(start, warnings: &warnings)
    let nextBlocks = cropBlocks(next, warnings: &warnings)
    #expect(paragraphTexts(startBlocks).last?.hasSuffix("all involved were") == true)
    let opening = try #require(nextBlocks.first { $0.hasReflowedText })
    #expect(opening.text.hasPrefix("responsible for making it work."))
    // The box's prose stands above the opening and reads as the page's prose; what keeps it from
    // refusing the join is that the page set it on a measure of its own.
    let boxed = try #require(next.lines.first { $0.text.hasPrefix("with the Cole investigators") })
    let body = try #require(next.lines.first { $0.text.hasPrefix("responsible for making it work.") })
    #expect(LayoutReconstructor.readsAsSentence(boxed))
    #expect(boxed.rect.minY > body.rect.minY)
    #expect(boxed.rect.minX - body.rect.minX > 24)
    #expect(!opening.followsCroppedText)

    var blocks: [ReflowBlock] = []
    LayoutReconstructor.appendPage(startBlocks, page: start, previousPage: nil, to: &blocks,
                                   vocabulary: [], warnings: &warnings)
    LayoutReconstructor.appendPage(nextBlocks, page: next, previousPage: start, to: &blocks,
                                   vocabulary: [], warnings: &warnings)
    #expect(paragraphTexts(blocks).contains {
        $0.contains("all involved were responsible for making it work.")
    })
    #expect(!blocks.contains { $0.content == .sourcePage(374) })
}

/// What counts as the page's prose, and where it has to stand. A crop's writing is read the way
/// every other crop rule reads it — four or more words of two letters or more (#255) — so a
/// figure's number or an axis label above the first line does not refuse the page. The row is
/// part of reading order: Wallace's page 344 prints `values into x =` at the measure and sets
/// the quadratic formula beside it, so the cropped half stands *before* the line that reflows
/// without standing above it (#267).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/267"))
func onlyProseThePagePrintedBeforeItsFirstReflowedLineRefusesTheJoin() {
    let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
    func line(_ text: String, x: Double = 85, y: Double, width: Double = 300) -> TextLine {
        TextLine(text: text, rect: CGRect(x: x, y: y, width: width, height: 12), fontSize: 12)
    }
    func page(_ lines: [TextLine]) -> PageContent {
        PageContent(number: 2, bounds: bounds, lines: lines, graphics: [])
    }
    func cropTookTheOpening(_ lines: [TextLine], taken: Set<Int>) -> Bool {
        let content = page(lines)
        let elements = lines.indices.filter { !taken.contains($0) }
            .map { LayoutReconstructor.Element(rect: lines[$0].rect, line: lines[$0]) }
        return LayoutReconstructor.cropTookThePageOpening(
            LayoutReconstructor.ordered(elements, bodySize: 12), taken: taken, page: content,
            body: 12, rightToLeft: false)
    }
    let opening = line("to find a missing side.", y: 730)
    let prose = line("b are the other two sides (legs), then we can use", y: 744)
    // Prose a crop took, standing above the first line the page reflows, on its own measure.
    #expect(cropTookTheOpening([prose, opening], taken: [0]))
    // The same words, still printed: nothing was taken, so the page begins where it reads.
    #expect(!cropTookTheOpening([prose, opening], taken: []))
    // A figure's own writing is not the page's prose.
    #expect(!cropTookTheOpening([line("Figure 6.9.", y: 744, width: 60), opening], taken: [0]))
    // A sidebar's prose is set on a measure of its own, which is not the page's.
    #expect(!cropTookTheOpening([line("b are the other two sides (legs), then we can use", x: 98, y: 744),
                                 opening], taken: [0]))
    // Page 344's shape: the cropped piece stands earlier along the same printed row.
    #expect(cropTookTheOpening([line("values into x =", y: 730, width: 140),
                                line("and we will get our two solutions.", x: 240, y: 730)], taken: [0]))
    // The mirror image: a crop later along the row took nothing the page printed first.
    #expect(!cropTookTheOpening([line("and we will get our two solutions.", y: 730, width: 140),
                                 line("values into x =", x: 240, y: 730)], taken: [1]))
    // Prose a crop took below the page's opening line is not before it.
    #expect(!cropTookTheOpening([opening, line("b are the other two sides (legs), then we can use", y: 700)],
                                taken: [1]))
}
