import CoreGraphics
import Foundation
import NaturalLanguage
import PDFKit
import Synchronization

/// Judges whether text inherited over a page-sized image is a plausible transcription of it (#93).
///
/// The CDC comic's layer under each page's artwork reads `sreANee v/eus` for "strange virus" and
/// lacks about half the speech balloons. Three independent tests, any of which fails the layer:
///
/// - **Too few English words.** Whitespace-separated words are sorted into English (a word in the
///   operating system's English lexicon, or `a`/`I`), damage (a lower-case word the lexicon does not
///   know, irregular capitalization such as `sreANee`, a stray lower-case letter from letter-spaced
///   text such as `n e x t`, or letters of another script) and neutral (capitalized or upper-case
///   words the lexicon does not know, which are names and abbreviations, compound names such as
///   `McDonald`, and words broken by symbols). With at least `minimumJudgedWords` English and
///   damaged words, fewer than half English fails. A layer in which a fifth or more of the words
///   carry digits is a table or form and is not judged: statistical tables read below half English,
///   and a fresh recognition of their handwritten cells reads no better.
/// - **Words misread in place (#7).** Under the same conditions, a layer fails when a tenth or more
///   of all its words are damaged words of three or more letters (or irregular capitals) that no
///   neighbour joins into an English word: `tcld t» ftboot` for "told me about" on a carbon
///   typescript, which reads half to three quarters English. Text split inside words
///   (`fi e ld stre ngth`) joins up and is not counted.
/// - **Too little text for the ink.** The page is rendered and its text-shaped ink found as in
///   `OCRTextCoverage`; the layer fails when its lines leave at least three quarters of that ink
///   and at least seven text rows uncovered, and it holds fewer English words than those rows.
///
/// Only English (`en`, `en-*`) is judged; the lexicon is `NLEmbedding.wordEmbedding(for: .english)`
/// (no network or download), and without it only the ink test runs.
///
/// The same ink evidence answers the opposite question (#176): a page with no text layer worth
/// reflowing, whose art is writing, is an image-only page and is recognized like a page with no
/// text layer at all. See `judgeImageOnly`.
enum TextLayerPlausibility {
    enum Finding: Equatable, Sendable {
        /// `english` of `judged` words are English words.
        case fewEnglishWords(english: Int, judged: Int)
        /// The layer's lines leave `uncoveredFraction` of the text-shaped ink, in `uncoveredRows`
        /// rows, uncovered while holding `englishWords` English words.
        case missingText(uncoveredFraction: Double, uncoveredRows: Int, englishWords: Int)
        /// `misread` of `words` words are misread in place; `examples` are the first of them (#7).
        case misreadWords(misread: Int, words: Int, examples: [String])
    }

    struct WordCounts: Equatable, Sendable {
        var english = 0
        var damaged = 0
        var neutral = 0
        /// Whitespace-separated tokens holding a digit, and all non-empty tokens.
        var numericTokens = 0
        var tokens = 0
        /// Damaged words misread in place (`misreadShare`), and the first three of them.
        var misread = 0
        var misreadExamples: [String] = []
        var judged: Int { english + damaged }
        var words: Int { english + damaged + neutral }
    }

    static let minimumJudgedWords = 20
    static let maximumEnglishShare = 0.5
    static let maximumNumericShare = 0.2
    static let minimumMisreadShare = 0.1
    static let minimumUncoveredFraction = 0.75
    static let minimumUncoveredRows = 7
    /// The ink test renders the page, which dominates its cost. A layer fails it only with fewer
    /// English words than uncovered text rows, and no image-backed page surveyed leaves 75% of its
    /// text ink uncovered in more than 27 rows, so a layer with 32 or more English words is not
    /// rendered.
    static let maximumWordsForInkTest = 32
    /// The ink test's resolution, independent of the client's `rasterDPI` so the test does not
    /// change with output policy; the client's pixel ceiling still applies.
    static let inkTestDPI = 180.0

    /// Only English statistics are embedded; other declared languages are not judged.
    static func supports(language: String) -> Bool {
        let primary = language.split(whereSeparator: { $0 == "-" || $0 == "_" }).first?.lowercased()
        return primary == "en" || primary == "eng"
    }

