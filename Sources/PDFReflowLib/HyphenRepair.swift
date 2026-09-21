import Foundation

/// What decides a line-end hyphen: the book's own words, and, in a document declared English,
/// the system's English lexicon (#186).
struct HyphenContext: Sendable, Equatable {
    /// Every word any page's lines split on, lowercased.
    var vocabulary: Set<String>
    /// Whether `lexiconVouches` may consult the system's English lexicon.
    var usesEnglishLexicon: Bool
    /// The character this book's text font puts where it draws a line-end hyphen, when the book
    /// never uses that character for anything else (#233). `nil` in an ordinary book.
    var lineEndSubstitute: Character?

    init(vocabulary: Set<String> = [], usesEnglishLexicon: Bool = false,
         lineEndSubstitute: Character? = nil) {
        self.vocabulary = vocabulary
        self.usesEnglishLexicon = usesEnglishLexicon
        self.lineEndSubstitute = lineEndSubstitute
    }
}

/// Counts, for one candidate character, the evidence that it is a line-end hyphen in disguise.
struct LineEndSubstituteTally: Sendable, Equatable {
    /// Every occurrence anywhere in the document's readable text.
    var total = 0
    /// Occurrences that end a line and follow a letter.
    var lineFinalAfterLetter = 0
    /// Of those, the ones with a following line on the page, and the ones it opens with a
    /// lowercase letter — a word carrying on, which is what a break looks like.
    var continuable = 0
    var continuedLowercase = 0
}

extension LayoutReconstructor {
    private enum JoinOperation { case space, concatenate, removeHyphen }

    /// Characters a font can encode a drawn hyphen as. Sentence punctuation, quotes, brackets and
    /// dashes are deliberately absent: they end English lines legitimately, and a book where every
    /// one of them happened to fall at a line end would have its text altered rather than repaired.
    static let lineEndSubstituteCandidates: Set<Character> = ["=", "¬", "~", "_", "|", "\\", "+", "*", "/", "<", ">", "^", "¦"]

    /// How many occurrences a candidate needs before one book's stray character can decide this.
    static let minimumLineEndSubstituteEvidence = 8
    /// The share of a candidate's occurrences that must end a line after a letter. Not all of
    /// them: the 9/11 report has 1,004 `=`, of which 994 break a word at a line end and ten do
    /// not, and a book that means `=` as a relation is nowhere near this line. The nearest other
    /// candidate in that book, `/`, scores 4 of 878 — three orders of magnitude away, so the exact
    /// threshold is not delicate.
    static let minimumLineEndSubstituteShare = 0.95
    /// The share of the candidate's line breaks that must carry on in lowercase on the next line.
    static let minimumLineEndSubstituteContinuation = 0.9

    /// The character a book draws as a line-end hyphen, or nil when no candidate is unanimous.
    ///
    /// A candidate qualifies only when almost every occurrence in the book's readable text ends a
    /// line after a letter, and nearly every one of those lines is carried on by a lowercase
    /// letter. A book that means the character — `2 + 2 = 4`, a URL's slashes — spends most of its
    /// occurrences inside lines and falls far short. Two qualifying candidates disqualify each
    /// other: the evidence no longer says which glyph the hyphen is.
    ///
    /// Detection is document-wide; the repair itself is not. Only a line-final occurrence is ever
    /// rewritten, so the occurrences that argued against the candidate are left exactly as read.
    static func lineEndSubstitute(from tallies: [Character: LineEndSubstituteTally]) -> Character? {
        let qualifying = tallies.filter { character, tally in
            tally.total >= minimumLineEndSubstituteEvidence
                && Double(tally.lineFinalAfterLetter) >= Double(tally.total) * minimumLineEndSubstituteShare
                && Double(tally.continuedLowercase) >= Double(tally.continuable) * minimumLineEndSubstituteContinuation
                && lineEndSubstituteCandidates.contains(character)
        }
        return qualifying.count == 1 ? qualifying.first?.key : nil
    }

    /// Folds one page's readable lines into the substitute evidence. Only lines the reader will
    /// see are counted, on the same footing as the hyphen vocabulary: a margin line the furniture
    /// plan removes, and retained unreadable text, never vote on what the book's hyphen looks like.
    static func tallyLineEndSubstitutes(of page: PageContent, skippingLines skipped: Set<Int> = [],
                                        into tallies: inout [Character: LineEndSubstituteTally]) {
        let visible = page.lines.enumerated().filter { !skipped.contains($0.offset) }.map(\.element)
        for (index, line) in visible.enumerated() {
            let text = line.text
            guard text.contains(where: { lineEndSubstituteCandidates.contains($0) }) else { continue }
            for character in text where lineEndSubstituteCandidates.contains(character) {
                tallies[character, default: LineEndSubstituteTally()].total += 1
            }
            guard let last = text.last, lineEndSubstituteCandidates.contains(last),
                  text.dropLast().last?.isLetter == true else { continue }
            tallies[last, default: LineEndSubstituteTally()].lineFinalAfterLetter += 1
            guard index + 1 < visible.count else { continue }
            tallies[last, default: LineEndSubstituteTally()].continuable += 1
            if visible[index + 1].text.first?.isLowercase == true {
                tallies[last, default: LineEndSubstituteTally()].continuedLowercase += 1
            }
        }
    }

