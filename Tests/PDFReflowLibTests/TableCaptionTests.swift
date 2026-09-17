import CoreGraphics
import Foundation
import Testing
import ZIPFoundation
@testable import PDFReflowLib

// Table titles and descriptions (#113). The Fed sets each text table's title band inside the
// table's box: a 10-pt title, then an 8-pt description, above the header row. The PDF tags both
// as one Caption element beside the Table. Reflow used to join them into one paragraph before the
// table (pages 46, 47, 97) or promote the title to a navigation heading (64, 82/83, 120/121). Now
// they are the table's caption: a title paragraph, then the description paragraph.

private func reflowed(_ page: PageContent) -> (regions: [CGRect], blocks: [ReflowBlock]) {
    let regions = LayoutReconstructor.graphicsWithLabels(page)
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: regions.enumerated().map { ($0.element, "image-\($0.offset)") },
        vocabulary: LayoutReconstructor.vocabulary(in: [page]), warnings: &warnings)
    return (regions, blocks)
}

private func tables(in blocks: [ReflowBlock]) -> [ReflowBlock.Table] {
    blocks.compactMap { if case let .table(table) = $0.content { table } else { nil } }
}

private func line(_ text: String, y: CGFloat, x: CGFloat = 100, size: CGFloat = 8, width: CGFloat = 300) -> TextLine {
    TextLine(text: text, rect: CGRect(x: x, y: y, width: width, height: size * 1.2), fontSize: size)
}

// MARK: Source pages

