import CoreGraphics
import Foundation
import Testing
import ZIPFoundation
@testable import PDFReflowLib

// Real lists for verified bulleted and numbered runs (#292): the pass that decides them as the
// document streams past, the evidence reconstruction leaves for it, the writer's markup, and
// the page markers a list may not hold between its items.

/// A list-shaped block as reconstruction leaves it: preformatted, opened by a marker.
private func item(_ text: String, page: Int = 1, recognized: Bool = false) -> ReflowBlock {
    var block = ReflowBlock(content: .preformatted(InlineText(text)), page: page)
    block.listEvidence = .init(recognized: recognized)
    return block
}
private func paragraph(_ text: String, page: Int = 1) -> ReflowBlock {
    ReflowBlock(content: .paragraph(InlineText(text)), page: page)
}
private func heading(_ text: String, page: Int = 1) -> ReflowBlock {
    ReflowBlock(content: .heading(id: "h-\(page)", text: InlineText(text)), page: page)
}
private func marker(_ page: Int) -> ReflowBlock { ReflowBlock(content: .sourcePage(page), page: page) }
private func built(_ blocks: [ReflowBlock]) -> [ReflowBlock] { ListBuilder.build(blocks) }
private func listItems(_ blocks: [ReflowBlock]) -> [ReflowBlock.ListItem] {
    blocks.compactMap { if case let .listItem(item) = $0.content { item } else { nil } }
}
private func preformatted(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case let .preformatted(text) = $0.content { text.text } else { nil } }
}
private func paragraphs(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case let .paragraph(text) = $0.content { text.text } else { nil } }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/292"))
func bulletedRunBecomesUnorderedItemsWithoutTheirPrintedGlyph() {
    let result = built([item("• Alternator switch position"), item("• Battery master switch"),
                        paragraph("Then the engine starts.")])
    let items = listItems(result)
    #expect(items.map(\.text.text) == ["Alternator switch position", "Battery master switch"])
    #expect(items.map(\.marker) == ["•", "•"])
    #expect(items.allSatisfy { $0.kind == .unordered && $0.ordinal == nil })
    #expect(items.map(\.opensList) == [true, false])
    #expect(result.allSatisfy { $0.listEvidence == nil })
    // The four bullet glyphs, each its own family: a run of one glyph is one list.
    for glyph in ["•", "-", "*", "+"] {
        let pair = built([item("\(glyph) Alternator switch position"), item("\(glyph) Battery master switch")])
        #expect(listItems(pair).map(\.marker) == [glyph, glyph], "\(glyph)")
    }
    // A change of glyph ends the list element: two runs, two lists, no nesting.
    let mixed = listItems(built([item("• one thing"), item("• another thing"), item("- a third thing"), item("- a fourth thing")]))
    #expect(mixed.map(\.opensList) == [true, false, true, false])
    // Negative controls: a minus opens Wallace's derivation rows, some of which read as words,
    // so it is no bullet; an elision is not one either; a block without marker evidence — code —
    // is never read at all.
    #expect(listItems(built([item("− 7+6x Our Solution"), item("− 5x +10 Our Solution")])).isEmpty)
    #expect(listItems(built([item("* * * he asked me"), item("* * * and then")])).isEmpty)
    let code = ReflowBlock(content: .preformatted(InlineText("- keep this dash")), page: 1)
    #expect(built([code, code]) == [code, code])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/292"))
func numberedRunAscendingByOneKeepsItsPrintedStart() {
    let result = built([item("6. Recognize the chances of an approach accident."),
                        item("7. Maintain optimum proficiency in landing procedures.")])
    let items = listItems(result)
    #expect(items.map(\.ordinal) == [6, 7])
    #expect(items.map(\.marker) == ["6.", "7."])
    #expect(items.map(\.text.text) == ["Recognize the chances of an approach accident.",
                                       "Maintain optimum proficiency in landing procedures."])
    #expect(items.allSatisfy { $0.kind == .ordered })
    // A `1` opens a new list even straight after another numbered item.
    let restarted = listItems(built([item("1. Stalls from steep turns"), item("2. Structural failures in acrobatics"),
                                     item("1. Airspeed in a spin is very low"), item("2. An aircraft pivots in a spin")]))
    #expect(restarted.map(\.opensList) == [true, false, true, false])
    #expect(restarted.map(\.ordinal) == [1, 2, 1, 2])
    // A bracket is a family of its own, and the two never chain.
    let brackets = listItems(built([item("1) The ability to determine other flights"), item("2) The ability to query the others")]))
    #expect(brackets.map(\.marker) == ["1)", "2)"])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/292"), arguments: [
    ["1. Distribute through any parentheses", "3. Get the variables on one side"],       // a gap
    ["3. Answer the question using the constant", "2. Find the constant of variation"],  // a step back
    ["2019. In October the committee announced", "2020. Then in the pandemic the committee"], // years
    ["1. Introduction to the whole matter", "1. Introduction repeated once more"],      // no advance
])
func numberedRunThatDoesNotAscendByOneStaysPreformatted(_ lines: [String]) {
    let result = built(lines.map { item($0) })
    #expect(listItems(result).isEmpty)
    #expect(preformatted(result) == lines)
    #expect(result.allSatisfy { $0.listEvidence != nil })
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/292"))
func aLoneMarkedLineIsAParagraphKeepingItsMarker() {
    // #195: nothing list-shaped on its page or the pages beside it, so an ordinary paragraph.
    let lone = built([paragraph("Prose before.", page: 5), item("1) Get a Kit", page: 6), paragraph("Prose after.", page: 6),
                      item("• Another lone line of text", page: 9)])
    #expect(lone.map(\.content) == [.paragraph(InlineText("Prose before.")), .paragraph(InlineText("1) Get a Kit")),
                                    .paragraph(InlineText("Prose after.")), .paragraph(InlineText("• Another lone line of text"))])
    #expect(lone.allSatisfy { $0.listEvidence == nil })
    // Negative controls: a list-shaped block on the next page (here a lettered item, which forms
    // no list), a note's asterisk, recognition debris and a multi-line block stay preformatted.
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
                  item("4. Plasma Averages", page: 5), paragraph("Body.", page: 6), item("5. Conclusions", page: 6)]
    #expect(preformatted(built(titles)).count == 5)
    // Negative control: without its siblings, the same line is a lone paragraph.
    #expect(preformatted(built([titles[3], titles[4], titles[5]])).isEmpty)
    #expect(paragraphs(built([titles[3], titles[4], titles[5]])) == ["Body.", "3. Quantum Description", "Body."])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/292"))
