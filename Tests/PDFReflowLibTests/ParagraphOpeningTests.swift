import Foundation
import Testing
@testable import PDFReflowLib

/// #147: a paragraph's opening line set further from the column's edge than the lines it wraps onto
/// (Our Flag's two-em first-line indent, the lines set beside a drop cap, a hanging-indent entry's
/// wrapped lines) continues into them; table rows and unevidenced openings do not.
private func nativePage(_ name: String) throws -> PageContent {
    let fixture = try SourceLayoutFixture.load(name)
    var page = fixture.content()
    for index in page.lines.indices {
        let line = page.lines[index]
        if let source = fixture.attributedLines.first(where: { $0.text == line.text }) {
            var native = NativeTextReader.textLine(semantic: line.text, bounds: line.rect,
                attributed: source.attributedString())
            native.structure = line.structure
            page.lines[index] = native
        }
    }
    LayoutReconstructor.joinDropCapInitials(&page, vocabulary: [])
    return page
}

private func paragraphs(_ page: PageContent) -> [String] {
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings).compactMap { block in
        guard case let .paragraph(text) = block.content else { return nil }
        return text.text
    }
}

private func expectJoined(_ texts: [String], _ first: String, _ second: String, _ comment: Comment) {
    #expect(texts.contains { $0.contains(first) && $0.contains(second) }, comment)
}

private func expectSeparate(_ texts: [String], _ first: String, _ second: String, _ comment: Comment) {
    #expect(texts.contains { $0.contains(first) } && texts.contains { $0.contains(second) }
        && !texts.contains { $0.contains(first) && $0.contains(second) }, comment)
}

@Test func flagIndentedOpeningLinesRunOntoTheirParagraphs() throws {
    // Untagged, two ems in: `…of New Jersey, a` / `signer of the Declaration…` (page 7).
    let seven = paragraphs(try nativePage("flag-7"))
    expectJoined(seven, "Francis Hopkinson of New Jersey, a", "signer of the Declaration", "page 7 indent")
    expectSeparate(seven, "while others had eight.", "Strong evidence indicates", "page 7 paragraph break")
    // Beside the drop cap and back at the edge below it (pages 5, 7, 10).
    expectJoined(seven, "The Stars and Stripes originated", "The resolution read:", "page 7 drop cap")
    let five = paragraphs(try nativePage("our-flag-page-5"))
    expectJoined(five, "During the night of September 13, 1814", "attack from the deck of a British", "page 5 drop cap")
    expectSeparate(five, "where he completed the poem.", "Years later, Key told", "page 5 paragraph break")
    let ten = paragraphs(try nativePage("our-flag-page-10"))
    expectJoined(ten, "admitted to the Union (Kentucky", "flag was the official flag of our country", "page 10 drop cap")
    // A drop cap whose second line PDFKit lists before it, and an untagged indented opening after
    // space (page 49).
    let fortyNine = paragraphs(try nativePage("our-flag-page-49"))
    expectJoined(fortyNine, "Fort McHenry is located in Baltimore, Maryland. This low", "citadel overlooks", "page 49 drop cap")
    expectJoined(fortyNine, "for nearly a century after", "the battle but changing technology", "page 49 indent")
}

@Test func flagQuotationGroupsTaggedPerLineJoinFromTheirIndentedOpening() throws {
    let texts = paragraphs(try nativePage("our-flag-page-12"))
    // Tagged group to tagged group, and tagged group to an untagged line.
    expectJoined(texts, "sees not the", "flag, but the nation itself.", "Beecher, group to group")
    expectJoined(texts, "bright morning stars of God,", "and the stripes upon it were beams", "Beecher, group to untagged line")
    expectJoined(texts, "under which we serve, is the", "emblem of our unity", "Wilson")
    // Each quotation still opens its own paragraph.
    expectSeparate(texts, "rejoiced in it.", "The stars upon it were like", "quotation break")
    expectSeparate(texts, "The writer Henry Ward Beecher said:", "A thoughtful mind", "introduction break")
}

@Test func flagReadingListHangingLinesJoinTheirSpacedEntries() throws {
    let texts = paragraphs(try nativePage("our-flag-page-54"))
    expectJoined(texts, "Phoenix, AZ: Continuing Education", "Institute, 1971.", "Manning")
    expectJoined(texts, "Art and as History, from", "the Birth of the Republic", "Mastai")
    expectJoined(texts, "Chicago: Childrens Press,", "1965.", "Miller")
    expectSeparate(texts, "Institute, 1971.", "Mastai, Bolesaw.", "entries stay apart")
    expectSeparate(texts, "(Landmark Books; 26), 1952.", "Miller, Natalie.", "entries stay apart")
}

