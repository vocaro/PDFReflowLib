import Foundation
import Testing
@testable import PDFReflowLib

// #103: a heading left at the foot of a horizontal cut's upper part reads inside the columns above
// it, and stacked sections of heading rows over two columns interleave (DGA pages 4 and 9). #105:
// bare Roman folios in the FAA front matter are kept as paragraphs (page 7's `viii`).

private let dgaSHA256 = "c34f1bec5c9416265670b7fcb24556bb8616ba95e8de2f2890460b6bbca1a472"
private let faaSHA256 = "247929cace0ab56b376e683eba540cc4c8f39f199ab35414e8b604e24f395cb7"

/// The page as the pipeline reconstructs it: the running foot the furniture pass removes is gone,
/// and preserved regions come from `graphicsWithLabels`.
private func pipelineBlocks(_ fixture: SourceLayoutFixture, pageSizedBackground: Bool = false) -> [ReflowBlock] {
    var page = fixture.content()
    page.lines.removeAll { $0.rect.maxY < 60 }
    // DGA page 4 draws its text over a page-sized graphic, so the pipeline keeps the page as a
    // reference image and reflows the text without graphics, tints or separators.
    if pageSizedBackground { page.graphics = []; page.tints = []; page.separators = [] }
    let regions = LayoutReconstructor.graphicsWithLabels(page).enumerated().map { ($0.element, "image-\($0.offset)") }
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: regions, vocabulary: [], warnings: &warnings)
}

private func index(of prefix: String, in blocks: [ReflowBlock]) throws -> Int {
    try #require(blocks.firstIndex { $0.text.hasPrefix(prefix) }, "no block opens with \(prefix)")
}

private func element(_ text: String, x: Double, y: Double, width: Double, size: Double = 12) -> LayoutReconstructor.Element {
    let rect = CGRect(x: x, y: y, width: width, height: size * 1.3)
    return .init(rect: rect, line: TextLine(text: text, rect: rect, fontSize: size))
}

private func texts(_ elements: [LayoutReconstructor.Element]) -> [String] {
    elements.map { $0.line?.text ?? "figure" }
}

@Test func dgaHeadingFollowsTheLastBulletsSubItemsAndPrecedesItsOwnBullets() throws {
    let fixture = try SourceLayoutFixture.load("dga-4")
    #expect(fixture.sourceSHA256 == dgaSHA256)
    let result = pipelineBlocks(fixture, pageSizedBackground: true)
    let leftLast = try index(of: "+ If preferred, flavor with salt", in: result)
    let rightFirst = try index(of: "+ 100% fruit or vegetable juice", in: result)
    let goals = try index(of: "+ Vegetables and fruits serving goals", in: result)
    let vegetables = try index(of: "- Vegetables: 3 servings per day", in: result)
    let fruits = try index(of: "- Fruits: 2 servings per day", in: result)
    let heading = try index(of: "Incorporate Healthy Fats", in: result)
    let fats = try index(of: "+ Healthy fats are plentiful", in: result)
    #expect(leftLast < rightFirst)
    #expect([goals, vegetables, fruits, heading, fats] == Array(goals...(goals + 4)))
    guard case .heading = result[heading].content else { Issue.record("not a heading"); return }
    // The page's other headings keep their places.
    #expect(try index(of: "Eat Vegetables & Fruits Throughout the Day", in: result) == 0)
    #expect(try index(of: "Focus on Whole Grains", in: result) + 1 == index(of: "+ Prioritize fiber-rich", in: result))
}

@Test func dgaOlderAdultsReadsEachColumnWhole() throws {
    let fixture = try SourceLayoutFixture.load("dga-9")
    #expect(fixture.sourceSHA256 == dgaSHA256)
    let result = pipelineBlocks(fixture)
    let text = result.map(\.text)
    let heading = try index(of: "Older Adults", in: result)
    let bullet = try index(of: "+ Some older adults", in: result)
    // The heading, its band (a preserved region), the left column's five lines, then the right
    // column's five. The column break still opens a paragraph: no rule joins prose from one
    // column's foot to the next column's head.
    #expect(bullet == heading + 2)
    guard case .image = result[heading + 1].content else { Issue.record("no band after the heading"); return }
    #expect(text[bullet] == "+ Some older adults need fewer calories but still require equal or greater amounts of key "
        + "nutrients such as protein, vitamin B12, vitamin D, and calcium. To meet these needs, they should prioritize "
        + "nutrient-dense foods such as dairy, meats, seafood,")
    #expect(text[bullet + 1] == "eggs, legumes, and whole plant foods (vegetables and fruits, whole grains, nuts, and seeds). "
        + "When dietary intake or absorption is insufficient, fortified foods or supplements may be needed under medical supervision.")
    // Sections whose tags apply are unchanged: whole bullets across both columns.
    #expect(text.contains { $0.hasPrefix("+ Lactation increases") && $0.hasSuffix("and vitamin A–rich vegetables.") })
    #expect(text.contains { $0.hasPrefix("+ Pregnant women should") && $0.hasSuffix("(e.g., salmon, sardines, trout).") })
}

