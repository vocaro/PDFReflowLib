import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

private func tocSource(_ number: Int) throws -> (PageContent, [GraphicsReader.Paint]) {
    struct NativeCapture: Decodable { var nativeLines: [TextLine] }
    let fixture = try SourceLayoutFixture.load("noaa-toc-\(number)")
    #expect(fixture.sourceSHA256 == "1942cbf346dc2c711fea413d6d6543edb8bc1e3a88d4c3a85e733c6b6d3577bf")
    var page = fixture.content()
    page.lines = try JSONDecoder().decode(NativeCapture.self,
        from: Data(contentsOf: fixtureURL("noaa-toc-\(number)-layout.json"))).nativeLines
    page = TextBackdrop.compose(page, graphics: .init(regions: page.graphics, unsupported: false,
        images: page.pictures, paints: fixture.paints))
    return (page, fixture.paints)
}

@Test(arguments: [8,19,20])
func noaaContentsKeepPaintedLeaderEntriesWithTheirLocators(number: Int) throws {
    var (page, paints) = try tocSource(number)
    let before = page.lines
    page.lines = LeaderRows.joined(page, paints: paints)
    let numberLines = before.filter { $0.text.range(of: #"^(?:[ivxlcdmIVXLCDM]{1,8}|[A-Z]?[0-9]{1,3}-[0-9]{1,3})$"#,
        options: .regularExpression) != nil }.sorted { $0.rect.midY > $1.rect.midY }
    #expect(numberLines.count == (number == 8 ? 25 : number == 19 ? 28 : 15))
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page,
        images: crops.enumerated().map { ($0.element,"image-\($0.offset)") },
        vocabulary: LayoutReconstructor.vocabulary(in: [page]), warnings: &warnings)
    func normalized(_ text: String) -> String {
        String(text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    let texts = blocks.filter(\.hasReflowedText).map { normalized($0.text) }
    let full = texts.joined(separator: " ")
    var positions: [String.Index] = []
    for numberLine in numberLines {
        let entry = try #require(before.first { $0.rect.maxX < numberLine.rect.minX
            && abs($0.rect.midY - numberLine.rect.midY) < 1 })
        let phrase = normalized(entry.text) + " " + numberLine.text
        #expect(texts.contains { $0.contains(phrase) }, "Page \(number) missing pair: \(phrase)")
        if let range = full.range(of: phrase) { positions.append(range.lowerBound) }
    }
    #expect(positions == positions.sorted())
    // Association changes neither source letters nor styles/links; art remains a crop.
    func characters(_ lines: [TextLine]) -> [Character] { lines.flatMap { $0.text.filter { !$0.isWhitespace } }.sorted() }
    #expect(characters(page.lines) == characters(before))
    #expect(page.lines.flatMap { $0.content.links }.count == before.flatMap { $0.content.links }.count)
    #expect(!crops.isEmpty)
}

@Test func paintedLeadersRequireRepeatedNativeRowsAndPreserveInlineContent() {
    let labels = ["First topic", "Second topic", "Third topic"]
    let rows = labels.enumerated().flatMap { index, text -> [TextLine] in
        let y = CGFloat(200 - index * 20)
        return [TextLine(content: InlineText(text,style:.bold),rect:CGRect(x:20,y:y,width:70,height:12),fontSize:10),
                TextLine(content:InlineText(elements:[.link(.external("https://example.org/\(index)"),InlineText("A1-\(index+1)"))]),
                         rect:CGRect(x:190,y:y,width:25,height:12),fontSize:10)]
    }
    let paints = (0..<3).map { index in
        let y = CGFloat(202-index*20)
        return GraphicsReader.Paint(rect:CGRect(x:92,y:y,width:96,height:4),strokeOnly:true,
            vertices:[CGPoint(x:94,y:y+2),CGPoint(x:186,y:y+2)])
    }
    var page = PageContent(number:1,bounds:CGRect(x:0,y:0,width:300,height:300),lines:rows,graphics:[])
    let joined = LeaderRows.joined(page,paints:paints)
    #expect(joined.count == 3)
    #expect(joined[0].content.elements.contains(.text("First topic",.bold)))
    #expect(joined[0].content.links.first?.text == "A1-1")
    for mode in 0..<7 {
        var control = page, marks = paints
        switch mode {
        case 0: marks = Array(paints.prefix(2))
        case 1: marks = paints.map { var p = $0; p.strokeOnly = false; return p }
        case 2: marks = paints.map { var p = $0; p.vertices[1].y += 10; return p }
        case 3: control.recognized = true
        case 4: control.lines = rows.map { var l = $0; l.turn = .clockwise; return l }
        case 5: control.lines = rows.map { var l = $0; l.structure = TextStructure(group:1,order:0,headingLevel:0,lineCount:6); return l }
        default: control.tables = [PageTable(rect:page.bounds,rows:[[.init(content:InlineText("cell"),rect:page.bounds)]])]
        }
        #expect(LeaderRows.joined(control,paints:marks) == control.lines, "negative control \(mode)")
    }
    page.hasSyntheticTextStyle = true
    #expect(LeaderRows.joined(page,paints:paints) == rows)
}
