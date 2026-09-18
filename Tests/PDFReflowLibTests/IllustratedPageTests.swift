import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

// Born-digital illustrated pages (#117). The Dietary Guidelines draw section bands, circular photo
// icons, rounded callout boxes and a margin timeline around visible native text. Clustered, that
// art covered DGA pages 3–5, so they took the unverified-text-layer treatment (review warning and
// a source-page reference) meant for text over a picture of the page; on pages 6 and 7 (source
// folios 5 and 7) callout boxes and title bands merged with photos kept prose inside crops.
// Fixtures are native extraction from the checksum-pinned source; expectations were read from the
// rendered pages.

private let dgaSHA256 = "c34f1bec5c9416265670b7fcb24556bb8616ba95e8de2f2890460b6bbca1a472"

// MARK: The image-backed decision (pipeline)

enum IllustratedPageBackground: Sendable {
    case none, scan, fill, pathFill, invisibleText, ruleAgainstText, fillAndFrame, fillWithFigureOnALabel
}

/// A two-section page: an 18-pt heading and eight prose lines per section, a square icon left of
/// each heading, a footer band holding a folio and a 1-pt timeline stroked down the margin from the
/// footer through both icons. Together the art clusters into a region covering 95% of the page.
private func illustratedPDF(_ background: IllustratedPageBackground) -> Data {
    var art = "0.9 0.95 0.9 rg 0 0 600 60 re f\n0.2 0.6 0.3 rg 25 590 30 30 re f 25 290 30 30 re f\n"
    // The timeline stands 50 pt clear of the text, or (control) against the text's left edge.
    let x = background == .ruleAgainstText ? 86 : 40
    art += "0 0.5 0 RG 1 w \(x) 58 m \(x) 760 l S\n"
    switch background {
    case .scan: art = "q 600 0 0 800 0 0 cm /Im Do Q\n" + art
    case .fill: art = "0.99 0.98 0.93 rg 0 0 600 800 re f\n" + art
    // What a presentation tool paints: the background and each text placeholder as a path, not a
    // rectangle, so the tint rules of #54 never see them (the Earthdata deck's own shape).
    case .pathFill:
        art = "0.2 0.3 0.4 rg 0 0 m 600 0 l 600 800 l 0 800 l h f\n"
            + "0.95 0.95 0.95 rg 60 430 m 560 430 l 560 630 l 60 630 l h f\n"
            + "0.95 0.95 0.95 rg 60 130 m 560 130 l 560 330 l 60 330 l h f\n" + art
    // The Fed colophon's shape: a page-sized tint with a page-sized border drawn around it.
    case .fillAndFrame: art = "0.99 0.98 0.93 rg 0 0 600 800 re f\n0.2 G 1 w 0 0 600 800 re S\n" + art
    // A figure drawn over a line's box, as the deck's pipeline icons stand on their labels: the
    // crop that grows from it would take that line out of the reflowed text.
    case .fillWithFigureOnALabel:
        art = "0.99 0.98 0.93 rg 0 0 600 800 re f\n" + art + "q 120 0 0 60 90 560 cm /Im Do Q\n"
    default: break
    }
    let mode = background == .invisibleText ? 3 : 0
    let prose = "Choose a variety of whole foods for every meal of the day"
    var text = ""
    for (section, top) in [(0, 600), (1, 300)] {
        text += "BT /F1 18 Tf \(mode) Tr 1 0 0 1 70 \(top) Tm (Section \(section + 1) heading for whole foods) Tj ET\n"
        for line in 0..<8 {
            text += "BT /F1 12 Tf \(mode) Tr 1 0 0 1 90 \(top - 30 - line * 16) Tm (\(prose) \(line)) Tj ET\n"
        }
    }
    text += "BT /F1 10 Tf \(mode) Tr 1 0 0 1 400 30 Tm (Guidelines page 3) Tj ET"
    return testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Resources << /Font << /F1 4 0 R >> /XObject << /Im 6 0 R >> >> /Contents 5 0 R >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        testPDFStream(art + text),
        testPDFStream("FFFFFF>", extra: "/Type /XObject /Subtype /Image /Width 1 /Height 1 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /ASCIIHexDecode"),
    ])
}