func aPieceOfAVerifiedRunHoldingOneItemIsAParagraph() {
    // #195: `22.`–`24.` touch, `25.` stands between prose; the run verifies, but only two or more
    // items make a list element. The lone piece keeps its printed number as a paragraph.
    let result = built([item("22. Your full name:"), item("23. Your address:"), item("24. Your occupation:"),
                        paragraph("Lines to write on."), item("25. Last school you attended:"), paragraph("More lines.")])
    #expect(listItems(result).map(\.ordinal) == [22, 23, 24])
    #expect(result[4].content == .paragraph(InlineText("25. Last school you attended:")))
    #expect(result[4].listEvidence == nil)
    // Only page boundaries may stand between two items of one piece.
    let paged = built([marker(1), item("1. First item of the list", page: 1), marker(2),
                       item("2. Second item of the list", page: 2), item("3. Third item of the list", page: 2)])
    #expect(listItems(paged).map(\.opensList) == [true, false, false])
    // Items are flat: bullets between two numbered items end the numbered list element, so each
    // numbered item is a piece of one and a paragraph, and the bullets are a list of their own.
    let brief = built([item("1. Reporting suggests attacks"), item("• One source said so"), item("• Another source agreed"),
                       item("2. Members received training"), item("• A source told us so"), item("3. The network moves closer")])
    #expect(paragraphs(brief) == ["1. Reporting suggests attacks", "2. Members received training",
                                  "• A source told us so", "3. The network moves closer"])
    #expect(listItems(brief).map(\.text.text) == ["One source said so", "Another source agreed"])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/292"))
