import CoreGraphics
import Foundation
import Testing
import ZIPFoundation
@testable import PDFReflowLib

// Real lists for verified bulleted and numbered runs (#194): the document pass that decides them,
// the writer's markup, page markers inside items, and tagged list structure.

/// A list-shaped block as reconstruction leaves it: preformatted, with its marker line's evidence.
private func item(_ text: String, page: Int = 1, edge: CGFloat = 72, size: CGFloat = 10,
                  tag: ListTag? = nil, recognized: Bool = false) -> ReflowBlock {
    var block = ReflowBlock(content: .preformatted(InlineText(text)), page: page)
    block.listEvidence = .init(edge: edge, fontSize: size, recognized: recognized, tag: tag)
    return block
}
private func paragraph(_ text: String, page: Int = 1) -> ReflowBlock {
    ReflowBlock(content: .paragraph(InlineText(text)), page: page)
}
private func built(_ blocks: [ReflowBlock]) -> [ReflowBlock] {
    var blocks = blocks
    ListBuilder.build(&blocks)
    return blocks
}
private func listItems(_ blocks: [ReflowBlock]) -> [ReflowBlock.ListItem] {
    blocks.compactMap { if case let .listItem(item) = $0.content { item } else { nil } }
}
private func preformatted(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case let .preformatted(text) = $0.content { text.text } else { nil } }
}

@Test func bulletedRunBecomesUnorderedItemsWithoutTheirPrintedGlyph() {
    let result = built([item("• Alternator switch position"), item("• Battery master switch"),
                        paragraph("Then the engine starts.")])
    let items = listItems(result)
    #expect(items.map(\.text.text) == ["Alternator switch position", "Battery master switch"])
    #expect(items.map(\.marker) == ["•", "•"])
    #expect(items.allSatisfy { $0.kind == .unordered && $0.level == 0 })
    #expect(items.map(\.opensList) == [true, false])
    // Negative control: one bullet with no sibling is no list.
    let lone = built([item("• Temporary flight restrictions"), paragraph("Prose follows.")])
    #expect(listItems(lone).isEmpty)
}

@Test func aLoneMarkedLineIsAParagraphKeepingItsMarker() {
    // #195: nothing list-shaped on its page or the pages beside it, so an ordinary paragraph.
    let lone = built([paragraph("Prose before.", page: 5), item("1) Get a Kit", page: 6), paragraph("Prose after.", page: 6),
                      item("• Another lone line of text", page: 8)])
    #expect(lone.map(\.content) == [.paragraph(InlineText("Prose before.")), .paragraph(InlineText("1) Get a Kit")),
                                    .paragraph(InlineText("Prose after.")), .paragraph(InlineText("• Another lone line of text"))])
    #expect(lone.allSatisfy { $0.listEvidence == nil })
    // Negative controls: a list-shaped block on the next page (here a lettered item, which forms no
    // list), a note's asterisk, recognition debris and a multi-line block stay preformatted.
    let near = [item("• Temporary flight restrictions", page: 6), paragraph("Prose.", page: 6),
                item("a. Airship with its own engine", page: 7)]
    #expect(preformatted(built(near)) == ["• Temporary flight restrictions", "a. Airship with its own engine"])
    #expect(preformatted(built([item("* Estimated for the year")])) == ["* Estimated for the year"])
    #expect(preformatted(built([item("- 26%", recognized: true)])) == ["- 26%"])
    #expect(preformatted(built([item("• First line\nsecond line")])) == ["• First line\nsecond line"])
    // Numbered section titles spread over the paper: `3.` has no list-shaped neighbour within a
    // page, but `2.` and `4.` are its siblings, so it stays as printed like them.
    let titles = [item("1. Introduction", page: 1), paragraph("Body.", page: 1), item("2. Classical Picture", page: 1),
                  paragraph("Body.", page: 2), item("3. Quantum Description", page: 3), paragraph("Body.", page: 4),
                  item("4. Plasma Averages", page: 6), paragraph("Body.", page: 6), item("5. Conclusions", page: 6)]
    #expect(preformatted(built(titles)).count == 5)
    // Negative control: without its siblings, the same line is a lone paragraph.
    #expect(preformatted(built([titles[3], titles[4], titles[5]])).isEmpty)
}