    /// Rows of drawn writing that make a page with no words of its own an image-only page (#176).
    /// One row is a label, an axis or a caption inside a figure, which the figure's own crop
    /// carries; two rows standing outside the layer are writing the page never reflowed.
    static let minimumImageOnlyRows = 2

    /// Whether a page's text layer would reflow no word of its own: it holds no letter (#176).
    ///
    /// A slide whose only sentence is drawn as vector outlines can hold just a folio in its text
    /// layer; furniture removal takes that away, so the page reaches the reader with no text at
    /// all. A page with no text layer is already recognized under an automatic policy, and a
    /// folio does not make the page any less text-less. A bare answer key of fractions and surds
    /// holds no letter either and does reflow, which the ink test below separates.
    static func reflowsNoWords(_ lines: [TextLine]) -> Bool {
        !lines.contains { $0.text.contains(where: \.isLetter) }
    }

    /// Whether such a page's art carries writing: enough rows of text-shaped ink, measured against
    /// the page's own background and away from its photographs, lie outside the layer's lines.
    /// Decorative art and charts of symbols form no such row, so they are never recognized on this
    /// evidence.
    ///
    /// The writing must be what the page itself draws, not what its pictures show. A photograph is
    /// a picture of the world, and the ink test cannot tell a blackboard of arithmetic or a
    /// photograph's own strata from typeset rows. Its crop already preserves it, and recognizing
    /// the page would put the picture's incidental lettering into the reading order and take every
    /// crop away.
    static func carriesDrawnText(_ measurement: OCRTextCoverage.Measurement) -> Bool {
        measurement.uncoveredRows >= minimumImageOnlyRows
    }

    /// Whether a page that reflows no words is an image-only page whose writing should be
    /// recognized. `measureInk` renders the page, measures its lines' coverage and is the caller's
    /// place to set the page's pictures aside. Only books declared English are judged: the rule and
    /// its thresholds were reviewed on English pages alone (#176).
    static func judgeImageOnly(lines: [TextLine], language: String,
                               measureInk: () throws -> OCRTextCoverage.Measurement?) rethrows -> Bool {
        guard supports(language: language), reflowsNoWords(lines),
              let measurement = try measureInk() else { return false }
        return carriesDrawnText(measurement)
    }

    /// The English lexicon, loaded once; nil when the system provides none. Lookups are serialized
    /// because `NLEmbedding` makes no thread-safety promise and conversions can run concurrently.
    private static let lexicon = Mutex<NLEmbedding?>(NLEmbedding.wordEmbedding(for: .english))

    /// Whether the system's English lexicon holds `word` (lowercase); nil when there is none. Line-end
    /// hyphens the book's own words cannot decide consult it (#186).
    static func lexiconContains(_ word: String) -> Bool? {
        lexicon.withLock { embedding in embedding.map { $0.contains(word) } }
    }

    /// Word counts against the system lexicon; nil when there is none.
    static func englishWordCounts(_ text: String) -> WordCounts? {
        lexicon.withLock { embedding in
            guard let embedding else { return nil }
            return wordCounts(text) { embedding.contains($0) }
        }
    }

