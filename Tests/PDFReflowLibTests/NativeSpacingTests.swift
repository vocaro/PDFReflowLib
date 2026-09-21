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
    // Character and word spacing are measured, not refused (#119), but Type3 space removal models
    // neither, so a spaced show supplies no removal evidence. A Form XObject is tolerated: its
    // text is not scanned, so it can neither supply nor contradict a boundary.
    for prefix in ["1 Tc", "1 Tw"] {
        #expect(try spacingEvidence(show, prefix: prefix).first?.text == nil)
    }
    #expect(try spacingEvidence(show, prefix: "/Nested Do").first?.extraSpaces(in: "Dair y") == [4])
    #expect(try spacingEvidence(show + " (again) Tj").isEmpty)
    #expect(try spacingEvidence(show, subtype: "Type1").isEmpty)
    #expect(try spacingEvidence(show, matrix: "0.001 0 0 0.001 0 0").first?.text == nil)
    #expect(try spacingEvidence(show, rotate: 90).isEmpty)
    #expect(try spacingEvidence(show, prefix: "0 1 -1 0 0 0 cm").isEmpty)
    #expect(try spacingEvidence("[(Dair)-5<01>] TJ").first?.text == nil)
}

@Test func sourceSpacingBoundsWorkAndRestoresSavedFontPlacement() throws {
    let show = "[(Dair)-5(y)] TJ"
    // TeX output reselects a font at every mathematical symbol, so the cap is on distinct fonts
    // parsed, not on selections (#120); ten thousand selections of one font still read.
    #expect(try spacingEvidence(show, prefix: String(repeating: "/T3_0 1 Tf ", count: 256))
        .first?.extraSpaces(in: "Dair y") == [4])
    #expect(try spacingEvidence(show, prefix: String(repeating: "/T3_0 1 Tf ", count: 10_001)).isEmpty)
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

// MARK: - The ported reader (#225: #43/#110, #119, #128, #120)

