import Foundation
import Testing
@testable import PDFReflowLib

// Wrapped body lines that begin with an initial, a citation abbreviation or a year followed by
// a period must continue their paragraph (#39). Genuine numbered and lettered lists stay separate.

private let loperBrightSHA256 = "12f5ea075004886774c25e7831ea1608fd0f831f0113e83bb0e85811c0a4bb6e"

private func reconstruct(_ page: PageContent) -> [ReflowBlock] {
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings)
}

private func paragraphs(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .paragraph = $0.content { return $0.text } else { return nil } }
}

private func preformatted(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .preformatted = $0.content { return $0.text } else { return nil } }
}

// Source-reviewed wrapped lines: each token-leading line and the text around it come from the
// pinned slip opinion, not from converter output. Hyphenated wraps stay literal without a book vocabulary.
@Test(arguments: [
    ("loper-60", "U. S. 967, 982–983 (2005). And those officials may even dis-",
     ["Telecommunications Assn. v. Brand X Internet Services, 545 U. S. 967, 982–983 (2005). And those officials may even dis-agree with",
      "a court’s past interpretation as well. Ibid. None of that is consistent with the APA’s clear mandate."]),
    ("loper-7", "2016. But because Chevron remains on the books, litigants must con-",
     ["has not deferred to an agency interpretation under Chevron since 2016. But because Chevron remains on the books, litigants must con-tinue to wrestle"]),
    ("loper-13", "F. 4th 359 (2022). The majority addressed various provi-",
     ["A divided panel of the D. C. Circuit affirmed. See 45 F. 4th 359 (2022). The majority addressed various provi-sions of the MSA"]),
    ("loper-2", "v. Moore, 95 U. S. 760, 763. “Respect,” though, was just that. The",
     ["who may well have drafted the laws at issue. United States v. Moore, 95 U. S. 760, 763. “Respect,” though, was just that. The views of the Executive Branch",
      "United States v. Morton Salt Co., 338 U. S. 632, 644, the Court often treated agency determinations of fact",
      "Skidmore v. Swift & Co., 323 U. S. 134, 140."]),
])
func loperBrightCitationLinesContinueTheirParagraphs(name: String, wrapped: String, joined: [String]) throws {
    let fixture = try SourceLayoutFixture.load(name)
    #expect(fixture.sourceSHA256 == loperBrightSHA256)
    let page = fixture.content()
    #expect(page.lines.contains { $0.text == wrapped })
    let blocks = reconstruct(page)
    #expect(preformatted(blocks).isEmpty)
    for phrase in joined {
        #expect(paragraphs(blocks).contains { $0.contains(phrase) }, "missing \(phrase)")
    }
    // Every source line still contributes its characters; joining cannot drop text.
    let text = blocks.map(\.text).joined(separator: " ")
    #expect(text.filter { !$0.isWhitespace }.sorted() == page.lines.flatMap { $0.text.filter { !$0.isWhitespace } }.sorted())
}

@Test func loperBrightPageTwoKeepsItsFourSourceParagraphs() throws {
    let fixture = try SourceLayoutFixture.load("loper-2")
    var page = fixture.content()
    page.lines.removeAll { $0.text == "2 LOPER BRIGHT ENTERPRISES v. RAIMONDO" || $0.text == "Syllabus" }
    let body = paragraphs(reconstruct(page))
    let openings = ["that the final “interpretation of the laws”", "The Court recognized from the outset",
                    "During the “rapid expansion", "Occasionally during this period"]
    let endings = ["Decatur v. Paulding, 14 Pet. 497, 515.", "United States v. Dickson, 15 Pet. 141, 162.",
                   "Skidmore v. Swift & Co., 323 U. S. 134, 140.", "specific facts found by"]
    #expect(body.count == 4)
    for (index, paragraph) in body.enumerated() where index < 4 {
        #expect(paragraph.hasPrefix(openings[index]))
        #expect(paragraph.hasSuffix(endings[index]))
    }
}

// Synthetic justified prose: a 460-point column whose lines reach the same right edge.
private func column(_ texts: [String], x: Double = 60, top: Double = 700, pitch: Double = 14,
                    widths: [Double]? = nil, indents: [Double]? = nil) -> [TextLine] {
    texts.enumerated().map { index, text in
        let width = widths?[index] ?? 460
        let indent = indents?[index] ?? 0
        return TextLine(text: text, rect: CGRect(x: x + indent, y: top - Double(index) * pitch, width: width - indent, height: 12),
                        fontSize: 12)
    }
}

@Test func authorInitialsAndYearsContinueJustifiedProse() {
    let lines = column([
        "The committee reviewed the position paper prepared during the previous session by",
        "A. Smith and B. Jones, who summarised the field work completed at the end of",
        "1998. The final report was accepted without amendment by all of the delegates",
        "v. the objections raised earlier, and the chair closed the meeting.",
    ], widths: [460, 460, 460, 300])
    let blocks = reconstruct(lines)
    #expect(preformatted(blocks).isEmpty)
    #expect(paragraphs(blocks).count == 1)
    #expect(paragraphs(blocks).first?.contains("session by A. Smith and B. Jones, who summarised the field work completed at the end of 1998. The final") == true)
}

@Test func numberedListAfterAShortIntroductionStaysSeparate() {
    // The introduction is not terminal, but it does not fill the column.
    let lines = column(["The three factors are", "1. cost of the material", "2. delivery time", "3. warranty"],
                       widths: [180, 200, 150, 120])
    let blocks = reconstruct(lines)
    #expect(paragraphs(blocks) == ["The three factors are"])
    #expect(preformatted(blocks) == ["1. cost of the material", "2. delivery time", "3. warranty"])
}

