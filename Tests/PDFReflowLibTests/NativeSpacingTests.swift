import Foundation
import CoreGraphics
import Testing
@testable import PDFReflowLib

private struct SpacingSource: Decodable {
    struct TextObject: Decodable { var operators: String }
    var sourceSHA256: String
    var toUnicode: String
    var textObjects: [TextObject]
    static func load() throws -> Self {
        try JSONDecoder().decode(Self.self, from: Data(contentsOf: Bundle.module.resourceURL!
            .appendingPathComponent("fixtures/dga-1-text-operators.json")))
    }
}

private func spacingPDF(_ operators: String, map: String, subtype: String = "Type3",
                        matrix: String = "1 0 0 1 0 0", rotate: Int = 0) throws -> CGPDFDocument {
    let data = testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Rotate \(rotate) /Resources << /Font << /T3_0 5 0 R >> /XObject << /Nested 7 0 R >> >> /Contents 4 0 R >>",
        testPDFStream(operators),
        "<< /Type /Font /Subtype /\(subtype) /FontMatrix [\(matrix)] /ToUnicode 6 0 R >>",
        testPDFStream(map),
        testPDFStream("", extra: "/Type /XObject /Subtype /Form /BBox [0 0 100 100]"),
    ])
    let provider = try #require(CGDataProvider(data: data as CFData))
    return try #require(CGPDFDocument(provider))
}

