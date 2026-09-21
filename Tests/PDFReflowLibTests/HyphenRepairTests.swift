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

// MARK: - A book whose font encodes its line-end hyphen as another character (#233)

private func substitutePage(_ lines: [String]) -> PageContent {
    PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 600, height: 800),
                lines: lines.enumerated().map {
                    TextLine(text: $0.element, rect: CGRect(x: 40, y: 740 - Double($0.offset) * 14, width: 500, height: 12),
                             fontSize: 10)
                }, graphics: [])
}

private func tally(_ pages: [[String]]) -> [Character: LineEndSubstituteTally] {
    var tallies: [Character: LineEndSubstituteTally] = [:]
    for page in pages {
        LayoutReconstructor.tallyLineEndSubstitutes(of: substitutePage(page), into: &tallies)
    }
    return tallies
}

/// Eight word breaks is the evidence floor, so each fixture book prints nine.
private let brokenBook = (1...9).map { _ in ["a word that broke as hijack=", "ers on the next line"] }

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/233")) func aLineEndHyphenEncodedAsAnotherCharacterIsFound() {
    let tallies = tally(brokenBook)
    #expect(tallies["="]?.total == 9)
    #expect(tallies["="]?.lineFinalAfterLetter == 9)
    #expect(tallies["="]?.continuedLowercase == 9)
    #expect(LayoutReconstructor.lineEndSubstitute(from: tallies) == "=")
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/233")) func aBookThatMeansTheCharacterKeepsIt() {
    // One relation inside a line is 1 of 10 — under the share — and the whole book is left alone.
    var maths = brokenBook
    maths.append(["the identity 2 + 2 = 4 holds", "for every reader"])
    #expect(LayoutReconstructor.lineEndSubstitute(from: tally(maths)) == nil)
    // A slash is common inside lines and never qualifies, as 9/11's 878 occurrences do not.
    let slashes = (1...9).map { _ in ["dated 9/11 and 24/7 through", "the whole report"] }
    #expect(LayoutReconstructor.lineEndSubstitute(from: tally(slashes)) == nil)
    // Too few occurrences to decide anything.
    #expect(LayoutReconstructor.lineEndSubstitute(from: tally(Array(brokenBook.prefix(3)))) == nil)
    // A line end that no lowercase word carries on is a mark, not a break.
    let ends = (1...9).map { _ in ["The total was ten=", "Next Section Begins"] }
    #expect(LayoutReconstructor.lineEndSubstitute(from: tally(ends)) == nil)
    // Sentence punctuation is never a candidate however the book falls.
    let stops = (1...9).map { _ in ["the sentence ends here.", "and carries on lowercase"] }
    #expect(LayoutReconstructor.lineEndSubstitute(from: tally(stops)) == nil)
    // Two qualifying characters no longer say which glyph the hyphen is.
    #expect(LayoutReconstructor.lineEndSubstitute(from: tally(brokenBook + (1...9).map { _ in ["broken word hijack~", "ers carry on"] })) == nil)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/233")) func theSubstituteJoinsExactlyAsThePrintedHyphenWould() {
    let book = HyphenContext(vocabulary: ["hijackers"], lineEndSubstitute: "=")
    var warnings: [ConversionWarning] = []
    // Certain: the book's own words vouch, so the mark goes and the halves join.
    #expect(LayoutReconstructor.join("the hijack=", "ers boarded", hyphens: book, page: 3, warnings: &warnings)
            == "the hijackers boarded")
    #expect(warnings.isEmpty)
    // Uncertain: a real hyphen is written back, never the character the font encoded, and the
    // existing warning is raised exactly as a printed hyphen would raise it.
    var uncertain: [ConversionWarning] = []
    let undecided = HyphenContext(vocabulary: [], lineEndSubstitute: "=")
    #expect(LayoutReconstructor.join("a zorbu=", "latinex sample", hyphens: undecided, page: 3, warnings: &uncertain)
            == "a zorbu-latinex sample")
    #expect(uncertain.map(\.code) == [.uncertainHyphen])
    // Not a word break at all: the mark still reads as the hyphen the page drew.
    var spaced: [ConversionWarning] = []
    #expect(LayoutReconstructor.join("the total=", "Next Section", hyphens: book, page: 3, warnings: &spaced)
            == "the total- Next Section")
    // A book with no substitute is untouched.
    var plain: [ConversionWarning] = []
    #expect(LayoutReconstructor.join("the hijack=", "ers boarded", vocabulary: ["hijackers"], page: 3, warnings: &plain)
            == "the hijack= ers boarded")
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/233")) func theRepairedHyphenKeepsItsRunStyle() {
    let book = HyphenContext(vocabulary: [], lineEndSubstitute: "=")
    var left = InlineText("a zorbu")
    left.append(InlineText("=", style: .italic))
    var warnings: [ConversionWarning] = []
    let joined = LayoutReconstructor.join(left, InlineText("latinex"), hyphens: book, page: 1, warnings: &warnings)
    #expect(joined.text == "a zorbu-latinex")
    #expect(joined.elements.contains { element in
        if case let .text(value, style) = element { return value == "-" && style == .italic } else { return false }
    })
}

