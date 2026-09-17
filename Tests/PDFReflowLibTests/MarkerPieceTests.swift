import Foundation
import Testing
@testable import PDFReflowLib

// A list marker PDFKit splits from its item's text rejoins that text, a numbered marker extracted
// with no space after its period is still a marker among spaced siblings (#69), and a line broken
// after a slash inside a compound or an address continues it without a space (#70).

private let gpo911SHA256 = "657d41475eb3a9a5e3e87a6c7c51ac1dfbe1af7566d1abff7bf7286e7e1c0e1b"

private func blocks(_ page: PageContent, preserveRegions: Bool = true) -> [ReflowBlock] {
    let regions = preserveRegions
        ? LayoutReconstructor.graphicsWithLabels(page).enumerated().map { ($0.element, "image-\($0.offset)") } : []
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: regions, vocabulary: [], warnings: &warnings)
}

private func items(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case let .preformatted(text) = $0.content { return text.text } else { return nil } }
}

private func paragraphs(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case let .paragraph(text) = $0.content { return text.text } else { return nil } }
}

/// The page without its running head, which document-wide furniture removal takes first.
private func body(_ name: String, head: String) throws -> PageContent {
    var page = try SourceLayoutFixture.load(name).content()
    #expect(page.lines.contains { $0.text == head })
    page.lines.removeAll { $0.text == head }
    return page
}

private func line(_ text: String, x: Double, y: Double, width: Double, size: Double = 10) -> TextLine {
    TextLine(text: text, rect: CGRect(x: x, y: y, width: width, height: size * 0.9), fontSize: size)
}

private func page(_ lines: [TextLine]) -> PageContent {
    PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines, graphics: [])
}

private func sources(_ blocks: [ReflowBlock]) -> String {
    blocks.map(\.text).joined(separator: " ").filter { !$0.isWhitespace }
}

// MARK: - Split markers (#69)

@Test func gpo911ItemFourKeepsTheMarkerPDFKitSplitFromItsText() throws {
    #expect(try SourceLayoutFixture.load("911-365").sourceSHA256 == gpo911SHA256)
    let page = try body("911-365", head: "FORESIGHT—AND HINDSIGHT 347")
    // The extraction really does split the marker from its text on one baseline.
    let marker = try #require(page.lines.first { $0.text == "4." })
    #expect(page.lines.contains { $0.text.hasPrefix("Neither the intelligence community") && abs($0.rect.minY - marker.rect.minY) < 0.5 })
    let result = blocks(page)
    let list = items(result)
    try #require(list.map { String($0.prefix(3)) } == ["1. ", "2. ", "3. ", "4. "])
    // Without a book vocabulary the line-ending hyphens stay literal.
    #expect(list[3].hasPrefix("4. Neither the intelligence community nor aviation security experts ana-lyzed systemic defenses"))
    #expect(list[3].hasSuffix("No one in the gov-ernment was taking on that role for domestic vulnerabilities."))
    // No stray marker survives, and the item's indented second paragraph and the prose after the
    // list keep their own blocks.
    #expect(!result.contains { $0.text.trimmingCharacters(in: .whitespaces) == "4." })
    #expect(paragraphs(result).contains { $0.hasPrefix("Richard Clarke told us that he was concerned") })
    #expect(paragraphs(result).contains { $0.hasPrefix("The methods for detecting and then warning of surprise attack") })
    #expect(sources(result).sorted() == page.lines.flatMap { $0.text.filter { !$0.isWhitespace } }.sorted())
}

@Test func faaSplitBulletsOpenTheirOwnItems() throws {
    let fixture = try SourceLayoutFixture.load("faa-27")
    #expect(fixture.sourceSHA256 == "247929cace0ab56b376e683eba540cc4c8f39f199ab35414e8b604e24f395cb7")
    let page = fixture.content()
    #expect(page.lines.filter { $0.text == "•" }.count == 11)
    let result = blocks(page)
    let bullets = items(result).filter { $0.hasPrefix("• ") }
    #expect(bullets.count == 11)
    #expect(bullets.first == "• Hazards, such as air shows, parachute jumps, kite flying, and rocket launches")
    #expect(bullets.contains("• Closed runways"))
    #expect(bullets.last == "• Software code risk announcements with associated patches to reduce specific vulnerabilities")
    // Before, each bullet ended the block above it and its item was an unmarked paragraph.
    #expect(!result.contains { $0.text.hasSuffix("•") })
    #expect(!paragraphs(result).contains { $0.hasPrefix("Hazards, such as") || $0.hasPrefix("Closed runways") })
    #expect(paragraphs(result).contains { $0.hasSuffix("Following are some of those reasons:") })
}

