import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// The 9/11 report's hearings appendix (#134) lists each panel's witnesses one to an entry, flush
// left, and wraps an entry (or a two-line panel title) one em into a hanging indent. Each panel's
// witnesses ran together as one paragraph, and a title wrapped into the indent, or set over entries
// narrower than itself, stayed fused into that paragraph.

private func reflow(_ page: PageContent, labelStyles: Set<LayoutReconstructor.LabelStyle> = []) -> [ReflowBlock] {
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings, labelStyles: labelStyles)
}

private func headings(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case let .heading(_, text, _) = $0.content { text.text } else { nil } }
}

private func paragraphs(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case let .paragraph(text) = $0.content { text.text } else { nil } }
}

/// The appendix's label style, as the book's page evidence establishes it (three pages).
private func appendixStyles() throws -> Set<LayoutReconstructor.LabelStyle> {
    var counts: [LayoutReconstructor.LabelStyle: Int] = [:]
    for name in ["911-458", "911-460", "911-462"] {
        for style in LayoutReconstructor.labelEvidence(on: try SourceLayoutFixture.load(name).styledContent()) {
            counts[style, default: 0] += 1
        }
    }
    return LayoutReconstructor.labelStyles(from: counts)
}

private func line(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat = 9, bold: Bool = false) -> TextLine {
    TextLine(content: InlineText(text, style: bold ? .bold : []), rect: CGRect(x: x, y: y, width: width, height: size * 0.9),
             fontSize: size, monospaced: false)
}

private func page(_ lines: [TextLine]) -> PageContent {
    PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines, graphics: [])
}

@Test func source911HearingPanelsHeadTheirWitnessesOneToAnEntry() throws {
    let blocks = reflow(try SourceLayoutFixture.load("911-458").styledContent(), labelStyles: try appendixStyles())
    for title in ["Borders, Money, and Transportation Security", "Law Enforcement, Domestic Intelligence, and Homeland Security",
                  "Intelligence Oversight and the Joint Inquiry", "State of the System: Civil Aviation Security on September 11"] {
        #expect(headings(blocks).contains(title), "\(title)")
    }
    let entries = paragraphs(blocks)
    for witness in ["Glenn Fine, Inspector General, U.S. Department of Justice", "Michael Wermuth, RAND Corporation",
                    "Ken Holden, Commissioner, New York City Department of Design and Construction",
                    "Senator John McCain (R-Az.)", "Senator Joseph Lieberman (D-Conn.)", "Senator Bob Graham (D-Fla.)",
                    "James May, Air Transport Association of America"] {
        #expect(entries.contains(witness), "\(witness)")
    }
    // No title text is left in a paragraph.
    #expect(!entries.contains { $0.contains("Homeland Security Michael") || $0.contains("Inquiry Senator") })
}

@Test func source911EntryContinuedFromThePreviousPageEndsBeforeTheNextEntry() throws {
    let blocks = reflow(try SourceLayoutFixture.load("911-462").styledContent(), labelStyles: try appendixStyles())
    let entries = paragraphs(blocks)
    // The fixture keeps the running head (furniture removal runs across pages), and replays bold
    // only on lines whose PDFKit text needed no word-space repair, so `Aviation Security on
    // 9/11:The Airlines` stays plain here; the corpus contract checks it as a heading.
    #expect(entries.prefix(3) == ["444 APPENDIX",
                                  "Management Department, Terrorist Threat Integration Center, Central Intelligence Agency",
                                  "Donna A. Bucella, Director, Terrorist Screening Center, Federal Bureau of Investigation"])
    #expect(entries.contains("Edmond L. Soliday, former Vice President of Safety, Quality Assurance, and Security, United Airlines"))
    #expect(headings(blocks).contains("The Response to September 11 on the Borders"))
}

@Test func hangingEdgesNeedAWrappedEntryAndNoIndentedParagraphOpening() {
    let entry = [line("Ken Holden, Commissioner, New York City Department of", x: 40, y: 500, width: 213),
                 line("Design and Construction", x: 49, y: 489, width: 90)]
    #expect(LayoutReconstructor.hangingEntryEdges(entry).map(\.x) == [40])
    #expect(LayoutReconstructor.hangingEntryEdges(entry, body: 9).map(\.x) == [40])
    // Lines larger than the body (a section title hung under its number) are no evidence.
    #expect(LayoutReconstructor.hangingEntryEdges(entry, body: 7.5).isEmpty)
    // A first-line indent under a sentence's end (or a colon) is a paragraph opening, and one on the
    // edge disqualifies it.
    let opening = [line("the end of a justified paragraph running to the measure.", x: 40, y: 460, width: 276),
                   line("The next paragraph opens on a first-line indent here", x: 49, y: 449, width: 267)]
    #expect(LayoutReconstructor.hangingEntryEdges(opening).isEmpty)
    #expect(LayoutReconstructor.hangingEntryEdges(entry + opening).isEmpty)
    #expect(LayoutReconstructor.hangingEntryEdges([line("as the witness said:", x: 40, y: 460, width: 213),
                                                   line("Quoted text", x: 49, y: 449, width: 204)]).isEmpty)
    // No evidence: a rule over an indented note, index sub-entries, a centred second line, a
    // step beyond 2.5 ems, a list marker.
    #expect(LayoutReconstructor.hangingEntryEdges([line("——————", x: 40, y: 500, width: 54),
                                                   line("*Together with No. 22–1219", x: 49, y: 489, width: 204)]).isEmpty)
    #expect(LayoutReconstructor.hangingEntryEdges([line("Vestibular illusions", x: 40, y: 500, width: 78),
                                                   line("Coriolis illusion..........17-7", x: 49, y: 489, width: 204)]).isEmpty)
    #expect(LayoutReconstructor.hangingEntryEdges([line("A centred display title set over", x: 40, y: 500, width: 213),
                                                   line("a second centred line", x: 52, y: 489, width: 189)]).isEmpty)
    #expect(LayoutReconstructor.hangingEntryEdges([line("Ken Holden, Commissioner, New York City Department of", x: 40, y: 500, width: 213),
                                                   line("Design and Construction", x: 70, y: 489, width: 90)]).isEmpty)
    #expect(LayoutReconstructor.hangingEntryEdges([line("• Ken Holden, Commissioner, New York City Department of", x: 40, y: 500, width: 213),
                                                   line("Design and Construction", x: 49, y: 489, width: 90)]).isEmpty)
}

