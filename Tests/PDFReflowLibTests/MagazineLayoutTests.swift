
import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

private func magazinePage(_ family: String, _ number: Int) throws -> PageContent {
    let fixture = try SourceLayoutFixture.load("\(family)-magazine-\(number)")
    let page = fixture.content()
    return TextBackdrop.compose(page, graphics: .init(regions: page.graphics, unsupported: false,
        images: page.pictures, paints: fixture.paints))
}

private func magazineBlocks(_ page: PageContent) -> [ReflowBlock] {
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: crops.enumerated().map { ($0.element, "image-\($0.offset)") },
        vocabulary: LayoutReconstructor.vocabulary(in: [page]), warnings: &warnings)
}

@Test(arguments: [11, 12])
func magazinePullQuotationIsOneSemanticBlock(number: Int) throws {
    let blocks = magazineBlocks(try magazinePage("usda", number))
    let quotes = blocks.filter { if case .quotation = $0.content { true } else { false } }
    #expect(quotes.count == 1)
    let quote = try #require(quotes.first)
    #expect(quote.text.hasPrefix(number == 11 ? "“I was one of those guys" : "“Whenever you get a new"))
    #expect(quote.text.hasSuffix(number == 11 ? "Douglas Burkett" : "Dan Kline"))
    let piece = try EPUBTextEncoder.piece(for: quote, imagePaths: [:])
    #expect(piece.markup.contains("<blockquote><p>"))
    #expect(piece.heading == nil)
}

@Test func magazineFurnitureCopiesLeaveOnlyWithAProvedFoot() throws {
    var pages = try [5,8,9,11,12,16,19,20,21,22,23].map { try magazinePage("usda", $0) }
    let original = try #require(pages.last)
    #expect(original.lines.filter { $0.text == "Agricultural Research l November/December 2012" }.count == 2)
    _ = FurnitureDetector.strip(&pages)
    #expect(pages.last?.lines.contains { $0.text.hasPrefix("Agricultural Research") } == false)
    // Repetition within one page cannot prove a running footer on its own.
    var one = [original]
    #expect(FurnitureDetector.strip(&one).isEmpty)
    #expect(one[0].lines == original.lines)
}

@Test func techportPaintedHeaderRepeatsAsACompleteBand() throws {
    var pages = try (1...5).map { try magazinePage("techport", $0) }
    #expect(pages.allSatisfy { $0.headerBackdrop != nil })
    _ = FurnitureDetector.strip(&pages)
    #expect(pages.allSatisfy { !$0.lines.contains { $0.text.contains("Completed Technology Project") } })
    #expect(pages[0].lines.contains { $0.text == "Project Introduction" })
}

@Test(arguments: [16,21]) func outlinedInitialRequiresThreeNativeWrappedRows(number: Int) throws {
    let fixture = try SourceLayoutFixture.load("usda-magazine-\(number)")
    let page = fixture.content()
    let candidate = try #require(OutlinedInitial.candidates(lines: page.lines, paints: fixture.paints).first)
    #expect(candidate.indices.count == 3)
    let first = page.lines[candidate.indices[0]]
    #expect(first.text.hasPrefix(number == 16 ? "team of" : "rtificial logs"))
    let reduced = page.lines.enumerated().filter { $0.offset != candidate.indices[1] }.map(\.element)
    #expect(OutlinedInitial.candidates(lines: reduced, paints: fixture.paints).isEmpty)
}

@Test func outlinedInitialChangesOnlyOneLexicallySupportedLetter() {
    let words: Set<String> = ["team", "artificial"]
    #expect(OutlinedInitial.prefix("A", to: "team of scientists", isWord: { words.contains($0) }) == "A ")
    #expect(OutlinedInitial.prefix("A", to: "rtificial logs", isWord: { words.contains($0) }) == "A")
    #expect(OutlinedInitial.prefix("B", to: "team of scientists", isWord: { words.contains($0) }) == nil)
    #expect(OutlinedInitial.prefix("A", to: "rtificial logs", isWord: { _ in nil }) == nil)
    #expect(OutlinedInitial.prefix("AB", to: "rtificial logs", isWord: { words.contains($0) }) == nil)
}