@Test func algebraExerciseNumbersRejoinTheirPointPairs() throws {
    let fixture = try SourceLayoutFixture.load("algebra-101")
    #expect(fixture.sourceSHA256 == "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678")
    let result = blocks(fixture.content())
    let list = items(result)
    #expect(list.contains("17) (− 16,− 14), (11,− 14)"))
    #expect(list.contains("28) (− 18,− 5), (14,− 3)"))
    // Exercises PDFKit did not split are unchanged.
    #expect(list.contains("18) (13, 15), (2, 10)"))
    #expect(!result.contains { ["17)", "28)"].contains($0.text.trimmingCharacters(in: .whitespaces)) })
}

@Test func loperBrightCitationPageNumberSplitOffAJustifiedLineContinuesItsParagraph() throws {
    let fixture = try SourceLayoutFixture.load("loper-5")
    #expect(fixture.sourceSHA256 == "12f5ea075004886774c25e7831ea1608fd0f831f0113e83bb0e85811c0a4bb6e")
    var page = fixture.content()
    page.lines.removeAll { $0.rect.minY > 690 }
    #expect(page.lines.contains { $0.text == "982." })
    let result = blocks(page, preserveRegions: false)
    #expect(items(result).isEmpty)
    #expect(paragraphs(result).contains {
        $0.contains("545 U. S. 967, 982. That regime is the antithesis of the time honored approach the APA prescribes.")
    })
}

@Test func markerPiecesJoinOnlyTheTextThatOpensTheirRow() {
    let text = "Neither the intelligence community nor aviation security experts"
    // Positive: a number, a letter and a bullet, each at the start of its row.
    for marker in ["4.", "b)", "•"] {
        let joined = LayoutReconstructor.joiningMarkerPieces([
            line(marker, x: 56, y: 500, width: 8), line(text, x: 68, y: 500, width: 276)])
        #expect(joined.map(\.text) == ["\(marker) \(text)"])
        #expect(joined.first?.rect.minX == 56)
    }
    let controls: [(String, [TextLine])] = [
        // A number in a table's first column, far from the cell beside it.
        ("table column", [line("4.", x: 56, y: 500, width: 8), line("Name of the witness", x: 120, y: 500, width: 90)]),
        // A marker that closes a sentence piece to its left is not at the start of its row.
        ("mid-row", [line("see paragraph", x: 20, y: 500, width: 30), line("4.", x: 56, y: 500, width: 8),
                     line(text, x: 68, y: 500, width: 276)]),
        // A raised note marker or a different size is not the item's text.
        ("size", [line("4.", x: 56, y: 500, width: 8, size: 6), line(text, x: 68, y: 500, width: 276)]),
        // A minus sign beside a numeral is arithmetic, not a marker.
        ("minus", [line("−", x: 56, y: 500, width: 8), line("5", x: 68, y: 500, width: 6)]),
        // Two marker pieces side by side (an answer grid's empty entries).
        ("two markers", [line("9)", x: 56, y: 500, width: 10), line("10)", x: 70, y: 500, width: 14)]),
        // A marker on another row.
        ("other row", [line("4.", x: 56, y: 500, width: 8), line(text, x: 68, y: 488, width: 276)]),
        // A folio beside a running head is not a marker, and a bare number has no marker form.
        ("folio", [line("347", x: 56, y: 760, width: 16), line("FORESIGHT—AND HINDSIGHT", x: 80, y: 760, width: 200)]),
    ]
    for (name, lines) in controls {
        #expect(LayoutReconstructor.joiningMarkerPieces(lines) == lines, "\(name)")
    }
}

// MARK: - Tight markers (#69)

@Test func gpo911TightTenthItemIsAListItemAmongItsSpacedSiblings() throws {
    #expect(try SourceLayoutFixture.load("911-374").sourceSHA256 == gpo911SHA256)
    let page = try body("911-374", head: "356 THE 9/11 COMMISSION REPORT")
    let result = blocks(page)
    let list = items(result)
    try #require(list.map { String($0.prefix(3)) } == ["6. ", "7. ", "8. ", "9. ", "10."])
    // The source text is kept verbatim: the marker is not rewritten.
    #expect(list.last == "10.August 2001: the CIA and FBI do not connect the presence of Mihdhar, Hazmi, and Moussaoui to the general threat report-ing about imminent attacks.")
    #expect(!paragraphs(result).contains { $0.hasPrefix("10.August") })
    #expect(paragraphs(result).first?.hasPrefix("responsible for making it work.") == true)
}

