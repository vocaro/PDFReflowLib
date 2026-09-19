import Foundation
import Testing
@testable import PDFReflowLib

@Test(arguments: ["faa-91", "faa-511"])
func faaSourceColumnsCompleteBeforeTheNextColumn(name: String) throws {
    let fixture = try SourceLayoutFixture.load(name)
    #expect(fixture.sourceSHA256 == "247929cace0ab56b376e683eba540cc4c8f39f199ab35414e8b604e24f395cb7")
    var page = fixture.content()
    // Exclude the source footer, which the full-document furniture pass removes.
    page.lines.removeAll { $0.text == "4-4" || $0.text == "G-35" }
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings)
    let text = blocks.map(\.text).joined(separator: " ")
    let endings = name == "faa-91" ? ["must be defined.", "identify the same level."]
        : ["Wind direction indicators.", "Wind shear.", "restricted areas, obstructions and other pertinent data."]
    let right = try #require(text.range(of: name == "faa-91" ? "The computation of density altitude" : "Zone of confusion."))
    for ending in endings {
        #expect(try #require(text.range(of: ending)).lowerBound < right.lowerBound)
    }
    // Every extracted line must still contribute its words; ordering cannot discard a column.
    let sourceCharacters = page.lines.flatMap { $0.text.filter { !$0.isWhitespace } }.sorted()
    #expect(text.filter { !$0.isWhitespace }.sorted() == sourceCharacters)
}

@Test func algebraSourceBaselineSurvivesAsASquaredExponent() throws {
    let fixture = try SourceLayoutFixture.load("algebra-343")
    #expect(fixture.sourceSHA256 == "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678")
    let line = try #require(fixture.attributedLines.first { $0.text.contains("quadratic is ax2") })
    #expect(line.runs.contains { $0.text.trimmingCharacters(in: .whitespaces) == "2" && $0.baselineOffset > 4 })
    let model = NativeTextReader.inlineText(from: line.attributedString())
    #expect(model.text == line.text)
    let html = EPUBTextEncoder.inline(model)
    #expect(html.contains("ax<sup>2"))
    #expect(html.contains("</sup>"))
    #expect(html.contains("+ bx + c = 0. We will now solve this for-"))
}

@Test func flagSourceTablePreservesBothHeadersAndAllTenRowsTogether() throws {
    let fixture = try SourceLayoutFixture.load("flag-27")
    #expect(fixture.sourceSHA256 == "a47a3153b649022a52b53e7b0c40b55bfea24e7980bbe32fe6fee0cf1936bbd8")
    let page = fixture.content()
    let header = try #require(page.lines.first { $0.text.contains("FLAGPOLE HEIGHT") })
    #expect(header.text.contains("FLAG SIZE (FT.)"))
    let regions = LayoutReconstructor.graphicsWithLabels(page)
    let table = try #require(regions.first { $0.contains(header.rect) })
    let reference = [("20", "4x6"), ("25", "5x8"), ("40", "6x10"), ("50", "8x12"),
                     ("60", "10x15"), ("70", "12x18"), ("90", "15x25"), ("125", "20x30"),
                     ("200", "30x40"), ("250", "40x50")]
    for (height, size) in reference {
        let line = try #require(page.lines.first { $0.text.hasPrefix(height + " .") })
        let cells = line.text.replacingOccurrences(of: #"(?:\.\s*){3,}"#, with: "|", options: .regularExpression)
            .split(separator: "|").map { $0.filter { !$0.isWhitespace } }
        #expect(cells == [height, size])
        #expect(table.contains(line.rect))
    }
    #expect(table.width < page.bounds.width * 0.6 && table.height < page.bounds.height * 0.3)
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: regions.enumerated().map { ($0.element, "image-\($0.offset)") },
        vocabulary: [], warnings: &warnings)
    let text = blocks.map(\.text).joined(separator: " ")
    #expect(text.contains("never store it until it is completely dry"))
    #expect(text.contains("sizes are shown in the following table:"))
    #expect(!text.contains("FLAGPOLE HEIGHT"))
}

