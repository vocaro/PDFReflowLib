import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// Titles over art, worked-example prose beside formula crops (#112) and same-page column
// continuations (#111). Fixtures are native extraction from the checksum-pinned DGA and FAA
// sources; expectations were read from the rendered pages.

private let dgaSHA256 = "c34f1bec5c9416265670b7fcb24556bb8616ba95e8de2f2890460b6bbca1a472"
private let faaSHA256 = "247929cace0ab56b376e683eba540cc4c8f39f199ab35414e8b604e24f395cb7"

private func source(_ name: String, sha256: String) throws -> PageContent {
    let fixture = try SourceLayoutFixture.load(name)
    #expect(fixture.sourceSHA256 == sha256)
    return fixture.content()
}

private func blocks(_ page: PageContent, _ crops: [CGRect]) -> [ReflowBlock] {
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: crops.enumerated().map { ($0.element, "image-\($0.offset)") },
        vocabulary: [], warnings: &warnings)
}

private func line(_ page: PageContent, _ prefix: String) throws -> TextLine {
    try #require(page.lines.first { $0.text.hasPrefix(prefix) }, "no source line \(prefix)")
}

private func headings(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .heading = $0.content { $0.text } else { nil } }
}

// MARK: Title art

// FAA's appendix and chapter-opener titles carry a drop shadow drawn as a transparency group. The
// shadow's cluster lies within the title's own line rectangles, so its crop took the title (and on
// page 461 the first body line, whose top 2 pt the blur overlaps). Page 473's title rectangle is
// PDFKit's merge of the title with `Appendix C`; its figure stays a crop.
@Test(arguments: [
    ("faa-3-title-art", "Preface", nil as String?, 0),
    ("faa-461-title-art", "Acronyms, Abbreviations, and", "This is a list of common acronyms", 0),
    ("faa-473-title-art", "Airport Signs and Markings", nil, 1),
    ("faa-477-title-art", "Glossary", nil, 0),
])
func titleShadowIsDecoration(name: String, title: String, body: String?, crops count: Int) throws {
    let page = try source(name, sha256: faaSHA256)
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    let titleLine = try line(page, title)
    #expect(!crops.contains { $0.intersects(titleLine.rect) }, "title inside a crop")
    if let body { #expect(!crops.contains { $0.intersects(try! line(page, body).rect) }, "body line inside a crop") }
    #expect(crops.count == count)
    #expect(headings(blocks(page, crops)).contains { $0.hasPrefix(title) })
}

// Page 453's shadow cluster touched the figure's in-frame table title, so the two crops merged over
// the appendix title. The figure keeps its own title line; the appendix title reflows.
@Test func titleShadowBesideAFigureLeavesTheFigureWhole() throws {
    let page = try source("faa-453-title-art", sha256: faaSHA256)
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    for title in ["Performance Data for Cessna", "Model 172R and Challenger 605", "Appendix A"] {
        #expect(!crops.contains { $0.intersects(try! line(page, title).rect) }, "\(title) inside a crop")
    }
    let figure = try #require(page.graphics.first { $0.height > 400 })
    #expect(crops.count == 1)
    #expect(crops.contains { $0.insetBy(dx: -1, dy: -1).contains(figure) })
    #expect(crops.contains { $0.contains(try! line(page, "Short Field Takeoff Distance").rect) })
    #expect(headings(blocks(page, crops)) == ["Performance Data for Cessna Model 172R and Challenger 605"])
}

// DGA page 9 sets each section title over the left end of a decorative band no taller than the title
// row. The band keeps its part beyond the title; `Older Adults`, 0.9 pt clear of its band, is the
// control whose band crop is unchanged.
@Test func sectionBandsKeepOnlyTheirPartBesideTheTitle() throws {
    let page = try source("dga-9", sha256: dgaSHA256)
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    // Composition now trims each band beside its title before clustering (#117); the reader's
    // untrimmed regions still hold the bands whose remainder is checked.
    let painted = try SourceLayoutFixture.load("dga-9").content(tinted: false)
    for title in ["Young Adulthood", "Pregnant Women", "Lactating Women"] {
        let titleLine = try line(page, title)
        #expect(!crops.contains { $0.intersects(titleLine.rect) }, "\(title) inside a crop")
        let band = try #require(painted.graphics.first { $0.intersects(titleLine.rect) })
        let kept = try #require(crops.first { $0.intersects(band) }, "\(title) lost its band")
        #expect(kept.minX > titleLine.rect.maxX && kept.minX < titleLine.rect.maxX + 1)
        #expect(abs(kept.maxX - band.maxX) < 0.01 && abs(kept.minY - band.minY) < 0.01 && abs(kept.height - band.height) < 0.01)
    }
    let older = try line(page, "Older Adults")
    let olderBand = try #require(page.graphics.first { $0.minY < older.rect.midY && $0.maxY > older.rect.midY && $0.width > 400 })
    #expect(crops.contains { $0 == olderBand })
    #expect(headings(blocks(page, crops)) == ["Young Adulthood", "Pregnant Women", "Lactating Women", "Older Adults"])
}

// DGA page 7: with its section title out of the band, `Special Populations & Considerations` stands
// directly over a smaller section title. It still introduces that section and stays a heading.
@Test func pageTitleOverASmallerSectionTitleStaysAHeading() throws {
    let page = try source("dga-7", sha256: dgaSHA256)
    let result = blocks(page, LayoutReconstructor.graphicsWithLabels(page))
    #expect(headings(result) == ["Special Populations & Considerations", "Infancy & Early Childhood (Birth–4 Years)"])
}

/// A synthetic page: ten body lines (10 pt) far below, a title line and one painted graphic.
private func titlePage(title: TextLine, graphic: CGRect, extra: [TextLine] = []) -> PageContent {
    let body = (0..<10).map { TextLine(text: "Body text line \($0) with ordinary words in it", rect: CGRect(x: 72, y: 100 + 14 * Double($0), width: 300, height: 12), fontSize: 10) }
    return PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: body + [title] + extra, graphics: [graphic])
}