/// Spaced numbered items 6 to 9 at x 64, then `candidate` on the next row.
private func tightPage(_ candidate: String, x: Double = 64, siblings: [Int] = [6, 7, 8, 9]) -> [ReflowBlock] {
    var lines: [TextLine] = []
    var y = 700.0
    for number in siblings {
        lines.append(line("\(number). August 2001: the FBI does not recognize the significance of", x: 64, y: y, width: 263))
        lines.append(line("the information regarding the meeting that was held abroad.", x: 76, y: y - 11.25, width: 240))
        y -= 22.5
    }
    lines.append(line(candidate, x: x, y: y, width: 263))
    return blocks(page(lines), preserveRegions: false)
}

@Test func tightMarkersNeedSpacedSiblingsOnTheirEdgeAndInSequence() {
    #expect(items(tightPage("10.August 2001: the CIA and FBI do not connect the presence of")).count == 5)
    #expect(items(tightPage("5.August 2001: the CIA and FBI do not connect the presence of")).count == 5)
    // With a single spaced sibling the tight line stays a paragraph.
    let lone = tightPage("10.August 2001: the CIA and FBI do not connect the presence of", siblings: [9])
    #expect(items(lone).count == 1)
    #expect(paragraphs(lone).contains { $0.hasPrefix("10.August 2001") })
    let controls: [(String, [ReflowBlock])] = [
        ("out of sequence", tightPage("12.August 2001: the CIA and FBI do not connect the presence of")),
        ("other edge", tightPage("10.August 2001: the CIA and FBI do not connect the presence of", x: 120)),
        ("decimal", tightPage("10.5 percent of the budget went unspent in the first quarter")),
        ("section number", tightPage("10.1 INSIDE THE FBI")),
        ("time", tightPage("10.30 the CIA and FBI met to review the presence of")),
        ("lowercase", tightPage("10.and the CIA and FBI do not connect the presence of")),
    ]
    for (name, result) in controls {
        #expect(items(result).count == 4, "\(name)")
        #expect(paragraphs(result).count == 1, "\(name)")
    }
}

// MARK: - Line-ending slashes (#70)

@Test(arguments: [
    ("• Review NOTAM for information on runway/", "taxiway closures", "• Review NOTAM for information on runway/taxiway closures"),
    ("maintenance, and/", "or modification", "maintenance, and/or modification"),
    ("outlined in the AFM/", "POH. Generally", "outlined in the AFM/POH. Generally"),
    ("available at https://", "www.federalreserve.gov/", "available at https://www.federalreserve.gov/"),
    ("(online at www.usdoj.gov/dea/", "agency/staffing.htm)", "(online at www.usdoj.gov/dea/agency/staffing.htm)"),
    ("www.whitehouse.gov/news/releases/", "2001/05/print", "www.whitehouse.gov/news/releases/2001/05/print"),
    // Controls: a slash the source sets apart, one before punctuation, and damaged OCR.
    ("China /", "East Asia", "China / East Asia"),
    ("either and/", "(or) both", "either and/ (or) both"),
    ("0. 2 )../", "1-Unknown 36", "0. 2 )../ 1-Unknown 36"),
    ("/", "taxiway", "/ taxiway"),
])
func lineEndingSlashJoinsWithoutASpace(left: String, right: String, joined: String) {
    var warnings: [ConversionWarning] = []
    #expect(LayoutReconstructor.join(left, right, vocabulary: [], page: 1, warnings: &warnings) == joined)
    #expect(LayoutReconstructor.join(InlineText(left), InlineText(right), vocabulary: [], page: 1, warnings: &warnings).text == joined)
    #expect(warnings.isEmpty)
}

@Test func faaRunwayTaxiwayBulletJoinsAcrossTheSlash() throws {
    let fixture = try SourceLayoutFixture.load("faa-365")
    let page = fixture.content()
    #expect(page.lines.contains { $0.text == "• Review NOTAM for information on runway/" })
    let result = blocks(page)
    #expect(items(result).contains("• Review NOTAM for information on runway/taxiway closures and construction areas."))
    #expect(!result.contains { $0.text.contains("runway/ taxiway") })
    // The hyphen policy beside it is unchanged, and `and/or` inside a line is untouched.
    #expect(items(result).contains("• Read back all runway crossing and/or hold instructions."))
}
