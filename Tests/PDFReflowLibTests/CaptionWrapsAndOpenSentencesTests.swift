import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// The last sentences split around figures after #118 (#145): a caption's wrapped line read apart from
// the caption, a column's last line that ends short on a comma, a parenthesis left open, and a paragraph
// the source tags as one across a figure. Fixtures are native extraction from checksum-pinned sources;
// every expected phrase was read against the rendered pages, not converter output.

private let faaSHA256 = "247929cace0ab56b376e683eba540cc4c8f39f199ab35414e8b604e24f395cb7"
private let fedSHA256 = "8db8fd9e1de63ac25a6f9585d78ded12f45ab56f0c14c52c199b36b368f84d60"
private let nbsSHA256 = "44653967317ce75f324b8051cdf2f123429ca1cbd199fefbffabe9acb9b0c86d"
private let ntrsSHA256 = "a98e4fcdea40b8ea7023880dd88966f04198b4ec311fced0bb9ebb2dec45fe6d"

private func source(_ name: String, sha256: String = faaSHA256) throws -> PageContent {
    let fixture = try SourceLayoutFixture.load(name)
    #expect(fixture.sourceSHA256 == sha256)
    return fixture.content()
}

/// The pipeline's reconstruction pass over consecutive pages: preserved regions (none when
/// `crops` is false), per-page blocks and the cross-page join.
private func reconstruct(_ pages: [PageContent], crops: Bool = true) -> [ReflowBlock] {
    var blocks: [ReflowBlock] = []
    var warnings: [ConversionWarning] = []
    var previous: PageContent?
    var previousRegions: [CGRect] = []
    for page in pages {
        let regions = crops ? LayoutReconstructor.graphicsWithLabels(page) : []
        let images = regions.enumerated().map { ($0.element, "image-\(page.number)-\($0.offset)") }
        let pageBlocks = LayoutReconstructor.blocks(page: page, images: images, vocabulary: [], warnings: &warnings)
        LayoutReconstructor.appendPage(pageBlocks, page: page, images: regions, previousPage: previous,
            previousImages: previousRegions, to: &blocks, vocabulary: [], warnings: &warnings)
        previous = page
        previousRegions = regions
    }
    return blocks
}

private func paragraph(_ blocks: [ReflowBlock], containing phrase: String) -> ReflowBlock? {
    blocks.first { $0.text.contains(phrase) }
}

// MARK: Wrapped caption lines

// FAA page 391: figure 16-4's caption sits at the left column's foot beside the right column's last
// lines, and the row sort read `be completed before dark…` between `Figure 16-4. Meridians and
// parallels—the basis of measuring time,` and its wrapped line `distance, and direction.`, which
// became a body paragraph after the one that continues on page 392.
@Test func captionKeepsTheLineItWrapsOntoAcrossTheOtherColumn() throws {
    let blocks = reconstruct([try source("faa-391"), try source("faa-392")])
    #expect(blocks.contains { $0.text == "Figure 16-4. Meridians and parallels—the basis of measuring time, distance, and direction." })
    #expect(!blocks.contains { $0.text == "distance, and direction." })
    let joined = try #require(paragraph(blocks, containing: "Remember, an hour is lost when flying eastward from one time zone"))
    #expect(joined.page == 391 && joined.sourcePages == [392])
}

// FAA pages 341–342: figure 14-8's caption wraps onto `on Taxiway Kilo.` beside the left column's
// `thresholds. Figure 14-10…` line, and figure 14-9's onto `14 with collocated Taxiway Alpha location
// sign.` with figure 14-7's caption read between. Whole captions let the column's lines rejoin and the
// paragraph run on to page 342's `Runway 36 is to the right.`
@Test func wrappedCaptionLinesRejoinTheirCaptionsAndReleaseTheColumnJoin() throws {
    let blocks = reconstruct([try source("faa-341"), try source("faa-342")])
    #expect(blocks.contains { $0.text == "Figure 14-8. Runway safety area boundary sign and marking located on Taxiway Kilo." })
    #expect(blocks.contains { $0.text == "Figure 14-9. Runway holding position sign at takeoff end of Runway 14 with collocated Taxiway Alpha location sign." })
    let joined = try #require(paragraph(blocks, containing: "“18-36” to indicate the threshold for Runway 18 is to the left and the threshold for Runway 36 is to the right."))
    #expect(joined.page == 341 && joined.sourcePages == [342])
}

