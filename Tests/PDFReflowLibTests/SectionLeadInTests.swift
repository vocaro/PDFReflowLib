import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

/// Bold run-in section labels under sub-point paragraph spacing (#60). The USGS Mineral
/// Commodity Summaries set about 0.3 pt between sections, well under the ordinary paragraph
/// threshold, so each lead-in used to be swallowed by the section above it.
private func leadInBlocks(_ page: PageContent, images: [(CGRect, String)] = []) -> [ReflowBlock] {
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: images,
        vocabulary: LayoutReconstructor.vocabulary(in: [page]), warnings: &warnings)
}

private func paragraphs(_ blocks: [ReflowBlock]) -> [String] {
    blocks.compactMap { if case .paragraph = $0.content { $0.text } else { nil } }
}

/// A body paragraph whose lines wrap at `leading` points of box gap, then a line set
/// `spacing` points below it. `label` opens that line as a bold run.
private func leadInPage(label: String = "Substitutes:", rest: String = " Aluminum substitutes for copper.",
                        previous: String = "resources contained 3.5 billion tons of copper.",
                        spacing: CGFloat = 8, leading: CGFloat = -2.7,
                        indent: CGFloat = 0, bold: Bool = true) -> PageContent {
    let size: CGFloat = 10, height: CGFloat = 13.8
    var lines: [TextLine] = []
    var top: CGFloat = 700
    for text in ["World Resources: The most recent assessment of global copper resources indicated",
                 "that identified resources contained 1.5 billion tons of unextracted copper and that", previous] {
        lines.append(TextLine(text: text, rect: CGRect(x: 100, y: top - height, width: 400, height: height), fontSize: size))
        top = top - height - leading
    }
    let content = InlineText(elements: [.text(label, bold ? [.bold] : []), .text(rest, [])])
    lines.append(TextLine(content: content,
        rect: CGRect(x: 100 + indent, y: top - height - spacing, width: 400, height: height), fontSize: size))
    return PageContent(number: 3, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines, graphics: [])
}

@Test func sourceUSGSBoldLeadInsOpenTheirOwnParagraphsUnderSubPointSpacing() throws {
    let page = try SourceLayoutFixture.load("usgs-2").styledContent()
    let texts = paragraphs(leadInBlocks(page))
    let leadIn = try #require(texts.first { $0.hasPrefix("Substitutes:") })
    #expect(leadIn.hasSuffix("Titanium and steel are used in heat exchangers."))
    #expect(!leadIn.contains("3.5 billion tons of copper"))
    let world = try #require(texts.first { $0.hasPrefix("World Mine and Refinery Production and Reserves:") })
    #expect(world.hasSuffix("industry association reports."))
    #expect(!world.contains("decreasing inflation"))
    // The label's own section keeps its body, and the section above keeps its own. The table
    // above `World Resources:` is prose in this fixture (the pipeline preserves it as an
    // image), so that label opens its paragraph's text rather than the block.
    let resources = try #require(texts.first { $0.contains("World Resources:") })
    #expect(resources.hasSuffix("3.5 billion tons of copper.8"))
    // The COMEX paragraph has no bold label; the blank line above it opens it (#71, see
    // `SpacedParagraphTests`), so the Events section ends at its own last sentence.
    let events = try #require(texts.first { $0.hasPrefix("Events, Trends, and Issues:") })
    #expect(!events.contains("The COMEX copper price reached a record high"))
    #expect(events.hasSuffix("expected to begin operating by yearend 2024."))
}

@Test func sourceUSGSFirstPageLeadInsSplitPastATrailingReferenceMarker() throws {
    let page = try SourceLayoutFixture.load("usgs-1").styledContent()
    let texts = paragraphs(leadInBlocks(page))
    // `Import Sources` follows a line ending `… of the U.S. copper supply.5`: the raised
    // marker is not the sentence's punctuation.
    let imports = try #require(texts.first { $0.hasPrefix("Import Sources (2020–23):") })
    #expect(!imports.contains("Copper recovered from scrap"))
    let recycling = try #require(texts.first { $0.contains("Recycling:") })
    #expect(recycling.hasSuffix("of the U.S. copper supply.5"))
    #expect(texts.contains { $0 == "Depletion Allowance: 15% (domestic), 14% (foreign)." })
    #expect(texts.contains { $0 == "Government Stockpile: None." })
}

