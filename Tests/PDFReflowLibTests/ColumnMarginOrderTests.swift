import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// #153: prose columns a margin folio, a running foot's rule or a spanning figure leaves without a
// whitespace cut, and the gutters a figure's rectangle crosses. Fixtures are native extraction from
// the checksum-pinned sources; expected orders were read from the rendered pages.

private let gwlSHA256 = "a98e4fcdea40b8ea7023880dd88966f04198b4ec311fced0bb9ebb2dec45fe6d"
private let dascSHA256 = "7c2137098ffb75153e0049b970272db97bc91e13168028dc7b53fbe2deb92caa"
private let usdaSHA256 = "2673d1fded74ad89c8b5c59dc325c7884601e1aca5b5755b15a105c1f5b0d761"
private let dgaSHA256 = "c34f1bec5c9416265670b7fcb24556bb8616ba95e8de2f2890460b6bbca1a472"
private let algebraSHA256 = "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678"

/// The page as the pipeline reflows it: preserved regions from `graphicsWithLabels`, and without
/// the lines the full-document furniture pass removes.
private func reflow(_ name: String, removing furniture: [String] = [], regions: Bool = true,
                    tags: Bool = true) throws -> (page: PageContent, blocks: [ReflowBlock], crops: [CGRect]) {
    let fixture = try SourceLayoutFixture.load(name)
    var page = fixture.content()
    page.lines.removeAll { furniture.contains($0.text) }
    // The pipeline's document-wide label and heading styles are not available here, and they
    // decide which tagged groups fall back. Pages the pipeline reports `structureFallback` for are
    // read spatially, as this file tests.
    if !tags { for index in page.lines.indices { page.lines[index].structure = nil } }
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

/// Every line outside a preserved region still contributes all of its characters.
private func expectCharactersConserved(_ page: PageContent, _ blocks: [ReflowBlock], crops: [CGRect],
                                       sourceLocation: SourceLocation = #_sourceLocation) {
    let source = page.lines.filter { line in !crops.contains { $0.intersects(line.rect) } }
        .flatMap { $0.text.filter { !$0.isWhitespace } }.sorted()
    #expect(blocks.map(\.text).joined().filter { !$0.isWhitespace }.sorted() == source, sourceLocation: sourceLocation)
}

private func line(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat = 10,
                  size: CGFloat = 10) -> LayoutReconstructor.Element {
    let rect = CGRect(x: x, y: y, width: width, height: height)
    return .init(rect: rect, line: TextLine(text: text, rect: rect, fontSize: size))
}

private func texts(_ elements: [LayoutReconstructor.Element]) -> [String] { elements.compactMap { $0.line?.text } }

/// A column of justified prose lines, `pitch` apart from `top` down.
private func column(_ texts: [String], x: CGFloat, top: CGFloat, width: CGFloat = 240,
                    pitch: CGFloat = 11.5, size: CGFloat = 10) -> [LayoutReconstructor.Element] {
    texts.enumerated().map { index, text in
        line(text, x: x, y: top - CGFloat(index) * pitch, width: width, size: size)
    }
}

// MARK: - The Word paper: a folio centred in the gutter

// Page 2 sets its columns 18 pt apart with the folio `2` in the gutter, 6 pt under their last
// lines: no whitespace cut separates every element, the text-measured gutter is crossed by the
// folio too, and the row sort read the columns a line at a time. The folio is now set aside as the
// page's foot and the columns read in turn.
@Test func aFolioInTheGutterDoesNotStopTheColumnCut() throws {
    #expect(try SourceLayoutFixture.load("gwl-2").sourceSHA256 == gwlSHA256)
    let (page, blocks, crops) = try reflow("gwl-2")
    expectInOrder(blocks.map(\.text).joined(separator: " "), [
        "program and has been theorized to capture the peak response",
        "Atmospheric-boundary-layer (ABL) test techniques have",
        "The purpose of the research effort described in this paper",
        "2. TEST DESCRIPTION", "Wind-Tunnel Facility",
        "The TDT is a large, variable pressure, transonic wind tunnel",
        "Unlike typical wind-tunnel testing", "Figure 1. Sketch of the Transonic Dynamics Tunnel",
        "Data Acquisition", "Data records were sampled at 10 kHz",
        "Data record length was 8.7 seconds", "2"])
    expectCharactersConserved(page, blocks, crops: crops)
}

// Page 1 breaks the abstract at the same height in both columns, 10.4 pt of paragraph space that
// the horizontal cut took first: the left column's last two paragraphs then read after the right
// column's continuation. The band is no wider than paragraph spacing and both columns break at it,
// so the gutter cut stands and each column reads whole.
@Test func columnsBreakingAParagraphAtTheSameHeightStillReadDownEachColumn() throws {
    #expect(try SourceLayoutFixture.load("gwl-1").sourceSHA256 == gwlSHA256)
    let (page, blocks, crops) = try reflow("gwl-1", tags: false)
    expectInOrder(blocks.map(\.text).joined(separator: " "), [
        "Abstract—A launch vehicle ground-wind-loads program",
        "Wind approaching the vehicle can be characterized",
        "The NASA Langley Transonic Dynamics Tunnel is capable",
        "Dynamic aeroelastically-scaled models representative",
        "It was discovered that peak dynamic loads",
        "U.S. Government work not protected by U.S. copyright",
        "profile. Alternately, nonresonant wind-induced oscillation",
        "TABLE OF CONTENTS", "1. INTRODUCTION",
        "A launch vehicle ground-wind-loads (GWL) program is"])
    expectCharactersConserved(page, blocks, crops: crops)
}

// MARK: - The IEEEtran paper

// Page 9's appendices break both columns 14.8 pt apart, and display crops narrow the gutter to
// 6 pt, so the horizontal cut read the right column's opening between the summary and `APPENDIX A`.
@Test func appendixColumnsReadWholeAcrossAParagraphBand() throws {
    #expect(try SourceLayoutFixture.load("dasc-9").sourceSHA256 == dascSHA256)
    let (page, blocks, crops) = try reflow("dasc-9")
    expectInOrder(blocks.map(\.text).joined(separator: " "), [
        "VIII. SUMMARY", "A distributed system for managing diverse air traffic",
        "APPENDIX A", "Table III gives a high-level outline of the algorithm",
        "APPENDIX B", "For n being the k-th node along the route",
        "The quadratic objective function is", "Letting x=",
        "For this problem class, the cvxopt Python module"])
    expectCharactersConserved(page, blocks, crops: crops)
}

// Page 10 sets Table III's crop under its two-line caption beside the references, with 12 pt of
// gutter. A preserved figure at a column's measure is column content beside a caption line, so the
// narrow gutter is prose evidence and `REFERENCES` no longer splits the caption.
@Test func aPreservedTableBesideItsCaptionIsColumnContent() throws {
    #expect(try SourceLayoutFixture.load("dasc-10").sourceSHA256 == dascSHA256)
    let (page, blocks, crops) = try reflow("dasc-10")
    expectInOrder(blocks.map(\.text).joined(separator: " "), [
        "TABLE III: A high-level outline of the scheduling algorithm", "of section V.",
        "REFERENCES", "[1] M. S. Andersen", "[10] K. Tumer and A. Agogino"])
    expectCharactersConserved(page, blocks, crops: crops)
}

// Page 4's Figure 1 crop overhangs the left column by 10 pt, 1.6 pt short of the right column's
// caption: the cut moves inside the gutter, past the crop, instead of falling to the row sort,
// which interleaved the Figure 2 caption with the left column's prose.
@Test func aFigureOverhangingTheGutterMovesTheCutInsteadOfLosingIt() throws {
    #expect(try SourceLayoutFixture.load("dasc-4").sourceSHA256 == dascSHA256)
    let (page, blocks, crops) = try reflow("dasc-4")
    expectInOrder(blocks.map(\.text).joined(separator: " "), [
        "Fig. 1: (A) The STAs of previously scheduled flights",
        "the separation requirements with the STAs",
        "On having computed all the time windows unavailable",
        "A generic time instant", "Fig. 2: (A) The only times (shown in blue) reachable at node"])
    expectCharactersConserved(page, blocks, crops: crops)
}

// MARK: - The USDA magazine

// Page 15 sets three columns; the display photo covers the first two, so their gutter is gone,
// while the running foot's rule crosses the third. The cut falls to the second gutter and the rule
// goes to the page's foot, so the article reads from its opening in the left column.
@Test func aFigureOverTwoOfThreeColumnsLeavesTheSecondGutter() throws {
    #expect(try SourceLayoutFixture.load("usda-15").sourceSHA256 == usdaSHA256)
    let (page, blocks, crops) = try reflow("usda-15")
    expectInOrder(blocks.map(\.text).joined(separator: " "), [
        "Applying pesticides is no simple task.",
        "Agricultural Research Service scientists",
        "that will result from that setup",
        "The apps incorporate the latest science of spray technology",
        "aircraft, and they allow users to save data",
        "The apps are available online through the"])
    expectCharactersConserved(page, blocks, crops: crops)
}

// MARK: - Controls

// Control: DGA page 3 stacks sections of two bullet columns. The 13.7 pt band under the protein
// section is narrower than paragraph spacing, but the right column ends 52 pt above it, so the
// band is a section break and the sections keep their order.
@Test func sectionsStackedOverTwoBulletColumnsKeepTheirOrder() throws {
    #expect(try SourceLayoutFixture.load("dga-3-illustrated").sourceSHA256 == dgaSHA256)
    let (page, blocks, crops) = try reflow("dga-3-illustrated", removing: ["Dietary Guidelines for Americans, 2025–2030  |  2"])
    expectInOrder(blocks.map(\.text).joined(separator: " "), [
        "Prioritize high-quality, nutrient-dense protein", "Swap deep-fried cooking methods",
        "Consume meat with no or limited added", "Protein serving goals",
        "Consume Dairy", "When consuming dairy", "Dairy serving goals"])
    expectCharactersConserved(page, blocks, crops: crops)
}

// Control: Wallace page 263 sets each step's formula crop beside its note. The crops are not prose,
// so the cut does not move past them into the notes' column and the rows keep their pairing.
@Test func formulaCropsBesideTheirNotesKeepTheRowOrder() throws {
    #expect(try SourceLayoutFixture.load("algebra-263").sourceSHA256 == algebraSHA256)
    let (page, blocks, crops) = try reflow("algebra-263", removing: ["263"])
    let notes = ["Identify LCD (use highest exponent)", "Multiply each term by LCD",
                 "Reduce fractions (subtract exponents)", "Multiply", "Factor", "Divide out (x− 1) factor"]
    expectInOrder(blocks.map(\.text).joined(separator: " "), notes)
    // A crop stands between the first two notes: the steps are not read as two columns.
    let first = try #require(blocks.firstIndex { $0.text.hasPrefix(notes[0]) })
    let second = try #require(blocks.firstIndex { $0.text.hasPrefix(notes[1]) })
    #expect(blocks[first..<second].contains { if case .image = $0.content { return true } else { return false } })
    expectCharactersConserved(page, blocks, crops: crops)
}

// MARK: - The guards, isolated

// A folio in the gutter, a rule across the foot and a figure over both columns are set aside;
// the columns read in turn.
@Test func marginBandsSetAsideWhatCrossesTheGutterAboveAndBelowTheColumns() {
    let left = column(["Wind approaching the vehicle can be characterized by a varying",
                       "speed with height and turbulence content. The combination of",
                       "both the varying speed and turbulence content is referred to"], x: 54, top: 700)
    let right = column(["herein as the atmospheric boundary-layer. The importance of",
                        "the atmospheric boundary-layer upon launch vehicle wind-",
                        "induced oscillation response has long been questioned, and its"], x: 310, top: 700)
    let folio = line("2", x: 300, y: 630, width: 6)
    let figure = LayoutReconstructor.Element(rect: CGRect(x: 54, y: 720, width: 496, height: 60), image: "image-0")
    let region = right + [folio, figure] + left
    // Nothing else separates the columns: the sort alone interleaves them.
    #expect(texts(LayoutReconstructor.sortedByRows(region, bodySize: 10)).prefix(2)
        == [texts(left)[0], texts(right)[0]])
    let parts = LayoutReconstructor.marginBands(region, bodySize: 10) {
        LayoutReconstructor.whitespaceCut(horizontal: true, measuring: $0.filter { $0.line != nil }, in: $0, bodySize: 10)
    }
    #expect(parts?.head.count == 1 && parts.map { texts($0.foot) } == ["2"])
    #expect(texts(LayoutReconstructor.ordered(region, bodySize: 10)) == texts(left) + texts(right) + ["2"])

    // Control: a scanned table's halves are rows of figures, not prose, and keep the row order.
    let cells = ["0 I I 0.0 3.7 II8 I 0 I /1,0 tJ.o 0.0", "I 3 4 /~.] :n., 6 I 7 78.(, 1./'6 B.'/",
                 "u I) l,f S'7./ D. 0 lf7. / 13.Z 9., 33,3"]
    let table = column(cells, x: 54, top: 700) + column(cells, x: 310, top: 700)
    #expect(LayoutReconstructor.marginBands(table + [folio], bodySize: 10) {
        LayoutReconstructor.whitespaceCut(horizontal: true, measuring: $0.filter { $0.line != nil }, in: $0, bodySize: 10)
    } == nil)

    // Control: a scan whose lines merge the margin rule beside them is not a column of prose.
    let merged = column(["I INTRODUCTION", "I REDUCTION OF DATA TO MECHANIZED", "I Questionnaire ."],
                        x: 10, top: 700, width: 240, size: 32)
    #expect(LayoutReconstructor.marginBands(merged + right + [folio], bodySize: 10) {
        LayoutReconstructor.whitespaceCut(horizontal: true, measuring: $0.filter { $0.line != nil }, in: $0, bodySize: 10)
    } == nil)
}

