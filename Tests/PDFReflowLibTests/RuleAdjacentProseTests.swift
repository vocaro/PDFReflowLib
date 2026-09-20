import CoreGraphics
import Foundation
import ImageIO
import Testing
import ZIPFoundation
@testable import PDFReflowLib

// Thin rules beside tightly leaded prose (#36, ported from the coordination branch for #229),
// and the web addresses a book's notes cite (#227). PDFKit line rectangles are about 1.36× the
// font size on 1.1× leading, so consecutive rectangles overlap; a section-label underline or
// a column rule must not rasterize the paragraph or column it touches, while borderless
// tables whose column headers are underlined must remain one preserved image.

private let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)

/// USGS-like geometry: 10-pt text, 11-pt leading, PDFKit rectangles 13.6 pt tall.
private func proseLine(_ text: String, x: CGFloat = 45, baseline: CGFloat, width: CGFloat) -> TextLine {
    TextLine(text: text, rect: CGRect(x: x, y: baseline - 3.3, width: width, height: 13.6), fontSize: 10)
}

/// A painted 1-pt underline after GraphicsReader's two-point padding.
private func underline(x: CGFloat, baseline: CGFloat, width: CGFloat) -> CGRect {
    CGRect(x: x - 2, y: baseline - 3.5, width: width + 4, height: 5)
}

private func paragraph(_ texts: [String], baseline: CGFloat, widths: [CGFloat]) -> [TextLine] {
    zip(texts, widths).enumerated().map { index, item in
        proseLine(item.0, baseline: baseline - CGFloat(index) * 11, width: item.1)
    }
}

private func reflowed(_ page: PageContent, regions: [CGRect]) -> [ReflowBlock] {
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: regions.enumerated().map { ($0.element, "image-\($0.offset)") },
        vocabulary: LayoutReconstructor.vocabulary(in: [page]), warnings: &warnings)
}

private let recycling = paragraph([
    "Recycling: Old scrap, converted to refined metal and other forms, provided about 150,000 tons",
    "of copper in 2024, and an estimated 720,000 tons of copper was recovered from new scrap",
    "derived from fabricating operations, about 35% of the total copper supply for the year.",
], baseline: 700, widths: [500, 505, 490])

private let importSources = paragraph([
    "Import Sources (2020–23): Copper content of blister and anodes: Finland, 92%; Malaysia, 3%",
    "Copper content of matte, ash, and precipitates: Canada, 48%; Belgium, 23%; Japan, 13%.",
    "Refined copper accounted for 88% of all unmanufactured copper imports in that period.",
], baseline: 656, widths: [491, 498, 439])

/// A borderless statistics table: an underlined label and three underlined year headers on
/// one row, indentation-only group rows and numeric value rows on 11-pt leading.
private func statisticsTable(baseline: CGFloat) -> (lines: [TextLine], rules: [CGRect]) {
    let header = [proseLine("Salient Statistics:", baseline: baseline, width: 90),
                  proseLine("2020 2021 2022", x: 300, baseline: baseline, width: 122)]
    let rows = [
        [proseLine("Production:", baseline: baseline - 11, width: 50)],
        [proseLine("Mine, recoverable", x: 55, baseline: baseline - 22, width: 80),
         proseLine("1,200 1,230 1,230", x: 300, baseline: baseline - 22, width: 122)],
        [proseLine("Refinery", x: 55, baseline: baseline - 33, width: 40),
         proseLine("872 922 930", x: 305, baseline: baseline - 33, width: 110)],
        [proseLine("Imports", x: 55, baseline: baseline - 44, width: 38),
         proseLine("2 11 12", x: 310, baseline: baseline - 44, width: 100)],
    ]
    let rules = [underline(x: 45, baseline: baseline, width: 90)] + [300, 342, 384].map {
        underline(x: $0, baseline: baseline, width: 26)
    }
    return (header + rows.flatMap { $0 }, rules)
}