@Test func aPieceOfAVerifiedRunHoldingOneItemIsAParagraph() {
    // #195: `22.`–`24.` touch, `25.` stands between prose; the run verifies, but only two or more
    // items make a list element. The lone piece keeps its printed number as a paragraph.
    let result = built([item("22. Your full name:"), item("23. Your address:"), item("24. Your occupation:"),
                        paragraph("Lines to write on."), item("25. Last school you attended:"), paragraph("More lines.")])
    #expect(listItems(result).map(\.ordinal) == [22, 23, 24])
    #expect(result[4].content == .paragraph(InlineText("25. Last school you attended:")))
    #expect(result[4].listEvidence == nil)
    // Negative control: a numbered item with nested bullets is a piece of three items and lists.
    let nested = listItems(built([item("1. Reporting suggests attacks", edge: 72), item("• One source said so", edge: 90),
                                  item("• Another source agreed", edge: 90), paragraph("Prose."),
                                  item("2. Members received training", edge: 72), item("3. The network moves closer", edge: 72)]))
    #expect(nested.map(\.level) == [0, 1, 1, 0, 0])
}

@Test func recognizedNumberedItemsListOnlyWhereTheirNumbersRunConsecutively() {
    // The CIA questionnaire's inherited text layer (#195): `22.` to `24.` ascend by one.
    let questions = listItems(built([item("22. Your full name:", recognized: true), item("23. Your address:", recognized: true),
                                     item("24. Your occupation:", recognized: true)]))
    #expect(questions.map(\.ordinal) == [22, 23, 24])
    #expect(questions.map(\.text.text) == ["Your full name:", "Your address:", "Your occupation:"])
    // Negative controls: a gap, and recognized bullets (table headers read as dashes).
    let gap = [item("39. Do you think you can estimate the speed of the object?", recognized: true),
               item("41. Please give the following information about yourself:", recognized: true)]
    #expect(listItems(built(gap)).isEmpty)
    #expect(preformatted(built(gap)) == gap.map(\.text))
    #expect(listItems(built([item("- Per Cent Number", recognized: true), item("- Per Cent", recognized: true)])).isEmpty)
    // A transcribed notes page: recognition garbles `4.` and `5.` into no item, and the readable
    // notes beside them form runs their numbering continues.
    let notes = [item("1. Martin Isaacs DE 1, but see footnote nine.", recognized: true),
                 item("2. Ibid., 1 H 318 (Robert Oswald).", recognized: true),
                 item("3. 1 H 132 (Marguerite Oswald).", recognized: true),
                 item("4. Isaacs DE 1 : CE 1159.", recognized: true),
                 item("5. Isaacs DE 1 ; CE 1159.", recognized: true),
                 item("6. CE 1159: 1 H 3 (Marina Oswald).", recognized: true),
                 item("7. Isaacs DE 1 (Martin Isaacs).", recognized: true),
                 item("8. 8 H 336 (Pauline Bates).", recognized: true)]
    #expect(listItems(built(notes)).isEmpty)
    // Negative controls: the same run typeset is held to #194's rules alone, and a transcribed run
    // set off by lettered options, as the questionnaire's are, still lists.
    #expect(listItems(built(notes.map { var block = $0; block.listEvidence?.recognized = false; return block })).count == 6)
    let options = listItems(built([item("18. The edges of the object were:", recognized: true),
                                   item("c. Sharply outlined", recognized: true),
                                   item("19. IF there was MORE THAN ONE object, then how many were there?", recognized: true),
                                   item("20. Draw a picture that will show the motion of the object.", recognized: true),
                                   item("d. Nickel", recognized: true)]))
    #expect(options.map(\.ordinal) == [19, 20])
}

