import Foundation
import CoreText
import PDFKit
import Testing
import ZIPFoundation
@testable import PDFReflowLib

@Test(arguments: [false, true])
func explicitBaselineOffsetsPreserveScriptWithoutGuessingFromSmallFonts(useFoundationKey: Bool) {
    let value = NSMutableAttributedString(string: "")
    for (text, offset, size) in [("base", 0.0, 12.0), ("small", 0, 8), ("raised", 4, 12),
                                ("lowered", -3, 8), ("noise", 0.1, 12)] {
        value.append(NSAttributedString(string: text, attributes: [
            .font: pdfKitGated { PlatformFont(name: "Helvetica-BoldOblique", size: size) }!,
            (useFoundationKey ? .baselineOffset : NSAttributedString.Key(kCTBaselineOffsetAttributeName as String)): offset,
        ]))
    }
    let model = NativeTextReader.inlineText(from: value)
    #expect(model.text == "basesmallraisedlowerednoise")
    let html = EPUBTextEncoder.inline(model)
    #expect(html.contains("<sup><strong><em>raised</em></strong></sup>"))
    #expect(html.contains("<sub><strong><em>lowered</em></strong></sub>"))
    #expect(!html.contains("<sup><strong><em>small"))
    #expect(!html.contains("<sup><strong><em>noise"))
}

@Test func nativeRaisedAndLoweredGlyphsReachTheEPUBAsSelectableText() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let pdf = dir.appendingPathComponent("source.pdf"), epub = dir.appendingPathComponent("book.epub")
    try testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 300] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
        testPDFStream("BT /F1 12 Tf 40 240 Td (Read ax) Tj /F1 8 Tf 4 Ts (2) Tj /F1 12 Tf 0 Ts ( and H) Tj /F1 8 Tf -3 Ts (2) Tj /F1 12 Tf 0 Ts (O carefully.) Tj ET"),
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]).write(to: pdf)
    let report = try await PDFConverter().convert(from: pdf, to: epub)
    #expect(report.imageCount == 0 && report.reflowedPageCount == 1)
    let html = try Archive(url: epub, accessMode: .read).chapter()
    #expect(html.contains("ax<sup>2</sup>"))
    #expect(html.contains("H<sub>2</sub>O"))
    #expect(html.contains("carefully."))
}

@Test func comicOCRLineSpacingIsNotAnInlineScript() throws {
    let source = try SourceLayoutFixture.load("cdc-5")
    let line = try #require(source.attributedLines.first)
    let model = NativeTextReader.inlineText(from: line.attributedString())
    #expect(model.text == line.text)
    let html = EPUBTextEncoder.inline(model)
    #expect(!html.contains("<sup>"))
    #expect(!html.contains("<sub>"))
}
