import Foundation
import Testing
@testable import PDFReflowLib

private struct CapturedCaptionLines: Decodable { var nativeLines: [TextLine] }
private func captionSource(_ name: String) throws -> PageContent {
    let fixture = try SourceLayoutFixture.load(name)
    let native = try JSONDecoder().decode(CapturedCaptionLines.self,
        from: Data(contentsOf: fixtureURL("\(name)-layout.json")))
    var page = fixture.content()
    page.lines = native.nativeLines
    // The full-document furniture pass removes these verified bottom folios. Keeping them
    // here would hide the cross-column continuation that the actual conversion exercises.
    page.lines.removeAll { $0.rect.maxY < 50 }
    return TextBackdrop.compose(page, graphics: .init(regions: page.graphics, unsupported: false,
        images: page.pictures, paints: fixture.paints))
}
private func captionBlocks(_ page: PageContent) -> [ReflowBlock] {
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: crops.enumerated().map { ($0.element,"image-\($0.offset)") },
        vocabulary: LayoutReconstructor.vocabulary(in: [page]), warnings: &warnings, documentBody: 10)
}
private func captionCanonical(_ text: String) -> String { text.lowercased().filter(\.isLetter) }

@Test(arguments: ["noaa-caption-56", "noaa-caption-58", "noaa-caption-67", "faa-caption-45", "faa-caption-216"])
func sourceCaptionsKeepTheirCompleteNativeRowsAndBodyOwnership(name: String) throws {
    let fixture = try SourceLayoutFixture.load(name)
    #expect(fixture.sourceSHA256 == (name.hasPrefix("noaa")
        ? "1942cbf346dc2c711fea413d6d6543edb8bc1e3a88d4c3a85e733c6b6d3577bf"
        : "247929cace0ab56b376e683eba540cc4c8f39f199ab35414e8b604e24f395cb7"))
    let page = try captionSource(name), crops = LayoutReconstructor.graphicsWithLabels(page)
    let groups = CaptionParagraphs.groups(lines: page.lines, pictures: page.pictures + crops, body: PageTypography(page: page).body)
    let prefix: String
    switch name {
    case "noaa-caption-56": prefix = "(left; Toledo"
    case "noaa-caption-58": prefix = "Figure 1.10."
    case "noaa-caption-67": prefix = "(top; Golden"
    case "faa-caption-45": prefix = "Figure 2-5."
    default: prefix = "Figure 8-15."
    }
    let group = try #require(groups.first { $0.lines.first?.text.hasPrefix(prefix) == true })
    #expect(group.lines.count == ["noaa-caption-56":8,"noaa-caption-58":15,"noaa-caption-67":6,"faa-caption-45":4,"faa-caption-216":4][name])
    // The actual content, including links/emphasis/source metadata, is carried unchanged.
    for line in group.lines { #expect(page.lines.contains(line)) }
    let expectedCaption = captionCanonical(group.lines.map(\.text).joined(separator: " "))
    let blocks = captionBlocks(page)
    let paragraphs = blocks.compactMap { block -> String? in
        if case .paragraph = block.content { return captionCanonical(block.text) }; return nil
    }
    #expect(paragraphs.filter { $0 == expectedCaption }.count == 1)
    let body: String
    switch name {
    case "noaa-caption-56": body = "traditional food sources. Heat-related stress and death are significantly greater for farmworkers than for all US civilian workers."
    case "noaa-caption-58": body = "Extreme events, such as extended drought, wildfire, and major hurricanes, have contributed to human migration and displacement."
    case "noaa-caption-67": body = "reduce opportunities to transfer important knowledge and identity to future generations."
    case "faa-caption-45": body = "The experiences of other pilots, coupled with the forecast, might cause the pilot to assign “occasional” to determine the probability of encountering IMC."
    default: body = "Altitude information is derived from the static pressure port just as an analogue system does; however, the static pressure does not enter a diaphragm."
    }
    #expect(paragraphs.contains { $0.contains(captionCanonical(body)) })
    #expect(!paragraphs.contains { $0.contains(expectedCaption) && $0 != expectedCaption })
    let assets = blocks.compactMap { block -> String? in
        if case .image(let image) = block.content { return image.assetID }; return nil
    }
    #expect(Set(assets) == Set(crops.indices.map { "image-\($0)" }))
    #expect(assets.count == crops.count)
}

