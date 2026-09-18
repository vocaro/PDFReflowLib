import Foundation
import Testing
@testable import PDFReflowLib

// A wrapped line of a list item belongs to that item, and bulleted columns too narrow for the
// prose-column test read one column at a time (#50, #64).

private func blocks(_ page: PageContent, preserveRegions: Bool = true) -> [ReflowBlock] {
    let regions = preserveRegions
        ? LayoutReconstructor.graphicsWithLabels(page).enumerated().map { ($0.element, "image-\($0.offset)") } : []
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: regions, vocabulary: [], warnings: &warnings)
}

/// The running head and folio the document-wide furniture pass removes before layout.
private func stripped(_ fixture: SourceLayoutFixture) -> PageContent {
    var page = fixture.content()
    page.lines.removeAll { $0.rect.minY > page.bounds.height - 60 }
    return page
}

private func items(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case let .preformatted(text) = $0.content { return text.text } else { return nil } }
}

private func paragraphs(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case let .paragraph(text) = $0.content { return text.text } else { return nil } }
}

private func line(_ text: String, x: Double, y: Double, width: Double, size: Double = 12,
                  mono: Bool = false) -> TextLine {
    TextLine(text: text, rect: CGRect(x: x, y: y, width: width, height: size), fontSize: size, monospaced: mono)
}

private func page(_ lines: [TextLine]) -> PageContent {
    PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines, graphics: [])
}

private func element(_ text: String, x: Double, y: Double, width: Double) -> LayoutReconstructor.Element {
    let rect = CGRect(x: x, y: y, width: width, height: 12)
    return .init(rect: rect, line: TextLine(text: text, rect: rect, fontSize: 12))
}