private let title = TextLine(text: "Chapter Title", rect: CGRect(x: 72, y: 650, width: 300, height: 40), fontSize: 36)

@Test func titleArtRequiresAShadowOrABandShape() {
    func crops(_ graphic: CGRect, title: TextLine = title, extra: [TextLine] = []) -> [CGRect] {
        LayoutReconstructor.graphicsWithLabels(titlePage(title: title, graphic: graphic, extra: extra))
    }
    // A shadow offset a few points from the title: decoration.
    #expect(crops(CGRect(x: 76, y: 646, width: 305, height: 36)).isEmpty)
    // A band the title overhangs keeps its part to the right of the title.
    let band = crops(CGRect(x: 150, y: 645, width: 400, height: 50))
    #expect(band.count == 1 && band[0].minX > title.rect.maxX && band[0].maxX == 550)
    // A band holding the whole title is its background: decoration.
    #expect(crops(CGRect(x: 50, y: 645, width: 500, height: 50)).isEmpty)
    // Controls: a figure behind the title that extends far below it keeps the title.
    #expect(crops(CGRect(x: 60, y: 400, width: 400, height: 280)).contains { $0.contains(title.rect) })
    // Art the title covers for less than 60% of its area is not a shadow, even within its extent.
    #expect(crops(CGRect(x: 76, y: 600, width: 305, height: 86)).contains { $0.contains(title.rect) })
    #expect(crops(CGRect(x: 72, y: 620, width: 330, height: 35)).contains { $0.contains(title.rect) })
    // Art reaching further than one type size beyond the title is not its shadow; this one is a band
    // the title overhangs, which keeps its part beyond the title.
    #expect(crops(CGRect(x: 80, y: 650, width: 380, height: 40)) == [CGRect(x: 372.5, y: 650, width: 87.5, height: 40)])
    // A shadow that another line overlaps by more than its blur keeps both.
    let overlapping = TextLine(text: "a body line", rect: CGRect(x: 72, y: 640, width: 200, height: 12), fontSize: 10)
    #expect(crops(CGRect(x: 76, y: 646, width: 305, height: 36), extra: [overlapping]).contains { $0.contains(title.rect) })
    // A band that also touches another line is not bare decoration.
    let caption = TextLine(text: "caption words", rect: CGRect(x: 420, y: 660, width: 100, height: 12), fontSize: 10)
    #expect(crops(CGRect(x: 150, y: 645, width: 400, height: 50), extra: [caption]).contains { $0.contains(title.rect) })
    // Body-size text over a band is not a title.
    let small = TextLine(text: "Chapter Title", rect: CGRect(x: 72, y: 664, width: 120, height: 12), fontSize: 10)
    #expect(crops(CGRect(x: 150, y: 660, width: 400, height: 18), title: small).contains { $0.contains(small.rect) })
    // A band taller than twice the title row is a figure.
    #expect(crops(CGRect(x: 150, y: 600, width: 400, height: 100)).contains { $0.contains(title.rect) })
}

