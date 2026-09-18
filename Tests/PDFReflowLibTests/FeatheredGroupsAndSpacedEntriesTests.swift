import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

// NOAA NCA5 (#181). Page 48's left column, its sub-heading and both figure captions were inside a
// crop: the page's corner art is a 30%-opacity image wrapped in a transparency group whose box
// stands eight points above the art, so #158's covered-box rule missed it and the box read as ink
// across the page's lower half. And the book's author and contributor blocks, one entry to a line
// at an even open leading, ran together into one paragraph, since no entry wraps into the hanging
// indent #134 reads. Fixtures are native extraction from the checksum-pinned source; expectations
// were read from the rendered pages.

private func crops(_ page: PageContent) -> [CGRect] { LayoutReconstructor.graphicsWithLabels(page) }

private func taken(_ page: PageContent, _ regions: [CGRect]) -> [String] {
    page.lines.filter { line in regions.contains { $0.intersects(line.rect) } }.map(\.text)
}

private func reflow(_ page: PageContent, bookWraps: [Int: CGFloat] = [:]) -> [ReflowBlock] {
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings, bookWraps: bookWraps)
}

private func paragraphs(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case let .paragraph(text) = $0.content { text.text } else { nil } }
}

/// NOAA's wrap at its ten-point body, as the book's pages give it (`bookWraps`, 0.15 pt on `f3840f4`).
private let noaaWraps = [LayoutReconstructor.wrapKey(10): CGFloat(0.15)]

private func line(_ text: String, x: CGFloat = 54, top: CGFloat, width: CGFloat, size: CGFloat = 10,
                  bold: Bool = false) -> TextLine {
    TextLine(content: InlineText(text, style: bold ? .bold : []), rect: CGRect(x: x, y: top - 13.3, width: width, height: 13.3),
             fontSize: size, monospaced: false)
}

private func page(_ lines: [TextLine]) -> PageContent {
    PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines, graphics: [])
}

// MARK: The feathered group box (page 48)

@Test func readerSkipsAFeatheredGroupBoxItsPaintsAllButFill() throws {
    // Corner art in a transparency group whose box stands eight points over the art (a feather),
    // and a form whose box reaches well past its paint.
    let data = testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 792 612] /Resources << /XObject << /Fm 5 0 R /Sm 6 0 R >> >> /Contents 4 0 R >>",
        testPDFStream("/Fm Do /Sm Do"),
        testPDFStream("0.9 g 0 0 792 248.7 re f",
                      extra: "/Type /XObject /Subtype /Form /BBox [-151.4 -141.66 1018.6 256.717] /Group << /S /Transparency >>"),
        testPDFStream("0.5 g 400 400 100 60 re f",
                      extra: "/Type /XObject /Subtype /Form /BBox [400 380 500 460] /Group << /S /Transparency >>"),
    ])
    let document = try #require(CGPDFDocument(CGDataProvider(data: data as CFData)!))
    let result = GraphicsReader.read(try #require(document.page(at: 1)))
    #expect(!result.unsupported)
    // The feathered box adds nothing and marks its paint; the second box keeps a quarter of itself
    // beyond its paint and is still recorded.
    #expect(result.paints.count == 3)
    #expect(!result.paints.contains { abs($0.rect.maxY - 256.717) < 0.5 })
    #expect(result.paints.map(\.grouped) == [true, false, false])
    #expect(result.paints.last?.rect == CGRect(x: 400, y: 380, width: 100, height: 80))
}

@Test func groupBoxesAreTheGroupsOwnBoundsOnlyWhenTheirPaintsAllButFillThem() {
    let box = CGRect(x: 0, y: 0, width: 792, height: 256.7)
    #expect(GraphicsReader.fills(box, by: CGRect(x: 0, y: 0, width: 792, height: 248.7)))
    #expect(GraphicsReader.fills(box, by: CGRect(x: 0, y: 0, width: 792, height: 232)))
    #expect(!GraphicsReader.fills(box, by: CGRect(x: 0, y: 0, width: 792, height: 228)))
    #expect(!GraphicsReader.fills(box, by: CGRect(x: 0, y: 300, width: 792, height: 100)))
    #expect(!GraphicsReader.fills(box, by: .null))
    #expect(!GraphicsReader.fills(.zero, by: box))
}