private func reconstruct(_ pdf: Data) async throws -> PDFReflowLibPipeline.Result {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("source.pdf")
    try pdf.write(to: url)
    var options = ConversionOptions(); options.ocr = .never
    return try await PDFReflowLibPipeline.reconstruct(from: url, options: options,
        workspace: dir.appendingPathComponent("work"), progress: { _ in })
}

private func hasReference(_ result: PDFReflowLibPipeline.Result) -> Bool {
    result.document.blocks.contains { if case let .image(image) = $0.content { image.provenance.hasPrefix("Source page") && image.alternativeText == PreservedImageKind.sourcePage.alternativeText } else { false } }
}

@Test func artThatOnlyClustersIntoAPageSizedRegionReflowsWithoutTheReviewSignal() async throws {
    let document = try #require(PDFDocument(data: illustratedPDF(.none)))
    let graphics = GraphicsReader.read(try #require(document.page(at: 0)?.pageRef))
    #expect(graphics.regions.contains { $0.width * $0.height > 600 * 800 * 0.75 })
    let result = try await reconstruct(illustratedPDF(.none))
    #expect(!result.warnings.contains { $0.code == .unverifiedTextLayer })
    #expect(!hasReference(result))
    #expect(result.document.blocks.filter { if case .heading = $0.content { true } else { false } }.count == 2)
    #expect(result.document.blocks.contains { $0.text.contains("of the day 7") })
    // The icons stay preserved regions.
    #expect(result.document.blocks.filter { if case .image = $0.content { true } else { false } }.count >= 2)
}

@Test(arguments: [IllustratedPageBackground.scan, .invisibleText, .ruleAgainstText, .fillAndFrame])
func textOverAPictureOfThePageKeepsTheReviewSignal(_ background: IllustratedPageBackground) async throws {
    // A page-sized image (a scan), invisible text, art whose crops would still hold the text (the
    // rule set against the prose joins everything), and a page-sized outline drawn over a
    // background fill (the Fed colophon, #72/#164) keep the warning.
    let result = try await reconstruct(illustratedPDF(background))
    #expect(result.warnings.contains { $0.code == .unverifiedTextLayer && $0.page == 1 }, "\(background)")
    #expect(hasReference(result), "\(background)")
}

@Test(arguments: [IllustratedPageBackground.fill, .pathFill])
func aBackgroundFillUnderNativeTextIsNoPictureOfThePage(_ background: IllustratedPageBackground) async throws {
    // #164: the same page with a full-bleed background fill reads exactly as it does without one,
    // whether the page paints that ground as a rectangle or, as a presentation tool does, as a
    // path under placeholder paths of its own. A flat colour behind visible native text is the
    // page's ground, not a picture of it.
    let result = try await reconstruct(illustratedPDF(background))
    #expect(!result.warnings.contains { $0.code == .unverifiedTextLayer }, "\(background)")
    #expect(!hasReference(result), "\(background)")
    #expect(result.document.blocks.filter { if case .heading = $0.content { true } else { false } }.count == 2, "\(background)")
    #expect(result.document.blocks.contains { $0.text.contains("of the day 7") }, "\(background)")
    // The icons stay preserved regions. The footer band holds the folio, so with the fill in
    // place it is a backdrop too, and the timeline joins the two icons into one margin crop.
    #expect(result.document.blocks.filter { if case .image = $0.content { true } else { false } }.count >= 1)
}

@Test func aBackdropPageWhoseFigureStandsOnALabelKeepsItsWholeTextAndAReference() async throws {
    // #164: the deck's pipeline icons are drawn in boxes over their labels, so a crop grown from
    // one takes that label out of the slide. Such a page keeps a source-page reference and no
    // crop, as an unverified page does, but its native text is not in doubt: no review warning.
    let result = try await reconstruct(illustratedPDF(.fillWithFigureOnALabel))
    #expect(!result.warnings.contains { $0.code == .unverifiedTextLayer })
    #expect(hasReference(result))
    #expect(result.document.blocks.contains { $0.text.contains("Section 1 heading for whole foods") })
    #expect(result.document.blocks.contains { $0.text.contains("of the day 7") })
    // Every crop is given up for the reference, so the icons are in the page image alone.
    #expect(result.document.blocks.filter { if case .image = $0.content { true } else { false } }.count == 1)
}

@Test func aLayoutComesApartOnlyWhenItsCropsLeaveTheText() {
    // Twenty ten-word lines in a strip at the foot of a 600 × 800 page (y 10–189), and crop seeds.
    let lines = (0..<20).map {
        TextLine(text: "one two three four five six seven eight nine ten", rect: CGRect(x: 60, y: 10 + CGFloat($0) * 9, width: 480, height: 8), fontSize: 7)
    }
    let page = CGRect(x: 0, y: 0, width: 600, height: 800)
    func comesApart(_ seeds: [CGRect], invisible: Bool = false, paints: [GraphicsReader.Paint] = []) -> Bool {
        var graphics = GraphicsReader.Result(regions: [], paints: paints, unsupported: false)
        graphics.hasInvisibleText = invisible
        return PDFReflowLibPipeline.layoutComesApart(PageContent(number: 1, bounds: page, lines: lines, graphics: seeds), graphics: graphics)
    }
    let icon = CGRect(x: 20, y: 700, width: 60, height: 60)
    #expect(comesApart([icon]))
    // A crop over more than 75% of the page stays the page's picture even when it takes no line.
    #expect(!comesApart([CGRect(x: 0, y: 195, width: 600, height: 605)]))
    #expect(comesApart([CGRect(x: 0, y: 195, width: 600, height: 580)]))
    // Crops taking 15% of the words hold the text; 5% (a running foot) do not.
    #expect(!comesApart([icon, CGRect(x: 0, y: 10, width: 600, height: 26)]))
    #expect(comesApart([icon, CGRect(x: 0, y: 10, width: 600, height: 6)]))
    // Invisible text, or one page-sized paint that is not a backdrop fill, keeps the signal
    // whatever the crops: an image (a scan) or an outline (the Fed colophon's border, #164).
    #expect(!comesApart([icon], invisible: true))
    #expect(!comesApart([icon], paints: [GraphicsReader.Paint(rect: page, frame: true, image: true)]))
    #expect(!comesApart([icon], paints: [GraphicsReader.Paint(rect: page, frame: true)]))
    #expect(!comesApart([icon], paints: [GraphicsReader.Paint(rect: page, frame: true, filled: true),
                                         GraphicsReader.Paint(rect: page, frame: true)]))
    // A page-sized fill is the page's backdrop, and its crops may hold up to half its words.
    #expect(comesApart([icon], paints: [GraphicsReader.Paint(rect: page, frame: true, filled: true)]))
    #expect(comesApart([icon, CGRect(x: 0, y: 10, width: 600, height: 26)],
                       paints: [GraphicsReader.Paint(rect: page, frame: true, filled: true)]))
    #expect(!comesApart([icon, CGRect(x: 0, y: 10, width: 600, height: 100)],
                        paints: [GraphicsReader.Paint(rect: page, frame: true, filled: true)]))
    #expect(comesApart([icon], paints: [GraphicsReader.Paint(rect: CGRect(x: 0, y: 0, width: 600, height: 590), frame: true, filled: true)]))
}

