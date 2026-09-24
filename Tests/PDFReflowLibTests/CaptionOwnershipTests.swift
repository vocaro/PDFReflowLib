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
    let groups = CaptionParagraphs.groups(lines: page.lines, pictures: page.pictures, figures: crops, body: PageTypography(page: page).body)
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
    let caption = try #require(CaptionParagraphs.groups(lines: page.lines, pictures: page.pictures, figures: crops, body: 10).first)
    let writing = caption.lines
    #expect(writing.allSatisfy { $0.structure?.group == writing.first?.structure?.group })
    func hasCaption(_ lines: [TextLine], _ pictures: [CGRect]) -> Bool {
        CaptionParagraphs.groups(lines: lines, pictures: [], figures: pictures, body: 10).contains { $0.lines.first?.text.hasPrefix("Figure 2-5.") == true }
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

@Test func parentheticalTableReferenceStaysInItsSourceCaption() throws {
    let page = try captionSource("noaa-caption-71")
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    let group = try #require(CaptionParagraphs.groups(lines:page.lines,pictures:page.pictures,figures:crops,
        body:PageTypography(page:page).body).first { $0.lines.first?.text.hasPrefix("Figure 1.13.") == true })
    #expect(group.lines.contains { $0.text.hasPrefix("Table 3 in the Guide") })
    #expect(group.lines.last?.text.hasSuffix("Arias et al. 2021.") == true)
    let expected = captionCanonical(group.lines.map(\.text).joined(separator:" "))
    #expect(captionBlocks(page).contains { block in
        if case .paragraph = block.content { return captionCanonical(block.text) == expected };return false
    })
}

@Test func inlineFigureReferenceDoesNotClaimBodyAsACaption() throws {
    let page = try captionSource("faa-caption-114")
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    let groups = CaptionParagraphs.groups(lines:page.lines,pictures:page.pictures,figures:crops,
        body:PageTypography(page:page).body)
    #expect(!groups.contains { $0.lines.contains { $0.text.hasPrefix("Figure 5-23 is not enough") } })
    let expected = "The downwash of the wings is reduced and the force at T in Figure 5-23 is not enough to hold the horizontal stabilizer down."
    #expect(captionBlocks(page).contains { block in
        if case .paragraph = block.content { return captionCanonical(block.text).contains(captionCanonical(expected)) };return false
    })
}

@Test func vectorTableCropDoesNotReleaseUnlabeledSmallCellsAsCaptions() throws {
    let page = try captionSource("noaa-caption-363")
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    let groups = CaptionParagraphs.groups(lines:page.lines,pictures:page.pictures,figures:crops,
        body:PageTypography(page:page).body)
    #expect(!groups.contains { $0.lines.contains { $0.text.contains("Plant genotypes and species considered") } })
    // The actual source cell remains in the preserved table region; no new unlabeled
    // paragraph may mix it with a different column's Tribal adaptation cell.
    #expect(!captionBlocks(page).contains { $0.text.contains("Plant genotypes and species considered") })
}

@Test func aNewCaptionStillStopsAfterTheParentheticalReferenceCloses() {
    let words = ["Figure 1. This caption describes the complete observations across this region.",
                 "Those observations establish conditions throughout the region (see also",
                 "Table 1 for the complete observations across this entire region).",
                 "Figure 2. A different caption describes another independent illustrated result."]
    let lines = words.enumerated().map { TextLine(text:$0.element,
        rect:CGRect(x:20,y:200-Double($0.offset)*12,width:340,height:11),fontSize:10) }
    let groups = CaptionParagraphs.groups(lines:lines,pictures:[],
        figures:[CGRect(x:20,y:214,width:340,height:100)],body:10)
    #expect(groups.first?.lines.map(\.text) == Array(words.prefix(3)))
    var unclosed = lines
    unclosed[2] = TextLine(text:words[2].replacingOccurrences(of:")",with:""),
        rect:lines[2].rect,fontSize:10)
    #expect(CaptionParagraphs.groups(lines:unclosed,pictures:[],
        figures:[CGRect(x:20,y:214,width:340,height:100)],body:10).isEmpty)
}

@Test(arguments: [102,105,111])
func unlabeledFedProseBesideVectorChartsKeepsItsParagraph(number: Int) throws {
    let page = try captionSource("fed-caption-\(number)")
    let phrase = [
        102: "Financial institutions and other parties use this service to hold, maintain, and transfer securities issued by the U.S. Treasury and other federal agencies, government-sponsored enterprises, and certain international organizations, such as the World Bank.",
        105: "For more information about the value and volume of currency in circulation and the volume, value, and cost of the new currency print order, visit the Payment Systems section of the Federal Reserve Board’s website, https://www.federalreserve.gov/paymentsystems. htm.",
        111: "Note: Quarterly averages of daily data. The Federal Reserve measures each depository institution’s account balance at the end of each minute during the business day. An institution’s peak daylight overdraft for a given day is its largest negative end-of-minute balance. The System peak daylight overdraft for a given day is determined by adding the negative account balances of all depository institutions at the end of each minute and then selecting the largest negative end-of-minute balance. The average daylight overdraft for a given day is the sum of the average per-minute daylight overdrafts for all institutions on that day. Further data regarding peak and average daylight overdrafts is available in the Payment Systems section of the Federal Reserve Board’s website, https://www. federalreserve.gov/paymentsystems.htm."
    ][number]!
    let blocks = captionBlocks(page)
    #expect(blocks.contains { block in
        if case .paragraph = block.content { return captionCanonical(block.text).contains(captionCanonical(phrase)) }; return false
    })
}

@Test func noaaPhotoCaptionPrecedesTheBodyPrintedBelowIt() throws {
    let page = try captionSource("noaa-caption-65")
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    #expect(!crops.isEmpty)
    let blocks = captionBlocks(page)
    let first = try #require(blocks.firstIndex { $0.text.hasPrefix("(top left; Fort Myers Beach") })
    let body = try #require(blocks.firstIndex { $0.text.hasPrefix("Many US households") })
    #expect(first < body)
}