@Test func numberedRunAscendingByOneKeepsItsPrintedStart() {
    let result = built([item("6. Recognize the chances of an approach accident."),
                        item("7. Maintain optimum proficiency in landing procedures.")])
    let items = listItems(result)
    #expect(items.map(\.ordinal) == [6, 7])
    #expect(items.map(\.text.text) == ["Recognize the chances of an approach accident.",
                                       "Maintain optimum proficiency in landing procedures."])
    #expect(items.allSatisfy { $0.kind == .ordered })
    // A `1` opens a new list even straight after another numbered item.
    let restarted = listItems(built([item("1. Stalls from steep turns"), item("2. Structural failures in acrobatics"),
                                     item("1. Airspeed in a spin is very low"), item("2. An aircraft pivots in a spin")]))
    #expect(restarted.map(\.opensList) == [true, false, true, false])
    #expect(restarted.map(\.ordinal) == [1, 2, 1, 2])
}

@Test(arguments: [
    ["1. Distribute through any parentheses", "3. Get the variables on one side"],   // a gap
    ["3. Answer the question using the constant", "2. Find the constant of variation"], // a step back
    ["2019. In October the committee announced", "2020. Then in the pandemic the committee"], // years
])
func numberedRunThatDoesNotAscendByOneStaysPreformatted(_ lines: [String]) {
    let result = built(lines.map { item($0) })
    #expect(listItems(result).isEmpty)
    #expect(preformatted(result) == lines)
}

@Test func unverifiableListShapesStayPreformatted() {
    // Answer-key values, recognized bullets, a contents list and code are not list items.
    #expect(listItems(built([item("1) 5"), item("2) 7")])).isEmpty)
    #expect(listItems(built([item("- Per Cent Number", recognized: true), item("- Per Cent", recognized: true)])).isEmpty)
    let contents = [item("4. RESPONSES TO AL QAEDA’S INITIAL ASSAULTS 108 4.1 Before the Bombings 108"),
                    item("5. AL QAEDA AIMS AT THE AMERICAN HOMELAND 145 5.1 Terrorist Entrepreneurs 145"),
                    item("6. FROM THREAT TO THREAT 174")]
    #expect(listItems(built(contents)).isEmpty)
    let code = ReflowBlock(content: .preformatted(InlineText("- keep this dash")), page: 1)
    #expect(built([code, code]) == [code, code])
    // An elision is not a bullet; numbered items each standing alone between prose are titles.
    #expect(listItems(built([item("* * * he asked me"), item("* * * and then")])).isEmpty)
    #expect(listItems(built([item("1. Introduction"), paragraph("Body text."), item("2. Classical Picture")])).isEmpty)
    // A numbered reference list and numbered word problems keep their printed numbers.
    #expect(listItems(built([item("1. IPCC, 2021: Climate Change 2021: The Physical Science Basis. Cambridge University Press."),
                             item("2. USGCRP, 2018: Impacts, Risks, and Adaptation. https://doi.org/10.7930/NCA4.2018")])).isEmpty)
    #expect(listItems(built([item("33. Mann, M.E., S. Rahmstorf, K. Kornhuber, B.A. Steinman, S.K. Miller, S. Petri"),
                             item("34. van Vuuren, D.P., J. Edmonds, M. Kainuma, K. Riahi, A. Thomson, K. Hibbard")])).isEmpty)
    #expect(listItems(built([item("380. Liu, M.J., K.N. Izquierdo, and D.S. Prince, 2022: Intelligent monitoring of fugitive"),
                             item("381. Norooz Oliaee, J., N.A. Sabourin, S.A. Festa-Bianchet, J.A. Gupta")])).isEmpty)
    // Negative control: dated items name no author before the year.
    #expect(listItems(built([item("1. January 2000: the CIA does not watchlist Khalid al Mihdhar"),
                             item("2. March 2000: the CIA does not watchlist Nawaf al Hazmi")])).count == 2)
    #expect(listItems(built([item("1. When five is added to a number, the result is 19. What is the number?"),
                             item("2. A certain number added twice to itself equals 96. What is the number?")])).isEmpty)
    // Negative control for the contents rule: a run with a number inside its prose still converts.
    #expect(listItems(built([item("1. Setting the altimeter to 29.92 and reading the altitude"),
                             item("2. Applying a correction factor to the indicated altitude")])).count == 2)
}

