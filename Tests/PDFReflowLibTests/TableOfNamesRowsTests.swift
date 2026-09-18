import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

// The 9/11 report's Table of Names after #161 (#199): a row PDFKit returns as one line where it
// returns the page's other rows as two ran into the next name (`John Ashcroft Attorney General,
// 2001– Monte Belger`, page 449), and a word the page breaks without printing a hyphen kept a space
// (`al Qaeda asso` over `ciate`, page 453).

private func reflow(_ page: PageContent, vocabulary: Set<String> = []) -> [ReflowBlock] {
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: [], vocabulary: vocabulary, warnings: &warnings)
}

private func paragraphs(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case let .paragraph(text) = $0.content { text.text } else { nil } }
}

/// A two-column list as the Table of Names sets it: names at x 45 and descriptions at x 153, each
/// its own show and the names drawn before the descriptions, so PDFKit reads the rows apart;
/// `merged` rows follow, each one show whose TJ adjustment carries the description to x 153, so
/// PDFKit returns the row as one line. Times-Roman at 10 points.
private func namesPDF(apart: Int = 10, merged: [(name: String, description: String)] = [("Janet Reno", "Attorney General")],
                      extra: String = "") -> Data {
    let names = ["Colin Powell", "Ronald Reagan", "Condoleezza Rice", "Bill Richardson", "Thomas Ridge", "Bruce Riedel",
                 "Christina Rocca", "Michael Rolince", "Donald Rumsfeld", "Peter Schoomaker"]
    let descriptions = ["Secretary of State", "President of the United States", "National Security Advisor",
                        "Ambassador to the United Nations", "Secretary of Homeland Security", "Senior Director",
                        "Assistant Secretary of State", "FBI Section Chief", "Secretary of Defense", "Commander"]
    // The names, then the descriptions: shows in column order.
    var content = ""
    for index in 0..<apart { content += "BT /F1 10 Tf 45 \(700 - index * 12) Td (\(names[index])) Tj ET\n" }
    for index in 0..<apart { content += "BT /F1 10 Tf 153 \(700 - index * 12) Td (\(descriptions[index])) Tj ET\n" }
    var y = 700 - apart * 12
    for row in merged {
        // The name's advance, from the font's widths, then an adjustment to x 153.
        let width = pdfKitGated {
            let font = CTFontCreateWithName("Times-Roman" as CFString, 10, nil)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: row.name,
                attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
            return CTLineGetTypographicBounds(line, nil, nil, nil)
        }
        let pad = Int(((153 - 45) - width) / 10 * 1000)
        content += "BT /F1 10 Tf 45 \(y) Td [(\(row.name)) -\(pad) (\(row.description))] TJ ET\n"
        y -= 12
    }
    content += extra
    return testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
        testPDFStream(content),
        "<< /Type /Font /Subtype /Type1 /BaseFont /Times-Roman /Encoding /WinAnsiEncoding >>",
    ])
}

