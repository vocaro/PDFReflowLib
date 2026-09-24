import Foundation
import Testing
@testable import PDFReflowLib

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/209"), arguments: [100, 122])
func warrenIndentedParagraphsKeepTheirSourceBreaks(pageNumber: Int) throws {
    let fixture = try SourceLayoutFixture.load("warren-\(pageNumber)")
    #expect(fixture.sourceSHA256 == "341cc3471750c9c3be68b95a34b52f6cbdc86c4392427a8483ee1c6bc53cfc19")
    #expect(fixture.page == pageNumber)
    var page = fixture.content()
    // Warren's inherited OCR sits invisibly over the scanned page. Its font metrics do not
    // describe the visible print, but its line positions do.
    page.hasSyntheticTextStyle = true
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings)
    let paragraphs = blocks.compactMap { block -> String? in
        if case .paragraph = block.content { return block.text }
        return nil
    }
    let openings = pageNumber == 100
        ? ["Another employee of the Union Terminal Co.", "As the motorcade proceeded"]
        : ["An examination of the Governor's shirt", "On the French cuff", "Course of huTlet"]
    for opening in openings {
        #expect(paragraphs.contains { $0.hasPrefix(opening) }, "Missing source paragraph: \(opening)")
    }
    let continuations = pageNumber == 100
        ? ["was at work in a railroad tower", "tators were clustered together"]
        : ["tear five-eighths", "a ragged, irregularly shaped hole", "tablished that the missile"]
    for continuation in continuations {
        #expect(paragraphs.contains { $0.contains(continuation) }, "Missing wrapped text: \(continuation)")
    }
}