// Fed page 13, negative control: the 10-point bold title `Figure 1.4. Federal Reserve net earnings are
// paid to the U.S. Treasury` stands directly over its 8-point description. The paragraph rule read the
// two lines in sequence and set them apart; nothing was read between them, so they stay apart.
@Test func captionLineReadInSequenceKeepsTheParagraphRulesBreak() throws {
    let blocks = reconstruct([try source("fed-13-tagged", sha256: fedSHA256)])
    #expect(blocks.contains { $0.text == "Figure 1.4. Federal Reserve net earnings are paid to the U.S. Treasury" })
    #expect(blocks.contains { $0.text == "The Federal Reserve transfers its net earnings to the U.S. Treasury." })
}

// NASA paper page 9, negative control: the right column's body sentence `…and is illustrated in` wraps onto
// `Figure 14. These peak values acquired in uniform flow and`, which opens like a caption, and reading
// order interleaves the columns. A caption's wrap is set smaller than the body; these 10-point lines stay
// body text.
@Test func bodyTypeLineOpeningWithAFigureReferenceTakesNoWrap() throws {
    let blocks = reconstruct([try source("ntrs-9", sha256: ntrsSHA256)])
    #expect(!blocks.contains { $0.text.hasPrefix("Figure 14. These peak values") && $0.text.contains("made about this data set") })
}

@Test func captionWrapNeedsTheNextLineOnTheCaptionsEdgeAtItsLeading() {
    func line(_ text: String, x: Double = 36, y: Double, width: Double = 236, size: Double = 9) -> TextLine {
        TextLine(text: text, rect: CGRect(x: x, y: y, width: width, height: size + 1.2), fontSize: size)
    }
    let last = line("Figure 16-4. Meridians and parallels—the basis of measuring time,", y: 82.4, size: 8)
    func wraps(_ first: TextLine, extra: [TextLine] = []) -> Bool {
        let page = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: [last, first] + extra, graphics: [])
        return LayoutReconstructor.wrapsCaption(last, onto: first, page: page, body: 10)
    }
    #expect(wraps(line("distance, and direction.", y: 70.5, width: 85)))
    // Centred wraps share the caption's centre instead of its edge.
    #expect(wraps(line("distance, and direction.", x: 111.5, y: 70.5, width: 85)))
    // Off the edge and the centre, below a paragraph space, above the caption, or set larger.
    #expect(!wraps(line("distance, and direction.", x: 60, y: 70.5, width: 85)))
    #expect(!wraps(line("distance, and direction.", y: 60, width: 85)))
    #expect(!wraps(line("distance, and direction.", y: 94, width: 85)))
    #expect(!wraps(line("distance, and direction.", y: 70.5, width: 85, size: 9.2)))
    // A line between them.
    #expect(wraps(line("distance, and direction.", y: 66, width: 85)))
    #expect(!wraps(line("distance, and direction.", y: 66, width: 85), extra: [line("a note", y: 77, width: 40, size: 3)]))
}