    static func wordCounts(_ text: String, isWord: (String) -> Bool) -> WordCounts {
        var counts = WordCounts()
        var words: [String] = []
        for token in text.split(whereSeparator: \.isWhitespace) {
            counts.tokens += 1
            if token.contains(where: \.isNumber) { counts.numericTokens += 1 }
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
            }
        }
        // A damaged piece a neighbour joins into a word was split, not misread (`fi e ld stre ngth`).
        func joinsNeighbour(_ index: Int) -> Bool {
            [index - 1, index].contains { start in
                guard start >= 0, start + 1 < words.count else { return false }
                let joined = words[start] + words[start + 1]
                return joined.allSatisfy(\.isLetter) && isWord(joined.lowercased())
            }
        }
        for (index, word) in words.enumerated() {
            // A word holding letters of another script is a misreading in an English text (#7).
            if word.unicodeScalars.contains(where: { $0.properties.isAlphabetic && !isLatinLetter($0) }) {
                counts.damaged += 1
                continue
            }
            guard word.allSatisfy(\.isLetter) else { counts.neutral += 1; continue }
            let lower = word.allSatisfy(\.isLowercase)
            if word.count == 1 {
                if word == "a" || word == "A" || word == "i" || word == "I" { counts.english += 1 }
                else if lower { counts.damaged += 1 } else { counts.neutral += 1 }
                continue
            }
            let upper = word.allSatisfy(\.isUppercase)
            let capitalized = word.first!.isUppercase && word.dropFirst().allSatisfy(\.isLowercase)
            if lower || upper || capitalized, isWord(word.lowercased()) { counts.english += 1; continue }
            // Names and abbreviations the lexicon lacks are neutral, a compound name's capitals too
            // (`McDonald`).
            if !lower && (upper || capitalized || isCompoundName(word)) { counts.neutral += 1; continue }
            counts.damaged += 1
            // Misread in place: a lower-case word of three or more letters, or irregular capitals,
            // that no neighbour completes.
            guard !lower || word.count >= 3, !joinsNeighbour(index) else { continue }
            counts.misread += 1
            if counts.misreadExamples.count < 3 { counts.misreadExamples.append(word) }
        }
        return counts
    }

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
    /// no more than half of its tokens. A proper name or month
    /// the lexicon holds capitalized (`September`) counts as English here. A recognized line must
    /// pass it to become a heading, and so a navigation entry: table cells and a reading of
    /// handwriting set large must not become titles. True without a lexicon when no other script
    /// appears.
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
            return knowsWord && counts.english * 2 >= counts.words && counts.numericTokens * 2 <= counts.tokens
        }
    }

    /// The word test alone.
    static func wordFinding(_ counts: WordCounts) -> Finding? {
        guard counts.judged >= minimumJudgedWords,
              Double(counts.numericTokens) < Double(counts.tokens) * maximumNumericShare else { return nil }
        if Double(counts.english) < Double(counts.judged) * maximumEnglishShare {
            return .fewEnglishWords(english: counts.english, judged: counts.judged)
        }
        if Double(counts.misread) >= Double(counts.words) * minimumMisreadShare {
            return .misreadWords(misread: counts.misread, words: counts.words, examples: counts.misreadExamples)
        }
        return nil
    }

    /// The ink test alone, over a coverage measurement of the layer's lines.
    static func inkFinding(_ measurement: OCRTextCoverage.Measurement, englishWords: Int) -> Finding? {
        guard measurement.uncoveredRows >= minimumUncoveredRows,
              measurement.uncoveredFraction >= minimumUncoveredFraction,
              englishWords < measurement.uncoveredRows else { return nil }
        return .missingText(uncoveredFraction: measurement.uncoveredFraction,
                            uncoveredRows: measurement.uncoveredRows, englishWords: englishWords)
    }

    /// Both tests over an image-backed page's inherited lines; nil when the layer is plausible or
    /// the language is not judged. `measureInk` renders the page and measures the lines' coverage.
    static func judge(lines: [TextLine], language: String,
                      measureInk: () throws -> OCRTextCoverage.Measurement?) rethrows -> Finding? {
        guard !lines.isEmpty, supports(language: language) else { return nil }
        let counts = englishWordCounts(lines.map(\.text).joined(separator: "\n"))
        if let counts, let finding = wordFinding(counts) { return finding }
        let english = counts?.english ?? 0
        guard english < maximumWordsForInkTest, let measurement = try measureInk() else { return nil }
        return inkFinding(measurement, englishWords: english)
    }

    /// Whether recognition of a page reads as English, judged as an inherited layer's words are
    /// (#7); nil when it does, or the language is not judged. Only the English-share test applies:
    /// recognition of a legible page can misread a tenth of its words and still be the best text
    /// the page has, while recognition of handwriting reads under half English. Such a reading is
    /// noise, which serves a reader worse than the page image.
    static func judgeRecognized(lines: [TextLine], language: String) -> Finding? {
        let text = lines.map(\.text).joined(separator: "\n")
        guard !lines.isEmpty, supports(language: language),
              let counts = englishWordCounts(text),
              case .fewEnglishWords(let english, let judged)? = wordFinding(counts),
              !readsAsAnotherLanguage(text) else { return nil }
        return .fewEnglishWords(english: english, judged: judged)
    }

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

    /// Whether recognition reads a page better than a layer that misreads `misread` of its `words`
    /// words (#7): it reads as English (`judgeRecognized`) and misreads a smaller share of its own.
    static func readsBetter(_ lines: [TextLine], than misread: Int, of words: Int, language: String) -> Bool {
        guard judgeRecognized(lines: lines, language: language) == nil,
              let counts = englishWordCounts(lines.map(\.text).joined(separator: "\n")), counts.words > 0 else { return false }
        return Double(counts.misread) / Double(counts.words) < Double(misread) / Double(max(1, words))
    }

    /// The `implausibleRecognition` warning for a page whose recognition was discarded.
    static func recognitionMessage(_ finding: Finding) -> String {
        guard case .fewEnglishWords(let english, let judged) = finding else { return "" }
        return "OCR of this page image does not read as English: only \(english) of \(judged) words are English words "
            + "(handwriting, or print recognition cannot read). The recognized text was discarded; "
            + "the page is preserved as an image and does not reflow."
    }

    /// Text-shaped ink outside `lines` on the rendered page, ignoring anything inside `excluding`.
    static func measureInk(page: PDFPage, bounds: CGRect, lines: [TextLine], excluding: [CGRect] = [],
                           options: ConversionOptions) throws -> OCRTextCoverage.Measurement? {
        var rasterOptions = options
        rasterOptions.rasterDPI = inkTestDPI
        let image = try PageRasterizer.image(page: page, rect: bounds, options: rasterOptions)
        func normalize(_ rect: CGRect) -> CGRect {
            CGRect(x: (rect.minX - bounds.minX) / bounds.width, y: (rect.minY - bounds.minY) / bounds.height,
                   width: rect.width / bounds.width, height: rect.height / bounds.height)
        }
        return OCRTextCoverage.measure(image: image, lines: lines.map { normalize($0.rect) },
                                       excluded: excluding.map(normalize),
                                       pixelsPerPoint: Double(image.width) / bounds.width)
    }

    /// What became of a failing layer.
    enum Outcome: Sendable {
        /// Recognition of the page image replaced it.
        case replaced
        /// It was discarded for recognition, which failed or found no text: the page is an image.
        case pageImage
        /// It was discarded for recognition, which read no better (`judgeRecognized`): the page is an image.
        case implausibleRecognition
        /// A misread layer was compared with recognition of the page image, which failed or read no
        /// better (`readsBetter`), so it was kept.
        case keptOverRecognition
        /// The OCR policy kept it.
        case retained
    }

    /// The `implausibleTextLayer` warning: what failed, and what the conversion did about it.
    static func message(_ finding: Finding, outcome: Outcome, referencesDisabled: Bool) -> String {
        let problem: String
        switch finding {
        case .fewEnglishWords(let english, let judged):
            problem = "Existing text over a page-sized image does not read as English: only \(english) of \(judged) words "
                + "are English words (misspelled, wrongly capitalized or letter-spaced text)."
        case .missingText(let fraction, let rows, let english):
            let percent = min(100, max(75, Int((fraction * 100).rounded(.down))))
            problem = "Existing text over a page-sized image is missing most of the page's text: about \(percent)% of the "
                + "page's text-shaped ink (\(rows) rows) lies outside its lines, which hold \(english) English "
                + (english == 1 ? "word." : "words.")
        case .misreadWords(let misread, let words, let examples):
            problem = "Existing text over a page-sized image is a damaged transcription: \(misread) of its \(words) words are "
                + "misread, not English words or names (such as " + examples.map { "\u{201C}\($0)\u{201D}" }.joined(separator: ", ") + ")."
        }
        switch outcome {
        case .replaced:
            return problem + " The existing text was discarded and replaced by OCR of the page image; review this page against "
                + (referencesDisabled ? "the source PDF." : "the original page image.")
        case .pageImage:
            return problem + " The existing text was discarded, but OCR of the page image failed or found no text, so the "
                + "page is preserved as an image."
        case .implausibleRecognition:
            return problem + " The existing text was discarded, but OCR of the page image does not read as English either, so "
                + "the page is preserved as an image and does not reflow."
        case .keptOverRecognition:
            return problem + " The page image was recognized again, but OCR failed or read it no better, so the existing text "
                + "is retained; read " + (referencesDisabled ? "the source PDF instead." : "the accompanying original page image instead.")
        case .retained:
            return problem + " The existing text is retained because the OCR policy keeps it; read "
                + (referencesDisabled ? "the source PDF instead." : "the accompanying original page image instead.")
        }
    }
}
