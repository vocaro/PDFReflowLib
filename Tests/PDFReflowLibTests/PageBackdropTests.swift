import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

private let backdrop = "0.2 0.3 0.4 rg 0 0 612 792 re f "

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/182")) func onlyAFlatRectangularGroundCanBeSeparatedFromItsArtwork() throws {
    let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
    for ground in [backdrop, "0 0 m 612 0 l 612 792 l 0 792 l 0 0 l f"] {
        let graphics = GraphicsReader.read(try operatorPage(ground))
        #expect(PageBackdrop.eligible(graphics, bounds: bounds))
    }
    for ground in ["0 0 612 792 re S", "612 0 0 792 0 0 cm /Im Do",
                   "0 0 m 612 0 l 612 792 l f", "/Pattern cs /P scn 0 0 612 792 re f",
                   backdrop + "3 Tr (hidden) Tj"] {
        let graphics = GraphicsReader.read(try operatorPage(ground))
        #expect(!PageBackdrop.eligible(graphics, bounds: bounds))
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/182")) func anArrowOutsideEveryTextBoxIsDecorationButDetachedArtIsPreserved() throws {
    let stream = backdrop + "40 400 150 100 re S 200 455 m 280 455 l S "
        + "280 455 m 270 450 l 270 460 l h f 400 400 m 420 410 l 400 420 l h f"
    let graphics = GraphicsReader.read(try operatorPage(stream))
    let page = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792),
        lines: [TextLine(text: "Box label", rect: CGRect(x: 60, y: 450, width: 100, height: 12), fontSize: 12)],
        graphics: graphics.regions)
    let composed = try #require(PageBackdrop.compose(page, graphics: graphics))
    #expect(composed.graphics.count == 1)
    #expect(composed.graphics[0].contains(CGPoint(x: 410, y: 410)))
    #expect(!composed.graphics[0].contains(CGPoint(x: 280, y: 455)))
    let polygon: [CGPoint] = [.init(x: 0, y: 4), .init(x: 20, y: 4), .init(x: 20, y: 0),
        .init(x: 30, y: 6), .init(x: 20, y: 12), .init(x: 20, y: 8), .init(x: 0, y: 8)]
    #expect(PageBackdrop.isArrowPolygon(polygon))
    #expect(!PageBackdrop.isArrowPolygon(Array(polygon.prefix(6))))
}