func recognizedNumberedItemsListOnlyWhereTheirNumbersRunConsecutively() {
    // The Blue Book questionnaire's inherited text layer (#195): `22.` to `24.` ascend by one.
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
    // A transcribed run set off by lettered options, as the questionnaire's are, still lists.
    let options = listItems(built([item("18. The edges of the object were:", recognized: true),
                                   item("c. Sharply outlined", recognized: true),
                                   item("19. IF there was MORE THAN ONE object, then how many were there?", recognized: true),
                                   item("20. Draw a picture that will show the motion of the object.", recognized: true),
                                   item("d. Nickel", recognized: true)]))
    #expect(options.map(\.ordinal) == [19, 20])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/292"))
func aRunThatContinuesAnApparatusOfEntriesStaysWithIt() {
    // A transcribed notes page: recognition garbles `4.` and `5.` into no item, and the readable
    // notes beside them form runs their numbering continues (Warren page 897).
    let notes = [item("1. Martin Isaacs DE 1, but see footnote nine.", recognized: true),
                 item("2. Ibid., 1 H 318 (Robert Oswald).", recognized: true),
                 item("3. 1 H 132 (Marguerite Oswald).", recognized: true),
                 item("4. Isaacs DE 1 : CE 1159.", recognized: true),
                 item("5. Isaacs DE 1 ; CE 1159.", recognized: true),
                 item("6. CE 1159: 1 H 3 (Marina Oswald).", recognized: true),
                 item("7. Isaacs DE 1 (Martin Isaacs).", recognized: true),
                 item("8. 8 H 336 (Pauline Bates).", recognized: true)]
    #expect(listItems(built(notes)).isEmpty)
    // An exercise set opens on conversions of figures and goes on in words (Wallace page 285):
    // the run `4.`–`6.` continues `3.`, which reads as no item, and stays with it.
    let conversions = [item("1. 7 mi. to feet"), item("2. 234 oz. to tons"), item("3. 11.2 mg to grams"),
                       item("4. 1.35 km to centimeters"), item("5. 9,800,000 mm (milimeters) to miles"),
                       item("6. 4.5 ft2 to square yards")]
    #expect(listItems(built(conversions)).isEmpty)
    // Negative control: a list whose run is set off by other blocks, not by a numbered entry.
    let setOff = listItems(built([paragraph("Intro."), item("1. Recognize the chances of an accident."),
                                  item("2. Maintain proficiency in landing procedures."), paragraph("Then prose.")]))
    #expect(setOff.map(\.ordinal) == [1, 2])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/292"))
func unverifiableListShapesStayPreformatted() {
    // Answer-key values, a contents list, numbered titles each standing alone, a numbered
    // reference list and numbered word problems keep their printed numbers.
    #expect(listItems(built([item("1) 5"), item("2) 7")])).isEmpty)
    let contents = [item("4. RESPONSES TO AL QAEDA’S INITIAL ASSAULTS 108 4.1 Before the Bombings 108"),
                    item("5. AL QAEDA AIMS AT THE AMERICAN HOMELAND 145 5.1 Terrorist Entrepreneurs 145"),
                    item("6. FROM THREAT TO THREAT 174")]
    #expect(listItems(built(contents)).isEmpty)
    #expect(listItems(built([item("1. Introduction"), paragraph("Body text."), item("2. Classical Picture")])).isEmpty)
    #expect(listItems(built([item("1. IPCC, 2021: Climate Change 2021: The Physical Science Basis. Cambridge University Press."),
                             item("2. USGCRP, 2018: Impacts, Risks, and Adaptation. https://doi.org/10.7930/NCA4.2018")])).isEmpty)
    #expect(listItems(built([item("33. Mann, M.E., S. Rahmstorf, K. Kornhuber, B.A. Steinman, S.K. Miller, S. Petri"),
                             item("34. van Vuuren, D.P., J. Edmonds, M. Kainuma, K. Riahi, A. Thomson, K. Hibbard")])).isEmpty)
    #expect(listItems(built([item("1. When five is added to a number, the result is 19. What is the number?"),
                             item("2. A certain number added twice to itself equals 96. What is the number?")])).isEmpty)
    // An answer key's two worded answers among its values are part of the key.
    let key = [item("44) 12"), item("45) − 2"), item("46) All real numbers"), item("47) No solution"), item("48) 3"), item("49) 0")]
    #expect(listItems(built(key)).isEmpty)
    // Negative controls: dated items name no author before the year, and a run with a number
    // inside its prose still converts.
    #expect(listItems(built([item("1. January 2000: the CIA does not watchlist Khalid al Mihdhar"),
                             item("2. March 2000: the CIA does not watchlist Nawaf al Hazmi")])).count == 2)
    #expect(listItems(built([item("1. Setting the altimeter to 29.92 and reading the altitude"),
                             item("2. Applying a correction factor to the indicated altitude")])).count == 2)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/292"))
