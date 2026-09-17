import CoreGraphics
import Foundation
import Testing
#if os(macOS)
import AppKit
private typealias TestFont = NSFont
#else
import UIKit
private typealias TestFont = UIFont
#endif
@testable import PDFReflowLib

// #180. Two leftovers of the IEEEtran paper (`ntrs-20190030725-dasc-2019`).
//
// 1. PDFKit measures a line from its first run, so TeX's 7-point `\labelitemi` makes a 9.96-point
//    itemize entry read as 6.97 and `continuesListItem` refuses the 9.96-point lines that wrap
//    under it. Extraction now reads such a line at the size of its own text
//    (`NativeTextReader.bulletItemBodySize`), beside the drop-cap and display-numeral rules.
// 2. PDFKit splits references [1] and [7] at a word space it stretched to justify the line, and
//    the detached piece opened a paragraph of its own. #148's prose-row tier cannot read those
//    junctions: they are 1.6 and 1.3 ems wide, and a reference's fields end in a period. The
//    space PDFKit kept at the left piece's end reads them (`TextLine.trailingSpace`).
//
// Fixtures are native extraction from the checksum-pinned document, captured before either rule;
// every expected phrase was read against the rendered source page.

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

private func preformatted(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case let .preformatted(text) = $0.content { text.text } else { nil } }
}

private func paragraphs(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case let .paragraph(text) = $0.content { text.text } else { nil } }
}

private func attributed(_ runs: [(String, String, CGFloat)]) -> NSAttributedString {
    let value = NSMutableAttributedString(string: "")
    for (text, name, size) in runs {
        var attributes: [NSAttributedString.Key: Any] = [:]
        attributes[.font] = TestFont(name: name, size: size)
        value.append(NSAttributedString(string: text, attributes: attributes))
    }
    return value
}

// MARK: - A bullet drawn smaller than its item

// Pages 5 sets four `\itemize` entries whose bullet is 6.97 points over 9.96-point text. The
// fixture records the line at the bullet's size — the defect — and extraction now reads the
// item's own size, so each entry keeps the lines that wrap under it.
@Test func sourceItemizeBulletsKeepTheirWrappedLines() throws {
    let fixture = try SourceLayoutFixture.load("dasc-5")
    let captured = try #require(fixture.lines.first { $0.text.hasPrefix("• Controllability") })
    #expect(abs(captured.fontSize - 6.97) < 0.05, "the captured line carries the bullet's size")
    let page = try sourcePage(5)
    for opening in ["• Controllability", "• Reachability", "• the totality", "• the travel time"] {
        let line = try #require(page.lines.first { $0.text.hasPrefix(opening) })
        #expect(abs(line.fontSize - 9.9626) < 0.05, "\(opening) reads at the item's size")
    }
    let items = preformatted(reflow(page))
    for item in ["• Controllability: By leaving node k at time Tk, flight f cannot reach node k+ 1 at any available time.",
                 "• the totality of the intervals (7), (8), (9) as the unavailable time windows (shown red in Ref. [4, Fig. 2]),",
                 "• the travel time bounds specified in (5.a) as the travel times (e.g., Ref. [4, Equations (5), (6), (7)])."] {
        #expect(items.contains(item), "\(item)")
    }
    #expect(items.contains { $0.hasPrefix("• Reachability: There is no time instant Tk−1 available to flight f at k−1 from which") })
    // Controls: no wrapped line is left standing on its own, and the paragraph over the entries
    // and the section title under them are untouched.
    for stranded in ["cannot reach node k+ 1 at any available time.", "unavailable time windows (shown red in Ref. [4, Fig. 2]),"] {
        #expect(!preformatted(reflow(page)).contains(stranded))
        #expect(!paragraphs(reflow(page)).contains(stranded))
    }
    #expect(paragraphs(reflow(page)).contains("for two other possible reasons:"))
}

// Page 6 nests dash items under its bullets. Once the bullets read at their own size, the first
// of those dash lines stands within the width a marker occupies and at ordinary leading, so it
// would wrap into the bullet; the dashes the page repeats on that edge say it opens an item.
@Test func sourceNestedDashItemsStayApartFromTheirBullet() throws {
    let page = try sourcePage(6)
    let blocks = reflow(page)
    for label in ["• Units of measurement:", "• Parameters affecting air traffic:",
                  "• The source and structure of the problem instances:"] {
        #expect(preformatted(blocks).contains(label), "\(label)")
    }
    for entry in ["– Only four types of aircraft can appear in the problem instance: [s]mall, [m]edium, [L]arge, [H]eavy.",
                  "– The route network for each problem is a tree weighted by the internodal distances and generated using random_tree function [3].",
                  "– Distance is measured in nautical miles (NMI)."] {
        #expect(paragraphs(blocks).contains { $0.hasPrefix(entry) }, "\(entry)")
        #expect(!preformatted(blocks).contains { $0.contains(entry) }, "\(entry)")
    }
}

