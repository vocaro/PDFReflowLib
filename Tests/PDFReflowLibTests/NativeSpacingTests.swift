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
    for prefix in ["1 Tc", "1 Tw", "1 Ts", "3 Tr", "90 Tz", "/G gs", "Q", "q", "/Missing Do"] {
        #expect(try spacingEvidence(show, prefix: prefix).isEmpty)
    }
    // A Form XObject is opaque: its text is neither evidence nor a contradiction, so the
    // page's own shows keep their evidence (#43); a Form drawn inside a text object is not.
    #expect(try spacingEvidence(show, prefix: "/Nested Do").first?.extraSpaces(in: "Dair y") == [4])
    #expect(try spacingEvidence(show, prefix: "BT /Nested Do ET").isEmpty)
    #expect(try spacingEvidence(show + " (again) Tj").isEmpty)
    #expect(try spacingEvidence(show, subtype: "Type1").isEmpty)
    #expect(try spacingEvidence(show, matrix: "0.001 0 0 0.001 0 0").first?.text == nil)
    #expect(try spacingEvidence(show, rotate: 90).isEmpty)
    #expect(try spacingEvidence(show, prefix: "0 1 -1 0 0 0 cm").isEmpty)
    #expect(try spacingEvidence("[(Dair)-5<01>] TJ").first?.text == nil)
}

