import Foundation
import NaturalLanguage
import Synchronization

/// The English-language judgments the conversion makes, in one place: which declared languages
/// are judged at all, the system lexicon and the word classification over it, and the two rules
/// built on that classification. A third rule, `TextEncodingCheck.isImplausible`, reads function
/// words and letter pairs instead of the lexicon, because the text it judges is not made of words
/// the lexicon could hold; it shares only `isDeclared` with the rules here.
///
/// The rules differ by design:
/// - `TextLayerPlausibility.wordFinding` judges an inherited text layer (#93, #7): at least
///   `minimumJudgedWords` judged words, fewer than a fifth of tokens numbers, at least half
///   English, and under a tenth misread in place. It sets a lone `a`/`I` with no word for company
///   aside first (`lonelyLetters`, #275).
/// - `readsAsWords` judges one recognized line before it may become a heading (#7): no letter of
///   another script, at least one known word, English at least half of all words (neutral words
///   count against it), and digits in no more than half of the tokens; a capitalized lexicon entry
///   counts as English here.
enum EnglishText {
    /// Only English statistics are embedded; other declared languages (`fr`, `zh-Hans`) are not
    /// judged. Accepts `en`, `en-*`, `en_*` and `eng`.
    static func isDeclared(_ language: String) -> Bool {
        let primary = language.split(whereSeparator: { $0 == "-" || $0 == "_" }).first?.lowercased()
        return primary == "en" || primary == "eng"
    }

    struct WordCounts: Equatable, Sendable {
        var english = 0
        var damaged = 0
        var neutral = 0
        /// Whitespace-separated tokens holding a digit, and all non-empty tokens.
        var numericTokens = 0
        /// Tokens holding a digit and no letter: the numbers the text actually states, as against
        /// `numericTokens`, which a misreading of a figure (`l6`, `0,3`, `A.Di`) joins as readily
        /// as a figure does (#275).
        var numberTokens = 0
        var tokens = 0
        /// English words among `english` that are a bare `a` or `I` standing on a line that holds
        /// no other English word (#275). A lone letter is a word only in the company of words;
        /// alone on its line it is a rule, a tick or a tally the reading shaped like a letter.
        var lonelyLetters = 0
        /// Damaged words misread in place (`misreadShare`), and the first three of them.
        var misread = 0
        var misreadExamples: [String] = []
        var judged: Int { english + damaged }
        var words: Int { english + damaged + neutral }
    }

    /// The English lexicon, loaded once; nil when the system provides none. Lookups are serialized
    /// because `NLEmbedding` makes no thread-safety promise and conversions can run concurrently.
    private static let lexicon = Mutex<NLEmbedding?>(NLEmbedding.wordEmbedding(for: .english))

    /// Whether the system's English lexicon holds `word` (lowercase); nil when there is none. Line-end
    /// hyphens the book's own words cannot decide consult it (#186).
    static func lexiconContains(_ word: String) -> Bool? {
        lexicon.withLock { embedding in embedding.map { $0.contains(word) } }
    }

    /// Conservative lexical corroboration for a line-break join and for source-font census
    /// calibration. Keeping this extraction-safe predicate here lets standalone native-text
    /// probes use the census without depending on the reconstruction pipeline.
    static func vouchesForHyphenJoin(prefix: String, suffix: String) -> Bool {
        guard prefix.count >= 2, suffix.count >= 2, prefix.count + suffix.count >= 6,
              lexiconContains(prefix + suffix) == true else { return false }
        return !(lexiconContains(prefix) == true && lexiconContains(suffix) == true)
    }

    /// The longest English word of three letters or more that opens `text`, or nil.
    ///
    /// A run the source draws against the number before it is a word the page set tight, not the
    /// next term of a formula: `8cent stamps` opens with `cent` and Wallace's `30qpr` opens with
    /// nothing, which is what tells a missing space from algebra (#120, #139). Three letters is
    /// the floor because a one- or two-letter opening is a variable as often as a word. At most
    /// twelve are tried, and a lexicon the system does not provide answers nil.
    static func openingWord(_ text: some StringProtocol, minimum: Int = 3, maximum: Int = 12) -> String? {
        let letters = text.prefix(while: \.isLetter).lowercased()
        guard letters.count >= minimum else { return nil }
        return lexicon.withLock { embedding in
            guard let embedding else { return nil }
            for length in stride(from: min(maximum, letters.count), through: minimum, by: -1) {
                let candidate = String(letters.prefix(length))
                if embedding.contains(candidate) { return candidate }
            }
            return nil
        }
    }

