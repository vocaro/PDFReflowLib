import CryptoKit
import Foundation
import Testing
@testable import PDFReflowLib

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/213"))
func nestedInlineScriptsEncodeAtBothSourceLevels() throws {
    let dasc = try Data(contentsOf: URL(fileURLWithPath: "corpus/cache/20190030725.pdf"))
    #expect(SHA256.hash(data: dasc).map { String(format: "%02x", $0) }.joined() ==
        "7c2137098ffb75153e0049b970272db97bc91e13168028dc7b53fbe2deb92caa")
    // DASC p5 prints STA with an outer raised n, i raised from n, h lowered from n,
    // then h lowered from STA. A flat style had read all three inner glyphs at one level.
    let stacked = InlineText(elements: [
        .text("STA", []),
        .text("n", .superscript),
        .text("i", [.superscript, .nestedSuperscript]),
        .text("h", [.superscript, .nestedSubscript]),
        .text("h", .subscript),
        .text(" follows", []),
    ])
    #expect(EPUBTextEncoder.inline(stacked) ==
        "STA<sup>n<sup>i</sup><sub>h</sub></sup><sub>h</sub> follows")

    // Wallace p178's exponent outside parentheses is a second script of the whole
    // parenthesized expression, rather than a continuation inside a's exponent.
    let parenthesized = InlineText(elements: [
        .text("(", []), .text("a", []), .text("2", .superscript),
        .text(")", []), .text("3", .superscript),
    ])
    #expect(EPUBTextEncoder.inline(parenthesized) == "(a<sup>2</sup>)<sup>3</sup>")
    #expect(EPUBTextEncoder.inline(InlineText("i", style: .nestedSuperscript)) == "i")
}