private func extracted(_ data: Data, native: Bool = true) throws -> [TextLine] {
    let page = try #require(PDFDocument(data: data)?.page(at: 0))
    let paints = GraphicsReader.read(try #require(page.pageRef)).paints.map(\.rect)
    return try NativeTextReader.lines(on: page, limit: 100_000, borderlessTableInk: native ? paints : nil)
}

@Test func aRowPDFKitMergesWhereItReadsTheOthersApartIsCutAtTheirEdge() throws {
    // Reproducer: PDFKit returns the merged row as one line; a page read as invisible text over a
    // scan (no ink passed) keeps it so.
    let unsplit = try extracted(namesPDF(), native: false)
    #expect(unsplit.contains { $0.text == "Janet Reno Attorney General" }, "\(unsplit.map(\.text))")
    let lines = try extracted(namesPDF())
    let name = try #require(lines.first { $0.text == "Janet Reno" }, "\(lines.map(\.text))")
    let description = try #require(lines.first { $0.text == "Attorney General" })
    #expect(abs(name.rect.minX - 45) <= 1 && abs(description.rect.minX - 153) <= 1)
    #expect(abs(name.rect.minY - description.rect.minY) <= 0.5)
    #expect(lines.contains { $0.text == "Colin Powell" } && lines.contains { $0.text == "Secretary of State" })
    // Controls: an edge only three rows share, a page number ending a contents entry, and a row
    // PDFKit merges beside as many rows it merges as it reads apart stay whole.
    #expect(try extracted(namesPDF(apart: 3)).contains { $0.text == "Janet Reno Attorney General" })
    #expect(try extracted(namesPDF(merged: [("Janet Reno", "433")])).contains { $0.text == "Janet Reno 433" })
    let many = [("Janet Reno", "Attorney General"), ("Anthony Zinni", "Commander"), ("Paul Wolfowitz", "Deputy Secretary"),
                ("Dale Watson", "Executive Assistant"), ("Larry Thompson", "Deputy Attorney")]
    let crowded = try extracted(namesPDF(apart: 4, merged: many)).map(\.text)
    #expect(crowded.contains("Janet Reno Attorney General") && crowded.contains("Larry Thompson Deputy Attorney"), "\(crowded)")
}

@Test func aProseLineCrossingARowEdgeKeepsItsWordSpaces() throws {
    // Prose under the list crosses the descriptions' edge with word spaces only.
    let prose = "BT /F1 10 Tf 45 560 Td (The names below are listed alphabetically, together with their offices.) Tj ET\n"
    let texts = try extracted(namesPDF(extra: prose)).map(\.text)
    #expect(texts.contains("The names below are listed alphabetically, together with their offices."), "\(texts)")
    #expect(texts.contains("Janet Reno"))
}

private func line(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat = 9) -> TextLine {
    TextLine(text: text, rect: CGRect(x: x, y: y, width: width, height: size), fontSize: size)
}

@Test func rowEdgesPairEachLineWithTheNearestLineBeforeIt() {
    // The Table of Names' rows: names at 44.7, descriptions at 152.7.
    let names = (0..<5).flatMap { index -> [TextLine] in
        [line("Name \(index)", x: 44.7, y: 500 - CGFloat(index) * 11, width: 60, size: 10.25),
         line("Description \(index)", x: 152.7, y: 500 - CGFloat(index) * 11, width: 150, size: 10.25)]
    }
    #expect(NativeTextReader.rowEdges(names) == [NativeTextReader.RowEdge(left: 44.7, x: 152.7, size: 10.25, rows: 5)])
    // Two timelines side by side (9/11 page 51): the right one's events stand beside the left
    // one's lines, and only two of its times stand apart from their events, so no edge.
    var timelines: [TextLine] = []
    for index in 0..<6 {
        let y = 367 - CGFloat(index) * 10
        timelines.append(line("8:5\(index) Event on the left", x: 44.7, y: y, width: 120))
        if index < 2 {
            timelines.append(line("9:3\(index)", x: 206.7, y: y, width: 16))
            timelines.append(line("Event on the right", x: 245.7, y: y, width: 90))
        } else {
            timelines.append(line("continued event", x: 245.7, y: y, width: 90))
        }
    }
    #expect(NativeTextReader.rowEdges(timelines).allSatisfy { abs($0.left - 206.7) > 1 })
    // Lines a word space apart, or in another size, pair with nothing.
    let close = (0..<5).flatMap { index -> [TextLine] in
        [line("Name", x: 44.7, y: 500 - CGFloat(index) * 11, width: 30),
         line("next", x: 80, y: 500 - CGFloat(index) * 11, width: 30)]
    }
    #expect(NativeTextReader.rowEdges(close).isEmpty)
    let sizes = (0..<5).flatMap { index -> [TextLine] in
        [line("Name", x: 44.7, y: 500 - CGFloat(index) * 11, width: 30, size: 14),
         line("Description", x: 152.7, y: 500 - CGFloat(index) * 11, width: 80)]
    }
    #expect(NativeTextReader.rowEdges(sizes).isEmpty)
}

@Test func source911TableOfNamesRowsPDFKitMergedReadAsNameAndDescription() throws {
    let page449 = paragraphs(reflow(try SourceLayoutFixture.load("911-449").styledContent()))
    for entry in ["John Ashcroft", "Attorney General, 2001–", "Monte Belger",
                  "Acting Deputy Administrator, Federal Aviation Administration 1997–2002",
                  // Rows PDFKit read apart, as before.
                  "Madeleine Albright", "Secretary of State, 1997–2001"] {
        #expect(page449.contains(entry), "\(entry)")
    }
    let page451 = paragraphs(reflow(try SourceLayoutFixture.load("911-451").styledContent()))
    for entry in ["Janet Reno", "Attorney General, 1993–2001", "Condoleezza Rice", "Mohammed Farrah Aidid"] {
        #expect(page451.contains(entry), "\(entry)")
    }
}

@Test func aWordBrokenWithoutAPrintedHyphenClosesOnTheBooksWordAndTheLexicon() throws {
    let english: Set<String> = [LayoutReconstructor.englishLexiconKey, "associate", "reality", "ongoing"]
    func pair(_ last: String, _ next: String, size: CGFloat = 10.25) -> (TextLine, TextLine) {
        (line(last, x: 152.7, y: 166.6, width: 195, size: 10.25), line(next, x: 164.7, y: 155.3, width: 120, size: size))
    }
    let (asso, ciate) = pair("(a.k.a. Abu Zubaydah) Palestinian; al Qaeda asso", "ciate; currently in U.S. custody")
    #expect(LayoutReconstructor.unprintedLineEndHyphen(asso, ciate, vocabulary: english))
    // Controls: a document not declared English, a joined word the book never prints, halves that
    // are words (`real` + `ity` has one), another size, a capital, and punctuation at the break.
    #expect(!LayoutReconstructor.unprintedLineEndHyphen(asso, ciate, vocabulary: ["associate"]))
    #expect(!LayoutReconstructor.unprintedLineEndHyphen(asso, ciate, vocabulary: [LayoutReconstructor.englishLexiconKey]))
    let (real, ity) = pair("did not become a real", "ity until June 20, 1782.")
    #expect(!LayoutReconstructor.unprintedLineEndHyphen(real, ity, vocabulary: english))
    let (on, going) = pair("the work is on", "going this year")
    #expect(!LayoutReconstructor.unprintedLineEndHyphen(on, going, vocabulary: english))
    let smaller = pair("(a.k.a. Abu Zubaydah) Palestinian; al Qaeda asso", "ciate; currently in U.S. custody", size: 8)
    #expect(!LayoutReconstructor.unprintedLineEndHyphen(smaller.0, smaller.1, vocabulary: english))
    let (_, capital) = pair("", "Ciate; currently")
    #expect(!LayoutReconstructor.unprintedLineEndHyphen(asso, capital, vocabulary: english))
    let (comma, _) = pair("al Qaeda asso,", "")
    #expect(!LayoutReconstructor.unprintedLineEndHyphen(comma, ciate, vocabulary: english))

    // Page 453 as the pipeline reads it: the book's own `associate`, from this page's `Hamburg
    // cell associate`, closes the break; without the lexicon key the space stays.
    let content = try SourceLayoutFixture.load("911-453").styledContent()
    var vocabulary = LayoutReconstructor.vocabulary(in: [content])
    let plain = paragraphs(reflow(content, vocabulary: vocabulary))
    #expect(plain.contains("(a.k.a. Abu Zubaydah) Palestinian; al Qaeda asso ciate; currently in U.S. custody"), "\(plain)")
    vocabulary.insert(LayoutReconstructor.englishLexiconKey)
    let joined = paragraphs(reflow(content, vocabulary: vocabulary))
    #expect(joined.contains("(a.k.a. Abu Zubaydah) Palestinian; al Qaeda associate; currently in U.S. custody"), "\(joined)")
    #expect(joined.contains("Moroccan; Hamburg cell associate"))
}