@Test func headingAtTheFootOfACutReadsWithThePartBelow() {
    // DGA page 4's geometry: a title across both columns 14.5 pt over them, a heading beneath the
    // left column, then the next bullet row. The band under the heading (15 pt) is wider than the
    // band over it (14 pt), so the heading is cut away with the columns and, once the title is
    // cut off, has no columns beneath it for `headingBand` to find.
    let columns = [
        element("Section Title Across Both Columns", x: 110, y: 550.1, width: 410, size: 18),
        element("+ left column bullet", x: 120, y: 520, width: 180),
        element("+ right column bullet", x: 360, y: 520, width: 180),
        element("- right sub-item", x: 378, y: 500, width: 120),
    ]
    let heading = element("Next Section", x: 110, y: 462.6, width: 170, size: 18)
    let below = [element("+ next section bullet", x: 120, y: 432, width: 180),
                 element("+ its right column", x: 360, y: 432, width: 180)]
    #expect(texts(LayoutReconstructor.ordered(columns + [heading] + below, bodySize: 12)) == [
        "Section Title Across Both Columns", "+ left column bullet", "+ right column bullet", "- right sub-item", "Next Section",
        "+ next section bullet", "+ its right column",
    ])
    let cut = (447.6 + 462.6) / 2
    #expect(LayoutReconstructor.trailingHeading(columns + [heading] + below, cut: cut, bodySize: 12)
        .map { abs($0 - 493) < 0.01 } == true)
    // Negative controls: a body-type line or a list line at that foot stays where the cut left it,
    // and so does a heading with no band of its own above it.
    for foot in [element("a closing line", x: 110, y: 462.6, width: 170),
                 element("1. Next Section", x: 110, y: 462.6, width: 170, size: 18),
                 element("Next Section", x: 110, y: 471.6, width: 170, size: 18)] {
        #expect(LayoutReconstructor.trailingHeading(columns + [foot] + below, cut: cut, bodySize: 12) == nil)
    }
}

@Test func headingRowWithAFigureSeparatesStackedSections() {
    // A section's two columns, then a heading and its decorative band 10 pt beneath them, then the
    // next section's columns 8 pt beneath the row: no whitespace cut, and the band hides the gutter.
    let banner = LayoutReconstructor.Element(rect: CGRect(x: 127, y: 257, width: 475, height: 33), image: "band")
    let heading = element("Older Adults", x: 36, y: 263, width: 90, size: 18)
    let above = [element("+ Lactation increases energy and needs", x: 54, y: 316, width: 230),
                 element("B12–rich protein sources such as meats,", x: 63, y: 300, width: 230),
                 element("eggs, and dairy; omega-3–rich seafood;", x: 334, y: 316, width: 237),
                 element("legumes; and vitamin A–rich vegetables.", x: 334, y: 300, width: 192)]
    let below = [element("+ Some older adults need fewer calories", x: 55, y: 232, width: 228),
                 element("require equal or greater amounts of key", x: 64, y: 216, width: 231),
                 element("eggs, legumes, and whole plant foods", x: 335, y: 232, width: 236),
                 element("and fruits, whole grains, nuts, and seeds", x: 335, y: 216, width: 225)]
    let all = above + [heading, banner] + below
    #expect(texts(LayoutReconstructor.ordered(all, bodySize: 12)) == [
        "+ Lactation increases energy and needs", "B12–rich protein sources such as meats,",
        "eggs, and dairy; omega-3–rich seafood;", "legumes; and vitamin A–rich vegetables.",
        "Older Adults", "figure",
        "+ Some older adults need fewer calories", "require equal or greater amounts of key",
        "eggs, legumes, and whole plant foods", "and fruits, whole grains, nuts, and seeds",
    ])
    // Negative controls: no figure in the row; body-type text beside the band; a figure reaching
    // into a column line above; nothing below the row.
    let plain = element("Older Adults", x: 36, y: 263, width: 90)
    let tall = LayoutReconstructor.Element(rect: CGRect(x: 127, y: 257, width: 475, height: 50), image: "band")
    for elements in [above + [heading] + below, above + [plain, banner] + below,
                     above + [heading, tall] + below, above + [heading, banner]] {
        #expect(LayoutReconstructor.headingRow(elements, bodySize: 12) == nil)
    }
}

