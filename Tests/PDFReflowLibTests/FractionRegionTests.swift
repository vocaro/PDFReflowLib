import Foundation
import Testing
@testable import PDFReflowLib

@Test func fractionBarControlsRejectRulesUnderlinesAndUnrelatedProse() {
    func page(_ upper: String, _ lower: String?, width: Double = 40, gap: Double = 7,
              mono: Bool = false) -> PageContent {
        var lines = [TextLine(text: upper, rect: CGRect(x: 165, y: 257, width: 20, height: 12),
                              fontSize: 12, monospaced: mono)]
        if let lower { lines.append(TextLine(text: lower, rect: CGRect(x: 165, y: 248 - gap - 12, width: 20, height: 12),
                                            fontSize: 12, monospaced: mono)) }
        return PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 400, height: 500), lines: lines,
                           graphics: [CGRect(x: 158, y: 248, width: width, height: 4)])
    }
    for source in [page("Heading", "Paragraph"), page("123", nil), page("x", "y", width: 240),
                   page("12", "34", gap: 40), page("foo", "bar", mono: true)] {
        #expect(FractionRegionDetector.regions(in: source).isEmpty)
    }
    for source in [page("36", "84"), page("x+1", "2"), page("a", "b")] {
        let regions = FractionRegionDetector.regions(in: source)
        #expect(regions.count == 1)
        #expect(source.lines.allSatisfy { line in regions.contains { $0.contains(line.rect) } })
    }
    var table = page("36", "84")
    table.graphics = [CGRect(x: 100, y: 180, width: 200, height: 150)]
    #expect(FractionRegionDetector.regions(in: table).isEmpty)
}

@Test func algebraAnswerKeyFractionsKeepBothSourceTerms() throws {
    let source = try SourceLayoutFixture.load("algebra-479")
    let page = source.content()
    let regions = LayoutReconstructor.graphicsWithLabels(page)
    // Source answers 55 and 56 contain -5/2 and -3/2; coordinates distinguish repeated digits.
    for (numerator, y) in [("5", 501.7), ("3", 478.1)] {
        let upper = try #require(page.lines.first { $0.text == numerator && abs($0.rect.minY - y) < 0.1 })
        let lower = try #require(page.lines.first { $0.text == "2" && $0.rect.minX > 350
            && $0.rect.minY < upper.rect.minY && upper.rect.minY - $0.rect.minY < 12 })
        #expect(regions.contains { $0.contains(upper.rect) && $0.contains(lower.rect) })
    }
}

@Test func completeFractionDoesNotGrowTowardUnrelatedNeighboringText() {
    let neighbor = TextLine(text: "Unrelated adjacent prose.", rect: CGRect(x: 40, y: 257, width: 117, height: 12), fontSize: 12)
    let page = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 400, height: 500), lines: [
        neighbor,
        TextLine(text: "36", rect: CGRect(x: 165, y: 251, width: 20, height: 12), fontSize: 12),
        TextLine(text: "84", rect: CGRect(x: 165, y: 239, width: 20, height: 12), fontSize: 12),
    ], graphics: [CGRect(x: 158, y: 248, width: 44, height: 4)])
    #expect(!LayoutReconstructor.graphicsWithLabels(page).contains { $0.intersects(neighbor.rect) })
}
