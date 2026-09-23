import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/295"), arguments: [21, 30, 50, 100])
func invisibleWarrenWordBoxesKeepSourceWordBoundaries(page: Int) throws {
    let source = try SpacingSourceFixture.load("warren-\(page)")
    let layout = try SourceLayoutFixture.load("warren-\(page)")
    #expect(source.sourceSHA256 == layout.sourceSHA256)
    let document = try source.document()
    let reference = try #require(document.page(at: 1))
    // The visible-font reader must still refuse this invisible transcription.
    #expect(NativeSpacingReader.read(reference).isEmpty)
    let evidence = NativeSpacingReader.readInvisible(reference)
    #expect(!evidence.isEmpty)
    let lines = layout.content().lines, bounds = lines.map(\.rect)
    let repaired = lines.enumerated().map { index, line in
        NativeSpacingReader.restoringInvisibleSpaces(line.text, evidence: evidence,
                                                     bounds: line.rect, allBounds: bounds)
    }.joined(separator: " ")
    let phrases = [21: ["Chapter I. SUMMARY AND CONCLUSIONS"],
                   30: ["two on each running board", "was approved by the local host committee", "\\Yhite House representa-"],
                   50: ["identify himself with various political groups", "the contacts which he initiated", "one must look to the assassin"],
                   100: ["Persons who were not railroad employees"]]
    for phrase in phrases[page] ?? [] { #expect(repaired.contains(phrase), "Missing \(phrase) in \(repaired)") }
    // These corrections insert spaces only: every inherited character remains in order.
    #expect(repaired.filter { !$0.isWhitespace } == lines.map(\.text).joined().filter { !$0.isWhitespace })
}

@Test func invisibleWordSpacesRequireOwnedTextAndPositiveWordGaps() {
    let bounds = CGRect(x: 0, y: 0, width: 200, height: 20)
    func repair(_ native: String = "twoon", gap: CGFloat = 2, end: CGFloat? = 30,
                y: CGFloat = 10, allBounds: [CGRect]? = nil) -> String {
        let shows = [NativeSpacingReader.Evidence(origin: CGPoint(x: 0, y: 10), unicode: "two", end: end, size: 10),
                     NativeSpacingReader.Evidence(origin: CGPoint(x: 30 + gap, y: y), unicode: "on", end: 50, size: 10)]
        return NativeSpacingReader.restoringInvisibleSpaces(native, evidence: shows, bounds: bounds,
                                                            allBounds: allBounds ?? [bounds])
    }
    #expect(repair() == "two on")
    #expect(repair("two on") == "two on")
    #expect(repair("twoone") == "twoone")
    #expect(repair("twxon") == "twxon")
    #expect(repair(gap: 1) == "twoon")
    #expect(repair(gap: 0) == "twoon")
    #expect(repair(gap: -1) == "twoon")
    #expect(repair(end: nil) == "twoon")
    #expect(repair(y: 15) == "twoon")
    #expect(repair(allBounds: [bounds, bounds]) == "twoon")
    let ideographs = [NativeSpacingReader.Evidence(origin: CGPoint(x: 0, y: 10), unicode: "文", end: 10, size: 10),
                      NativeSpacingReader.Evidence(origin: CGPoint(x: 20, y: 10), unicode: "字", end: 30, size: 10)]
    #expect(NativeSpacingReader.restoringInvisibleSpaces("文字", evidence: ideographs,
                                                        bounds: bounds, allBounds: [bounds]) == "文字")
}

@Test func invisibleWordSpacingRefusesVisibleOrUnmodeledTextAndRestoresRenderState() throws {
    var source = try SpacingSourceFixture.load("warren-30")
    let original = source.content
    for mode in ["0 Tr", "4 Tr"] {
        source.content = original.replacingOccurrences(of: "3 Tr", with: mode)
        let document = try source.document()
        #expect(NativeSpacingReader.readInvisible(try #require(document.page(at: 1))).isEmpty)
    }
    source.content = original.replacingOccurrences(of: "3 Tr", with: "3 Tr q 0 Tr Q")
    let document = try source.document()
    #expect(!NativeSpacingReader.readInvisible(try #require(document.page(at: 1))).isEmpty)
    source.fonts["F1"]?.baseFont = "UnknownFont"
    let unknown = try source.document()
    let evidence = NativeSpacingReader.readInvisible(try #require(unknown.page(at: 1)))
    #expect(evidence.allSatisfy { $0.end == nil })
}

@Test func invisibleWordRepairIgnoresTheScansAttachmentSelection() throws {
    // The source producer's one-word-per-show shape, with a page-sized image that PDFKit
    // includes as its own attachment selection. That selection cannot own text anchors.
    let data = testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 300] /Resources << /XObject << /Im 5 0 R >> /Font << /F1 6 0 R >> >> /Contents 4 0 R >>",
        testPDFStream("q 300 0 0 300 0 0 cm /Im Do Q 3 Tr /F1 10 Tf BT 1 0 0 1 20 240 Tm (two) Tj ET /F1 9.5 Tf BT 1 0 0 1 40.8 240 Tm (on) Tj ET"),
        testPDFStream("FFFFFF>", extra: "/Type /XObject /Subtype /Image /Width 1 /Height 1 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /ASCIIHexDecode"),
        "<< /Type /Font /Subtype /Type1 /BaseFont /Courier /Encoding /WinAnsiEncoding >>",
    ])
    let document = try #require(PDFDocument(data: data)), page = try #require(document.page(at: 0))
    let before = try NativeTextReader.lines(on: page, limit: 10000, includeStyle: false)
    #expect(before.map(\.text) == ["twoon"])
    let after = try NativeTextReader.lines(on: page, limit: 10000, includeStyle: false, preserveInvisibleWordGaps: true)
    #expect(after.map(\.text) == ["two on"])
    #expect(after.allSatisfy { !$0.monospaced })
}