func exerciseSetsUnderTheBooksOwnHeadingKeepTheirNumbers() {
    // Wallace heads every exercise set `Practice`; its numbered problems key the answers and wait
    // for their reading order (#219 item 4). Its worked procedures are headed otherwise and list.
    let exercises = [heading("1.7 Practice - Variation"), paragraph("Write the formula that expresses the relationship described"),
                     item("1. c varies directly as a"), item("2. x is jointly proportional to y and z"),
                     item("3. w varies inversely as x")]
    #expect(listItems(built(exercises)).isEmpty)
    #expect(preformatted(built(exercises)).count == 3)
    let procedure = [heading("1.3 Solving Linear Equations - General"), paragraph("The steps are:"),
                     item("1. Distribute through any parentheses."), item("2. Combine like terms on each side of the equation."),
                     item("3. Get the variables on one side by adding or subtracting")]
    #expect(listItems(built(procedure)).map(\.ordinal) == [1, 2, 3])
    // The heading in force is the last one: a set that runs on to the next page is still a set,
    // and a bulleted run under the heading is untouched by the rule.
    let continued = [heading("1.9 Practice - Number and Geometry Problems", page: 1), item("1. When five is added to a number", page: 1),
                     marker(2), item("2. A certain number added twice", page: 2), item("3. The sum of three integers", page: 2)]
    #expect(listItems(built(continued)).isEmpty)
    #expect(listItems(built([heading("Exercises"), item("• one thing to do"), item("• another thing to do")])).count == 2)
    #expect(ListBuilder.namesExercises("Chapter 3 Exercises") && ListBuilder.namesExercises("3.4 Practice - Three Variables"))
    #expect(!ListBuilder.namesExercises("Practiced Hands") && !ListBuilder.namesExercises("The Exercised Prerogative"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/292"))
func plusBulletsAreReadFromParagraphsAndOtherFamiliesBreakTheirList() {
    // The dietary guidelines set their top-level items with `+`, which reconstruction reads as an
    // operator and joins whole as paragraphs, and their sub-items with `-`.
    let result = built([paragraph("+ For children, the recommendations vary by age:"),
                        item("- Ages 1–3: less than 1,200 mg per day"), item("- Ages 4–8: less than 1,500 mg per day"),
                        paragraph("+ Highly processed foods high in sodium should be avoided."),
                        paragraph("+ Consume less alcohol for better overall health."),
                        paragraph("A paragraph between two lists."),
                        paragraph("+ Some older adults need fewer calories but still"),
                        paragraph("+ Following the Dietary Guidelines will support optimal health.")])
    let items = listItems(result)
    #expect(items.map(\.text.text) == ["Ages 1–3: less than 1,200 mg per day", "Ages 4–8: less than 1,500 mg per day",
                                       "Highly processed foods high in sodium should be avoided.",
                                       "Consume less alcohol for better overall health.",
                                       "Some older adults need fewer calories but still",
                                       "Following the Dietary Guidelines will support optimal health."])
    #expect(items.map(\.marker) == ["-", "-", "+", "+", "+", "+"])
    #expect(items.map(\.opensList) == [true, false, true, false, true, false])
    // The `+` item that its sub-items set apart is a piece of one, and stays the paragraph it was.
    #expect(paragraphs(result).first == "+ For children, the recommendations vary by age:")
    // Negative controls: a derivation row and recognition debris open with no bullet, and the
    // word test reads the whole paragraph.
    for text in ["+ 21 + 21 Add 21 to both sides", "+ c ~ 50 50 ~", "+ 28 + 28", "+"] {
        #expect(ListBuilder.marker(text) == nil, Comment(rawValue: text))
        #expect(paragraphs(built([paragraph(text), paragraph(text)])) == [text, text])
    }
    #expect(ListBuilder.marker("+ 100% fruit or vegetable juice should be consumed in limited portions")?.family == .bullet("+"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/292"))
