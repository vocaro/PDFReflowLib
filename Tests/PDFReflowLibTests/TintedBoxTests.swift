import CoreGraphics
import Foundation
import Testing
import ZIPFoundation
@testable import PDFReflowLib

// Shaded sidebar boxes and text tables (#54). A rectangle painted behind prose (a stroked
// frame, a tint band, cell shading) used to seed a crop that swallowed every line inside it.
// Now the page's text decides: rectangles holding prose are tints, the rules between shaded
// rows are separators, a chart inside a box keeps its own band image, and a grid of shaded
// rows reads as a table. Figure backgrounds, bar charts, flowchart nodes, ratings grids and
// ruled tables without shading keep their images.

private let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)

private func line(_ text: String, x: CGFloat, baseline: CGFloat, width: CGFloat, size: CGFloat = 9) -> TextLine {
    TextLine(text: text, rect: CGRect(x: x, y: baseline - 2.5, width: width, height: size * 1.25), fontSize: size)
}

private func paint(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, frame: Bool) -> GraphicsReader.Paint {
    GraphicsReader.Paint(rect: CGRect(x: x, y: y, width: width, height: height), frame: frame)
}

/// The page as the pipeline builds it: tint removal, then whole-line crop expansion and layout.
private func page(_ paints: [GraphicsReader.Paint], lines: [TextLine]) -> PageContent {
    var page = PageContent(number: 1, bounds: pageBounds, lines: lines, graphics: [])
    let composed = TintDetector.compose(paints, lines: lines, bounds: pageBounds)
    page.graphics = composed.graphics
    page.tints = composed.tints
    page.separators = composed.separators
    return page
}

private func reflowed(_ page: PageContent) -> (regions: [CGRect], blocks: [ReflowBlock]) {
    let regions = LayoutReconstructor.graphicsWithLabels(page)
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: regions.enumerated().map { ($0.element, "image-\($0.offset)") },
        vocabulary: LayoutReconstructor.vocabulary(in: [page]), warnings: &warnings)
    return (regions, blocks)
}

private func table(in blocks: [ReflowBlock]) -> ReflowBlock.Table? {
    blocks.compactMap { if case let .table(table) = $0.content { table } else { nil } }.first
}

private let frame = CGRect(x: 88.5, y: 202.5, width: 435, height: 501)

/// Sidebar prose on 11-pt leading, as PDFKit extracts the Fed's boxes.
private func boxProse(baseline: CGFloat, count: Int) -> [TextLine] {
    (0..<count).map {
        line("In preparation for each Federal Open Market Committee meeting policymakers analyze developments \($0)",
             x: 103, baseline: baseline - CGFloat($0) * 11, width: 400)
    }
}

private let bodyProse = (0..<3).map {
    line("During the FOMC meeting policymakers discuss a broad range of information to assess trends \($0)",
         x: 90, baseline: 148 - CGFloat($0) * 16, width: 420, size: 10)
}

@Test func graphicsReaderRecordsRectanglesOutsideFigureMarksAsFrames() throws {
    let data = testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R >>",
        testPDFStream("""
        /Artifact BMC 0.9 g 90 200 431 500 re f EMC
        0 G 1 w 90 200 431 500 re S
        0 G 100 100 m 300 150 l S
        /Figure << /MCID 0 >> BDC 0.5 g 120 120 50 50 re f EMC
        """),
    ])
    let document = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!))
    let result = GraphicsReader.read(try #require(document.page(at: 1)))
    #expect(!result.unsupported)
    #expect(result.paints.map(\.frame) == [true, true, false, false])
    #expect(result.paints[0].rect == CGRect(x: 88, y: 198, width: 435, height: 504))
    // The clustered regions are unchanged by the classification.
    #expect(result.regions.count == 2)
}

/// #99: FAA pages 474–475 place a two-page illustration across both pages, so hundreds of its
/// marks lie wholly off each page. Their crop-box intersection was the infinite null rectangle,
/// which `tools/capture-layout-fixture.swift` could not write as JSON.
@Test func graphicsReaderDropsPaintsWhollyOffThePage() throws {
    let data = testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 594 774] /Contents 4 0 R >>",
        testPDFStream("""
        0.5 g 750 400 60 40 re f
        0.5 g -380 460 100 90 re f
        0.5 g 570 300 60 40 re f
        0.5 g 100 100 50 50 re f
        """),
    ])
    let document = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!))
    let result = GraphicsReader.read(try #require(document.page(at: 1)))
    #expect(result.paints.allSatisfy { !$0.rect.isNull && $0.rect.isFinite })
    // Controls: a fill overhanging the edge keeps its visible part; one on the page is whole.
    #expect(result.paints.map(\.rect) == [CGRect(x: 568, y: 298, width: 26, height: 44),
                                          CGRect(x: 98, y: 98, width: 54, height: 54)])
    #expect(result.regions.count == 2)
}

