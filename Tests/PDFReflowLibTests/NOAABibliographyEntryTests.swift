import Foundation
import Testing
@testable import PDFReflowLib

/// Physical page 122 hangs references 30–40 from a separate number column. Every continuation
/// of the unusually long entry 30 stays at the author edge, including lines beginning with an
/// initial such as `N. Viovy`; those initials do not open lettered list items (#219 item 1).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/219"))
func noaaBibliographyKeepsEachNumberedEntryWhole() throws {
    let fixture = try SourceLayoutFixture.load("noaa-122")
    #expect(fixture.sourceSHA256 == "1942cbf346dc2c711fea413d6d6543edb8bc1e3a88d4c3a85e733c6b6d3577bf")
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: fixture.content(), images: [], vocabulary: [], warnings: &warnings)
    let texts = blocks.map(\.text)
    let entry30 = try #require(texts.first { $0.hasPrefix("30. Saunois, M.") })
    #expect(entry30.contains("N. Viovy, A. Voulgarakis"))
    #expect(entry30.hasSuffix("https://doi.org/10.5194/essd-12-1561-2020"))
    #expect(texts.contains { $0.hasPrefix("31. Lan, X.") && $0.contains("https://doi.org/10.15138/p8xg-aa10") })
    #expect(texts.contains { $0.hasPrefix("40. Gettelman, A.") && $0.contains("2020gl091805") })
    #expect(!texts.contains { $0 == "30." || $0 == "31." || $0.hasPrefix("N. Viovy, A.") })
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/219"))
func numberedBibliographyRequiresPrintedCitationEvidence() throws {
    for name in ["noaa-toc-10", "911-14", "census-17"] {
        let page = try SourceLayoutFixture.load(name).content()
        #expect(NumberedBibliography.evidence(in: page.lines,
                   body: PageTypography(page: page).body)?.edge == nil, Comment(rawValue: name))
    }
}
