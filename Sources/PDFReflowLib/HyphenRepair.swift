import Foundation

/// What decides a line-end hyphen: the book's own words, and, in a document declared English,
/// the system's English lexicon (#186).
struct HyphenContext: Sendable, Equatable {
    /// Every word any page's lines split on, lowercased.
    var vocabulary: Set<String>
    /// Whether `lexiconVouches` may consult the system's English lexicon.
    var usesEnglishLexicon: Bool

    init(vocabulary: Set<String> = [], usesEnglishLexicon: Bool = false) {
        self.vocabulary = vocabulary
        self.usesEnglishLexicon = usesEnglishLexicon
    }
}

extension LayoutReconstructor {
    private enum JoinOperation { case space, concatenate, removeHyphen }

    private static func joinOperation(_ left: String, _ right: String, hyphens: HyphenContext, page: Int,
                                      warnings: inout [ConversionWarning]) -> JoinOperation {
        if left.hasSuffix("\u{00ad}") { return .removeHyphen }
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
    /// The system's English lexicon (`TextLayerPlausibility.lexiconContains`, the list the text-layer
    /// judgement reads) vouches for the join when it holds the joined word and neither half is
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
              TextLayerPlausibility.lexiconContains(prefix + suffix) == true else { return false }
        return !(TextLayerPlausibility.lexiconContains(prefix) == true && TextLayerPlausibility.lexiconContains(suffix) == true)
    }

    static func join(_ left: String, _ right: String, hyphens: HyphenContext, page: Int,
                     warnings: inout [ConversionWarning]) -> String {
        switch joinOperation(left, right, hyphens: hyphens, page: page, warnings: &warnings) {
        case .space: left + " " + right
        case .concatenate: left + right
        case .removeHyphen: String(left.dropLast()) + right
        }
    }

    static func join(_ left: InlineText, _ right: InlineText, hyphens: HyphenContext, page: Int,
                     sourceBoundary: Int? = nil, warnings: inout [ConversionWarning]) -> InlineText {
        var result = left
        switch joinOperation(left.text, right.text, hyphens: hyphens, page: page, warnings: &warnings) {
        case .space: result.append(InlineText(" "))
        case .concatenate: break
        case .removeHyphen: result.removeLastCharacter()
        }
        if let sourceBoundary { result.elements.append(.sourcePage(sourceBoundary)) }
        result.append(right)
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