@Test func faaFrontMatterRomanFoliosAreFurniture() throws {
    let names = ["faa-5", "faa-6-tagged", "faa-7", "faa-8"]
    let fixtures = try names.map { try SourceLayoutFixture.load($0) }
    #expect(fixtures.allSatisfy { $0.sourceSHA256 == faaSHA256 })
    var pages = fixtures.map { $0.content() }
    let original = pages
    let warnings = LayoutReconstructor.stripFurniture(&pages)
    // `vii`, `viii` and `ix` number pages 6–8 one past the physical page. Page 5's `v` numbers it
    // exactly, an offset no other page here shares, so its one page is no run and it stays.
    #expect(warnings.map(\.page) == [6, 7, 8])
    for (before, after) in zip(original, pages) {
        let removed = before.lines.map(\.text).filter { text in !after.lines.contains { $0.text == text } }
        #expect(removed == (before.number == 5 ? [] : [["vii", "viii", "ix"][before.number - 6]]), "page \(before.number)")
        #expect(after.lines.count == before.lines.count - removed.count)
    }
    // Page 7 no longer emits its folio, which reading order had moved to the top of the page.
    var warningsOut: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: pages[2], images: [], vocabulary: [], warnings: &warningsOut)
    #expect(!blocks.contains { $0.text == "viii" })
    #expect(blocks.contains { $0.text == "Chapter 3" })
    // Negative control: two pages of the run are not three.
    var pair = Array(original[1...2])
    #expect(LayoutReconstructor.stripFurniture(&pair).isEmpty)
}

@Test func bareRomanFoliosNeedTheRunBandAndCanonicalSpelling() {
    func page(_ number: Int, foot: String, y: Double = 30) -> PageContent {
        PageContent(number: number, bounds: CGRect(x: 0, y: 0, width: 600, height: 800), lines: [
            TextLine(text: "Body paragraph \(number) stays available.", rect: CGRect(x: 40, y: 700, width: 400, height: 12), fontSize: 12),
            TextLine(text: foot, rect: CGRect(x: 36, y: y, width: 12, height: 12), fontSize: 10),
        ], graphics: [])
    }
    func removed(_ feet: [String], first: Int = 3, y: [Double]? = nil) -> [Int] {
        var pages = feet.enumerated().map { page(first + $0.offset, foot: $0.element, y: y?[$0.offset] ?? 30) }
        return LayoutReconstructor.stripFurniture(&pages).map(\.page)
    }
    // One letter alone is a numeral as well: `iii`, `iv`, `v`.
    #expect(removed(["iii", "iv", "v"]) == [3, 4, 5])
    #expect(removed(["v", "vi", "vii"], first: 4) == [4, 5, 6])
    // A bare folio may shift within the band as other folios do: FAA page 13 sets `xiv` at 2.8% of
    // the page height where its neighbours sit at 5.2%.
    #expect(removed(["xiii", "xiv", "xv"], first: 13, y: [30, 11, 30]) == [13, 14, 15])
    // Negative controls: an offset that changes, a non-canonical spelling, a word, a line above
    // the footer band, and Arabic numbers of equal value that cannot extend a Roman run.
    #expect(removed(["iii", "v", "vi"]).isEmpty)
    #expect(removed(["iii", "iiii", "v"]).isEmpty)
    #expect(removed(["iii", "did", "v"]).isEmpty)
    #expect(removed(["iii", "iv", "v"], y: [30, 30, 100]).isEmpty)
    #expect(removed(["iii", "4", "v"]).isEmpty)
}