@Test func techportRuledCellsPreserveAllWordsAndMergedHeaders() throws {
    struct Capture: Decodable {
        struct Selection: Decodable { var rect: [Double]; var text: String }
        var tableSelections: [Selection]
    }
    let fixture = try SourceLayoutFixture.load("techport-magazine-4")
    let captured = try JSONDecoder().decode(Capture.self, from: Data(contentsOf: fixtureURL("techport-magazine-4-layout.json")))
    func read(_ rect: CGRect) -> String {
        captured.tableSelections.first { cell in
            zip(cell.rect, [rect.minX,rect.minY,rect.width,rect.height]).allSatisfy { abs($0 - $1) < 0.01 }
        }?.text ?? ""
    }
    let tables = RuledTableReader.tables(lines: fixture.content().lines, paints: fixture.paints, readCell: read)
    #expect(tables.count == 3)
    #expect(tables.map { $0.rows.count } == [5,2,3])
    #expect(tables[0].rows[1].map(\.text) == ["Carthage College","Lead Organization","Academia","Kenosha, Wisconsin"])
    #expect(tables[2].rows[0].count == 1)
    #expect(tables[2].rows[0][0].columns == 2)
    #expect(tables[2].rows[2][0].text == "Texas")
    #expect(tables[2].rows[2][0].columns == 2)
    // A selection that loses a native character cannot supply a reflowed table.
    #expect(RuledTableReader.tables(lines: fixture.content().lines, paints: fixture.paints,
                                   readCell: { String(read($0).dropFirst()) }).isEmpty)
    #expect(RuledTableReader.tables(lines: fixture.content().lines, paints: [], readCell: read).isEmpty)
}

@Test(arguments: [20,21,22,23]) func magazinePersistentMarginsPreserveColumnOrder(number: Int) throws {
    var page = try magazinePage("usda", number)
    page.lines.removeAll { $0.text.hasPrefix("Agricultural Research") || $0.text == "\(number)" }
    let text = magazineBlocks(page).map(\.text).joined(separator: " ")
    let phrases = number == 20 ? ["running a farm", "blood. Using these materials", "The scientists want to scale up"]
        : number == 21 ? ["Mowing front and backyard lawns", "Adding a small amount", "Though the Albany team"]
        : number == 22 ? ["Air quality", "Cattle", "copper footbaths"]
        : ["Imidacloprid", "Papaya", "manure compost"]
    let indices = try phrases.map { try #require(text.range(of: $0)?.lowerBound) }
    #expect(indices == indices.sorted())
}

@Test func techportSidebarNumericFieldsReflowBesideTheTRLGraphic() throws {
    let page = try magazinePage("techport", 2)
    let text = magazineBlocks(page).map(\.text).joined(separator: " ")
    #expect(page.sidebarValueRows?.count == 3)
    #expect(text.contains("Start: 4"))
    #expect(text.contains("Current: 6"))
    #expect(text.contains("Estimated End: 7"))
    #expect(magazineBlocks(page).contains { if case .image = $0.content { true } else { false } })
}

@Test func aPatternedRectangleBehindProseIsNotAFlatFrame() {
    let rect = CGRect(x: 20, y: 20, width: 300, height: 400)
    let lines = (0..<3).map { row in TextLine(text: "Several ordinary words appear on this native row.",
        rect: CGRect(x: 30, y: 350 - row * 15, width: 270, height: 12), fontSize: 12) }
    let paint = GraphicsReader.Paint(rect: rect, rectangular: true)
    let page = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 600, height: 800), lines: lines,
                           graphics: [rect], pictures: [])
    let result = TextBackdrop.compose(page, graphics: .init(regions: [rect], unsupported: false, paints: [paint]))
    #expect(result.graphics == [rect])
}

