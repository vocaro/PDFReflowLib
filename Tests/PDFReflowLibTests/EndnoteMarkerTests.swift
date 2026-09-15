import Testing
@testable import PDFReflowLib

@Test func sourceEndnoteMarkerRetainsNativeSuperscriptEvidence() throws {
    let fixture = try SourceLayoutFixture.load("911-20")
    let source = try #require(fixture.attributedLines.first { $0.text.contains("7:45.") })
    #expect(EPUBTextEncoder.inline(NativeTextReader.inlineText(from: source.attributedString()))
        .contains("7:45.<sup>4</sup>"))
}
