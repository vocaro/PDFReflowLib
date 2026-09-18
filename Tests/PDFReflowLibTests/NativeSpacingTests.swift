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
    for prefix in ["1 Ts", "3 Tr", "90 Tz", "/G gs", "Q", "q", "/Missing Do"] {
        #expect(try spacingEvidence(show, prefix: prefix).isEmpty)
    }
    // Character and word spacing are measured for word boundaries (#119), but Type3 space removal
    // does not model them: its show supplies no removal evidence.
    for prefix in ["1 Tc", "1 Tw", "-0.5 Tc"] {
        let evidence = try spacingEvidence(show, prefix: prefix)
        #expect(evidence.count == 1)
        #expect(evidence.first?.text == nil)
        #expect(evidence.first?.extraSpaces(in: "Dair y") == nil)
    }
    #expect(try spacingEvidence(show, prefix: "1001 Tc").isEmpty)
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
    for prefix in ["1 Ts ", "90 Tz ", "/G gs "] {
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
    // Character and word spacing are measured since #119: 1 Tc (0.1 em per glyph) widens each
    // advance and leaves the glyphs after the last one alone; 1 Tw widens only code 32.
    let spaced = try boundaryEvidence("/R7 gs 1 Tc " + upright, extGState: states)
    #expect(spaced.map(\.end) == [69, 73, 99])
    #expect(repairedBoundary(spaced, "event emust") == "event e must")
    let words = try boundaryEvidence("/R7 gs 1 Tw " + upright.replacingOccurrences(of: "(event)", with: "(ev ent)"), extGState: states)
    #expect(words.map(\.end) == [71, 73, 96])
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

// MARK: - Same-font word spaces (#119)

private struct NineElevenSource: Decodable {
    struct Font: Decodable {
        var resourceName: String
        var subtype: String
        var firstChar: Int?
        var widths: [Double]?
        var toUnicode: String?
    }
    struct Line: Decodable { var text: String; var rect: [Double] }
    struct Page: Decodable {
        var page: Int
        var fonts: [Font]
        var extGStates: [String: String]
        var operators: String
        var lines: [Line]
    }
    var sourceSHA256: String
    var pages: [Page]
    static func load(_ name: String = "911-text-operators") throws -> Self {
        try JSONDecoder().decode(Self.self, from: Data(contentsOf: Bundle.module.resourceURL!
            .appendingPathComponent("fixtures/\(name).json")))
    }
}

/// The two words around every space `repaired` adds to `native`, in order (`went.8 They`).
private func insertedPairs(_ native: String, _ repaired: String) -> [String] {
    let before = Array(native), after = Array(repaired)
    var i = 0, j = 0, pairs: [String] = []
    while i < before.count, j < after.count {
        if before[i] == after[j] { i += 1; j += 1; continue }
        guard after[j] == " ", j > 0 else { return ["mismatch: \(repaired)"] }
        let start = after[..<(j - 1)].lastIndex(of: " ").map { $0 + 1 } ?? 0
        let end = after[(j + 1)...].firstIndex(of: " ") ?? after.count
        pairs.append(String(after[start..<end]))
        j += 1
    }
    return i == before.count && j == after.count ? pairs : ["mismatch: \(repaired)"]
}

/// A fixture page rebuilt from its source fonts, graphics states and content stream, with PDFKit's
/// native lines repaired as NativeTextReader does: the inserted pairs and the repaired lines.
private func nineElevenRepairs(_ page: NineElevenSource.Page, operators: String? = nil,
                               rows: Bool = false) throws -> (pairs: [String], text: [String]) {
    let fonts = page.fonts.map {
        BoundaryFont(name: $0.resourceName, firstChar: $0.firstChar, widths: $0.widths, map: $0.toUnicode, subtype: $0.subtype)
    }
    let states = page.extGStates.sorted { $0.key < $1.key }.map { "/\($0.key) \($0.value)" }.joined(separator: " ")
    let document = try boundaryPDF(fonts: fonts, operators: operators ?? page.operators, extGState: states)
    let evidence = NativeSpacingReader.read(try #require(document.page(at: 1)))
    let bounds = page.lines.map { CGRect(x: $0.rect[0], y: $0.rect[1], width: $0.rect[2], height: $0.rect[3]) }
    var pairs: [String] = [], text: [String] = []
    for (index, line) in page.lines.enumerated() {
        let repaired = NativeSpacingReader.apply(evidence, to: NSAttributedString(string: line.text), bounds: bounds[index],
                                                 allBounds: bounds, allTexts: rows ? page.lines.map(\.text) : []).string
        pairs += insertedPairs(line.text, repaired)
        text.append(repaired)
    }
    return (pairs, text)
}

@Test func nineElevenSameFontWordSpacesAreRestoredOnSourcePages() throws {
    let source = try NineElevenSource.load()
    #expect(source.sourceSHA256 == (try SourceLayoutFixture.load("911-19")).sourceSHA256)
    // Every insertion on these pages, reviewed on 200-dpi renders of the original (#119 record):
    // spaces after punctuation set as a TJ adjustment (`mosques.)-108.9(He`), before capitals whose
    // kern takes the space (`New|York`), before `(`, and the note reference `went.8They`. Since #128
    // also every sentence space a kern absorbs entirely (`dispute.|The`, `v.|Yousef`), across a
    // semibold speaker label (`Headquarters:|Yes.`) and after an ellipsis's last word (`...Okay.|Push`),
    // each reviewed on 250-dpi renders (kerned-sentence-spaces-and-fusions record).
    let expected: [Int: [String]] = [
        19: ["work. Some", "Towers, the", "World Trade", "New York", "City. Others", "Arlington, Vir-", "Pentagon. Across", "journey. Among", "Boston: American", "Boston, Atta", "later, Atta", "Airport. They"],
        45: ["9:23: “Okay", ". These", "New York.", "York. The", "area. The", "liaison, NEADS", "NEADS: “We’re", "77.” The", "Washington: “Latest", "report. Aircraft", "House.... Six,", "Six, south-", "fighters: “Okay,", "“Okay, we’re", "instructed, but", "ocean. “I", "said. “Damn", "... Okay.", "Okay. Push", "order, this", "location. Second,", "Second, a", "“generic” flight", "miles. Third,", "Washington. The", "9:38. The", "9:37:46. The", "aircraft. It", "all. After", "second World", "World Trade", "crash, Boston"],
        48: ["area. Within", "seconds, the", "aircraft, and", "D.C. The", "dispute. The", "radar, the", "Headquarters: Yes.", "Uh, who,", "who, it", "ground. That’s", "10:07. Unaware"],
        57: ["to Vice", "Cheney, Dr.", "Dr. Rice,", "Rice, New", "New York", "airport. The", "9:30, the", "missing. Staff", "the White", "determine, no", "Pentagon. The", "nation. The", "9:45. During", "the Vice", "President: “Sounds", "Pentagon. We’re", "time, Card,", "Card, the", "agent, the", "aide, and", "elsewhere. The", "The Vice", "to Washington.", "Washington. Air", "destination. The", "us.” This", "time. As", "minute, before", "back. This"],
        234: ["mosques. He", "research, which", "instructed, they", "Airport, we", "went.8 They", "community, specifically", "evening, Abdullah", "private. The", "them. This", "Angeles. This", "community, Thumairy"],
        489: ["v. Ali", "Davies, “Saudis", "(London), Aug.", "later. Testimony", "88. “World", "U.S. Attorney", "Odeh, Aug.", "U.S. Attorney", "interview, “To", "U.S. Attorney", "93. ABC", "interview, “Terror", "Suspect: An", "1. Brief", "v. Ramzi", "Ahmed Yousef,", "Yousef, Lead", "No. 98-1041", "Cir. filed", "Aug. 25,", "25, 2000),", "War: The", "CIA, Afghanistan,", "3. Trial", "v. Yousef,", "v. Yousef,", "v. Rahman,", "Rahman, 189", "88, 104", "Cir. 1999);", "1999); Brief", "v. Siddig", "No. 96-1044", "Cir. filed", "3, 1997),", "1997), pp.", "pp. 10,", "10, 15.", "15. See", "report, “Review"],
    ]
    var texts: [Int: String] = [:]
    for page in source.pages {
        let result = try nineElevenRepairs(page)
        #expect(result.pairs == expected[page.page] ?? [], "page \(page.page)")
        texts[page.page] = result.text.joined(separator: "\n")
    }
    // Negative controls on the same pages: letter-spaced small caps (Tc), a time whose adjustment
    // Tc cancels (`9:|34`, +31 against -0.031 em), the `f|’` kern at +0.125 em, ellipsis dots,
    // initials inside an abbreviation, and a kerned space glyph all stay as PDFKit read them. The
    // sentence space narrower than the overhang threshold (`dispute.|The`) is restored by #128.
    #expect(texts[19]?.contains("Tuesday, September 11, 2001, dawned temperate") == true)
    #expect(texts[57]?.contains("White House, at 9:34. It") == true)
    #expect(texts[48]?.contains("Commission staff’s analysis") == true)
    #expect(texts[48]?.contains("subject of some dispute. The 10:03:11") == true)
    // #128's character rule leaves every closed abbreviation on these pages closed (`U.S.`, `D.C.`,
    // `S.D.`, `A.M.`, `O.K.`): no other punctuation-capital run remains. The ellipses before a capital
    // it left closed (`House....Six`, `...Okay`) sit in letter-spaced lines whose adjustments offset
    // Tc 0.13–0.18 em (`(...S)131.1(i)`); since #143 their in-string gaps open `House.... Six, south-`
    // and `... Okay.` as the 200-dpi render sets them.
    let closed = try NSRegularExpression(pattern: #"\S*[.,;:?!][”’)\]]*[A-Z“‘]\S*"#)
    let remaining = texts.keys.sorted().flatMap { page -> [String] in
        let text = texts[page]!, range = NSRange(text.startIndex..., in: text)
        return closed.matches(in: text, range: range).map { "\(page): " + (text as NSString).substring(with: $0.range) }
    }
    #expect(remaining == ["19: A.M.", "45: D.C.", "48: D.C.", "48: O.K.", "489: U.S.", "489: (S.D.",
                          "489: N.Y.),", "489: U.S.", "489: U.S.", "489: U.S.", "489: U.S.", "489: U.S.", "489: (S.D.", "489: N.Y.),"])
    #expect(texts[45]?.contains("crank it up. . . . Run them") == true)
    #expect(texts[489]?.contains("(S.D. N.Y.), Oct. 20, 2000") == true)
    #expect(texts[234]?.contains("Customs at Los Angeles International") == true)
    // Without character and word spacing the producer model does not hold, so the same arrays
    // yield no word spaces; the separately positioned note reference is still restored.
    let page234 = try #require(source.pages.first { $0.page == 234 })
    let unspaced = page234.operators.replacingOccurrences(of: #"-?[0-9]*\.?[0-9]+ T([cw])"#, with: "0 T$1 ", options: .regularExpression)
    #expect(unspaced != page234.operators && !unspaced.contains("-0.0687 Tw"))
    #expect(try nineElevenRepairs(page234, operators: unspaced).pairs == ["went.8 They"])
}

@Test func sameFontWordSpaceSeparatesTheMeasuredGapModes() {
    func space(_ left: Unicode.Scalar, _ right: Unicode.Scalar, _ gap: CGFloat, after before: Unicode.Scalar? = "a") -> Bool {
        NativeSpacingReader.sameFontWordSpace(before: before, left: left, right: right, gap: gap)
    }
    // Before a letter, digit or `(`: 9/11 kerns end at 0.059 em, word spaces begin at 0.075 em.
    #expect(space(".", "H", 0.108) && space(",", "w", 0.075) && space(",", "2", 0.11) && space("\u{201D}", "t", 0.1))
    #expect(space(".", "(", 0.105) && space("w", "t", 0.1))
    #expect(!space("r", "i", 0.0586) && !space(".", "S", 0.06) && !space(".", "(", 0.05))
    // After a lowercase letter or punctuation, an overhanging capital or opening quote: kerns and
    // abbreviations lie at or below 0.001 em, word spaces from 0.003 em; the threshold is 0.005.
    #expect(space("w", "Y", 0.0235) && space(".", "T", 0.006) && space(",", "\u{201C}", 0.0085) && space(";", "\u{2018}", 0.01))
    #expect(!space(".", "Y", -0.0004) && !space(".", "W", 0.001) && !space("w", "Y", 0.004))
    // Between capitals the narrow mode is kerning (Replay's Libertine small caps `WI|TH`).
    #expect(!space("I", "T", 0.037) && space("I", "T", 0.0835) && !space("3", "T", 0.03))
    // Decimals and times never split; a comma between digits does at a word gap (`11, 2001`).
    #expect(!space(".", "5", 0.2, after: "3") && !space(":", "4", 0.2, after: "8") && space(",", "2", 0.11, after: "1"))
    // Not word boundaries: ellipsis dots, closing quotes after a letter, dashes, mathematical
    // letters, and gaps beyond an em.
    #expect(!space(".", ".", 0.13) && !space("f", "\u{2019}", 0.125) && !space("\u{2014}", "T", 0.2) && !space("e", "-", 0.2))
    #expect(!space(".", "\u{1D453}", 0.1) && !space("\u{1D43B}", "\u{1D43F}", 0.1) && !space("\u{210E}", "l", 0.1))
    #expect(!space(".", "T", 1.01) && !space(".", "T", .infinity) && !space(".", "T", .nan))
}

@Test func tjAdjustmentsInJustifiedShowsRestoreWordSpacesAndLetterSpacingStaysJoined() throws {
    // 10-point fonts with 500-unit advances. Nonzero Tc and Tw make the show a justified one; the
    // adjustment of 110 thousandths is a word space after the period.
    func words(_ show: String, spacing: String = "0.001 Tc -0.2 Tw") throws -> [NativeSpacingReader.Evidence] {
        try boundaryEvidence("BT \(spacing) /Fa 10 Tf 1 0 0 1 40 700 Tm \(show) ET")
    }
    let sentence = try words("[(went.)-110(They)] TJ")
    #expect(sentence.first?.wordSpaces == [5])
    #expect(repairedBoundary(sentence, "went.They") == "went. They")
    #expect(repairedBoundary(sentence, "went. They") == "went. They")
    for native in ["went.Them", "went.They extra", "wentThey"] {
        #expect(repairedBoundary(sentence, native) == native)
    }
    // A trailing space glyph that PDFKit trims still matches; any other difference does not.
    #expect(repairedBoundary(try words("[(went.)-110(They )] TJ"), "went.They") == "went. They")
    #expect(repairedBoundary(try words("[(went.)-110(Vir=)] TJ"), "went.Vir-") == "went.Vir-")
    #expect(repairedBoundary(try words("[(went.)-110(They)] TJ"), "went.They ") == "went. They ")
    // Negative character spacing that cancels the adjustment leaves no gap (9/11's `9:|34`, +31
    // against Tc -0.031 em); a smaller one leaves the word gap.
    #expect(try words("[(went.)-110(They)] TJ", spacing: "-1.1 Tc -0.2 Tw").first?.wordSpaces == [])
    #expect(try words("[(went.)-110(They)] TJ", spacing: "-0.2 Tc -0.2 Tw").first?.wordSpaces == [5])
    // Letter-spaced type adjusts every glyph alike: no single boundary is a word space.
    #expect(try words("[(C)-100(H)-100(A)-100(P)] TJ").first?.wordSpaces == [])
    #expect(try words("[(to)-100(a)-100(b)] TJ").first?.wordSpaces == [])
    #expect(try words("[(went.)-110(A)-5(nd)] TJ").first?.wordSpaces == [5])
    // A show without character or word spacing (TeX, NOAA's Lora `E.|A.` at +0.027 em) is not read.
    #expect(try words("[(went.)-110(They)] TJ", spacing: "0 Tc 0 Tw").first?.wordSpaces == [])
    // An empty string between the adjustment and the glyphs keeps the boundary.
    #expect(try words("[(went.)-110()(They)] TJ").first?.wordSpaces == [5])
}

@Test func noteReferenceBeforeACapitalRestoresItsWordSpaceOnly() throws {
    // 9/11 page 234: `ent.` at 10.25 points, the reference `8` at 7.175 points raised 2.25 points,
    // then `They` 0.6 point after the reference's advance. Fonts have 500-unit advances.
    func line(_ note: String, raise: CGFloat = 2.25, gap: CGFloat = 0.6, size: CGFloat = 7.175, next: String = "They") throws -> [NativeSpacingReader.Evidence] {
        let end = 60 + 0.5 * size * CGFloat(note.count)
        return try boundaryEvidence("BT 0.001 Tc -0.07 Tw /Fa 10.25 Tf 1 0 0 1 40 700 Tm (ent.) Tj /Fa \(size) Tf 1 0 0 1 60 \(700 + raise) Tm (\(note)) Tj "
            + "/Fa 10.25 Tf 1 0 0 1 \(end + gap) 700 Tm (\(next)) Tj ET")
    }
    #expect(repairedBoundary(try line("8"), "ent.8They") == "ent.8 They")
    #expect(repairedBoundary(try line("135"), "ent.135They") == "ent.135 They")
    // A reference set tight against the text, on the baseline, before a lowercase continuation, at
    // nearly the text's size, or anything but digits stays joined.
    #expect(repairedBoundary(try line("8", gap: 0.2), "ent.8They") == "ent.8They")
    #expect(repairedBoundary(try line("8", raise: 0), "ent.8They") == "ent.8They")
    #expect(repairedBoundary(try line("8", next: "they"), "ent.8they") == "ent.8they")
    #expect(repairedBoundary(try line("8", size: 9), "ent.8They") == "ent.8They")
    #expect(repairedBoundary(try line("a"), "ent.aThey") == "ent.aThey")
}

// MARK: - Kerned sentence spaces (#128) and remaining fusions (#120)

@Test func sentenceSpaceSeparatesSentencesFromInitialsAbbreviationsAndAddresses() {
    func sentence(_ word: String, _ following: String, gap: CGFloat = -0.02, startsShow: Bool = false) -> Bool {
        NativeSpacingReader.sentenceSpace(word: Array(word.unicodeScalars), startsShow: startsShow,
                                          following: Array(following.unicodeScalars), gap: gap)
    }
    // 9/11's absorbed sentence spaces: a word, sentence punctuation (and closing quotes or brackets),
    // then a capitalized word, an acronym, a one-letter word or an opening quote.
    #expect(sentence("casualties.", "The ") && sentence("unharmed.", "We") && sentence("Berger,", "Tenet ") && sentence("FAA:", "Yes. "))
    #expect(sentence("2004);", "Vice ") && sentence("Jews.\u{201D}", "The ") && sentence("(OMB).", "They ") && sentence("City].", "They\u{2019}re "))
    #expect(sentence("alert.", "\u{201C}Is ") && sentence("memo,", "\u{201C}Bin ") && sentence("States.", "FBI ") && sentence("aircraft.", "A "))
    // The book spaces an abbreviation or an initial before a capitalized word (`U.S.|Army` 157 of 157,
    // initials 230 of 236), and a year that ends a sentence inside a show.
    #expect(sentence("v.", "Yousef, ") && sentence("F.", "Verga, ") && sentence("U.S.", "VISIT ") && sentence("Asst.", "Doc. "))
    #expect(sentence("...Okay.", "Push ") && sentence("1998.", "The ") && sentence("10.", "August ") && sentence("S.", "Court "))
    // Set closed: a capital that continues an abbreviation (781 of 791), an initial before a short
    // capitalized abbreviation (Our Flag's `H.Doc.`), an apostrophe after a letter, an ellipsis,
    // an address, and a number that opens its show (list and note numbers, `10.August 2001`).
    #expect(!sentence("U.", "S. ") && !sentence("(S.D.N.", "Y.), ") && !sentence("Ladin.", "U.S. ") && !sentence("Washington,D.", "C. "))
    #expect(!sentence("H.", "Doc. ") && !sentence("S.", "Ct. ") && !sentence("Ph.", "D. "))
    #expect(!sentence("O\u{2019}", "Neill ") && !sentence("QAEDA\u{2019}", "S ") && sentence("Jones\u{2019}.", "The "))
    #expect(!sentence("....", "We ") && !sentence("House....", "Six,") && !sentence("\u{2019}...", "Islamism "))
    #expect(!sentence("reports/print.php3?", "ReportID=145). ") && !sentence("www.fbi.", "Gov ") && !sentence("name@site.", "Org "))
    #expect(!sentence("10.", "August ", startsShow: true) && !sentence("21.", "While ", startsShow: true) && sentence("(21).", "While ", startsShow: true))
    // Not sentence boundaries: no punctuation, a lowercase continuation, punctuation alone, a
    // mathematical letter, a capital that ends the show (its word is unknown), an opening quote
    // before a space, and gaps outside -0.15 to 1 em.
    #expect(!sentence("event", "Must ") && !sentence("e.", "must ") && !sentence(".", "The ") && !sentence(",", "The ") && !sentence(")).", "The "))
    #expect(!sentence("\u{1D452}.", "The ") && !sentence("x.", "\u{1D434} ") && !sentence("done.", "T") && !sentence("said,", "\u{201C} "))
    #expect(sentence("casualties.", "The ", gap: -0.15) && !sentence("casualties.", "The ", gap: -0.16) && sentence("casualties.", "The ", gap: 1))
    #expect(!sentence("casualties.", "The ", gap: 1.01) && !sentence("casualties.", "The ", gap: .nan))
}

@Test func kernedSentenceSpacesAreRestoredInsideAndAcrossJustifiedShows() throws {
    // 10-point fonts with 500-unit advances; nonzero Tc and Tw mark a justified show (#119).
    func read(_ body: String, spacing: String = "0.001 Tc -0.07 Tw") throws -> [NativeSpacingReader.Evidence] {
        try boundaryEvidence("BT \(spacing) \(body) ET")
    }
    // 9/11 page 134, `casualties.)19.7(The`: the kern before the overhanging T takes the whole space.
    let adjusted = try read("/Fa 10 Tf 1 0 0 1 40 700 Tm [(ties.)19.7(The)] TJ")
    #expect(adjusted.first?.wordSpaces == [] && adjusted.first?.sentenceSpaces == [5])
    #expect(repairedBoundary(adjusted, "ties.The") == "ties. The")
    // Page 312, `unharmed.We`: no adjustment at all.
    let unadjusted = try read("/Fa 10 Tf 1 0 0 1 40 700 Tm (med.We know) Tj")
    #expect(unadjusted.first?.sentenceSpaces == [4])
    #expect(repairedBoundary(unadjusted, "med.We know") == "med. We know")
    // Closed forms in the same kind of show stay as PDFKit reads them.
    for text in ["U.S.", "N.Y. law", "H.Doc. 108", "10.August", "a....We", "x/p.php?Id", "O'Neill"] {
        let evidence = try read("/Fa 10 Tf 1 0 0 1 40 700 Tm (\(text)) Tj")
        #expect(evidence.first?.sentenceSpaces == [], "\(text)")
        #expect(repairedBoundary(evidence, text) == text)
    }
    // Without character or word spacing the producer model does not hold (TeX, InDesign).
    #expect(try read("/Fa 10 Tf 1 0 0 1 40 700 Tm (med.We know) Tj", spacing: "0 Tc 0 Tw").first?.sentenceSpaces == [])
    // A semibold speaker label (9/11 page 44, `FAA:|Yes.`): the next show resumes 0.1 em later, below
    // the font-change rule's 0.15 em.
    func label(_ reply: String, size: CGFloat = 10, spacing: String = "0.001 Tc -0.07 Tw") throws -> [NativeSpacingReader.Evidence] {
        try read("/Fb 10 Tf 1 0 0 1 40 700 Tm (FAA:) Tj /Fa \(size) Tf 1 0 0 1 61 700 Tm (\(reply)) Tj", spacing: spacing)
    }
    #expect(repairedBoundary(try label("Yes."), "FAA:Yes.") == "FAA: Yes.")
    #expect(repairedBoundary(try label("yes."), "FAA:yes.") == "FAA:yes.")
    #expect(repairedBoundary(try label("Yes.", size: 7), "FAA:Yes.") == "FAA:Yes.")
    #expect(repairedBoundary(try label("Yes.", spacing: "0 Tc 0 Tw"), "FAA:Yes.") == "FAA:Yes.")
    // The word or the capital's word continues into another show: an italic title before roman
    // punctuation (page 193, `Encyclopedia|.Six`) and a show split inside a name (page 223,
    // `June,T|enet`, whose second show continues the cursor).
    let italic = try read("/Fb 10 Tf 1 0 0 1 40 700 Tm (Encyc) Tj /Fa 10 Tf 1 0 0 1 65.004 700 Tm (.Six of) Tj")
    #expect(italic.last?.sentenceSpaces == [] && italic.last?.sentenceCandidates.keys.sorted() == [1])
    #expect(repairedBoundary(italic, "Encyc.Six of") == "Encyc. Six of")
    #expect(repairedBoundary(try read("/Fa 10 Tf 1 0 0 1 40 700 Tm (June,T) Tj (enet) Tj"), "June,Tenet") == "June, Tenet")
    // A word gap before the punctuation's show leaves it a word of its own.
    let apart = try read("/Fb 10 Tf 1 0 0 1 40 700 Tm (Encyc) Tj /Fa 10 Tf 1 0 0 1 80 700 Tm (.Six of) Tj")
    #expect(repairedBoundary(apart, "Encyc .Six of") == "Encyc .Six of")
}

@Test func chainedInitialsTakeTheLetterThresholdBeforeAnOverhangingCapital() throws {
    // NOAA page 518: Lora kerns `.|A` by +0.027 em inside initials it sets closed, on lines with word
    // spacing of -0.002 em (`0 Tc -0.018 Tw` at 9 points).
    let initials = try boundaryEvidence("BT 0 Tc -0.018 Tw /Fa 9 Tf 1 0 0 1 40 700 Tm [(C.)-27(A. Morgan)] TJ ET")
    #expect(initials.first?.wordSpaces == [] && initials.first?.sentenceSpaces == [])
    #expect(repairedBoundary(initials, "C.A. Morgan") == "C.A. Morgan")
    // The same kern after a word is a sentence space's remainder.
    let sentence = try boundaryEvidence("BT 0 Tc -0.018 Tw /Fa 9 Tf 1 0 0 1 40 700 Tm [(ic.)-27(A plane)] TJ ET")
    #expect(sentence.first?.wordSpaces == [3])
    // 9/11 `George H.|W.Bush` at 0.015-0.050 em now stays closed, as page 358 sets it; `Samuel M.|W.`
    // at 0.081 em keeps its space.
    func space(_ before: Unicode.Scalar, _ gap: CGFloat, after: Unicode.Scalar?) -> Bool {
        NativeSpacingReader.sameFontWordSpace(before: before, left: ".", right: "W", gap: gap, after: after)
    }
    #expect(!space("H", 0.029, after: ".") && space("M", 0.081, after: ".") && space("H", 0.029, after: "a") && space("e", 0.029, after: "."))
    #expect(space("H", 0.029, after: nil))
}

@Test func showsThatContinueTheTextCursorAreReadFromTheMeasuredAdvance() throws {
    // Replay Clocks page 10 continues the cursor after a measured show (`[([8])]TJ 0 g 0 G [-571(D)…]TJ`).
    // A math show that ends with a trailing adjustment moves the next show by it: `must` resumes
    // 0.15 em after `e`, a font-change word space.
    let continued = try boundaryEvidence("BT /Fa 10 Tf 1 0 0 1 40 700 Tm (if ) Tj /Fb 10 Tf [(e)-150] TJ /Fa 10 Tf (must) Tj ET")
    #expect(continued.map(\.origin.x) == [40, 55, 61.5])
    #expect(continued.map(\.end) == [55, 60, 81.5])
    #expect(repairedBoundary(continued, "if emust") == "if e must")
    // Character spacing after the last glyph moves the cursor; `Td` stays relative to the line start.
    let spaced = try boundaryEvidence("BT 2 Tc /Fa 10 Tf 1 0 0 1 40 700 Tm (ab) Tj (c) Tj 0 -12 Td (d) Tj ET")
    #expect(spaced.map(\.origin) == [CGPoint(x: 40, y: 700), CGPoint(x: 54, y: 700), CGPoint(x: 40, y: 688)])
    // A show without complete widths gives no advance, so a show that continues it still disqualifies
    // the page, as do `'` and a show before any positioning.
    let unmeasured = [BoundaryFont(name: "Fa"), BoundaryFont(name: "Fb", widths: nil)]
    #expect(try boundaryEvidence("BT /Fb 10 Tf 1 0 0 1 40 700 Tm (e) Tj /Fa 10 Tf (must) Tj ET", fonts: unmeasured).isEmpty)
    #expect(try boundaryEvidence("BT /Fa 10 Tf 1 0 0 1 40 700 Tm (if) Tj 12 TL (e) ' ET").isEmpty)
    #expect(try boundaryEvidence("BT /Fa 10 Tf (must) Tj ET").isEmpty)
}

@Test func characterSpacingColumnGapsSplitTwoGlyphTableCells() throws {
    // FAA page 458, the Challenger 605 table: Helvetica at `1 Tf` under an 8× text matrix, where
    // `(68)Tj 1.465 Tc -1.465 Tw (52)Tj` sets the column gap between 5 and 2 as character spacing and
    // `(52)` continues the cursor. Fonts have 500-unit advances.
    func row(_ cell: String, spacing: String = "1.465") throws -> [NativeSpacingReader.Evidence] {
        try boundaryEvidence("BT /Fa 1 Tf 8 0 0 8 40 700 Tm -0.002 Tc 0.002 Tw (1,68) Tj \(spacing) Tc -\(spacing) Tw (\(cell)) Tj "
            + "-0.002 Tc 0.002 Tw (,599) Tj ET")
    }
    let table = try row("52")
    #expect(table.map(\.unicode) == ["1,68", "52", ",599"] && table[1].wordSpaces == [1])
    #expect(repairedBoundary(table, "1,6852,599") == "1,685 2,599")
    #expect(repairedBoundary(try row("52", spacing: "0.756"), "1,6852,599") == "1,685 2,599")
    // Letter-spacing (FAA's largest is 0.2 em), a longer show and a gap beyond 10 em stay joined.
    #expect(try row("52", spacing: "0.2").map(\.wordSpaces) == [[], [], []])
    #expect(try row("523", spacing: "1.465").map(\.wordSpaces) == [[], [], []])
    #expect(try row("52", spacing: "10.5").map(\.wordSpaces) == [[], [], []])
}

@Test func mathPunctuationClosingAFormulaBeforeProseAtAFontChangeRestoresItsSpace() throws {
    // Wallace page 22, `(x − 6) when`: the closing parenthesis is set in the math font against the
    // formula and the prose resumes 0.16 em later in the text font. Fonts have 500-unit advances.
    func line(closing: String = "\\)", at x: CGFloat = 60, next: CGFloat = 66.6, word: String = "when") throws -> [NativeSpacingReader.Evidence] {
        try boundaryEvidence("BT /Fa 10 Tf 1 0 0 1 40 700 Tm (\\(x-6) Tj /Fb 10 Tf 1 0 0 1 \(x) 700 Tm (\(closing)) Tj "
            + "/Fa 10 Tf 1 0 0 1 \(next) 700 Tm (\(word)) Tj ET")
    }
    #expect(repairedBoundary(try line(), "(x-6)when") == "(x-6) when")
    #expect(repairedBoundary(try line(closing: ";"), "(x-6;when") == "(x-6; when")
    // Below the word gap, before a digit, after a word gap, after a space in its own show, or after a
    // period, the punctuation stays joined.
    #expect(repairedBoundary(try line(next: 66.4), "(x-6)when") == "(x-6)when")
    #expect(repairedBoundary(try line(word: "3"), "(x-6)3") == "(x-6)3")
    #expect(repairedBoundary(try line(at: 62, next: 68.6), "(x-6 )when") == "(x-6 )when")
    #expect(repairedBoundary(try line(closing: " \\)", next: 71.6), "(x-6 )when") == "(x-6 )when")
    #expect(repairedBoundary(try line(closing: "."), "(x-6.when") == "(x-6.when")
}

// MARK: - Math spaces beside operators (#188)

/// Source pages captured by `measurements/math-operator-spaces/capture.swift`: font resources with
/// their ToUnicode maps and encodings, graphics states, the decoded content stream and PDFKit's lines.
private struct OperatorSource: Decodable {
    struct Font: Decodable {
        var resourceName: String
        var subtype: String
        var firstChar: Int?
        var widths: [Double]?
        var toUnicode: String?
        var encoding: String?
    }
    struct Line: Decodable { var text: String; var rect: [Double] }
    struct Page: Decodable {
        var page: Int
        var fonts: [Font]
        var extGStates: [String: String]
        var operators: String
        var lines: [Line]
    }
    var sourceSHA256: String
    var pages: [Page]
    static func load(_ name: String) throws -> Self {
        try JSONDecoder().decode(Self.self, from: Data(contentsOf: Bundle.module.resourceURL!
            .appendingPathComponent("fixtures/\(name)-text-operators.json")))
    }
}

/// The spacing evidence of a fixture page rebuilt from its fonts, graphics states and content stream
/// (`operators` replaces the stream).
private func operatorEvidence(_ page: OperatorSource.Page, operators: String? = nil) throws -> [NativeSpacingReader.Evidence] {
    let fonts = page.fonts.map {
        BoundaryFont(name: $0.resourceName, firstChar: $0.firstChar, widths: $0.widths, map: $0.toUnicode,
                     encoding: $0.encoding, subtype: $0.subtype)
    }
    let states = page.extGStates.sorted { $0.key < $1.key }.map { "/\($0.key) \($0.value)" }.joined(separator: " ")
    let document = try boundaryPDF(fonts: fonts, operators: operators ?? page.operators, extGState: states.isEmpty ? nil : states)
    return NativeSpacingReader.read(try #require(document.page(at: 1)))
}

/// Every line of a fixture page that the spacing reader changes, as NativeTextReader applies it,
/// keyed by PDFKit's text (trailing whitespace trimmed).
private func operatorRepairs(_ page: OperatorSource.Page, operators: String? = nil) throws -> [String: String] {
    let evidence = try operatorEvidence(page, operators: operators)
    let bounds = page.lines.map { CGRect(x: $0.rect[0], y: $0.rect[1], width: $0.rect[2], height: $0.rect[3]) }
    var repaired: [String: String] = [:]
    for (index, line) in page.lines.enumerated() {
        let result = NativeSpacingReader.apply(evidence, to: NSAttributedString(string: line.text), bounds: bounds[index], allBounds: bounds).string
        if result != line.text {
            repaired[line.text.trimmingCharacters(in: .whitespaces)] = result.trimmingCharacters(in: .whitespaces)
        }
    }
    return repaired
}

@Test func operatorSpaceSeparatesTheMathSpaceFromKernsScriptsAndClosedSigns() {
    func space(_ left: Unicode.Scalar, _ right: Unicode.Scalar, _ gap: CGFloat) -> Bool {
        NativeSpacingReader.operatorSpace(left: left, right: right, gap: gap)
    }
    // Measured on Wallace page 7 (`− 5 + ( − 3)`, `add 5 + 3`): every gap beside an operator is TeX's
    // thin space, 0.160–0.172 em, whichever side PDFKit spaced; and Replay Clocks' `𝑛 = 32` at 0.285 em.
    #expect(space("5", "+", 0.1629) && space("+", "(", 0.1719) && space("(", "\u{2212}", 0.1601))
    #expect(space("\u{2212}", "5", 0.1655) && space("=", "\u{2212}", 0.1600) && space("\u{1D45B}", "=", 0.2851))
    #expect(space("\u{2264}", "E", 0.3) && space("\u{00D7}", "1", 0.2) && space("f", "\u{2212}", 0.1624))
    // The thresholds: a thin space at 0.15 em (Wallace sets no operator gap from 0.14 to 0.15 em) up to an em.
    #expect(space("5", "+", 0.15) && !space("5", "+", 0.1499))
    #expect(space("5", "+", 1) && !space("5", "+", 1.01))
    // Kerns stay joined: Replay's caption (e) sets `𝑛=` at 0.035 em where its siblings set 0.285, TeX
    // sets two relations together (`>>`, 0.043 em), and Wallace's script-size signs sit at 0.047 em.
    #expect(!space("\u{1D45B}", "=", 0.0349) && !space(">", ">", 0.043) && !space("\u{2212}", "5", 0.0473))
    // No operator (juxtaposed variables, #119's kerns; the ASCII hyphen, slash and middle dot are prose
    // punctuation), whitespace on either side, or no measurement.
    #expect(!space("x", "y", 0.3) && !space("-", "5", 0.3) && !space("/", "2", 0.3) && !space("\u{00B7}", "2", 0.3))
    #expect(!space(" ", "+", 0.3) && !space("+", " ", 0.3) && !space("5", "+", .nan) && !space("5", "+", .infinity))
}

@Test func wallaceWorkedExamplesSpaceEveryOperatorAsTheSourceSetsIt() throws {
    let source = try OperatorSource.load("algebra-7-8")
    #expect(source.sourceSHA256 == (try SourceLayoutFixture.load("algebra-10")).sourceSHA256)
    let seven = try #require(source.pages.first { $0.page == 7 }), eight = try #require(source.pages.first { $0.page == 8 })
    // Every change on the two pages, reviewed on 150-dpi renders (math-operator-spaces record): TeXmacs
    // sets one thin space on both sides of each sign, the unary minus included (`( − 3)`), as kerns.
    // PDFKit kept the space after the sign and dropped the one before (#188: `− 5+ (− 3)`, `add 5+ 3`).
    #expect(try operatorRepairs(seven) == [
        "− 5+ (− 3)": "− 5 + ( − 3)",
        "Same sign, add 5+ 3, keep the negative": "Same sign, add 5 + 3, keep the negative",
        "− 7+ (− 5)": "− 7 + ( − 5)",
        "Same sign, add 7+ 5, keep the negative": "Same sign, add 7 + 5, keep the negative",
        "− 7+ 2": "− 7 + 2",
        "Diﬀerent signs, subtract 7− 2, use sign from bigger number, negative":
            "Diﬀerent signs, subtract 7 − 2, use sign from bigger number, negative",
        "− 4+ 6": "− 4 + 6",
        "Diﬀerent signs, subtract 6− 4, use sign from bigger number, positive":
            "Diﬀerent signs, subtract 6 − 4, use sign from bigger number, positive",
    ])
    let repaired = try operatorRepairs(eight)
    #expect(repaired == [
        "4+(− 3)": "4 + ( − 3)",
        "Diﬀerent signs, subtract 4− 3, use sign from bigger number, positive":
            "Diﬀerent signs, subtract 4 − 3, use sign from bigger number, positive",
        "7+(− 10)": "7 + ( − 10)",
        "Diﬀerent signs, subtract 10− 7, use sign from bigger number, negative":
            "Diﬀerent signs, subtract 10 − 7, use sign from bigger number, negative",
        "8− 3": "8 − 3",
        "8+(− 3)": "8 + ( − 3)",
        "Diﬀerent signs, subtract 8− 3, use sign from bigger number, positive":
            "Diﬀerent signs, subtract 8 − 3, use sign from bigger number, positive",
        "− 4− 6": "− 4 − 6",
        "− 4+ (− 6)": "− 4 + ( − 6)",
        "Same sign, add 4+ 6, keep the negative": "Same sign, add 4 + 6, keep the negative",
        "9− (− 4)": "9 − ( − 4)",
        "9 +4": "9 + 4",
        "Add the opposite of− 4": "Add the opposite of − 4",
        "Same sign, add 9+ 4, keep the positive": "Same sign, add 9 + 4, keep the positive",
        "− 6− (− 2)": "− 6 − ( − 2)",
        "− 6 +2": "− 6 + 2",
        "Add the opposite of− 2": "Add the opposite of − 2",
        "Diﬀerent sign, subtract 6− 2, use sign from bigger number, negative":
            "Diﬀerent sign, subtract 6 − 2, use sign from bigger number, negative",
    ])
    // #189: no line gains a space after its ﬀ ligature, whose in-word gap is a kern (−0.005 to 0.017 em).
    #expect(repaired.values.allSatisfy { !$0.contains("\u{FB00} ") })
    #expect(eight.lines.filter { $0.text.contains("Diﬀerent") }.count == 4)
    // Negative controls on the same source. Example 1's `5|+` adjustment at 0.12 em (below the thin
    // space) leaves that boundary as PDFKit read it while the other signs gain their spaces; Ghostscript
    // sets no character or word spacing, so none of this depends on #119's producer condition.
    let example = "[(5)-162.863(+)-171.939(\\()159.952]TJ"
    #expect(seven.operators.contains(example) && !seven.operators.contains(" Tc") && !seven.operators.contains(" Tw"))
    let kern = try operatorRepairs(seven, operators: seven.operators.replacingOccurrences(of: example, with: "[(5)-120(+)-171.939(\\()159.952]TJ"))
    #expect(kern["− 5+ (− 3)"] == "− 5+ ( − 3)")
    // The same adjustments between digits record nothing: only a boundary beside an operator is read.
    let shows = try operatorEvidence(seven)
    #expect(shows.first { $0.unicode == "5+(" }.map { $0.operatorGaps.keys.sorted() } == [1, 2])
    #expect(shows.allSatisfy { !$0.spaced && $0.wordSpaces.isEmpty })
    let digits = try operatorEvidence(seven, operators: seven.operators.replacingOccurrences(of: example, with: "[(5)-162.863(7)-171.939(\\()159.952]TJ"))
    #expect(digits.first { $0.unicode == "57(" }?.operatorGaps.isEmpty == true)
}