@Test func onlyAnOpenCaptionTakesALineReadApartFromIt() {
    // FAA page 391's arrangement: a caption at the left foot (its figure above) beside the right
    // column's last lines, with too little prose on the left for a column cut, so the row sort reads
    // a right-column line between the caption and its wrapped line.
    func texts(caption: String, wrap: String = "distance, and direction.", wrapY: Double = 70.5, extra: [TextLine] = []) -> [String] {
        let lines = [
            TextLine(text: "Body prose that fills the right column to its edge on every", rect: CGRect(x: 285, y: 91, width: 237, height: 11.5), fontSize: 10),
            TextLine(text: caption, rect: CGRect(x: 36, y: 82.4, width: 236, height: 10.8), fontSize: 8),
            TextLine(text: "line down to the foot of the column where it ends.", rect: CGRect(x: 285, y: 78.5, width: 237, height: 11.5), fontSize: 10),
            TextLine(text: wrap, rect: CGRect(x: 36, y: wrapY, width: 85, height: 10.2), fontSize: 9),
        ] + (0..<4).map { TextLine(text: "More body prose above that fills the right column measure", rect: CGRect(x: 285, y: 103.5 + 12.5 * Double($0), width: 237, height: 11.5), fontSize: 10) } + extra
        var warnings: [ConversionWarning] = []
        return LayoutReconstructor.blocks(page: PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines, graphics: []),
                                          images: [], vocabulary: [], warnings: &warnings).map(\.text)
    }
    let open = texts(caption: "Figure 16-4. Meridians and parallels—the basis of measuring time,")
    #expect(open.contains("Figure 16-4. Meridians and parallels—the basis of measuring time, distance, and direction."))
    // A caption that closes its sentence keeps the line beneath apart.
    let closed = texts(caption: "Figure 16-4. Meridians and parallels measuring time.", wrap: "Source: the National Atlas.")
    #expect(closed.contains("Source: the National Atlas."))
    // A second caption does not wrap the first.
    let second = texts(caption: "Figure 16-4. Meridians and parallels—the basis of measuring time,", wrap: "Figure 16-5. Time zones.")
    #expect(second.contains("Figure 16-5. Time zones."))
    // A later paragraph that does not open on the line beneath is not taken, even when a line lies there.
    let foot = TextLine(text: "A separate note set at the foot of the page.", rect: CGRect(x: 285, y: 30, width: 180, height: 11.5), fontSize: 10)
    let beside = texts(caption: "Figure 16-4. Meridians and parallels—the basis of measuring time,", wrap: "Figure 16-5. Time zones.", extra: [foot])
    #expect(beside.contains("Figure 16-4. Meridians and parallels—the basis of measuring time,"))
    // No line beneath the caption: no later paragraph is taken, the right column's included.
    let far = texts(caption: "Figure 16-4. Meridians and parallels—the basis of measuring time,", wrapY: 30)
    #expect(far.contains("Figure 16-4. Meridians and parallels—the basis of measuring time,"))
    // Read in sequence and set apart by the paragraph rule (a caption line the text layer marks
    // unwrapped), the wrap stays apart: a single column, nothing read between.
    func single(captionWraps: Bool?) -> [String] {
        let lines = [TextLine(text: "Body prose above the figure fills the column to its edge on every", rect: CGRect(x: 36, y: 120, width: 237, height: 11.5), fontSize: 10),
                     TextLine(text: "line down to the figure below it where the column continues.", rect: CGRect(x: 36, y: 107.5, width: 237, height: 11.5), fontSize: 10),
                     TextLine(text: "Figure 16-4. Meridians and parallels—the basis of measuring time,", rect: CGRect(x: 36, y: 82.4, width: 236, height: 10.8), fontSize: 8, wraps: captionWraps),
                     TextLine(text: "distance, and direction.", rect: CGRect(x: 36, y: 70.5, width: 85, height: 10.2), fontSize: 9)]
        var warnings: [ConversionWarning] = []
        return LayoutReconstructor.blocks(page: PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines, graphics: []),
                                          images: [], vocabulary: [], warnings: &warnings).map { $0.text }
    }
    #expect(single(captionWraps: nil).contains("Figure 16-4. Meridians and parallels—the basis of measuring time, distance, and direction."))
    #expect(single(captionWraps: false).contains("distance, and direction."))
}

// MARK: A column's last line ending on a comma

// FAA pages 221–222 and 438–439: `compass. Errors in the magnetic compass are numerous,` and `list, states
// have taken steps to allow the possession, sale,` end their columns short of the justified edge (the
// shows' measured advances agree with PDFKit: 535.7 and 510.5 against 562.3 and 522.1). The next pages
// open `making straight flight…` and `and use of marijuana…`.
@Test func lineEndingOnACommaContinuesAcrossThePage() throws {
    let compass = reconstruct([try source("faa-221"), try source("faa-222")])
    let heading = try #require(paragraph(compass, containing: "compass are numerous, making straight flight and precision turns"))
    #expect(heading.page == 221 && heading.sourcePages == [222])
    let drugs = reconstruct([try source("faa-438"), try source("faa-439")])
    let marijuana = try #require(paragraph(drugs, containing: "the possession, sale, and use of marijuana"))
    #expect(marijuana.page == 438 && marijuana.sourcePages == [439])
}