@Test func sourceType3KerningRepairsOnlyTheTwoDgaLabelSpaces() throws {
    let source = try SpacingSource.load(), layout = try SourceLayoutFixture.load("dga-1")
    #expect(source.sourceSHA256 == layout.sourceSHA256)
    let document = try spacingPDF(source.textObjects.map(\.operators).joined(separator: "\n"), map: source.toUnicode)
    let evidence = NativeSpacingReader.read(try #require(document.page(at: 1)))
    #expect(evidence.count == 11)
    #expect(evidence.filter { !$0.smallGaps.isEmpty }.map { $0.text } == ["Protein, Dairy", "Vegetables"])
    let lines = layout.content().lines, bounds = lines.map(\.rect)
    for (index, line) in layout.attributedLines.enumerated() {
        let expected = ["Protein, Dair y": "Protein, Dairy", "Ve getables": "Vegetables"][line.text] ?? line.text
        let repaired = NativeSpacingReader.apply(evidence, to: line.attributedString(), bounds: bounds[index], allBounds: bounds)
        #expect(repaired.string == expected)
    }
}

private func simpleSpacingMap() -> String {
    "1 begincodespacerange <00> <FF> endcodespacerange\n95 beginbfchar\n"
        + (32...126).map { String(format: "<%02X> <%04X>", $0, $0) }.joined(separator: "\n") + "\nendbfchar"
}

private func spacingEvidence(_ show: String, prefix: String = "", suffix: String = "",
                             subtype: String = "Type3", matrix: String = "1 0 0 1 0 0", rotate: Int = 0) throws -> [NativeSpacingReader.Evidence] {
    let document = try spacingPDF(prefix + " BT /T3_0 1 Tf 18 0 0 18 40 460 Tm " + show + " ET " + suffix,
                                 map: simpleSpacingMap(), subtype: subtype, matrix: matrix, rotate: rotate)
    return NativeSpacingReader.read(try #require(document.page(at: 1)))
}

@Test func sourceSpaceAndActualWordGapsRemainIntact() throws {
    for show in ["[(Dair y)] TJ", "[(Dair)-250(y)] TJ", "[(Dair)-10.1(y)] TJ",
                 "[(Dair)0(y)] TJ", "[(Dair)5(y)] TJ", "[(Dair)-3 -3(y)] TJ",
                 "[-5(Dairy)] TJ", "(Dairy) Tj"] {
        let evidence = try spacingEvidence(show)
        #expect(evidence.first?.extraSpaces(in: "Dair y") == nil)
    }
    let evidence = try #require(spacingEvidence("[(Healthy )-5(Fats)] TJ").first)
    #expect(evidence.extraSpaces(in: "Healthy Fats") == nil)
    #expect(evidence.extraSpaces(in: "Healthy  Fats") == nil)
    #expect(try spacingEvidence("[(Dair)-5(y)] TJ").first?.extraSpaces(in: "Dair y") == [4])
}

@Test func nativeSpacingRequiresCompleteTextAndExactGapEvidence() throws {
    let evidence = try #require(spacingEvidence("[(Dair)-5(y)] TJ").first)
    for text in ["Dairy", "Dai ry", "Dair  y", "Dair\ty", "Dair y extra", "Dair x", "Dair", "dair y"] {
        #expect(evidence.extraSpaces(in: text) == nil)
    }
    for (source, native) in [("well-known", "well- known"), ("A&B", "A& B"), ("1234", "12 34")] {
        #expect(NativeSpacingReader.Evidence(origin: .zero, text: source, smallGaps: Set(0...10)).extraSpaces(in: native) == nil)
    }
}

@Test func nativeSpacingPreservesStylesAndRejectsAmbiguousGeometry() throws {
    let evidence = try spacingEvidence("[(Dair)-5(y)] TJ")
    let rect = CGRect(x: 40, y: 450, width: 100, height: 18)
    let key = NSAttributedString.Key("test-source-style")
    let original = NSMutableAttributedString(string: "Dair y")
    original.addAttribute(key, value: "emphasis", range: NSRange(location: 5, length: 1))
    let repaired = NativeSpacingReader.apply(evidence, to: original, bounds: rect, allBounds: [rect])
    #expect(repaired.string == "Dairy")
    #expect(repaired.attribute(key, at: 4, effectiveRange: nil) as? String == "emphasis")
    #expect(original.string == "Dair y")
    #expect(NativeSpacingReader.apply(evidence + evidence, to: original, bounds: rect, allBounds: [rect]).string == original.string)
    #expect(NativeSpacingReader.apply(evidence, to: original, bounds: rect, allBounds: [rect, rect]).string == original.string)
    #expect(NativeSpacingReader.apply(evidence, to: original, bounds: rect.offsetBy(dx: 100, dy: 0), allBounds: [rect]).string == original.string)
}

@Test func unsupportedSourceSpacingStateFallsBack() throws {
    let show = "[(Dair)-5(y)] TJ"
    for prefix in ["1 Tc", "1 Tw", "1 Ts", "3 Tr", "90 Tz", "/G gs", "Q", "q", "/Missing Do", "/Nested Do"] {
        #expect(try spacingEvidence(show, prefix: prefix).isEmpty)
    }
    #expect(try spacingEvidence(show + " (again) Tj").isEmpty)
    #expect(try spacingEvidence(show, subtype: "Type1").isEmpty)
    #expect(try spacingEvidence(show, matrix: "0.001 0 0 0.001 0 0").first?.text == nil)
    #expect(try spacingEvidence(show, rotate: 90).isEmpty)
    #expect(try spacingEvidence(show, prefix: "0 1 -1 0 0 0 cm").isEmpty)
    #expect(try spacingEvidence("[(Dair)-5<01>] TJ").first?.text == nil)
}

@Test func sourceSpacingBoundsWorkAndRestoresSavedFontPlacement() throws {
    let show = "[(Dair)-5(y)] TJ"
    #expect(try spacingEvidence(show, prefix: String(repeating: "/T3_0 1 Tf ", count: 256)).isEmpty)
    #expect(try spacingEvidence("[(" + String(repeating: "a", count: 4097) + ")] TJ").first?.text == nil)
    #expect(try spacingEvidence("[" + String(repeating: "(a) ", count: 4097) + "] TJ").isEmpty)
    let evidence = try spacingEvidence(show, prefix: "q 2 0 0 2 100 100 cm /T3_0 9 Tf Q 1 0 0 1 10 20 cm")
    #expect(evidence.first?.origin == CGPoint(x: 50, y: 480))
    #expect(evidence.first?.extraSpaces(in: "Dair y") == [4])
    #expect(try spacingEvidence(show, prefix: "0 Tc 0 Tw 0 Ts 0 Tr 100 Tz").first?.extraSpaces(in: "Dair y") == [4])
}

@Test func unsupportedAndMalformedCharacterMapsCannotAuthorizeRepairs() {
    let good = simpleSpacingMap()
    #expect(NativeSpacingReader.characterMap(Data(good.utf8))?[65] == "A")
    for bad in [good + " /Other usecmap", good + " 0 beginbfrange endbfrange",
                good.replacingOccurrences(of: "95 beginbfchar", with: "94 beginbfchar"),
                good.replacingOccurrences(of: "<41> <0041>", with: "<41> <00410042>"),
                good.replacingOccurrences(of: "<41> <0041>", with: "<40> <0041>"),
                good.replacingOccurrences(of: "<00> <FF>", with: "<0000> <FFFF>"),
                good.replacingOccurrences(of: "<41> <0041>", with: "<41> <D800>"),
                good + String(repeating: " ", count: 65_536)] {
        #expect(NativeSpacingReader.characterMap(Data(bad.utf8)) == nil)
    }
}
