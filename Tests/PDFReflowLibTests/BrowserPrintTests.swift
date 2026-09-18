import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// Browser prints of web pages (#167): the print footer a site stacks at every page's foot, the
// browser's own `N/M` page count, list bullets drawn as shapes, nested list indents measured from
// the item's text, addresses broken inside a word, and titles on a page whose crops hold the type.

/// A letter page with body text and the TechPort print footer's geometry: `Printed on` over the
/// time at the left, the notice over the URL in the middle, `Page N` at the right, rows closer
/// together than a line height, beside a logo drawn above the time.
private func printedPage(_ number: Int, time: String = "03:51 PM CDT", bodyFoot: Double = 225) -> PageContent {
    func line(_ text: String, _ x: Double, _ y: Double, _ width: Double, size: Double = 8.2, height: Double = 10) -> TextLine {
        TextLine(text: text, rect: CGRect(x: x, y: y, width: width, height: height), fontSize: size)
    }
    return PageContent(number: number, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: [
        line("Body paragraph \(number) stays in the reading flow.", 36, 600, 340, size: 9, height: 10.9),
        line("Its last line stands well above the foot.", 36, bodyFoot, 200, size: 9, height: 10.9),
        line("Printed on 08/24/2021", 36, 47, 94.8),
        line(time, 36, 36.5, 59.7),
        line("For more information and an accessible alternative, please visit:", 187.3, 54.5, 267.3),
        line("https://techport.nasa.gov/view/97058", 241, 44, 160),
        line("Page \(number)", 547.9, 54.5, 28.1),
    ], graphics: [CGRect(x: 40.6, y: 60, width: 87.3, height: 18.7)])
}

@Test func aStackedPrintFooterAndTheLogoBesideItLeaveEveryPage() {
    var pages = (1...5).map { printedPage($0) }
    let warnings = LayoutReconstructor.stripFurniture(&pages)
    #expect(warnings.map(\.page) == Array(1...5))
    for page in pages {
        #expect(page.lines.map(\.text) == ["Body paragraph \(page.number) stays in the reading flow.",
                                           "Its last line stands well above the foot."])
        #expect(page.graphics.isEmpty)
    }
}

@Test func aStackedFootLeavesOnlyWholeAndOnlyWhereItRepeats() {
    // One line of the stack changes on every page: no line of it repeats on its own evidence, so
    // the rest of the stack stays with it, and so does the logo, which no removed line stands beside.
    var changing = (1...5).map { printedPage($0, time: "03:5\($0) PM CDT") }
    #expect(LayoutReconstructor.stripFurniture(&changing).isEmpty)
    #expect(changing.allSatisfy { $0.lines.count == 7 && $0.graphics.count == 1 })
    // Two printed pages are too few for a run.
    var short = (1...2).map { printedPage($0) }
    #expect(LayoutReconstructor.stripFurniture(&short).isEmpty)
    // A body reaching down onto the stack joins it; the block then passes the page's outer eighth
    // and nothing is taken.
    var crowded = (1...5).map { printedPage($0, bodyFoot: 66) }
    for index in crowded.indices {
        for y in [78.0, 90] {
            crowded[index].lines.insert(TextLine(text: "A closing paragraph line.", rect: CGRect(x: 36, y: y, width: 300, height: 10.9),
                                                 fontSize: 9), at: 1)
        }
    }
    #expect(LayoutReconstructor.stripFurniture(&crowded).isEmpty)
}

@Test func aBrowsersPageCountGoesWithItsUrlRow() {
    // Chromium's own footer: the URL at the left and `N/M` at the right of one row.
    var pages = (1...4).map { number in
        PageContent(number: number, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: [
            TextLine(text: "Body paragraph \(number).", rect: CGRect(x: 36, y: 600, width: 300, height: 12), fontSize: 10),
            TextLine(text: "https://example.gov/page", rect: CGRect(x: 20, y: 14, width: 120, height: 8), fontSize: 7),
            TextLine(text: "\(number)/4", rect: CGRect(x: 580, y: 14, width: 12, height: 8), fontSize: 7),
        ], graphics: [])
    }
    #expect(LayoutReconstructor.stripFurniture(&pages).map(\.page) == Array(1...4))
    #expect(pages.allSatisfy { $0.lines.map(\.text) == ["Body paragraph \($0.number)."] })
    // A fixed `9/11` does not count the pages.
    var fixed = (1...4).map { number in
        PageContent(number: number, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: [
            TextLine(text: "Body paragraph \(number).", rect: CGRect(x: 36, y: 600, width: 300, height: 12), fontSize: 10),
            TextLine(text: "Chapter \(number * 7) 9/11", rect: CGRect(x: 520, y: 14, width: 60, height: 8), fontSize: 7),
        ], graphics: [])
    }
    #expect(LayoutReconstructor.stripFurniture(&fixed).isEmpty)
}

