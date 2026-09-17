import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// Sentences split by a figure, caption or figure page between a column's foot and the next
// column's head (#118). Fixtures are native extraction from the checksum-pinned FAA handbook; every
// expected phrase was read against the rendered pages, not converter output.

private let faaSHA256 = "247929cace0ab56b376e683eba540cc4c8f39f199ab35414e8b604e24f395cb7"

private func source(_ name: String) throws -> PageContent {
    let fixture = try SourceLayoutFixture.load(name)
    #expect(fixture.sourceSHA256 == faaSHA256)
    return fixture.content()
}

/// The pipeline's reconstruction pass: preserved regions, per-page blocks and the cross-page join,
/// with pages that hold only figures kept aside (at most two) as the pipeline keeps them.
private func reconstruct(_ pages: [PageContent], skipFigurePages: Bool = true) -> [ReflowBlock] {
    var blocks: [ReflowBlock] = []
    var warnings: [ConversionWarning] = []
    var previous: PageContent?
    var previousRegions: [CGRect] = []
    var figurePages: [(page: PageContent, images: [CGRect])] = []
    for page in pages {
        let regions = LayoutReconstructor.graphicsWithLabels(page)
        let images = regions.enumerated().map { ($0.element, "image-\(page.number)-\($0.offset)") }
        let pageBlocks = LayoutReconstructor.blocks(page: page, images: images, vocabulary: [], warnings: &warnings)
        LayoutReconstructor.appendPage(pageBlocks, page: page, images: regions, previousPage: previous,
            previousImages: previousRegions, skippedPages: previous == nil ? [] : figurePages,
            to: &blocks, vocabulary: [], warnings: &warnings)
        if skipFigurePages, previous != nil, figurePages.count < 2,
           LayoutReconstructor.holdsOnlyFigures(pageBlocks, page: page) {
            figurePages.append((page, regions))
        } else {
            previous = page
            previousRegions = regions
            figurePages = []
        }
    }
    return blocks
}

private func index(_ blocks: [ReflowBlock], _ phrase: String) -> Int? {
    blocks.firstIndex { $0.text.contains(phrase) }
}

private func isImage(_ block: ReflowBlock) -> Bool {
    if case .image = block.content { true } else { false }
}

// MARK: Source reproducers

// FAA page 21: `…then, now, and into` ends the left column over a portrait; the right column opens
// `the future.` under figure 1-10, whose caption wraps onto `Richard “Pete” Quesada, 1959–1961.`
// That 9-pt wrapped line competed as prose above the head; it belongs to the caption.
@Test func wrappedCaptionLineDoesNotCompeteWithAColumnJoin() throws {
    let blocks = reconstruct([try source("faa-21-continuation")])
    let joined = try #require(index(blocks, "then, now, and into the future. The DOT began operation"))
    let caption = try #require(index(blocks, "Figure 1-10."))
    #expect(caption > joined, "the caption follows the joined paragraph")
    #expect(blocks.contains { $0.text.hasSuffix("Richard “Pete” Quesada, 1959–1961.") && $0.text.hasPrefix("Figure 1-10.") })
}

// FAA pages 68–69: `…take place in the` ends page 68's left column; page 69's left column opens
// `landing phase,` and its right column's foot holds figure 2-24's wrapped caption, which competed
// beside the anchor.
@Test func wrappedCaptionLineDoesNotCompeteAcrossPages() throws {
    let blocks = reconstruct([try source("faa-68"), try source("faa-69")])
    let paragraph = try #require(blocks.first { $0.text.contains("GA accidents take place in the landing phase, one realm of flight") })
    #expect(paragraph.page == 68 && paragraph.sourcePages == [69])
    #expect(blocks.contains { $0.text.hasPrefix("Figure 2-24.") && $0.text.hasSuffix("Cirrus Entega.") })
}

// FAA page 230: the OAT gauge (figure 8-39) sits beside the paragraph in the right column, and
// reading order put it between `…in a single strip and twisted` and `into a helix.`, the next line.
@Test func figureBesideAParagraphDoesNotSplitIt() throws {
    let blocks = reconstruct([try source("faa-230")])
    let joined = try #require(index(blocks, "welded together in a single strip and twisted into a helix. One end is anchored"))
    let caption = try #require(index(blocks, "Figure 8-39."))
    #expect(caption > joined)
    #expect(blocks[(joined + 1)...].contains(where: isImage))
}

