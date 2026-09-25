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
///   `McDonald`, and words broken by symbols). A bare `a` or `I` standing on a line that holds no
///   other English word is set aside before the count: alone on its line it is a ruled column, a
///   tick or a tally the reading shaped like a letter, not a word (#275). With at least
///   `minimumJudgedWords` English and damaged words left, fewer than half English fails. A layer
///   in which a fifth or more of the tokens are numbers is a table or form and is not judged:
///   statistical tables read below half English, and a fresh recognition of their handwritten
///   cells reads no better. The exemption counts the numbers the page states, not every token
///   holding a digit, because a misreading of a hand-written figure (`l6`, `0,3`, `A.Di`) holds
///   digits too and would otherwise buy the page its own exemption (#275).
/// - **Words misread in place (#7, #216).** Under the same conditions, a prose layer fails when
///   8.5% or more of all its words are damaged words of three or more letters (or irregular capitals) that no
///   neighbor joins into an English word: `tcld t» ftboot` for "told me about" on a carbon
///   typescript, which reads half to three quarters English. Text split inside words
///   (`fi e ld stre ngth`) joins up and is not counted. A digit-heavy page keeps the 10% cut.
/// - **Too little text for the ink.** The page is rendered and its text-shaped ink found as in
///   `OCRTextCoverage`; the layer fails when its lines leave at least three quarters of that ink
///   and at least seven text rows uncovered, and it holds fewer English words than those rows.
///
/// A sparse layer that passes all three is checked against recognition of its page
/// (`sparseEnglishWords`, #216): handwriting whose layer only looks plausible in aggregate reads as
/// noise there. A recognition too short to judge alone is judged beside the layer's own words
/// (`judgeRecognized(lines:besideLayer:language:)`).
///
/// Only English (`en`, `en-*`) inherited layers are judged; the lexicon and word classification are
/// `EnglishText`'s (no network or download), and without a lexicon only the ink test runs.
///
/// The same ink evidence also finds drawn writing beside a folio or a lone word (#176, #192).
/// That separate geometry-only test is language-independent. See `judgeImageOnly`.
enum TextLayerPlausibility {
    enum Finding: Equatable, Sendable {
        /// `english` of `judged` words are English words.
        case fewEnglishWords(english: Int, judged: Int)
        /// The layer's lines leave `uncoveredFraction` of the text-shaped ink, in `uncoveredRows`
        /// rows, uncovered while holding `englishWords` English words.
        case missingText(uncoveredFraction: Double, uncoveredRows: Int, englishWords: Int)
        /// `misread` of `words` words are misread in place; `examples` are the first of them (#7).
        case misreadWords(misread: Int, words: Int, examples: [String])
        /// A sparse layer holding `englishWords` English words passed every test above, but
        /// recognition of its page does not read as English: the page's writing is handwriting,
        /// or print recognition cannot read, and the layer transcribes little of it (#216). Found
        /// only once recognition has run (`RecognitionPlan.Mode.verify`), never by `judge`.
        case unreadWriting(englishWords: Int)
        /// A recognition too short to judge alone reads `english` of `judged` words as English, and
        /// the sparse layer it verifies `layerEnglish` of `layerJudged`: each under half, and
        /// together enough words to judge (#216). Found only by `judgeRecognized(lines:besideLayer:language:)`.
        case fewEnglishWordsInEitherReading(english: Int, judged: Int, layerEnglish: Int, layerJudged: Int)
    }

    typealias WordCounts = EnglishText.WordCounts

    static let minimumJudgedWords = 20
    static let minimumEnglishShare = 0.5
    static let maximumNumericShare = 0.2
    // The Warren carbon typescripts on pages 649, 655, 657, 659 and 661 score 8.7–9.7%.
    // In the source survey, the highest unaffected Blue Book page scored 8.0% and NBS 6.0%.
    // Leave a margin above those controls while admitting the damaged typescripts (#216).
    static let minimumMisreadShare = 0.085
    // CDC 22's inherited layer is only 43 of 75 judged words English and misreads 7 of 88
    // words in place. Its 7.95% misread share falls just below the ordinary cut, but the two
    // kinds of damage corroborate each other: the page is neither reliable prose nor a page
    // of names. Keep this combined cut above the ordinary table controls' word damage unless
    // the English share also fails the stricter 60% check (#168).
    static let minimumMisreadShareWithLowEnglish = 0.075
    static let maximumEnglishShareForCombinedMisread = 0.6
    // Numeric table text can hold misread words among correctly copied column labels. Keep its
    // older, more conservative misread cut: the historical Blue Book survey has 18 table pages
    // between 8.5% and 10%, all with at least a fifth of tokens holding digits. The separate
    // #275 word-share test still judges their handwriting where the numbers themselves are noise.
    static let minimumMisreadShareForNumericPages = 0.1
    static let minimumUncoveredFraction = 0.75
    static let minimumUncoveredRows = 7
    /// A short recognition has too few words for the inherited-layer word-share rule. Several
    /// letters of another script, making up at least a tenth of its writing, and more than a
    /// third damaged words together are stronger evidence of OCR noise than its raw word count.
    /// Warren 555 (a handwritten hospital note) has 6 English of 11 judged words and 11 foreign
    /// letters of 97; Warren 239's recognized diagram labels have 7 of 11 and 11 of 86 (#216).
    static let minimumShortRecognitionWords = 5
    static let minimumShortRecognitionForeignLetters = 5
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