private func paddedIconPDF(opaque: Bool = false, maskExtra: String = "", clip: Bool = false) -> Data {
    func stream(_ data: Data, _ extra: String = "") -> Data {
        Data("<< /Length \(data.count) \(extra) >>\nstream\n".utf8) + data + Data("\nendstream".utf8)
    }
    let samples = (0..<100).map { offset -> UInt8 in
        opaque || ((2...7).contains(offset / 10) && (1...8).contains(offset % 10)) ? 255 : 0
    }
    let paint = backdrop + (clip ? "60 230 80 50 re W n " : "")
        + "q 80 0 0 80 60 200 cm /Im Do Q BT /F 14 Tf 60 198 Td (Cumulus) Tj ET"
    let objects: [Data] = [
        Data("<< /Type /Catalog /Pages 2 0 R >>".utf8),
        Data("<< /Type /Pages /Kids [3 0 R] /Count 1 >>".utf8),
        Data("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /XObject << /Im 5 0 R >> /Font << /F 7 0 R >> >> /Contents 4 0 R >>".utf8),
        stream(Data(paint.utf8)),
        stream(Data(repeating: 0, count: 100), "/Type /XObject /Subtype /Image /Width 10 /Height 10 /BitsPerComponent 8 /ColorSpace /DeviceGray /SMask 6 0 R"),
        stream(Data(samples), "/Type /XObject /Subtype /Image /Width 10 /Height 10 /BitsPerComponent 8 /ColorSpace /DeviceGray \(maskExtra)"),
        Data("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>".utf8)]
    var data = Data("%PDF-1.7\n".utf8), offsets = [0]
    for (index, object) in objects.enumerated() {
        offsets.append(data.count); data += Data("\(index + 1) 0 obj\n".utf8) + object + Data("\nendobj\n".utf8)
    }
    let xref = data.count
    data += Data("xref\n0 \(offsets.count)\n0000000000 65535 f \n".utf8)
    for offset in offsets.dropFirst() { data += Data(String(format: "%010d 00000 n \n", offset).utf8) }
    data += Data("trailer\n<< /Size \(offsets.count) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n".utf8)
    return data
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/182")) func aPaddedSoftMaskIsTrimmedBeforeGraphicsAreClustered() throws {
    for (opaque, extra, clip, expected) in [
        (false, "", false, CGRect(x: 68, y: 216, width: 64, height: 48)),
        (true, "", false, CGRect(x: 60, y: 200, width: 80, height: 80)),
        (false, "/Decode [0 1]", false, CGRect(x: 60, y: 200, width: 80, height: 80)),
        (false, "", true, CGRect(x: 68, y: 230, width: 64, height: 34))] {
        let data = paddedIconPDF(opaque: opaque, maskExtra: extra, clip: clip)
        let provider = try #require(CGDataProvider(data: data as CFData))
        let doc = try #require(CGPDFDocument(provider))
        let page = try #require(doc.page(at: 1))
        let graphics = GraphicsReader.read(page) { _, dictionary in ImageAlphaBounds.read(dictionary) }
        #expect(graphics.images == [expected])
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/182")) func isolatedMaskDecodingReleasesTheNativeLabelFromItsPadding() throws {
    let directory = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("padded.pdf")
    try paddedIconPDF().write(to: url)
    let document = try PDFPageSource(url: url)
    let extracted = try PageReader.read(pageIndex: 0, from: document, limit: 1000,
                                       options: ConversionOptions(), structure: nil)
    let label = try #require(extracted.content.lines.first { $0.text == "Cumulus" })
    let crops = LayoutReconstructor.graphicsWithLabels(extracted.content)
    #expect(LayoutReconstructor.takes(CGRect(x: 60, y: 200, width: 80, height: 80), label))
    #expect(!crops.contains { LayoutReconstructor.takes($0, label) })
    #expect(extracted.content.pictures == [CGRect(x: 68, y: 216, width: 64, height: 48)])
    #expect(!extracted.content.graphics.contains { PageDiagnosis.coversPage($0, bounds: extracted.content.bounds) })
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/182")) func earthdataCloudPaddingReleasesCumulusOnARealBackdropPage() throws {
    struct Capture: Decodable {
        var sourceSHA256: String
        var original: PageContent
        var rawPaints: [GraphicsReader.Paint]
        var trimmedPaints: [GraphicsReader.Paint]
        var trimmedPictures: [CGRect]
    }
    let fixture = try JSONDecoder().decode(Capture.self,
        from: Data(contentsOf: fixtureURL("earthdata-12-backdrop.json")))
    #expect(fixture.sourceSHA256 == "f0a1ea3f5711228a9de2544fd1a94b05cfb8d9323fe3a4c253542f5a6ead5c94")
    let label = try #require(fixture.original.lines.first { $0.text == "Cumulus" })
    func compose(_ paints: [GraphicsReader.Paint], pictures: [CGRect]) throws -> PageContent {
        let graphics = GraphicsReader.Result(regions: fixture.original.graphics, unsupported: false,
            images: pictures, visibleText: true, paints: paints)
        return try #require(PageBackdrop.compose(fixture.original, graphics: graphics))
    }
    let before = try compose(fixture.rawPaints, pictures: fixture.original.pictures)
    let after = try compose(fixture.trimmedPaints, pictures: fixture.trimmedPictures)
    #expect(LayoutReconstructor.graphicsWithLabels(before).contains { LayoutReconstructor.takes($0, label) })
    #expect(!LayoutReconstructor.graphicsWithLabels(after).contains { LayoutReconstructor.takes($0, label) })
    #expect(after.graphics.count == 6)
    #expect(!after.graphics.contains { PageDiagnosis.coversPage($0, bounds: after.bounds) })
    // The unclustered before/after capture exposes the actual padding; the old full-page
    // cluster would hide it and make this comparison vacuous.
    #expect(fixture.original.graphics == [fixture.original.bounds])
}