// MARK: Worked-example prose

// FAA page 251: `“weight x arm = moment.”` is the quoted end of step 2's sentence, set on the step's
// hanging indent, not a display; its formula crop took steps 2 and 3. The two figure crops remain.
@Test func wrappedSentenceEndIsNotAFormula() throws {
    let page = try source("faa-251-worked-example", sha256: faaSHA256)
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    for text in ["2. Enter the moment for each item listed. Remember", "“weight x arm = moment.”", "3. Find the total weight"] {
        #expect(!crops.contains { $0.intersects(try! line(page, text).rect) }, "\(text) inside a crop")
    }
    #expect(crops.count == 2)
    #expect(blocks(page, crops).contains { $0.text == "2. Enter the moment for each item listed. Remember “weight x arm = moment.”" })
}

// FAA page 298: the sentence closing the worked example reflows; the displayed calculation above it
// stays a crop.
@Test func sentenceBeneathADisplayIsNotItsMargin() throws {
    let page = try source("faa-298-worked-example", sha256: faaSHA256)
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    #expect(!crops.contains { $0.intersects(try! line(page, "The height of the cloud base is 3,180 feet AGL.").rect) })
    for display in ["Temperature (T) = 85 °F", "TDS ÷ CR = X", "85 °F – 71 °F = 14 °F", "3.18 × 1,000 = 3,180 feet AGL"] {
        #expect(crops.contains { $0.contains(try! line(page, display).rect) }, "\(display) left its crop")
    }
}

@Test func formulaMarginSentenceAndWrappedEndControls() {
    let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
    let formula = TextLine(text: "3x + 2 = 11", rect: CGRect(x: 90, y: 500, width: 80, height: 11.5), fontSize: 10)
    func crops(_ lines: [TextLine]) -> [CGRect] {
        LayoutReconstructor.graphicsWithLabels(PageContent(number: 1, bounds: bounds, lines: lines, graphics: []))
    }
    func sentence(_ text: String) -> TextLine {
        TextLine(text: text, rect: CGRect(x: 90, y: 488, width: 200, height: 11.5), fontSize: 10)
    }
    // A sentence directly beneath the display reflows.
    let closing = sentence("The value of the unknown is 3 in this example.")
    #expect(!crops([formula, closing]).contains { $0.intersects(closing.rect) })
    // Controls: words without a sentence's capital and full stop, or with a term, stay in the margin.
    for text in ["the value of the unknown is 3 in this example", "The value of the unknown in this long example is found as x = 3 at the end."] {
        let other = sentence(text)
        #expect(crops([formula, other]).contains { $0.intersects(other.rect) }, "\(text) left the formula")
    }
    // A lowercase line on the hanging indent under an open sentence ends that sentence.
    let step = TextLine(text: "2. Enter the moment for each item listed. Remember", rect: CGRect(x: 81, y: 207, width: 228, height: 11.5), fontSize: 10)
    let quoted = TextLine(text: "“weight x arm = moment.”", rect: CGRect(x: 99, y: 194.5, width: 108, height: 12.5), fontSize: 10)
    #expect(crops([step, quoted]).isEmpty)
    // Controls: the line above closes its sentence, or the candidate opens with a term.
    let closed = TextLine(text: "2. Enter the moment for each item listed below.", rect: step.rect, fontSize: 10)
    #expect(crops([closed, quoted]).contains { $0.intersects(quoted.rect) })
    let term = TextLine(text: "3 weight x arm = moment", rect: quoted.rect, fontSize: 10)
    #expect(crops([step, term]).contains { $0.intersects(term.rect) })
}

// MARK: Same-page column continuation

// DGA page 9's `Older Adults` bullet ends the left column at `…dairy, meats, seafood,` and continues at
// the right column's head. The section band above both columns bounds the search, so the sections
// stacked above (whose right columns sit above the head line) do not compete. Without the bands'
// crops there is no such bound and the join is refused.
@Test func columnContinuationJoinsBelowASectionBand() throws {
    let page = try source("dga-9", sha256: dgaSHA256)
    var trimmed = page
    trimmed.lines.removeAll { $0.rect.maxY < 60 }
    let joined = blocks(trimmed, LayoutReconstructor.graphicsWithLabels(trimmed)).map(\.text)
    #expect(joined.contains { $0.contains("dairy, meats, seafood, eggs, legumes, and whole plant foods") })
    let unbounded = blocks(trimmed, []).map(\.text)
    #expect(!unbounded.contains { $0.contains("seafood, eggs, legumes") })
}