@Test func sidebarFrameHoldingProseIsATintAndItsTextReflows() throws {
    let lines = boxProse(baseline: 655, count: 6) + bodyProse
    let tinted = page([paint(88.5, 202.5, 435, 501, frame: true)], lines: lines)
    #expect(tinted.graphics.isEmpty && tinted.tints == [frame])
    let (regions, blocks) = reflowed(tinted)
    #expect(regions.isEmpty)
    #expect(blocks.allSatisfy { $0.hasReflowedText })
    let text = blocks.map(\.text).joined(separator: "\n")
    #expect(text.contains("policymakers analyze developments 0") && text.contains("policymakers analyze developments 5"))
    #expect(text.contains("assess trends 2"))
    // Without tint removal the same frame swallowed every box line (the defect of #54).
    let untinted = PageContent(number: 1, bounds: pageBounds, lines: lines, graphics: [frame])
    let crop = try #require(LayoutReconstructor.graphicsWithLabels(untinted).first)
    #expect(lines.prefix(6).allSatisfy { crop.contains($0.rect) })
}

@Test func chartInsideBoxKeepsOneBandImageBelowTheProse() throws {
    let prose = boxProse(baseline: 655, count: 4)
    let captions = [line("A. Overnight money market rates", x: 103, baseline: 430, width: 85, size: 8),
                    line("Note: The upper bound of the target range", x: 103, baseline: 280, width: 160, size: 7)]
    let chart = [paint(120, 300, 160, 120, frame: false), paint(320, 300, 160, 120, frame: false),
                 paint(118, 298, 4, 124, frame: false)]
    let composed = page([paint(88.5, 202.5, 435, 501, frame: true)] + chart, lines: prose + captions + bodyProse)
    #expect(composed.tints == [frame])
    #expect(composed.graphics.count == 1)
    let band = try #require(composed.graphics.first)
    #expect(band.minX == frame.minX && band.width == frame.width)
    for caption in captions { #expect(band.contains(caption.rect), "caption outside the band: \(caption.text)") }
    for line in prose + bodyProse { #expect(!band.contains(CGPoint(x: line.rect.midX, y: line.rect.midY)), "prose inside the band: \(line.text)") }
    let (regions, blocks) = reflowed(composed)
    #expect(regions.count == 1)
    #expect(blocks.filter { !$0.hasReflowedText }.count == 1)
    let text = blocks.filter(\.hasReflowedText).map(\.text).joined(separator: "\n")
    #expect(text.contains("analyze developments 3") && !text.contains("Overnight money market"))
}

@Test func figureBackgroundsBarChartsFlowchartsAndGridsKeepTheirImages() {
    // A bar chart: rectangles holding no text beside an axis.
    let bars = [paint(100, 300, 30, 80, frame: true), paint(140, 300, 30, 120, frame: true),
                paint(180, 300, 30, 60, frame: true), paint(95, 295, 300, 4, frame: false)]
    // A flowchart: node boxes with short labels joined by thin arrows.
    let nodes = [paint(100, 500, 120, 40, frame: true), paint(300, 500, 120, 40, frame: true),
                 paint(200, 400, 120, 40, frame: true), paint(220, 442, 4, 56, frame: false)]
    let labels = [line("Board of Governors", x: 105, baseline: 515, width: 100),
                  line("Reserve Banks", x: 305, baseline: 515, width: 80),
                  line("Federal Open Market Committee", x: 205, baseline: 415, width: 105)]
    // A frame with too little prose, and a ratings grid whose cells are short fragments.
    let sparse = boxProse(baseline: 655, count: 2)
    let fragments = (0..<12).map { line("Capital adequacy and positions \($0)", x: 103 + CGFloat($0 % 3) * 140,
                                        baseline: 500 - CGFloat($0 / 3) * 30, width: 120) }
    for (paints, lines) in [(bars, bodyProse), (nodes, labels + bodyProse),
                            ([paint(88.5, 202.5, 435, 501, frame: true)], sparse + bodyProse),
                            ([paint(88.5, 202.5, 435, 501, frame: true)], boxProse(baseline: 655, count: 3) + fragments + bodyProse)] {
        let composed = TintDetector.compose(paints, lines: lines, bounds: pageBounds)
        #expect(composed.tints.isEmpty && composed.separators.isEmpty)
        #expect(composed.graphics == clusters(paints.map(\.rect), distance: 4))
    }
}

/// A Fed-style entity/overview table: a stroked box, a header band, three row bands, the
/// rules between them and a title above the bands inside the box.
private func bandTable() -> (paints: [GraphicsReader.Paint], lines: [TextLine], title: TextLine) {
    let strokes = [paint(88, 699.5, 437, 4, frame: false), paint(88, 146.1, 437, 4, frame: false),
                   paint(88.5, 146.6, 4, 556.9, frame: false), paint(520.5, 146.6, 4, 556.9, frame: false)]
    let bands = [paint(96, 595.4, 421.3, 33.9, frame: true)] + [535.4, 475.4, 415.4].map { paint(96, $0, 421.3, 60, frame: true) }
    var rules: [GraphicsReader.Paint] = []
    for y in [595.4, 535.4, 475.4, 415.4] as [CGFloat] {
        rules += [paint(95.7, y - 2, 149, 4, frame: false), paint(240.7, y - 2, 276.8, 4, frame: false)]
    }
    rules += [96, 240.7, 513.2].map { paint($0, 415.4, 4, 180, frame: false) }
    let title = line("Figure 4.6. Monitoring financial system stability requires global cooperation", x: 95, baseline: 690, width: 380, size: 12)
    var lines = [title, line("International authority", x: 100, baseline: 610, width: 110, size: 8),
                 line("Overview", x: 245, baseline: 610, width: 60, size: 8)]
    for (index, name) in ["Financial Stability Board", "Central banks", "Bank for International Settlements"].enumerated() {
        let top = 585 - CGFloat(index) * 60
        lines += [line(name, x: 100, baseline: top, width: 120, size: 8),
                  line("Established \(2009 - index)", x: 100, baseline: top - 10, width: 70, size: 8),
                  line("The \(name) promotes stability through coordination of", x: 245, baseline: top, width: 270, size: 8),
                  line("national financial authorities and international standard setting bodies", x: 245, baseline: top - 10, width: 268, size: 8)]
    }
    return (strokes + bands + rules, lines, title)
}

@Test func shadedRowsWithRulesReadAsATableWithTheTitleOutsideIt() throws {
    let fixture = bandTable()
    let composed = page(fixture.paints, lines: fixture.lines + bodyProse)
    #expect(composed.graphics.isEmpty)
    #expect(composed.tints.count == 5)
    #expect(composed.separators.count == 11)
    let (regions, blocks) = reflowed(composed)
    #expect(regions.isEmpty)
    let table = try #require(table(in: blocks))
    #expect(table.columns == 2)
    #expect(table.rows.count == 4)
    #expect(table.rows[0].header && table.rows[0].cells.map(\.text.text) == ["International authority", "Overview"])
    #expect(table.rows[1].cells.map(\.text.text) == ["Financial Stability Board Established 2009",
        "The Financial Stability Board promotes stability through coordination of national financial authorities and international standard setting bodies"])
    #expect(table.rows[3].cells[0].text.text.hasPrefix("Bank for International Settlements"))
    #expect(table.rows.dropFirst().allSatisfy { !$0.header && $0.cells.allSatisfy { $0.span == 1 } })
    let paragraphs = blocks.filter { if case .table = $0.content { false } else { true } }
    #expect(paragraphs.contains { $0.text == fixture.title.text })
    #expect(paragraphs.contains { $0.text.contains("assess trends 0") })
}