@Test func labelUnderlinesLeaveTightlyLeadedProseSelectable() throws {
    let page = PageContent(number: 1, bounds: pageBounds, lines: recycling + importSources, graphics: [
        underline(x: 45, baseline: 700, width: 52), underline(x: 45, baseline: 656, width: 125),
    ])
    #expect(LayoutReconstructor.graphicsWithLabels(page).isEmpty)
    let blocks = reflowed(page, regions: LayoutReconstructor.graphicsWithLabels(page))
    #expect(!blocks.isEmpty && blocks.allSatisfy { $0.hasReflowedText })
    // Every source line reflows in order; whether the tall rectangles leave the two paragraphs
    // separate is the existing paragraph heuristic's decision, not this regression's.
    let text = blocks.map(\.text).joined(separator: "\n")
    #expect(text.hasPrefix("Recycling: Old scrap"))
    for phrase in ["150,000 tons of copper in 2024, and an estimated", "supply for the year.",
                   "Import Sources (2020–23): Copper content of blister", "Japan, 13%. Refined copper accounted"] {
        #expect(text.contains(phrase), "missing prose: \(phrase)")
    }
}

@Test func columnRulesTouchingProseDoNotAbsorbTheColumn() throws {
    // A rule painted in the leading above the first line overlaps its rectangle without
    // striking its glyphs: nothing is rasterized. The same rule clear of every rectangle stays
    // an isolated graphic, as before, and still leaves the prose selectable.
    let touching = CGRect(x: 38, y: 700 + 7, width: 500, height: 4)
    let clear = CGRect(x: 38, y: 700 + 12, width: 500, height: 4)
    for (rule, count) in [(touching, 0), (clear, 1)] {
        let page = PageContent(number: 1, bounds: pageBounds, lines: recycling, graphics: [rule])
        let regions = LayoutReconstructor.graphicsWithLabels(page)
        #expect(regions.count == count)
        #expect(!regions.contains { region in page.lines.contains { region.intersects($0.rect) } })
        let blocks = reflowed(page, regions: regions)
        let prose = blocks.filter(\.hasReflowedText)
        #expect(prose.count == 1 && prose[0].text.hasSuffix("supply for the year."))
    }
}