// NBS page 1, negative control: the 3-point footnote `I Figures ill brackets indicllLe the literature
// references al the end of thi s paper,` (a period read as a comma) ends the left column; the right
// column opens `where u (t) = Uo sinwt…` after an equation. The footnote is not body type.
@Test func commaEndingInOtherTypeDoesNotContinueAColumn() throws {
    let blocks = reconstruct([try source("nbs-1", sha256: nbsSHA256)], crops: false)
    #expect(!blocks.contains { $0.text.contains("end of thi s paper, where u (t)") })
    #expect(blocks.contains { $0.text.hasPrefix("where u (t) = Uo sinwt") })
}

@Test func shortCommaLineNeedsProseAndALowercaseOpening() {
    let letter = CGRect(x: 0, y: 0, width: 612, height: 792)
    func column(_ texts: [(String, Double)], x: Double = 60, top: Double) -> [TextLine] {
        texts.enumerated().map { TextLine(text: $1.0, rect: CGRect(x: x, y: top - 14 * Double($0), width: $1.1, height: 12), fontSize: 12) }
    }
    let rest = [("The office was given a crucial role in coordinating the work of every agency in", 230.0),
                ("the city during an emergency, and its director was expected to arrive at the", 230.0)]
    let head = "whose liaisons would report to the center as soon as the incident was declared"
    /// Across a page break, or from the left column's foot to the right column's head on one page.
    func joins(_ last: (String, Double), head: String = head, samePage: Bool = false) -> Bool {
        let foot = column(rest + [last], top: 146)
        let next = column([(head, 230), rest[0], rest[1]], x: samePage ? 320 : 60, top: samePage ? 700 : 740)
        let pages = samePage
            ? [PageContent(number: 1, bounds: letter, lines: foot + next, graphics: [])]
            : [PageContent(number: 1, bounds: letter, lines: foot, graphics: []),
               PageContent(number: 2, bounds: letter, lines: next, graphics: [])]
        return reconstruct(pages).contains { $0.text.contains(last.0 + " " + head) }
    }
    for samePage in [false, true] {
        #expect(joins(("of each major incident, the mayor, the police chief,", 190), samePage: samePage))
        // Not a comma after a word, too few words, too narrow, or before a capital.
        #expect(!joins(("of each major incident, the mayor, the police chief", 190), samePage: samePage))
        #expect(!joins(("of each major incident, the mayor, the police chief 12,", 190), samePage: samePage))
        #expect(!joins(("a b c d e f,", 190), samePage: samePage))
        #expect(!joins(("of each major incident, the mayor,", 100), samePage: samePage))
        #expect(!joins(("of each major incident, the mayor, the police chief,", 190),
                       head: "Whose liaisons would report to the center as soon as the incident was declared", samePage: samePage))
        // A capital that an open parenthesis admits still needs the line to fill its column.
        #expect(!joins(("of each major incident (the mayor, the police chief,", 190),
                       head: "Whose liaisons would report to the center as soon as the incident was declared", samePage: samePage))
    }
}

// MARK: Capital openings: an open parenthesis, one tagged paragraph

// FAA pages 169–170: `…(versus relative) Fahrenheit degrees (70 x 100/180 = 38.89` / `Celsius degrees)
// (Remember there are 180 Fahrenheit degrees`.
@Test func openParenthesisContinuesBeforeACapital() throws {
    let blocks = reconstruct([try source("faa-169"), try source("faa-170")])
    let joined = try #require(paragraph(blocks, containing: "(70 x 100/180 = 38.89 Celsius degrees) (Remember"))
    #expect(joined.page == 169 && joined.sourcePages == [170])
}