func markerStrippingKeepsLeadingPageBoundariesStylesAndLinks() {
    let text = InlineText(elements: [.sourcePage(4), .text("12. ", .bold), .text("Remarks", [.bold, .italic]),
                                     .text(" section", [])])
    let stripped = ListBuilder.dropping(ListBuilder.marker(text.text)!.length, from: text)
    #expect(stripped == InlineText(elements: [.sourcePage(4), .text("Remarks", [.bold, .italic]), .text(" section", [])]))
    let linked = InlineText(elements: [.link(.page(3), InlineText("• See page")), .text(" three", [])])
    #expect(ListBuilder.dropping(2, from: linked) == InlineText(elements: [.link(.page(3), InlineText("See page")), .text(" three", [])]))
    #expect(ListBuilder.marker("3.5 percent") == nil)
    #expect(ListBuilder.marker("1234. Too many digits for an item") == nil)
    #expect(ListBuilder.marker("− 7ab− 2ab") == nil)
    #expect(ListBuilder.marker("•no space") == nil)
    #expect(ListBuilder.marker("12) Twelve")?.printed == "12)")
}

/// The pass holds a block only while its verdict can still change, and the stream it releases is
/// the document the whole-document build makes.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/292"))
func theStreamingPassReleasesBlocksAsRunsCloseAndMatchesTheWholeDocumentBuild() {
    var blocks: [ReflowBlock] = []
    let names = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"]
    for page in 1...12 {
        blocks.append(marker(page))
        blocks.append(paragraph("Prose on page \(names[page - 1]).", page: page))
        if page % 4 == 0 {
            blocks.append(item("1. First step on page \(names[page - 1])", page: page))
            blocks.append(item("2. Second step on page \(names[page - 1])", page: page))
        }
        if page == 6 { blocks.append(item("• A lone bullet on page six", page: page)) }
    }
    var builder = ListBuilder()
    var released: [ReflowBlock] = []
    var releasedBefore: [Int: Int] = [:]
    for block in blocks {
        released += builder.accept(block)
        releasedBefore[block.page] = released.count
    }
    released += builder.finish()
    #expect(released == ListBuilder.build(blocks))
    #expect(listItems(released).count == 6)
    #expect(paragraphs(released).contains("• A lone bullet on page six"))
    // A block that is no candidate is out at once; page 4's items wait until page 7 opens, and
    // page 6's lone bullet until page 9 does; nothing waits for the end but the last pages.
    #expect(releasedBefore[4] == 8)
    #expect(releasedBefore[6] == 8)
    #expect(releasedBefore[7]! >= 14)
    #expect(releasedBefore[8]! < 19)
    #expect(releasedBefore[9]! >= 19)
    #expect(releasedBefore[12]! < blocks.count)
    // Pages never reorder and no block is lost or duplicated.
    #expect(released.map(\.page) == blocks.map(\.page))
}

