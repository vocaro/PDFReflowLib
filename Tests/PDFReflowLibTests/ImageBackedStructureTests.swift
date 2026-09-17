import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

/// A tagged page drawn over a page-sized background image, as the Fed's chapter openers are
/// (#72). The heading is set in body type, so only its `H2` tag can make it a heading; the
/// paragraph's two lines carry one `P` identity. `mode` is the text rendering mode of every line;
/// `invisibleLine` adds one untagged invisible line, as an inherited OCR fragment would be.
private func backgroundImageTaggedPDF(mode: Int, invisibleLine: Bool = false, image: Bool = true) -> Data {
    let background = image ? "/Artifact << /O /Layout >> BDC q 600 0 0 800 0 0 cm /Im Do Q EMC\n" : ""
    let hidden = invisibleLine ? "\nBT /F1 12 Tf 3 Tr 1 0 0 1 40 300 Tm (Recognized fragment) Tj ET" : ""
    return testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R /StructTreeRoot 6 0 R /MarkInfo << /Marked true >> >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Resources << /Font << /F1 4 0 R >> /XObject << /Im 10 0 R >> >> /Contents 5 0 R /StructParents 0 >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        testPDFStream(background + """
        /H2 << /MCID 0 >> BDC BT /F1 12 Tf \(mode) Tr 1 0 0 1 40 700 Tm (Overview of the Federal Reserve) Tj ET EMC
        /P << /MCID 1 >> BDC BT /F1 12 Tf \(mode) Tr 1 0 0 1 40 660 Tm (The Federal Reserve performs five key functions in the public) Tj ET EMC
        /P << /MCID 2 >> BDC BT /F1 12 Tf \(mode) Tr 1 0 0 1 40 645 Tm (interest to promote the health of the economy.) Tj ET EMC
        """ + hidden),
        "<< /Type /StructTreeRoot /K [8 0 R 9 0 R] /ParentTree 7 0 R >>",
        "<< /Nums [0 [8 0 R 9 0 R 9 0 R]] >>",
        "<< /Type /StructElem /S /H2 /P 6 0 R /Pg 3 0 R /K 0 >>",
        "<< /Type /StructElem /S /P /P 6 0 R /Pg 3 0 R /K [1 2] >>",
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

private func headings(_ result: PDFReflowLibPipeline.Result) -> [String] {
    result.document.blocks.compactMap { if case let .heading(_, text, _) = $0.content { text.text } else { nil } }
}

@Test func visibleTaggedTextOverABackgroundImageKeepsItsTags() async throws {
    let result = try await reconstruct(backgroundImageTaggedPDF(mode: 0))
    #expect(headings(result) == ["Overview of the Federal Reserve"])
    let heading = try #require(result.document.blocks.first { $0.text == "Overview of the Federal Reserve" })
    #expect(heading.taggedLevel == 2)
    let paragraph = try #require(result.document.blocks.first { $0.text.hasPrefix("The Federal Reserve performs") })
    #expect(paragraph.taggedLevel == 0 && paragraph.structureGroup != nil)
    #expect(paragraph.text.hasSuffix("public interest to promote the health of the economy."))
    // The review signal and its source-page reference are unchanged: only structure survives.
    #expect(result.warnings.contains { $0.code == .unverifiedTextLayer && $0.page == 1 })
    #expect(!result.warnings.contains { $0.code == .structureFallback })
    #expect(result.document.assets.count == 1)
}

@Test(arguments: [(3, false), (0, true)])
func invisibleTextOverABackgroundImageNeverInheritsTags(mode: Int, invisibleLine: Bool) async throws {
    // An exclusively invisible layer, and a visible layer with one invisible fragment: both are
    // inherited transcription candidates, so no line keeps a tag and the body-size title is prose.
    let result = try await reconstruct(backgroundImageTaggedPDF(mode: mode, invisibleLine: invisibleLine))
    #expect(headings(result).isEmpty)
    #expect(result.document.blocks.allSatisfy { $0.taggedLevel == nil && $0.structureGroup == nil })
    #expect(result.document.blocks.contains { $0.text.contains("Overview of the Federal Reserve") })
    #expect(result.warnings.contains { $0.code == .unverifiedTextLayer && $0.page == 1 })
}

@Test func theSameTaggedPageWithoutABackgroundAppliesItsTags() async throws {
    // Positive control: the fixture's tags validate and apply on their own, with no review warning.
    let result = try await reconstruct(backgroundImageTaggedPDF(mode: 0, image: false))
    #expect(headings(result) == ["Overview of the Federal Reserve"])
    #expect(!result.warnings.contains { $0.code == .unverifiedTextLayer })
}

@Test func graphicsReaderReportsAnyInvisibleText() throws {
    func inspect(_ body: String) throws -> GraphicsReader.Result {
        let document = try #require(PDFDocument(data: testPDF(objects: [
            "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 500] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
            testPDFStream(body), "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        ])))
        return GraphicsReader.read(try #require(document.page(at: 0)?.pageRef))
    }
    let hidden = "BT /F1 12 Tf 3 Tr 40 400 Td (Hidden) Tj ET "
    let visible = "BT /F1 12 Tf 0 Tr 40 380 Td (Visible) Tj ET "
    #expect(try inspect(hidden).hasInvisibleText)
    #expect(try inspect(visible + hidden).hasInvisibleText)
    #expect(try !inspect(visible).hasInvisibleText)
    // Setting mode 3 without showing text is not invisible text.
    #expect(try !inspect("BT /F1 12 Tf 3 Tr ET " + visible).hasInvisibleText)
}

/// A chapter opener's lines in reading order: a tagged title, a display-type paragraph group of
/// `quote` lines, and the chapter's own contents entries in body type at the same left edge.
private func openerPage(quote: [String]) -> PageContent {
    var lines: [TextLine] = []
    var title = TextLine(text: "Overview of the Federal Reserve System", rect: CGRect(x: 60, y: 700, width: 380, height: 26), fontSize: 24)
    title.structure = TextStructure(group: 1, order: 1, headingLevel: 2, lineCount: 1)
    lines.append(title)
    for (i, text) in quote.enumerated() {
        var line = TextLine(text: text, rect: CGRect(x: 60, y: 650 - CGFloat(i) * 18, width: 400, height: 16), fontSize: 14)
        line.structure = TextStructure(group: 2, order: 2, headingLevel: 0, lineCount: quote.count)
        lines.append(line)
    }
    let entries = ["The U.S. Approach to Central Banking", "The Decentralized System Structure and Its Philosophy",
                   "The Reserve Banks: A Blend of Private and Governmental Characteristics"]
    for (i, text) in entries.enumerated() {
        lines.append(TextLine(text: text, rect: CGRect(x: 60, y: 300 - CGFloat(i) * 26, width: 420, height: 11), fontSize: 10))
    }
    for i in 0..<8 {
        lines.append(TextLine(text: "Body prose that sets the page's ordinary type size for the heading threshold.",
                              rect: CGRect(x: 60, y: 200 - CGFloat(i) * 13, width: 420, height: 11), fontSize: 10))
    }
    return PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines, graphics: [])
}

@Test func aTaggedPullQuoteAboveTheTextItIntroducesStaysItsParagraph() {
    let quote = ["The Federal Reserve performs five key functions", "in the public interest to promote the health of the",
                 "U.S. economy and the stability of the U.S. financial", "system."]
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: openerPage(quote: quote), images: [], vocabulary: [], warnings: &warnings)
    let paragraph = blocks.first { $0.text.hasPrefix("The Federal Reserve performs") }
    #expect(paragraph?.text == quote.joined(separator: " "))
    #expect(paragraph?.taggedLevel == 0 && paragraph?.structureGroup == 2)
    #expect(blocks.first?.taggedLevel == 2)
}

@Test(arguments: [
    ["Advisory Councils"],                                    // one line: a section title (#67)
    ["Monetary Policy Tools and", "How They Are Implemented"], // no terminal punctuation
    ["Why It Matters.", "Stability."],                         // under eight words
])
func aParagraphTagInHeadingTypeThatIsNotAPullQuoteStillHeadsTheTextBelow(_ title: [String]) {
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: openerPage(quote: title), images: [], vocabulary: [], warnings: &warnings)
    #expect(blocks.contains { block in
        if case .heading = block.content { block.taggedLevel == nil && block.text.hasPrefix(title[0]) } else { false }
    }, "\(title)")
}