@Test func readerMarksImagesAndFills() throws {
    func paints(_ body: String) throws -> [GraphicsReader.Paint] {
        let document = try #require(PDFDocument(data: testPDF(objects: [
            "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 500] /Resources << /XObject << /Im 5 0 R >> >> /Contents 4 0 R >>",
            testPDFStream(body),
            testPDFStream("FFFFFF>", extra: "/Type /XObject /Subtype /Image /Width 1 /Height 1 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /ASCIIHexDecode"),
        ])))
        return GraphicsReader.read(try #require(document.page(at: 0)?.pageRef)).paints
    }
    let image = try paints("q 100 0 0 80 50 300 cm /Im Do Q")
    #expect(image.count == 1 && image[0].image && !image[0].filled)
    // A curved box filled, filled and stroked, closed-filled-stroked, stroked, and a stroked outline.
    for (op, filled) in [("f", true), ("B", true), ("b", true), ("f*", true), ("S", false), ("s", false)] {
        let shape = try paints("0.5 g 1 w 50 50 m 150 50 l 150 100 l 100 140 50 120 50 50 c \(op)")
        #expect(shape.count == 1 && shape[0].filled == filled && !shape[0].image, "\(op)")
    }
}

// MARK: DGA source pages

private func fixture(_ page: Int) throws -> SourceLayoutFixture {
    let fixture = try SourceLayoutFixture.load("dga-\(page)-illustrated")
    #expect(fixture.sourceSHA256 == dgaSHA256)
    return fixture
}