// FAA page 411: the left column ends `…by means of the` above figure 16-29; the right column opens
// `course select knob.` below figure 16-30, lower on the page than the foot it continues.
@Test func continuationBeneathTheFigureHeadingTheNextColumn() throws {
    let blocks = reconstruct([try source("faa-411")])
    let joined = try #require(index(blocks, "in relation to the compass card, by means of the course select knob. The HSI has"))
    for caption in ["Figure 16-29.", "Figure 16-30."] {
        #expect(try #require(index(blocks, caption)) > joined)
    }
}

// FAA pages 286–287: `…a rate of about 2 °Celsius (C) every` / `1,000 feet of altitude gain` (the
// issue's page 286). A digit carries the sentence on after a word that cannot end one; figure 12-2
// keeps page 286, ahead of the paragraph.
@Test func digitContinuesASentenceAfterAnOpenWord() throws {
    let blocks = reconstruct([try source("faa-286"), try source("faa-287")])
    let paragraph = try #require(blocks.first { $0.text.contains("about 2 °Celsius (C) every 1,000 feet of altitude gain") })
    #expect(paragraph.page == 286 && paragraph.sourcePages == [287])
    let position = try #require(blocks.firstIndex { $0 == paragraph })
    #expect(try #require(index(blocks, "Figure 12-2. Layers of the atmosphere.")) < position)
    #expect(!blocks.contains { $0.content == .sourcePage(287) })
}

// FAA pages 45–47: page 46 is a full-page risk assessment form (figure 2-6). Page 45 ends
// `…assesses health, fatigue, weather,` and page 47 opens `capabilities, etc.`. The form and its
// caption follow the paragraph, and both page boundaries sit at the text boundary.
@Test func paragraphContinuesPastAPageHoldingOnlyAFigure() throws {
    let pages = [try source("faa-45-continuation"), try source("faa-46"), try source("faa-47")]
    let blocks = reconstruct(pages)
    let paragraph = try #require(blocks.first { $0.text.contains("assesses health, fatigue, weather, capabilities, etc. The scores") })
    #expect(paragraph.page == 45 && paragraph.sourcePages == [46, 47])
    #expect(!blocks.contains { $0.content == .sourcePage(46) || $0.content == .sourcePage(47) })
    let position = try #require(blocks.firstIndex { $0 == paragraph })
    #expect(try #require(index(blocks, "Figure 2-6.")) > position)
    #expect(blocks[(position + 1)...].contains { isImage($0) && $0.page == 46 })
    // Control: joining only adjacent pages leaves the sentence split around the form.
    let adjacent = reconstruct(pages, skipFigurePages: false)
    #expect(!adjacent.contains { $0.text.contains("weather, capabilities") })
    #expect(adjacent.contains { $0.content == .sourcePage(46) } && adjacent.contains { $0.content == .sourcePage(47) })
}

// FAA page 341, negative control: `…and the threshold for` ends the left column; the continuation is on
// page 342. Beneath figure 14-9 in the right column, the caption's wrapped line `14 with collocated
// Taxiway Alpha location sign.` opens with a digit after an open word, but it is 9-pt caption type
// and must not join. The same column's `…respective runway` / `thresholds.`, split by figure 14-8's
// caption beside it, does join.
@Test func captionFragmentDoesNotContinueASentence() throws {
    let blocks = reconstruct([try source("faa-341")])
    #expect(!blocks.contains { $0.text.contains("threshold for 14 with collocated") })
    #expect(blocks.contains { $0.text.hasSuffix("and the threshold for") })
    #expect(index(blocks, "location of the respective runway thresholds. Figure 14-10 shows") != nil)
}

// FAA page 19, negative control: in this fixture's crops the full-width map region takes the right
// column's first four lines (`Department of Commerce made…` to `…apart, the`), so the first visible
// line there is `standard beacon tower…`. With figure 1-5's wrapped caption excused below the foot,
// only the swallowed body prose inside the crossing region stands against `…this system. The`.
@Test func proseSwallowedByTheRegionOverTheHeadRefusesTheJoin() throws {
    var page = try source("faa-19")
    page.lines.removeAll { $0.text == "1-4" }
    let blocks = reconstruct([page])
    #expect(!blocks.contains { $0.text.contains("this system. The standard beacon") })
    #expect(blocks.contains { $0.text.hasSuffix("had initiated this system. The") })
}

// MARK: Synthetic controls

private let letter = CGRect(x: 0, y: 0, width: 612, height: 792)

private func text(_ value: String) -> InlineText { InlineText(value) }

