import Foundation
import Testing
@testable import PDFReflowLib

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/171"))
func nasaWordBracketedReferencesAreWholeParagraphs() throws {
    let url = URL(fileURLWithPath: "corpus/cache/20200002975.pdf")
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    let source = try PDFPageSource(url: url)
    let page = try PageReader.read(pageIndex: 18, from: source, limit: 100_000,
                                   options: ConversionOptions(), structure: nil).content
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings)
    let entries = blocks.filter { $0.text.range(of: #"^\[[0-9]+\] "#, options: .regularExpression) != nil }
    #expect(entries.count == 18)
    #expect(entries.allSatisfy { if case .paragraph = $0.content { true } else { false } })
    #expect(entries.contains { $0.text.hasPrefix("[2] Farmer") && $0.text.contains("Wind Tunnel Studies") })
    #expect(entries.contains { $0.text.hasPrefix("[18] McCullough") && $0.text.contains("Adjacent Structures") })
    #expect(!blocks.contains { $0.text.hasPrefix("doi: 10.1016") })
    #expect(blocks.contains { if case .heading = $0.content { return $0.text == "REFERENCES" }; return false })
    #expect(blocks.contains { if case .heading = $0.content { return $0.text == "ACKNOWLEDGEMENTS" }; return false })
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/171"))
func bracketedReferencesRequireLabelAndCitationRun() {
    func paragraph(_ text: String) -> ReflowBlock {
        .init(content: .paragraph(InlineText(text)), page: 1)
    }
    let numbered = (1...5).map { paragraph("[\($0)] Carry out step \($0) now.") }
    #expect(BracketedReferenceBlocks.joined([paragraph("STEPS")] + numbered)
        == [paragraph("STEPS")] + numbered)
    #expect(BracketedReferenceBlocks.joined([paragraph("REFERENCES")] + numbered)
        == [paragraph("REFERENCES")] + numbered)
}