@Test func numberedListAfterAFullTerminalLineStaysSeparate() {
    for ending in ["as follows:", "the steps.", "the steps.”", "the steps.)", "steps?", "steps!"] {
        let lines = column([
            "Justified prose that fills the whole measure of the column and then introduces",
            "another full line that also reaches the right margin before listing " + ending,
            "1. First step in the procedure that follows the introduction",
            "2. Second step in the procedure",
            "a. A lettered sub-step",
        ], widths: [460, 460, 300, 200, 150])
        let blocks = reconstruct(lines)
        #expect(paragraphs(blocks).count == 1)
        #expect(preformatted(blocks).map { String($0.prefix(2)) } == ["1.", "2.", "a."], Comment(rawValue: ending))
    }
}

@Test func separatedOrIndentedItemsAfterAFullLineStaySeparate() {
    let base = [
        "Justified prose that fills the whole measure of the column and then continues",
        "with another full line that also reaches the right margin without any period",
        "1. First item that is not a wrapped continuation of the prose above it",
    ]
    // A paragraph gap before the item.
    var gapped = column(base)
    gapped[2].rect.origin.y -= 12
    #expect(preformatted(reconstruct(gapped)).count == 1)
    // A marker indented by half a body size or more.
    let indented = column(base, indents: [0, 0, 8])
    #expect(preformatted(reconstruct(indented)).count == 1)
    // An OCR line that Vision says does not wrap.
    var ocr = column(base)
    ocr[1].wraps = false
    #expect(preformatted(reconstruct(ocr)).count == 1)
    // The same geometry without those signals joins.
    #expect(preformatted(reconstruct(column(base))).isEmpty)
    #expect(paragraphs(reconstruct(column(base))).count == 1)
}

@Test func rightEdgeNeedsThreeSupportingLines() {
    // Two lines alone cannot establish a justified column; the marker stays a list item.
    let lines = column(["A single line of prose that happens to reach the right margin without",
                        "1. a period at the end"], widths: [460, 200])
    #expect(preformatted(reconstruct(lines)) == ["1. a period at the end"])
    // With a third full line on the page the same pair joins.
    let supported = column(["A single line of prose that happens to reach the right margin without",
                            "1. a period at the end, and then more prose that fills the measure again",
                            "and again with a third line that reaches the same right margin before",
                            "ending here with a period."], widths: [460, 460, 460, 200])
    #expect(preformatted(reconstruct(supported)).isEmpty)
    #expect(paragraphs(reconstruct(supported)).count == 1)
}

@Test func bulletsAndHangingMarkersNeverContinueProse() {
    let lines = column([
        "Justified prose that fills the whole measure of the column and then continues",
        "• a bullet at the same left edge without a gap is still a list item, not prose",
        "− a minus-prefixed line is treated the same way as a bullet marker here",
        "- and so is a hyphen marker at the start of a line",
    ])
    #expect(preformatted(reconstruct(lines)).count == 3)
    #expect(paragraphs(reconstruct(lines)).count == 1)
}

@Test func outdentedSecondLineJoinsOnlyAnIndentedOpeningLine() {
    // Loper Bright page 13: an indented opening line followed by "F. 4th 359 (2022)" at the column edge.
    let opening = column([
        "A divided panel of the circuit affirmed the judgment below. See 45",
        "F. 4th 359 (2022). The majority addressed various provisions of the",
        "statute and concluded that the text was not wholly unambiguous, and",
        "the dissent disagreed.",
    ], widths: [460, 460, 460, 180], indents: [12, 0, 0, 0])
    #expect(preformatted(reconstruct(opening)).isEmpty)
    #expect(paragraphs(reconstruct(opening)).count == 1)
    // A dedented note continuation followed by an indented numbered note start stays a list.
    let notes = column([
        "5. See the earlier discussion of the evidence, which fills the whole line and",
        "continues here at the dedented margin without ending in a period, pp. 40",
        "6. The next note begins at the indented margin like every other note start",
    ], widths: [460, 460, 460], indents: [12, 0, 12])
    #expect(preformatted(reconstruct(notes)).map { String($0.prefix(2)) } == ["5.", "6."])
}

// Every source line that carries a list marker on these pages must still be its own block:
// algebra exercises follow short lines, and the Warren points follow terminal short lines.
@Test func algebraExercisesAndWarrenListsRemainPreformatted() throws {
    let algebra = try SourceLayoutFixture.load("algebra-26")
    let exercises = preformatted(reconstruct(algebra.content()))
    let markers = algebra.lines.map(\.text).filter {
        $0.range(of: "^[0-9]+(?:[.)]\\s|\\)−)", options: .regularExpression) != nil
    }
    #expect(markers.count >= 20)
    // Minus-prefixed continuation lines of split exercises keep their existing separate blocks.
    #expect(exercises.filter { !$0.hasPrefix("−") }.sorted() == markers.sorted())
    #expect(exercises.contains("39) 8n(n +9)"))
    #expect(paragraphs(reconstruct(algebra.content())).contains("Distribute"))
    let warren = try SourceLayoutFixture.load("warren-50")
    var page = warren.content()
    page.hasSyntheticTextStyle = true
    let items = preformatted(reconstruct(page))
    #expect(items.count == 2)
    #expect(items.allSatisfy { $0.hasPrefix("10.") || $0.hasPrefix("11.") })
}

private func reconstruct(_ lines: [TextLine]) -> [ReflowBlock] {
    reconstruct(PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines, graphics: []))
}