@Test func sentenceContinuationNeedsLowercaseOrAnOpenWord() {
    func continues(_ left: String, _ right: String) -> Bool {
        LayoutReconstructor.continuesSentence(text(left), into: text(right))
    }
    #expect(continues("rises at a rate of about two degrees", "per thousand feet"))
    #expect(continues("further increasing the", "AOA. In this situation"))
    #expect(continues("a rate of about 2 °C every", "1,000 feet of altitude gain"))
    #expect(continues("the motion about its lateral axis is", "“pitch,” and the motion"))
    #expect(continues("This increases the wing’s", "AOA and results in increased lift"))
    // A word that can end a sentence before a capital, digit or quote: a new sentence or a label.
    #expect(!continues("the scores are added to it all", "The next element is severity"))
    #expect(!continues("Abilene altimeter setting 29.69", "(Since 1 inch of pressure"))
    #expect(!continues("Service personnel, flight instructors, and ATC", "An understanding of the process"))
    #expect(continues("a Florida businessman's", "Report of 1914"))
    #expect(!continues("the report of Mr. O's", "Report of 1914"))
    // Terminal punctuation closes the sentence whatever follows.
    #expect(!continues("at the altitude of the.", "Every"))
    #expect(!continues("pressure decreases at a rate of the.", "next sentence opens lowercase"))
}

@Test func nextLineInColumnRequiresTheParagraphsOwnPitchAndEdge() {
    func line(_ y: Double, x: Double = 36, size: Double = 10, height: Double = 11.5) -> TextLine {
        TextLine(text: "materials are welded together in a single strip and twisted", rect: CGRect(x: x, y: y, width: 237, height: height), fontSize: size)
    }
    let page = { (lines: [TextLine]) in PageContent(number: 1, bounds: letter, lines: lines, graphics: []) }
    let last = line(651.2)
    // The next line at a 12.5-pt pitch, on the same edge.
    #expect(LayoutReconstructor.nextLineInColumn(last, line(638.7), page: page([last, line(638.7)]), body: 10))
    // A paragraph space (a 25-pt pitch) is a paragraph break.
    #expect(!LayoutReconstructor.nextLineInColumn(last, line(626.2), page: page([last, line(626.2)]), body: 10))
    // An indented first line, a different size, or a line between them.
    #expect(!LayoutReconstructor.nextLineInColumn(last, line(638.7, x: 48), page: page([last, line(638.7, x: 48)]), body: 10))
    #expect(!LayoutReconstructor.nextLineInColumn(last, line(638.7, size: 9), page: page([last, line(638.7, size: 9)]), body: 10))
    let middle = line(644.9, height: 4)
    #expect(!LayoutReconstructor.nextLineInColumn(last, line(638.7), page: page([last, middle, line(638.7)]), body: 10))
    // A line above the last one, or beside it in the other column.
    #expect(!LayoutReconstructor.nextLineInColumn(last, line(663.7), page: page([last, line(663.7)]), body: 10))
    #expect(!LayoutReconstructor.nextLineInColumn(last, line(638.7, x: 285), page: page([last, line(638.7, x: 285)]), body: 10))
}

/// Two justified 12-pt columns: the left one ends `leftLast` at y 630; the right one opens with
/// `rightFirst` at `rightTop`, under `figure` when one is given.
private func twoColumns(leftLast: String = "the paragraph keeps running to the foot of the",
                        rightFirst: String = "column and continues at the head of the next one.",
                        rightTop: Double = 700, rightSize: Double = 12, rightFirstWidth: Double = 240,
                        figure: CGRect? = nil, tints: [CGRect] = [], extra: [TextLine] = []) -> [String] {
    let lefts = ["Opening words of a paragraph that fills this", "column with ordinary prose set on a justified",
                 "measure so every line reaches the right edge", "of the column and wraps at the same width as",
                 "the others above and below it in the text, and", leftLast]
    let left = lefts.enumerated().map { TextLine(text: $1, rect: CGRect(x: 40, y: 700 - 14 * Double($0), width: 240, height: 13), fontSize: 12) }
    let rights = [rightFirst, "The right column carries on with more prose that", "fills its measure in the same way as the left one",
                  "does, each line reaching the shared right edge", "of the column until the paragraph ends on this"]
    let right = rights.enumerated().map {
        TextLine(text: $1, rect: CGRect(x: 300, y: rightTop - 14 * Double($0), width: $0 == 0 ? rightFirstWidth : 240,
                                        height: $0 == 0 ? rightSize + 1 : 13),
                 fontSize: $0 == 0 ? rightSize : 12)
    }
    var page = PageContent(number: 1, bounds: letter, lines: left + right + extra, graphics: [])
    page.tints = tints
    var warnings: [ConversionWarning] = []
    let crops = figure.map { [$0] } ?? []
    return LayoutReconstructor.blocks(page: page, images: crops.enumerated().map { ($0.element, "image-\($0.offset)") },
        vocabulary: [], warnings: &warnings).map(\.text)
}