@Test func captionOwnershipRejectsIncompleteTagsRemoteFiguresAndChangedRowGeometry() throws {
    let page = try captionSource("faa-caption-45")
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    let caption = try #require(CaptionParagraphs.groups(lines: page.lines, pictures: crops, body: 10).first)
    let writing = caption.lines
    #expect(writing.allSatisfy { $0.structure?.group == writing.first?.structure?.group })
    func hasCaption(_ lines: [TextLine], _ pictures: [CGRect]) -> Bool {
        CaptionParagraphs.groups(lines: lines, pictures: pictures, body: 10).contains { $0.lines.first?.text.hasPrefix("Figure 2-5.") == true }
    }
    #expect(!hasCaption(Array(writing.dropLast()), crops))
    var foreign = writing
    foreign[1].structure?.group += 1
    #expect(!hasCaption(foreign, crops))
    var heading = writing
    for index in heading.indices { heading[index].structure?.headingLevel = 2 }
    #expect(!hasCaption(heading, crops))
    #expect(!hasCaption(writing, crops.map { $0.offsetBy(dx: 1000,dy: 1000) }))
    var broken = writing
    broken[2].rect = broken[2].rect.offsetBy(dx: 0,dy: -30)
    #expect(!hasCaption(broken, crops))
}

@Test func captionMarginMergeDoesNotCombineSimultaneousOrSeparateColumns() {
    func rows(x: CGFloat, y: CGFloat, width: CGFloat) -> [TextLine] {
        (0..<6).map { TextLine(text:"This source row supplies several ordinary prose words.",
            rect:CGRect(x:x,y:y-CGFloat($0)*14,width:width,height:12),fontSize:10) }
    }
    let caption = rows(x:30,y:400,width:200)
    let unit = LayoutReconstructor.Element(rect:union(caption.map(\.rect)),caption:caption)
    let overlapping = rows(x:65,y:400,width:170).map { LayoutReconstructor.Element(rect:$0.rect,line:$0) }
    #expect(PrintedColumns.plan([unit]+overlapping,body:10) == nil)
    let separate = rows(x:260,y:400,width:180).map { LayoutReconstructor.Element(rect:$0.rect,line:$0) }
    #expect(PrintedColumns.plan([unit]+separate,body:10)?.columns.count == 2)
}

@Test func twoRowColumnEndingRequiresAShortTerminalRow() {
    typealias Element = LayoutReconstructor.Element
    func line(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat = 180, size: CGFloat = 10) -> TextLine {
        TextLine(text:text,rect:CGRect(x:x,y:y,width:width,height:11),fontSize:size)
    }
    let left = [80.0,66.0,52.0].map { line("This filled column continues with",x:20,y:$0) }
    let caption = [line("Figure 1. A separate illustrated caption",x:220,y:434,size:9),
                   line("that belongs to the figure above.",x:220,y:420,size:9)]
    let opening = line("the continuation across the column",x:220,y:390)
    let ending = line("and its final words.",x:220,y:376,width:100)
    var elements = left.map { Element(rect:$0.rect,line:$0) }
    elements += [Element(rect:CGRect(x:220,y:455,width:180,height:60),image:"figure"),
                 Element(rect:union(caption.map(\.rect)),caption:caption),
                 Element(rect:opening.rect,line:opening),Element(rect:ending.rect,line:ending)]
    let roles: [LineRole?] = [.prose,.prose,.prose,nil,nil,.prose,.prose]
    #expect(InterruptedColumnContinuation.pairs(elements,roles:roles,body:10) == [5:2])
    var unfinished = elements
    let fragment = line("and further unfinished words",x:220,y:376,width:100)
    unfinished[6] = Element(rect:fragment.rect,line:fragment)
    #expect(InterruptedColumnContinuation.pairs(unfinished,roles:roles,body:10).isEmpty)
    var full = elements
    full[6].line?.rect.size.width = 180
    #expect(InterruptedColumnContinuation.pairs(full,roles:roles,body:10).isEmpty)
}