// The evidence the rule asks for, and what it refuses.
@Test func bulletItemSizeNeedsAMarkerBeforeSubstantialText() {
    let item = attributed([("• ", "Helvetica", 6.97),
                           ("Controllability: By leaving node k at time T", "Helvetica", 9.96)])
    #expect(NativeTextReader.bulletItemBodySize(in: item).map { abs($0 - 9.96) < 0.01 } == true)
    // A bullet drawn larger than its text overstates the line rather than hiding it; that is a
    // different defect and is left alone (the Fed's page-58 list sets a 10-point bullet over
    // 8-point text).
    #expect(NativeTextReader.bulletItemBodySize(
        in: attributed([("• ", "Helvetica", 10), ("Primary Dealer Credit Facility was announced", "Helvetica", 8)])) == nil)
    // The same size is no marker to correct.
    #expect(NativeTextReader.bulletItemBodySize(
        in: attributed([("• ", "Helvetica", 10), ("Controllability: By leaving node k", "Helvetica", 10)])) == nil)
    // A first run that is not a marker: a letter, a digit, a raised note number, a dash.
    for opening in [("A", 6.97), ("1", 6.97), ("178", 7.17), ("– ", 6.97)] {
        #expect(NativeTextReader.bulletItemBodySize(
            in: attributed([(opening.0, "Helvetica", opening.1),
                            ("Controllability: By leaving node k at time T", "Helvetica", 9.96)])) == nil, "\(opening.0)")
    }
    // A short label opening a list is an item (`• Units of measurement:`, 18 letters in three
    // words), and so the paper's own list reads at one size.
    #expect(NativeTextReader.bulletItemBodySize(
        in: attributed([("• ", "Helvetica", 6.97), ("Units of measurement:", "Helvetica", 9.96)])) != nil)
    // Two words are not an item's text, however many letters they hold, and neither are three
    // that do not reach fifteen letters.
    #expect(NativeTextReader.bulletItemBodySize(
        in: attributed([("• ", "Helvetica", 6.97), ("Units measurements", "Helvetica", 9.96)])) == nil)
    #expect(NativeTextReader.bulletItemBodySize(
        in: attributed([("• ", "Helvetica", 6.97), ("Unit of time", "Helvetica", 9.96)])) == nil)
    // A stray glyph pair in a scan's text layer is no item: the Blue Book's OCR reads a
    // scan-margin mark as `✓` before a column of figures.
    for text in ["✓ I", "✓ 5 1/J.tJ RtJ.tJ", "✓ () 3 3M M 3/),L ?"] {
        #expect(NativeTextReader.bulletItemBodySize(
            in: attributed([("✓ ", "Helvetica", 6.96), (String(text.dropFirst(2)), "Helvetica", 8.5)])) == nil, "\(text)")
    }
    // A marker with nothing after it, and a monospaced item.
    #expect(NativeTextReader.bulletItemBodySize(in: attributed([("• ", "Helvetica", 6.97)])) == nil)
    #expect(NativeTextReader.textLine(semantic: "• Controllability: By leaving node k at time T",
        bounds: CGRect(x: 0, y: 0, width: 200, height: 10),
        attributed: attributed([("• ", "Courier", 6.97),
                                ("Controllability: By leaving node k at time T", "Courier", 9.96)])).fontSize == 6.97)
}

// MARK: - A justified line PDFKit split at its own word space

// References [1] and [7] keep the piece PDFKit split off (`CVXOPT: A`, `NASA`), and the entries
// around them are unchanged.
@Test func sourceSplitReferenceRowsRejoinAtTheirWordSpace() throws {
    let page = try sourcePage(10)
    let left = try #require(page.lines.first { $0.text.hasPrefix("[1] M. S. Andersen") })
    let right = try #require(page.lines.first { $0.text == "CVXOPT: A" })
    #expect(left.trailingSpace && !right.trailingSpace)
    // The junction is 1.57 ems — far wider than the word space #148's tier admits.
    #expect(right.rect.minX - left.rect.maxX > left.fontSize * 1.5)
    let entries = paragraphs(reflow(page))
    #expect(entries.contains("[1] M. S. Andersen, J. Dahl, and L. Vandenberghe. CVXOPT: A python package for convex optimization, version 1.1.5. seas.ucla.edu/ ∼vandenbe/publications/coneprog.pdf , 2012."))
    #expect(entries.contains { $0.hasPrefix("[7] J. L. Rios") && $0.hasSuffix("level 4. NASA Technical Memorandum, 2018.") })
    // Controls: no detached piece is left, and the entries PDFKit did not split are unchanged.
    #expect(!entries.contains { $0 == "CVXOPT: A" || $0 == "NASA" || $0 == "Technical Memorandum, 2018." })
    #expect(entries.contains("[6] C. H. Papadimitriou and K. Steiglitz. Combinatorial Optimization; Algorithms and Complexity. Dover Publications, 1998."))
    #expect(entries.contains("[8] A. S. Tanenbaum and M. Van Steen. Distributed systems: principles and paradigms. Prentice-Hall, 2007."))
}