@Test(arguments: [
    (46, "Table 3.1 Traditional tools in an ample-reserves regime",
     "In recent years, the Federal Reserve has successfully implemented monetary policy with a varying degree of ample reserves in the banking system."),
    (47, "Table A. Simplified view of the Federal Reserve balance sheet, as of June 24, 2020",
     "The Federal Reserve publishes data weekly regarding its balance sheet."),
    (64, "Figure 4.6. Monitoring financial system stability requires global cooperation",
     "What happens in the global economy can influence—sometimes greatly—the stability of the U.S. economy."),
    (83, "Figure 5.7. Federal Reserve regulations by topic (continued)", ""),
    (97, "Figure 6.5. Examples of automated clearinghouse transfers",
     "Automated clearinghouse (ACH) transfers can be categorized as either “credit transfers” or “debit transfers” based on the type of instruction sent by the originator of the transfer."),
    (109, "Figure 6.11. Federal Reserve regulations governing the payment system",
     "The Federal Reserve has adopted the following set of regulations, which implement certain federal laws governing the U.S. payment system and the operations of participating institutions."),
    (120, "Figure 7.2. Federal consumer financial protection laws and regulations applicable to banks",
     "Financial institutions must comply with a variety of laws and regulations that protect consumers."),
])
func fedTableTitlesAndDescriptionsAreTheTablesCaption(_ number: Int, _ title: String, _ description: String) throws {
    let page = try SourceLayoutFixture.load("fed-\(number)").content()
    let (_, blocks) = reflowed(page)
    let found = tables(in: blocks)
    #expect(found.count == 1, "fed-\(number)")
    let table = try #require(found.first)
    #expect(table.caption.first?.text == title, "fed-\(number)")
    if description.isEmpty {
        #expect(table.caption.count == 1, "fed-\(number)")
    } else {
        #expect(table.caption.count == 2, "fed-\(number)")
        #expect(table.caption.last?.text.hasPrefix(description) == true, "fed-\(number)")
    }
    // Neither the title nor the description reads anywhere else: not as a heading, not as prose.
    let others = blocks.filter { if case .table = $0.content { false } else { true } }.map(\.text)
    #expect(!others.contains { $0.contains(title) }, "fed-\(number)")
    if !description.isEmpty { #expect(!others.contains { $0.contains(description) }, "fed-\(number)") }
    // The rows are untouched: the first row is still the table's own.
    #expect(!table.rows.contains { $0.cells.contains { $0.text.text.contains(title) } }, "fed-\(number)")
}

@Test func boxProseAboveTableAStaysOutsideItsCaption() throws {
    // Fed page 47: Table A sits inside Box 3.5, under the box's title and three paragraphs.
    let page = try SourceLayoutFixture.load("fed-47").content()
    #expect(try SourceLayoutFixture.load("fed-47").sourceSHA256 == SourceLayoutFixture.load("fed-46").sourceSHA256)
    let (_, blocks) = reflowed(page)
    let table = try #require(tables(in: blocks).first)
    #expect(table.caption.count == 2)
    #expect(table.rows.first?.cells.map(\.span) == [2, 2])
    let texts = blocks.filter { if case .table = $0.content { false } else { true } }.map(\.text)
    for phrase in ["Box 3.5. Gauging Monetary Policy through the Fed’s", "The table below shows the major asset and liability categories",
                   "On the liabilities side of the balance sheet"] {
        #expect(texts.contains { $0.contains(phrase) }, "\(phrase)")
        #expect(!table.caption.contains { $0.text.contains(phrase) }, "\(phrase)")
    }
    // The note under the table follows it.
    let tableIndex = try #require(blocks.firstIndex { if case .table = $0.content { true } else { false } })
    #expect(blocks[(tableIndex + 1)...].contains { $0.text.hasPrefix("Note: The H.4.1 statistical release") })
}

// MARK: The caption rule

@Test func captionIsATitleAndItsDescriptionDirectlyAboveTheTable() {
    let title = line("Table 9. Title of the table", y: 700, size: 10)
    let description = [line("A description of the table that wraps onto", y: 686), line("a second line.", y: 676)]
    let caption = ShadedTableDetector.caption(above: [title] + description, bodySize: 8)
    #expect(caption.title == [title] && caption.description == description)
    // A two-line title over no description.
    let twoLineTitle = [line("Figure 9. A long title that runs", y: 712, size: 10), title]
    let titleOnly = ShadedTableDetector.caption(above: twoLineTitle, bodySize: 8)
    #expect(titleOnly.title == twoLineTitle && titleOnly.description.isEmpty)
}

@Test func linesThatAreNotACaptionStayOutOfIt() {
    let title = line("Table 9. Title of the table", y: 700, size: 10)
    let description = line("A description of the table.", y: 686)
    func none(_ lines: [TextLine], _ reason: String) {
        let caption = ShadedTableDetector.caption(above: lines, bodySize: 8)
        #expect(caption.title.isEmpty && caption.description.isEmpty, "\(reason)")
    }
    none([description, line("More introduction", y: 700)], "no title-sized line")
    none([], "nothing above the table")
    none([title, description, line("Beside the description", y: 686, x: 420, width: 80)], "a row of two lines")
    none([title, line("A description set off to the right.", y: 686, x: 140)], "the description off the title's edge")
    none([title, line("A description in another size.", y: 686, size: 9)], "a description at another size")
    none([title, line("A description far below the title.", y: 650)], "a gap wider than two body sizes")
    none([title] + (0..<7).map { line("Introduction line \($0)", y: 686 - CGFloat($0) * 10) }, "more than a short description")
    none((0..<4).map { line("Title line \($0)", y: 730 - CGFloat($0) * 12, size: 10) }, "more than three title lines")
    // Text above the caption ends the scan without costing the caption.
    let above = [line("Box prose that sits above the table's title band.", y: 716),
                 line("Box 3.5. A larger box title", y: 740, x: 100, size: 16)]
    let kept = ShadedTableDetector.caption(above: above + [title, description], bodySize: 8)
    #expect(kept.title == [title] && kept.description == [description])
    let largerAbove = ShadedTableDetector.caption(above: [line("Box 3.5. A larger box title", y: 714, size: 16), title, description], bodySize: 8)
    #expect(largerAbove.title == [title] && largerAbove.description == [description])
}

// MARK: Serialization

@Test func captionParagraphsSerializeInsideTheTable() async throws {
    let directory = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    var title = InlineText("Table <A>", style: .bold)
    title.append(InlineText(" & notes"))
    let table = ReflowBlock.Table(columns: 2, rows: [
        .init(cells: [.init(text: InlineText("Entity")), .init(text: InlineText("Overview"))], header: true),
        .init(cells: [.init(text: InlineText("Board")), .init(text: InlineText("Promotes stability"))], header: false),
    ], caption: [title, InlineText(elements: [.text("A description", []), .sourcePage(2), .text(" continued.", [])])])
    let block = ReflowBlock(content: .table(table), page: 1)
    #expect(block.text == "Table <A> & notes A description continued. Entity Overview Board Promotes stability")
    #expect(block.sourcePages == [2])
    let book = ReflowDocument(metadata: .init(title: "Tables", language: "en"), blocks: [
        ReflowBlock(content: .sourcePage(1), page: 1),
        ReflowBlock(content: .heading(id: "h", text: InlineText("Section"), level: 2), page: 1),
        block,
    ], assets: [])
    let url = try await EPUBWriter.write(book, maximumOutputBytes: 1 << 20, directory: directory) { _ in }
    let archive = try Archive(url: url, accessMode: .read)
    func read(_ path: String) throws -> String {
        let entry = try #require(archive[path])
        var bytes = Data(); _ = try archive.extract(entry) { bytes += $0 }
        return String(decoding: bytes, as: UTF8.self)
    }
    let xhtml = try read("EPUB/chapter-1.xhtml")
    #expect(xhtml.contains("<table><caption><p><strong>Table &lt;A&gt;</strong> &amp; notes</p><p>A description"
        + EPUBTextEncoder.sourcePage(2) + " continued.</p></caption><thead><tr><th>Entity</th>"))
    // A caption is not navigation; its page boundary still is.
    let nav = try read("EPUB/nav.xhtml")
    #expect(nav.contains(">Section</a>") && !nav.contains("Table &lt;A&gt;"))
    #expect(nav.contains("#page-2\">2</a>"))
    // A table without a caption has no caption element.
    #expect(!EPUBTextEncoder.table(.init(columns: 1, rows: table.rows)).contains("<caption"))
}