@Test func noaaPage48ColumnAndCaptionsLeaveTheFigureCrop() throws {
    let fixture = try SourceLayoutFixture.load("noaa-48")
    let page = fixture.content()
    let regions = crops(page)
    let phrases = ["Global greenhouse gas emissions from human activities continue", "Current climate changes are unprecedented",
                   "The US has warmed rapidly since the 1970s", "Figure 1.5. The graph shows the change in US annual average",
                   "US and Global Changes in Average Surface Temperature"]
    for phrase in phrases {
        #expect(page.lines.contains { $0.text.contains(phrase) }, "the source has no \(phrase)")
        #expect(!taken(page, regions).contains { $0.contains(phrase) }, "a crop still holds \(phrase)")
    }
    // The figure keeps exactly its own crop.
    #expect(regions.count == 1)
    #expect(regions.first.map { $0.minX > 400 && $0.minY > 170 && $0.maxY < 410 } == true)
    // Control: the group's box recorded as a paint of its own, as before, takes the whole lower half.
    var paints = try #require(fixture.paints).map {
        GraphicsReader.Paint(rect: CGRect(x: $0.rect[0], y: $0.rect[1], width: $0.rect[2], height: $0.rect[3]),
                             frame: $0.frame, image: $0.image ?? false, filled: $0.filled ?? false, grouped: $0.grouped ?? false)
    }
    paints.append(GraphicsReader.Paint(rect: CGRect(x: 0, y: 0, width: 792, height: 256.717), frame: false))
    var defect = fixture.content(tinted: false)
    let composed = TintDetector.compose(paints, lines: defect.lines, bounds: defect.bounds)
    defect.graphics = composed.graphics
    defect.tints = composed.tints
    let held = taken(defect, crops(defect))
    for phrase in phrases.dropLast() { #expect(held.contains { $0.contains(phrase) }, "control: \(phrase)") }
}

// MARK: One-line entries set apart by space (#181)