@Test func sectionRowsAndMergedLetterCellsReadAsSpanningAndJoinedCells() throws {
    let header = [line("Regulation (by letter and name)", x: 95, baseline: 690, width: 170, size: 8),
                  line("Description", x: 248, baseline: 690, width: 60, size: 8)]
    let section = line("Banks and banking", x: 95, baseline: 652, width: 90, size: 8)
    var rows: [TextLine] = []
    for (index, row) in [("F Limitations on Interbank Liabilities", "", "Prescribes standards to limit the risks that the failure"),
                         ("H", "Membership of State Banking Institutions", "Defines the requirements for membership of state chartered"),
                         ("K", "International Banking Operations", "Governs the international banking operations of banking")].enumerated() {
        let top = 636 - CGFloat(index) * 28
        rows.append(line(row.0, x: row.1.isEmpty ? 95 : 98, baseline: top, width: row.1.isEmpty ? 150 : 8, size: 8))
        if !row.1.isEmpty { rows.append(line(row.1, x: 122, baseline: top, width: 120, size: 8)) }
        rows += [line(row.2, x: 248, baseline: top, width: 270, size: 8),
                 line("of one depository institution would pose to another institution", x: 248, baseline: top - 10, width: 260, size: 8)]
    }
    var paints = [paint(89.5, 136.3, 436, 567.2, frame: true), paint(89.5, 684.6, 435, 18.9, frame: true),
                  paint(89.5, 647.7, 435, 17.5, frame: true), paint(116.5, 560, 130, 84, frame: true),
                  paint(242.5, 560, 282, 84, frame: true)]
    for y in [614, 586] as [CGFloat] {
        paints += [paint(89.2, y, 31.2, 4, frame: false), paint(116.5, y, 130, 4, frame: false), paint(242.5, y, 282, 4, frame: false)]
    }
    let composed = page(paints, lines: header + [section] + rows + bodyProse)
    #expect(composed.graphics.isEmpty && composed.separators.count == 6)
    let (_, blocks) = reflowed(composed)
    let table = try #require(table(in: blocks))
    #expect(table.columns == 2)
    #expect(table.rows.map(\.header) == [true, false, false, false, false])
    #expect(table.rows[0].cells.map(\.text.text) == ["Regulation (by letter and name)", "Description"])
    #expect(table.rows[1].cells.map(\.span) == [2] && table.rows[1].cells[0].text.text == "Banks and banking")
    #expect(table.rows[2].cells[0].text.text == "F Limitations on Interbank Liabilities")
    #expect(table.rows[3].cells[0].text.text == "H Membership of State Banking Institutions")
    #expect(table.rows[4].cells[1].text.text.hasPrefix("Governs the international banking operations"))
}