@Test func algebraFiveStepListKeepsItemFoursWrappedLineInsideTheItem() throws {
    let fixture = try SourceLayoutFixture.load("algebra-40")
    #expect(fixture.sourceSHA256 == "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678")
    let result = blocks(fixture.content())
    let steps = items(result).filter { $0.range(of: #"^[1-5]\. "#, options: .regularExpression) != nil }
    #expect(steps.count == 5)
    #expect(steps[3] == "4. Solve the remaining 2-step equation (add or subtract then multiply or divide)")
    #expect(steps[4] == "5. Check your answer by plugging it back in for x to find a true statement.")
    // The continuation must not also stand on its own, and the item after it opens a new block.
    #expect(!paragraphs(result).contains { $0.hasPrefix("divide)") })
    #expect(!steps[3].contains("5. Check"))
    // The steps keep their order and the prose around them keeps its paragraphs.
    #expect(steps.map { String($0.prefix(2)) } == ["1.", "2.", "3.", "4.", "5."])
    #expect(paragraphs(result).contains { $0.hasPrefix("The order of these steps is very important.") })
}

@Test func fedFunctionListGivesEveryBulletItsWrappedLines() throws {
    let fixture = try SourceLayoutFixture.load("fed-9")
    #expect(fixture.sourceSHA256 == "8db8fd9e1de63ac25a6f9585d78ded12f45ab56f0c14c52c199b36b368f84d60")
    let result = blocks(fixture.content())
    let bullets = items(result).filter { $0.hasPrefix("•") }
    #expect(bullets.count == 5)
    #expect(bullets[0] == "• conducts the nation’s monetary policy to promote maximum employment and stable prices in the U.S. economy;")
    #expect(bullets[1].hasSuffix("engagement in the U.S. and abroad;"))
    #expect(bullets[2].hasSuffix("impact on the financial system as a whole;"))
    #expect(bullets[3].hasSuffix("U.S.-dollar transactions and payments; and"))
    // The last bullet wraps onto three lines; all of them belong to it.
    #expect(bullets[4].hasSuffix("the administration of consumer laws and regulations."))
    #expect(bullets[4].contains("research and analysis of emerging consumer issues and trends,"))
    #expect(!paragraphs(result).contains { $0.hasPrefix("the U.S. economy;") || $0.hasPrefix("regulations.") })
}

@Test func fedEmergencyPanelReadsTheLeftBulletColumnBeforeTheRight() throws {
    let fixture = try SourceLayoutFixture.load("fed-58")
    let result = blocks(fixture.content())
    let bullets = items(result).filter { $0.hasPrefix("•") }
    #expect(bullets == [
        "• Primary Dealer Credit Facility",
        "• Commercial Paper Funding Facility",
        "• Money Market Mutual Fund Liquidity Facility",
        // The source repeats this entry in its left column; reflow reproduces it.
        "• Commercial Paper Funding Facility",
        "• Main Street Lending Program",
        "• Municipal Liquidity Facility",
        "• Paycheck Protection Program Lending Facility",
        "• Term Asset-Backed Securities Loan Facility",
        "• Primary Market Corporate Credit Facility",
        "• Secondary Market Corporate Credit Facility",
    ])
    // Wrapped halves must not survive as prose beside the items.
    for fragment in ["Facility", "Lending Facility", "Liquidity Facility", "Loan Facility", "Credit Facility"] {
        #expect(!paragraphs(result).contains(fragment))
    }
    // The label set over both columns reads before them; the third column follows them.
    let text = result.map(\.text).joined(separator: "\n")
    let label = try #require(text.range(of: "Emergency lending facilities"))
    let first = try #require(text.range(of: "• Primary Dealer Credit Facility"))
    let last = try #require(text.range(of: "• Secondary Market Corporate Credit Facility"))
    let right = try #require(text.range(of: "Expanded open market operations"))
    #expect(label.upperBound < first.lowerBound)
    #expect(last.upperBound < right.lowerBound)
    #expect(text.contains("Box 4.2. Responding to Financial System Emergencies"))
    // Every source character inside the panel survives the reordering.
    let panel = fixture.content().lines.filter { $0.rect.minY < 290 && $0.rect.maxY > 160 }
    for source in panel { #expect(text.contains(source.text)) }
}

@Test func loperWrappedCitationDoesNotSwallowTheIndentedParagraphBeneathIt() throws {
    let fixture = try SourceLayoutFixture.load("loper-64")
    #expect(fixture.sourceSHA256 == "12f5ea075004886774c25e7831ea1608fd0f831f0113e83bb0e85811c0a4bb6e")
    let result = blocks(fixture.content())
    let block = try #require(items(result).first { $0.hasPrefix("U. S. 134 (1944)") })
    // The line above ends a sentence, so the indented line under it opens a paragraph.
    #expect(block == "U. S. 134 (1944), the Court returned to its time-worn path.")
    #expect(paragraphs(result).contains { $0.hasPrefix("Echoing themes that had run throughout our law from its start,") })
}

@Test func fedAdvisoryCouncilItemsRunToSeveralSentencesAndAcrossThePageBreak() throws {
    let twentyOne = try stripped(SourceLayoutFixture.load("fed-21"))
    let twentyTwo = try stripped(SourceLayoutFixture.load("fed-22"))
    var warnings: [ConversionWarning] = []
    var result = blocks(twentyOne)
    LayoutReconstructor.appendPage(blocks(twentyTwo), page: twentyTwo, previousPage: twentyOne,
        to: &result, vocabulary: [], warnings: &warnings)
    let council = try #require(items(result).first { $0.hasPrefix("1. Federal Advisory Council") })
    // The item wraps onto the next page and stays one preformatted block.
    #expect(council.contains("The FAC ordinarily meets with the Board four times a year, as required by law."))
    #expect(council.hasSuffix("elect their own officers."))
    // A multi-sentence item keeps every sentence on its hanging indent.
    let advisory = try #require(items(result).first { $0.hasPrefix("4. Community Advisory Council") })
    #expect(advisory.contains("The CAC meets semiannually with members of the Board of Governors."))
    #expect(advisory.hasSuffix("selected by the Board through a public nomination process."))
    #expect(!paragraphs(result).contains { $0.hasPrefix("The 15 CAC members") })
    #expect(items(result).filter { $0.range(of: #"^[1-5]\. "#, options: .regularExpression) != nil }.count == 5)
}

@Test func syntheticListItemsCloseAtMarkersGapsDedentsAndCodeBlocks() {
    // A bullet and its hanging-indent continuation are one item; the next marker opens another.
    let wrapped = blocks(page([line("• first item that runs out of room and", x: 90, y: 700, width: 300),
                              line("wraps under its own text", x: 103, y: 686, width: 200),
                              line("• second item", x: 90, y: 672, width: 120)]))
    #expect(items(wrapped) == ["• first item that runs out of room and wraps under its own text", "• second item"])
    // A paragraph gap closes the item.
    let separated = blocks(page([line("• first item that runs out of room and", x: 90, y: 700, width: 300),
                                 line("a later indented line", x: 103, y: 640, width: 200)]))
    #expect(items(separated) == ["• first item that runs out of room and"])
    #expect(paragraphs(separated) == ["a later indented line"])
    // A dedent to the marker's own edge closes the item.
    let dedented = blocks(page([line("• first item that runs out of room and", x: 90, y: 700, width: 300),
                                line("a line on the marker edge", x: 90, y: 686, width: 200)]))
    #expect(items(dedented) == ["• first item that runs out of room and"])
    #expect(paragraphs(dedented) == ["a line on the marker edge"])
    // A deep indent is nested content, not a wrapped line.
    let nested = blocks(page([line("• first item that runs out of room and", x: 90, y: 700, width: 300),
                              line("a deeply indented line", x: 160, y: 686, width: 200)]))
    #expect(items(nested) == ["• first item that runs out of room and"])
    // A monospaced line under an item opens a code block instead.
    let code = blocks(page([line("1. run the command", x: 90, y: 700, width: 300),
                            line("print(value)", x: 103, y: 686, width: 100, mono: true)]))
    #expect(items(code) == ["1. run the command", "print(value)"])
    // A terminated marker line keeps the indented line beneath it as its own paragraph.
    let terminated = blocks(page([line("1. a whole item on one line.", x: 90, y: 700, width: 300),
                                  line("An indented new paragraph follows", x: 103, y: 686, width: 250)]))
    #expect(items(terminated) == ["1. a whole item on one line."])
    #expect(paragraphs(terminated) == ["An indented new paragraph follows"])
}

@Test func warrenSyntheticTextListsAndAlgebraExercisesKeepSeparateBlocks() throws {
    // Inherited-OCR pages keep the #39 behaviour: each numbered point is its own block.
    var warren = try SourceLayoutFixture.load("warren-50").content()
    warren.hasSyntheticTextStyle = true
    let points = items(blocks(warren, preserveRegions: false))
    #expect(points.count == 2)
    #expect(points.allSatisfy { $0.hasPrefix("10.") || $0.hasPrefix("11.") })
    // Spaced algebra exercises stay one block each; nothing merges into a neighbour.
    let algebra = try SourceLayoutFixture.load("algebra-26")
    let exercises = items(blocks(algebra.content())).filter { $0.hasPrefix("80)") }
    #expect(exercises == ["80) (7a2 +7a)− (6a2 + 4a)"])
    let page10 = try SourceLayoutFixture.load("algebra-10")
    let numbered = items(blocks(page10.content())).filter {
        $0.range(of: #"^\d+\) "#, options: .regularExpression) != nil
    }
    #expect(numbered.count == 44)
    #expect(Set(numbered.map { $0.prefix(while: { $0 != ")" }) }).count == 44)
}

@Test func bulletColumnCutNeedsMarkerRunsOnBothSidesOfAClearGutter() throws {
    // Two bullet columns under one spanning label: the label reads first, then each column.
    let label = element("Column label over both", x: 150, y: 700, width: 220)
    let left = (0..<3).map { element("• left \($0) item text", x: 100, y: 660 - Double($0) * 20, width: 90) }
    let right = (0..<3).map { element("• right \($0) item text", x: 230, y: 660 - Double($0) * 20, width: 90) }
    let ordered = LayoutReconstructor.ordered(right + [label] + left, bodySize: 12)
    #expect(ordered.map { $0.line!.text } == ["Column label over both"]
        + left.map { $0.line!.text } + right.map { $0.line!.text })
    #expect(LayoutReconstructor.bulletColumns(right + [label] + left, bodySize: 12) != nil)
    // A name/description table has no markers, so its rows keep their associations.
    let rows = (0..<3).flatMap { index in
        [element("A Name \(index)", x: 100, y: 660 - Double(index) * 20, width: 90),
         element("a description \(index)", x: 230, y: 660 - Double(index) * 20, width: 90)]
    }
    #expect(LayoutReconstructor.bulletColumns(rows, bodySize: 12) == nil)
    // A note under the columns spans the gutter and binds them together.
    let note = element("A note running under both columns", x: 100, y: 580, width: 220)
    #expect(LayoutReconstructor.bulletColumns(right + [label, note] + left, bodySize: 12) == nil)
    // One marker on a side is not a column.
    #expect(LayoutReconstructor.bulletColumns(Array(right.prefix(1)) + left, bodySize: 12) == nil)
    // Markers scattered across a single column give no gutter.
    let ragged = [element("• one item", x: 100, y: 660, width: 200),
                  element("• two item", x: 104, y: 640, width: 200),
                  element("• three item", x: 100, y: 620, width: 200),
                  element("• four item", x: 103, y: 600, width: 200)]
    #expect(LayoutReconstructor.bulletColumns(ragged, bodySize: 12) == nil)
}

@Test func narrowGutterControlsKeepTheirExistingReadingOrder() throws {
    // The 9/11 name/description page must not split into columns (#43 control).
    let names = try SourceLayoutFixture.load("911-451")
    #expect(LayoutReconstructor.bulletColumns(
        names.content().lines.map { .init(rect: $0.rect, line: $0) }, bodySize: 10) == nil)
    // FAA's prose columns are cut by whitespace before the bullet rule is reached.
    for name in ["faa-91", "faa-511"] {
        var source = try SourceLayoutFixture.load(name).content()
        source.lines.removeAll { $0.text == "4-4" || $0.text == "G-35" }
        let text = blocks(source).map(\.text).joined(separator: " ")
        let characters = source.lines.flatMap { $0.text.filter { !$0.isWhitespace } }.sorted()
        #expect(text.filter { !$0.isWhitespace }.sorted() == characters)
    }
}