    /// Word counts against the system lexicon; nil when there is none.
    static func wordCounts(_ text: String) -> WordCounts? {
        lexicon.withLock { embedding in
            guard let embedding else { return nil }
            return wordCounts(text) { embedding.contains($0) }
        }
    }

    /// Whitespace-separated words sorted into English (a word `isWord` knows, or `a`/`I`), damaged
    /// (a lower-case word it does not know, irregular capitalization such as `sreANee`, a stray
    /// lower-case letter from letter-spaced text such as `n e x t`, or letters of another script)
    /// and neutral (capitalized or upper-case words it does not know, which are names and
    /// abbreviations, compound names such as `McDonald`, and words broken by symbols).
    static func wordCounts(_ text: String, isWord: (String) -> Bool) -> WordCounts {
        var counts = WordCounts()
        var words: [String] = []
        // The line each word was read on, so a lone letter can be asked what company it keeps
        // (#275). Splitting on newlines and then on whitespace yields the same tokens, in the
        // same order, as splitting on whitespace alone.
        var linesOfWords: [Int] = []
        for (line, row) in text.split(whereSeparator: \.isNewline).enumerated() {
            for token in row.split(whereSeparator: \.isWhitespace) {
                counts.tokens += 1
                if token.contains(where: \.isNumber) {
                    counts.numericTokens += 1
                    if !token.contains(where: \.isLetter) { counts.numberTokens += 1 }
                }
                var piece = Substring(token)
                while let first = piece.first, !first.isLetter { piece = piece.dropFirst() }
                while let last = piece.last, !last.isLetter { piece = piece.dropLast() }
                guard !piece.isEmpty else { continue }
                for part in piece.split(separator: "-") {
                    var word = part.replacingOccurrences(of: "\u{2019}", with: "'")
                    for clitic in ["'s", "n't", "'ll", "'re", "'ve", "'m", "'d"]
                    where word.count > clitic.count && word.lowercased().hasSuffix(clitic) {
                        word.removeLast(clitic.count)
                        break
                    }
                    words.append(word)
                    linesOfWords.append(line)
                }
            }
        }
        // A damaged piece a neighbor joins into a word was split, not misread (`fi e ld stre ngth`).
        func joinsNeighbour(_ index: Int) -> Bool {
            [index - 1, index].contains { start in
                guard start >= 0, start + 1 < words.count else { return false }
                let joined = words[start] + words[start + 1]
                return joined.allSatisfy(\.isLetter) && isWord(joined.lowercased())
            }
        }
        // Bare `a`/`I` per line, and the lines on which some other word reads as English (#275).
        var bareLetters: [Int: Int] = [:]
        var linesWithAWord: Set<Int> = []
        for (index, word) in words.enumerated() {
            // A word holding letters of another script is a misreading in an English text (#7).
            if word.unicodeScalars.contains(where: { $0.properties.isAlphabetic && !isLatinLetter($0) }) {
                counts.damaged += 1
                continue
            }
            guard word.allSatisfy(\.isLetter) else { counts.neutral += 1; continue }
            let lower = word.allSatisfy(\.isLowercase)
            if word.count == 1 {
                if word == "a" || word == "A" || word == "i" || word == "I" {
                    counts.english += 1
                    bareLetters[linesOfWords[index], default: 0] += 1
                }
                else if lower { counts.damaged += 1 } else { counts.neutral += 1 }
                continue
            }
            let upper = word.allSatisfy(\.isUppercase)
            let capitalized = word.first!.isUppercase && word.dropFirst().allSatisfy(\.isLowercase)
            if lower || upper || capitalized, isWord(word.lowercased()) {
                counts.english += 1
                linesWithAWord.insert(linesOfWords[index])
                continue
            }
            // Names and abbreviations the lexicon lacks are neutral, a compound name's capitals too
            // (`McDonald`).
            if !lower && (upper || capitalized || isCompoundName(word)) { counts.neutral += 1; continue }
            counts.damaged += 1
            // Misread in place: a lower-case word of three or more letters, or irregular capitals,
            // that no neighbor completes.
            guard !lower || word.count >= minimumMisreadWordLength, !joinsNeighbour(index) else { continue }
            counts.misread += 1
            if counts.misreadExamples.count < misreadExampleLimit { counts.misreadExamples.append(word) }
        }
        counts.lonelyLetters = bareLetters.filter { !linesWithAWord.contains($0.key) }.values.reduce(0, +)
        return counts
    }

