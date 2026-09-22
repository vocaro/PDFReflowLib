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

// MARK: - The shows a line holds beside ones it does not (#258)

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/258"))
func aShowTwoLineRectanglesHoldIsAHoleRatherThanTheEndOfTheLine() throws {
    // Three shows on one baseline, the middle one also inside a second rectangle. The line keeps
    // the two it alone holds and reads the third as a hole: nothing of its own, and no boundary
    // computed against it, because the line may not have drawn it.
    let line = CGRect(x: 0, y: 100, width: 200, height: 12)
    let neighbor = CGRect(x: 40, y: 104, width: 40, height: 12)
    let shows = [CGPoint(x: 10, y: 102), CGPoint(x: 50, y: 106), CGPoint(x: 120, y: 102)].map {
        NativeSpacingReader.Evidence(origin: $0, text: "x", unicode: "x", end: $0.x + 6, size: 12, font: 1,
                                     wordSpaces: [1], sentenceSpaces: [1])
    }
    let held = NativeSpacingReader.heldShows(shows, bounds: line, allBounds: [line, neighbor])
    #expect(held.count == 3)
    #expect(held.map(\.origin) == shows.map(\.origin))
    #expect(held.map(\.unicode) == ["x", nil, "x"])
    #expect(held.map(\.end) == [16, nil, 126])
    #expect(held.map(\.wordSpaces) == [[1], [], [1]])
    #expect(held.map(\.sentenceSpaces) == [[1], [], [1]])
    // The predecessor rule refuses the whole line for the same geometry, which is #258's defect.
    #expect(NativeSpacingReader.anchoredShows(shows, bounds: line, allBounds: [line, neighbor]) == nil)
    #expect(NativeSpacingReader.anchoredShows(shows, bounds: line, allBounds: [line])?.count == 3)
    // A rectangle every show is ambiguous in holds only holes, and so supplies no evidence at all.
    #expect(NativeSpacingReader.heldShows(shows, bounds: line, allBounds: [line, line]).allSatisfy { $0.unicode == nil })
    #expect(NativeSpacingReader.line(of: NativeSpacingReader.heldShows(shows, bounds: line, allBounds: [line, line])).source.isEmpty)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/258"))
func sourceLineWhoseRectangleHoldsAnotherRowsShowsStillAppliesItsOwn() throws {
    // Wallace page 281's `Convert 8cubic feet to yd3 …` carries an exponent and two stacked
    // fractions, so PDFKit's rectangle for it is 69 points tall and holds the origins of eight
    // shows belonging to the fraction rows drawn inside it. The line's own shows spell its text
    // and place the `8|cubic` font change at 0.16 em, which the rules already admit.
    let changed = try changedLines(spacing: "algebra-281", layout: "algebra-281")
    #expect(changed == ["Convert 8cubic feet to yd3 Write 8ft3 as fraction, put it over 1":
                        "Convert 8 cubic feet to yd3 Write 8ft3 as fraction, put it over 1"])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/258"))
func sourceSuperscriptSharedByTwoLineRectanglesLeavesEachLineItsOwnReading() throws {
    // Wallace page 186 raises `b0`'s exponent into the rectangle of the line above it, so that one
    // show lies in both rectangles and both lines refused every boundary they held. The line that
    // holds the `3|and` font change now applies it; the two lines that share the exponent read it
    // as a hole and keep the text PDFKit gave them, because neither can say it drew it.
    let changed = try changedLines(spacing: "algebra-186", layout: "algebra-186")
    #expect(changed == [
        "2 Move 3and b to denominator because of negative exponents":
            "2 Move 3 and b to denominator because of negative exponents",
        // The page's one line whose rectangle holds nothing else, repaired since #120.
        "Move 2with negative exponent down and z0 =1": "Move 2 with negative exponent down and z0 =1",
    ])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/258"))