@Test func replayCaptionsSpaceTheirRelationsAndKeepTheOneTheAuthorsSetClosed() throws {
    let source = try OperatorSource.load("replay-7")
    #expect(source.sourceSHA256 == (try SourceLayoutFixture.load("replay-1")).sourceSHA256)
    let page = try #require(source.pages.first)
    // pdfLaTeX sets a relation's thick space as the gap between shows: 0.285 em after `𝑛` (LibertineMathMI)
    // before `=` (txmiaX), which PDFKit dropped. Caption (e) is set `𝑛=` at 0.035 em in the source and
    // stays so, beside five siblings that gain the space (render reviewed in the record). The page's
    // other repairs are #43's font-change word spaces (`Ewhile`), which hold no operator.
    let repaired = try operatorRepairs(page).filter { $0.key.unicodeScalars.contains(where: NativeSpacingReader.mathOperators.contains) }
    #expect(repaired == [
        "(a) 𝛼 = 20 messages/s, 𝑛= 32.": "(a) 𝛼 = 20 messages/s, 𝑛 = 32.",
        "(b) 𝛼 = 40 messages/s, 𝑛= 32.": "(b) 𝛼 = 40 messages/s, 𝑛 = 32.",
        "(c) 𝛼 = 160 messages/s, 𝑛= 32.": "(c) 𝛼 = 160 messages/s, 𝑛 = 32.",
        "(d) 𝛼 = 20 messages/s, 𝑛= 64.": "(d) 𝛼 = 20 messages/s, 𝑛 = 64.",
        "Figure 5: 𝜏 vs Ewhen varying 𝐼, 𝛿= 8𝜇𝑠.": "Figure 5: 𝜏 vs E when varying 𝐼, 𝛿 = 8𝜇𝑠.",
        "(f) 𝛼 = 160 messages/s, 𝑛= 64.": "(f) 𝛼 = 160 messages/s, 𝑛 = 64.",
        "in the simulation to ensure that if E= 1𝑚𝑠 then the worst-case": "in the simulation to ensure that if E = 1𝑚𝑠 then the worst-case",
    ])
    #expect(page.lines.contains { $0.text.hasPrefix("(e) 𝛼 = 40 messages/s, 𝑛= 64.") })
}

