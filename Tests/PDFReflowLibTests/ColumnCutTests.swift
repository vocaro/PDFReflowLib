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
      "Fixed-Pitch Propeller", "simplicity, and low cost are needed.", "climb or cruise propeller"],
     // The column's last sentence continues at the right column's head (#111); the caption
     // between them follows the joined paragraph.
     ["installed depends upon its intended use.", "Figure 7-7. Relationship of travel distance",
      "The cruise propeller has a higher pitch",
      "When operating altitude increases", "Figure 7-8. Engine rpm"]),
    ("faa-199", "7-39",
     ["Figure 7-45. Continuous flow mask", "breathing cycle because oxygen is only delivered during",
      "altitude is increased. [Figure 7-46]", "Pulse Oximeters", "oxygen. [Figure 7-47]",
      "Servicing of Oxygen Systems", "whenever aircraft oxygen"],
     ["systems are to be serviced.", "free of oil, grease,", "Figure 7-46. EDS-011", "Figure 7-47. Onyx"]),
    ("faa-262", "11-6",
     ["Figure 11-5. Drag versus speed.", "aircraft is operated in steady, level flight at twice",
      "When an aircraft is in steady, level flight", "The maximum level flight speed", "Climb Performance",
      "acquires mechanical energy when it moves."],
     ["energy comes in two forms", "Figure 11-6. Power versus speed.", "Aircraft motion (KE) is described", "We sometimes use the terms",
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

// #86: a figure set across both columns' full measure, above or below them, bridges the text
// gutter, and its crop comes within a few points of the columns' first or last lines, so neither
// whitespace cut applies and the page fell to the reading-order sort, which interleaved the columns
// line by line. Page 340's runway figure ends 0.7 pt above the column headings; page 401's figures
// begin 8 pt below the left column with a caption under them; page 108's ground-effect crop rises
// to within points of both columns' last lines; pages 439 and 392 also break both columns'
// paragraphs at one height, so a paragraph-sized band was cut first (left, right, left, right).
// The figures and their captions now read before or after the complete columns.
@Test(arguments: [
    ("faa-340", "14-6", true,
     ["Runway Safety Area", "The runway safety area (RSA) is a defined surface", "The RSA is typically graded",
      "operations at uncontrolled airports. [Figure 14-7]", "Runway Safety Area Boundary Sign",
      "Some taxiway stubs also have", "surface painted marking.", "Runway Holding Position Sign",
      "result in the FAA filing a Pilot Deviation"]),
    ("faa-401", "16-14", false,
     ["so familiar with the fundamental principles", "of wind triangle.", "If flight is to be made on a course",
      "In actual practice, the triangle", "the blue, yellow, and black lines in Figure 16-20",
      "Suppose a flight is to be flown", "Now, on a plain sheet of paper", "Step 1",
      "true course) and another at 45°", "Figure 16-20. The wind triangle"]),
    ("faa-108", "5-11", false,
     ["Ground Effect", "When an aircraft in flight comes", "While the aerodynamic characteristics",
      "downwash, and wingtip vortices.", "the spanwise lift distribution",
      "Figure 5-16. Ground effect changes airflow.", "Ground effect also alters", "In order for ground effect",
      "Figure 5-17. Ground effect changes drag and lift."]),
    ("faa-439", "17-17", false,
     ["and use of marijuana", "Stimulants are drugs that excite", "stimulant reaction, even though",
      "this reaction is not their primary function", "Depressants are drugs that reduce",
      "The most common depressant is alcohol.", "Figure 17-9. Adverse affects of various drugs."]),
    ("faa-392", "16-5", true,
     ["flying eastward from one time zone", "In most aviation operations", "Because a pilot may cross",
      "Pacific Standard Time", "For Daylight Saving Time", "Measurement of Direction",
      "Because meridians converge", "As shown in Figure 16-7"]),
])
func fullMeasureFigureReadsApartFromTheColumns(name: String, folio: String, figureFirst: Bool, order: [String]) throws {
    #expect(try SourceLayoutFixture.load(name).sourceSHA256 == faaSHA256)
    let (page, blocks, crops) = try reflow(name, removing: [folio])
    if case .image = try #require(blocks.first).content {
        #expect(figureFirst, "the page opens with a figure")
    } else {
        #expect(!figureFirst, "the page does not open with its figure")
    }
    expectInOrder(blocks.map(\.text).joined(separator: " "), order)
    expectCharactersConserved(page, blocks, crops: crops)
}

// Control: a caption that sits against a figure of a column's own stays with that column even when
// it lies below all column text. Page 194's `Figure 7-38` is under its photo in the left column,
// above the full-width figure 7-39; page 19's photo caption wraps below the right column's foot.
@Test(arguments: [
    // The left column's last sentence continues at the right column's head (#111), so the caption
    // follows that joined paragraph, still ahead of the right column's next section.
    ("faa-194", "7-34", ["Landing gear can also be classified", "maintenance. Retractable landing gear",
                         "Figure 7-38. Tailwheel landing gear.", "Pressurized Aircraft",
                         "Figure 7-39. Fixed (left) and retractable (right) gear airplanes."]),
    ("faa-19", "1-4", ["United States. This legislation", "The Air Commerce Act charged",
                       "Figure 1-5. The de Haviland DH-4 on the New York to San Francisco inaugural route in 1921.",
                       "standard beacon tower was 51 feet high", "In 1934, to recognize"]),
])
func captionOfAColumnFigureStaysInItsColumn(name: String, folio: String, order: [String]) throws {
    #expect(try SourceLayoutFixture.load(name).sourceSHA256 == faaSHA256)
    let (page, blocks, crops) = try reflow(name, removing: [folio])
    expectInOrder(blocks.map(\.text).joined(separator: " "), order)
    expectCharactersConserved(page, blocks, crops: crops)
}

// Control: Wallace's worked examples set formula crops and triangles beside short notes. Those are
// not prose columns under a figure, so the notes keep their places beside their steps. Page 429's
// side-length label `12` is drawn under its triangle and is preserved with it (#179), so the notes
// alone are checked here; page 186's first note follows its step.
@Test func workedExampleNotesAreNotColumnsUnderAFigure() throws {
    #expect(try SourceLayoutFixture.load("algebra-429").sourceSHA256 == algebraSHA256)
    let (_, examples, _) = try reflow("algebra-429", removing: ["429"])
    expectBlocksInOrder(examples, ["From angle θ the given sides", "Because we are looking for an angle",
                                   "45◦ Our Solution", "Example 556.", "Find the indicated angle"])
    #expect(try SourceLayoutFixture.load("algebra-186").sourceSHA256 == algebraSHA256)
    let (_, powers, _) = try reflow("algebra-186", removing: ["186"])
    expectBlocksInOrder(powers, ["Example 219.", "In numerator, use product rule", "In the previous example"])
}

// #78: page 487's section 10.6 sets item 1's sub-answers a–i in three columns above answers 2–15 in
// three columns on the same edges. One gutter ran through both blocks, so they read `a`–`d`, `2`–`6`,
// `e`–`h`, `7`–`11`, `i`, `12`–`15`. The 38-pt band between the blocks is more than twice any gap
// inside a column, and the blocks now read one after the other.
@Test func stackedAnswerBlocksReadBlockByBlock() throws {
    #expect(try SourceLayoutFixture.load("algebra-487").sourceSHA256 == algebraSHA256)
    let (page, blocks, crops) = try reflow("algebra-487", removing: ["487"])
    expectBlocksInOrder(blocks, ["10.6", "Answers - Interest Rate Problems", "1)", "a. 740.12", "d. 1979.22",
                                 "e. 1209.52", "h. 3219.23", "i. 7152.17", "2) 1640.70", "6) 1507.08",
                                 "7) 2001.60", "11) 13742.19", "12) 28240.43", "15) 101.68"])
    expectCharactersConserved(page, blocks, crops: crops)
}

// #78: page 448 sets graphs 15–22 three to a row under bare labels numbered along the rows, with no
// whitespace between rows (graph 20 hangs below label 21's top). Only the column gutters cut them,
// so they read 15, 18, 21, 16… The labels now read in number order, each followed by its graph.
@Test func rowNumberedGraphGridReadsInNumberOrder() throws {
    #expect(try SourceLayoutFixture.load("algebra-448").sourceSHA256 == algebraSHA256)
    let (_, blocks, _) = try reflow("algebra-448", removing: ["448"])
    let labels = ["15)", "16)", "17)", "18)", "19)", "20)", "21)", "22)"]
    expectBlocksInOrder(blocks, labels + ["2.2"])
    for label in labels {
        let index = try #require(blocks.firstIndex { $0.text == label })
        if case .image = blocks[index + 1].content {} else { Issue.record("\(label) is not followed by its graph") }
    }
}

// Controls: numbering decides a grid's order, never geometry alone. Page 449's graphs are numbered
// down their columns (31–36, then 37–42) and keep that order. The exercise sets are numbered along
// their rows two to a row (1 | 2), but the book reads them column by column by contract: pages 10
// and 26 with inline problems, and page 424's triangles under bare labels, are unchanged.
@Test func columnNumberedGridsAndExerciseSetsKeepColumnOrder() throws {
    #expect(try SourceLayoutFixture.load("algebra-449").sourceSHA256 == algebraSHA256)
    let (_, graphs, _) = try reflow("algebra-449", removing: ["449"])
    expectBlocksInOrder(graphs, ["31)", "32)", "33)", "34)", "35)", "36)", "37)", "38)", "39)", "40)", "41)", "42)"])
    #expect(try SourceLayoutFixture.load("algebra-424").sourceSHA256 == algebraSHA256)
    let (_, triangles, _) = try reflow("algebra-424", removing: ["424"])
    expectBlocksInOrder(triangles, ["13)", "15)", "17)", "19)", "14)", "16)", "18)", "20)"])
    let (_, integers, _) = try reflow("algebra-10", removing: ["10"])
    expectInOrder(integers.map(\.text).joined(separator: " "),
                  ["Evaluate each expression.", "1) 1", "29)", "Find each product.", "43)", "2) 4", "30)", "44)"])
    let (_, polynomials, _) = try reflow("algebra-26", removing: ["26"])
    expectInOrder(polynomials.map(\.text).joined(separator: " "), ["37)", "39)", "41)", "38)", "40)"])
}

// Synthetic guard controls for #86 and #78: each layout is protected by exactly one guard, and the
// test fails when that guard is removed (measurements/column-order/guard-mutations.log).
private func textAt(_ text: String, x: Double, y: Double, width: Double) -> LayoutReconstructor.Element {
    let rect = CGRect(x: x, y: y, width: width, height: 12)
    return .init(rect: rect, line: TextLine(text: text, rect: rect, fontSize: 10))
}

private func figureAt(_ name: String, x: Double, y: Double, width: Double, height: Double) -> LayoutReconstructor.Element {
    .init(rect: CGRect(x: x, y: y, width: width, height: height), image: name)
}

private func names(_ elements: [LayoutReconstructor.Element]) -> [String] {
    elements.map { $0.line?.text ?? $0.image ?? "box" }
}

/// Two prose columns of `count` lines at 12.5-pt leading from `top`, labelled `<prefix>L1…`/`<prefix>R1…`.
private func proseColumns(_ prefix: String, top: Double, count: Int) -> [LayoutReconstructor.Element] {
    (0..<count).flatMap { row in
        [textAt("\(prefix)L\(row + 1)", x: 36, y: top - 12.5 * Double(row), width: 240),
         textAt("\(prefix)R\(row + 1)", x: 290, y: top - 12.5 * Double(row), width: 240)]
    }
}

// Guard: the columns under a spanning figure must be prose. A two-column table of short names and
// values set 2 pt under a full-width figure keeps its rows.
@Test func shortCellsUnderAFigureKeepTheirRows() {
    let figure = figureAt("figure", x: 36, y: 500, width: 494, height: 200)
    let rows = (0..<4).flatMap { row in
        [textAt("Name \(row + 1)", x: 36, y: 486 - 12.5 * Double(row), width: 60),
         textAt("Value \(row + 1)", x: 200, y: 486 - 12.5 * Double(row), width: 80)]
    }
    #expect(names(LayoutReconstructor.ordered([figure] + rows, bodySize: 10))
        == ["figure", "Name 1", "Value 1", "Name 2", "Value 2", "Name 3", "Value 3", "Name 4", "Value 4"])
}