func sourceChartRowWhoseRectangleHoldsTheRowBelowSeparatesItsOwnColumns() throws {
    // A positive control from the other producer: the FAA handbook's page 459 performance chart,
    // whose rows PDFKit reads as overlapping rectangles. `Spc Range` runs two of its own cells
    // together at a character-spaced column gap, which #120's rule already measures; the row
    // refused it because the row beneath reaches into its rectangle.
    // Every other line of the chart page, numbers and prose alike, comes back as it already did:
    // the four column gaps #120 already separated, and nothing else.
    #expect(try changedLines(spacing: "faa-459", layout: "faa-459") == [
        "Spc Range 0.165 0.1780.199": "Spc Range 0.165 0.178 0.199",
        "M0.82M0.80 M0.74": "M0.82 M0.80 M0.74",
        "290Speed": "290 Speed",
        "390Speed 459 424": "390 Speed 459 424",
        "FL290 FL310FL330 FL350FL370 FL390": "FL290 FL310 FL330 FL350 FL370 FL390",
    ])
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

// MARK: - One number the page draws in two shows (#274)

/// Two shows of one font on one baseline, the first ending in a digit and the second opening with
/// one, at the gap and the font's own space width, in em, of the 10-point type FAA page 416 sets.
private func closesNumber(gap: CGFloat, space: CGFloat? = 0.25, left: String = "2", right: String = "5",
                          size: CGFloat = 10, rightSize: CGFloat = 10, rightFont: Int = 1,
                          raise: CGFloat = 0) -> Bool {
    let end: CGFloat = 551.64, x = end + gap * max(size, rightSize)
    let previous = NativeSpacingReader.Evidence(origin: CGPoint(x: 501, y: 359.57), unicode: left, end: end,
                                                size: size, font: 1, spaceWidth: space)
    let show = NativeSpacingReader.Evidence(origin: CGPoint(x: x, y: 359.57 + raise), unicode: right,
                                            end: x + 5, size: rightSize, font: rightFont, spaceWidth: space)
    return NativeSpacingReader.closesNumber(previous, show, end: end)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/274"))
func aNumberDrawnInTwoShowsClosesOnlyBelowTheSpaceItsOwnFontDraws() {
    // FAA page 416's own measurement: 1.34 pt over a 10-point size against a 0.25 em space.
    #expect(closesNumber(gap: 0.134))
    // The space the page draws is the threshold, read from either side of it.
    #expect(closesNumber(gap: 0.249))
    #expect(!closesNumber(gap: 0.25))
    #expect(!closesNumber(gap: 0.3))
    // The next digit-to-digit boundary the corpus draws, FAA page 458's chart columns at 0.787 em
    // over a 0.218 em space, is a column gap and stays one.
    #expect(!closesNumber(gap: 0.787, space: 0.218))
    // Shows that touch or overlap state no gap to measure and are not this defect.
    #expect(!closesNumber(gap: 0))
    #expect(!closesNumber(gap: -0.05))
    // A font that states no space, or states none wider than nothing, states nothing here: that is
    // every TeX font of Wallace's algebra, which draws no space glyph at all.
    #expect(!closesNumber(gap: 0.134, space: nil))
    #expect(!closesNumber(gap: 0.134, space: 0))
    // Only two digits close. A number against a word, or a word against a number, is what #120's
    // font-change rule weighs, and the mirror rule must never reach it.
    #expect(!closesNumber(gap: 0.134, left: "5", right: "q"))
    #expect(!closesNumber(gap: 0.134, left: "q", right: "5"))
    #expect(!closesNumber(gap: 0.134, left: "r", right: "e"))
    #expect(!closesNumber(gap: 0.134, left: ".", right: "2"))
    #expect(!closesNumber(gap: 0.134, left: "2", right: "."))
    #expect(!closesNumber(gap: 0.134, left: ",", right: "M"))
    // A font change, a size change or another baseline is another kind of boundary, not this one.
    #expect(!closesNumber(gap: 0.134, rightFont: 2))
    #expect(!closesNumber(gap: 0.134, rightSize: 8))
    #expect(!closesNumber(gap: 0.134, raise: 2))
    // Within a tenth of the size is one baseline still, and a rounding of the size is one size.
    #expect(closesNumber(gap: 0.134, raise: 0.9))
    #expect(closesNumber(gap: 0.134, rightSize: 9.95))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/274"))
func aClosedSpaceIsRemovedOnlyWhereTheShowsSpellTheWholeLine() {
    // The page carries the cursor from cell to cell with runs of space glyphs and PDFKit reports
    // one space for a run, so on such a row the source draws whitespace the extraction does not.
    // Ownership for a removal is therefore whole-line and blind to whitespace on both sides.
    let source = Array("MH     Under 50         25".utf16)
    let extracted = Array("MH Under 50 2 5".utf16)
    #expect(NativeSpacingReader.closedSpaces(in: extracted, source: source, closures: [25]) == [13])
    // The segmented walk cannot own this line at all: the longest anchor between the two readings
    // is the nine characters of `Under 50 `, against an anchor length of twelve.
    #expect(NativeSpacingReader.resynchronize(source: source, at: 3, extracted: extracted, at: 3) == nil)
    // A closure the shows do not place, or a line they do not spell, removes nothing.
    #expect(NativeSpacingReader.closedSpaces(in: extracted, source: source, closures: []).isEmpty)
    #expect(NativeSpacingReader.closedSpaces(in: extracted, source: source, closures: [24]).isEmpty)
    #expect(NativeSpacingReader.closedSpaces(in: Array("MH Under 50 2 51".utf16), source: source, closures: [25]).isEmpty)
    #expect(NativeSpacingReader.closedSpaces(in: Array("MH Under 5O 2 5".utf16), source: source, closures: [25]).isEmpty)
    #expect(NativeSpacingReader.closedSpaces(in: Array("MH Under 50 25".utf16), source: source, closures: [25]).isEmpty)
    // Two spaces where the page draws none is not one space PDFKit inserted, and is left alone.
    #expect(NativeSpacingReader.closedSpaces(in: Array("MH Under 50 2  5".utf16), source: source, closures: [25]).isEmpty)
    // The source must draw the two characters against each other: whitespace of its own beside the
    // closure means the space PDFKit read is the page's.
    #expect(NativeSpacingReader.closedSpaces(in: extracted, source: Array("MH     Under 50         2 5".utf16),
                                             closures: [26]).isEmpty)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/274"))
func sourceTableRowWhoseNumberIsDrawnInTwoShowsReadsItAsOneNumber() throws {
    // FAA page 416's NDB service-volume table sets the `MH` row's `25` as `(       2)Tj` and
    // `(5)Tj`, the second 1.34 points past the first's last glyph over a 10-point size, and PDFKit
    // reads a space there. Every other row of the same table is one show per cell and already
    // reads correctly; the page's other 91 lines come back exactly as PDFKit read them.
    #expect(try changedLines(spacing: "faa-416", layout: "faa-416") == [
        "MH Under 50 2 5": "MH Under 50 25",
    ])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/274"))
func sourceAlgebraPagesKeepEveryNumberTheySetSideBySide() throws {
    // #119's standing control, held against the mirror rule. Wallace's TeX fonts state no width for
    // the space character, or state zero, so no boundary of this book can close: the quadratic
    // formula's own kerns, the worked examples that set one number against another, and the
    // `8cubic` and `3and` font changes the rules already admit all read exactly as they did.
    #expect(try changedLines(spacing: "algebra-343", layout: "algebra-343").isEmpty)
    #expect(try changedLines(spacing: "algebra-281", layout: "algebra-281") == [
        "Convert 8cubic feet to yd3 Write 8ft3 as fraction, put it over 1":
            "Convert 8 cubic feet to yd3 Write 8ft3 as fraction, put it over 1"])
    #expect(try changedLines(spacing: "algebra-186", layout: "algebra-186") == [
        "2 Move 3and b to denominator because of negative exponents":
            "2 Move 3 and b to denominator because of negative exponents",
        "Move 2with negative exponent down and z0 =1": "Move 2 with negative exponent down and z0 =1",
    ])
}