private func rect(_ values: [Double]) -> CGRect { CGRect(x: values[0], y: values[1], width: values[2], height: values[3]) }

private func paints(_ fixture: SourceLayoutFixture) -> [GraphicsReader.Paint] {
    (fixture.paints ?? []).map { GraphicsReader.Paint(rect: rect($0.rect), frame: $0.frame, image: $0.image ?? false, filled: $0.filled ?? false) }
}

/// The page as reconstruction sees it: the running foot furniture removal takes is gone.
private func reflowed(_ fixture: SourceLayoutFixture) -> (page: PageContent, crops: [CGRect], blocks: [ReflowBlock]) {
    var page = fixture.content()
    page.lines.removeAll { $0.rect.maxY < 60 }
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: crops.enumerated().map { ($0.element, "image-\($0.offset)") },
                                            vocabulary: [], warnings: &warnings)
    return (page, crops, blocks)
}

private func headings(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .heading = $0.content { $0.text } else { nil } }
}

private func index(of prefix: String, in blocks: [ReflowBlock]) throws -> Int {
    try #require(blocks.firstIndex { $0.text.hasPrefix(prefix) }, "no block opens with \(prefix)")
}

@Test(arguments: [3, 4, 5])
func dgaSectionPagesComeApartIntoIconsBannerAndFooter(_ number: Int) throws {
    let source = try fixture(number)
    let page = source.content()
    let area = page.bounds.width * page.bounds.height
    // The reader's regions still cluster into a page-sized one; composition takes it apart.
    #expect(source.graphics.map(rect).contains { $0.width * $0.height > area * 0.75 })
    #expect(!page.graphics.contains { $0.width * $0.height > area * 0.5 })
    let graphics = GraphicsReader.Result(regions: source.graphics.map(rect), paints: paints(source), unsupported: false)
    #expect(PDFReflowLibPipeline.layoutComesApart(page, graphics: graphics))
    // Only the running foot lies in a crop; every section title and bullet reflows.
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    #expect(page.lines.filter { line in crops.contains { $0.intersects(line.rect) } }.allSatisfy { $0.rect.maxY < 60 })
    // Negative control: without composition the art is one crop over every line.
    let untinted = source.content(tinted: false)
    #expect(!PDFReflowLibPipeline.layoutComesApart(untinted, graphics: graphics))
}

@Test func dgaCallBoxesAndTheirTabsReflow() throws {
    // Page 3's `Gut Health`, page 6's `Sodium` and page 8's infant-feeding box: a filled rounded box
    // with a tab holding its title. The prose and the title reflow; no crop takes them.
    for (number, title, first) in [(3, "Gut Health", "+ Your gut contains trillions"), (6, "Sodium", "+ Sodium and electrolytes"),
                                   (8, "Introducing Food to Infants & Toddlers", "+ Every child is different.")] {
        let result = reflowed(try fixture(number))
        #expect(headings(result.blocks).contains(title), "page \(number)")
        let heading = try index(of: title, in: result.blocks)
        #expect(try index(of: first, in: result.blocks) == heading + 1, "page \(number)")
    }
    let sodium = reflowed(try fixture(6))
    let items = sodium.blocks.map(\.text)
    #expect(items.filter { $0.hasPrefix("- Ages") }.count == 3)
}