/// Every line of a source page, repaired, beside the text PDFKit read: the rebuilt source page
/// supplies the evidence and the layout capture supplies PDFKit's own lines and rectangles.
private func repairedLines(spacing: String, layout: String) throws -> [(pdfkit: String, repaired: String)] {
    let source = try SpacingSourceFixture.load(spacing), capture = try SourceLayoutFixture.load(layout)
    #expect(source.sourceSHA256 == capture.sourceSHA256)
    #expect(source.page == capture.page)
    let document = try source.document()
    let evidence = NativeSpacingReader.read(try #require(document.page(at: 1)))
    func rect(_ values: [Double]) -> CGRect { CGRect(x: values[0], y: values[1], width: values[2], height: values[3]) }
    let bounds = try capture.attributedLines.map { rect(try #require($0.rect)) }
    return capture.attributedLines.enumerated().map { index, line in
        (line.text, NativeSpacingReader.apply(evidence, to: line.attributedString(), bounds: bounds[index],
                                              allBounds: bounds).string)
    }
}

/// Only the lines the repair changes, as `PDFKit's text` → `repaired text`; every other line must
/// come back exactly as PDFKit read it.
private func changedLines(spacing: String, layout: String) throws -> [String: String] {
    var changed: [String: String] = [:]
    for line in try repairedLines(spacing: spacing, layout: layout) where line.pdfkit != line.repaired {
        changed[line.pdfkit] = line.repaired
    }
    return changed
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/119"),
      .bug("https://github.com/vocaro/PDFReflowLib/issues/128"))
func sourceReportPageRestoresItsDroppedWordAndSentenceSpaces() throws {
    // 9/11 report page 19, the first page of chapter 1: Distiller justified it with character and
    // word spacing and folded each word space into a TJ adjustment, so PDFKit reads none of them.
    #expect(try changedLines(spacing: "911-19", layout: "911-19") == [
        "work.Some made their way to the Twin Towers,the signature structures of the":
            "work. Some made their way to the Twin Towers, the signature structures of the",
        "WorldTrade Center complex in NewYork City.Others went to Arlington,Vir-":
            "World Trade Center complex in New York City. Others went to Arlington, Vir-",
        "ginia, to the Pentagon.Across the Potomac River, the United States Congress":
            "ginia, to the Pentagon. Across the Potomac River, the United States Congress",
        "better for a safe and pleasant journey.Among the travelers were Mohamed Atta":
            "better for a safe and pleasant journey. Among the travelers were Mohamed Atta",
        "Boston:American 11 and United 175. Atta and Omari boarded a 6:00 A.M.":
            "Boston: American 11 and United 175. Atta and Omari boarded a 6:00 A.M.",
        "When he checked in for his flight to Boston,Atta was selected by a com-":
            "When he checked in for his flight to Boston, Atta was selected by a com-",
        "Atta and Omari arrived in Boston at 6:45. Seven minutes later,Atta appar-":
            "Atta and Omari arrived in Boston at 6:45. Seven minutes later, Atta appar-",
        "another terminal at Logan Airport.They spoke for three minutes.3 It would be":
            "another terminal at Logan Airport. They spoke for three minutes.3 It would be",
    ])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/119"))
func sourceAlgebraPageKeepsEveryGapItsFormulasSet() throws {
    // Wallace page 343 (the quadratic formula and its derivation): Ghostscript's TeX output kerns
    // and italic-corrects inside every formula at word-space widths. #119's hard constraint is
    // that none of those gaps becomes a space.
    #expect(try changedLines(spacing: "algebra-343", layout: "algebra-343").isEmpty)
}

// MARK: - Partial-line ownership (#139 item 1)

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/139"))
func sourceRowSplitBetweenTwoPdfkitLinesRepairsTheHalfEachLineHolds() throws {
    // The 9/11 appendix's page 452 sets each entry as one show across two columns, which PDFKit
    // splits into two lines: the name, then the alias and the description. The whole-line walk
    // owns neither half, because each line accounts for only part of the show.
    let changed = try changedLines(spacing: "911-452", layout: "911-452")
    #expect(changed["(a.k.a.Ammar al Baluchi) Pakistani; KSM’s nephew;"]
        == "(a.k.a. Ammar al Baluchi) Pakistani; KSM’s nephew;")
    #expect(changed["(a.k.a.Abu Hafs al Masri) Egyptian; al Qaeda mili-"]
        == "(a.k.a. Abu Hafs al Masri) Egyptian; al Qaeda mili-")
    #expect(changed["Barakat)Yemeni; potential suicide bomber in"] == "Barakat) Yemeni; potential suicide bomber in")
    // The name half of each row keeps its own text: the boundary belongs to the other line.
    #expect(changed["Ali Abdul Aziz Ali "] == nil)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/139"))
func aBoundaryBesideTextTheShowsCannotAccountForIsDropped() {
    let source = Array("the Twin Towers,the signature".utf16)
    let boundaries: Set<Int> = [16]
    // PDFKit read the line whole: the boundary is strictly inside the one agreeing segment.
    #expect(NativeSpacingReader.segmentedInsertions(in: Array("the Twin Towers,the signature".utf16),
                                                    source: source, boundaries: boundaries) == [16])
    // A line PDFKit read only the tail of: the walk resynchronizes and still applies it, where the
    // whole-line walk discards it.
    #expect(NativeSpacingReader.segmentedInsertions(in: Array("Towers,the signature".utf16),
                                                    source: source, boundaries: boundaries) == [7])
    #expect(NativeSpacingReader.wholeLineInsertions(in: Array("Towers,the signature".utf16),
                                                    source: source, boundaries: boundaries) == nil)
    // A character the shows cannot account for at the boundary itself: the character after it
    // never matched, so the boundary is against a disagreeing region and is dropped.
    #expect(NativeSpacingReader.segmentedInsertions(in: Array("the Twin Towers,\u{FFFD}he signature".utf16),
                                                    source: source, boundaries: boundaries) == nil)
    // One character earlier, the boundary is again strictly inside a segment that matched on both
    // sides, so it applies although the rest of the line did not.
    #expect(NativeSpacingReader.segmentedInsertions(in: Array("the Twin Tower\u{FFFD},the signature".utf16),
                                                    source: source, boundaries: boundaries) == [16])
    #expect(NativeSpacingReader.segmentedInsertions(in: Array("th\u{FFFD} Twin Towers,the signature".utf16),
                                                    source: source, boundaries: boundaries) == [16])
    // A space PDFKit already sets at the boundary inserts nothing.
    #expect(NativeSpacingReader.segmentedInsertions(in: Array("the Twin Towers, the signature".utf16),
                                                    source: source, boundaries: boundaries) == nil)
    // Nothing resynchronizes on fewer matching characters than the anchor asks for.
    let anchor = String("abcdefghijklmnopqrstuvwxyz".prefix(NativeSpacingReader.anchorLength))
    #expect(NativeSpacingReader.resynchronize(source: Array(anchor.utf16), at: 0,
                                              extracted: Array(("X" + anchor).utf16), at: 0) != nil)
    #expect(NativeSpacingReader.resynchronize(source: Array(anchor.dropLast().utf16), at: 0,
                                              extracted: Array(("X" + anchor.dropLast()).utf16), at: 0) == nil)
    // A run that recurs earlier in the line must not take the walk to the wrong half of a row:
    // the 9/11 appendix sets `Abu Bara al Yemeni (a.k.a.Abu al Bara al Ta’izi` as one row, and
    // `Bara al ` occurs in both halves. The anchor is long enough to tell them apart (#120).
    let row = Array("Abu Bara al Yemeni (a.k.a.Abu al Bara al Ta’izi,Suhail".utf16)
    let half = Array("(a.k.a.Abu al Bara al Ta’izi, Suhail".utf16)
    #expect(NativeSpacingReader.resynchronize(source: row, at: 0, extracted: half, at: 0)?.0 == 19)
    #expect(NativeSpacingReader.segmentedInsertions(in: half, source: row, boundaries: [26, 48]) == [7])
}

