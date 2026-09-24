import Foundation
import Testing
@testable import PDFReflowLib

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/168"))
func damagedDialogueOnCDCPage22IsFlagged() throws {
    try #require(EnglishText.wordCounts("the") != nil, "no system English lexicon")
    let fixture = try SourceLayoutFixture.load("cdc-22")
    #expect(fixture.sourceSHA256 == "d95e9ec2d8cf52cb8c218a6195e132ec140725018358fd2122928bab8a13efc3")
    #expect(fixture.page == 22)
    let counts = try #require(EnglishText.wordCounts(fixture.lines.map(\.text).joined(separator: "\n")))
    #expect(TextLayerPlausibility.wordFinding(counts) != nil, "CDC 22: \(counts)")
}