@Test func aBulletedItemWrapsAfterASentenceOnTheHangingIndentItsSiblingsWrapTo() {
    // FAA page 211's `• Green arc—the normal operating range of the aircraft.` over `Most flying
    // occurs within this range.` (#194): the page's other bullets wrap to the same indent, so the line
    // continues its item although the marker line ends a sentence.
    let lines = [line("• White arc—commonly referred to as the flap operating", x: 90, y: 700, width: 300),
                 line("range since its lower limit represents the full flap", x: 103, y: 686, width: 290),
                 line("• Green arc—the normal operating range of the aircraft.", x: 90, y: 672, width: 300),
                 line("Most flying occurs within this range.", x: 103, y: 658, width: 200)]
    #expect(items(blocks(page(lines))) == [
        "• White arc—commonly referred to as the flap operating range since its lower limit represents the full flap",
        "• Green arc—the normal operating range of the aircraft. Most flying occurs within this range."])
    // Negative control: with no sibling wrapping to that indent, the line after a sentence opens a
    // paragraph, as Loper Bright page 64's does beneath its lettered citation.
    let alone = blocks(page([lines[2], lines[3]]))
    #expect(items(alone) == ["• Green arc—the normal operating range of the aircraft."])
    #expect(paragraphs(alone) == ["Most flying occurs within this range."])
}