    /// A lone word is no more proof of a complete layer than a folio (#192). The
    /// gate counts letter runs, independent of the declared language or a lexicon. A URL
    /// and a multiword title are not lone words: recognizing those pages on this weak ink
    /// evidence would pull map labels and vector-seal lettering into prose. A single run's
    /// length is bounded as well, since CJK sentences need not have spaces between words.
    static func judgeImageOnly(lines: [TextLine], language: String,
                               measureInk: () throws -> OCRTextCoverage.Measurement?) rethrows -> Bool {
        let words = lines.flatMap { $0.text.split(whereSeparator: { !$0.isLetter }) }
        guard words.count <= 1, (words.first?.count ?? 0) <= 32,
              let measurement = try measureInk() else { return false }
        return carriesDrawnText(measurement)
    }

    /// The word test alone. A lone letter with no word for company is set aside first (#275).
    static func wordFinding(_ counts: WordCounts) -> Finding? {
        let english = counts.english - counts.lonelyLetters
        let judged = counts.judged - counts.lonelyLetters
        guard judged >= minimumJudgedWords,
              Double(counts.numberTokens) < Double(counts.tokens) * maximumNumericShare else { return nil }
        if Double(english) < Double(judged) * minimumEnglishShare {
            return .fewEnglishWords(english: english, judged: judged)
        }
        let numeric = Double(counts.numericTokens) >= Double(counts.tokens) * maximumNumericShare
        let misreadCut = numeric ? minimumMisreadShareForNumericPages : minimumMisreadShare
        let combinedDamage = !numeric
            && Double(english) < Double(judged) * maximumEnglishShareForCombinedMisread
            && Double(counts.misread) >= Double(counts.words) * minimumMisreadShareWithLowEnglish
        if Double(counts.misread) >= Double(counts.words) * misreadCut || combinedDamage {
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
        // The ink test's gate is a cost ceiling surveyed over raw English word counts, so it is
        // read raw: #275 narrowed what the word tests count, not what a page costs to render.
        let english = counts?.english ?? 0
        guard english < maximumWordsForInkTest, let measurement = try measureInk() else { return nil }
        return inkFinding(measurement, englishWords: english)
    }

    /// The English words of a sparse inherited layer, nil when the layer is not one: an English
    /// layer holding fewer than `maximumWordsForInkTest` English words (#216). Such a layer can
    /// pass every test above and still transcribe almost nothing of its page. On the Warren report's handwritten exhibits the
    /// layer is the printed title and caption plus a few symbol-broken tokens over the handwriting
    /// (`^<^ ,7^^Crt^`), which the word tests count as neutral names; cursive strokes are not
    /// glyph-shaped, so the ink test finds few rows to leave uncovered. The text and the ink alone
    /// do not separate those pages from the photographs, diagrams and floor plans whose sparse
    /// layers are their labels (`measurements/issue-216-handwriting-gap`), but recognition of the
    /// page does: it reads a printed page's labels as English and handwriting as noise. A sparse
    /// layer is therefore recognized under the judging policy, and kept unless that recognition
    /// does not read as English (`judgeRecognized`). The word count is read raw, as the ink test's
    /// gate is, and a dense layer is never verified: a typescript's layer is far above it.
    static func sparseEnglishWords(lines: [TextLine], language: String) -> Int? {
        sparseLayerCounts(lines: lines, language: language)?.english
    }

    /// The word counts of a sparse inherited layer (`sparseEnglishWords`), nil when the layer is
    /// not one. A recognition too short to judge alone is judged beside them (#216).
    static func sparseLayerCounts(lines: [TextLine], language: String) -> WordCounts? {
        guard !lines.isEmpty, EnglishText.isDeclared(language),
              let counts = EnglishText.wordCounts(lines.map(\.text).joined(separator: "\n")),
              counts.english < maximumWordsForInkTest else { return nil }
        return counts
    }

    /// Whether recognition of a page reads as English, judged as an inherited layer's words are
    /// (#7, #216); nil when it does, or the language is not judged. The English-share test applies:
    /// recognition of a legible page can misread a tenth of its words and still be the best text
    /// the page has, while recognition of handwriting reads under half English. Such a reading is
    /// noise, which serves a reader worse than the page image. A short result needs the separate
    /// mixed-script evidence below because its handful of guessed words makes that share unstable.
    static func judgeRecognized(lines: [TextLine], language: String) -> Finding? {
        let text = lines.map(\.text).joined(separator: "\n")
        guard !lines.isEmpty, EnglishText.isDeclared(language),
              let counts = EnglishText.wordCounts(text),
              !EnglishText.readsAsAnotherLanguage(text) else { return nil }
        if case .fewEnglishWords(let english, let judged)? = wordFinding(counts) {
            return .fewEnglishWords(english: english, judged: judged)
        }
        let letters = text.unicodeScalars.filter(\.properties.isAlphabetic).count
        return shortRecognitionFinding(counts, foreignLetters: EnglishText.foreignLetters(text), letters: letters)
    }

    /// A short recognized result can be judged only when its weak English words are corroborated
    /// by substantial mixed-script noise. Numeric forms and too-short fragments stay unjudged.
    static func shortRecognitionFinding(_ counts: WordCounts, foreignLetters: Int, letters: Int) -> Finding? {
        let english = counts.english - counts.lonelyLetters
        let judged = counts.judged - counts.lonelyLetters
        guard judged >= minimumShortRecognitionWords, judged < minimumJudgedWords,
              Double(counts.numberTokens) < Double(counts.tokens) * maximumNumericShare,
              foreignLetters >= minimumShortRecognitionForeignLetters,
              foreignLetters * 10 >= letters,
              english * 3 < judged * 2 else { return nil }
        return .fewEnglishWords(english: english, judged: judged)
    }

    /// Whether a recognition too short for `judgeRecognized` reads as noise beside the sparse layer
    /// it verifies (#216); nil when it does not, or the language is not judged.
    ///
    /// The layer and the recognition are two readings of one page. Where each reads under half
    /// English but neither holds the `minimumJudgedWords` the word test needs, the share each
    /// reports is unstable alone, yet both readings agree that the page's writing is not English,
    /// and together they hold enough words to judge. Warren 550's cursive admission note is the
    /// case: its layer reads 6 of 14 judged words as English (the printed title and caption among
    /// symbol-broken tokens), and its recognition 5 of 16 (`artauit benepit`, `pneed cad penntent`).
    /// Only the count of judged words is pooled; each reading's share is judged on its own, so the
    /// printed words both hold raise both shares. A legible page's labels read as English in at
    /// least one of the two readings, which is enough to keep its layer.
    static func judgeRecognized(lines: [TextLine], besideLayer layer: WordCounts, language: String) -> Finding? {
        let text = lines.map(\.text).joined(separator: "\n")
        guard !lines.isEmpty, EnglishText.isDeclared(language),
              let counts = EnglishText.wordCounts(text),
              !EnglishText.readsAsAnotherLanguage(text) else { return nil }
        return shortReadingsFinding(counts, layer: layer)
    }

    /// The two-reading test over word counts: the recognition and the layer each hold at least
    /// `minimumShortRecognitionWords` and fewer than `minimumJudgedWords` judged words, are not
    /// numeric, read under half English, and hold `minimumJudgedWords` judged words between them.
    static func shortReadingsFinding(_ reading: WordCounts, layer: WordCounts) -> Finding? {
        // A reading's share as the word test reads it: lone letters set aside (#275), a table or
        // form not judged.
        func unreadShare(_ counts: WordCounts) -> (english: Int, judged: Int)? {
            let english = counts.english - counts.lonelyLetters
            let judged = counts.judged - counts.lonelyLetters
            guard judged >= minimumShortRecognitionWords, judged < minimumJudgedWords,
                  Double(counts.numberTokens) < Double(counts.tokens) * maximumNumericShare,
                  Double(english) < Double(judged) * minimumEnglishShare else { return nil }
            return (english, judged)
        }
        guard let read = unreadShare(reading), let kept = unreadShare(layer),
              read.judged + kept.judged >= minimumJudgedWords else { return nil }
        return .fewEnglishWordsInEitherReading(english: read.english, judged: read.judged,
                                               layerEnglish: kept.english, layerJudged: kept.judged)
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
        if case .fewEnglishWordsInEitherReading(let english, let judged, let layerEnglish, let layerJudged) = finding {
            return "OCR of this page image is too short a reading to judge alone, and like the page's existing text it does "
                + "not read as English: only \(english) of its \(judged) judged words are English, and \(layerEnglish) of the "
                + "existing text's \(layerJudged) (handwriting, or print recognition cannot read). The recognized text was "
                + "discarded; the page is preserved as an image and does not reflow."
        }
        guard case .fewEnglishWords(let english, let judged) = finding else { return "" }
        if judged < minimumJudgedWords {
            return "OCR of this page image is a short, mixed-script reading rather than a reliable English transcription: "
                + "only \(english) of \(judged) judged words are English. The recognized text was discarded; "
                + "the page is preserved as an image and does not reflow."
        }
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
        case .unreadWriting(let english):
            problem = "Existing text over a page-sized image transcribes little of the page: it holds only \(english) English "
                + (english == 1 ? "word" : "words") + ", and the rest of the page's writing does not read as English when "
                + "recognized (handwriting, or print recognition cannot read)."
        case .fewEnglishWordsInEitherReading(let english, let judged, let layerEnglish, let layerJudged):
            problem = "Existing text over a page-sized image does not read as English, and neither does OCR of the page: only "
                + "\(layerEnglish) of its \(layerJudged) judged words are English, and \(english) of the OCR's \(judged)."
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