    /// A lower-case damaged word shorter than this is a fragment, not a misreading.
    static let minimumMisreadWordLength = 3
    /// How many misread words a finding quotes.
    static let misreadExampleLimit = 3

    /// Capitalized parts of two or more letters each, run together as names are (`McDonald`,
    /// `DeLoach`): irregular capitals, but not a misreading.
    static func isCompoundName(_ word: String) -> Bool {
        var parts: [String] = []
        for letter in word {
            if letter.isUppercase || parts.isEmpty { parts.append(String(letter)) } else { parts[parts.count - 1].append(letter) }
        }
        return parts.count > 1 && parts.allSatisfy { part in
            part.count >= 2 && part.first!.isUppercase && part.dropFirst().allSatisfy(\.isLowercase)
        }
    }

    /// Whether `scalar` is a letter of the Latin script: Basic Latin through Latin Extended-B, the
    /// IPA extensions, Latin Extended Additional and the Latin ligatures.
    static func isLatinLetter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0...0x2AF, 0x1D00...0x1DBF, 0x1E00...0x1EFF, 0x2C60...0x2C7F, 0xA720...0xA7FF, 0xFB00...0xFB06: true
        default: false
        }
    }

    /// Letters of another script in an English transcription: what recognition makes of handwriting
    /// and art it cannot read.
    static func foreignLetters(_ text: String) -> Int {
        text.unicodeScalars.filter { $0.properties.isAlphabetic && !isLatinLetter($0) }.count
    }

    /// Whether a line of transcription reads as English words (#7): no letter of another script, an
    /// English word of two or more letters, English words at least half of its words, and digits in
    /// no more than half of its tokens. A proper name or month the lexicon holds capitalized
    /// (`September`) counts as English here. A recognized line must pass it to become a heading,
    /// and so a navigation entry: table cells and a reading of handwriting set large must not
    /// become titles. True without a lexicon when no other script appears.
    static func readsAsWords(_ text: String) -> Bool {
        guard foreignLetters(text) == 0 else { return false }
        return lexicon.withLock { embedding in
            guard let embedding else { return true }
            // A lone `a` or `I` is no evidence: `a0 0.0` and `24:5i2` are digits misread.
            var knowsWord = false
            let counts = wordCounts(text) { word in
                let known = embedding.contains(word) || embedding.contains(word.prefix(1).uppercased() + word.dropFirst())
                knowsWord = knowsWord || known
                return known
            }
            return knowsWord && counts.english * lineEnglishDivisor >= counts.words
                && counts.numericTokens * lineNumericDivisor <= counts.tokens
        }
    }

    /// `readsAsWords` needs English words to be at least one in this many of all words, and
    /// numeric tokens at most one in this many of all tokens: half, and half.
    static let lineEnglishDivisor = 2
    static let lineNumericDivisor = 2

    /// Whether text that is not English is confidently another language: a page in French is text,
    /// not noise, even in a book declared English (the default). The system's language recognizer
    /// must name one language other than English with at least `minimumOtherLanguageConfidence`.
    static func readsAsAnotherLanguage(_ text: String) -> Bool {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first else { return false }
        return language != .english && confidence >= minimumOtherLanguageConfidence
    }

    static let minimumOtherLanguageConfidence = 0.95
}