@Test func boldLeadInAfterASentenceSplitsOnlyWithAddedSpace() {
    #expect(paragraphs(leadInBlocks(leadInPage())).count == 2)
    // No added space: the label sits at the leading the paragraph has been wrapping at.
    #expect(paragraphs(leadInBlocks(leadInPage(spacing: 0, leading: 0))).count == 1)
    // A gap past the ordinary threshold already broke the paragraph before this rule.
    #expect(paragraphs(leadInBlocks(leadInPage(spacing: 12))).count == 2)
    // Less added space than a blank line (a 1.3-point gap, 4 points over the paragraph's -2.7-point
    // leading, under the half body size that opens a spaced paragraph of any kind, #71) still
    // splits at a lead-in.
    #expect(paragraphs(leadInBlocks(leadInPage(spacing: 4))).count == 2)
}

@Test func boldEmphasisInsideAParagraphNeverSplitsIt() {
    // These controls set a 1.3-point gap, 4 points over the paragraph's leading: the lead-in rule's
    // own evidence, and less than the blank line that opens any spaced paragraph (#71).
    // No colon and no capitals: ordinary emphasis opening a wrapped line.
    #expect(paragraphs(leadInBlocks(leadInPage(label: "Aluminum", rest: " substitutes for copper.", spacing: 4))).count == 1)
    // A colon label that is not bold is ordinary prose.
    #expect(paragraphs(leadInBlocks(leadInPage(spacing: 4, bold: false))).count == 1)
    // The previous line does not end a sentence, so the label continues it.
    #expect(paragraphs(leadInBlocks(leadInPage(previous: "resources contained 3.5 billion tons of"))).count == 1)
    // Indented from the column's left edge, but not far enough for the existing column test
    // to break the paragraph: a run-in inside an item, not a section opening.
    #expect(paragraphs(leadInBlocks(leadInPage(indent: 12))).count == 1)
    // A wholly bold line is a heading candidate, not a run-in label.
    #expect(paragraphs(leadInBlocks(leadInPage(rest: "", spacing: 4))).count <= 1)
}

/// Pages that carry bold emphasis, bulleted definitions and box run-in heads, whose block
/// structure this rule must not touch. The counts are the reconstruction at `62877e6`,
/// measured before the change: `faa-211`/`faa-212` are the V-speed definitions, `fed-32` a
/// box run-in head (#54), `flag-27` a page of heading rules, `algebra-289` an exercise page
/// and `loper-60` a dash-separator footnote page. Two counts have since changed for other
/// defects: the Fed box's closing `For more information on the FOMC…` paragraph, set off by the
/// same added space as the box's lead-ins, is its own paragraph (#71: 11, 9 → 12, 10), and the
/// opening sentence of `algebra-289` (with no crops in this test) is one paragraph again once its
/// radical pieces rejoin their row (#95: 36 → 34).
@Test func sourceControlPagesKeepEveryBlockBoundary() throws {
    for (name, expected) in [("faa-211", (18, 7, 0)), ("faa-212", (19, 9, 0)), ("fed-32", (12, 10, 0)),
                             ("flag-27", (13, 9, 0)), ("algebra-289", (34, 34, 0)), ("loper-60", (6, 5, 1))] {
        let page = try SourceLayoutFixture.load(name).styledContent()
        let blocks = leadInBlocks(page)
        let counts = (blocks.count, paragraphs(blocks).count, blocks.filter(\.isFootnote).count)
        #expect(counts == expected, "\(name) block structure changed")
    }
}