@Test func deeperMarkersNestAndARunInterruptedByProseSplits() {
    // The dietary guidelines' `+` items with `-` items set deeper beneath one of them.
    let result = built([item("+ For children, the recommendations vary by age:", edge: 72),
                        item("- Ages 1–3: less than 1,200 mg per day", edge: 84),
                        item("- Ages 4–8: less than 1,500 mg per day", edge: 84),
                        item("+ Highly processed foods high in sodium should be avoided.", edge: 72),
                        paragraph("A paragraph between two lists."),
                        item("+ Consume less alcohol for better overall health.", edge: 72),
                        item("+ Some people should avoid alcohol completely.", edge: 72)])
    let items = listItems(result)
    #expect(items.map(\.level) == [0, 1, 1, 0, 0, 0])
    #expect(items.map(\.opensList) == [true, true, false, false, true, false])
    // In the next column the edges say nothing; the marker matches its own level.
    let column = listItems(built([item("+ Examples of foods to introduce include:", edge: 72),
                                  item("- Meat, poultry, and seafood", edge: 84),
                                  item("+ Avoid added sugars during infancy.", edge: 320)]))
    #expect(column.map(\.level) == [0, 1, 0])
}

@Test func aLoneDeeperBulletBetweenNumberedItemsIsNestedInTheList() {
    // 9/11 page 147: bullets set under the daily brief's numbered paragraphs, one of them alone.
    let result = built([item("1. Reporting suggests Bin Ladin and his allies are preparing attacks", edge: 72),
                        item("• IG leader Islambuli was planning to hijack an airliner", edge: 90),
                        item("• The same source said Bin Ladin might implement plans", edge: 90),
                        item("2. Some members of the network have received hijack training", edge: 72),
                        item("• A source told us that extremist elements had acquired missiles", edge: 90),
                        item("3. Reporting indicates the organization is moving closer", edge: 72)])
    let items = listItems(result)
    #expect(items.count == 6)
    #expect(items.map(\.level) == [0, 1, 1, 0, 1, 0])
    #expect(items.filter { $0.level == 0 }.map(\.opensList) == [true, false, false])
    // The first item opens on page 146 and its bullets follow on page 147, whose margin is not
    // page 146's: they nest because the next numbered item stands left of them on their own page.
    let across = listItems(built([item("1. Reporting suggests Bin Ladin and his allies are preparing attacks", page: 146, edge: 72),
                                  item("• IG leader Islambuli was planning to hijack an airliner", page: 147, edge: 99),
                                  item("• The same source said Bin Ladin might implement plans", page: 147, edge: 99),
                                  item("2. Some members of the network have received hijack training", page: 147, edge: 81)]))
    #expect(across.map(\.level) == [0, 1, 1, 0])
    #expect(across.map(\.opensList) == [true, true, false, false])
    // Negative control: with the numbered item at the bullets' edge, they are its siblings' list.
    let flat = listItems(built([item("1. Reporting suggests Bin Ladin and his allies are preparing attacks", page: 146, edge: 72),
                                item("• IG leader Islambuli was planning to hijack an airliner", page: 147, edge: 81),
                                item("• The same source said Bin Ladin might implement plans", page: 147, edge: 81),
                                item("2. Some members of the network have received hijack training", page: 147, edge: 81)]))
    #expect(flat.map(\.level) == [0, 0, 0, 0])
}

@Test func taggedListsDecideDepthAndListIdentity() {
    let first = ListTag(list: 1, item: 1, depth: 0, label: true)
    let second = ListTag(list: 1, item: 2, depth: 0, label: true)
    let other = ListTag(list: 2, item: 3, depth: 0, label: true)
    let nested = ListTag(list: 3, item: 4, depth: 1, label: true)
    // Same edges throughout: only the tags say where one list ends and where one nests.
    let items = listItems(built([item("• one", tag: first), item("• two", tag: second),
                                 item("• three", tag: nested), item("• four", tag: other)]))
    #expect(items.map(\.level) == [0, 0, 1, 0])
    #expect(items.map(\.opensList) == [true, false, true, true])
    // A list element the producer closed at the page break continues on the next page.
    let paged = listItems(built([item("• one", page: 1, tag: first), item("• two", page: 1, tag: second),
                                 item("• three", page: 2, tag: other)]))
    #expect(paged.map(\.opensList) == [true, false, false])
}

