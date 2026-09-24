import Foundation
import Testing
@testable import PDFReflowLib

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/211"))
func proSeCountedFoliosAndHeaderRulesLeaveWithFurniture() throws {
    var pages = try (1...5).map { number -> PageContent in
        let source = try SourceLayoutFixture.load("uscourts-\(number)")
        #expect(source.sourceSHA256 == "9fe218570d311b0deab9413e39efda41210e60f2a5221eb360d43912ce05a118")
        return source.content()
    }
    let before = pages
    let warnings = FurnitureDetector.strip(&pages)
    #expect(warnings.map(\.page) == [1, 2, 3, 4, 5])
    for (source, result) in zip(before, pages) {
        #expect(source.lines.contains { $0.text == "Page \(source.number) of 5" })
        #expect(!result.lines.contains { $0.text == "Page \(source.number) of 5" })
        #expect(!result.lines.contains { $0.text.hasPrefix("Pro Se 1 (Rev. 12/16)") })
        #expect(!result.graphics.contains { $0.minY > 730 && $0.width >= source.bounds.width * 0.6 })
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/211"))
func proSeHeaderRuleIsDecorationEvenWhenItsTextIsKept() throws {
    let source = try SourceLayoutFixture.load("uscourts-1").content()
    let header = try #require(source.lines.first { $0.text.hasPrefix("Pro Se 1 (Rev. 12/16)") })
    let dividers = FurnitureDetector.rulesSettingOff(header,
        kept: source.lines.filter { $0 != header }, on: source)
    #expect(dividers.count == 1)
    #expect(dividers[0].width >= source.bounds.width * 0.6)
    // A distant rule below body content is not a header divider.
    var control = source
    control.graphics = [CGRect(x: 34, y: 620, width: 544, height: 5)]
    #expect(FurnitureDetector.rulesSettingOff(header,
        kept: control.lines.filter { $0 != header }, on: control).isEmpty)
}