@Test func columnHeadBelowTheFootNeedsAFigureOverIt() {
    let joins = { (texts: [String]) in texts.contains { $0.contains("foot of the column and continues") } }
    // The right column's head sits below the left column's foot, under a figure that reaches above it.
    let figure = CGRect(x: 300, y: 600, width: 240, height: 150)
    #expect(joins(twoColumns(rightTop: 580, figure: figure)))
    // No figure over the head: the head below the foot is not that column's continuation.
    #expect(!joins(twoColumns(rightTop: 580)))
    // A body-size line across both columns above them bounds the section without competing itself.
    let across = TextLine(text: "A line of body text set across both columns above the section here", rect: CGRect(x: 40, y: 730, width: 500, height: 13), fontSize: 12)
    #expect(joins(twoColumns(extra: [across])))
    // A tinted box around the right column's text (it keeps its lines, unlike a crop) reaches above
    // the foot but does not stand over the head.
    let boxed = twoColumns(rightTop: 580, tints: [CGRect(x: 295, y: 510, width: 250, height: 190)])
    #expect(boxed.contains { $0.hasPrefix("column and continues at the head") })
    #expect(!joins(boxed))
    // A figure that ends below the foot's middle does not head a column beside it.
    #expect(!joins(twoColumns(rightTop: 560, figure: CGRect(x: 300, y: 575, width: 240, height: 50))))
    // Under the figure, a first line in other type does not continue the sentence.
    #expect(!joins(twoColumns(rightTop: 580, rightSize: 9, figure: figure)))
    // A digit after an open word joins in body type and refuses in caption type (FAA page 341).
    let digit = { (texts: [String]) in texts.contains { $0.contains("foot of the 14 columns") } }
    #expect(digit(twoColumns(rightFirst: "14 columns continue at the head of the next one.")))
    #expect(!digit(twoColumns(rightFirst: "14 columns continue at the head of the next one.", rightSize: 9)))
    // A capital on a short line (a title or credit) does not continue; a short line closing its
    // sentence does.
    let capital = { (texts: [String]) in texts.contains { $0.contains("foot of the Column") } }
    #expect(!capital(twoColumns(rightFirst: "Column Heading Credit Line", rightFirstWidth: 130)))
    #expect(capital(twoColumns(rightFirst: "Column heads end here.", rightFirstWidth: 130)))
}

@Test func onlyCaptionTypeInACaptionIsExcusedFromCompeting() {
    let joins = { (texts: [String]) in texts.contains { $0.contains("foot of the column and continues") } }
    // The figure and its caption stand a paragraph space above the right column's head.
    let figure = CGRect(x: 300, y: 766, width: 240, height: 20)
    let captionFirst = TextLine(text: "Figure 4. A figure over the right column head.", rect: CGRect(x: 300, y: 752, width: 200, height: 10), fontSize: 9)
    let wrapped = TextLine(text: "with a caption that wraps onto a second line here", rect: CGRect(x: 300, y: 741, width: 230, height: 10), fontSize: 9)
    let captionBlocks = twoColumns(figure: figure, extra: [captionFirst, wrapped])
    #expect(captionBlocks.contains { $0.hasPrefix("Figure 4.") && $0.hasSuffix("second line here") })
    #expect(joins(captionBlocks))
    // A caption set in body type: its wrapped line competes as prose above the head.
    let bodyCaption = TextLine(text: "Figure 4. A figure over the right column head.", rect: CGRect(x: 300, y: 752, width: 200, height: 12), fontSize: 12)
    let bodyWrapped = TextLine(text: "with a caption that wraps onto a second line here", rect: CGRect(x: 300, y: 738, width: 230, height: 12), fontSize: 12)
    let bodyBlocks = twoColumns(figure: figure, extra: [bodyCaption, bodyWrapped])
    #expect(bodyBlocks.contains { $0.hasPrefix("Figure 4.") && $0.hasSuffix("second line here") })
    #expect(!joins(bodyBlocks))
}