// A band both columns break at reads down each column; a band under a section does not.
@Test func onlyABandBothColumnsRunOnBeneathGivesWayToTheGutter() {
    func gutter(_ part: [LayoutReconstructor.Element]) -> CGFloat? {
        LayoutReconstructor.whitespaceCut(horizontal: true, measuring: part.filter { $0.line != nil },
                                          in: part, bodySize: 10)
    }
    let left = column(["winds prior to launch. Of particular interest is the dynamic",
                       "response of a launch vehicle when a von Karman vortex street",
                       "forms in the wake of the vehicle resulting in quasiperiodic lift"], x: 54, top: 540)
    let right = column(["comparisons. Loads created by the resonant response events",
                        "were substantially stronger than those from the nonresonant",
                        "response events. Therefore, if testing is done to simply identify"], x: 310, top: 540)
    let bandY = 540 - 3 * 11.5 - 5.2
    let lower = column(["Wind approaching the vehicle can be characterized by a varying",
                        "speed with height and turbulence content. The combination of"], x: 54, top: bandY - 5.2)
        + column(["herein as the atmospheric boundary-layer. The importance of",
                  "the atmospheric boundary-layer upon launch vehicle wind-"], x: 310, top: bandY - 5.2)
    let columns = left + right + lower
    let parts = LayoutReconstructor.marginBands(columns, bodySize: 10, across: bandY, gutter: gutter)
    #expect(parts.map { $0.gutter > 294 && $0.gutter < 310 } == true)
    #expect(LayoutReconstructor.breaksBothColumns(columns, gutter: 303, band: bandY, bodySize: 10))

    // Controls: a section heading opening the left column beneath the band, and a right column
    // that ended well above it, are section breaks and keep the horizontal cut.
    let heading = [line("Consume Dairy", x: 54, y: bandY - 28.6, width: 150, height: 23.4, size: 18)]
        + column(["When consuming dairy, include full-fat dairy with no added",
                  "sugars. Dairy is an excellent source of protein and vitamins"], x: 54, top: bandY - 45)
        + Array(lower.suffix(2))
    #expect(LayoutReconstructor.marginBands(left + right + heading, bodySize: 10, across: bandY, gutter: gutter) == nil)
    let ended = left + column(["comparisons. Loads created by the resonant response events"], x: 310, top: 600)
        + lower
    #expect(LayoutReconstructor.marginBands(ended, bodySize: 10, across: bandY, gutter: gutter) == nil)
}