@Test func ruledTableWithoutShadedRowsStaysOneImage() throws {
    var fixture = bandTable()
    // Only the header band is shaded; the rows are ruled. The three title-band lines qualify
    // the box as a tint, but the unshaded grid inside it is a table this reader cannot parse.
    fixture.paints.removeAll { $0.frame && $0.rect.minY < 590 }
    let heading = [line("Table 3.1 Traditional tools in an ample reserves regime with three columns", x: 95, baseline: 690, width: 380, size: 12),
                   line("In recent years the Federal Reserve has successfully implemented monetary policy", x: 95, baseline: 675, width: 380, size: 9),
                   line("with a varying degree of ample reserves in the banking system as shown", x: 95, baseline: 664, width: 370, size: 9)]
    let cells = fixture.lines.dropFirst().map { line in
        TextLine(text: String(line.text.split(separator: " ").prefix(3).joined(separator: " ")), rect: CGRect(origin: line.rect.origin, size: CGSize(width: 90, height: line.rect.height)), fontSize: 8)
    }
    let composed = page(fixture.paints, lines: heading + cells + bodyProse)
    #expect(composed.separators.isEmpty)
    #expect(composed.graphics.count == 1)
    let crop = try #require(composed.graphics.first)
    for cell in cells { #expect(crop.contains(cell.rect), "cell outside the crop: \(cell.text)") }
    #expect(table(in: reflowed(composed).blocks) == nil)
}

@Test func boxBesideWrappedProseReadsAfterTheLinesBesideIt() throws {
    let above = (0..<2).map { line("Reserve Banks provide the Federal Reserve System with a wealth of information \($0)", x: 90, baseline: 700 - CGFloat($0) * 16, width: 420, size: 10) }
    let beside = (0..<5).map { line("In addition through their leaders and their connections to members \($0)", x: 90, baseline: 668 - CGFloat($0) * 16, width: 200, size: 10) }
    let below = (0..<2).map { line("vital to formulating a national monetary policy that will help the economy \($0)", x: 90, baseline: 588 - CGFloat($0) * 16, width: 420, size: 10) }
    let sidebar = (0..<5).map { line("Want to learn more about Reserve Bank directors and their many roles \($0)", x: 320, baseline: 668 - CGFloat($0) * 12, width: 195, size: 8) }
    let composed = page([paint(313, 600, 210, 90, frame: true)], lines: above + beside + below + sidebar)
    #expect(composed.tints.count == 1)
    let (_, blocks) = reflowed(composed)
    let texts = blocks.map(\.text)
    let box = try #require(texts.firstIndex { $0.hasPrefix("Want to learn more") })
    #expect(texts[..<box].joined(separator: " ").contains("connections to members 4"))
    #expect(texts[(box + 1)...].joined(separator: " ").hasPrefix("vital to formulating"))
    #expect(texts[box].hasSuffix("many roles 4"))
    // The box's paragraph never joins the body text on either side of it.
    #expect(!texts.contains { $0.contains("members 4") && $0.contains("Want to learn") })
    #expect(!texts.contains { $0.contains("many roles 4") && $0.contains("vital to") })
}

@Test func tableBlocksSerializeAsXHTMLTables() async throws {
    let directory = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    var styled = InlineText("Financial ")
    styled.append(InlineText("Stability", style: .bold))
    let table = ReflowBlock.Table(columns: 2, rows: [
        .init(cells: [.init(text: InlineText("Entity")), .init(text: InlineText("Overview"))], header: true),
        .init(cells: [.init(text: InlineText("Group <A>"), span: 2)], header: false),
        .init(cells: [.init(text: styled), .init(text: InlineText("Promotes stability & cooperation"))], header: false),
    ])
    let book = ReflowDocument(metadata: .init(title: "Tables", language: "en"), blocks: [
        ReflowBlock(content: .sourcePage(1), page: 1),
        ReflowBlock(content: .paragraph(InlineText("Before")), page: 1),
        ReflowBlock(content: .table(table), page: 1),
    ], assets: [])
    #expect(book.blocks[2].hasReflowedText && book.blocks[2].text == "Entity Overview Group <A> Financial Stability Promotes stability & cooperation")
    let url = try await EPUBWriter.write(book, maximumOutputBytes: 1 << 20, directory: directory) { _ in }
    let archive = try Archive(url: url, accessMode: .read)
    let entry = try #require(archive["EPUB/chapter-1.xhtml"])
    var bytes = Data(); _ = try archive.extract(entry) { bytes += $0 }
    let xhtml = String(decoding: bytes, as: UTF8.self)
    #expect(xhtml.contains("<p>Before</p>\n<table><thead><tr><th>Entity</th><th>Overview</th></tr></thead>"
        + "<tbody><tr><td colspan=\"2\">Group &lt;A&gt;</td></tr><tr><td>Financial <strong>Stability</strong></td>"
        + "<td>Promotes stability &amp; cooperation</td></tr></tbody></table>\n"))
    let css = try #require(archive["EPUB/style.css"])
    var style = Data(); _ = try archive.extract(css) { style += $0 }
    #expect(String(decoding: style, as: UTF8.self).contains("th, td { border"))
}