@Test func markerStrippingKeepsLeadingPageBoundariesAndStyles() {
    let text = InlineText(elements: [.sourcePage(4), .text("12. ", .bold), .text("Remarks", [.bold, .italic]),
                                     .text(" section", [])])
    let stripped = ListBuilder.dropping(ListBuilder.marker(text.text)!.length, from: text)
    #expect(stripped == InlineText(elements: [.sourcePage(4), .text("Remarks", [.bold, .italic]), .text(" section", [])]))
    #expect(ListBuilder.marker("10.August 2001: the CIA")?.value == 10)
    #expect(ListBuilder.marker("− 7ab− 2ab") == nil)
    #expect(ListBuilder.marker("3.5 percent") == nil)
}

private func writtenBody(_ blocks: [ReflowBlock], chapterStarts: Set<Int> = []) async throws -> [String] {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let book = ReflowDocument(metadata: .init(title: "Lists", language: "en"), blocks: blocks, assets: [],
                              chapterStartPages: chapterStarts)
    let url = try await EPUBWriter.write(book, maximumOutputBytes: 10_000_000, directory: dir, progress: { _ in })
    let archive = try Archive(url: url, accessMode: .read)
    return try archive.filter { $0.path.hasPrefix("EPUB/chapter-") }.sorted { $0.path < $1.path }.map { entry in
        var data = Data()
        _ = try archive.extract(entry) { data += $0 }
        let text = String(decoding: data, as: UTF8.self)
        return String(text[text.range(of: "<body>")!.upperBound..<text.range(of: "</body>")!.lowerBound])
    }
}

/// Every list element's children are items, in every spine document.
private func listsHoldOnlyItems(_ body: String) throws -> Bool {
    let document = try XMLDocument(xmlString: "<body xmlns:epub=\"http://www.idpf.org/2007/ops\">\(body)</body>")
    let lists = try document.nodes(forXPath: "//ul | //ol")
    return lists.allSatisfy { list in (list.children ?? []).allSatisfy { $0.name == "li" } }
}

@Test func writerOpensNestsAndClosesListsAndPutsPageMarkersInsideItems() async throws {
    let blocks = built([
        ReflowBlock(content: .sourcePage(1), page: 1),
        item("3. Third step of the procedure", page: 1), item("4. Fourth step of the procedure", page: 1),
        item("• A detail of the fourth step", page: 1, edge: 90), item("• Another detail of it", page: 1, edge: 90),
        ReflowBlock(content: .sourcePage(2), page: 2),
        item("5. Fifth step of the procedure", page: 2),
        paragraph("After the list.", page: 2),
    ])
    let body = try #require(try await writtenBody(blocks).first)
    #expect(body.contains("<ol start=\"3\"><li>\(EPUBTextEncoder.sourcePage(1))Third step of the procedure</li><li>Fourth step of the procedure"
        + "<ul><li>A detail of the fourth step</li><li>Another detail of it</li></ul></li>"
        + "<li><span epub:type=\"pagebreak\" role=\"doc-pagebreak\" id=\"page-2\" aria-label=\"2\"/>Fifth step of the procedure</li></ol>\n<p>After the list.</p>"), "\(body)")
    #expect(try listsHoldOnlyItems(body))
    // Negative control: the same markup with the marker between the items is caught.
    #expect(try !listsHoldOnlyItems("<ul><li>a</li><span epub:type=\"pagebreak\" id=\"page-2\"/><li>b</li></ul>"))
}

