import CoreGraphics
import Foundation
import PDFKit

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
///   neighbor joins into an English word: `tcld t» ftboot` for "told me about" on a carbon
///   typescript, which reads half to three quarters English. Text split inside words
///   (`fi e ld stre ngth`) joins up and is not counted.
/// - **Too little text for the ink.** The page is rendered and its text-shaped ink found as in
///   `OCRTextCoverage`; the layer fails when its lines leave at least three quarters of that ink
///   and at least seven text rows uncovered, and it holds fewer English words than those rows.
///
/// Only English (`en`, `en-*`) is judged; the lexicon and the word classification are
/// `EnglishText`'s (no network or download), and without a lexicon only the ink test runs.
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

    typealias WordCounts = EnglishText.WordCounts

    static let minimumJudgedWords = 20
    static let minimumEnglishShare = 0.5
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
        guard EnglishText.isDeclared(language), reflowsNoWords(lines),
              let measurement = try measureInk() else { return false }
        return carriesDrawnText(measurement)
    }

    /// The word test alone.
    static func wordFinding(_ counts: WordCounts) -> Finding? {
        guard counts.judged >= minimumJudgedWords,
              Double(counts.numericTokens) < Double(counts.tokens) * maximumNumericShare else { return nil }
        if Double(counts.english) < Double(counts.judged) * minimumEnglishShare {
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
        guard !lines.isEmpty, EnglishText.isDeclared(language) else { return nil }
        let counts = EnglishText.wordCounts(lines.map(\.text).joined(separator: "\n"))
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
        guard !lines.isEmpty, EnglishText.isDeclared(language),
              let counts = EnglishText.wordCounts(text),
              case .fewEnglishWords(let english, let judged)? = wordFinding(counts),
              !EnglishText.readsAsAnotherLanguage(text) else { return nil }
        return .fewEnglishWords(english: english, judged: judged)
    }

    /// Whether recognition reads a page better than a layer that misreads `misread` of its `words`
    /// words (#7): it reads as English (`judgeRecognized`) and misreads a smaller share of its own.
    static func readsBetter(_ lines: [TextLine], than misread: Int, of words: Int, language: String) -> Bool {
        guard judgeRecognized(lines: lines, language: language) == nil,
              let counts = EnglishText.wordCounts(lines.map(\.text).joined(separator: "\n")), counts.words > 0 else { return false }
        return Double(counts.misread) / Double(counts.words) < Double(misread) / Double(max(1, words))
    }

    /// The `implausibleRecognition` warning for a page whose recognition was discarded.
    static func recognitionMessage(_ finding: Finding) -> String {
        guard case .fewEnglishWords(let english, let judged) = finding else { return "" }
        return "OCR of this page image does not read as English: only \(english) of \(judged) words are English words "
            + "(handwriting, or print recognition cannot read). The recognized text was discarded; "
            + "the page is preserved as an image and does not reflow."
    }

    /// The page rendered at the ink test's resolution; the client's pixel ceiling still applies.
    static func inkImage(page: PDFPage, bounds: CGRect, options: ConversionOptions) throws -> CGImage {
        var rasterOptions = options
        rasterOptions.rasterDPI = inkTestDPI
        return try PageRasterizer.image(page: page, rect: bounds, options: rasterOptions)
    }

    /// Text-shaped ink outside `lines` on the rendered page, ignoring anything inside `excluding`.
    static func measureInk(image: CGImage, bounds: CGRect, lines: [TextLine],
                           excluding: [CGRect] = []) -> OCRTextCoverage.Measurement? {
        func normalize(_ rect: CGRect) -> CGRect {
            CGRect(x: (rect.minX - bounds.minX) / bounds.width, y: (rect.minY - bounds.minY) / bounds.height,
                   width: rect.width / bounds.width, height: rect.height / bounds.height)
        }
        return OCRTextCoverage.measure(image: image, boxes: lines.map { normalize($0.rect) },
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
        /// A page whose only writing is drawn was recognized, which failed or read nothing, so the
        /// page kept the text and crops it was extracted with (#176, #220).
        case keptAsExtracted
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
        case .keptAsExtracted:
            // The page keeps whatever extraction gave it, which need not include a page reference,
            // so this outcome promises the reader no accompanying image.
            return problem + " The page was recognized because its artwork holds writing, but OCR failed or found no text, "
                + "so the page keeps the text and image crops it was extracted with; the writing in its artwork does not reflow."
        case .retained:
            return problem + " The existing text is retained because the OCR policy keeps it; read "
                + (referencesDisabled ? "the source PDF instead." : "the accompanying original page image instead.")
        }
    }
}