@Test func dgaPage6ConnectorLeavesTheFirstBulletRowToProse() throws {
    // The 21-pt stroke from the icon up to the banner joined them into one crop across the columns,
    // which took `+ Consume less alcohol for better` and `amount they drink, and people taking`.
    let result = reflowed(try fixture(6))
    for prefix in ["+ Consume less alcohol for better", "amount they drink, and people taking", "Limit Alcoholic Beverages"] {
        let line = try #require(result.page.lines.first { $0.text.hasPrefix(prefix) })
        #expect(!result.crops.contains { $0.intersects(line.rect) }, "\(prefix) inside a crop")
    }
    #expect(result.blocks.contains { $0.text == "+ Consume less alcohol for better overall health." })
    #expect(result.blocks.contains { $0.text.hasPrefix("+ People who should completely avoid alcohol") && $0.text.hasSuffix("associated addictive behaviors.") })
}

@Test func dgaSectionIconsReadWithTheirTitles() throws {
    // Page 4: each icon reaches past its title into the section above and below. It reads just
    // before its title; the sections keep their column order (#103's heading still follows the
    // right column's last bullet and its sub-items).
    let result = reflowed(try fixture(4))
    let blocks = result.blocks
    #expect(blocks.contains { $0.text == "+ If preferred, flavor with salt, spices, and herbs." })
    let leftLast = try index(of: "+ If preferred", in: blocks)
    let rightFirst = try index(of: "+ 100% fruit", in: blocks)
    let fruits = try index(of: "- Fruits: 2 servings per day", in: blocks)
    let fats = try index(of: "Incorporate Healthy Fats", in: blocks)
    let inGeneral = try index(of: "+ In general, saturated fat", in: blocks)
    let grains = try index(of: "Focus on Whole Grains", in: blocks)
    #expect(leftLast < rightFirst && rightFirst < fruits && fruits < fats && fats < inGeneral && inGeneral < grains)
    for heading in [fats, grains] {
        guard case .image = blocks[heading - 1].content else { Issue.record("no icon before \(blocks[heading].text)"); continue }
    }
    // Page 5's two-line title reads as one heading after its icon.
    let five = reflowed(try fixture(5)).blocks
    let title = try index(of: "Limit Highly Processed Foods, Added Sugars, & Refined Carbohydrates", in: five)
    guard case .heading = five[title].content, case .image = five[title - 1].content else {
        Issue.record("page 5 title \(five[title].text)"); return
    }
}

@Test func dgaLinkUnderlinesDoNotJoinFootnotesToTheFooterBand() throws {
    // Page 2's footnotes 2 and 4 sit 2 pt above the footer band; their link underlines joined them to it.
    let source = try fixture(2)
    let result = reflowed(source)
    for url in ["nchs/fastats/obesity-overweight", "military-readiness/unfit-to-serve"] {
        let line = try #require(result.page.lines.first { $0.text.contains(url) })
        #expect(!result.crops.contains { $0.intersects(line.rect) }, "\(url) inside a crop")
    }
    // Negative control: the reader's clusters take both notes into the footer crop.
    let untinted = source.content(tinted: false)
    let note = try #require(untinted.lines.first { $0.text.contains("nchs/fastats/obesity-overweight") })
    #expect(LayoutReconstructor.graphicsWithLabels(untinted).contains { $0.intersects(note.rect) })
}

// MARK: Synthetic guards

private func line(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat = 300, size: CGFloat = 12) -> TextLine {
    TextLine(text: text, rect: CGRect(x: x, y: y, width: width, height: size * 1.3), fontSize: size)
}

private let proseLines = (0..<5).map { line("Choose a variety of whole foods every day \($0)", x: 120, y: 400 - CGFloat($0) * 16) }
private let bounds = CGRect(x: 0, y: 0, width: 600, height: 800)