@Test func writerKeepsEmptyPagesInsideTheListAndClosesItAtAChapterStart() async throws {
    // Built directly: the list pass itself chains items only across one page boundary.
    func bullet(_ text: String, page: Int, opens: Bool = false) -> ReflowBlock {
        ReflowBlock(content: .listItem(.init(text: InlineText(text), marker: "•", kind: .unordered, opensList: opens)), page: page)
    }
    let blocks = [
        ReflowBlock(content: .sourcePage(1), page: 1),
        bullet("First bulleted item", page: 1, opens: true),
        ReflowBlock(content: .sourcePage(2), page: 2), ReflowBlock(content: .sourcePage(3), page: 3),
        bullet("Second bulleted item", page: 3),
        ReflowBlock(content: .sourcePage(4), page: 4),
        bullet("Third bulleted item", page: 4),
    ]
    let bodies = try await writtenBody(blocks)
    #expect(bodies.count == 1)
    #expect(bodies[0].contains("<ul><li>\(EPUBTextEncoder.sourcePage(1))First bulleted item<span epub:type=\"pagebreak\" role=\"doc-pagebreak\" id=\"page-2\" aria-label=\"2\"/></li>"
        + "<li><span epub:type=\"pagebreak\" role=\"doc-pagebreak\" id=\"page-3\" aria-label=\"3\"/>Second bulleted item</li>"), "\(bodies[0])")
    #expect(try listsHoldOnlyItems(bodies[0]))
    // A chapter opening between two items closes the list in one document and opens it in the next.
    let split = try await writtenBody(blocks, chapterStarts: [4])
    #expect(split.count == 2)
    #expect(split[0].hasSuffix("Second bulleted item</li></ul>\n"))
    #expect(split[1].contains("<ul><li><span epub:type=\"pagebreak\" role=\"doc-pagebreak\" id=\"page-4\" aria-label=\"4\"/>Third bulleted item</li></ul>"))
    for body in split { #expect(try listsHoldOnlyItems(body)) }
}