// MARK: - The evidence reconstruction leaves

private func reconstruct(_ page: PageContent, notesPage: Bool = false) -> [ReflowBlock] {
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings,
                                      numberedNotePage: notesPage)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/292"))
func markerOpenedBlocksCarryTheirEvidenceAndCodeTableRowsAndNotesPagesCarryNone() {
    func line(_ text: String, y: Double, x: Double = 40, mono: Bool = false) -> TextLine {
        TextLine(text: text, rect: CGRect(x: x, y: y, width: 300, height: 12), fontSize: 10, monospaced: mono)
    }
    let bounds = CGRect(x: 0, y: 0, width: 600, height: 800)
    var page = PageContent(number: 1, bounds: bounds, lines: [
        line("The engine starts once these are set:", y: 700),
        line("• Alternator switch position", y: 680), line("• Battery master switch", y: 660),
        line("if value < 3:", y: 620, mono: true), line("print(value)", y: 600, x: 68.8, mono: true),
    ], graphics: [])
    var blocks = reconstruct(page)
    let bullets = blocks.filter { $0.text.hasPrefix("•") }
    #expect(bullets.count == 2)
    #expect(bullets.allSatisfy { $0.listEvidence?.recognized == false && $0.listEvidence?.edge != nil })
    #expect(blocks.first { $0.text.hasPrefix("if value") }?.listEvidence == nil)
    #expect(listItems(ListBuilder.build(blocks)).map(\.text.text) == ["Alternator switch position", "Battery master switch"])
    // A transcription says so on its evidence, and a page the document heads as notes leaves none.
    page.recognized = true
    blocks = reconstruct(page)
    #expect(blocks.filter { $0.text.hasPrefix("•") }.allSatisfy {
        $0.listEvidence?.recognized == true && $0.listEvidence?.edge != nil
    })
    page.recognized = false
    #expect(reconstruct(page, notesPage: true).allSatisfy { $0.listEvidence == nil })
    // A numbered line on an edge the page sets a list on carries evidence; on an edge that reads
    // as a column of names it opens a paragraph and carries none (#171).
    let numbered = PageContent(number: 2, bounds: bounds, lines: [
        line("1. Illness—Am I sick?", y: 700), line("2. Medication—Am I taking any medicines?", y: 680),
        line("3. Stress—Am I under pressure?", y: 660),
    ], graphics: [])
    #expect(reconstruct(numbered).allSatisfy { $0.listEvidence != nil })
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/292"))
func sourcePagesListWhereTheirItemsAreWholeAndKeepWhatIsNotAList() throws {
    // The FAA handbook's page 91 sets three bulleted effects of thin air, and two numbered steps
    // each of which wraps, so no two of the steps touch: the bullets list and the steps stay as
    // printed.
    let faa = try SourceLayoutFixture.load("faa-91")
    #expect(faa.sourceSHA256 == faaSHA256)
    let blocks = ListBuilder.build(reconstruct(faa.content()))
    #expect(listItems(blocks).map(\.text.text) == ["Power because the engine takes in less air",
                                                   "Thrust because a propeller is less efficient in thin air",
                                                   "Lift because the thin air exerts less force on the airfoils"])
    #expect(preformatted(blocks).filter { $0.hasPrefix("1. Setting") || $0.hasPrefix("2. Applying") }.count == 2)
    // Wallace's page 16 is an answer key: its entries read as values, not items.
    let key = try SourceLayoutFixture.load("algebra-16")
    #expect(key.sourceSHA256 == wallaceSHA256)
    let answers = ListBuilder.build(reconstruct(key.content()))
    #expect(listItems(answers).isEmpty)
    #expect(preformatted(answers).contains("1) 42"))
}