// Synthetic rows: a justified column of 10-point lines on one 300-point measure whose third row
// PDFKit split at a stretched word space, 1.4 ems wide, after a sentence end — neither of which
// #148's tier reads.
private func line(_ text: String, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat,
                  trailing: Bool = false, height: CGFloat = 10) -> TextLine {
    var result = TextLine(text: text, rect: CGRect(x: x, y: y, width: width, height: height), fontSize: 10)
    result.trailingSpace = trailing
    return result
}

private func blocks(_ lines: [TextLine]) -> [String] {
    var warnings: [ConversionWarning] = []
    let page = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 792, height: 792), lines: lines, graphics: [])
    return LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings).map(\.text)
}

/// The column, with the split row's two pieces standing in it.
private func splitRowColumn(_ pieces: [TextLine], edge: CGFloat = 372) -> [String] {
    blocks([line("The committee should conduct continuing studies of every agency and report", 72, 712, edge - 72),
            line("the problems it finds to all the members of the House and of the Senate", 72, 700, edge - 72)]
        + pieces
        + [line("and be clearly accountable to the Congress for the whole of their own work", 72, 676, edge - 72),
           line("The staff of this committee should be nonpartisan and work for the whole house", 72, 664, edge - 72)])
}

private let splitLeft = "and the agencies. We have conducted our oversight."
private let splitRight = "The whole intelligence"
private let splitPhrase = "We have conducted our oversight. The whole intelligence"

@Test func stretchedWordSpaceRowsNeedTheSpaceTheMeasureAndAnOrdinaryLine() {
    func joins(_ texts: [String]) -> Bool { texts.contains { $0.contains(splitPhrase) } }
    #expect(joins(splitRowColumn([line(splitLeft, 72, 688, 250, trailing: true),
                                  line(splitRight, 326, 688, 46)])))
    // Controls, each leaving the pieces apart.
    // The space PDFKit reported is the evidence; without it a junction 1.4 ems wide after a
    // sentence end is no word space.
    #expect(!joins(splitRowColumn([line(splitLeft, 72, 688, 250), line(splitRight, 326, 688, 46)])))
    // The row does not reach the right edge its paragraph's lines reach: it ends 16 points short
    // of the measure, which is a line's own right edge and no full line of the paragraph.
    #expect(!joins(splitRowColumn([line(splitLeft, 72, 688, 250, trailing: true),
                                   line(splitRight, 326, 688, 30)])))
    // Only two lines reach that edge: a paragraph's measure is the edge its lines share, and two
    // lines with one beside the row are all `isProseRow` itself asks for.
    #expect(!joins(blocks([line("The committee should conduct continuing studies of every agency and report", 72, 700, 300),
                           line(splitLeft, 72, 688, 250, trailing: true),
                           line(splitRight, 326, 688, 46),
                           line("The staff of this committee should be nonpartisan and work for the house", 72, 676, 300)])))
    // The row stands taller than the page's ordinary line of its type: something set beside the
    // text, not a line of it (Wallace page 189's worked example).
    #expect(!joins(splitRowColumn([line(splitLeft, 72, 688, 250, trailing: true, height: 22),
                                   line(splitRight, 326, 688, 46, height: 22)])))
    // The junction is wider than a justified line stretches a space to.
    #expect(!joins(splitRowColumn([line(splitLeft, 72, 688, 240, trailing: true),
                                   line(splitRight, 340, 688, 32)])))
    // A two-column table whose labels are set to one right edge: the left piece ends where the
    // other labels end, so PDFKit broke no line there, and the values beside them start wherever
    // their digits fall (Our Flag page 16's proportion table).
    let table = [line("The committee should conduct continuing studies of every agency and report", 72, 712, 300),
                 line("the problems it finds to all the members of the House and of the Senate", 72, 700, 300),
                 line(splitLeft, 72, 688, 228, trailing: true),
                 line(splitRight, 316, 688, 56),
                 line("Hoist of the flag and of its union and of each of the stars it carries", 72, 676, 228),
                 line("and the diameter of each star and of the union in its whole breadth", 72, 664, 228),
                 line("1.0 and 0.5385 for each of them", 310, 676, 62),
                 line("0.0616 and 0.0540 for the rest", 321, 664, 51)]
    #expect(!joins(blocks(table)))
    // A two-column page's row: the left piece ends on its own column's measure, so PDFKit broke
    // no line there. The pieces read as one row and as one full line across both columns.
    let columns = [line("The committee should conduct continuing studies of every agency and report", 72, 712, 300),
                   line("the problems it finds to all the members of the House and of the Senate", 72, 700, 300),
                   line(splitLeft, 72, 688, 300, trailing: true),
                   line("The staff of this committee should be nonpartisan for the whole of the house", 72, 676, 300),
                   line("The committee should report the problems it finds to all of the members and", 400, 712, 300),
                   line("conduct continuing studies of every agency of the House and of the Senate all", 400, 700, 300),
                   line(splitRight, 400, 688, 300),
                   line("The staff of this committee should work for the whole house and be nonpartisan", 400, 676, 300)]
    #expect(!joins(blocks(columns)))
}