@Test func calloutShapesMustBeFilledAndHoldOnlyText() {
    let box = CGRect(x: 110, y: 310, width: 330, height: 120)
    let filled = GraphicsReader.Paint(rect: box, frame: false, filled: true)
    #expect(TintDetector.compose([filled], lines: proseLines, bounds: bounds).tints == [box])
    // A stroked outline (streamlines, an unfilled path) seeds a crop as before.
    let stroked = GraphicsReader.Paint(rect: box, frame: false)
    #expect(TintDetector.compose([stroked], lines: proseLines, bounds: bounds).graphics == [box])
    // A filled box holding other art is a boxed figure (Fed page 130).
    let art = GraphicsReader.Paint(rect: CGRect(x: 300, y: 320, width: 40, height: 20), frame: false, filled: true)
    #expect(TintDetector.compose([filled, art], lines: proseLines, bounds: bounds).tints.isEmpty)
    // An image is never a backdrop.
    let photo = GraphicsReader.Paint(rect: box, frame: false, image: true, filled: false)
    #expect(TintDetector.compose([photo], lines: proseLines, bounds: bounds).tints.isEmpty)
    // Too little prose: two lines.
    #expect(TintDetector.compose([filled], lines: Array(proseLines.prefix(2)), bounds: bounds).tints.isEmpty)
}

@Test func calloutTabHoldsOnlyItsTitle() {
    let box = CGRect(x: 110, y: 310, width: 330, height: 120)
    let tab = CGRect(x: 110, y: 428, width: 90, height: 34)
    let title = line("Sodium", x: 120, y: 436, width: 60, size: 18)
    let paints = [GraphicsReader.Paint(rect: box, frame: false, filled: true), GraphicsReader.Paint(rect: tab, frame: false, filled: true)]
    #expect(TintDetector.compose(paints, lines: proseLines + [title], bounds: bounds).tints.sorted { $0.minY < $1.minY } == [box, tab])
    // A title sticking out of the shape is not its tab's.
    let wide = line("Sodium and electrolytes", x: 120, y: 436, width: 200, size: 18)
    #expect(!TintDetector.compose(paints, lines: proseLines + [wide], bounds: bounds).tints.contains(tab))
}

@Test func marginRulesBridgeNoArtAcrossProse() {
    // An icon above the prose and a footer band across the page below it, as on DGA pages 3–5.
    let top = CGRect(x: 20, y: 600, width: 60, height: 60), bottom = CGRect(x: 0, y: 150, width: 600, height: 60)
    let rule = CGRect(x: 48, y: 210, width: 4, height: 390)
    // The rule, 68 pt clear of the prose, joined icon and band into one hull over five prose lines.
    #expect(clusters([top, bottom, rule], distance: 4).count == 1)
    #expect(TintDetector.seedClusters([top, bottom, rule], lines: proseLines).count == 2)
    // Controls: a rule within two bodies of a line (a grid's rule), no prose in the hull, and a
    // single escaped line keep the rule as a seed of its own. Since #158 a hull that bridges
    // running text is split whatever bridges it, so the parts are counted rather than the hull:
    // only a dropped rule leaves no seed of its own.
    let near = CGRect(x: 100, y: 210, width: 4, height: 390)
    let nearTop = CGRect(x: 72, y: 600, width: 60, height: 60)
    #expect(TintDetector.seedClusters([nearTop, bottom, near], lines: proseLines).contains { $0.contains(near) })
    #expect(TintDetector.seedClusters([top, bottom, rule], lines: []).count == 1)
    #expect(TintDetector.seedClusters([top, bottom, rule], lines: Array(proseLines.prefix(1))).count == 1)
    #expect(!TintDetector.seedClusters([top, bottom, rule], lines: proseLines).contains { $0.contains(rule) })
    // A thick bar is not a rule.
    let bar = CGRect(x: 40, y: 210, width: 20, height: 390)
    #expect(TintDetector.seedClusters([top, bottom, bar], lines: proseLines).contains { $0.contains(bar) })
}

