import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// NOAA NCA5 follow-ups to #181 (#200). The book's widest author entry ran into the next one, and
// a block of two entries stayed one paragraph; the front matter's poem read as wrapped entries,
// while two staff entries a column did not; each figure's bold lead ran into its caption; a photo
// credit underlined as a link read as a table's sub-header; and corner art behind a painting took
// the right column's last lines into the painting's crop. Fixtures are native extraction from the
// checksum-pinned source; expectations were read from the rendered pages.

/// NOAA's wrap and entry spacings at its ten-point body, as the book gives them (`bookWraps`,
/// `bookSpacings`, measured on the whole book).
private let noaaWraps = [LayoutReconstructor.wrapKey(10): CGFloat(0.15)]
private let noaaSpacings = [LayoutReconstructor.wrapKey(10): [CGFloat(2.23), 3.23, 4.65, 7.73]]

private func reflow(_ page: PageContent, spacings: [Int: [CGFloat]] = noaaSpacings) -> [ReflowBlock] {
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings,
                                      bookWraps: noaaWraps, bookSpacings: spacings)
}

private func paragraphs(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case let .paragraph(text) = $0.content { text.text } else { nil } }
}

private func taken(_ page: PageContent) -> [String] {
    let regions = LayoutReconstructor.graphicsWithLabels(page)
    return page.lines.filter { line in regions.contains { $0.intersects(line.rect) } }.map(\.text)
}

private func line(_ text: String, x: CGFloat = 54, top: CGFloat, width: CGFloat, size: CGFloat = 10,
                  bold: Bool = false) -> TextLine {
    TextLine(content: InlineText(text, style: bold ? .bold : []), rect: CGRect(x: x, y: top - 13.3, width: width, height: 13.3),
             fontSize: size, monospaced: false)
}

private func page(_ lines: [TextLine]) -> PageContent {
    PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines, graphics: [])
}

// MARK: Spaced entries

@Test func noaaWidestEntryOfASpacedRunOpensItsOwnParagraph() throws {
    // Page 488's authors stand 3.2 pt apart; Colgan's entry is the edge's widest but for the
    // citation, and `Sarah` would not have fitted after it.
    var content = try SourceLayoutFixture.load("noaa-488").styledContent()
    let found = paragraphs(reflow(content))
    for entry in ["Charles S. Colgan, Middlebury Institute of International Studies at Monterey, Center for the Blue Economy",
                  "Sarah R. Cooley, Ocean Conservancy", "Richard J. Bell, The Nature Conservancy",
                  "Miriam C. Goldstein, Center for American Progress (through February 2023)"] {
        #expect(found.contains(entry), "\(entry)")
    }
    // Control: set at the book's wrap, Cooley's line continues Colgan's entry.
    let index = try #require(content.lines.firstIndex { $0.text.hasPrefix("Sarah R. Cooley") })
    let colgan = try #require(content.lines.first { $0.text.hasPrefix("Charles S. Colgan") })
    content.lines[index].rect.origin.y = colgan.rect.minY - 0.15 - content.lines[index].rect.height
    #expect(paragraphs(reflow(content)).contains { $0.hasPrefix("Charles S. Colgan") && $0.hasSuffix("Sarah R. Cooley, Ocean Conservancy") })
}

@Test func anEntryAsWideAsTheEdgeIsNoMeasureOfItsOwnRun() {
    // Four entries 7.7 pt apart, the second the edge's widest line, and nothing else on the edge:
    // one line at the widest sets no measure, so the run holds all four (page 343's LeDuc entry).
    let entries = [line("Linda A. Joyce, USDA Forest Service, Rocky Mountain Research Station", top: 560, width: 330),
                   line("Stephen D. LeDuc, US Environmental Protection Agency, Office of Research and Development", top: 539, width: 420),
                   line("David H. Levinson, USDA Forest Service, National Stream and Aquatic Ecology Center", top: 518, width: 380),
                   line("Jeremy S. Littell, US Geological Survey, Alaska Climate Adaptation Science Center", top: 497, width: 370)]
    let edges = LayoutReconstructor.spacedEntryEdges(entries, body: 10, bookWrap: 0.15)
    #expect(edges.map(\.openings.count) == [3])
    #expect(paragraphs(reflow(page(entries))) == entries.map(\.text))
    // Control: where three lines reach the measure, the widest fills it and ends the run there.
    var measured = entries
    measured[2].rect.size.width = 415
    measured[3].rect.size.width = 418
    #expect(LayoutReconstructor.spacedEntryEdges(measured, body: 10, bookWrap: 0.15).isEmpty)
}