@Test func noaaContributorEntriesAreParagraphsOfTheirOwn() throws {
    // Page 81's authors stand 3.2 pt apart and page 1700's contributors 7.7; each page's citation
    // reaches its measure on two lines or one, and page 343 carries none, so the book's wrap is
    // the evidence.
    for (name, entries) in [
        ("noaa-81", ["Sarah Aarons, University of California San Diego, Scripps Institution of Oceanography",
                     "Abhishek Chatterjee, NASA Jet Propulsion Laboratory, California Institute of Technology",
                     "Zeke Hausfather, Stripe Inc.", "Alexander Robel, Georgia Institute of Technology",
                     "Deepti Singh, Washington State University Vancouver",
                     "Russell S. Vose, NOAA National Centers for Environmental Information"]),
        ("noaa-1700", ["Robert G. Byron, Montana Health Professionals for a Healthy Climate", "Amy E. East, US Geological Survey",
                       "Michael Méndez, University of California, Irvine",
                       "Ambarish Vaidyanathan, Centers for Disease Control and Prevention"]),
        ("noaa-343", ["Michelle Baumflek, USDA Forest Service, Southern Research Station",
                      "Chris Swanston, USDA Forest Service, Washington Office",
                      "Ning Liu, USDA Forest Service, Southern Research Station",
                      "Brian F. Walters, USDA Forest Service, Northern Research Station"]),
    ] {
        let content = try SourceLayoutFixture.load(name).styledContent()
        let found = paragraphs(reflow(content, bookWraps: noaaWraps))
        for entry in entries { #expect(found.contains(entry), "\(name): \(entry)") }
        // The recommended citation still reads as one paragraph where the page carries it.
        if name != "noaa-343" { #expect(found.contains { $0.hasPrefix("Recommended Citation") || $0.contains(", 2023: ") }) }
        // Control: without the book's wrap, an edge whose own measure is one or two citation lines,
        // or none, has no evidence, and the entries run together.
        #expect(!paragraphs(reflow(content)).contains(entries[0]), "\(name) control")
    }
}

@Test func spacedEntryEdgesNeedARunAtEvenAddedLeadingOverTheWrap() {
    let entries = ["Robert G. Byron, Montana Health Professionals", "Amy E. East, US Geological Survey",
                   "Michael Méndez, University of California, Irvine", "Jeffrey R. Pierce, Colorado State University"]
    let citation = ["Ostoja, S.M., A.R. Crimmins, R.G. Byron, A.E. East, M. Méndez, S.M. O’Neill, D.L. Peterson, J.R. Pierce,",
                    "Raymond, A. Tripati, and A. Vaidyanathan, 2023: Focus on western wildfires. In: Fifth National Climate",
                    "Assessment. Crimmins, A.R., C.W. Avery, D.R. Easterling, K.E. Kunkel, B.C. Stewart, and T.K. Maycock, Eds.",
                    "Global Change Research Program, Washington, DC, USA."]
    func listing(pitch: CGFloat, count: Int = 4) -> [TextLine] {
        entries.prefix(count).enumerated().map { line($1, top: 560 - CGFloat($0) * pitch, width: 180 + CGFloat($0 % 2) * 60) }
            + citation.enumerated().map { line($1, top: 300 - CGFloat($0) * 13.4, width: $0 == 3 ? 260 : 500) }
    }
    // Entries 21 points apart (7.7 pt of space) over a citation wrapping at 0.1 pt.
    let spaced = listing(pitch: 21)
    #expect(LayoutReconstructor.spacedEntryEdges(spaced, body: 10).map(\.x) == [54])
    #expect(paragraphs(reflow(page(spaced))).prefix(4) == ArraySlice(entries))
    #expect(paragraphs(reflow(page(spaced))).last == citation.joined(separator: " "))
    // Controls: entries at the citation's own leading are wrapped lines as far as the page shows;
    // two entries are no run; the entries' leading must be even.
    #expect(LayoutReconstructor.spacedEntryEdges(listing(pitch: 13.4), body: 10).isEmpty)
    #expect(LayoutReconstructor.spacedEntryEdges(listing(pitch: 21, count: 2), body: 10).isEmpty)
    var uneven = spaced
    uneven[2].rect.origin.y += 3.7
    #expect(LayoutReconstructor.spacedEntryEdges(uneven, body: 10).isEmpty)
    #expect(paragraphs(reflow(page(listing(pitch: 13.4)))).first?.hasPrefix(entries.joined(separator: " ")) == true)
    // A paragraph set at open leading fills its measure, so its lines make no run.
    let open = (0..<4).map { line("agriculture is exposed to negative influences from nature and markets \($0)",
                                  top: 560 - CGFloat($0) * 21, width: 500) }
        + citation.enumerated().map { line($1, top: 300 - CGFloat($0) * 13.4, width: $0 == 3 ? 260 : 500) }
    #expect(LayoutReconstructor.spacedEntryEdges(open, body: 10).isEmpty)
    // Lines out of the body's size, lists and wholly bold labels are no evidence.
    #expect(LayoutReconstructor.spacedEntryEdges(spaced, body: 12).isEmpty)
    let bold = spaced.enumerated().map { $0.offset < 4 ? line(entries[$0.offset], top: $0.element.rect.maxY, width: $0.element.rect.width, bold: true) : $0.element }
    #expect(LayoutReconstructor.spacedEntryEdges(bold, body: 10).isEmpty)
}

@Test func anEntryOpensOnlyAtItsSpacingAndWhereItsLineEndedEarly() {
    // A spaced edge (entries 7.7 pt apart, a citation wrapping at 0.1 pt), with a wrapped entry: its
    // second line sits at the wrap and continues it, although its first word would have fitted on
    // the line above.
    let lines = [line("Robert G. Byron, Montana Health Professionals for a Healthy Climate", top: 560, width: 306),
                 line("Amy E. East, US Geological Survey", top: 539, width: 152),
                 line("Susan M. O’Neill, USDA Forest Service, Pacific Northwest Research Station, Corvallis,", top: 518, width: 380),
                 line("Oregon, Western Wildland Environmental Threat Assessment Center", top: 504.6, width: 300),
                 line("Michael Méndez, University of California, Irvine", top: 483.6, width: 207),
                 line("Jeffrey R. Pierce, Colorado State University", top: 462.6, width: 191)]
        + ["Ostoja, S.M., A.R. Crimmins, R.G. Byron, A.E. East, M. Méndez, S.M. O’Neill, D.L. Peterson, J.R. Pierce,",
           "Raymond, A. Tripati, and A. Vaidyanathan, 2023: Focus on western wildfires. In: Fifth National Climate",
           "Assessment. Crimmins, A.R., C.W. Avery, D.R. Easterling, K.E. Kunkel, B.C. Stewart, and T.K. Maycock, Eds.",
           "Global Change Research Program, Washington, DC, USA."].enumerated().map { line($1, top: 300 - CGFloat($0) * 13.4, width: $0 == 3 ? 260 : 500) }
    let found = paragraphs(reflow(page(lines)))
    #expect(found.prefix(5) == ["Robert G. Byron, Montana Health Professionals for a Healthy Climate", "Amy E. East, US Geological Survey",
                                "Susan M. O’Neill, USDA Forest Service, Pacific Northwest Research Station, Corvallis, Oregon, Western Wildland Environmental Threat Assessment Center",
                                "Michael Méndez, University of California, Irvine", "Jeffrey R. Pierce, Colorado State University"])
}

