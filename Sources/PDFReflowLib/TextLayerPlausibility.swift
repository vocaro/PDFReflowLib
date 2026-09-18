import CoreGraphics
import Foundation
import NaturalLanguage
import PDFKit
import Synchronization

/// Judges whether text inherited over a page-sized image is a plausible transcription of it (#93).
///
/// The CDC comic's layer under each page's artwork reads `sreANee v/eus` for "strange virus" and
/// lacks about half the speech balloons. Two independent tests, either of which fails the layer:
///
/// - **Too few English words.** Whitespace-separated words are sorted into English (a word in the
///   operating system's English lexicon, or `a`/`I`), damage (a lower-case word the lexicon does not
///   know, irregular capitalization such as `sreANee`, or a stray lower-case letter from letter-spaced
///   text such as `n e x t`) and neutral (capitalized or upper-case words the lexicon does not know,
///   which are names and abbreviations, and words broken by symbols). With at least
///   `minimumJudgedWords` English and damaged words, fewer than half English fails. A layer in
///   which a fifth or more of the words carry digits is a table or form and is not judged: the
///   Blue Book's statistical tables read below half English, and a fresh recognition of their
///   handwritten cells reads no better (`measurements/text-layer-plausibility/record.md`).
/// - **Too little text for the ink.** The page is rendered and its text-shaped ink found as in
///   `OCRTextCoverage`; the layer fails when its lines leave at least three quarters of that ink
///   and at least seven text rows uncovered, and it holds fewer English words than those rows.
///
/// Only English (`en`, `en-*`) is judged; the lexicon is `NLEmbedding.wordEmbedding(for: .english)`
/// (57,171 words on macOS 27; no network or download), and without it only the ink test runs.
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
    }

    struct WordCounts: Equatable, Sendable {
        var english = 0
        var damaged = 0
        var neutral = 0
        /// Whitespace-separated tokens holding a digit, and all non-empty tokens.
        var numericTokens = 0
        var tokens = 0
        var judged: Int { english + damaged }
    }

    static let minimumJudgedWords = 20
    static let maximumEnglishShare = 0.5
    static let maximumNumericShare = 0.2
    static let minimumUncoveredFraction = 0.75
    static let minimumUncoveredRows = 7
    /// The ink test renders the page, which dominates its cost (about 0.5 s for a Warren scan, 70 ms
    /// for a Blue Book page). A layer fails it only with fewer English words than uncovered text rows,
    /// and no image-backed page in the English corpus leaves 75% of its text ink uncovered in more
    /// than 27 rows, so a layer with 32 or more English words is not rendered.
    static let maximumWordsForInkTest = 32
    /// The ink test's resolution, independent of the client's `rasterDPI` so the test does not
    /// change with output policy; the client's pixel ceiling still applies.
    static let inkTestDPI = 180.0

    /// Rows of drawn writing that make a page with no words of its own an image-only page (#176).
    /// One row is a label, an axis or a caption inside a figure, which the figure's own crop
    /// carries; two rows standing outside the layer are writing the page never reflowed. Slide 5
    /// of the Earthdata deck, the corpus's only such page, shows three.
    static let minimumImageOnlyRows = 2

    /// Whether a page's text layer would reflow no word of its own: it holds no letter (#176).
    ///
    /// The Earthdata deck's slide 5 draws its only sentence as vector outlines, and its text layer
    /// holds the folio `5` and nothing else; furniture removal takes that away, so the slide
    /// reaches the reader with no text at all. A page with no text layer is already recognized
    /// under an automatic policy, and a folio does not make the page any less text-less. Answer
    /// keys of bare fractions and surds (*Beginning and Intermediate Algebra* pages 309 and 439)
    /// hold no letter either and do reflow, which the ink test below separates.
    static func reflowsNoWords(_ lines: [TextLine]) -> Bool {
        !lines.contains { $0.text.contains(where: \.isLetter) }
    }

    /// Whether such a page's art carries writing: enough rows of text-shaped ink, measured against
    /// the page's own background and away from its photographs, lie outside the layer's lines.
    /// Decorative art and charts of symbols form no such row, so they are never recognized on this
    /// evidence.
    ///
    /// The writing must be what the page itself draws, not what its pictures show. A photograph is
    /// a picture of the world, and the ink test cannot tell a blackboard of arithmetic or the
    /// strata of Mount Rushmore (the Arabic civics cards' pages 62 and 88) from typeset rows.
    /// Its crop already preserves it, and recognizing the page would put the picture's incidental
    /// lettering into the reading order and take every crop away.
    static func carriesDrawnText(_ measurement: OCRTextCoverage.Measurement) -> Bool {
        measurement.uncoveredRows >= minimumImageOnlyRows
    }

    /// Whether a page that reflows no words is an image-only page whose writing should be
    /// recognized. `measureInk` renders the page, measures its lines' coverage and is the caller's
    /// place to set the page's pictures aside. Only books declared English are judged: the rule and
    /// its thresholds were reviewed on English pages alone (#176).
    static func judgeImageOnly(lines: [TextLine], language: String,
                               measureInk: () throws -> OCRTextCoverage.Measurement?) rethrows -> Bool {
        guard TextEncodingCheck.supports(language: language), reflowsNoWords(lines),
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
                guard word.allSatisfy(\.isLetter) else { counts.neutral += 1; continue }
                let lower = word.allSatisfy(\.isLowercase)
                if word.count == 1 {
                    if word == "a" || word == "A" || word == "i" || word == "I" { counts.english += 1 }
                    else if lower { counts.damaged += 1 } else { counts.neutral += 1 }
                    continue
                }
                let upper = word.allSatisfy(\.isUppercase)
                let capitalized = word.first!.isUppercase && word.dropFirst().allSatisfy(\.isLowercase)
                guard lower || upper || capitalized else { counts.damaged += 1; continue }
                if isWord(word.lowercased()) { counts.english += 1 }
                else if lower { counts.damaged += 1 } else { counts.neutral += 1 }
            }
        }
        return counts
    }

    /// The word test alone.
    static func wordFinding(_ counts: WordCounts) -> Finding? {
        guard counts.judged >= minimumJudgedWords,
              Double(counts.numericTokens) < Double(counts.tokens) * maximumNumericShare,
              Double(counts.english) < Double(counts.judged) * maximumEnglishShare else { return nil }
        return .fewEnglishWords(english: counts.english, judged: counts.judged)
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
        guard !lines.isEmpty, TextEncodingCheck.supports(language: language) else { return nil }
        let counts = englishWordCounts(lines.map(\.text).joined(separator: "\n"))
        if let counts, let finding = wordFinding(counts) { return finding }
        let english = counts?.english ?? 0
        guard english < maximumWordsForInkTest, let measurement = try measureInk() else { return nil }
        return inkFinding(measurement, englishWords: english)
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
        }
        switch outcome {
        case .replaced:
            return problem + " The existing text was discarded and replaced by OCR of the page image; review this page against "
                + (referencesDisabled ? "the source PDF." : "the original page image.")
        case .pageImage:
            return problem + " The existing text was discarded, but OCR of the page image failed or found no text, so the "
                + "page is preserved as an image."
        case .retained:
            return problem + " The existing text is retained because the OCR policy keeps it; read "
                + (referencesDisabled ? "the source PDF instead." : "the accompanying original page image instead.")
        }
    }
}