// Source-derived cases: The Fed Explained pages 32, 40, 58, 64, 83 and 120, captured with
// their painted footprints. Each fixture's `content(tinted: false)` reproduces the defect.

@Test(arguments: [(32, "Box 3.1. What Happens at an FOMC Meeting", "Reserve Bank input gathered."),
                  (58, "Box 4.2. Responding to Financial System Emergencies", "The idea that a central bank should provide liquidity")])
func fedSidebarBoxesReflowAsHeadingAndParagraphs(_ number: Int, _ title: String, _ phrase: String) throws {
    let fixture = try SourceLayoutFixture.load("fed-\(number)")
    let before = LayoutReconstructor.graphicsWithLabels(fixture.content(tinted: false))
    #expect(before.contains { region in fixture.lines.filter { region.contains(CGRect(x: $0.rect[0], y: $0.rect[1], width: $0.rect[2], height: $0.rect[3])) }.count >= 30 })
    let page = fixture.content()
    let (regions, blocks) = reflowed(page)
    // Only the running-header rule remains a crop; no region touches a box line.
    #expect(regions.allSatisfy { $0.height <= 6 })
    #expect(!regions.contains { region in page.lines.contains { region.intersects($0.rect) } })
    #expect(blocks.contains { if case .heading = $0.content { $0.text == title } else { false } })
    #expect(blocks.contains { if case .paragraph = $0.content { $0.text.contains(phrase) } else { false } })
    let text = blocks.map(\.text).joined(separator: "\n")
    for source in page.lines where source.rect.midY < 730 {
        #expect(text.contains(source.text.trimmingCharacters(in: .whitespaces).prefix(30)), "missing: \(source.text)")
    }
}

