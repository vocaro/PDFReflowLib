import Foundation
import Testing
@testable import PDFReflowLib

// Whitespace column cuts in `LayoutReconstructor.ordered()` (#47, #56). Fixtures are native
// extraction from the checksum-pinned sources; expected orders were read from the rendered pages.

private let algebraSHA256 = "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678"
private let faaSHA256 = "247929cace0ab56b376e683eba540cc4c8f39f199ab35414e8b604e24f395cb7"

/// The page as the pipeline reflows it: preserved regions from `graphicsWithLabels`, unless a
/// test leaves them out, and without the lines the full-document furniture pass removes.
private func reflow(_ name: String, removing furniture: [String] = [], regions: Bool = true)
    throws -> (page: PageContent, blocks: [ReflowBlock], crops: [CGRect]) {
    let fixture = try SourceLayoutFixture.load(name)
    var page = fixture.content()
    page.lines.removeAll { furniture.contains($0.text) }
    let crops = regions ? LayoutReconstructor.graphicsWithLabels(page) : []
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: crops.enumerated().map { ($0.element, "image-\($0.offset)") },
        vocabulary: [], warnings: &warnings)
    return (page, blocks, crops)
}

/// Each phrase is found after the previous one in the page's joined block text.
private func expectInOrder(_ text: String, _ phrases: [String], sourceLocation: SourceLocation = #_sourceLocation) {
    var cursor = text.startIndex
    for phrase in phrases {
        guard let range = text.range(of: phrase, range: cursor..<text.endIndex) else {
            Issue.record("missing or out of order: \(phrase)", sourceLocation: sourceLocation)
            return
        }
        cursor = range.upperBound
    }
}

/// Block indices of phrases that open blocks, strictly increasing.
private func expectBlocksInOrder(_ blocks: [ReflowBlock], _ openings: [String], sourceLocation: SourceLocation = #_sourceLocation) {
    var previous = -1
    for opening in openings {
        guard let index = blocks.firstIndex(where: { $0.text.hasPrefix(opening) }) else {
            Issue.record("missing block: \(opening)", sourceLocation: sourceLocation)
            return
        }
        #expect(index > previous, "\(opening) at block \(index) follows block \(previous)", sourceLocation: sourceLocation)
        previous = index
    }
}

/// Every line outside a preserved region still contributes all of its characters.
private func expectCharactersConserved(_ page: PageContent, _ blocks: [ReflowBlock], crops: [CGRect],
                                       sourceLocation: SourceLocation = #_sourceLocation) {
    let source = page.lines.filter { line in !crops.contains { $0.intersects(line.rect) } }
        .flatMap { $0.text.filter { !$0.isWhitespace } }.sorted()
    #expect(blocks.map(\.text).joined().filter { !$0.isWhitespace }.sorted() == source, sourceLocation: sourceLocation)
}

// Page 438: `Answers - Chapter 0` is centred over columns 2 and 3 while column 1 begins far to its
// left, so the widest whitespace is column 1's gutter. Before #47 the title, `Answers - Integers`
// and columns 2 and 3 all read after column 1's whole answer list and the `0.2` fractions.
@Test func answerKeyTitleAndSectionLabelsPrecedeAllThreeColumns() throws {
    #expect(try SourceLayoutFixture.load("algebra-438").sourceSHA256 == algebraSHA256)
    let (_, blocks, _) = try reflow("algebra-438", removing: ["438"])
    let heading = try #require(blocks.first { $0.text == "Answers - Chapter 0" })
    if case .heading = heading.content {} else { Issue.record("the chapter title is not a heading") }
    expectBlocksInOrder(blocks, ["Answers - Chapter 0", "0.1", "Answers - Integers", "1)− 2", "21)− 7",
                                 "22) 0", "42) 4", "43)− 20", "60)− 9", "0.2", "Answers - Fractions"])
}

// Page 471: before #47, `8.1` and its first answers read ahead of the 7.8 right column, and the
// `7.8` label and `Answers - Dimensional Analysis` title were split across the columns.
@Test func answerKeySectionsReadWholeBeforeTheNextChapter() throws {
    #expect(try SourceLayoutFixture.load("algebra-471").sourceSHA256 == algebraSHA256)
    let (_, blocks, _) = try reflow("algebra-471", removing: ["471"])
    expectBlocksInOrder(blocks, ["21) 0, 5", "28) 1", "33)− 10", "7.8", "Answers - Dimensional Analysis",
                                 "1) 12320 yd", "15) 111 m/s", "16) 2,623,269,600 km/yr", "30) 621,200 mg; 1.42 lb",
                                 "Answers - Chapter 8", "8.1", "Answers - Square Roots", "3) 6", "4) 14"])
}