    private static func joinOperation(_ left: String, _ right: String, hyphens: HyphenContext, page: Int,
                                      warnings: inout [ConversionWarning]) -> JoinOperation {
        if left.hasSuffix("\u{00ad}") { return .removeHyphen }
        // A line break inside East Asian writing is not a word break: the characters run on with
        // no space, and inserting one splits a word the page never split (#42).
        if CJKText.setsNoSpace(between: left, and: right) { return .concatenate }
        guard left.hasSuffix("-"), right.first?.isLowercase == true else { return .space }
        let prefix = left.dropLast().reversed().prefix(while: { $0.isLetter }).reversed()
        let suffix = right.prefix(while: { $0.isLetter })
        let joined = (String(prefix) + suffix).lowercased()
        let compound = (String(prefix) + "-" + suffix).lowercased()
        if hyphens.vocabulary.contains(joined), !hyphens.vocabulary.contains(compound) { return .removeHyphen }
        if !hyphens.vocabulary.contains(compound) {
            if lexiconVouches(prefix: String(prefix).lowercased(), suffix: String(suffix).lowercased(),
                              usesEnglishLexicon: hyphens.usesEnglishLexicon) {
                return .removeHyphen
            }
            if !warnings.contains(where: { $0.code == .uncertainHyphen && $0.page == page }) {
                warnings.append(.init(code: .uncertainHyphen, page: page,
                    message: "An ambiguous line-ending hyphen is retained. Review source word joins."))
            }
        }
        return .concatenate
    }

    /// A line-end hyphen the book's own words cannot decide, in an English document (#186). A
    /// magazine can print `com-` + `panies` and `infec-` + `tions` and never the words whole or in
    /// another inflection, so the book's own vocabulary is silent although the words are ordinary.
    /// The system's English lexicon (`EnglishText.lexiconContains`, the list the text-layer
    /// judgment reads) vouches for the join when it holds the joined word and neither half is
    /// independently a lexicon word, with short-fragment guards: two letters a side and six in all.
    /// A compound whose halves are both words (`camera-` + `man`) keeps its hyphen and warns, as
    /// before.
    ///
    /// Only the lexicon, not the vocabulary, judges the halves. The vocabulary is every word any
    /// page's lines split on, including a line that opens with the second half of a hyphenated
    /// break (`addVocabulary` does not carry a broken word's halves the way the reference design's
    /// `opensBrokenWord` does): `panies` from `com-panies` becomes an apparent vocabulary "word" by
    /// that route, which would wrongly read the compound as two real words and keep the hyphen.
    /// The lexicon has no such fragment, so it alone decides whether a half stands on its own.
    static func lexiconVouches(prefix: String, suffix: String, usesEnglishLexicon: Bool) -> Bool {
        guard usesEnglishLexicon, prefix.count >= 2, suffix.count >= 2, prefix.count + suffix.count >= 6,
              EnglishText.lexiconContains(prefix + suffix) == true else { return false }
        return !(EnglishText.lexiconContains(prefix) == true && EnglishText.lexiconContains(suffix) == true)
    }

    /// True when this line ends with the character the book draws its line-end hyphen as (#233).
    /// The caller judges the join as if the hyphen were there, and writes a real hyphen back into
    /// any result that keeps the character.
    private static func endsWithSubstitute(_ text: String, _ hyphens: HyphenContext) -> Bool {
        guard let substitute = hyphens.lineEndSubstitute else { return false }
        return text.last == substitute
    }

    static func join(_ left: String, _ right: String, hyphens: HyphenContext, page: Int,
                     warnings: inout [ConversionWarning]) -> String {
        let substituted = endsWithSubstitute(left, hyphens)
        let repaired = substituted ? String(left.dropLast()) + "-" : left
        switch joinOperation(repaired, right, hyphens: hyphens, page: page, warnings: &warnings) {
        case .space: return repaired + " " + right
        case .concatenate: return repaired + right
        case .removeHyphen: return String(repaired.dropLast()) + right
        }
    }

    static func join(_ left: InlineText, _ right: InlineText, hyphens: HyphenContext, page: Int,
                     sourceBoundary: Int? = nil, warnings: inout [ConversionWarning]) -> InlineText {
        var result = left
        let substituted = endsWithSubstitute(left.text, hyphens)
        let repaired = substituted ? String(left.text.dropLast()) + "-" : left.text
        if substituted { result.replaceLastCharacter(with: "-") }
        switch joinOperation(repaired, right.text, hyphens: hyphens, page: page, warnings: &warnings) {
        case .space: result.append(InlineText(" "))
        case .concatenate: break
        case .removeHyphen: result.removeLastCharacter()
        }
        if let sourceBoundary { result.elements.append(.sourcePage(sourceBoundary)) }
        result.append(right)
        // One link over two printed lines is one anchor, not two (#247).
        result.mergeAdjacentLinks()
        return result
    }

    // Vocabulary-only conveniences for tests that never consult the lexicon.

    static func join(_ left: String, _ right: String, vocabulary: Set<String>, page: Int,
                     warnings: inout [ConversionWarning]) -> String {
        join(left, right, hyphens: HyphenContext(vocabulary: vocabulary), page: page, warnings: &warnings)
    }

    static func join(_ left: InlineText, _ right: InlineText, vocabulary: Set<String>, page: Int,
                     sourceBoundary: Int? = nil, warnings: inout [ConversionWarning]) -> InlineText {
        join(left, right, hyphens: HyphenContext(vocabulary: vocabulary), page: page,
             sourceBoundary: sourceBoundary, warnings: &warnings)
    }
}
