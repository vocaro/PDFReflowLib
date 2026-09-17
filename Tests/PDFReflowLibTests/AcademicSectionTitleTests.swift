import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// An IEEEtran conference paper sets both of its heading levels at the body's own size (#162):
// section titles in small capitals centred in the column (`II. PROBLEM INPUT AND OUTPUT`,
// `APPENDIX A`, `REFERENCES`) and subsection titles in italic on the column's left edge
// (`A. Input data`). Neither reaches the heading-size threshold, `I.` and `V.` read as one-letter
// list markers, and a subsection title ran into its first paragraph. The same paper's references
// and algorithm steps hang their wrapped lines with no space between entries, so #147's opening
// rule could not join them either.
//
// Fixtures are native extraction from the checksum-pinned corpus document; the expected text was
// read from the rendered source pages.

private let dascSHA256 = "7c2137098ffb75153e0049b970272db97bc91e13168028dc7b53fbe2deb92caa"

private func sourcePage(_ page: Int) throws -> PageContent {
    let fixture = try SourceLayoutFixture.load("dasc-\(page)")
    #expect(fixture.sourceSHA256 == dascSHA256)
    return fixture.styledContent()
}

private func reflow(_ page: PageContent) -> [ReflowBlock] {
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: page.graphics.enumerated().map { ($0.element, "image-\($0.offset)") },
                                      vocabulary: LayoutReconstructor.vocabulary(in: [page]), warnings: &warnings)
}

private func headings(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case let .heading(_, text, _) = $0.content { text.text } else { nil } }
}

private func paragraphs(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case let .paragraph(text) = $0.content { text.text } else { nil } }
}

private func preformatted(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case let .preformatted(text) = $0.content { text.text } else { nil } }
}

@Test func sourceNumberedSectionTitlesAreHeadingsAtTheBodySize() throws {
    for (page, titles) in [(1, ["I. INTRODUCTION"]),
                           (2, ["II. PROBLEM INPUT AND OUTPUT", "III. SCHEDULING CONSTRAINTS"]),
                           (5, ["V. ALGORITHM FORMULATION"])] {
        let blocks = reflow(try sourcePage(page))
        for title in titles {
            #expect(headings(blocks).contains(title), "\(title)")
            // `I.` and `V.` are one-letter list markers, and `IV.` used to run into its paragraph.
            #expect(!preformatted(blocks).contains { $0.hasPrefix(title) }, "\(title)")
            #expect(!paragraphs(blocks).contains { $0.contains(title) }, "\(title)")
        }
    }
}

@Test func sourceTitlesSetOverTwoOrThreeLinesAreOneHeading() throws {
    // Page 7's title wraps into the small capitals' own size (7.97 points under its 9.96-point
    // line); page 9's appendices stack a same-size title under their number, and `ALGORITHM` under
    // that, again in small capitals only.
    #expect(headings(reflow(try sourcePage(7)))
        .contains("VII. COMPATIBILITY WITH A DISTRIBUTED SYSTEM FOR MANAGING ARRIVAL AIR TRAFFIC"))
    let appendices = headings(reflow(try sourcePage(9)))
    #expect(appendices.contains("APPENDIX A A HIGH-LEVEL DESCRIPTION OF THE SCHEDULING ALGORITHM"))
    #expect(appendices.contains("APPENDIX B QUADRATIC PROGRAM"))
    #expect(appendices.contains("VIII. SUMMARY"))
}

@Test func sourceUnnumberedReferencesHeadIsAHeadingOverSmallerEntries() throws {
    let blocks = reflow(try sourcePage(10))
    #expect(headings(blocks).contains("REFERENCES"))
    // The table's caption is centred over its own column and is no heading.
    #expect(!headings(blocks).contains { $0.contains("TABLE III") })
}