// FAA pages 165, 199 and 262 keep 11.6–11.9 pt of whitespace between their text columns, as pages
// 91 and 511 do, but a figure's rectangle overhangs the prose and narrows the gutter to 6.5–7.4 pt,
// under the 0.75-body test. Before #56 the pages fell through to the reading-order sort: page 199
// interleaved line by line and pages 165 and 262 read the right column before the figure-headed
// left one. The figure now joins the column it heads and the left column completes first.
@Test(arguments: [
    ("faa-165", "7-5",
     ["Figure 7-6. Changes in propeller blade angle", "throughout its entire length would be inefficient",
      "Fixed-Pitch Propeller", "simplicity, and low cost are needed.", "climb or cruise propeller",
      "Figure 7-7. Relationship of travel distance"],
     ["installed depends upon its intended use.", "The cruise propeller has a higher pitch",
      "When operating altitude increases", "Figure 7-8. Engine rpm"]),
    ("faa-199", "7-39",
     ["Figure 7-45. Continuous flow mask", "breathing cycle because oxygen is only delivered during",
      "altitude is increased. [Figure 7-46]", "Pulse Oximeters", "oxygen. [Figure 7-47]",
      "Servicing of Oxygen Systems", "whenever aircraft oxygen"],
     ["Figure 7-46. EDS-011", "systems are to be serviced.", "free of oil, grease,", "Figure 7-47. Onyx"]),
    ("faa-262", "11-6",
     ["Figure 11-5. Drag versus speed.", "aircraft is operated in steady, level flight at twice",
      "When an aircraft is in steady, level flight", "The maximum level flight speed", "Climb Performance",
      "acquires mechanical energy when it moves.", "Figure 11-6. Power versus speed."],
     ["energy comes in two forms", "Aircraft motion (KE) is described", "We sometimes use the terms",
      "Positive climb performance occurs", "As an example of factor 2"]),
])
func figureOverhangingTheGutterJoinsItsColumn(name: String, folio: String, left: [String], right: [String]) throws {
    #expect(try SourceLayoutFixture.load(name).sourceSHA256 == faaSHA256)
    let (page, blocks, crops) = try reflow(name, removing: [folio])
    // The figure heading the left column reads first, ahead of the column's text.
    if case .image = try #require(blocks.first).content {} else { Issue.record("the page does not open with its figure") }
    expectInOrder(blocks.map(\.text).joined(separator: " "), left + right)
    expectCharactersConserved(page, blocks, crops: crops)
}

// Control: Our Flag page 34 is a grid of four state entries. Its folio sits in the gutter 3.6 pt
// from the right-hand flags, so no gutter separates every element, while the text alone leaves one
// and 62 pt of whitespace separates the rows. The text-measured gutter is tried only after the
// horizontal cut, so the rows keep the book's alphabetical row order.
@Test func rowBandedGridKeepsRowOrderAheadOfTheTextGutter() throws {
    #expect(try SourceLayoutFixture.load("flag-34").sourceSHA256 == "a47a3153b649022a52b53e7b0c40b55bfea24e7980bbe32fe6fee0cf1936bbd8")
    let (page, blocks, crops) = try reflow("flag-34")
    expectBlocksInOrder(blocks, ["FLORIDA", "GEORGIA", "HAWAII", "IDAHO"])
    expectCharactersConserved(page, blocks, crops: crops)
}

// Control: the FAA glossary page 511 fills its left column below the right column's last entry,
// with only the printed folio beyond the gutter. A single-line band there is the column's own
// tail, not a heading over both columns, so the left column still completes before the right.
// The folio is kept: it is what places content on both sides beneath the band.
@Test func columnTailBesideAFolioStaysWithItsColumn() throws {
    #expect(try SourceLayoutFixture.load("faa-511").sourceSHA256 == faaSHA256)
    let (page, blocks, _) = try reflow("faa-511", regions: false)
    let text = blocks.map(\.text).joined(separator: " ")
    expectInOrder(text, ["Wind direction indicators.", "Wing area.", "Wing span.", "Work.",
                         "restricted areas, obstructions and other pertinent data.", "Zone of confusion.", "Zulu time."])
    expectCharactersConserved(page, blocks, crops: [])
}

// Control: the CDC comic's speech balloons stand clear of one another as labels do. A band of two
// or more lines is a paragraph of its own panel, so the bottom-left panel's balloons still read
// before the bottom-right panel's. The full-bleed artwork is left out; the balloons' text is tested.
@Test func speechBalloonsAreNotHeadingBands() throws {
    #expect(try SourceLayoutFixture.load("cdc-26").sourceSHA256 == "d95e9ec2d8cf52cb8c218a6195e132ec140725018358fd2122928bab8a13efc3")
    let (page, blocks, _) = try reflow("cdc-26", regions: false)
    expectBlocksInOrder(blocks, ["Uh oh", "what? yo u", "WELL...", "DO ME A fAVOr"])
    expectCharactersConserved(page, blocks, crops: [])
}

// Control: a figure spanning both columns must never be dropped. Measured over text alone the
// gutter is clear, but the figure straddles it, so no column cut is taken and every element stays.
@Test func textMeasuredGutterNeverCutsAFigureSpanningIt() {
    func line(_ text: String, x: Double, y: Double) -> LayoutReconstructor.Element {
        let rect = CGRect(x: x, y: y, width: 240, height: 12)
        return .init(rect: rect, line: TextLine(text: text, rect: rect, fontSize: 12))
    }
    let above = [line("Left 1", x: 40, y: 700), line("Left 2", x: 40, y: 688), line("Right 1", x: 292, y: 700),
                 line("Right 2", x: 292, y: 688)]
    let below = [line("Left 3", x: 40, y: 590), line("Left 4", x: 40, y: 578), line("Right 3", x: 292, y: 590),
                 line("Right 4", x: 292, y: 578)]
    // The figure overlaps the lines above and below it, so no horizontal band separates it either.
    let figure = LayoutReconstructor.Element(rect: CGRect(x: 40, y: 596, width: 492, height: 98), image: "figure")
    let elements = above + [figure] + below
    let ordered = LayoutReconstructor.ordered(elements, bodySize: 12)
    #expect(ordered.count == elements.count)
    #expect(ordered.contains { $0.image == "figure" })
}