@Test func narrowGuttersStillKeepSpanningHeadingsAndFiguresInPlace() {
    func line(_ text: String, x: Double, y: Double, width: Double) -> LayoutReconstructor.Element {
        let rect = CGRect(x: x, y: y, width: width, height: 12)
        return .init(rect: rect, line: TextLine(text: text, rect: rect, fontSize: 12), image: nil)
    }
    let heading = line("Heading", x: 40, y: 700, width: 490)
    let left = [line("Left 1", x: 40, y: 660, width: 240), line("Left 2", x: 40, y: 640, width: 240)]
    let right = [line("Right 1", x: 292, y: 660, width: 238), line("Right 2", x: 292, y: 640, width: 238)]
    let figure = LayoutReconstructor.Element(rect: CGRect(x: 40, y: 500, width: 490, height: 100), image: "figure")
    let elements = right + [figure, heading] + left
    let ordered = LayoutReconstructor.ordered(elements, bodySize: 12)
    #expect(ordered.map { $0.line?.text ?? $0.image! } == ["Heading", "Left 1", "Left 2", "Right 1", "Right 2", "figure"])
    let single = [line("Third", x: 50, y: 640, width: 200), line("First", x: 40, y: 680, width: 205),
                  line("Second", x: 45, y: 660, width: 210)]
    #expect(LayoutReconstructor.ordered(single, bodySize: 12).map { $0.line!.text } == ["First", "Second", "Third"])
}

@Test func leaderTableControlsSeparateLookupRowsFromContentsAndEllipses() {
    func page(_ strings: [String], gap: Double = 14, mono: Bool = false, header: Bool = true) -> PageContent {
        var lines = strings.enumerated().map { index, text in
            TextLine(text: text, rect: CGRect(x: 40, y: 250 - Double(index) * gap, width: 180, height: 12),
                fontSize: 12, monospaced: mono)
        }
        if header { lines.append(TextLine(text: "Height  Width", rect: CGRect(x: 40, y: 274, width: 180, height: 12), fontSize: 12)) }
        return PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 400, height: 400), lines: lines, graphics: [])
    }
    for rows in [["10 .... 25", "20 .... 50", "30 .... 75"],
                 ["1.5 .... 2.5%", "2.5 .... 3.5%", "3.5 .... 4.5%"],
                 ["10 . . . 4 x 6", "20 . . . 5 x 8", "30 . . . 6 x 10"]] {
        let source = page(rows)
        let region = TableRegionDetector.regions(in: source)
        #expect(region.count == 1)
        #expect(source.lines.allSatisfy { line in region.contains { $0.contains(line.rect) } })
    }
    for source in [
        page(["Chapter 1 .... 10", "Chapter 2 .... 20", "Chapter 3 .... 30"]),
        page(["We waited ... then left.", "He paused ... and spoke.", "She replied ... yes."]),
        page(["10 .... 25", "20 .... 50"]),
        page(["10 .... 25", "20 .... 50", "30 .... 75"], gap: 70),
        page(["10 .... 25", "20 .... 50", "30 .... 75"], mono: true),
        page(["10 .... 25", "20 .... 50", "30 .... 75"], header: false),
    ] { #expect(TableRegionDetector.regions(in: source).isEmpty) }
    var interrupted = page(["10 .... 25", "20 .... 50", "30 .... 75"])
    interrupted.lines.append(TextLine(text: "Intervening explanation", rect: CGRect(x: 40, y: 238, width: 180, height: 12), fontSize: 12))
    #expect(TableRegionDetector.regions(in: interrupted).isEmpty)
}

@Test func narrowGutterDoesNotSeparateNamesFromDescriptions() throws {
    let source = try SourceLayoutFixture.load("911-451")
    var page = source.content()
    page.lines.removeAll { $0.text.hasPrefix("APPENDIX") }
    var warnings: [ConversionWarning] = []
    let text = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings)
        .map(\.text).joined(separator: " ")
    let phrases = ["Abdullah bin Abdul Aziz", "Crown Prince and de facto regent", "Mohdar Abdullah",
                   "Yemeni; student in San Diego", "Sayf al Adl", "Egyptian; high-ranking member",
                   "Mahmud Ahmed", "Director General of Pakistan’s Inter-Services"]
    var previous = text.startIndex
    for phrase in phrases {
        let range = try #require(text.range(of: phrase))
        #expect(range.lowerBound >= previous)
        previous = range.upperBound
    }
}