@Test(arguments: [5,8,9,19]) func magazinePhotoCaptionsAreCompleteReadingUnits(number: Int) throws {
    let page = try magazinePage("usda", number)
    let paragraphs = magazineBlocks(page).compactMap { block -> String? in
        if case .paragraph = block.content { return block.text }; return nil
    }
    let expected = number == 5 ? "The mosquito Aedes aegypti can spread several diseases as it travels from person to person. Only the females feed on blood."
        : number == 8 ? "A sand fly, Phlebotomus papatasi, can transmit parasites that cause leishmaniasis, a disease that can cause permanent skin damage and severe organ damage."
        : number == 9 ? "The adult stable fly, Stomoxys calcitrans, is one of many biting, blood-feeding insects."
        : "Technician Damon Baptista (left) and microbiologist Mark Ibekwe collect a water sample from a creek that drains into the middle Santa Ana River Watershed."
    #expect(paragraphs.contains { $0.contains(expected) })
}

@Test func aRasterStripBesideAnOrnamentIsNotAVectorDivider() {
    let strip = CGRect(x: 30, y: 200, width: 552, height: 4)
    let ornament = CGRect(x: 300, y: 195, width: 20, height: 20)
    let lines = (0..<3).map { row in TextLine(text: "Several ordinary words appear on this native row.",
        rect: CGRect(x: 30, y: 350 - row * 15, width: 270, height: 12), fontSize: 12) }
    let page = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines,
                           graphics: [strip,ornament], pictures: [strip,ornament])
    let result = TextBackdrop.compose(page, graphics: .init(regions: page.graphics, unsupported: false,
        images: page.pictures, paints: [.init(rect: strip,image:true),.init(rect:ornament,image:true)]))
    #expect(result.graphics.contains { $0.contains(strip) })
}