@Test func twoEntriesStandApartAtTheBooksEntrySpacing() throws {
    // Page 1738's two authors stand 7.7 pt apart, as page 1700's contributors do: one of the
    // spacings of the book's runs. (Its bold labels are headings only by the book's label styles,
    // which this page alone does not give, so the first entry here follows its label.)
    let content = try SourceLayoutFixture.load("noaa-1738").styledContent()
    let found = paragraphs(reflow(content))
    #expect(found.contains { $0.hasSuffix("Samantha Basile, US Global Change Research Program / ICF") })
    #expect(found.contains("Allyza Lustig, US Global Change Research Program / ICF"))
    // Control: without the book's spacings two entries are no run.
    let alone = paragraphs(reflow(content, spacings: [:]))
    #expect(alone.contains { $0.hasSuffix("Samantha Basile, US Global Change Research Program / ICF Allyza Lustig, US Global Change Research Program / ICF") })
    // The pair is read at the spacing alone; the edge's other lines are not entries of it.
    let pairs = LayoutReconstructor.spacedEntryPairs(content.lines, body: 10, bookWrap: 0.15, bookSpacings: [7.73])
    #expect(pairs.count == 1)
    #expect(LayoutReconstructor.spacedEntryPairs(content.lines, body: 10, bookWrap: 0.15, bookSpacings: [5]).isEmpty)
}

@Test func bookSpacingsNeedThreePagesOverTheWrap() {
    let key = LayoutReconstructor.wrapKey(10)
    // Three pages' runs at 7.7 (within a tenth of a size), two at 3.2; the median stands.
    let evidence: [Int: [[CGFloat]]] = [key: [[7.7], [7.72, 3.2], [7.69], [3.25]]]
    #expect(LayoutReconstructor.bookSpacings(from: evidence, wraps: [key: 0.15]) == [key: [7.7]])
    // Gaps within a fifth of a size of the wrap are the wrap's, and a size with no wrap has none.
    #expect(LayoutReconstructor.bookSpacings(from: [key: [[1.9], [2.0], [2.1]]], wraps: [key: 0.15]).isEmpty)
    #expect(LayoutReconstructor.bookSpacings(from: evidence, wraps: [:]).isEmpty)
    // A page's evidence is its runs of three or more.
    let run = (0..<3).map { line("Author \($0), University of Somewhere", top: 560 - CGFloat($0) * 21, width: 200) }
        + (0..<3).map { line("A paragraph of prose that fills the measure of its column \($0)", top: 400 - CGFloat($0) * 13.45, width: 500) }
    let spacing = LayoutReconstructor.spacingEvidence(on: page(run))
    #expect(spacing?.size == key)
    #expect(spacing?.gaps.count == 1)
    #expect(abs((spacing?.gaps.first ?? 0) - 7.7) < 0.01)
}

// MARK: Verse and wrapped entries