@Test func whetherASignStandsApartDoesNotDecideThatARowIsProse() {
    // Wallace page 89's paragraph beside its coordinate plane, every line on one measure. Its last
    // line was `representing x =1, 2, 3.` as PDFKit spaced it; with both math spaces read, a sign
    // counted as a token of its own tipped the row under isWordy's 40% and into a formula crop.
    func line(_ text: String, _ y: CGFloat) -> TextLine {
        TextLine(text: text, rect: CGRect(x: 400, y: y, width: 300, height: 12), fontSize: 12)
    }
    let paragraph = [line("The plane is divided into four sections by a horizontal", 700),
                     line("number line and a vertical number line. Where the two", 688),
                     line("lines meet in the center is called the origin. This center", 676),
                     line("origin is where x = 0 and y = 0. As we move to the right", 664)]
    for text in ["from zero, representing x =1, 2, 3....", "from zero, representing x = 1, 2, 3....",
                 "from zero, representing x=1, 2, 3....", "from zero, representing x = 1 , 2 , 3 ...."] {
        let row = line(text, 652)
        #expect(LayoutReconstructor.isProseRow(row, in: paragraph + [row], body: 12) == !text.contains(" , "), "\(text)")
    }
    // Controls on the same measure: terms still count, so a row of arithmetic with two words is not
    // prose however its signs are spaced, and neither is a derivation step.
    for text in ["the sum 3 + 4 = 7 + 1 = 8 − 2", "the sum 3+ 4= 7+ 1= 8− 2", "x = 1; y = 2(1) − 3 = 2 − 3 = − 1"] {
        let row = line(text, 652)
        #expect(!LayoutReconstructor.isProseRow(row, in: paragraph + [row], body: 12), "\(text)")
    }
}