@Test func entriesSplitOnlyOnAHangingEdgeAndNeverInsideJustifiedOrIndentedProse() {
    let wrapped = [line("Ken Holden, Commissioner, New York City Department of", x: 40, y: 500, width: 213),
                   line("Design and Construction", x: 49, y: 489, width: 90)]
    let entries = [line("Senator John McCain (R-Az.)", x: 40, y: 478, width: 108),
                   line("Senator Joseph Lieberman (D-Conn.)", x: 40, y: 467, width: 135),
                   line("Gerald Dillingham, Director, Civil Aviation Issues, General Accounting Office", x: 40, y: 456, width: 276)]
    #expect(paragraphs(reflow(page(wrapped + entries))) == [
        "Ken Holden, Commissioner, New York City Department of Design and Construction",
        "Senator John McCain (R-Az.)", "Senator Joseph Lieberman (D-Conn.)",
        "Gerald Dillingham, Director, Civil Aviation Issues, General Accounting Office"])
    // Negative control: the same entries with no wrapped entry on the page run together, as before.
    #expect(paragraphs(reflow(page(entries))).count == 1)
    // Lines that fill the measure, a lowercase opening and a line-end hyphen continue their paragraph.
    let prose = [line("A justified line of prose that runs all the way to the measure", x: 40, y: 478, width: 276),
                 line("Continues on the next line of the same paragraph to the measure", x: 40, y: 467, width: 276),
                 line("Short line that ends early", x: 40, y: 456, width: 100),
                 line("and then continues in lowercase with a hyphen-", x: 40, y: 445, width: 180),
                 line("Ated word", x: 40, y: 434, width: 40)]
    #expect(paragraphs(reflow(page(wrapped + prose))).count == 2)
    // A paragraph's indented first line is no entry's continuation: the flush line after it continues it.
    let indented = [line("An indented first line of a paragraph beside the entries", x: 49, y: 460, width: 267),
                    line("Its second line on the edge", x: 40, y: 449, width: 120)]
    #expect(paragraphs(reflow(page(wrapped + indented))) == [
        "Ken Holden, Commissioner, New York City Department of Design and Construction",
        "An indented first line of a paragraph beside the entries Its second line on the edge"])
}

@Test func hangingTitlesNeedTheirPagesHangingEdge() {
    let styles: Set<LayoutReconstructor.LabelStyle> = [LayoutReconstructor.LabelStyle(
        line("Title", x: 40, y: 0, width: 20, bold: true), body: 9)]
    let title = [line("Law Enforcement, Domestic Intelligence, and", x: 40, y: 530, width: 184, bold: true),
                 line("Homeland Security", x: 49, y: 519, width: 79, bold: true)]
    let witnesses = [line("Michael Wermuth, RAND Corporation", x: 40, y: 508, width: 143),
                     line("Zoë Baird, Markle Foundation", x: 40, y: 497, width: 109)]
    let wrapped = [line("Ken Holden, Commissioner, New York City Department of", x: 40, y: 486, width: 213),
                   line("Design and Construction", x: 49, y: 475, width: 90),
                   line("Gerald Dillingham, Director, Civil Aviation Issues, General Accounting Office", x: 40, y: 464, width: 276)]
    let blocks = reflow(page(title + witnesses + wrapped), labelStyles: styles)
    #expect(headings(blocks) == ["Law Enforcement, Domestic Intelligence, and Homeland Security"])
    #expect(paragraphs(blocks).prefix(2) == ["Michael Wermuth, RAND Corporation", "Zoë Baird, Markle Foundation"])
    // A single-line title over narrower entries.
    let single = [line("Intelligence Oversight and the Joint Inquiry", x: 40, y: 530, width: 176, bold: true),
                  line("Senator Bob Graham (D-Fla.)", x: 40, y: 519, width: 107)]
    #expect(headings(reflow(page(single + wrapped), labelStyles: styles)) == ["Intelligence Oversight and the Joint Inquiry"])
    // Negative controls: without a wrapped entry on the page neither title is read, as before.
    #expect(headings(reflow(page(title + witnesses), labelStyles: styles)).isEmpty)
    #expect(headings(reflow(page(single + [line("Senator Richard Shelby (R-Ala.)", x: 40, y: 508, width: 117)]), labelStyles: styles)).isEmpty)
}
