import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// The word that opens a line after a line-end hyphen is the rest of a broken word (`es-` +
// `timates.html`, `communi-` + `cations`), not a book word, so it vouches for no hyphen join
// (#101). The same letters seen anywhere else still count, and a compound opening such a line
// keeps its own unbroken hyphen as evidence.

private func page(_ texts: [String], number: Int = 1) -> PageContent {
    let lines = texts.enumerated().map { index, text in
        TextLine(text: text, rect: CGRect(x: 72, y: 700 - CGFloat(index) * 14, width: 400, height: 12), fontSize: 10,
                 monospaced: false)
    }
    return PageContent(number: number, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines, graphics: [])
}

private func joined(_ left: String, _ right: String, _ vocabulary: Set<String>) -> (String, [ConversionWarning.Code]) {
    var warnings: [ConversionWarning] = []
    let text = LayoutReconstructor.join(left, right, vocabulary: vocabulary, page: 1, warnings: &warnings)
    return (text, warnings.map(\.code))
}

@Test func wordOpeningALineAfterAHyphenIsNotABookWord() {
    let vocabulary = LayoutReconstructor.vocabulary(in: [page([
        "the program reached many small citi-",
        "es and towns, with the communi-",
        "cations office and",
        "Soft hyphens break words too: resil\u{00ad}",
        "ience grows",
    ])])
    #expect(!vocabulary.contains("es"))
    #expect(!vocabulary.contains("cations"))
    #expect(!vocabulary.contains("ience"))
    // Every other word on those lines still counts.
    #expect(vocabulary.isSuperset(of: ["and", "with", "the", "office", "grows"]))
}

@Test func continuationWordsSeenElsewhereAndOrdinaryLineStartsStillCount() {
    let vocabulary = LayoutReconstructor.vocabulary(in: [
        page(["the census es-", "timates held", "timates appear here unbroken"]),
        // An ordinary line end, a capital after a hyphen, and a line ending in a dash-like word.
        page(["the first line ends", "cations follow it", "Pre-", "Flight checks", "a well-", "known-good path"], number: 2),
        // A line after a hyphen on the previous page is not taken as a continuation.
        page(["ions open this page"], number: 3),
    ])
    #expect(vocabulary.contains("timates"))
    #expect(vocabulary.contains("cations"))
    #expect(vocabulary.contains("flight"))
    #expect(vocabulary.contains("ions"))
    // A compound opening the line keeps its unbroken hyphen as evidence (FAA `straight-` +
    // `and-level flight`, which lets `straight-and-` + `level` keep its hyphen silently).
    #expect(vocabulary.contains("known-good"))
    let faa = LayoutReconstructor.vocabulary(in: [page(["maintain straight-", "and-level flight"])])
    #expect(faa.contains("and-level"))
    #expect(joined("in straight-and-", "level flight", faa) == ("in straight-and-level flight", []))
}

@Test func noaaPage553AddressHyphenJoinsWhenTheContinuationIsOnlyAFragment() throws {
    // The source address is `…/community-resilience-estimates.html` (the page's link annotation).
    // Before #101 the book knew `es` (DOI segments such as page 284's `…/es504293b`) and `timates`
    // (this break's own continuation), so #88's word tier found both pieces words and kept the
    // hyphen with a warning.
    let page553 = try SourceLayoutFixture.load("noaa-553"), page284 = try SourceLayoutFixture.load("noaa-284")
    #expect(page553.sourceSHA256 == "1942cbf346dc2c711fea413d6d6543edb8bc1e3a88d4c3a85e733c6b6d3577bf")
    #expect(page284.sourceSHA256 == page553.sourceSHA256)
    let content553 = page553.content(), content284 = page284.content()
    #expect(content553.lines.contains { $0.text.hasSuffix("(https://www.census.gov/programs-surveys/community-resilience-es-") })
    #expect(content553.lines.contains { $0.text.hasPrefix("timates.html) and emerging") })
    #expect(content284.lines.contains { $0.text.hasSuffix("https://doi.org/10.1021/es504293b") })
    let vocabulary = LayoutReconstructor.vocabulary(in: [content284, content553])
    #expect(vocabulary.contains("es") && vocabulary.contains("estimates"))
    #expect(!vocabulary.contains("timates"))

    var warnings: [ConversionWarning] = []
    let text = LayoutReconstructor.blocks(page: content553, images: [], vocabulary: vocabulary, warnings: &warnings)
        .map(\.text).joined(separator: "\n")
    #expect(text.contains("(https://www.census.gov/programs-surveys/community-resilience-estimates.html) and emerging"))
    #expect(!text.contains("resilience-es-timates"))
    // The break itself is decided, not warned about (the page warns for other breaks this
    // two-page vocabulary cannot decide).
    #expect(joined("(https://www.census.gov/programs-surveys/community-resilience-es-", "timates.html) and", vocabulary)
        == ("(https://www.census.gov/programs-surveys/community-resilience-estimates.html) and", []))
}

@Test func hyphenDecisionsThatFragmentsNeverDecidedAreUnchanged() {
    // Fed 27: `communi-` + `cations.htm` still joins, now with neither piece a book word.
    let fed = LayoutReconstructor.vocabulary(in: [page([
        "https://www.federalreserve.gov/monetarypolicy/review-of-monetary-policy-strategy-tools-and-communi-",
        "cations.htm.", "better communications with the public",
    ])])
    #expect(!fed.contains("cations"))
    #expect(joined("strategy-tools-and-communi-", "cations.htm.", fed).0 == "strategy-tools-and-communications.htm.")
    // A real compound broken at its hyphen, both words known: kept with a warning (Fed 46).
    let real = LayoutReconstructor.vocabulary(in: [page(["https://research.stlouisfed.org/publications/page1-",
                                                         "econ/2020/08/03/tools.", "the economy and the page"])])
    #expect(joined("https://research.stlouisfed.org/publications/page1-", "econ/2020/08/03/tools.", real)
        == ("https://research.stlouisfed.org/publications/page1-econ/2020/08/03/tools.", [.uncertainHyphen]))
    // Prose: the joined word must still be seen unbroken to remove a hyphen.
    let prose = LayoutReconstructor.vocabulary(in: [page(["repair of the commu-", "nications link", "our communications"])])
    #expect(joined("the commu-", "nications link", prose) == ("the communications link", []))
    #expect(joined("an unusual cross-", "wind", prose) == ("an unusual cross-wind", [.uncertainHyphen]))
}