@Test func fedChartBoxKeepsChartsNotesAndCaptionsAsOneBandBelowItsProse() throws {
    let page = try SourceLayoutFixture.load("fed-40").content()
    let (regions, blocks) = reflowed(page)
    let bands = regions.filter { $0.height > 6 }
    #expect(bands.count == 1)
    let band = try #require(bands.first)
    #expect(band.height < 260 && band.width > 400)
    for phrase in ["A. Overnight money market rates", "Note: The upper bound of the target range"] {
        #expect(page.lines.contains { $0.text.hasPrefix(phrase) && band.contains($0.rect) }, "\(phrase) outside the band")
    }
    for phrase in ["The Federal Reserve uses interest on reserve balances", "other financial asset prices and overall financial conditions",
                   "Open market operations. Over the years"] {
        #expect(page.lines.contains { $0.text.hasPrefix(phrase) && !band.intersects($0.rect) }, "\(phrase) inside the band")
        #expect(blocks.contains { $0.hasReflowedText && $0.text.contains(phrase) }, "\(phrase) not reflowed")
    }
    #expect(blocks.contains { if case .heading = $0.content { $0.text.hasPrefix("Box 3.3. Interest on Reserve Balances") } else { false } })
}

@Test func fedEntityTableReadsAsTwoColumnsWithItsHeader() throws {
    let page = try SourceLayoutFixture.load("fed-64").content()
    let (regions, blocks) = reflowed(page)
    #expect(regions.allSatisfy { $0.height <= 6 })
    let table = try #require(table(in: blocks))
    #expect(table.columns == 2 && table.rows.count == 8)
    // The header cell breaks after `authority/`; the slash joins its line without a space (#70).
    #expect(table.rows[0].header && table.rows[0].cells.map(\.text.text) == ["International authority/deliberative body", "Overview/Federal Reserve engagement"])
    #expect(table.rows[1].cells[0].text.text == "Financial Stability Board Established: 2009 Location: Basel, Switzerland Website: https://www.fsb.org")
    #expect(table.rows[1].cells[1].text.text.hasPrefix("The Financial Stability Board (FSB), successor to the Financial Stability Forum"))
    #expect(table.rows.map { $0.cells[0].text.text.prefix(12) } == ["Internationa", "Financial St", "Central bank", "Bank for Int", "G7 & G20 Est", "Internationa", "Organisation", "World Bank E"])
    // The title band's title and the description beneath it are the table's caption (#113).
    #expect(table.caption.count == 2)
    #expect(table.caption.first?.text == "Figure 4.6. Monitoring financial system stability requires global cooperation")
    #expect(table.caption.last?.text.hasPrefix("What happens in the global economy") == true)
    #expect(!blocks.contains { if case .table = $0.content { false } else { $0.text.contains("Figure 4.6.") || $0.text.contains("What happens in the global economy") } })
}

@Test func fedRegulationTableReadsSectionsAndMergedLetterCells() throws {
    let page = try SourceLayoutFixture.load("fed-83").content()
    let table = try #require(table(in: reflowed(page).blocks))
    #expect(table.columns == 2)
    #expect(table.rows[0].header && table.rows[0].cells.map(\.text.text) == ["Regulation (by letter and name)", "Description"])
    let sections = table.rows.filter { $0.cells.count == 1 }.map(\.cells[0].text.text)
    #expect(sections == ["Holding companies and nonbank financial companies", "Federal Reserve Credit",
                         "Monetary policy and reserve requirements", "Securities credit transactions"])
    #expect(table.rows.contains { $0.cells.count == 2 && $0.cells[0].text.text == "Y Bank Holding Companies and Change in Bank Control" })
    #expect(table.rows.contains { $0.cells.count == 2 && $0.cells[0].text.text == "LL Savings and Loan Holding Companies" })
    #expect(table.rows.contains { $0.cells.count == 2 && $0.cells[0].text.text == "X Borrowers of Securities Credit" })
    #expect(table.rows.count == 20)
}

@Test func fedContinuationTableStartsWithASectionRowAndNoHeader() throws {
    let page = try SourceLayoutFixture.load("fed-120").content()
    let table = try #require(table(in: reflowed(page).blocks))
    #expect(table.columns == 2 && !table.rows.contains(where: \.header))
    #expect(table.rows[0].cells.map(\.text.text) == ["General banking"] && table.rows[0].cells.map(\.span) == [2])
    #expect(table.rows[1].cells.map(\.text.text) == ["Federal Trade Commission Act",
        "Prohibits unfair or deceptive acts or practices in any aspect of banking transactions."])
    #expect(table.rows.filter { $0.cells.count == 1 }.map(\.cells[0].text.text) == ["General banking", "Depository accounts", "Credit/general lending"])
    #expect(table.rows.count == 12)
}
