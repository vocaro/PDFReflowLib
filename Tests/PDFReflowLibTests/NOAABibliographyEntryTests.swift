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

/// Physical page 31 uses inline numbers at x=72 and hangs each later row at x=90. The
/// `675.` page number inside citation 4 is on the hanging edge, not a new reference.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/219"))
func noaaInlineNumberedReferencesKeepTheirHangingLines() throws {
    let fixture = try SourceLayoutFixture.load("noaa-31")
    #expect(fixture.sourceSHA256 == "1942cbf346dc2c711fea413d6d6543edb8bc1e3a88d4c3a85e733c6b6d3577bf")
    let page = fixture.content()
    #expect(NumberedBibliography.inlineWraps(in: page.lines, body: PageTypography(page: page).body).count >= 10)
    var warnings: [ConversionWarning] = []
    let texts = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings).map(\.text)
    #expect(texts.contains { $0.hasPrefix("1. Global Change Research Act") && $0.contains("congress.gov/bill") })
    #expect(texts.contains { $0.hasPrefix("2. USGCRP, 2018") && $0.contains("D.R. Easterling")
        && $0.contains("https://doi.org/10.7930/nca4.2018") })
    #expect(texts.contains { $0.hasPrefix("4. Mastrandrea") && $0.contains("guidance note")
        && $0.contains("675. https://doi.org/10.1007/s10584-011-0178-6") })
    #expect(!texts.contains { $0.hasPrefix("D.R. Easterling") || $0.hasPrefix("guidance note")
        || $0.hasPrefix("675. https://doi") })
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/219"))
func inlineNumberedBibliographyNeedsRepeatedHangingCitations() throws {
    for name in ["noaa-toc-10", "911-14", "algebra-10", "census-17"] {
        let page = try SourceLayoutFixture.load(name).content()
        #expect(NumberedBibliography.inlineWraps(in: page.lines,
            body: PageTypography(page: page).body).isEmpty, Comment(rawValue: name))
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/219"))
func noaaInlineNumberedActualPagePreservesEntries() throws {
    let url = URL(fileURLWithPath: "corpus/cache/noaa_61592_DS1.pdf")
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    let source = try PDFPageSource(url: url)
    let page = try PageReader.read(pageIndex: 30, from: source, limit: 100_000,
                                   options: ConversionOptions(), structure: nil).content
    let wraps = NumberedBibliography.inlineWraps(in: page.lines, body: PageTypography(page: page).body)
    #expect(wraps.count >= 10)
    var warnings: [ConversionWarning] = []
    let texts = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings).map(\.text)
    #expect(texts.contains { $0.hasPrefix("2. USGCRP, 2018") && $0.contains("D.R. Easterling") })
    #expect(texts.contains { $0.hasPrefix("4. Mastrandrea") && $0.contains("guidance note") })
}