@Test func anUnderlineBridgesOnlyWhenItUnderlinesOneLine() {
    let band = CGRect(x: 0, y: 0, width: 600, height: 74)
    let notes = [line("2 https://www.example.gov/data/statistics/obesity-overweight.htm", x: 54, y: 77.5, width: 260, size: 6),
                 line("4 https://www.example.gov/activity/readiness/unfit-to-serve.html", x: 316, y: 77.5, width: 260, size: 6)]
    let body = (0..<6).map { line("Body prose that sets the ordinary size of this page \($0)", x: 54, y: 400 - CGFloat($0) * 16) }
    let underlines = [CGRect(x: 55, y: 76.1, width: 250, height: 4), CGRect(x: 316, y: 76.1, width: 250, height: 4)]
    #expect(TintDetector.seedClusters([band] + underlines, lines: notes + body) == [band])
    // A rule touching two lines, or reaching beyond its line, is not an underline.
    let spanning = [CGRect(x: 55, y: 76.1, width: 511, height: 4)]
    #expect(TintDetector.seedClusters([band] + spanning, lines: notes + body).count == 1)
    #expect(TintDetector.seedClusters([band] + spanning, lines: notes + body) != [band])
}

@Test func titleBackdropsAreJudgedPerPaintOnlyOutsideBoxesAndFrames() {
    let title = line("Consume Dairy Every Day", x: 114, y: 334.6, width: 108, size: 18)
    let body = (0..<8).map { line("Body prose that sets the ordinary size of this page \($0)", x: 123, y: 300 - CGFloat($0) * 16) }
    let band = GraphicsReader.Paint(rect: CGRect(x: 100.4, y: 327.9, width: 477.9, height: 32.7), frame: false, filled: true)
    let icon = GraphicsReader.Paint(rect: CGRect(x: 35, y: 315.3, width: 61.9, height: 61.9), frame: false, filled: true)
    // The band holds the whole title: it is dropped even though it touches the icon.
    #expect(TintDetector.withoutTitleBackdrops([band, icon], lines: body + [title]) == [icon])
    // Controls: a rectangle frame band, a band inside a box and an image are left to clustering.
    var frame = band; frame.frame = true
    #expect(TintDetector.withoutTitleBackdrops([frame, icon], lines: body + [title]).count == 2)
    let box = GraphicsReader.Paint(rect: CGRect(x: 90, y: 100, width: 500, height: 280), frame: false, filled: true)
    #expect(TintDetector.withoutTitleBackdrops([band, box], lines: body + [title]).count == 2)
    var photo = band; photo.image = true
    #expect(TintDetector.withoutTitleBackdrops([photo, icon], lines: body + [title]).count == 2)
}

@Test func aStackedTitleIsOneTitleOnlyWhenJudgedPerPaint() {
    // DGA page 5's band behind a two-line title; the cluster rule (Fed page 130's boxed title bar)
    // still reads two title lines as not a band.
    let upper = line("Limit Highly Processed Foods, Added Sugars,", x: 110.7, y: 707, width: 327.7, size: 18)
    let lower = line("& Refined Carbohydrates", x: 110.7, y: 687, width: 178.4, size: 18)
    let body = (0..<8).map { line("Body prose that sets the ordinary size of this page \($0)", x: 123, y: 600 - CGFloat($0) * 16) }
    let band = CGRect(x: 108.4, y: 679.2, width: 469.6, height: 60.2)
    #expect(LayoutReconstructor.titleArt(band, in: body + [upper, lower], body: 12, stacked: true) == .some(nil))
    #expect(LayoutReconstructor.titleArt(band, in: body + [upper, lower], body: 12) == nil)
    // Two titles from different left edges are not one title.
    let offset = line("& Refined Carbohydrates", x: 300, y: 687, width: 178.4, size: 18)
    #expect(LayoutReconstructor.titleArt(band, in: body + [upper, offset], body: 12, stacked: true) == nil)
}

