import Foundation
import Testing
@testable import PDFReflowLib

// Line-end hyphen repair: the book's own vocabulary, soft hyphens, the uncertain-hyphen warning,
// and the English lexicon's vote where the vocabulary is silent (#186).

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/186")) func anEnglishLexiconDecidesABreakTheBookCannot() throws {
    guard EnglishText.lexiconContains("companies") != nil else { return }
    let english = HyphenContext(usesEnglishLexicon: true)
    for (left, right, joined) in [("commercial com-", "panies interested", "commercial companies interested"),
                                  ("a range of infec-", "tions in humans", "a range of infections in humans")] {
        var warnings: [ConversionWarning] = []
        #expect(LayoutReconstructor.join(left, right, hyphens: english, page: 6, warnings: &warnings) == joined)
        #expect(warnings.isEmpty)
        // Control: without the declared language the break stays undecided, hyphen kept and warned.
        var undecided: [ConversionWarning] = []
        #expect(LayoutReconstructor.join(left, right, vocabulary: [], page: 6, warnings: &undecided) == left + right)
        #expect(undecided.map(\.code) == [.uncertainHyphen])
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/186")) func theLexiconLeavesGenuineCompoundsAndShortHalves() throws {
    guard EnglishText.lexiconContains("companies") != nil else { return }
    let english = HyphenContext(usesEnglishLexicon: true)
    // A compound whose halves are both words on their own (camera-man), a one-letter half
    // (e-mail), and a joined word the lexicon does not hold all keep the hyphen.
    for (left, right) in [("camera-", "man arrived"), ("e-", "mail it"), ("zorbu-", "latinex tonight")] {
        var warnings: [ConversionWarning] = []
        #expect(LayoutReconstructor.join(left, right, hyphens: english, page: 1, warnings: &warnings) == left + right,
                "\(left)\(right)")
    }
}

// MARK: - The document-body floor's own boundary

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/186")) func aVocabularyFragmentFromTheOtherHalfOfTheSameBreakDoesNotBlockTheVouch() throws {
    // main's addVocabulary is page-local and has no notion of a line that opens with the second
    // half of a hyphen-broken word: reading "panies interested in..." on its own adds "panies" to
    // the document's vocabulary as if it were an independent whole word. lexiconVouches must not
    // let that fragment count as evidence that "panies" is a real standalone word, or it would
    // wrongly treat "com-panies" as two genuine words and keep the hyphen. The lexicon, not the
    // vocabulary, is what decides a half's standing.
    guard EnglishText.lexiconContains("companies") != nil else { return }
    #expect(LayoutReconstructor.lexiconVouches(prefix: "com", suffix: "panies", usesEnglishLexicon: true))
}

@Test func ambiguousHyphensArePreservedAndWarned() {
    var warnings: [ConversionWarning] = []
    #expect(LayoutReconstructor.join("an unknown-", "word", vocabulary: [], page: 1, warnings: &warnings) == "an unknown-word")
    #expect(warnings.map(\.code) == [.uncertainHyphen])
    #expect(LayoutReconstructor.join("a soft\u{00ad}", "hyphen", vocabulary: [], page: 1, warnings: &warnings) == "a softhyphen")
}

@Test func hyphenContextDecidesJoins() {
    var warnings: [ConversionWarning] = []
    let known = HyphenContext(vocabulary: ["software", "hard-ware"])
    #expect(LayoutReconstructor.join("soft-", "ware", hyphens: known, page: 1, warnings: &warnings) == "software")
    #expect(LayoutReconstructor.join("hard-", "ware", hyphens: known, page: 1, warnings: &warnings) == "hard-ware")
    #expect(LayoutReconstructor.join("a soft\u{00ad}", "hyphen", hyphens: known, page: 1, warnings: &warnings) == "a softhyphen")
    #expect(LayoutReconstructor.join("plain", "words", hyphens: known, page: 1, warnings: &warnings) == "plain words")
    #expect(warnings.isEmpty)
    // An undecided break keeps the hyphen and warns once per page.
    #expect(LayoutReconstructor.join("un-", "known", hyphens: known, page: 2, warnings: &warnings) == "un-known")
    #expect(LayoutReconstructor.join("an-", "other", hyphens: known, page: 2, warnings: &warnings) == "an-other")
    #expect(warnings.map(\.page) == [2] && warnings[0].code == .uncertainHyphen)
    // The lexicon is consulted only when the context allows it.
    #expect(!LayoutReconstructor.lexiconVouches(prefix: "com", suffix: "panies", usesEnglishLexicon: false))
}

@Test func wordRepairPreservesStyleAndAnInteriorSourceBoundary() {
    var warnings: [ConversionWarning] = []
    let repaired = LayoutReconstructor.join(InlineText("conver-", style: [.bold, .italic]),
        InlineText("sion", style: .italic), vocabulary: ["conversion"], page: 2,
        sourceBoundary: 2, warnings: &warnings)
    #expect(repaired == InlineText(elements: [
        .text("conver", [.bold, .italic]), .sourcePage(2), .text("sion", .italic),
    ]))
    #expect(repaired.text == "conversion")
    #expect(repaired.sourcePages == [2])
    #expect(warnings.isEmpty)
    let ambiguous = LayoutReconstructor.join(InlineText("unknown-", style: .bold),
        InlineText("word"), vocabulary: [], page: 3, warnings: &warnings)
    #expect(ambiguous.text == "unknown-word")
    #expect(warnings.map(\.code) == [.uncertainHyphen])
}

@Test func softHyphenRepairHandlesASeparateStyleRun() {
    var warnings: [ConversionWarning] = []
    let left = InlineText(elements: [.text("soft", .bold), .text("\u{00ad}", .italic)])
    let joined = LayoutReconstructor.join(left, InlineText("ware"), vocabulary: [], page: 1, warnings: &warnings)
    #expect(joined == InlineText(elements: [.text("soft", .bold), .text("ware", [])]))
}