// MARK: - The writer

private func writtenBodies(_ blocks: [ReflowBlock], chapterStarts: Set<Int> = []) async throws -> [String] {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let book = ReflowDocument(metadata: .init(title: "Lists", language: "en"), blocks: blocks, assets: [],
                              chapterStartPages: chapterStarts)
    let url = try await EPUBWriter.write(book, maximumOutputBytes: 10_000_000, directory: dir, progress: { _ in })
    let archive = try Archive(url: url, accessMode: .read)
    return try archive.filter { $0.path.hasPrefix("EPUB/chapter-") }
        .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }.map { entry in
            var data = Data()
            _ = try archive.extract(entry) { data += $0 }
            let text = String(decoding: data, as: UTF8.self)
            return String(text[text.range(of: "<body>")!.upperBound..<text.range(of: "</body>")!.lowerBound])
        }
}

/// Every list element's children are items, in every spine document: nothing but `<li` opens a
/// list or follows an item's end.
private func listsHoldOnlyItems(_ body: String) -> Bool {
    var rest = Substring(body)
    while let open = rest.range(of: "<ul>") ?? rest.range(of: "<ol") {
        let inside = rest[open.upperBound...]
        guard let close = inside.range(of: "</ul>") ?? inside.range(of: "</ol>") else { return false }
        var list = inside[..<close.lowerBound]
        if list.hasPrefix(" start=\"") { list = list[list.index(after: list.firstIndex(of: ">")!)...] }
        guard list.hasPrefix("<li") else { return false }
        for gap in list.components(separatedBy: "</li>").dropFirst() where !gap.isEmpty && !gap.hasPrefix("<li") {
            return false
        }
        rest = inside[close.upperBound...]
    }
    return true
}