// Guard: only a figure above or below every column line is set apart. A full-width figure between
// two blocks of columns, 3 pt from each, is not moved after both blocks.
@Test func figureBetweenColumnBlocksKeepsItsPlace() {
    let figure = figureAt("figure", x: 36, y: 560, width: 494, height: 112)
    let ordered = names(LayoutReconstructor.ordered(proseColumns("A", top: 675, count: 3) + [figure]
        + proseColumns("B", top: 545, count: 3), bodySize: 10))
    let position = ordered.firstIndex(of: "figure") ?? -1
    #expect(ordered.prefix(position).allSatisfy { $0.hasPrefix("A") })
    #expect(ordered.dropFirst(position + 1).allSatisfy { $0.hasPrefix("B") })
}

// Guard: only a paragraph-sized band gives way to the figure partition. A 40-pt band between two
// blocks of columns under a head figure is still cut first, so each block reads left then right.
@Test func wideBandBeneathAHeadFigureIsCutFirst() {
    let figure = figureAt("figure", x: 36, y: 720, width: 494, height: 80)
    let ordered = names(LayoutReconstructor.ordered([figure] + proseColumns("A", top: 705, count: 3)
        + proseColumns("B", top: 628, count: 3), bodySize: 10))
    #expect(ordered == ["figure", "AL1", "AL2", "AL3", "AR1", "AR2", "AR3", "BL1", "BL2", "BL3", "BR1", "BR2", "BR3"])
}