// #177: 9/11 pages 254, 259 and 438 set one justified show across a row PDFKit returns as two
// lines (`…each had arrived.Hawsawi ` and `told`; `ning for what later became ` and `the 9/11
// attack.At the time…`; `…the agencies,to conduct oversight of ` and `the intel-`), so neither
// piece is spelled by the shows it holds and #119's word space had no line to go in. Read as
// pieces of their row, each piece takes the spaces inside its own text. Every insertion was read
// on the source render (split-rows-and-soft-hyphens record).
@Test func nineElevenSplitRowsTakeTheirRowsWordSpaces() throws {
    let source = try NineElevenSource.load("911-split-row-operators")
    #expect(source.sourceSHA256 == (try NineElevenSource.load()).sourceSHA256)
    // Page 455 is the appendix's list of names, where one show runs from the name column into the
    // description column 38 points to its right (`Eyad al Rababah` / `Jordanian;Virginia resident…`).
    let expected: [Int: [String]] = [254: ["arrived. Hawsawi"], 259: ["attack. At"], 438: ["agencies, to"],
                                     455: ["Jordanian; Virginia", "(a.k.a. Abu", "(a.k.a. Abu", "(a.k.a. Abu"]]
    for page in source.pages {
        let rows = try nineElevenRepairs(page, rows: true)
        let alone = try nineElevenRepairs(page)
        let gained = rows.pairs.filter { !alone.pairs.contains($0) }
        #expect(gained == expected[page.page] ?? ["page missing"], "page \(page.page)")
        // Without the row the same pieces take no space at all: the defect.
        #expect(!alone.pairs.contains { expected[page.page]?.contains($0) == true }, "page \(page.page)")
        // Every other line reads exactly as it does alone: the row reading adds only what a piece lacks.
        #expect(zip(rows.text, alone.text).filter { $0 != $1 }.count == expected[page.page]?.count, "page \(page.page)")
    }
    // Page 254's `told` owns no show; its row puts no space in it.
    let page254 = try #require(source.pages.first { $0.page == 254 })
    let told = try #require(page254.lines.firstIndex { $0.text == "told" })
    #expect(try nineElevenRepairs(page254, rows: true).text[told] == "told")
}