@Test func parenthesisIsOpenOnlyInTheLastSentence() {
    #expect(LayoutReconstructor.leavesParenthesisOpen("absolute (versus relative) Fahrenheit degrees (70 x 100/180 = 38.89"))
    #expect(LayoutReconstructor.leavesParenthesisOpen("(quoting Allentown Mack Sales &"))
    #expect(!LayoutReconstructor.leavesParenthesisOpen("absolute (versus relative) Fahrenheit degrees"))
    // Opened in an earlier sentence (the text since the last sentence end is balanced).
    #expect(!LayoutReconstructor.leavesParenthesisOpen("the drop (see figure 7-12. The ice forms"))
    #expect(!LayoutReconstructor.leavesParenthesisOpen("It cools. The drop (see figure 7-12. The ice forms"))
    #expect(LayoutReconstructor.leavesParenthesisOpen("It cools. The drop is (see figure 7-12). Ice forms (at"))
    #expect(!LayoutReconstructor.leavesParenthesisOpen("the drop (see figure 7-12). The ice forms"))
    // A sentence end inside a quotation or bracket still bounds the last sentence.
    #expect(LayoutReconstructor.leavesParenthesisOpen("it ended.” Then (as noted"))
    func continues(_ left: String, _ right: String, sameTag: Bool = false) -> Bool {
        LayoutReconstructor.continuesSentence(InlineText(left), into: InlineText(right), sameTag: sameTag)
    }
    #expect(continues("Fahrenheit degrees (70 x 100/180 = 38.89", "Celsius degrees)"))
    #expect(!continues("Fahrenheit degrees 70 x 100/180 = 38.89", "Celsius degrees"))
    #expect(continues("education. The FAA", "Safety Team", sameTag: true))
    #expect(!continues("education. The FAA", "Safety Team"))
    #expect(!continues("education. The FAA.", "Safety Team", sameTag: true))
}

// FAA page 24: the left column ends `…through training, outreach, and education. The FAA` over figure
// 1-13; the right column opens `Safety Team (FAASTeam) exemplifies this commitment.` The structure tree
// holds both lines in one `P` (the figure interrupts it, so the group falls back); `FAA` can end a
// sentence, and only the tag says this one does not.
@Test func oneTaggedParagraphContinuesBeforeACapital() throws {
    let page = try source("faa-24-tagged")
    #expect(paragraph(reconstruct([page]), containing: "education. The FAA Safety Team (FAASTeam) exemplifies") != nil)
    // Untagged, or tagged as two paragraphs or as a heading, the capital opens a new sentence.
    func retagged(_ change: (inout TextStructure) -> Void) -> PageContent {
        var copy = page
        for index in copy.lines.indices where copy.lines[index].text.hasPrefix("Safety Team (FAASTeam)") {
            if var tag = copy.lines[index].structure { change(&tag); copy.lines[index].structure = tag }
        }
        return copy
    }
    var untagged = page
    for index in untagged.lines.indices { untagged.lines[index].structure = nil }
    #expect(paragraph(reconstruct([untagged]), containing: "The FAA Safety Team") == nil)
    #expect(paragraph(reconstruct([retagged { $0.group += 100_000 }]), containing: "The FAA Safety Team") == nil)
    #expect(!LayoutReconstructor.sameParagraphTag(
        TextLine(text: "a", rect: .zero, fontSize: 10).tagged(TextStructure(group: 7, order: 0, headingLevel: 2)),
        TextLine(text: "b", rect: .zero, fontSize: 10).tagged(TextStructure(group: 7, order: 1, headingLevel: 2))))
    #expect(LayoutReconstructor.sameParagraphTag(
        TextLine(text: "a", rect: .zero, fontSize: 10).tagged(TextStructure(group: 7, order: 0, headingLevel: 0)),
        TextLine(text: "b", rect: .zero, fontSize: 10).tagged(TextStructure(group: 7, order: 1, headingLevel: 0))))
}

// FAA pages 20–21: `…the responsibility of administering the Federal Aid` ends page 20 and `Airport
// Program. This program was designed…` opens page 21, both lines in one tagged `P`.
@Test func oneTaggedParagraphContinuesAcrossThePage() throws {
    let blocks = reconstruct([try source("faa-20-tagged"), try source("faa-21-tagged")])
    let joined = try #require(paragraph(blocks, containing: "administering the Federal Aid Airport Program. This program"))
    #expect(joined.page == 20 && joined.sourcePages == [21])
}

private extension TextLine {
    func tagged(_ structure: TextStructure) -> TextLine {
        var copy = self
        copy.structure = structure
        return copy
    }
}