@Test func sourceItalicSubsectionTitlesStandApartFromTheirParagraph() throws {
    let second = reflow(try sourcePage(2))
    for title in ["A. Input data", "B. Output data: the format of a “schedule”"] {
        #expect(headings(second).contains(title), "\(title)")
    }
    #expect(paragraphs(second).contains {
        $0.hasPrefix("A schedule will be defined here as a mapping that, for each flight f, provides every node")
    })
    let fifth = reflow(try sourcePage(5))
    for title in ["A. The algorithm invariants", "B. The generic step: scheduling the next flight"] {
        #expect(headings(fifth).contains(title), "\(title)")
    }
    #expect(paragraphs(fifth).contains {
        $0.hasPrefix("Assume the first (f−1) flights have been scheduled; i.e., the schedules of the form (3)")
    })
}

@Test func sourceHangingEntriesKeepTheirWrappedLines() throws {
    let references = paragraphs(reflow(try sourcePage(10)))
    for entry in ["[3] A. Hagberg, P. Swart, and D. Schult. Exploring network structure, dynamics, and function using networkx. http://networkx.github.io, 2008.",
                  "[4] L. Meyn. A closed-form solution to multi-point scheduling problems. In AIAA Modeling and Simulation Technologies Conference, page 7911, 2010.",
                  // An entry whose first line is a list of initials rather than words, and whose
                  // last row PDFKit split at its word space (`NASA`, rejoined since #180).
                  "[7] J. L. Rios, I. S. Smith, P. Venkatesan, D. R. Smith, V. Baskaran, S. M. Jurcak, S. K. Iyer, and P. Verma. UTM UAS service supplier development: Sprint 2 toward technical capability level 4. NASA Technical Memorandum, 2018."] {
        #expect(references.contains(entry), "\(entry)")
    }
    let steps = paragraphs(reflow(try sourcePage(5)))
    #expect(steps.contains("Step 4. Use the algorithm in Ref. [4] to compute the available time windows for f at the nodes on its route (the region shown green in Ref. [4, Fig. 2(c)]), using:"))
}

// MARK: - Synthetic evidence

private func line(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat = 10,
                  style: TextStyle = []) -> TextLine {
    TextLine(content: InlineText(text, style: style), rect: CGRect(x: x, y: y, width: width, height: size * 0.9),
             fontSize: size, monospaced: false)
}

private func page(_ lines: [TextLine]) -> PageContent {
    PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines, graphics: [])
}

/// A justified column of prose from `top` downwards, one line every 12 points, indented one em on
/// each paragraph's first line, so the page carries a measure of its own.
private func column(_ texts: [String], top: CGFloat, x: CGFloat = 50, measure: CGFloat = 250) -> [TextLine] {
    texts.enumerated().map { offset, text in
        line(text, x: x, y: top - CGFloat(offset) * 12, width: measure)
    }
}

private func titles(_ lines: [TextLine], body: CGFloat = 10) -> [String] {
    let content = page(lines)
    return LayoutReconstructor.academicSectionTitles(in: lines, body: body, page: content).map(\.text)
}

private let prose = ["the stakeholders are left with no way to influence the schedule",
                     "assigned to each of their flights by the centralized system",
                     "and so a distributed system is proposed for the arrivals",
                     "of every flight that is routed through the arrival meter fix"]

@Test func centredTitlesNeedTheirPlaceInTheSectionSequence() throws {
    // A centred line of capitals over text on the column's edge, set off above.
    func spread(_ text: String, width: CGFloat, style: TextStyle = []) -> [TextLine] {
        column(prose, top: 700)
            + [line(text, x: 50 + (250 - width) / 2, y: 640, width: width, style: style)]
            + column(prose, top: 620)
    }
    #expect(titles(spread("II. PROBLEM INPUT AND OUTPUT", width: 140)) == ["II. PROBLEM INPUT AND OUTPUT"])
    #expect(titles(spread("REFERENCES", width: 56)) == ["REFERENCES"])
    #expect(titles(spread("APPENDIX A", width: 54)) == ["APPENDIX A"])
    // No numeral and no standard head: a caption block's centred line, not a section title.
    #expect(titles(spread("RELENTLESS, INC., ET AL., PETITIONERS", width: 180)).isEmpty)
    // A bare numeral with no period is a slip opinion's part label.
    #expect(titles(spread("III", width: 12)).isEmpty)
    // Small capitals are set in the text face; a bold label is `sectionLabels`' evidence.
    #expect(titles(spread("REFERENCES", width: 56, style: .bold)).isEmpty)
    // A line that fills the measure is justified prose, not a centred title.
    #expect(titles(spread("II. PROBLEM INPUT AND OUTPUT", width: 250)).isEmpty)
    // Lower case: the title is set from an uppercased string.
    #expect(titles(spread("II. Problem input and output", width: 140)).isEmpty)
}