// MARK: - A font's ligatures are letters to the vocabulary (#123)

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/123"))
func aLigatureIsHeldAndLookedUpAsTheLettersItDraws() {
    // Wallace's text font prints `different` with a U+FB00 `ﬀ`, 56 times, so the book's own words
    // held `diﬀerent` and never `different` and could not decide `dif-` + `ferent` on pages 50
    // and 218. The vocabulary now holds the letters the glyph stands for.
    let printed = TextLine(text: "This is very common with diﬀerent formulas, there may be more",
                           rect: CGRect(x: 85, y: 200, width: 425, height: 12), fontSize: 12)
    #expect(printed.text.contains("\u{FB00}"))
    #expect(LayoutReconstructor.words(of: printed).contains("different"))
    #expect(!LayoutReconstructor.words(of: printed).contains { $0.contains("\u{FB00}") })

    var warnings: [ConversionWarning] = []
    let book = HyphenContext(vocabulary: LayoutReconstructor.vocabulary(in: [
        PageContent(number: 50, bounds: CGRect(x: 0, y: 0, width: 595, height: 842),
                    lines: [printed], graphics: []),
    ]))
    #expect(LayoutReconstructor.join("they are just written in a dif-", "ferent form because we solved",
                                     hyphens: book, page: 50, warnings: &warnings)
            == "they are just written in a different form because we solved")
    #expect(warnings.isEmpty)

    // The other half of the lookup: a break whose second half opens with the ligature is asked
    // about as letters too, against a vocabulary that never saw the glyph. The repair joins the
    // halves the page printed, so the glyph the reader gets is untouched.
    let plain = HyphenContext(vocabulary: ["coefficient"])
    #expect(LayoutReconstructor.join("the leading coe-", "ﬃcient of x", hyphens: plain, page: 1, warnings: &warnings)
            == "the leading coeﬃcient of x")
    #expect(warnings.isEmpty)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/123"))
func normalizingTheVocabularyLeavesAGenuineCompoundAndTheBooksOwnText() {
    // A compound the book prints whole keeps its hyphen, whichever glyphs the font draws it
    // with: normalization decides how a word is spelled for the lookup, not whether a break is a
    // word break. Both halves of the evidence fold, so the compound is still recognized.
    let printed = TextLine(text: "the coﬀee-maker in the staﬀ room was replaced last week",
                           rect: CGRect(x: 85, y: 200, width: 425, height: 12), fontSize: 12)
    let book = HyphenContext(vocabulary: LayoutReconstructor.vocabulary(in: [
        PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 595, height: 842),
                    lines: [printed], graphics: []),
    ]))
    #expect(book.vocabulary.contains("coffee-maker") && !book.vocabulary.contains("coffeemaker"))
    var warnings: [ConversionWarning] = []
    #expect(LayoutReconstructor.join("the coﬀee-", "maker in the room", hyphens: book, page: 1, warnings: &warnings)
            == "the coﬀee-maker in the room")
    #expect(warnings.isEmpty)
    // Only the evidence folds. The ligature the page printed stays in the text the reader gets,
    // on both sides of a join the vocabulary does decide.
    #expect(LayoutReconstructor.vocabularyWord("Diﬀerence") == "difference")
    #expect(LayoutReconstructor.vocabularyWord("plain") == "plain")
    #expect(LayoutReconstructor.join("a staﬀ-", "room notice", hyphens: HyphenContext(vocabulary: ["staffroom"]),
                                     page: 1, warnings: &warnings) == "a staﬀroom notice")
}