// The row reading's own conditions (#177), on one show `…had arrived.Hawsawi told ` whose word
// space at `.|H` PDFKit's split leaves in the first of two pieces.
@Test func rowPieceSpacesNeedTheWholeRowSpelledByShowsItOwns() {
    let text = "check that each had arrived.Hawsawi told "
    let space = text.utf16.count - "Hawsawi told ".utf16.count
    let show = NativeSpacingReader.Evidence(origin: CGPoint(x: 40, y: 67.7), text: text, unicode: text, end: 354.5,
                                            size: 10.25, font: 1, wordSpaces: [space], spaced: true)
    let first = CGRect(x: 39.66, y: 65.35, width: 291.97, height: 9.29)
    func repaired(_ pieces: [(String, CGRect)], _ shows: [NativeSpacingReader.Evidence] = [show],
                  texts: Bool = true) -> [String] {
        pieces.map { piece in
            NativeSpacingReader.apply(shows, to: NSAttributedString(string: piece.0), bounds: piece.1,
                                      allBounds: pieces.map(\.1), allTexts: texts ? pieces.map(\.0) : []).string
        }
    }
    let told = ("told", CGRect(x: 335.87, y: 65.35, width: 15.81, height: 9.29))
    #expect(repaired([("check that each had arrived.Hawsawi ", first), told])
        == ["check that each had arrived. Hawsawi ", "told"])
    // Controls. Without the row's texts, the pieces stay as PDFKit read them (the pre-#177 reading).
    #expect(repaired([("check that each had arrived.Hawsawi ", first), told], texts: false)
        == ["check that each had arrived.Hawsawi ", "told"])
    // A second piece further than a line's height away is not the same row's, unless the show
    // measures past its start by more than that height.
    let far = ("told", CGRect(x: 350, y: 65.35, width: 15.81, height: 9.29))
    #expect(repaired([("check that each had arrived.Hawsawi ", first), far])[0] == "check that each had arrived.Hawsawi ")
    var longer = show
    longer.end = 370
    #expect(repaired([("check that each had arrived.Hawsawi ", first), far], [longer])[0]
        == "check that each had arrived. Hawsawi ")
    // A piece on another baseline is not.
    let lower = ("told", CGRect(x: 335.87, y: 60, width: 15.81, height: 9.29))
    #expect(repaired([("check that each had arrived.Hawsawi ", first), lower])[0] == "check that each had arrived.Hawsawi ")
    // The pieces must be what the show spells: a second piece with other text refuses the row.
    let other = ("said", told.1)
    #expect(repaired([("check that each had arrived.Hawsawi ", first), other])[0] == "check that each had arrived.Hawsawi ")
    // A show whose origin two line rectangles hold is not the row's to read.
    let overlapping = ("check that each", CGRect(x: 39, y: 65.35, width: 80, height: 9.29))
    #expect(repaired([("check that each had arrived.Hawsawi ", first), told, overlapping])[0]
        == "check that each had arrived.Hawsawi ")
}