// MARK: - The rules (#119, #128)

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/119"))
func sameFontWordSpaceTakesTheMeasuredThresholds() {
    func space(_ before: Unicode.Scalar?, _ left: Unicode.Scalar, _ right: Unicode.Scalar,
               _ gap: CGFloat, _ after: Unicode.Scalar? = nil) -> Bool {
        NativeSpacingReader.sameFontWordSpace(before: before, left: left, right: right, gap: gap, after: after)
    }
    // Before a letter, kerns end at 0.059 em and word spaces begin at 0.075 em.
    #expect(!space(nil, "r", "s", 0.059))
    #expect(space(nil, "r", "s", 0.075))
    // Before an overhanging capital after a lowercase letter or punctuation, the space's own kern
    // is inside the gap: abbreviations and initials lie at or below 0.001 em.
    #expect(!space(nil, "s", "T", 0.001))
    #expect(space(nil, "s", "T", 0.005))
    // A chained initial (`C.|A.`) takes the letter threshold, as two capitals do.
    #expect(!space("C", ".", "A", 0.03, "."))
    #expect(space("C", ".", "A", 0.03, "n"))
    // Never inside a number or a time, and never beside a mathematical letter.
    #expect(!space("3", ".", "5", 1))
    #expect(!space("8", ":", "4", 1))
    #expect(!space(nil, "\u{1D452}", "m", 1))
    #expect(!space(nil, ".", "\u{1D453}", 1))
    // A gap wider than one em is a column, not a word space; character spacing decides those.
    #expect(!space(nil, "r", "s", 1.01))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/128"))
func sentenceSpaceReadsTheWordsAroundTheBoundaryNotTheGap() {
    func sentence(_ word: String, _ following: String, gap: CGFloat = -0.1, startsShow: Bool = false) -> Bool {
        NativeSpacingReader.sentenceSpace(word: Array(word.unicodeScalars), startsShow: startsShow,
                                          following: Array(following.unicodeScalars), gap: gap)
    }
    #expect(sentence("casualties.", "The "))
    #expect(sentence("Jews.\u{201D}", "The "))
    #expect(sentence("(OMB).", "They "))
    #expect(sentence("FAA:", "Yes. "))
    // A capital continuing an abbreviation is set closed: `U.|S.`, `D.|C.`, `N.|Y.`.
    #expect(!sentence("U.", "S. "))
    #expect(!sentence("H.", "Doc. "))
    #expect(sentence("H.", "Kean "))
    // An apostrophe, an ellipsis and an address are not sentence ends.
    #expect(!sentence("O\u{2019}", "Neill "))
    #expect(!sentence("threat...", "Is "))
    #expect(!sentence("www.usdoj.gov/print.php3?", "ReportID "))
    #expect(!sentence("www.foxnews.com.", "The "))
    // A list or note number that opens the show keeps its period closed.
    #expect(!sentence("10.", "August ", startsShow: true))
    #expect(sentence("10.", "August ", startsShow: false))
    // Mathematics is never a sentence boundary, and a gap of a whole em is not one either.
    #expect(!sentence("\u{1D452}.", "The "))
    #expect(!sentence("casualties.", "The ", gap: 1.01))
    #expect(!sentence("casualties.", "The ", gap: -0.16))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/120"))
func aNumberSetAgainstAWordClosesAtATighterGapThanTheRuleWants() {
    // Wallace sets `8cent stamps` and `Subtract 5from both sides` with a font change and a gap of
    // 0.12 to 0.13 em, where the font-change rule wants 0.15, and left them fused.
    // The longest word that opens the run, which is all the boundary rule needs to know.
    #expect(EnglishText.openingWord("centstamplesas") == "cents")
    #expect(EnglishText.openingWord("timesasmany") == "times")
    #expect(EnglishText.openingWord("frombothsides") == "from")
    #expect(EnglishText.openingWord("placesthen") == "places")
    // Algebra opens with no word, so the same page's `30qpr` and `5q` keep the tighter reading.
    #expect(EnglishText.openingWord("qpr") == nil)
    #expect(EnglishText.openingWord("q") == nil)
    #expect(EnglishText.openingWord("xy") == nil)
    #expect(EnglishText.openingWord("") == nil)
}