private func bullet(_ text: String, page: Int, opens: Bool = false) -> ReflowBlock {
    ReflowBlock(content: .listItem(.init(text: InlineText(text), marker: "•", kind: .unordered, opensList: opens)), page: page)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/292"))
func writerPacksEachListWholeAndPutsPageMarkersInsideItems() async throws {
    let blocks = built([
        marker(1), item("3. Third step of the procedure", page: 1), item("4. Fourth step of the procedure", page: 1),
        marker(2), item("5. Fifth step of the procedure", page: 2), paragraph("After the list.", page: 2),
        marker(3), item("• A detail", page: 3), item("• Another detail", page: 3), marker(4), paragraph("Last.", page: 4),
    ])
    let body = try #require(try await writtenBodies(blocks).first)
    #expect(body == EPUBTextEncoder.sourcePage(1)
        + "<ol start=\"3\"><li>Third step of the procedure</li><li>Fourth step of the procedure</li>"
        + "<li>\(EPUBTextEncoder.sourcePage(2))Fifth step of the procedure</li></ol>\n<p>After the list.</p>\n"
        + EPUBTextEncoder.sourcePage(3) + "<ul><li>A detail</li><li>Another detail</li></ul>\n"
        + EPUBTextEncoder.sourcePage(4) + "<p>Last.</p>\n", Comment(rawValue: body))
    #expect(listsHoldOnlyItems(body))
    // Negative control for the check itself: a marker between two items is caught.
    #expect(!listsHoldOnlyItems("<ul><li>a</li><span epub:type=\"pagebreak\" id=\"page-2\"/><li>b</li></ul>"))
    #expect(!listsHoldOnlyItems("<ol start=\"3\"><p>a</p></ol>"))
    // A list from 1 states no start; an item in right-to-left writing states its direction.
    let plain = try #require(try await writtenBodies(built([item("1. First"), item("2. Second")])).first)
    #expect(plain == "<ol><li>First</li><li>Second</li></ol>\n")
    let arabic = try #require(try await writtenBodies([bullet("الإقامة المتواصلة", page: 1, opens: true), bullet("second", page: 1)]).first)
    #expect(arabic.hasPrefix("<ul><li dir=\"rtl\">"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/292"))
func writerKeepsEmptyPagesInsideTheListAndClosesItAtAChapterStart() async throws {
    let blocks = [
        marker(1), bullet("First bulleted item", page: 1, opens: true), marker(2), marker(3),
        bullet("Second bulleted item", page: 3), marker(4), bullet("Third bulleted item", page: 4),
    ]
    let bodies = try await writtenBodies(blocks)
    #expect(bodies.count == 1)
    #expect(bodies[0] == EPUBTextEncoder.sourcePage(1) + "<ul><li>First bulleted item\(EPUBTextEncoder.sourcePage(2))</li>"
        + "<li>\(EPUBTextEncoder.sourcePage(3))Second bulleted item</li><li>\(EPUBTextEncoder.sourcePage(4))Third bulleted item</li></ul>\n", Comment(rawValue: bodies[0]))
    #expect(listsHoldOnlyItems(bodies[0]))
    // A chapter opening between two items closes the list in one document and opens it in the next.
    let split = try await writtenBodies(blocks, chapterStarts: [4])
    #expect(split.count == 2)
    #expect(split[0].hasSuffix("Second bulleted item</li></ul>\n"))
    #expect(split[1] == EPUBTextEncoder.sourcePage(4) + "<ul><li>Third bulleted item</li></ul>\n")
    for body in split { #expect(listsHoldOnlyItems(body)) }
    // A trailing marker after the last item travels with what follows the list, or stands last.
    let trailing = try await writtenBodies([bullet("one", page: 1, opens: true), bullet("two", page: 1), marker(2)])
    #expect(trailing == ["<ul><li>one</li><li>two</li></ul>\n" + EPUBTextEncoder.sourcePage(2)])
    // The page list names every page once, in order, wherever its marker was written.
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let book = ReflowDocument(metadata: .init(title: "Lists", language: "en"), blocks: blocks, assets: [])
    _ = try await EPUBWriter.write(book, maximumOutputBytes: 10_000_000, directory: dir, progress: { _ in })
    let nav = try String(contentsOf: dir.appendingPathComponent("EPUB/nav.xhtml"), encoding: .utf8)
    let entries = nav.components(separatedBy: "chapter-1.xhtml#page-").dropFirst().map { $0.prefix(1) }
    #expect(entries == ["1", "2", "3", "4"])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/292"))
func aListNeverStraddlesASpineDocumentBoundary() async throws {
    // A list that would cross the body target travels whole into the next document, and one that
    // is itself larger than the target occupies a document of its own, unsplit.
    // The filler leaves 42 bytes of the 60,000-byte target, and the list's markup is 63.
    let filler = paragraph(String(repeating: "x", count: 59_950))
    let list = [bullet("first item", page: 1, opens: true), bullet("second item", page: 1), bullet("third item", page: 1)]
    let bodies = try await writtenBodies([filler] + list + [paragraph("after")])
    try #require(bodies.count == 2)
    #expect(bodies[1] == "<ul><li>first item</li><li>second item</li><li>third item</li></ul>\n<p>after</p>\n")
    let long = (1...4_000).map { bullet("item number \($0) of a very long list", page: 1, opens: $0 == 1) }
    let oversized = try await writtenBodies([paragraph("before")] + long + [paragraph("after")])
    try #require(oversized.count == 3)
    #expect(oversized[1].hasPrefix("<ul><li>item number 1 of") && oversized[1].hasSuffix("</li></ul>\n"))
    #expect(oversized[1].components(separatedBy: "<li>").count - 1 == 4_000)
    #expect(oversized.allSatisfy(listsHoldOnlyItems))
}

private let faaSHA256 = "247929cace0ab56b376e683eba540cc4c8f39f199ab35414e8b604e24f395cb7"
private let wallaceSHA256 = "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678"