@Test func noaaPoemKeepsItsLines() throws {
    // Page 5 sets each couplet apart, its second line 1.8 ems in; three of ten first lines stop
    // where the next word would have fitted.
    let content = try SourceLayoutFixture.load("noaa-5").styledContent()
    let verse = content.lines.filter { $0.rect.minX > 260 && $0.rect.minX < 290 && $0.rect.minY > 150 && $0.rect.maxY < 480 }
    #expect(verse.count == 20)
    let wraps = LayoutReconstructor.hangingWraps(in: content.lines, edge: 263.7, size: 10, indent: 30)
    #expect(wraps.wrapped == 7 && wraps.short == 3)
    let found = paragraphs(reflow(content))
    for text in verse.map(\.text) { #expect(found.contains(text), "\(text)") }
}

@Test func noaaFrontMatterWrapsTwoEntriesAColumn() throws {
    // Page 6 wraps two staff entries in each column, 1.8 ems in; the committee's 11-point title
    // wraps flush over its 10-point entries, and the running foot crosses both columns.
    let found = paragraphs(reflow(try SourceLayoutFixture.load("noaa-6").styledContent()))
    for entry in ["Federal Steering Committee for the Fifth National Climate Assessment",
                  "Rebecca S. Dodder, US Environmental Protection Agency (from January 2023)",
                  "Susan C. Aragon-Long , Senior Science Coordinator / USGS Liaison to USGCRP (through January 2022)",
                  "Charles A. Brodine, Engagement and Communications Specialist (through August 2022)",
                  "USGCRP National Climate Assessment (NCA) Coordination Office", "NCA Leadership",
                  "Katie Reeves, Engagement and Communications Lead (through April 2023)"] {
        #expect(found.contains(entry), "\(entry)")
    }
}

@Test func aVerseTurnedIntoAHangingIndentIsNoListOfEntries() {
    // Stanzas set apart, each turning its second line 1.8 ems in: the first lines of three share
    // a measure, but two of five break short, so no turned line runs on.
    let stanzas = [("It is a forgotten pleasure, the pleasure", 180, "of the unexpected blue-bellied lizard"),
                   ("To think, perhaps, we are not distinguishable", 222, "and therefore no loneliness can exist here."),
                   ("Species to species in the same blue air, smoke—", 222, "wing flutter buzzing, a car horn coming."),
                   ("If you sit by the riverside, you see a culmination", 222, "of all things upstream. We know now,"),
                   ("The world says, Once we were separate,", 186, "and now we must move in unison.")]
    let verse = stanzas.enumerated().flatMap { index, stanza in
        [line(stanza.0, x: 36, top: 500 - CGFloat(index) * 32.5, width: CGFloat(stanza.1)),
         line(stanza.2, x: 54, top: 486 - CGFloat(index) * 32.5, width: 180)]
    }
    #expect(paragraphs(reflow(page(verse))) == verse.map(\.text))
    // Control: every first line full, the stanzas are entries whose turned lines run on.
    let full = stanzas.enumerated().flatMap { index, stanza in
        [line(stanza.0, x: 36, top: 500 - CGFloat(index) * 32.5, width: 222),
         line(stanza.2, x: 54, top: 486 - CGFloat(index) * 32.5, width: 180)]
    }
    #expect(paragraphs(reflow(page(full))).first == "\(stanzas[0].0) \(stanzas[0].2)")
}

// MARK: Figure leads, credits and backdrops

@Test func aBoldCaptionLabelOpensItsCaption() throws {
    let found = paragraphs(reflow(try SourceLayoutFixture.load("noaa-48").styledContent()))
    #expect(found.contains("The US has warmed rapidly since the 1970s."))
    #expect(found.contains { $0.hasPrefix("Figure 1.5. The graph shows the change in US annual average surface temperature") })
    // Control: a figure named in running text opens nothing, and neither does a label set plain.
    func lead(_ caption: TextLine) -> [String] {
        paragraphs(reflow(page([line("The US has warmed rapidly since the 1970s.", top: 560, width: 200), caption])))
    }
    let bold = TextLine(content: InlineText(elements: [.text("Figure 1.5. ", .bold), .text("The graph shows the change.", [])]),
                        rect: CGRect(x: 54, y: 533.25, width: 250, height: 13.3), fontSize: 10, monospaced: false)
    #expect(lead(bold).count == 2)
    #expect(lead(line("Figure 1.5. The graph shows the change.", top: 546.55, width: 250)).count == 1)
}

@Test func aCaptionBrokenAtAHyphenRunsOnOverleaf() throws {
    // Page 1182's Figure 25.8 caption, its own paragraph now that the bold lead is apart, ends
    // `…with cropland prev-` at the page's foot; page 1183 opens `alent in the eastern portion`.
    // The running head and foot are furniture the pipeline removes first.
    func stripped(_ name: String) throws -> PageContent {
        var content = try SourceLayoutFixture.load(name).styledContent()
        content.lines.removeAll { $0.rect.maxY < 31 || $0.rect.minY > content.bounds.maxY - 26 }
        return content
    }
    let pages = [try stripped("noaa-1182"), try stripped("noaa-1183")]
    func reconstruct(_ pages: [PageContent]) -> [ReflowBlock] {
        var blocks: [ReflowBlock] = []
        var warnings: [ConversionWarning] = []
        var previous: (page: PageContent, regions: [CGRect])?
        for page in pages {
            let regions = LayoutReconstructor.graphicsWithLabels(page)
            let images = regions.enumerated().map { ($0.element, "image-\(page.number)-\($0.offset)") }
            let pageBlocks = LayoutReconstructor.blocks(page: page, images: images, vocabulary: ["prevalent"], warnings: &warnings,
                                                        bookWraps: noaaWraps, bookSpacings: noaaSpacings)
            LayoutReconstructor.appendPage(pageBlocks, page: page, images: regions, previousPage: previous?.page,
                                           previousImages: previous?.regions ?? [], to: &blocks, vocabulary: ["prevalent"],
                                           warnings: &warnings)
            previous = (page, regions)
        }
        return blocks
    }
    let found = paragraphs(reconstruct(pages))
    #expect(found.contains { $0.hasPrefix("Figure 25.8.") && $0.contains("with cropland prevalent in the eastern portion of the region") })
    // Control: a caption that closes its sentence at the foot is stepped over as before.
    var closed = pages
    let index = try #require(closed[0].lines.firstIndex { $0.text.hasSuffix("prev-") })
    let foot = closed[0].lines[index]
    closed[0].lines[index] = TextLine(text: foot.text.replacingOccurrences(of: "prev-", with: "common."), rect: foot.rect,
                                      fontSize: foot.fontSize)
    #expect(paragraphs(reconstruct(closed)).contains { $0.hasPrefix("alent in the eastern portion") })
}

@Test func noaaPhotoCreditIsNoTableSubheader() throws {
    // Page 69 underlines `Tami Phelps` as a link under the painting; the left column runs on
    // beside it at the same leading, and its own column resumes 38 points down.
    let content = try SourceLayoutFixture.load("noaa-69").styledContent()
    #expect(TableRegionDetector.underlinedColumnRegions(in: content).isEmpty)
    let held = taken(content)
    for phrase in ["The CO2 not removed from the atmosphere", "Carbon dioxide, along with other greenhouse gases"] {
        #expect(content.lines.contains { $0.text.hasPrefix(phrase) }, "the source has no \(phrase)")
        #expect(!held.contains { $0.hasPrefix(phrase) }, "a crop holds \(phrase)")
    }
}

@Test func noaaCornerArtBehindAPaintingIsABackdrop() throws {
    // Page 47's corner art lies under the left column and, below it, behind the painting.
    let fixture = try SourceLayoutFixture.load("noaa-47")
    let content = fixture.styledContent()
    #expect(!taken(content).contains { $0.hasPrefix("deliver substantial emissions reductions") })
    #expect(paragraphs(reflow(content)).contains { $0.hasSuffix("are needed to reach net zero” below). {5.3, 6.3, 32.2, 32.3}") })
    // Control: without the painting the art keeps its piece beneath the column.
    let paints = try #require(fixture.paints).map {
        GraphicsReader.Paint(rect: CGRect(x: $0.rect[0], y: $0.rect[1], width: $0.rect[2], height: $0.rect[3]),
                             frame: $0.frame, image: $0.image ?? false, filled: $0.filled ?? false, grouped: $0.grouped ?? false)
    }
    let corner = try #require(paints.first { $0.grouped && $0.image })
    #expect(!TintDetector.withoutTextBackdrops(paints, lines: content.lines).contains { $0.grouped && $0.image })
    let alone = TintDetector.withoutTextBackdrops(paints.filter { !$0.image || $0.grouped }, lines: content.lines)
    #expect(alone.contains { $0.image && $0.rect.minX == corner.rect.minX && $0.rect.maxY < corner.rect.maxY })
    // Control: page 57's corner art keeps its piece above the column, which the photograph over
    // it covers a fifth of.
    let other = try SourceLayoutFixture.load("noaa-57")
    let art = try #require(other.paints).map {
        GraphicsReader.Paint(rect: CGRect(x: $0.rect[0], y: $0.rect[1], width: $0.rect[2], height: $0.rect[3]),
                             frame: $0.frame, image: $0.image ?? false, filled: $0.filled ?? false, grouped: $0.grouped ?? false)
    }
    let kept = TintDetector.withoutTextBackdrops(art, lines: other.styledContent().lines)
    #expect(kept.contains { $0.grouped && $0.image && $0.rect.minY > 250 })
}
