import Testing
@testable import PDFReflowLib

@Test func asidesAndQuotationsKeepTextWithoutNavigationHeadings() throws {
    let value = InlineText("A displayed summary or quotation.")
    for (content, tag) in [(ReflowBlock.Content.aside(value), "aside"), (.quotation(value), "blockquote")] {
        let block = ReflowBlock(content: content, page: 1)
        let piece = try EPUBTextEncoder.piece(for: block, imagePaths: [:])
        #expect(block.hasReflowedText)
        #expect(block.text == value.text)
        #expect(piece.markup == "<\(tag)><p>A displayed summary or quotation.</p></\(tag)>\n")
        #expect(piece.heading == nil)
    }
}
