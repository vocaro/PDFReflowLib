import Foundation
import Testing
@testable import PDFReflowLib

// Nesting and joining in the EPUB writer (#142). `EPUBTextEncoder` wrapped each run separately,
// so a style shared by adjacent runs was written twice (`<strong><em>Demand</em></strong><strong>
// Shocks</strong>`, Fed page 30) and an unstyled line-join space broke a style in two (arXiv page
// 4). Runs now nest: each element spans every adjacent run carrying its style, and a joining
// space takes the emphasis the runs either side of it share.

private func inline(_ elements: [InlineText.Element]) -> String {
    EPUBTextEncoder.inline(InlineText(elements: elements))
}

@Test func adjacentRunsNestInsideTheStyleTheyShare() {
    // Fed page 30: a demibold italic sidebar subtitle before its demibold text.
    #expect(inline([.text("Demand", [.bold, .italic]), .text(" Shocks", .bold)])
            == "<strong><em>Demand</em> Shocks</strong>")
    #expect(inline([.text("Supervisory ", .bold), .text("Ratings", [.bold, .italic])])
            == "<strong>Supervisory <em>Ratings</em></strong>")
    // A style opening and closing inside the one it shares is one element either way.
    #expect(inline([.text("a", .bold), .text("b", [.bold, .italic]), .text("c", .bold)])
            == "<strong>a<em>b</em>c</strong>")
    // Three deep: a maths variable inside bold inside a superscript.
    #expect(inline([.text("n", [.superscript, .bold, .mathItalic]), .text("+1", [.superscript, .bold])])
            == "<sup><strong><i>n</i>+1</strong></sup>")
    // Controls: styles sharing nothing stay apart, and a run raised and lowered at once is raised.
    #expect(inline([.text("a", .bold), .text("b", .italic)]) == "<strong>a</strong><em>b</em>")
    #expect(inline([.text("a", .superscript), .text("b", .subscript)]) == "<sup>a</sup><sub>b</sub>")
    #expect(inline([.text("a", [.superscript, .subscript])]) == "<sup>a</sup>")
    // Control: a page boundary and a note reference carry their own element, so they end a run.
    let key = NoteKey(number: 3, scope: .page(31))
    #expect(inline([.text("a", .bold), .sourcePage(31), .text("b", .bold)])
            .hasPrefix("<strong>a</strong><span epub:type=\"pagebreak\""))
    #expect(inline([.text("a", .bold), .noteReference("3", [.superscript, .bold], key), .text("b", .bold)])
            .hasPrefix("<strong>a</strong><sup><a "))
    // Control: text is still escaped, and an unstyled run is written bare.
    #expect(inline([.text("<&>", .bold), .text(" plain", [])]) == "<strong>&lt;&amp;&gt;</strong> plain")
}

@Test func aJoiningSpaceTakesTheEmphasisTheRunsBesideItShare() {
    // arXiv page 4: the caption's two lines join with a space of their own.
    #expect(inline([.text("=15, and the", .bold), .text(" ", []), .text("shift is issued", .bold)])
            == "<strong>=15, and the shift is issued</strong>")
    // Only what both sides carry, and only where it is invisible in a space.
    #expect(inline([.text("a", [.bold, .italic]), .text(" ", []), .text("b", .bold)])
            == "<strong><em>a</em> b</strong>")
    #expect(inline([.text("a", [.superscript, .bold]), .text(" ", []), .text("b", [.superscript, .bold])])
            == "<sup><strong>a</strong></sup> <sup><strong>b</strong></sup>")
    // A space of its own style keeps it and gains the shared emphasis around it.
    #expect(inline([.text("a", .bold), .text(" ", .italic), .text("b", .bold)])
            == "<strong>a<em> </em>b</strong>")
    // Controls: runs sharing nothing, a space carrying text, an edge space with one neighbour,
    // and a space beside a page boundary are all left as they are.
    #expect(inline([.text("a", .bold), .text(" ", []), .text("b", .italic)])
            == "<strong>a</strong> <em>b</em>")
    #expect(inline([.text("a", .bold), .text(" x ", []), .text("b", .bold)])
            == "<strong>a</strong> x <strong>b</strong>")
    #expect(inline([.text(" ", []), .text("b", .bold)]) == " <strong>b</strong>")
    #expect(inline([.text("a", .bold), .text(" ", [])]) == "<strong>a</strong> ")
    #expect(inline([.text("a", .bold), .text(" ", []), .sourcePage(5), .text("b", .bold)])
            .hasPrefix("<strong>a</strong> <span epub:type=\"pagebreak\""))
}

@Test func mathItalicIsWrittenAsANonEmphasisItalic() {
    // The owner's decision on #142: `<i>` carries the slope of a maths italic font. `<em>` is
    // spoken stress, which a variable is not, and `<var>` claims a named variable, which the
    // font alone does not evidence.
    #expect(inline([.text("5", []), .text("x", .mathItalic), .text("\u{2212} 2", []), .text("y", .mathItalic)])
            == "5<i>x</i>\u{2212} 2<i>y</i>")
    #expect(inline([.text("Check:", .italic)]) == "<em>Check:</em>")
    // A variable inside a bold label nests, and a run is never both italics in one book's fonts.
    #expect(inline([.text("Solve for ", .bold), .text("x", [.bold, .mathItalic])])
            == "<strong>Solve for <i>x</i></strong>")
    // Control: `<i>` is the innermost element, so `<em>` beside it never merges with it.
    #expect(inline([.text("a", .italic), .text("b", .mathItalic)]) == "<em>a</em><i>b</i>")
}

@Test func nestingLeavesNotesAndTablesValidAndUnchangedInText() throws {
    // A note's opening number stays in its backlink, and the text after it nests as prose does.
    let note = InlineText(elements: [.text("12.", .bold), .text(" See ", .bold), .text("Annual Report", [.bold, .italic])])
    let markup = EPUBTextEncoder.note(note, number: 12, backlink: "noteref-c1-12")
    #expect(markup.hasPrefix("<a href=\"#noteref-c1-12\" role=\"doc-backlink\" epub:type=\"backlink\"><strong>12.</strong></a>"))
    #expect(markup.hasSuffix("<strong> See <em>Annual Report</em></strong>"))
    // A table cell nests the same way; every element the encoder writes is closed in order.
    let cell = ReflowBlock.Table.Cell(text: InlineText(elements: [.text("Demand", [.bold, .italic]), .text(" Shocks", .bold)]))
    let table = ReflowBlock.Table(columns: 1, rows: [.init(cells: [cell], header: false)])
    #expect(EPUBTextEncoder.table(table) == "<table><tbody><tr><td><strong><em>Demand</em> Shocks</strong></td></tr></tbody></table>")
    let block = ReflowBlock(content: .paragraph(InlineText(elements: [.text("n", [.superscript, .bold, .mathItalic])])), page: 1)
    let payload = try EPUBTextEncoder.payload(block, imagePaths: [:])
    #expect(payload == "<sup><strong><i>n</i></strong></sup>")
}