@Test func techportGallerySurvivesPaintAndCropClustering() throws {
    let page = try magazinePage("techport", 5)
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    let blocks = magazineBlocks(page)
    let text = blocks.map(\.text).joined(separator: " ")
    let phrases = ["Space Propellant Gauging", "Existing propellant gauging methods comparison", "The Basic Formula"]
    let positions = try phrases.map { try #require(text.range(of: $0)?.lowerBound) }
    #expect(positions == positions.sorted())
}

@Test func outlinedInitialKeepsNativeMetadataAndStyledWords() {
    let content = InlineText(elements: [.link(.external("https://example.com"), InlineText("team", style: .bold))])
    var line = TextLine(content: content, rect: CGRect(x: 40, y: 100, width: 180, height: 12), fontSize: 10,
                        wraps: true, turn: .upright)
    line.structure = TextStructure(group: 7, order: 1, headingLevel: 0, lineCount: 4)
    line.readingRect = CGRect(x: 35, y: 100, width: 185, height: 12)
    let result = OutlinedInitial.prepending("A ", to: line)
    #expect(result.text == "A team")
    #expect(result.content.elements.dropFirst() == line.content.elements[...])
    #expect(result.structure == line.structure)
    #expect(result.wraps == line.wraps && result.turn == line.turn && result.readingRect == line.readingRect)
}

@Test func ruledGridPreservesNativeStylesRejectsPlotsAndOwnsNoNeighboringGrid() {
    func box(_ rect: CGRect, filled: Bool = false) -> GraphicsReader.Paint {
        .init(rect: rect, filled: filled, rectangular: true,
              vertices: [CGPoint(x: rect.minX,y: rect.minY),CGPoint(x: rect.maxX,y: rect.minY),
                         CGPoint(x: rect.maxX,y: rect.maxY),CGPoint(x: rect.minX,y: rect.maxY)])
    }
    func rules(_ offset: CGFloat) -> [GraphicsReader.Paint] {
        [20.0,80,140].map { box(CGRect(x: $0 - 0.5,y: 20 + offset,width: 1,height: 100)) }
            + [20.0,70,120].map { box(CGRect(x: 20,y: $0 + offset - 0.5,width: 120,height: 1)) }
    }
    let lines = [("A",30.0,95.0),("B",90.0,95.0),("C",30.0,45.0),("D",90.0,45.0)].map { text,x,y in
        TextLine(content: InlineText(text,style: .bold),rect: CGRect(x:x,y:y,width:10,height:10),fontSize:10)
    }
    func read(_ rect: CGRect) -> String { lines.filter { rect.contains($0.rect) }.map(\.text).joined(separator:" ") }
    let plain = RuledTableReader.tables(lines:lines,paints:rules(0),readCell:read)
    #expect(plain.count == 1)
    #expect(plain.flatMap(\.rows).flatMap { $0 }.map(\.content) == lines.map(\.content))
    let background = box(CGRect(x:20,y:20,width:120,height:100),filled:true)
    #expect(RuledTableReader.tables(lines:lines,paints:rules(0)+[background],readCell:read).first?.headerRows == 0)
    let diagonal = GraphicsReader.Paint(rect:CGRect(x:25,y:25,width:110,height:90),
        vertices:[CGPoint(x:25,y:25),CGPoint(x:135,y:115)])
    #expect(RuledTableReader.tables(lines:lines,paints:rules(0)+[diagonal],readCell:read).isEmpty)
    let upper = lines.map { TextLine(content:$0.content,rect:$0.rect.offsetBy(dx:0,dy:150),fontSize:$0.fontSize) }
    let both = lines + upper
    let shared = box(CGRect(x:20,y:20,width:120,height:250),filled:true)
    let separate = RuledTableReader.tables(lines:both,paints:rules(0)+rules(150)+[shared]) { rect in
        both.filter { rect.contains($0.rect) }.map(\.text).joined(separator:" ")
    }
    #expect(separate.count == 2)
    #expect(!separate[0].rect.intersects(separate[1].rect))
    #expect(separate.flatMap(\.rows).flatMap { $0 }.map(\.text).count == 8)
}

@Test func noaaContentsLeadersRemainSeparateFromThePainting() throws {
    let page = try magazinePage("noaa", 8)
    let text = magazineBlocks(page).map(\.text).joined(separator: " ")
    let phrases = ["About This Report", "Guide to the Report", "Key Advances Since the Fourth National Climate Assessment",
                   "Chapter 1. Overview", "Chapter 2. Climate Trends", "Chapter 3. Earth Systems Processes"]
    let indices = try phrases.map { try #require(text.range(of: $0)?.lowerBound) }
    #expect(indices == indices.sorted())
    #expect(magazineBlocks(page).contains { if case .image = $0.content { true } else { false } })
}

@Test func noaaPatternedPanelKeepsBothNativeProseAndArtwork() throws {
    let fixture = try SourceLayoutFixture.load("noaa-magazine-48")
    let page = try magazinePage("noaa", 48)
    let panel = try #require(fixture.paints.first { paint in
        paint.rectangular && !paint.image && !paint.filled && paint.strokeOnly != true
            && page.lines.filter { paint.rect.contains($0.rect) }.count >= 6
    })
    #expect(page.graphics.contains { $0.contains(panel.rect) })
    let text = magazineBlocks(page).map(\.text).joined(separator: " ")
    #expect(text.contains("Global greenhouse gas emissions from human activities continue to increase, resulting in rapid warming (Figure 1.5)"))
    #expect(text.contains("unprecedented for thousands of years (Figure 1.6)"))
    #expect(magazineBlocks(page).contains { if case .image = $0.content { true } else { false } })
}

@Test func displayQuotationRequiresNativeUprightTypography() throws {
    var page = try magazinePage("usda", 12)
    let type = PageTypography(page: page)
    #expect(DisplayQuotation.groups(in: page.lines, body: type.body, threshold: type.headingThreshold).count == 1)
    let sideways = page.lines.map { original in var line = original; line.turn = .clockwise; return line }
    #expect(DisplayQuotation.groups(in: sideways, body: type.body, threshold: type.headingThreshold).isEmpty)
    page.hasSyntheticTextStyle = true
    #expect(!magazineBlocks(page).contains { if case .quotation = $0.content { true } else { false } })
}