// #177: *Our Flag* maps its line-end hyphen to U+00AD, and PDFKit leaves the character out of the
// line, so `…did not become a real` over `ity until June 20, 1782.` read as two words. The show the
// page draws ends in the soft hyphen; the line gets it back, and the join removes it as it removes
// every soft hyphen (`joinOperation`).
@Test func aSoftHyphenPDFKitDropsAtTheLineEndIsRestored() {
    let drawn = "beliefs, values, and sovereignty of the new Nation, did not become a real\u{00AD}"
    let show = NativeSpacingReader.Evidence(origin: CGPoint(x: 64, y: 499.2), text: drawn, unicode: drawn, end: 369.02,
                                            size: 9, font: 1, spaced: true)
    let bounds = CGRect(x: 64, y: 496.95, width: 302.02, height: 8.87)
    func line(_ native: String, _ shows: [NativeSpacingReader.Evidence] = [show]) -> String {
        NativeSpacingReader.apply(shows, to: NSAttributedString(string: native), bounds: bounds, allBounds: [bounds]).string
    }
    let native = "beliefs, values, and sovereignty of the new Nation, did not become a real"
    #expect(line(native) == native + "\u{00AD}")
    #expect(NativeSpacingReader.droppedSoftHyphen(native, shows: [show]))
    // PDFKit's line break where the page draws a space glyph (page 25's `ner\nwhatsoever.`) is
    // whitespace for whitespace.
    let broken = "ner whatsoever. It should not be embroidered on such articles as cush\u{00AD}"
    let second = NativeSpacingReader.Evidence(origin: CGPoint(x: 82, y: 415.4), text: broken, unicode: broken, end: 369,
                                              size: 9, font: 1, spaced: true)
    #expect(NativeSpacingReader.droppedSoftHyphen("ner\nwhatsoever. It should not be embroidered on such articles as cush",
                                                  shows: [second]))
    // Controls: a line PDFKit read with its hyphen, a show that ends in a letter, a line the show
    // does not spell, and a soft hyphen after something other than a letter.
    #expect(line(native + "\u{00AD}") == native + "\u{00AD}")
    let plain = NativeSpacingReader.Evidence(origin: show.origin, text: String(drawn.dropLast()),
                                             unicode: String(drawn.dropLast()), end: 366, size: 9, font: 1, spaced: true)
    #expect(line(native, [plain]) == native)
    #expect(line("beliefs, values, and sovereignty of the old Nation, did not become a real") != native + "\u{00AD}")
    let dash = NativeSpacingReader.Evidence(origin: show.origin, text: "1776–\u{00AD}", unicode: "1776–\u{00AD}", end: 100,
                                            size: 9, font: 1, spaced: true)
    #expect(!NativeSpacingReader.droppedSoftHyphen("1776–", shows: [dash]))
    // The layout's join removes the restored soft hyphen as it removes every one.
    var warnings: [ConversionWarning] = []
    let lines = [TextLine(text: native + "\u{00AD}", rect: bounds, fontSize: 9),
                 TextLine(text: "ity until June 20, 1782.", rect: CGRect(x: 64, y: 485, width: 100, height: 8.87), fontSize: 9)]
    let page = PageContent(number: 47, bounds: CGRect(x: 0, y: 0, width: 423, height: 652), lines: lines, graphics: [])
    let text = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings).map(\.text)
    #expect(text.contains { $0.contains("did not become a reality until June 20, 1782.") })
    #expect(!warnings.contains { $0.code == .uncertainHyphen })
}