/// A page setting two 9-point items after 3-point drawn squares (7 points with the graphics
/// reader's padding), as the TechPort print does.
private func bulletPage(secondBullet: Bool = true) -> (page: PageContent, paints: [GraphicsReader.Paint]) {
    var graphics = [CGRect(x: 75.25, y: 637.8, width: 7, height: 7)]
    if secondBullet { graphics.append(CGRect(x: 75.25, y: 613.8, width: 7, height: 7)) }
    graphics.append(CGRect(x: 36, y: 300, width: 300, height: 200))
    let page = PageContent(number: 2, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: [
        TextLine(text: "High accuracy demonstrated on Orion Tank", rect: CGRect(x: 88.5, y: 636.4, width: 300, height: 10.9), fontSize: 9),
        TextLine(text: "Demonstrated with Morpheus static engine firings", rect: CGRect(x: 88.5, y: 612.4, width: 276, height: 10.9), fontSize: 9),
    ], graphics: graphics)
    return (page, graphics.map { GraphicsReader.Paint(rect: $0, frame: false, filled: true) })
}

@Test func shapesDrawnBeforeItemsBecomeTheirBullets() {
    let fixture = bulletPage()
    var page = fixture.page
    DrawnBulletReader.apply(&page, paints: fixture.paints)
    #expect(page.lines.map(\.text) == ["• High accuracy demonstrated on Orion Tank",
                                       "• Demonstrated with Morpheus static engine firings"])
    #expect(page.lines.allSatisfy { abs($0.rect.minX - 77.25) < 0.01 && $0.markerTextEdge == 88.5 })
    // The figure stays; the two squares seed no crops.
    #expect(page.graphics == [CGRect(x: 36, y: 300, width: 300, height: 200)])
}

@Test func aLoneShapeOrADrawnImageIsNoBullet() {
    let fixture = bulletPage(secondBullet: false)
    var lone = fixture.page
    DrawnBulletReader.apply(&lone, paints: fixture.paints)
    #expect(lone == fixture.page)
    var image = bulletPage().page
    let icons = image.graphics.map { GraphicsReader.Paint(rect: $0, frame: false, image: true) }
    let original = image
    DrawnBulletReader.apply(&image, paints: icons)
    #expect(image == original)
}

@Test func aNestedMarkerIsMeasuredFromItsParentsTextWhereTheMarkerWasDrawn() {
    func item(_ text: String, edge: CGFloat, textEdge: CGFloat?) -> ReflowBlock {
        var block = ReflowBlock(content: .preformatted(InlineText(text)), page: 2)
        block.listEvidence = .init(edge: edge, fontSize: 9, textEdge: textEdge)
        return block
    }
    func levels(_ drawn: Bool) -> [Int] {
        var blocks = [item("• Demonstrated with Morpheus", edge: 77.25, textEdge: drawn ? 88.5 : nil),
                      item("• Can use one tank to develop", edge: 129.75, textEdge: drawn ? 141 : nil),
                      item("• Zero-G accuracy is on the order of 1%", edge: 77.25, textEdge: drawn ? 88.5 : nil)]
        ListBuilder.build(&blocks)
        return blocks.compactMap { if case let .listItem(item) = $0.content { item.level } else { nil } }
    }
    // 52.5 points is 5.8 type sizes past the parent's marker, but 4.6 past its text.
    #expect(levels(true) == [0, 1, 0])
    #expect(levels(false) == [0, 0, 0])
}

@Test(arguments: [
    ("The essential signal chain (https://techport.nasa.gov/imag", "e/41317)", "The essential signal chain (https://techport.nasa.gov/imag" + "e/41317)"),
    ("Close Out Report (https://techport.nasa.gov/fi", "le/41595).", "Close Out Report (https://techport.nasa.gov/fi" + "le/41595)."),
    ("see [https://example.gov/data/set", "s/a.csv]", "see [https://example.gov/data/set" + "s/a.csv]"),
    // Controls: the bracket stays open over words, the continuation holds no address separator,
    // or the address closed its bracket already.
    ("(see https://example.gov/a", "for details)", "(see https://example.gov/a for details)"),
    ("(https://example.gov/a", "b)", "(https://example.gov/a b)"),
    ("(https://example.gov/a) and", "b/c)", "(https://example.gov/a) and b/c)"),
])
func anAddressBrokenInsideAWordRejoinsWhereItsBracketCloses(left: String, right: String, joined: String) {
    var warnings: [ConversionWarning] = []
    #expect(LayoutReconstructor.join(left, right, vocabulary: [], page: 1, warnings: &warnings) == joined)
    #expect(warnings.isEmpty)
}

@Test func aBarePageMeasuresTitlesAgainstTheDocumentsBodyNotItsCrops() {
    let text = [TextLine(text: "Tank Health Monitoring Close Out Report and Executive Summary",
                         rect: CGRect(x: 36, y: 298, width: 299, height: 10.9), fontSize: 9),
                TextLine(text: "(https://techport.nasa.gov/file/41595)", rect: CGRect(x: 36, y: 286, width: 175, height: 10.9), fontSize: 9),
                TextLine(text: "Figure 1: essential signal", rect: CGRect(x: 36, y: 175, width: 127, height: 10.9), fontSize: 9),
                TextLine(text: "Closeout Documentation", rect: CGRect(x: 36, y: 318, width: 130, height: 14.3), fontSize: 10.5)]
    // The table text inside the page's crops makes its estimate 10 points.
    #expect(LayoutReconstructor.headingBodySize(text, pageBody: 10, documentBody: 9) == 9)
    #expect(LayoutReconstructor.headingBodySize(text, pageBody: 10) == 10)
    // A page whose own text is not in the document's body keeps the page estimate.
    #expect(LayoutReconstructor.headingBodySize(text, pageBody: 10, documentBody: 11) == 10)
}