/// Two justified columns of six 12-pt lines on a 14-pt leading. `leftLast` ends the left column
/// and `rightFirst` opens the right one.
private func columns(leftLast: String = "the paragraph keeps running to the foot of the",
                     rightFirst: String = "column and continues at the head of the next one.",
                     leftLastWidth: Double = 240, rightX: Double = 300, extra: [TextLine] = [],
                     leftGroup: Int? = nil, rightGroup: Int? = nil) -> PageContent {
    func column(_ x: Double, _ texts: [String], group: Int?) -> [TextLine] {
        texts.enumerated().map { index, text in
            var line = TextLine(text: text, rect: CGRect(x: x, y: 700 - 14 * Double(index), width: index == texts.count - 1 && x < 100 ? leftLastWidth : 240, height: 13), fontSize: 12)
            if let group { line.structure = TextStructure(group: group, order: group * 10 + index, headingLevel: 0, lineCount: texts.count) }
            return line
        }
    }
    let left = column(40, ["Opening words of a paragraph that fills this", "column with ordinary prose set on a justified",
                           "measure so every line reaches the right edge", "of the column and wraps at the same width as",
                           "the others above and below it in the text, and", leftLast], group: leftGroup)
    let right = column(rightX, [rightFirst, "The right column carries on with more prose that", "fills its measure in the same way as the left one",
                             "does, each line reaching the shared right edge", "of the column until the paragraph ends on this",
                             "last line of the right column set here in full."], group: rightGroup)
    return PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: rightX + 312, height: 792), lines: left + right + extra, graphics: [])
}

private func paragraphTexts(_ page: PageContent, images: [CGRect] = []) -> [String] {
    blocks(page, images).map(\.text)
}

@Test func columnContinuationGuards() {
    let joins = { (texts: [String]) in texts.contains { $0.contains("to the foot of the column and continues at the head") } }
    #expect(joins(paragraphTexts(columns())))
    // The left column ends its sentence.
    #expect(!joins(paragraphTexts(columns(leftLast: "the paragraph keeps running to the foot of the."))))
    #expect(!paragraphTexts(columns(leftLast: "the paragraph keeps running to the foot of it.")).contains { $0.contains("it. column and") })
    // The right column opens a new sentence.
    #expect(!paragraphTexts(columns(rightFirst: "Column text continues at the head of the next one.")).contains { $0.contains("of the Column text") })
    // The last line does not fill the justified column.
    #expect(!paragraphTexts(columns(leftLastWidth: 170)).contains { $0.contains("foot of the column and") })
    // Two different validated paragraph identities.
    #expect(!joins(paragraphTexts(columns(leftGroup: 1, rightGroup: 2))))
    // Body-size prose swallowed by a region below the last line: the column did not end there.
    let below = TextLine(text: "more body prose that the figure region swallowed here", rect: CGRect(x: 40, y: 600, width: 240, height: 13), fontSize: 12)
    #expect(!joins(paragraphTexts(columns(extra: [below]), images: [CGRect(x: 30, y: 590, width: 260, height: 30)])))
    // A column of prose between the two (inside a region, so it is not itself a block).
    let middle = TextLine(text: "a middle column of prose standing between the two", rect: CGRect(x: 300, y: 650, width: 240, height: 13), fontSize: 12)
    #expect(joins(paragraphTexts(columns(rightX: 560))))
    #expect(!joins(paragraphTexts(columns(rightX: 560, extra: [middle]), images: [CGRect(x: 290, y: 640, width: 260, height: 30)])))
    // Prose above the head line in its column (an earlier section's right column, swallowed by a region).
    let above = TextLine(text: "an earlier section's prose standing above this column", rect: CGRect(x: 300, y: 765, width: 240, height: 13), fontSize: 12)
    let earlier = CGRect(x: 290, y: 760, width: 260, height: 25)
    #expect(!joins(paragraphTexts(columns(extra: [above]), images: [earlier])))
    // ...unless a region crossing the gutter separates it, as a section band does.
    #expect(joins(paragraphTexts(columns(extra: [above]), images: [earlier, CGRect(x: 30, y: 730, width: 520, height: 12)])))
}