// A tagged numbered list: `L` > `LI` > `Lbl` + `LBody`, then a paragraph. The first item's body
// runs to a second line after a sentence, which only the tags join to it.
private func taggedListObjects(secondLineItem: String = "11 0 R") -> [String] {
    [
        "<< /Type /Catalog /Pages 2 0 R /StructTreeRoot 6 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R /StructParents 0 >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        testPDFStream("""
        /Lbl << /MCID 0 >> BDC BT /F1 10 Tf 1 0 0 1 40 700 Tm (1.) Tj ET EMC
        /LBody << /MCID 1 >> BDC BT /F1 10 Tf 1 0 0 1 56 700 Tm (Check the weather.) Tj ET EMC
        /LBody << /MCID 5 >> BDC BT /F1 10 Tf 1 0 0 1 56 688 Tm (Then file the plan.) Tj ET EMC
        /Lbl << /MCID 2 >> BDC BT /F1 10 Tf 1 0 0 1 40 676 Tm (2.) Tj ET EMC
        /LBody << /MCID 3 >> BDC BT /F1 10 Tf 1 0 0 1 56 676 Tm (Brief the passengers.) Tj ET EMC
        /P << /MCID 4 >> BDC BT /F1 10 Tf 1 0 0 1 40 640 Tm (After the list.) Tj ET EMC
        """),
        "<< /Type /StructTreeRoot /K [8 0 R 12 0 R] /ParentTree 7 0 R >>",
        "<< /Nums [0 [10 0 R 11 0 R 14 0 R 15 0 R 12 0 R \(secondLineItem)]] >>",
        "<< /Type /StructElem /S /L /P 6 0 R /K [9 0 R 13 0 R] >>",
        "<< /Type /StructElem /S /LI /P 8 0 R /K [10 0 R 11 0 R] >>",
        "<< /Type /StructElem /S /Lbl /P 9 0 R /Pg 3 0 R /K 0 >>",
        "<< /Type /StructElem /S /LBody /P 9 0 R /Pg 3 0 R /K [1 5] >>",
        "<< /Type /StructElem /S /P /P 6 0 R /Pg 3 0 R /K 4 >>",
        "<< /Type /StructElem /S /LI /P 8 0 R /K [14 0 R 15 0 R] >>",
        "<< /Type /StructElem /S /Lbl /P 13 0 R /Pg 3 0 R /K 2 >>",
        "<< /Type /StructElem /S /LBody /P 13 0 R /Pg 3 0 R /K 3 >>",
    ]
}

private func taggedListLines() -> [TextLine] {
    [TextLine(text: "1. Check the weather.", rect: CGRect(x: 40, y: 697, width: 110, height: 12), fontSize: 10),
     TextLine(text: "Then file the plan.", rect: CGRect(x: 56, y: 685, width: 90, height: 12), fontSize: 10),
     TextLine(text: "2. Brief the passengers.", rect: CGRect(x: 40, y: 673, width: 120, height: 12), fontSize: 10),
     TextLine(text: "After the list.", rect: CGRect(x: 40, y: 637, width: 80, height: 12), fontSize: 10)]
}

@Test func taggedListItemsAnnotateTheirLinesAndDecideItemBoundaries() throws {
    let directory = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("list.pdf")
    try testPDF(objects: taggedListObjects()).write(to: url)
    let document = try #require(CGPDFDocument(url as CFURL))
    let page = try #require(document.page(at: 1))
    let index = try StructureTreeReader.read(url)
    let tags = try #require(index.listTags[1])
    #expect(Set(tags.keys) == [0, 1, 2, 3, 5])
    #expect(tags[0]?.label == true && tags[1]?.label == false && tags[5]?.item == tags[0]?.item)
    #expect(tags[2]?.item != tags[0]?.item && tags[2]?.list == tags[0]?.list && tags[0]?.depth == 0)
    // List roles form no paragraph groups: only the paragraph after the list is grouped.
    #expect(Set(try #require(index.pages[1]).keys) == [4])
    #expect(StructureTreeReader.validates(tags, owners: try #require(index.listOwners[1]), page: page))
    var lines = taggedListLines()
    #expect(MarkedTextReader.apply(try #require(index.pages[1]), listTags: tags, page: page, lines: &lines))
    #expect(lines[0].listTag?.label == true && lines[1].listTag?.item == lines[0].listTag?.item)
    #expect(lines[2].listTag?.item == tags[2]?.item && lines[3].listTag == nil)
    var warnings: [ConversionWarning] = []
    var blocks = LayoutReconstructor.blocks(page: .init(number: 1, bounds: page.getBoxRect(.cropBox), lines: lines, graphics: []),
        images: [], vocabulary: [], warnings: &warnings)
    ListBuilder.build(&blocks)
    let items = listItems(blocks)
    // The tags join the sentence the geometry alone would leave as a paragraph.
    #expect(items.map(\.text.text) == ["Check the weather. Then file the plan.", "Brief the passengers."])
    #expect(items.map(\.opensList) == [true, false])
    // Negative control: without the tags, the item ends at its first sentence, and the numbered
    // items, each standing alone beside prose, stay preformatted.
    var untagged = taggedListLines()
    var plain = LayoutReconstructor.blocks(page: .init(number: 1, bounds: page.getBoxRect(.cropBox), lines: untagged, graphics: []),
        images: [], vocabulary: [], warnings: &warnings)
    ListBuilder.build(&plain)
    #expect(plain.map(\.text) == ["1. Check the weather.", "Then file the plan.", "2. Brief the passengers.", "After the list."])
    #expect(listItems(plain).isEmpty)
    // A line whose shows name two items carries neither.
    untagged = [TextLine(text: "1. Check the weather. 2. Brief", rect: CGRect(x: 40, y: 670, width: 200, height: 40), fontSize: 10)]
    _ = MarkedTextReader.apply([:], listTags: tags, page: page, lines: &untagged)
    #expect(untagged[0].listTag == nil)
}

@Test func listItemsTaggedOutsideAnyListBelongToTheListTheirParentHolds() throws {
    // Our Flag tags its folding steps as `Sect` > `LI`, with no `L`.
    var objects = taggedListObjects()
    objects[7] = objects[7].replacingOccurrences(of: "/S /L ", with: "/S /Sect ")
    let directory = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("sect.pdf")
    try testPDF(objects: objects).write(to: url)
    let tags = try #require(try StructureTreeReader.read(url).listTags[1])
    #expect(Set(tags.keys) == [0, 1, 2, 3, 5])
    #expect(tags[0]?.list == tags[2]?.list && tags[0]?.item != tags[2]?.item && tags[0]?.depth == 0)
}
