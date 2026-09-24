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

@Test(arguments: Array(8...20))
func noaaContentsKeepPaintedLeaderEntriesWithTheirLocators(number: Int) throws {
    var (page, paints) = try tocSource(number)
    let before = page.lines
    page.lines = LeaderRows.joined(page, paints: paints)
    let numberLines = before.filter { $0.text.range(of: #"^(?:[ivxlcdmIVXLCDM]{1,8}|[A-Z]?[0-9]{1,3}-[0-9]{1,3})$"#,
        options: .regularExpression) != nil }.sorted { $0.rect.midY > $1.rect.midY }
    #expect(numberLines.count == [8:25,9:27,10:26,11:18,12:19,13:16,14:22,15:20,16:16,17:18,18:22,19:28,20:15][number])
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
        var parts = [entry]
        // A wrapped entry's preceding source row has the same left edge and type, with
        // 11pt baseline leading. Its PDFKit rectangle can overlap the final row's box.
        while let last = parts.last, let prior = before.first(where: {
            abs($0.rect.minX - last.rect.minX) < 1 && abs($0.fontSize - last.fontSize) < 0.1
                && $0.rect.midY - last.rect.midY >= last.fontSize * 0.8
                && $0.rect.midY - last.rect.midY <= last.fontSize * 1.25
        }) { parts.append(prior) }
        let phrase = parts.reversed().map { normalized($0.text) }.joined(separator: " ") + " " + numberLine.text
        #expect(full.contains(phrase), "Page \(number) missing complete entry: \(phrase)")
        // Preserve the original single-row association contract; wrapped entries may span
        // existing paragraph blocks, but their complete source text must remain adjacent.
        if [8,19,20].contains(number) {
            #expect(texts.contains { $0.contains(phrase) }, "Page \(number) detached locator: \(phrase)")
        }
        let restored: [Int: Set<String>] = [9:["4-16"],10:["9-5"],12:["15-17"],
            13:["18-11"],15:["24-21"],16:["27-8","27-21"]]
        if restored[number]?.contains(numberLine.text) == true {
            #expect(page.lines.contains { normalized($0.text) == normalized(entry.text) + " " + numberLine.text })
        }
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

@Test func paintedLeadersDoNotJumpAcrossInterveningNativeText() {
    var rows: [TextLine] = [], paints: [GraphicsReader.Paint] = []
    for index in 0..<3 {
        let y = CGFloat(200 - index * 20)
        rows += [TextLine(text:"Chapter heading",rect:CGRect(x:20,y:y,width:70,height:12),fontSize:10),
                 TextLine(text:"intervening native words",rect:CGRect(x:110,y:y,width:65,height:12),fontSize:10),
                 TextLine(text:"A1-\(index+1)",rect:CGRect(x:190,y:y,width:25,height:12),fontSize:10)]
        paints.append(.init(rect:CGRect(x:92,y:y+2,width:96,height:4),strokeOnly:true,
            vertices:[CGPoint(x:94,y:y+4),CGPoint(x:186,y:y+4)]))
    }
    var page = PageContent(number:1,bounds:CGRect(x:0,y:0,width:300,height:300),lines:rows,graphics:[])
    #expect(LeaderRows.joined(page,paints:paints) == rows)
    // The same leader rows are valid once the unrelated text is outside their corridor.
    for index in [1,4,7] { page.lines[index].rect.origin.x = 230 }
    #expect(LeaderRows.joined(page,paints:paints).count == 6)
}

@Test func paintedLeaderComparisonExhaustionLeavesTheWholePageUnchanged() throws {
    let (page, paints) = try tocSource(19)
    #expect(LeaderRows.joined(page,paints:paints).count < page.lines.count)
    // Even after some pairs have been found, exhaustion cannot return a partial page.
    for limit in [0,100,1_000] {
        #expect(LeaderRows.joined(page,paints:paints,comparisonLimit:limit) == page.lines)
    }
    // These individually admitted input counts previously needed 80 million rule comparisons.
    let labels = (0..<100).map { _ in
        TextLine(text:"A long native row label",rect:CGRect(x:20,y:200,width:70,height:12),fontSize:10)
    }
    let numbers = (0..<100).map { _ in
        TextLine(text:"A1-1",rect:CGRect(x:190,y:200,width:25,height:12),fontSize:10)
    }
    let marks = (0..<8_000).map { _ in
        GraphicsReader.Paint(rect:CGRect(x:92,y:202,width:40,height:4),strokeOnly:true,
            vertices:[CGPoint(x:94,y:204),CGPoint(x:130,y:204)])
    }
    let dense = PageContent(number:1,bounds:page.bounds,lines:labels+numbers,graphics:[])
    #expect(LeaderRows.maximumComparisons == 2_000_000)
    #expect(LeaderRows.joined(dense,paints:marks) == dense.lines)
}

@Test func paintedLeaderObstructionUsesInkBandRatherThanOverlappingLineLeading() {
    var rows: [TextLine] = [], paints: [GraphicsReader.Paint] = []
    for index in 0..<3 {
        let y = CGFloat(200 - index * 40)
        rows += [TextLine(text:"A long entry wraps before",rect:CGRect(x:20,y:y+11,width:140,height:13.27),fontSize:10),
                 TextLine(text:"its final row",rect:CGRect(x:20,y:y,width:70,height:13.27),fontSize:10),
                 TextLine(text:"A1-\(index+1)",rect:CGRect(x:190,y:y,width:25,height:13.27),fontSize:10)]
        paints.append(.init(rect:CGRect(x:92,y:y+2,width:96,height:4),strokeOnly:true,
            vertices:[CGPoint(x:94,y:y+4),CGPoint(x:186,y:y+4)]))
    }
    let page = PageContent(number:1,bounds:CGRect(x:0,y:0,width:300,height:300),lines:rows,graphics:[])
    let joined = LeaderRows.joined(page,paints:paints)
    #expect(joined.count == 6)
    #expect(joined.contains { $0.text == "its final row A1-1" })
    // Moving the first row down so its ink box crosses the leader makes it an obstruction.
    var crossed = page
    for index in [0,3,6] { crossed.lines[index].rect.origin.y -= 9 }
    #expect(LeaderRows.joined(crossed,paints:paints) == crossed.lines)
}