// 9/11 pages 301–302: `…the city’s overall response to an` ends page 301; page 302 opens with a
// rendering whose credit `The World Trade Center Radio Repeater System` is a short line. A capital after
// `an` continues only on a full line, or on a short one that closes its sentence (FAA page 127).
@Test func capitalOpeningAcrossPagesNeedsAFullLineInTheAnchorsType() {
    func column(_ texts: [(String, Double)], top: Double, size: Double = 12) -> [TextLine] {
        texts.enumerated().map { TextLine(text: $1.0, rect: CGRect(x: 60, y: top - 14 * Double($0), width: $1.1, height: size), fontSize: size) }
    }
    let foot = column([("The office was given a crucial role in coordinating the work of every agency in the", 460),
                       ("city during an emergency, and its director was expected to arrive quickly at the scene", 460),
                       ("of each major incident to take charge of the city’s overall response to an", 460)], top: 146)
    func joins(_ head: [(String, Double)], size: Double = 12) -> Bool {
        let pages = [PageContent(number: 1, bounds: letter, lines: foot, graphics: []),
                     PageContent(number: 2, bounds: letter, lines: column(head, top: 740, size: size), graphics: [])]
        return reconstruct(pages).contains { $0.text.contains("overall response to an Emergency") }
    }
    let rest = [("and every agency would send a liaison there, as well as the mayor and senior staff", 460.0),
                ("of the city, who would respond to the center as soon as the incident was declared.", 460.0)]
    #expect(joins([("Emergency Operations Center activation, after which designated liaisons from", 460)] + rest))
    // A short title or credit line.
    #expect(!joins([("Emergency Operations Center Rendering", 220)] + rest))
    // A short line that closes its sentence is the continuation's end.
    #expect(joins([("Emergency Operations Center activation.", 220)] + rest))
    // A full line in other type.
    #expect(!joins([("Emergency Operations Center activation, after which designated liaisons from", 460)] + rest, size: 9))
}

@Test func figurePageWithProseIsNotSteppedOver() {
    func column(_ texts: [String], top: Double, size: Double = 12) -> [TextLine] {
        texts.enumerated().map { TextLine(text: $1, rect: CGRect(x: 60, y: top - 14 * Double($0), width: 460, height: size), fontSize: size) }
    }
    let foot = column(["The committee reviewed the position paper prepared during the previous session and",
                       "recorded the objections raised by every delegate before the vote was called, noting",
                       "that the earlier draft had been circulated without the appendix that described the",
                       "sampling method in detail, and after a short adjournment the chair proposed that the"], top: 160)
    let head = column(["report be accepted without amendment provided that the appendix was attached to the",
                       "final version and circulated again to every member of the committee before the end"], top: 740)
    let caption = TextLine(text: "Figure 3. Objections recorded by delegation.", rect: CGRect(x: 60, y: 90, width: 220, height: 9), fontSize: 9)
    func pages(_ figureExtra: [TextLine]) -> [PageContent] {
        [PageContent(number: 1, bounds: letter, lines: foot, graphics: []),
         PageContent(number: 2, bounds: letter, lines: [caption] + figureExtra, graphics: [CGRect(x: 60, y: 110, width: 460, height: 600)]),
         PageContent(number: 3, bounds: letter, lines: head, graphics: [])]
    }
    let joined = { (blocks: [ReflowBlock]) in blocks.contains { $0.text.contains("proposed that the report be accepted") } }
    #expect(joined(reconstruct(pages([]))))
    // Two figure pages: every skipped page opens at the text boundary, in order.
    let figure = PageContent(number: 2, bounds: letter, lines: [caption], graphics: [CGRect(x: 60, y: 110, width: 460, height: 600)])
    var second = figure
    second.number = 3
    var last = pages([])[2]
    last.number = 4
    let twice = reconstruct([pages([])[0], figure, second, last])
    let continued = twice.first { $0.text.contains("proposed that the report be accepted") }
    #expect(continued?.sourcePages == [2, 3, 4])
    // A third figure page is beyond the bound.
    var third = figure
    third.number = 4
    last.number = 5
    #expect(!joined(reconstruct([pages([])[0], figure, second, third, last])))
    // A page holding a caption but no figure is not a figure page.
    let captionOnly = [pages([])[0], PageContent(number: 2, bounds: letter, lines: [caption], graphics: []), pages([])[2]]
    #expect(!joined(reconstruct(captionOnly)))
    // Body prose inside the figure page's region: the page is not only a figure.
    let swallowed = column(["an appendix circulated to the delegates on the second day of the session and"], top: 400)
    #expect(!joined(reconstruct(pages(swallowed))))
    // A body paragraph below the figure: the page holds text of its own.
    let paragraph = column(["A short paragraph of body text that stands below the figure on its own page."], top: 60)
    #expect(!joined(reconstruct(pages(paragraph))))
}