// The cut moves inside the gutter only where prose runs beside prose.
@Test func theCutMovesPastAnOverhangingFigureOnlyBetweenProseColumns() {
    let left = column(["it is generally incorrect to conclude that all the time",
                       "instants at k are available to flight f. This is because the",
                       "availability of node k to flight f is affected not only by the"], x: 49, top: 200, width: 251)
    let right = column(["Fig. 2: (A) The only times (shown in blue) reachable at node",
                        "k+1 by leaving node k at time instant Tk. (B) With a different",
                        "choice of Tk, on leaving node k at time Tk, flight f can reach"], x: 312, top: 196, width: 251)
    // The crop overhangs the left column to 310.4, short of the right column's edge.
    let crop = LayoutReconstructor.Element(rect: CGRect(x: 80, y: 357, width: 230, height: 384), image: "image-0")
    let cut = LayoutReconstructor.whitespaceCut(horizontal: true, measuring: (left + right).filter { $0.line != nil },
                                                in: left + right + [crop], bodySize: 10)
    #expect(cut.map { $0 > 310.4 && $0 < 312 } == true)
    #expect(texts(LayoutReconstructor.ordered(left + right + [crop], bodySize: 10)) == texts(left) + texts(right))

    // Control: notes beside formula crops are not two prose columns, so the overhanging crop keeps
    // the region whole and the rows read in turn.
    let notes = [line("Identify LCD (use highest exponent)", x: 274, y: 200, width: 176),
                 line("Multiply each term by LCD", x: 274, y: 160, width: 130)]
    let crops = [LayoutReconstructor.Element(rect: CGRect(x: 93, y: 190, width: 180, height: 30), image: "image-1"),
                 LayoutReconstructor.Element(rect: CGRect(x: 93, y: 150, width: 182, height: 30), image: "image-2")]
    #expect(LayoutReconstructor.whitespaceCut(horizontal: true, measuring: notes, in: notes + crops, bodySize: 10) == nil)
}