@Test func aCentredTitleOverCentredTextIsATableTitleNotASection() throws {
    // FAA page 416 centres `NONDIRECTIONAL RADIO BEACON (NDB)` over `(Usable radius distances for
    // all altitudes)` and its table, not over the column's own text.
    let lines = column(prose, top: 700)
        + [line("REFERENCES", x: 147, y: 640, width: 56),
           line("(Usable radius distances for all altitudes)", x: 120, y: 628, width: 110)]
    #expect(titles(lines).isEmpty)
    // The same title over text on the column's edge is a section head.
    #expect(titles(column(prose, top: 700) + [line("REFERENCES", x: 147, y: 640, width: 56)]
                   + column(prose, top: 620)) == ["REFERENCES"])
}

@Test func italicSubsectionTitlesNeedTheirMarkerStyleAndSpacing() throws {
    // A column of prose, then the title set `gap` points clear of the line above and of the
    // paragraph beneath it, which opens on the column's one-em first-line indent.
    func subsection(_ text: String, style: TextStyle = .italic, gap: CGFloat = 16,
                    beneath: TextStyle = []) -> [TextLine] {
        let title = 664 - 9 - gap
        let opening = title - 9 - gap
        return column(prose, top: 700)
            + [line(text, x: 50, y: title, width: 60, style: style)]
            + [line(prose[0], x: 60, y: opening, width: 240, style: beneath)]
            + column(Array(prose.dropFirst()), top: opening - 12)
    }
    #expect(titles(subsection("A. Input data")) == ["A. Input data"])
    // Roman type is a lettered list item, and a bold one is `sectionLabels`' evidence.
    #expect(titles(subsection("A. Input data", style: [])).isEmpty)
    #expect(titles(subsection("A. Input data", style: .bold)).isEmpty)
    // Without the marker the line is an italic run-in lead-in.
    #expect(titles(subsection("Input data", style: .italic)).isEmpty)
    // Set at the column's leading it is an italic line of the paragraph, not a title.
    #expect(titles(subsection("A. Input data", gap: 2)).isEmpty)
    // More italic beneath is not the section's body text.
    #expect(titles(subsection("A. Input data", beneath: .italic)).isEmpty)
}

@Test func hangingRunsNeedTwoOpeningsAndAWrappedRun() throws {
    func entries(_ wrapped: [Int], top: CGFloat = 700) -> [TextLine] {
        var lines: [TextLine] = []
        var y = top
        for count in wrapped {
            lines.append(line("entry opening line that runs the whole measure of its column", x: 50, y: y, width: 250))
            y -= 12
            for _ in 0..<count {
                lines.append(line("wrapped line of that entry set into the hanging indent", x: 68, y: y, width: 232))
                y -= 12
            }
        }
        return lines
    }
    func run(_ lines: [TextLine]) -> Bool {
        LayoutReconstructor.hangingRun(in: lines, edge: 50, indent: 68, size: 10)
    }
    // Two entries open on the edge and one of them wraps twice.
    #expect(run(entries([2, 1])))
    #expect(run(entries([1, 2])))
    // One opening, or no run of two indented lines, is not a hanging list.
    #expect(!run(entries([2])))
    #expect(!run(entries([1, 1, 1])))
    // A first-line indent is the converse and never sets two lines at the indent in a row.
    var indented: [TextLine] = []
    for paragraph in 0..<3 {
        indented.append(line("an indented opening line of this paragraph on the column", x: 68, y: 700 - CGFloat(paragraph) * 36, width: 232))
        indented.append(line("wrapped line back on the column's own left edge, justified", x: 50, y: 688 - CGFloat(paragraph) * 36, width: 250))
        indented.append(line("another wrapped line back on the column's own left edge", x: 50, y: 676 - CGFloat(paragraph) * 36, width: 250))
    }
    #expect(!run(indented))
}