@Test func sourceSpacingBoundsWorkAndRestoresSavedFontPlacement() throws {
    let show = "[(Dair)-5(y)] TJ"
    // TeX reselects fonts at every symbol, so the selection bound is generous; it still exists.
    #expect(try spacingEvidence(show, prefix: String(repeating: "/T3_0 1 Tf ", count: 9_999)).first?.extraSpaces(in: "Dair y") == [4])
    #expect(try spacingEvidence(show, prefix: String(repeating: "/T3_0 1 Tf ", count: 10_000)).isEmpty)
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

// MARK: - Word boundaries hidden at font changes (#43)

private struct BoundarySource: Decodable {
    struct Font: Decodable {
        var resourceName: String
        var subtype: String
        var firstChar: Int?
        var widths: [Double]?
        var toUnicode: String?
    }
    struct TextObject: Decodable { var operators: String }
    var sourceSHA256: String
    var fonts: [String: Font]
    var textObjects: [TextObject]
    static func load() throws -> Self {
        try JSONDecoder().decode(Self.self, from: Data(contentsOf: Bundle.module.resourceURL!
            .appendingPathComponent("fixtures/replay-1-text-operators.json")))
    }
}

private func simpleUnicodeMap() -> String { "begincmap\n" + simpleSpacingMap() + "\nendcmap" }

private struct BoundaryFont {
    var name: String
    var firstChar: Int? = 32
    var widths: [Double]? = Array(repeating: 500, count: 95)
    var map: String? = simpleUnicodeMap()
    /// An inline `/Encoding` value (a name or a dictionary), written verbatim.
    var encoding: String?
    var subtype = "Type1"
}

/// A page whose fonts are simple Type1 dictionaries with Widths and ToUnicode streams, and
/// optionally inline ExtGState dictionaries (`/Name << ... >>` entries).
private func boundaryPDF(fonts: [BoundaryFont], operators: String, extGState: String? = nil) throws -> CGPDFDocument {
    var objects = ["<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>", "",
                   testPDFStream(operators)]
    var resources: [String] = []
    for font in fonts {
        let index = objects.count + 1
        var dictionary = "<< /Type /Font /Subtype /\(font.subtype) /BaseFont /\(font.name)"
        if let encoding = font.encoding { dictionary += " /Encoding \(encoding)" }
        if let firstChar = font.firstChar, let widths = font.widths {
            dictionary += " /FirstChar \(firstChar) /LastChar \(firstChar + widths.count - 1) /Widths ["
                + widths.map { String(format: "%g", $0) }.joined(separator: " ") + "]"
        }
        if font.map != nil { dictionary += " /ToUnicode \(index + 1) 0 R" }
        objects.append(dictionary + " >>")
        if let map = font.map { objects.append(testPDFStream(map)) }
        resources.append("/\(font.name) \(index) 0 R")
    }
    objects[2] = "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << "
        + resources.joined(separator: " ") + " >>" + (extGState.map { " /ExtGState << \($0) >>" } ?? "")
        + " >> /Contents 4 0 R >>"
    let provider = try #require(CGDataProvider(data: testPDF(objects: objects) as CFData))
    return try #require(CGPDFDocument(provider))
}

private func boundaryEvidence(_ operators: String, fonts: [BoundaryFont] = [BoundaryFont(name: "Fa"), BoundaryFont(name: "Fb")],
                              extGState: String? = nil) throws -> [NativeSpacingReader.Evidence] {
    let document = try boundaryPDF(fonts: fonts, operators: operators, extGState: extGState)
    return NativeSpacingReader.read(try #require(document.page(at: 1)))
}

private let boundaryRect = CGRect(x: 40, y: 690, width: 120, height: 14)

private func repairedBoundary(_ evidence: [NativeSpacingReader.Evidence], _ native: String) -> String {
    NativeSpacingReader.apply(evidence, to: NSAttributedString(string: native), bounds: boundaryRect, allBounds: [boundaryRect]).string
}

@Test func sourceFontBoundariesRestoreReplayClocksWordSpaces() throws {
    let source = try BoundarySource.load(), layout = try SourceLayoutFixture.load("replay-1")
    #expect(source.sourceSHA256 == layout.sourceSHA256)
    let fonts = source.fonts.values.sorted { $0.resourceName < $1.resourceName }.map {
        BoundaryFont(name: $0.resourceName, firstChar: $0.firstChar, widths: $0.widths, map: $0.toUnicode)
    }
    let document = try boundaryPDF(fonts: fonts, operators: source.textObjects.map(\.operators).joined(separator: "\n"))
    let evidence = NativeSpacingReader.read(try #require(document.page(at: 1)))
    // Every upright show on the page is decoded and measured; the rotated arXiv stamp yields
    // no evidence and does not disqualify the page.
    #expect(evidence.count == 187)
    #expect(evidence.allSatisfy { $0.unicode != nil && $0.end != nil })
    #expect(evidence.allSatisfy { $0.text == nil })
    // Reviewed against the rendered page and Poppler's text layer: the only changes are the
    // word spaces after mathematical variables set in the LibertineMathMI font.
    let expected = [
        "a distributed computation. Specifically, if event 𝑒must occur before":
            "a distributed computation. Specifically, if event 𝑒 must occur before",
        "As an illustration, consider two drones 𝐴and 𝐵that are cooper-":
            "As an illustration, consider two drones 𝐴 and 𝐵 that are cooper-",
        "all these checks during the execution would require that 𝐴and 𝐵":
            "all these checks during the execution would require that 𝐴 and 𝐵",
        "processes often differ. Hence, it is possible that drone 𝐴may send a":
            "processes often differ. Hence, it is possible that drone 𝐴 may send a",
        "message at time 50 (local time of 𝐴) but it is received by 𝐵at time":
            "message at time 50 (local time of 𝐴) but it is received by 𝐵 at time",
        "introduce two concerns: Their size of 𝑂(𝑛), where 𝑛is the number":
            "introduce two concerns: Their size of 𝑂(𝑛), where 𝑛 is the number",
        "external observer will know that the action of 𝐴occurred before 𝐵.":
            "external observer will know that the action of 𝐴 occurred before 𝐵.",
        "However, if 𝐴and 𝐵did not communicate then the corresponding":
            "However, if 𝐴 and 𝐵 did not communicate then the corresponding",
    ]
    let bounds = try layout.attributedLines.map { line -> CGRect in
        let values = try #require(line.rect)
        return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }
    var repaired: [String: String] = [:]
    for (index, line) in layout.attributedLines.enumerated() {
        let result = NativeSpacingReader.apply(evidence, to: line.attributedString(), bounds: bounds[index], allBounds: bounds)
        if result.string != line.text { repaired[line.text] = result.string }
    }
    #expect(repaired == expected)
    // The stamp line itself is untouched, as is a line whose spaces PDFKit already synthesized.
    #expect(repaired["arXiv:2311.07842v1 [cs.DC] 14 Nov 2023"] == nil)
    #expect(repaired["𝑓 then the replay clock must ensure that 𝑒 is replayed before 𝑓."] == nil)
}

@Test func fontChangeGapRestoresWordSpaceOnlyBetweenWords() throws {
    // 10-point fonts with 500-unit advances: "event" ends at 65, the variable at 68 (0.3 em
    // later) ends at 73, and "must" starts at 76.
    let ops = "BT /Fa 10 Tf 1 0 0 1 40 700 Tm (event) Tj /Fb 10 Tf 1 0 0 1 68 700 Tm (e) Tj /Fa 10 Tf 1 0 0 1 76 700 Tm (must) Tj ET"
    let evidence = try boundaryEvidence(ops)
    #expect(evidence.map(\.end) == [65, 73, 96])
    #expect(evidence.map(\.unicode) == ["event", "e", "must"])
    #expect(evidence.map(\.size) == [10, 10, 10])
    #expect(evidence[0].font == evidence[2].font, "one font dictionary keeps one identity")
    #expect(evidence[0].font != evidence[1].font)
    #expect(repairedBoundary(evidence, "event emust") == "event e must")
    #expect(repairedBoundary(evidence, "eventemust") == "event e must")
    #expect(repairedBoundary(evidence, "event e must") == "event e must")
    #expect(repairedBoundary(evidence, "event e must\n") == "event e must\n")
    // Any mismatch beyond PDFKit's own spaces leaves the line alone.
    for native in ["event xmust", "event emus", "event emust extra", "Event emust"] {
        #expect(repairedBoundary(evidence, native) == native)
    }
    // Tm scaling (pdfTeX font expansion) scales advances and the em used for the threshold.
    let scaled = try boundaryEvidence(ops.replacingOccurrences(of: "1 0 0 1 40 700 Tm", with: "0.9 0 0 1 40 700 Tm"))
    #expect(scaled.map(\.end) == [62.5, 73, 96])
    #expect(scaled.map(\.size) == [9, 10, 10])
    #expect(repairedBoundary(scaled, "event emust") == "event e must")
}

@Test func fontChangeGapsBelowWordSizeOrOutsideWordsStayJoined() throws {
    func ops(second: String = "/Fb 10 Tf 1 0 0 1 68 700 Tm (e) Tj", third: String = "/Fa 10 Tf 1 0 0 1 76 700 Tm (must) Tj") -> String {
        "BT /Fa 10 Tf 1 0 0 1 40 700 Tm (event) Tj \(second) \(third) ET"
    }
    // 0.14 em is a kern or italic correction; 0.15 em is the shrunk glue of a justified line.
    #expect(repairedBoundary(try boundaryEvidence(ops(third: "/Fa 10 Tf 1 0 0 1 74.4 700 Tm (must) Tj")), "event emust") == "event emust")
    #expect(repairedBoundary(try boundaryEvidence(ops(third: "/Fa 10 Tf 1 0 0 1 74.5 700 Tm (must) Tj")), "event emust") == "event e must")
    // The same font on both sides is PDFKit's ordinary spacing, outside this rule.
    #expect(repairedBoundary(try boundaryEvidence(ops(second: "/Fa 10 Tf 1 0 0 1 68 700 Tm (e) Tj")), "event emust") == "event emust")
    // Punctuation beside the gap is not a word boundary; a raised show is not on the baseline.
    #expect(repairedBoundary(try boundaryEvidence(ops(third: "/Fa 10 Tf 1 0 0 1 76 700 Tm (.) Tj")), "event e.") == "event e.")
    #expect(repairedBoundary(try boundaryEvidence(ops(second: "/Fb 10 Tf 1 0 0 1 68 700 Tm (,) Tj")), "event ,must") == "event ,must")
    #expect(repairedBoundary(try boundaryEvidence(ops(second: "/Fb 10 Tf 1 0 0 1 68 704 Tm (e) Tj")), "event emust") == "event emust")
    // A TJ adjustment inside a show moves its end; a word-size adjustment is still measured.
    let adjusted = try boundaryEvidence(ops(second: "/Fb 10 Tf 1 0 0 1 68 700 Tm [(e)-300(f)] TJ"))
    #expect(adjusted[1].end == 81)
    #expect(repairedBoundary(adjusted, "event e fmust") == "event e fmust")
    // Without Widths the advance is unknown, so only the boundary before the show is measured.
    let partial = try boundaryEvidence(ops(), fonts: [BoundaryFont(name: "Fa"), BoundaryFont(name: "Fb", widths: nil)])
    #expect(partial.map(\.end) == [65, nil, 96])
    #expect(repairedBoundary(partial, "eventemust") == "event emust")
    // Without a ToUnicode map the show is not decoded and the line cannot be matched.
    let unmapped = try boundaryEvidence(ops(), fonts: [BoundaryFont(name: "Fa"), BoundaryFont(name: "Fb", map: nil)])
    #expect(unmapped.map(\.unicode) == ["event", nil, "must"])
    #expect(repairedBoundary(unmapped, "event emust") == "event emust")
}

@Test func rotatedShowsAndFormsLeaveUprightEvidenceIntact() throws {
    let upright = "BT /Fa 10 Tf 1 0 0 1 40 700 Tm (event) Tj /Fb 10 Tf 1 0 0 1 68 700 Tm (e) Tj /Fa 10 Tf 1 0 0 1 76 700 Tm (must) Tj ET"
    let stamp = "q 0 1 -1 0 30 200 cm BT /Fa 20 Tf 1 0 0 1 0 0 Tm (arXiv stamp) Tj ET Q "
    let evidence = try boundaryEvidence(stamp + upright)
    #expect(evidence.count == 3)
    #expect(repairedBoundary(evidence, "event emust") == "event e must")
    // Two shows in one line rectangle that also lie inside another rectangle are ambiguous.
    let overlapping = CGRect(x: 40, y: 695, width: 120, height: 14)
    #expect(NativeSpacingReader.apply(evidence, to: NSAttributedString(string: "event emust"), bounds: boundaryRect,
                                      allBounds: [boundaryRect, overlapping]).string == "event emust")
    // Unsupported text state still disqualifies the page for insertion as it does for removal.
    for prefix in ["1 Tc ", "1 Tw ", "90 Tz ", "/G gs "] {
        #expect(try boundaryEvidence(prefix + upright).isEmpty)
    }
}

@Test func generalUnicodeMapsDecodeRangesLigaturesAndSurrogatesOrFallBack() {
    let map = """
    /CIDInit /ProcSet findresource begin begincmap
    1 begincodespacerange <00> <FF> endcodespacerange
    2 beginbfrange
    <16> <17> <D835DC34>
    <20> <21> [<0041> <00420043>]
    endbfrange
    2 beginbfchar
    <1B> <00660069>
    <41> <0041>
    endbfchar
    endcmap
    """
    let decoded = NativeSpacingReader.unicodeMap(Data(map.utf8))
    #expect(decoded?[0x16] == "𝐴")
    #expect(decoded?[0x17] == "𝐵")
    #expect(decoded?[0x20] == "A")
    #expect(decoded?[0x21] == "BC")
    #expect(decoded?[0x1B] == "fi")
    #expect(decoded?[0x41] == "A")
    #expect(decoded?.count == 6)
    #expect(NativeSpacingReader.unicodeMap(Data(simpleSpacingMap().utf8)) == nil, "a bare map without begincmap is not a CMap")
    for bad in [map + " /Other usecmap", map.replacingOccurrences(of: "<00> <FF>", with: "<0000> <FFFF>"),
                map.replacingOccurrences(of: "<41> <0041>", with: "<16> <0041>"),
                map.replacingOccurrences(of: "<41> <0041>", with: "<41> <004>"),
                map.replacingOccurrences(of: "<41> <0041>", with: "<41> <D800>"),
                map.replacingOccurrences(of: "<16> <17>", with: "<17> <16>"),
                map.replacingOccurrences(of: "2 beginbfchar", with: "1 beginbfchar"),
                map.replacingOccurrences(of: "[<0041> <00420043>]", with: "[<0041>]"),
                map + String(repeating: " ", count: 65_536)] {
        #expect(NativeSpacingReader.unicodeMap(Data(bad.utf8)) == nil)
    }
}

// MARK: - Adobe one-byte maps under a two-byte codespace (#104)

/// A simple-font ToUnicode map as Adobe PDF Library writes it (FAA, DGA, Fed): the one-byte entries
/// of `simpleSpacingMap()` under a two-byte `<0000> <FFFF>` codespace.
private func adobeUnicodeMap(_ entries: String = simpleSpacingMap()) -> String {
    "/CIDInit /ProcSet findresource begin 12 dict begin begincmap\n/CMapName /Adobe-Identity-UCS def /CMapType 2 def\n"
        + entries.replacingOccurrences(of: "1 begincodespacerange <00> <FF> endcodespacerange",
                                       with: "1 begincodespacerange\n<0000> <FFFF>\nendcodespacerange")
        + "\nendcmap CMapName currentdict /CMap defineresource pop end end"
}

@Test func adobeOneByteMapsUnderATwoByteCodespaceSupplyWordBoundaryEvidence() throws {
    let ops = "BT /Fa 10 Tf 1 0 0 1 40 700 Tm (event) Tj /Fb 10 Tf 1 0 0 1 68 700 Tm (e) Tj /Fa 10 Tf 1 0 0 1 76 700 Tm (must) Tj ET"
    let adobeFonts = [BoundaryFont(name: "Fa", map: adobeUnicodeMap()), BoundaryFont(name: "Fb", map: adobeUnicodeMap())]
    let adobe = try boundaryEvidence(ops, fonts: adobeFonts)
    #expect(adobe.map(\.unicode) == ["event", "e", "must"])
    #expect(adobe.map(\.end) == [65, 73, 96])
    #expect(repairedBoundary(adobe, "event emust") == "event e must")
    // Either font may use either form; the evidence is the same as for a one-byte codespace.
    let mixed = try boundaryEvidence(ops, fonts: [BoundaryFont(name: "Fa"), BoundaryFont(name: "Fb", map: adobeUnicodeMap())])
    #expect(mixed.map(\.unicode) == ["event", "e", "must"])
    #expect(repairedBoundary(mixed, "event emust") == "event e must")
    // The gap rule is unchanged: a 0.14 em gap stays joined under the Adobe form.
    let kern = try boundaryEvidence(ops.replacingOccurrences(of: "76 700 Tm", with: "74.4 700 Tm"), fonts: adobeFonts)
    #expect(repairedBoundary(kern, "event emust") == "event emust")
    // A map this reading still rejects leaves its shows undecoded, so the line is not matched.
    let twoByte = adobeUnicodeMap().replacingOccurrences(of: "<65> <0065>", with: "<0065> <0065>")
    let rejected = try boundaryEvidence(ops, fonts: [BoundaryFont(name: "Fa"), BoundaryFont(name: "Fb", map: twoByte)])
    #expect(rejected.map(\.unicode) == ["event", nil, "must"])
    #expect(repairedBoundary(rejected, "event emust") == "event emust")
}

@Test func onlyTheAdobeCodespaceIsReadAsOneByteAndOnlyForSimpleFonts() throws {
    let oneByte = "begincmap\n" + simpleSpacingMap() + "\nendcmap"
    let expected = try #require(NativeSpacingReader.unicodeMap(Data(oneByte.utf8)))
    #expect(NativeSpacingReader.simpleFontUnicodeMap(Data(adobeUnicodeMap().utf8)) == expected)
    #expect(NativeSpacingReader.simpleFontUnicodeMap(Data(oneByte.utf8)) == expected)
    // The general parser itself still refuses a two-byte codespace.
    #expect(NativeSpacingReader.unicodeMap(Data(adobeUnicodeMap().utf8)) == nil)
    let adobe = adobeUnicodeMap()
    for bad in [
        // FAA's mixed maps: one-byte entries plus a two-byte `<0020>` entry.
        adobe.replacingOccurrences(of: "<20> <0020>", with: "<0020> <0020>"),
        // Loper Bright's and three Fed maps: a symbol-font codespace in two ranges.
        adobe.replacingOccurrences(of: "1 begincodespacerange\n<0000> <FFFF>", with: "2 begincodespacerange\n<00> <EF> <F000> <FFFF>"),
        // Any other two-byte codespace, a second codespace block, an inherited map, an oversized stream.
        adobe.replacingOccurrences(of: "<0000> <FFFF>", with: "<0000> <00FF>"),
        adobe.replacingOccurrences(of: "\nendcmap", with: "\n1 begincodespacerange <00> <FF> endcodespacerange\nendcmap"),
        adobe + " /Other usecmap",
        adobe + String(repeating: " ", count: 65_536),
    ] {
        #expect(NativeSpacingReader.simpleFontUnicodeMap(Data(bad.utf8)) == nil)
    }
    // Type3 space removal keeps its own explicit one-byte bfchar map: the Adobe form authorizes nothing.
    let show = " BT /T3_0 1 Tf 18 0 0 18 40 460 Tm [(Dair)-5.6(y)] TJ ET "
    let type3 = NativeSpacingReader.read(try #require(try spacingPDF(show, map: simpleSpacingMap()).page(at: 1)))
    #expect(type3.map(\.text) == ["Dairy"])
    let adobeType3 = NativeSpacingReader.read(try #require(try spacingPDF(show, map: adobeUnicodeMap()).page(at: 1)))
    #expect(adobeType3.count == 1)
    #expect(adobeType3.first?.text == nil)
}

// MARK: - Wallace: WinAnsi-encoded Type1 fonts, `gs` without a font, trailing TJ adjustments (#110)

/// Ghostscript's TeX output (Wallace): Type1 fonts with Widths and a WinAnsi encoding, no ToUnicode.
private func wallaceFont(_ name: String, encoding: String = "<< /Type /Encoding /BaseEncoding /WinAnsiEncoding /Differences [ 126 /tilde ] >>") -> BoundaryFont {
    BoundaryFont(name: name, map: nil, encoding: encoding)
}

@Test func wallaceDigitBeforeTextFontRestoresItsWordSpaceAndMathStaysJoined() throws {
    let fonts = [wallaceFont("R35"), wallaceFont("R46", encoding: "/WinAnsiEncoding"), wallaceFont("R44")]
    let states = "/R7 << /Type /ExtGState /OPM 1 >>"
    // Wallace page 29, `Subtract 7 from both sides`: the digit is a CMR12 show that Ghostscript
    // ends with a trailing adjustment, `[(7)178.413]TJ`; the text resumes 0.16 em after the digit's
    // advance, in the EC text font. Every page sets `/R7 gs` first. 10-point fonts, 500-unit advances.
    let reproducer = "/R7 gs BT /R35 10 Tf 1 0 0 1 40 700 Tm (Subtract) Tj /R46 10 Tf 1 0 0 1 82 700 Tm [(7)178.413] TJ /R35 10 Tf 1 0 0 1 88.6 700 Tm (from) Tj ET"
    let evidence = try boundaryEvidence(reproducer, fonts: fonts, extGState: states)
    #expect(evidence.map(\.unicode) == ["Subtract", "7", "from"])
    func close(_ ends: [CGFloat?], _ expected: [CGFloat]) -> Bool {
        ends.count == expected.count && zip(ends, expected).allSatisfy { end, value in end.map { abs($0 - value) < 0.001 } ?? false }
    }
    #expect(close(evidence.map(\.end), [80, 87, 108.6]), "the trailing adjustment moves no glyph of its show")
    #expect(repairedBoundary(evidence, "Subtract 7from") == "Subtract 7 from")
    // Wallace page 24, `− 5y`: the coefficient ends with the same kind of adjustment and the CMMI12
    // variable follows at 0.05 em. Subtracting the adjustment from the end measured 0.23 em and
    // inserted `5 y` inside formulas; the glyphs' own gap keeps it joined.
    let formula = "/R7 gs BT /R35 10 Tf 1 0 0 1 40 700 Tm (Subtract) Tj /R46 10 Tf 1 0 0 1 82 700 Tm [(5)178.413] TJ /R44 10 Tf 1 0 0 1 87.5 700 Tm (y) Tj ET"
    let math = try boundaryEvidence(formula, fonts: fonts, extGState: states)
    #expect(close(math.map(\.end), [80, 87, 92.5]))
    #expect(repairedBoundary(math, "Subtract 5y") == "Subtract 5y")
    // Adjustments between strings still move the glyphs after them.
    let inner = try boundaryEvidence("BT /R46 10 Tf 1 0 0 1 82 700 Tm [(7)-300(8)178.413] TJ ET", fonts: fonts)
    #expect(inner.first?.end == 95)
}

@Test func graphicsStateWithoutAFontKeepsEvidenceAndAnyOtherDisqualifies() throws {
    let upright = "BT /Fa 10 Tf 1 0 0 1 40 700 Tm (event) Tj /Fb 10 Tf 1 0 0 1 68 700 Tm (e) Tj /Fa 10 Tf 1 0 0 1 76 700 Tm (must) Tj ET"
    let states = "/R7 << /Type /ExtGState /OPM 1 /CA 0.5 >> /WithFont << /Type /ExtGState /Font [null 12] >> /NotADictionary 3"
    for prefix in ["/R7 gs ", "q /R7 gs Q "] {
        #expect(repairedBoundary(try boundaryEvidence(prefix + upright, extGState: states), "event emust") == "event e must")
    }
    let insideText = "BT /Fa 10 Tf 1 0 0 1 40 700 Tm (event) Tj /R7 gs /Fb 10 Tf 1 0 0 1 68 700 Tm (e) Tj /Fa 10 Tf 1 0 0 1 76 700 Tm (must) Tj ET"
    #expect(repairedBoundary(try boundaryEvidence(insideText, extGState: states), "event emust") == "event e must")
    for prefix in ["/WithFont gs ", "/Missing gs ", "/NotADictionary gs ", "gs "] {
        #expect(try boundaryEvidence(prefix + upright, extGState: states).isEmpty)
    }
    // Nonzero character or word spacing still disqualifies the page, as before.
    for prefix in ["/R7 gs 1 Tc ", "/R7 gs 1 Tw "] {
        #expect(try boundaryEvidence(prefix + upright, extGState: states).isEmpty)
    }
}

@Test func onlyWinAnsiEncodedType1FontsWithoutToUnicodeDecodeThroughTheirEncoding() throws {
    let plain = try #require(NativeSpacingReader.winAnsiUnicodeMap(differences: []))
    #expect(plain.count == 95)
    #expect(plain[32] == " " && plain[65] == "A" && plain[126] == "~")
    #expect(plain[31] == nil && plain[127] == nil && plain[146] == nil)
    // Wallace's EC text fonts: quotes and ligatures through Differences; an unknown name removes its code.
    let ec = try #require(NativeSpacingReader.winAnsiUnicodeMap(differences: [
        .code(16), .name("quotedblleft"), .name("quotedblright"), .code(27), .name("ff"), .name("fi"),
        .code(39), .name("quoteright"), .code(55), .name("seven"), .code(65), .name("Omega"),
    ]))
    #expect(ec[16] == "\u{201C}" && ec[17] == "\u{201D}" && ec[27] == "\u{FB00}" && ec[28] == "\u{FB01}")
    #expect(ec[39] == "\u{2019}" && ec[55] == "7")
    #expect(ec[65] == nil)
    let bad: [[NativeSpacingReader.EncodingDifference]] = [[.name("a")], [.code(256)], [.code(-1)],
        [.code(255), .name("a"), .name("b")], Array(repeating: .code(1), count: 257)]
    for differences in bad {
        #expect(NativeSpacingReader.winAnsiUnicodeMap(differences: differences) == nil)
    }
    let ops = "BT /Fa 10 Tf 1 0 0 1 40 700 Tm (event) Tj /Fb 10 Tf 1 0 0 1 68 700 Tm (e) Tj /Fa 10 Tf 1 0 0 1 76 700 Tm (must) Tj ET"
    func second(_ font: BoundaryFont) throws -> String? { try boundaryEvidence(ops, fonts: [BoundaryFont(name: "Fa"), font])[1].unicode }
    #expect(try second(BoundaryFont(name: "Fb", map: nil, encoding: "/WinAnsiEncoding")) == "e")
    #expect(try second(BoundaryFont(name: "Fb", map: nil, encoding: "/WinAnsiEncoding", subtype: "MMType1")) == "e")
    #expect(try second(BoundaryFont(name: "Fb", map: nil, encoding: "<< /Differences [ 101 /e ] /BaseEncoding /WinAnsiEncoding >>")) == "e")
    // Other encodings, a dictionary without a WinAnsi base, TrueType (whose codes select glyphs
    // through the font's cmap), a Differences name the table lacks or before any code, and a font
    // whose ToUnicode map is present but rejected do not decode, so their lines are not matched.
    let undecoded = [
        BoundaryFont(name: "Fb", map: nil),
        BoundaryFont(name: "Fb", map: nil, encoding: "/MacRomanEncoding"),
        BoundaryFont(name: "Fb", map: nil, encoding: "<< /Differences [ 101 /e ] >>"),
        BoundaryFont(name: "Fb", map: nil, encoding: "<< /BaseEncoding /StandardEncoding >>"),
        BoundaryFont(name: "Fb", map: nil, encoding: "<< /BaseEncoding /WinAnsiEncoding /Differences [ 101 /epsilon1 ] >>"),
        BoundaryFont(name: "Fb", map: nil, encoding: "<< /BaseEncoding /WinAnsiEncoding /Differences [ /e ] >>"),
        BoundaryFont(name: "Fb", map: nil, encoding: "/WinAnsiEncoding", subtype: "TrueType"),
        BoundaryFont(name: "Fb", map: "not a cmap", encoding: "/WinAnsiEncoding"),
    ]
    for font in undecoded {
        #expect(try second(font) == nil)
        #expect(repairedBoundary(try boundaryEvidence(ops, fonts: [BoundaryFont(name: "Fa"), font]), "event emust") == "event emust")
    }
    // A page whose simple fonts lack both ToUnicode and a supported encoding is not scanned.
    #expect(try boundaryEvidence(ops, fonts: [BoundaryFont(name: "Fa", map: nil), BoundaryFont(name: "Fb", map: nil)]).isEmpty)
}