@Test func underlinedColumnHeadersKeepBorderlessTableAsOneImageBetweenProse() throws {
    let table = statisticsTable(baseline: 634)
    let closing = paragraph([
        "Tariff: Item Number Normal Trade Relations apply to the items listed in the table.",
        "Copper ore and concentrates are free of duty under the trade relations in force.",
        "Refined copper and alloys carry a 1% ad valorem duty under the same relations.",
    ], baseline: 568, widths: [420, 410, 400])
    let page = PageContent(number: 1, bounds: pageBounds, lines: recycling + table.lines + closing,
        graphics: [underline(x: 45, baseline: 700, width: 52)] + table.rules + [underline(x: 45, baseline: 568, width: 29)])
    let regions = LayoutReconstructor.graphicsWithLabels(page)
    #expect(regions.count == 1)
    let region = try #require(regions.first)
    for line in table.lines { #expect(region.contains(line.rect), "table piece outside the crop: \(line.text)") }
    for line in recycling + closing { #expect(!region.intersects(line.rect), "prose inside the crop: \(line.text)") }
    let blocks = reflowed(page, regions: regions)
    #expect(blocks.count == 3)
    #expect(blocks[0].text.hasPrefix("Recycling:"))
    #expect(!blocks[1].hasReflowedText)
    #expect(blocks[2].text.hasPrefix("Tariff: Item Number") && blocks[2].text.hasSuffix("same relations."))
    #expect(!blocks.contains { $0.text.contains("1,230") || $0.text.contains("Mine, recoverable") })
}

@Test func headerUnderlinesNeedNumericRowsAndSingleUnderlinesNeedColumnPlacement() throws {
    func regions(_ lines: [TextLine], _ rules: [CGRect]) -> [CGRect] {
        LayoutReconstructor.graphicsWithLabels(PageContent(number: 1, bounds: pageBounds, lines: lines, graphics: rules))
    }
    // A short heading underlined whole at the left margin, then tightly leaded numeric prose.
    let heading = [proseLine("Introduction", baseline: 700, width: 60)] + paragraph([
        "In 2024 the recoverable content of mine production was 1.1 million tons, down 3%.",
        "Arizona accounted for 70% of domestic output; 25 mines produced 99% of the total.",
        "Refined production increased 2% while apparent consumption rose to 1.8 million tons.",
    ], baseline: 689, widths: [470, 468, 480])
    #expect(regions(heading, [underline(x: 45, baseline: 700, width: 60)]).isEmpty)
    // Three underlined links on one row above prose without numbers.
    let links = [proseLine("irs.gov forms.gov treasury.gov", baseline: 700, width: 150)] + paragraph([
        "These sites describe the credit, the rules for claiming it and how to file a return.",
        "Each page explains the schedule that applies and where the amounts are entered.",
        "The instructions repeat the eligibility rules for a qualifying child in detail.",
    ], baseline: 689, widths: [450, 440, 430])
    #expect(regions(links, [45, 90, 135].map { underline(x: $0, baseline: 700, width: 35) }).isEmpty)
    // A right-hand column subheader underlined whole needs at least three numeric rows below.
    func tariff(rows: Int) -> [TextLine] {
        [proseLine("Tariff: Item Number Normal Trade Relations", baseline: 700, width: 300),
         proseLine("12–31–24", x: 468, baseline: 689, width: 44)] + (0..<rows).map {
            proseLine("Copper item \($0 + 1) 7403.00.0000 Free.", baseline: 678 - CGFloat($0) * 11, width: 300)
        }
    }
    // Too few rows: not a table. The underlined short piece keeps a crop of its own line, as
    // any short mathematical line with a rule does, but the rows and heading reflow.
    let sparse = regions(tariff(rows: 2), [underline(x: 468, baseline: 689, width: 44)])
    #expect(sparse.count == 1)
    #expect(tariff(rows: 2).filter { line in sparse.contains { $0.intersects(line.rect) } }.map(\.text) == ["12–31–24"])
    let preserved = regions(tariff(rows: 5), [underline(x: 468, baseline: 689, width: 44)])
    #expect(preserved.count == 1)
    #expect(tariff(rows: 5).allSatisfy { line in preserved.contains { $0.contains(line.rect) } })
}

@Test func fractionBarsBeneathNumeratorsStillCropTheirTerms() throws {
    // An exercise fraction bar sits exactly like an underline beneath its numerator line, but
    // the compact denominator beneath it makes it a fraction: both terms stay in one crop.
    let numerator = TextLine(text: "1) 42", rect: CGRect(x: 85, y: 666, width: 26, height: 12), fontSize: 12)
    let denominator = TextLine(text: "12", rect: CGRect(x: 100, y: 653, width: 11, height: 12), fontSize: 12)
    let neighbor = TextLine(text: "2) 25", rect: CGRect(x: 308, y: 668, width: 26, height: 12), fontSize: 12)
    let instructions = TextLine(text: "Simplify each. Leave your answer as an improper fraction.",
        rect: CGRect(x: 85, y: 690, width: 300, height: 12), fontSize: 12)
    let page = PageContent(number: 1, bounds: pageBounds, lines: [instructions, numerator, denominator, neighbor],
        graphics: [CGRect(x: 98, y: 664, width: 14, height: 4)])
    let regions = LayoutReconstructor.graphicsWithLabels(page)
    #expect(regions.count == 1)
    let region = try #require(regions.first)
    #expect(region.contains(numerator.rect) && region.contains(denominator.rect))
    #expect(!region.intersects(neighbor.rect) && !region.intersects(instructions.rect))
}

@Test func algebraPracticeFractionsKeepEveryBarWithItsTerms() throws {
    let fixture = try SourceLayoutFixture.load("algebra-16")
    #expect(fixture.sourceSHA256 == "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678")
    let page = fixture.content()
    // The page paints 44 short rules: fraction bars plus minus signs drawn as paths.
    let body = max(4, LayoutReconstructor.bodySize(page.lines))
    let bars = page.graphics.filter { LayoutReconstructor.isFractionBar($0, in: page.lines, body: body) }
    #expect(page.graphics.count == 44 && bars.count == 25)
    let regions = LayoutReconstructor.graphicsWithLabels(page)
    #expect(regions.count == 36)
    for bar in bars {
        let terms = page.lines.filter { $0.rect.intersects(bar) }
        #expect(terms.count >= 2, "fraction terms missing at \(bar)")
        #expect(regions.contains { region in region.contains(bar) && terms.allSatisfy { region.contains($0.rect) } },
            "fraction split or flattened at \(bar)")
    }
    let blocks = reflowed(page, regions: regions).filter(\.hasReflowedText)
    #expect(blocks.contains { $0.text.contains("Simplify each. Leave your answer as an improper fraction.") })
    #expect(!blocks.contains { $0.text.contains("42 12") })
}

@Test func ourFlagHeadingRulesAndLeaderTableAreUnchangedControls() throws {
    let page = try SourceLayoutFixture.load("flag-27").content()
    let regions = LayoutReconstructor.graphicsWithLabels(page)
    // Two column-wide heading rules stay isolated crops; the dot-leader table stays whole.
    #expect(regions.count == 3)
    for heading in ["Care of Your Flag", "Sizes of Flags"] {
        let line = try #require(page.lines.first { $0.text == heading })
        #expect(!regions.contains { $0.intersects(line.rect) })
    }
    let header = try #require(page.lines.first { $0.text.contains("FLAGPOLE HEIGHT") })
    let table = try #require(regions.first { $0.contains(header.rect) })
    for height in ["20", "50", "250"] {
        let row = try #require(page.lines.first { $0.text.hasPrefix(height + " .") })
        #expect(table.contains(row.rect))
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/36"))
func usgsProseReflowsWhileUnderlinedTablesStayPreserved() throws {
    func line(_ page: PageContent, _ prefix: String) throws -> TextLine {
        try #require(page.lines.first { $0.text.hasPrefix(prefix) }, "missing source line \(prefix)")
    }
    let first = try SourceLayoutFixture.load("usgs-1")
    #expect(first.sourceSHA256 == "348b1e224d830a51e6d35cf81343eead26a0cb2a4e74c474d699b7faed1b10e6")
    let page1 = first.content()
    let regions1 = LayoutReconstructor.graphicsWithLabels(page1)
    #expect(regions1.count == 2)
    for prefix in ["Domestic Production and Use:", "general products, 10%;", "Recycling: Old", "Import Sources (2020–23):",
                   "Peru, 6%; and other, 3%.", "Depletion Allowance:", "Government Stockpile:", "Prepared by Daniel M. Flanagan"] {
        let source = try line(page1, prefix)
        #expect(!regions1.contains { $0.intersects(source.rect) }, "prose inside a crop: \(prefix)")
    }
    // The reviewed reference regions (corpus/references/usgs-mcs2025-copper) in PDF coordinates.
    let salientReference = CGRect(x: 40, y: 792 - 481, width: 525, height: 276)
    let tariffReference = CGRect(x: 40, y: 792 - 691, width: 525, height: 88)
    for (reference, prefixes) in [(salientReference, ["Salient Statistics—United States:", "2020 2021 2022 2023 2024e",
                                                      "Production:", "Copper recovered from old", "Net import reliance"]),
                                  (tariffReference, ["Tariff: Item Number", "12–31–24", "Copper ore and concentrates", "Copper wire rod"])] {
        let region = try #require(regions1.first { $0.intersects(reference) })
        #expect(reference.insetBy(dx: -6, dy: -6).contains(region))
        for prefix in prefixes {
            let rect = try line(page1, prefix).rect
            #expect(region.contains(rect), "table piece outside crop: \(prefix)")
        }
    }
    let blocks1 = reflowed(page1, regions: regions1)
    let text1 = blocks1.filter(\.hasReflowedText).map(\.text).joined(separator: "\n")
    for phrase in ["Domestic Production and Use: In 2024, the recoverable copper content of U.S. mine production",
                   "Recycling: Old (post-consumer) scrap, converted to refined metal, alloys, and other forms",
                   "Import Sources (2020–23): Copper content of blister and anodes: Finland, 92%",
                   "Depletion Allowance: 15% (domestic), 14% (foreign).", "Government Stockpile: None."] {
        #expect(text1.contains(phrase), "missing reflowed prose: \(phrase)")
    }
    #expect(!text1.contains("Mine, recoverable") && !text1.contains("2603.00.0010"))

    let second = try SourceLayoutFixture.load("usgs-2")
    #expect(second.sourceSHA256 == first.sourceSHA256)
    let page2 = second.content()
    let regions2 = LayoutReconstructor.graphicsWithLabels(page2)
    #expect(regions2.count == 1)
    let world = try #require(regions2.first)
    #expect(CGRect(x: 40, y: 792 - 512, width: 525, height: 240).insetBy(dx: -6, dy: -6).contains(world))
    for prefix in ["Mine production Refinery production", "2023 2024e 2023 2024e", "United States 1,130", "World total (rounded)"] {
        let rect = try line(page2, prefix).rect
        #expect(world.contains(rect), "table piece outside crop: \(prefix)")
    }
    for prefix in ["Events, Trends, and Issues:", "Kentucky and a new secondary", "The COMEX copper price",
                   "World Mine and Refinery Production and Reserves:", "were revised based on company",
                   "World Resources:", "Substitutes:", "eEstimated. — Zero.", "U.S. Geological Survey, Mineral Commodity Summaries"] {
        let rect = try line(page2, prefix).rect
        #expect(!world.intersects(rect), "prose inside the crop: \(prefix)")
    }
    let text2 = reflowed(page2, regions: regions2).filter(\.hasReflowedText).map(\.text).joined(separator: "\n")
    for phrase in ["Events, Trends, and Issues: In 2024, production decreased at a majority of copper mines",
                   "World Resources:", "Substitutes: Aluminum substitutes for copper in automobile radiators"] {
        #expect(text2.contains(phrase), "missing reflowed prose: \(phrase)")
    }
    #expect(!text2.contains("World total (rounded)"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/36"))
func geltmanClosingProseReflowsAroundItsInlineEquation() throws {
    let fixture = try SourceLayoutFixture.load("nbs-7")
    #expect(fixture.sourceSHA256 == "44653967317ce75f324b8051cdf2f123429ca1cbd199fefbffabe9acb9b0c86d")
    var page = fixture.content()
    // The pipeline keeps a page-sized scan as a reference image rather than as a figure.
    if page.graphics.contains(where: { $0.width * $0.height > page.bounds.width * page.bounds.height * 0.75 }) {
        page.graphics = []
    }
    let regions = LayoutReconstructor.graphicsWithLabels(page)
    let closing = page.lines.filter { $0.rect.minX < 260 && $0.rect.minY > 469 && $0.rect.minY < 560 }
    #expect(closing.count == 10)
    #expect(closing.contains { $0.text == "on neutral atoms." })
    for line in closing {
        #expect(!regions.contains { $0.intersects(line.rect) }, "closing prose inside a crop: \(line.text)")
    }
    for line in page.lines where line.rect.minX > 260 {
        #expect(!regions.contains { $0.intersects(line.rect) }, "reference entry inside a crop: \(line.text)")
    }
    // The inline equation line still matches the formula heuristic; its crop stays bounded to
    // that line and its immediate neighbors instead of the column.
    #expect(regions.count == 1)
    let crop = try #require(regions.first)
    #expect(crop.height < 40)
    let blocks = reflowed(page, regions: regions).filter(\.hasReflowedText)
    let paragraph = try #require(blocks.first { $0.text.contains("In concluding, we would like to bring") })
    #expect(paragraph.text.hasSuffix("on neutral atoms."))
    let texts = blocks.map(\.text).joined(separator: "\n")
    let remarks = try #require(texts.range(of: "Our remarks above have been confined"))
    let concluding = try #require(texts.range(of: "In concluding"))
    let references = try #require(texts.range(of: "6. References"))
    #expect(remarks.lowerBound < concluding.lowerBound && concluding.lowerBound < references.lowerBound)
}

// An original PDF with the same layout family: tightly leaded 10-pt Helvetica, section labels
// underlined with filled rectangles, and a borderless table whose headers are underlined.
private func underlinedSectionsPDF() -> Data {
    testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
        testPDFStream("""
        0 g BT /F1 10 Tf 11 TL 45 700 Td
        (Domestic Production and Use: In 2024, mine production of copper decreased by 3% from) Tj T*
        (that in 2023 and was valued at an estimated 10 billion dollars in total output.) Tj T*
        (Arizona was the leading copper-producing State and accounted for most of the output.) Tj
        ET
        45 697.5 140 0.8 re f
        BT /F1 10 Tf 45 656 Td (Salient Statistics:) Tj ET
        BT /F1 10 Tf 300 656 Td (2020) Tj ET BT /F1 10 Tf 350 656 Td (2021) Tj ET BT /F1 10 Tf 400 656 Td (2022) Tj ET
        45 653.5 80 0.8 re f 300 653.5 22 0.8 re f 350 653.5 22 0.8 re f 400 653.5 22 0.8 re f
        BT /F1 10 Tf 45 645 Td (Production:) Tj ET
        BT /F1 10 Tf 55 634 Td (Mine, recoverable) Tj ET
        BT /F1 10 Tf 300 634 Td (1,200) Tj ET BT /F1 10 Tf 350 634 Td (1,230) Tj ET BT /F1 10 Tf 400 634 Td (1,230) Tj ET
        BT /F1 10 Tf 55 623 Td (Refinery) Tj ET
        BT /F1 10 Tf 300 623 Td (872) Tj ET BT /F1 10 Tf 350 623 Td (922) Tj ET BT /F1 10 Tf 400 623 Td (930) Tj ET
        BT /F1 10 Tf 55 612 Td (Imports) Tj ET
        BT /F1 10 Tf 300 612 Td (2) Tj ET BT /F1 10 Tf 350 612 Td (11) Tj ET BT /F1 10 Tf 400 612 Td (12) Tj ET
        BT /F1 10 Tf 11 TL 45 590 Td
        (Recycling: Old scrap converted to refined metal provided about 150,000 tons of) Tj T*
        (copper in 2024, and 720,000 tons of copper was recovered from new scrap derived) Tj T*
        (from fabricating operations, which is about 35% of the total copper supply.) Tj
        ET
        45 587.5 46 0.8 re f
        """),
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ])
}

@Test func underlinedLabelsConvertToProseAndUnderlinedHeadersToOneTableImage() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let source = dir.appendingPathComponent("source.pdf"), output = dir.appendingPathComponent("book.epub")
    try underlinedSectionsPDF().write(to: source)
    var options = ConversionOptions(); options.ocr = .never; options.rasterDPI = 72
    let report = try await PDFConverter().convert(from: source, to: output, options: options)
    #expect(report.reflowedPageCount == 1 && report.recognizedPageCount == 0)
    #expect(report.warnings.contains { $0.code == .imageRegion && $0.page == 1 })
    #expect(!report.warnings.contains { $0.code == .pageImageFallback })
    let archive = try Archive(url: output, accessMode: .read)
    func read(_ path: String) throws -> Data {
        let entry = try #require(archive[path]); var data = Data()
        _ = try archive.extract(entry) { data += $0 }
        return data
    }
    let html = String(decoding: try read("EPUB/chapter-1.xhtml"), as: UTF8.self)
    for phrase in ["Domestic Production and Use: In 2024, mine production of copper decreased by 3% from that in 2023",
                   "Arizona was the leading copper-producing State",
                   "Recycling: Old scrap converted to refined metal provided about 150,000 tons of copper in 2024",
                   "about 35% of the total copper supply."] {
        #expect(html.contains(phrase), "missing prose: \(phrase)")
    }
    for cell in ["Salient Statistics:", "Mine, recoverable", "1,230", "Refinery", "922"] {
        #expect(!html.contains(cell), "table text flattened into prose: \(cell)")
    }
    let images = archive.filter { $0.path.hasSuffix(".png") }
    #expect(images.count == 1)
    let image = try #require(images.first)
    let first = try #require(html.range(of: "Domestic Production"))
    let figure = try #require(html.range(of: "<img "))
    let last = try #require(html.range(of: "Recycling:"))
    #expect(first.lowerBound < figure.lowerBound && figure.lowerBound < last.lowerBound)
    let imageData = try read(image.path)
    let sourceImage = try #require(CGImageSourceCreateWithData(imageData as CFData, nil))
    let raster = try #require(CGImageSourceCreateImageAtIndex(sourceImage, 0, nil))
    // Five rows on 11-pt leading plus margins: the crop covers the table, not the paragraphs.
    #expect(raster.height > 50 && raster.height < 90)
    #expect(raster.width > 360 && raster.width < 460)
}

// MARK: - 9/11 report: an underlined word, and a cited web address (#229, #227)

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/229"))
func anUnderlinedWordDoesNotRasterizeItsNotesPage() throws {
    // Physical page 526 prints one underlined word — `not` in “I do not believe a proposal of
    // this magnitude” — as a 13.3 × 4 pt painted rule inside the note's line box. That rule was
    // the page's only graphic, and the whole-line union grew its crop over all 61 lines.
    let fixture = try SourceLayoutFixture.load("911-526")
    #expect(fixture.sourceSHA256 == "657d41475eb3a9a5e3e87a6c7c51ac1dfbe1af7566d1abff7bf7286e7e1c0e1b")
    let page = fixture.content()
    let rule = try #require(page.graphics.first)
    #expect(page.graphics.count == 1 && LayoutReconstructor.isThinRule(rule))
    let underlined = try #require(LayoutReconstructor.underlinedLine(rule, in: page.lines))
    #expect(underlined.text.contains("I do not believe a pro"))
    #expect(LayoutReconstructor.graphicsWithLabels(page).isEmpty)
    let text = reflowed(page, regions: []).filter(\.hasReflowedText).map(\.text).joined(separator: "\n")
    for phrase in ["137. President Clinton meeting (Apr. 8, 2004).",
                   "I do not believe a pro",
                   "Options to Undermine Usama Bin Ladin"] {
        #expect(text.contains(phrase), "missing reflowed note: \(phrase)")
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/229"))
func underlinedWordsInBodyProseDoNotRasterizeTheirColumn() throws {
    // Physical page 161 underlines `gain` and `risk` inside one line of chapter 4's prose.
    let fixture = try SourceLayoutFixture.load("911-161")
    #expect(fixture.sourceSHA256 == "657d41475eb3a9a5e3e87a6c7c51ac1dfbe1af7566d1abff7bf7286e7e1c0e1b")
    let page = fixture.content()
    #expect(page.graphics.count == 2 && page.graphics.allSatisfy(LayoutReconstructor.isThinRule))
    for rule in page.graphics {
        let line = try #require(LayoutReconstructor.underlinedLine(rule, in: page.lines))
        #expect(line.text.contains("if the gain clearly outweighs the risk"))
    }
    #expect(LayoutReconstructor.graphicsWithLabels(page).isEmpty)
    let text = reflowed(page, regions: []).filter(\.hasReflowedText).map(\.text).joined(separator: "\n")
    for phrase in ["Finally, the CIA considered the possibility of putting U.S. personnel on the",
                   "if the gain clearly outweighs the risk",
                   "chance of achieving that objective."] {
        #expect(text.contains(phrase), "missing reflowed prose: \(phrase)")
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/227"))
func citedWebAddressesAreNotDisplayedEquations() throws {
    // The notes pages paint nothing at all, so a cited query string was a page's only seed.
    for (name, number) in [("911-571", 571), ("911-581", 581), ("911-582", 582), ("911-583", 583)] {
        let fixture = try SourceLayoutFixture.load(name)
        #expect(fixture.page == number)
        #expect(fixture.sourceSHA256 == "657d41475eb3a9a5e3e87a6c7c51ac1dfbe1af7566d1abff7bf7286e7e1c0e1b")
        let content = fixture.content()
        #expect(content.graphics.isEmpty, "page \(number) paints nothing")
        #expect(LayoutReconstructor.graphicsWithLabels(content).isEmpty, "page \(number) seeds a crop")
        let text = reflowed(content, regions: []).filter(\.hasReflowedText).map(\.text).joined(separator: "\n")
        #expect(text.split(whereSeparator: \.isWhitespace).count > 700, "page \(number) reflows too little")
    }
    let notes = try SourceLayoutFixture.load("911-581").content()
    let cited = try #require(notes.lines.first { $0.text.contains("print.php3?ReportID=145") })
    #expect(!LayoutReconstructor.statesAnEquation(cited.text))
    for address in ["item_id=1645&content_type_id=7).",
                    "www.dhs.gov/dhspublic/display?theme=45&content=3498&print=true).",
                    "http://worldtradeaftermath.com/wta/contacts/companies_list.asp?letter=a);"] {
        #expect(LayoutReconstructor.isWebAddress(address[...]))
        #expect(!LayoutReconstructor.statesAnEquation("For the tenants, see " + address + " and the list"))
    }
}

// MARK: - Positive controls: real displayed equations and real ruled figures

@Test func wallaceDisplayedEquationsKeepTheirCrops() throws {
    // Wallace page 343 derives the quadratic formula: its relations are genuine displayed
    // equations and must stay preserved, not flatten into prose.
    let fixture = try SourceLayoutFixture.load("algebra-343")
    #expect(fixture.sourceSHA256 == "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678")
    let page = fixture.content()
    let regions = LayoutReconstructor.graphicsWithLabels(page)
    for statement in ["ax2 + bc +c =0", "ax2 + bx=− c"] {
        let line = try #require(page.lines.first { $0.text == statement })
        #expect(LayoutReconstructor.statesAnEquation(line.text), "no longer an equation: \(statement)")
        #expect(regions.contains { $0.contains(line.rect) }, "equation lost its crop: \(statement)")
    }
    let text = reflowed(page, regions: regions).filter(\.hasReflowedText).map(\.text).joined(separator: "\n")
    #expect(text.contains("Objective: Solve quadratic equations by using the quadratic"))
    #expect(!text.contains("ax2 + bc +c =0"))
}

@Test func fedRuledFiguresKeepTheirCropsBesideARunningHeadRule() throws {
    // The Fed book rules its boxes and charts as painted rectangles and rules every page head.
    // The head rule underlines no line — it is painted clear of every line rectangle — so it
    // stays an isolated crop of its own, as it was before #229; the ruled figures, which are
    // not thin, keep their crops with the labels inside them.
    for (name, crops) in [("fed-32", 2), ("fed-46", 3), ("fed-54", 3)] {
        let page = try SourceLayoutFixture.load(name).content()
        let head = try #require(page.graphics.first { LayoutReconstructor.isThinRule($0) })
        #expect(head.width > page.bounds.width * 0.75)
        #expect(LayoutReconstructor.underlinedLine(head, in: page.lines) == nil)
        let regions = LayoutReconstructor.graphicsWithLabels(page)
        #expect(regions.count == crops, "\(name) keeps \(crops) crops, got \(regions.count)")
        for figure in page.graphics where !LayoutReconstructor.isThinRule(figure) {
            #expect(regions.contains { $0.contains(figure) }, "\(name) lost a ruled figure at \(figure)")
        }
    }
}