// Pages 9-11: the paragraph that opens `Dynamic Loads due to Lift` on page 9 runs through both of
// page 10's columns into page 11, so page 10's marker lies inside it. Figure 16 and its caption
// therefore follow the joined paragraph instead of reading ahead of it, inside page 9.
@Test func aCrossedPagesFigureFollowsTheParagraphThatRunsThroughIt() throws {
    let pages = try ["ntrs-9", "gwl-10", "gwl-11"].map { name -> PageContent in
        let fixture = try SourceLayoutFixture.load(name)
        #expect(fixture.sourceSHA256 == gwlSHA256)
        return fixture.content()
    }
    var blocks: [ReflowBlock] = []
    var warnings: [ConversionWarning] = []
    var previous: PageContent?
    var previousRegions: [CGRect] = []
    for page in pages {
        let regions = LayoutReconstructor.graphicsWithLabels(page)
        let images = regions.enumerated().map { ($0.element, "image-\(page.number)-\($0.offset)") }
        let pageBlocks = LayoutReconstructor.blocks(page: page, images: images, vocabulary: [], warnings: &warnings)
        LayoutReconstructor.appendPage(pageBlocks, page: page, images: regions, previousPage: previous,
            previousImages: previousRegions, to: &blocks, vocabulary: [], warnings: &warnings)
        previous = page
        previousRegions = regions
    }
    let paragraph = try #require(blocks.firstIndex { $0.text.hasPrefix("Dynamic Loads due to Lift") })
    let caption = try #require(blocks.firstIndex { $0.text.hasPrefix("Figure 16. Static bending moment") })
    #expect(blocks[paragraph].sourcePages == [10, 11])
    #expect(caption > paragraph)
}