// MARK: Recaptured fixtures (#114)

@Test func recapturedFed77And109KeepTheirEvidenceWithoutTags() throws {
    // Both fixtures now carry paints and the tags the pipeline applies. Their heading and body
    // expectations (HeadingTests) must also hold on geometry alone, as they did when captured.
    for (number, heading, phrase) in [(77, "Examination Report", "BHCs and SLHCs with less than $100 billion"),
                                      (109, "Expedited Funds Availability Act", "During the last two decades, Congress has directed")] {
        var fixture = try SourceLayoutFixture.load("fed-\(number)")
        #expect(fixture.paints?.isEmpty == false, "fed-\(number)")
        #expect(fixture.lines.contains { $0.structure != nil }, "fed-\(number)")
        for index in fixture.lines.indices { fixture.lines[index].structure = nil }
        let (regions, blocks) = reflowed(fixture.content())
        #expect(blocks.contains { if case .heading = $0.content { $0.text == heading } else { false } }, "fed-\(number)")
        #expect(blocks.contains { if case .paragraph = $0.content { $0.text.contains(phrase) } else { false } }, "fed-\(number)")
        if number == 77 {
            // The ratings grid stays an image: its merged header line is inside a crop, not reflowed.
            let grid = try #require(fixture.lines.first { $0.text.hasPrefix("Rating system") })
            let rect = CGRect(x: grid.rect[0], y: grid.rect[1], width: grid.rect[2], height: grid.rect[3])
            #expect(regions.contains { $0.contains(CGPoint(x: rect.midX, y: rect.midY)) })
            #expect(tables(in: blocks).isEmpty)
        } else {
            #expect(tables(in: blocks).first?.caption.first?.text == "Figure 6.11. Federal Reserve regulations governing the payment system")
        }
    }
}