// MARK: Entries wrapped wider than a paragraph's drift (#181)

@Test func noaaStaffEntriesWrapIntoTheirHangingIndent() throws {
    let found = paragraphs(reflow(try SourceLayoutFixture.load("noaa-7").styledContent()))
    for entry in ["Brooke C. Stewart, Managing Editor and Lead Science Editor, North Carolina State University (through July 2023)",
                  "David R. Easterling, Technical Support Unit Director, NOAA National Centers for Environmental Information (NCEI)",
                  "Sonia Aronson, Climate Change and Sustainability Analyst, ICF (through June 2023)",
                  "Kenneth E. Kunkel, Lead Scientist, North Carolina State University",
                  "Thomas K. Maycock, Senior Science Editor, North Carolina State University"] {
        #expect(found.contains(entry), "\(entry)")
    }
}

@Test func aHangingEntryRunsIntoAWideIndentOnlyOnItsPagesHangingEdge() {
    // Three staff entries wrapped 1.8 ems in at one measure: the wrapped pairs qualify the edge (#134).
    let entries = [line("Brooke C. Stewart, Managing Editor and Lead Science Editor, North Carolina", x: 36, top: 325.6, width: 336),
                   line("State University (through July 2023)", x: 54, top: 313.6, width: 158),
                   line("Thomas K. Maycock, Senior Science Editor, NC State University", x: 36, top: 301.6, width: 280),
                   line("Jessicca Allen, Visual Communications Specialist and Lead Graphic", x: 36, top: 289.6, width: 330),
                   line("Designer, North Carolina State University", x: 54, top: 277.6, width: 179),
                   line("Barbara Ambrose, Visual Communications Specialist, Mississippi State", x: 36, top: 265.6, width: 332),
                   line("University, Northern Gulf Institute", x: 54, top: 253.6, width: 146),
                   line("Rocky Bilotta, Physical Scientist,", x: 36, top: 241.6, width: 150),
                   line("NOAA NCEI", x: 54, top: 229.6, width: 50),
                   line("Amy V. Camper, Visual Communications Specialist, Innovative Consulting", x: 36, top: 217.6, width: 334),
                   line("and Management Services LLC", x: 54, top: 205.6, width: 137)]
    #expect(LayoutReconstructor.hangingEntryEdges(entries, body: 10).map(\.x) == [36])
    #expect(paragraphs(reflow(page(entries))) == [
        "Brooke C. Stewart, Managing Editor and Lead Science Editor, North Carolina State University (through July 2023)",
        "Thomas K. Maycock, Senior Science Editor, NC State University",
        "Jessicca Allen, Visual Communications Specialist and Lead Graphic Designer, North Carolina State University",
        "Barbara Ambrose, Visual Communications Specialist, Mississippi State University, Northern Gulf Institute",
        // Broken short, where `NOAA` would have fitted: the indented line is no wrap.
        "Rocky Bilotta, Physical Scientist,", "NOAA NCEI",
        "Amy V. Camper, Visual Communications Specialist, Innovative Consulting and Management Services LLC"])
    // Control: entries that wrap at no measure three of them share (a poem's couplets, broken where
    // the verse breaks) keep their lines apart, even where the next word would not have fitted.
    let ragged = [line("Brooke C. Stewart, Managing Editor and Lead Science Editor, North Carolina", x: 36, top: 325.6, width: 336),
                  line("Telecommunications Administration", x: 54, top: 313.6, width: 200),
                  line("Jessicca Allen, Visual Communications Specialist", x: 36, top: 301.6, width: 250),
                  line("Telecommunications Administration", x: 54, top: 289.6, width: 200),
                  line("Barbara Ambrose, Communications Specialist", x: 36, top: 277.6, width: 200),
                  line("Telecommunications Administration", x: 54, top: 265.6, width: 200)]
    #expect(LayoutReconstructor.hangingEntryEdges(ragged, body: 10).map(\.pairs) == [3])
    #expect(paragraphs(reflow(page(ragged))).filter { $0 == "Telecommunications Administration" }.count == 3)
    // Control: a first line that closes its sentence is a paragraph of its own, and so is the
    // line indented under it (an indented opening is no wrapped entry, so the edge has no evidence).
    var closed = entries
    closed[0] = line("Brooke C. Stewart, Managing Editor and Lead Science Editor, North Carolina.", x: 36, top: 325.6, width: 338)
    closed[3] = line("Jessicca Allen, Visual Communications Specialist and Lead Graphic.", x: 36, top: 289.6, width: 332)
    closed[5] = line("Barbara Ambrose, Visual Communications Specialist, Mississippi State.", x: 36, top: 265.6, width: 334)
    closed[9] = line("Amy V. Camper, Visual Communications Specialist, Innovative Consulting.", x: 36, top: 217.6, width: 336)
    #expect(LayoutReconstructor.hangingEntryEdges(closed, body: 10).isEmpty)
    #expect(paragraphs(reflow(page(closed))).contains("State University (through July 2023)"))
    // A poem indenting alternate lines breaks them short: the next line's first word would have
    // fitted, so each is a line of its own (NOAA page 5).
    let poem = [line("It is a forgotten pleasure, the pleasure", x: 36, top: 500, width: 180),
                line("of the unexpected blue-bellied lizard", x: 54, top: 488, width: 170),
                line("skittering off his sun spot rock, the flicker", x: 36, top: 476, width: 200),
                line("of an unknown bird by the bus stop.", x: 54, top: 464, width: 160),
                line("To think, perhaps, we are not distinguishable from the rest of it all,", x: 36, top: 452, width: 300),
                line("and therefore no loneliness can exist here.", x: 54, top: 440, width: 190)]
    #expect(LayoutReconstructor.hangingEntryEdges(poem, body: 10).map(\.pairs) == [2])
    #expect(paragraphs(reflow(page(poem))).contains("of the unexpected blue-bellied lizard"))
    // A line three ems in is past the edge's hanging indent; a checkbox and a worked step are not
    // an entry's words.
    for (text, x) in [("State University (through July 2023)", CGFloat(66)), ("☐ Federal question", CGFloat(54)),
                      ("2+3(5)2 Exponents", CGFloat(54))] {
        var other = entries
        other[1] = line(text, x: x, top: 313.6, width: 158)
        #expect(paragraphs(reflow(page(other))).contains(text), "\(text)")
    }
}