@Test func onlyAnIconBesideAHeadingReadsInItsRow() throws {
    // DGA page 4 with its icon crops moved: 30 pt further left (beyond two bodies of the titles) they
    // no longer read beside them, and stretched 20 pt past three title lines each way they again
    // cut the section apart.
    var page = try fixture(4).content()
    page.lines.removeAll { $0.rect.maxY < 60 }
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    let icons = crops.filter { $0.width < 100 }
    #expect(icons.count == 3)
    func texts(_ regions: [CGRect]) -> [String] {
        var warnings: [ConversionWarning] = []
        return LayoutReconstructor.blocks(page: page, images: regions.enumerated().map { ($0.element, "image-\($0.offset)") },
                                          vocabulary: [], warnings: &warnings)
            .map { if case .image = $0.content { "image" } else { $0.text } }
    }
    let beside = texts(crops)
    let fats = try #require(beside.firstIndex(of: "Incorporate Healthy Fats"))
    #expect(fats > 0 && beside[fats - 1] == "image")
    let far = texts(crops.map { icons.contains($0) ? $0.offsetBy(dx: -30, dy: 0) : $0 })
    let farFats = try #require(far.firstIndex(of: "Incorporate Healthy Fats"))
    #expect(farFats == 0 || far[farFats - 1] != "image")
    // Stretched, they again cut the section apart. Before `+` was a bullet this split `+ If preferred,
    // flavor with salt, spices,` from `and herbs.`; the item's wrapped line now stays with it (#194),
    // and the cut shows in the order instead: the section's `+ 100% fruit or vegetable juice` item
    // reads after the next section's title.
    let tall = texts(crops.map { icons.contains($0) ? $0.insetBy(dx: 0, dy: -20) : $0 })
    func juiceReadsAfterFats(_ texts: [String]) throws -> Bool {
        let juice = try #require(texts.firstIndex { $0.hasPrefix("+ 100% fruit or vegetable juice") })
        return juice > (try #require(texts.firstIndex(of: "Incorporate Healthy Fats")))
    }
    #expect(try juiceReadsAfterFats(tall))
    #expect(try !juiceReadsAfterFats(beside))
    #expect(!beside.contains("and herbs.") && beside.contains("+ If preferred, flavor with salt, spices, and herbs."))
}

// MARK: Cost on vector-dense pages

@Test func vectorDensePagesStayBoundedAndKeepTheirClustering() {
    // A title and six prose lines at the foot of the page, and a drawing above them.
    var lines = [TextLine(text: "Consume Dairy Every Day", rect: CGRect(x: 114, y: 160, width: 108, height: 24), fontSize: 18)]
    lines += (0..<6).map {
        TextLine(text: "Body prose that sets the ordinary size of this page \($0)", rect: CGRect(x: 60, y: 20 + CGFloat($0) * 16, width: 480, height: 13), fontSize: 10)
    }
    let page = CGRect(x: 0, y: 0, width: 600, height: 800)
    // 4,020 filled vector marks overlapping in rows, plus a band that holds the title: past the
    // candidate limit the band is left to clustering, as before #117.
    var paints: [GraphicsReader.Paint] = []
    for row in 0..<60 {
        for column in 0..<67 {
            paints.append(GraphicsReader.Paint(rect: CGRect(x: CGFloat(column) * 8.5, y: 230 + CGFloat(row) * 9, width: 10, height: 10), frame: false, filled: true))
        }
    }
    let band = GraphicsReader.Paint(rect: CGRect(x: 100.4, y: 155, width: 477.9, height: 32.7), frame: false, filled: true)
    paints.append(band)
    #expect(paints.count > TintDetector.titleBackdropCandidateLimit)
    var start = Date()
    #expect(TintDetector.withoutTitleBackdrops(paints, lines: lines) == paints)
    let dense = TintDetector.compose(paints, lines: lines, bounds: page)
    let denseSeconds = Date().timeIntervalSince(start)
    #expect(dense.graphics == clusters(paints.map(\.rect), distance: 4) && dense.tints.isEmpty)
    // Control: the same band among a few marks is still title art.
    #expect(TintDetector.withoutTitleBackdrops(Array(paints.prefix(20)) + [band], lines: lines) == Array(paints.prefix(20)))
    // 2,400 isolated strokes clear of the text, each its own cluster.
    var strokes: [CGRect] = []
    for row in 0..<48 {
        for column in 0..<50 { strokes.append(CGRect(x: CGFloat(column) * 12, y: 220 + CGFloat(row) * 12, width: 2, height: 6)) }
    }
    start = Date()
    let isolated = TintDetector.seedClusters(strokes, lines: lines)
    let strokeSeconds = Date().timeIntervalSince(start)
    #expect(isolated == clusters(strokes, distance: 4))
    #expect(denseSeconds < 3 && strokeSeconds < 3, "compose \(denseSeconds) s, strokes \(strokeSeconds) s")
}