// Guard: labels must be consecutive along the rows. A three-column graph grid numbered down its
// columns (1–2, 3–4, 5–6) keeps column order.
@Test func columnNumberedThreeColumnGridKeepsColumnOrder() {
    let cells = [(1, 40.0, 700.0), (2, 40, 590), (3, 190, 700), (4, 190, 590), (5, 340, 700), (6, 340, 590)]
        .flatMap { number, x, y in
            [textAt("\(number))", x: x, y: y, width: 16), figureAt("graph \(number)", x: x, y: y - 105, width: 130, height: 103)]
        }
    #expect(names(LayoutReconstructor.ordered(cells, bodySize: 10))
        == ["1)", "graph 1", "2)", "graph 2", "3)", "graph 3", "4)", "graph 4", "5)", "graph 5", "6)", "graph 6"])
}

// Guard: prose columns are never stacked blocks. Both columns break for a 30-pt space at the same
// height, and the left column still completes before the right.
@Test func alignedSpaceInProseColumnsIsNotAStackedBlock() {
    let upper = proseColumns("upper ", top: 700, count: 2), lower = proseColumns("lower ", top: 645, count: 2)
    #expect(names(LayoutReconstructor.ordered(upper + lower, bodySize: 10))
        == ["upper L1", "upper L2", "lower L1", "lower L2", "upper R1", "upper R2", "lower R1", "lower R2"])
}

// Guard: a stacked block needs columns on both sides of the gutter above and below the band. A
// left column that continues 40 pt below the right column's end is that column's own tail.
@Test func columnTailBelowABandStaysWithItsColumn() {
    let cells = [textAt("a1", x: 40, y: 700, width: 60), textAt("a2", x: 40, y: 680, width: 60),
                 textAt("a3", x: 40, y: 660, width: 60), textAt("a4", x: 40, y: 608, width: 60),
                 textAt("a5", x: 40, y: 588, width: 60), textAt("b1", x: 200, y: 700, width: 60),
                 textAt("b2", x: 200, y: 680, width: 60), textAt("b3", x: 200, y: 660, width: 60)]
    #expect(names(LayoutReconstructor.ordered(cells, bodySize: 10)) == ["a1", "a2", "a3", "a4", "a5", "b1", "b2", "b3"])
}