@Test func tableStubsAndHeaderRowsAreNoOpenings() throws {
    // Blue Book page 142's scanned stub column: `Evaluation` over labels that end together.
    let stub = paragraphs(try nativePage("blue-142"))
    #expect(stub.contains { $0.hasPrefix("Evaluation") })
    #expect(!stub.contains { $0.contains("Evaluation") && $0.contains("Balloon") })
    // Page 70's table header row over the first data row.
    let rows = paragraphs(try nativePage("blue-70"))
    #expect(rows.contains { $0.contains("Identification 1 2 3 4 5 6 7") })
    #expect(!rows.contains { $0.contains("Identification") && $0.contains("Balloon 156") })
    // A stub whose heading reads as words but spans no prose measure (under twelve bodies).
    let stubPage = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 432, height: 648), lines: [
        line("Kinds of flags flown", x: 82, y: 330, right: 150),
        line("Garrison flags", x: 64, y: 318, right: 150),
        line("Storm flags aloft", x: 64, y: 306, right: 150),
        line("Burial flags held", x: 64, y: 294, right: 150),
    ], graphics: [])
    expectSeparate(paragraphs(stubPage), "Kinds of flags flown", "Garrison flags", "narrow stub")
}

// Synthetic controls on a 9-point justified column from x 64 to 369 at 12-point leading.
private func line(_ text: String, x: CGFloat, y: CGFloat, right: CGFloat = 369) -> TextLine {
    TextLine(text: text, rect: CGRect(x: x, y: y, width: right - x, height: 8.9), fontSize: 9)
}

private let filler = [
    line("The column sets these lines to the full measure of the page.", x: 64, y: 140),
    line("Three lines on the edge establish the justified right edge,", x: 64, y: 128),
    line("which an opening line and its wrapped lines both reach here.", x: 64, y: 116),
]

private func page(_ lines: [TextLine]) -> PageContent {
    PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 432, height: 648), lines: lines + filler, graphics: [])
}

@Test func indentedOpeningNeedsItsOwnEvidence() throws {
    let opening = line("Strong evidence indicates that Francis Hopkinson of New Jersey, a", x: 82, y: 330)
    let wrapped = line("signer of the Declaration of Independence, was responsible for the", x: 64, y: 318)
    let above = line("Some stars had six points while others had eight.", x: 64, y: 342, right: 266)
    expectJoined(paragraphs(page([above, opening, wrapped])), "New Jersey, a", "signer of", "short line above")
    // A full line above that runs on without ending a sentence: the indented line may be that
    // paragraph's hanging line, so the text beneath it is not joined to it.
    let runOn = line("an entry whose first line fills the measure and runs straight on", x: 64, y: 342)
    expectSeparate(paragraphs(page([runOn, opening, wrapped])), "New Jersey, a", "signer of", "unevidenced opening")
    // Indented by more than three bodies.
    let deep = line("Strong evidence indicates that Francis Hopkinson of New Jersey, a", x: 100, y: 330)
    expectSeparate(paragraphs(page([above, deep, wrapped])), "New Jersey, a", "signer of", "deep indent")
    // An opening that stops short of the measure.
    let short = line("Strong evidence indicates that Francis Hopkinson of", x: 82, y: 330, right: 300)
    expectSeparate(paragraphs(page([above, short, wrapped])), "Hopkinson of", "signer of", "short opening")
    // An opening in lowercase.
    let lower = line("strong evidence indicates that Francis Hopkinson of New Jersey, a", x: 82, y: 330)
    expectSeparate(paragraphs(page([above, lower, wrapped])), "New Jersey, a", "signer of", "lowercase opening")
}

@Test func hangingLineNeedsSpaceAboveItsEntry() throws {
    let entry = line("Manning, John R. The Story of Old Glory. Phoenix, AZ: Continuing Education", x: 64, y: 300)
    let hanging = line("Institute, 1971.", x: 82, y: 288, right: 140)
    let spaced = line("Capitol Hill. Washington: Library of Congress, 1977.", x: 82, y: 316, right: 260)
    expectJoined(paragraphs(page([spaced, entry, hanging])), "Continuing Education", "Institute, 1971.", "spaced entry")
    // The same entry at ordinary leading under the text above has no space setting it apart.
    let tight = line("Capitol Hill. Washington: Library of Congress, 1977.", x: 82, y: 312, right: 260)
    expectSeparate(paragraphs(page([tight, entry, hanging])), "Continuing Education", "Institute, 1971.", "unspaced entry")
}
