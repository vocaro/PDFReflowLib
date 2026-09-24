import CoreGraphics
import CoreText
import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

// Whether an inherited text layer is a plausible transcription of its page (#93, #7), and whether
// a page with no words of its own carries drawn writing worth recognizing (#176).

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/93")) func wordCountsSortEnglishDamagedAndNeutralWords() {
    let lexicon: Set<String> = ["the", "movie", "strange"]
    let counts = EnglishText.wordCounts("a sreANee v/eus n e x t The NASA Kennedy movie's 42 strange vrius") {
        lexicon.contains($0)
    }
    // English: a, The, movie('s), strange. Damaged: sreANee (capitalization), n e x t (stray
    // letters), vrius (unknown lower case). Neutral: v/eus (symbol), NASA, Kennedy (names).
    #expect(counts.english == 4)
    #expect(counts.damaged == 6)
    #expect(counts.neutral == 3)
    #expect(counts.numericTokens == 1 && counts.tokens == 14)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/93")) func wordTestNeedsEnoughWordsFewerThanHalfEnglishAndFewNumbers() {
    typealias Counts = TextLayerPlausibility.WordCounts
    #expect(TextLayerPlausibility.wordFinding(Counts(english: 9, damaged: 11, tokens: 20))
        == .fewEnglishWords(english: 9, judged: 20))
    #expect(TextLayerPlausibility.wordFinding(Counts(english: 10, damaged: 10, tokens: 20)) == nil)  // half English
    #expect(TextLayerPlausibility.wordFinding(Counts(english: 5, damaged: 14, tokens: 19)) == nil)   // 19 judged
    // A fifth of the tokens being numbers exempts the layer; a fifth merely holding a digit does
    // not, because a misreading of a hand-written figure holds digits too (#275).
    #expect(TextLayerPlausibility.wordFinding(Counts(english: 5, damaged: 15, numberTokens: 5, tokens: 25)) == nil)
    #expect(TextLayerPlausibility.wordFinding(Counts(english: 5, damaged: 15, numberTokens: 4, tokens: 25)) != nil)
    #expect(TextLayerPlausibility.wordFinding(Counts(english: 5, damaged: 15, numericTokens: 25,
                                                     numberTokens: 4, tokens: 25)) != nil)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/93")) func inkTestNeedsMostTextInkUncoveredInSevenRowsAndFewerWordsThanRows() {
    func measurement(rows: Int, uncovered: Int) -> OCRTextCoverage.Measurement {
        OCRTextCoverage.Measurement(textRows: 10, uncoveredRows: rows, textInk: 100, uncoveredInk: uncovered)
    }
    #expect(TextLayerPlausibility.inkFinding(measurement(rows: 7, uncovered: 75), englishWords: 6)
        == .missingText(uncoveredFraction: 0.75, uncoveredRows: 7, englishWords: 6))
    #expect(TextLayerPlausibility.inkFinding(measurement(rows: 6, uncovered: 90), englishWords: 0) == nil)
    #expect(TextLayerPlausibility.inkFinding(measurement(rows: 9, uncovered: 74), englishWords: 0) == nil)
    #expect(TextLayerPlausibility.inkFinding(measurement(rows: 7, uncovered: 90), englishWords: 7) == nil)
}

// A layer with no letters cannot trigger the lexicon's misread-word judgment. Drawn-text
// recovery also admits sparse worded layers now; PageDiagnosis explicitly excludes layers
// that have already received an implausibility finding (#192).
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/93")) func misreadInPlaceAndReflowsNoWordsCannotBothHoldForTheSameLines() {
    let noLetters = [TextLine(text: "5", rect: .zero, fontSize: 10), TextLine(text: "10-12", rect: .zero, fontSize: 10),
                     TextLine(text: "37) 5 2 3", rect: .zero, fontSize: 10)]
    #expect(TextLayerPlausibility.reflowsNoWords(noLetters))
    let counts = EnglishText.wordCounts(noLetters.map(\.text).joined(separator: "\n")) { _ in true }
    #expect(counts.judged == 0 && counts.words == 0)
    #expect(TextLayerPlausibility.wordFinding(counts) == nil)
    // Any lines that satisfy reflowsNoWords contain no letters at all, so no `isWord` closure
    // (real lexicon or this permissive stub) can ever find a judged word among them.
    typealias Counts = TextLayerPlausibility.WordCounts
    #expect(TextLayerPlausibility.wordFinding(Counts(english: 0, damaged: 0, tokens: noLetters.count)) == nil)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/93")) func judgeRendersOnlySparseEnglishLayers() throws {
    try #require(EnglishText.wordCounts("the") != nil, "no system English lexicon")
    func lines(_ text: String) -> [TextLine] { [TextLine(text: text, rect: CGRect(x: 0, y: 0, width: 100, height: 10), fontSize: 10)] }
    let missing = OCRTextCoverage.Measurement(textRows: 12, uncoveredRows: 12, textInk: 100, uncoveredInk: 95)
    var renders = 0
    // A caption over a page of unrecognized text: rendered, and it fails the ink test.
    #expect(TextLayerPlausibility.judge(lines: lines("Commission Exhibit No. 2215"), language: "en") {
        renders += 1; return missing
    } == .missingText(uncoveredFraction: 0.95, uncoveredRows: 12, englishWords: 3))
    // A layer of 32 English words is never rendered; another language is never judged.
    let wordy = Array(repeating: "the report", count: 16).joined(separator: " ")
    #expect(TextLayerPlausibility.judge(lines: lines(wordy), language: "en") { renders += 1; return missing } == nil)
    #expect(TextLayerPlausibility.judge(lines: lines("Commission"), language: "fr") { renders += 1; return missing } == nil)
    // A word finding needs no rendering.
    let garbled = Array(repeating: "rhe sreANee v/eus eeeAN", count: 10).joined(separator: " ")
    if case .fewEnglishWords = TextLayerPlausibility.judge(lines: lines(garbled), language: "en-US", measureInk: {
        renders += 1; return missing
    }) {} else { Issue.record("garbled layer passed the word test") }
    #expect(renders == 1)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/93")) func realInheritedLayersFailOrPassTheWordTest() throws {
    try #require(EnglishText.wordCounts("the") != nil, "no system English lexicon")
    func counts(_ name: String) throws -> TextLayerPlausibility.WordCounts {
        let fixture = try SourceLayoutFixture.load(name)
        return try #require(EnglishText.wordCounts(fixture.lines.map(\.text).joined(separator: "\n")))
    }
    // The CDC comic's damaged dialogue fails the word test.
    let damaged = try counts("cdc-5")
    #expect(TextLayerPlausibility.wordFinding(damaged) != nil, "cdc-5: \(damaged)")
    // Prose, an index and a witness list keep their text.
    for name in ["warren-50", "warren-910", "blue-12", "blue-5"] {
        let value = try counts(name)
        #expect(TextLayerPlausibility.wordFinding(value) == nil, "\(name): \(value)")
    }
    // #7: carbon typescript read in place (`tcld t» ftboot`) is half English, and misread.
    let typescript = try counts("warren-636")
    guard case .misreadWords(let misread, let words, _)? = TextLayerPlausibility.wordFinding(typescript) else {
        Issue.record("warren-636: \(typescript)"); return
    }
    #expect(Double(misread) >= Double(words) * TextLayerPlausibility.minimumMisreadShare)
    #expect(Double(typescript.english) >= Double(typescript.judged) * TextLayerPlausibility.minimumEnglishShare)
    // So is the comic's page 4 (#168), 0.6 English.
    if case .misreadWords? = TextLayerPlausibility.wordFinding(try counts("cdc-4")) {} else { Issue.record("cdc-4 passed") }
}

// #275: a lone letter is a word only in the company of words, and the numeric exemption counts
// the numbers a page states rather than every token that holds a digit.

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/275")) func aLoneLetterIsEvidenceOnlyInTheCompanyOfWords() {
    let lexicon: Set<String> = ["total", "certain", "evaluation"]
    // Three ruled columns read as `I`, a row of hand-written cells read as `I` and stray figures,
    // then the printed label row, where the same letter stands among words.
    let ruled = EnglishText.wordCounts("I I I\nI 0.3 I 1.2 I\nCertain I Total I Evaluation") { lexicon.contains($0) }
    #expect(ruled.english == 11 && ruled.judged == 11)
    #expect(ruled.lonelyLetters == 6)
    // The same words on one line keep their company, so the count is a judgment about lines, not
    // about how many bare letters a page holds.
    let together = EnglishText.wordCounts("I I I I 0.3 I 1.2 I Certain I Total I Evaluation") { lexicon.contains($0) }
    #expect(together.english == 11 && together.lonelyLetters == 0)
    // A bare letter is set aside, never counted against the layer: the share is taken over what
    // is left, so `judged` loses it too.
    typealias Counts = TextLayerPlausibility.WordCounts
    #expect(TextLayerPlausibility.wordFinding(Counts(english: 21, damaged: 20, tokens: 41, lonelyLetters: 0)) == nil)
    #expect(TextLayerPlausibility.wordFinding(Counts(english: 21, damaged: 20, tokens: 41, lonelyLetters: 2))
        == .fewEnglishWords(english: 19, judged: 39))
    // Nothing is judged once too few words are left standing.
    #expect(TextLayerPlausibility.wordFinding(Counts(english: 21, damaged: 20, tokens: 41, lonelyLetters: 22)) == nil)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/275")) func theNumericExemptionCountsNumbersNotTokensHoldingDigits() {
    let counts = EnglishText.wordCounts("0.3 l6 A.Di 1,234 x2 -") { _ in false }
    #expect(counts.tokens == 6)
    // Holding a digit: 0.3, l6, 1,234, x2. Being a number: 0.3 and 1,234.
    #expect(counts.numericTokens == 4)
    #expect(counts.numberTokens == 2)
}

// The page #275 was filed on: `cia-blue-book-14-1955` page 150, `TABLE A63 EVALUATION OF ALL
// SIGHTINGS FOR ALL YEARS BY COLORS REPORTED`, four ruled grids of 25 columns whose every value
// is written in ink. Its printed labels are transcribed correctly and its hand-written body comes
// back as `II 'i "J.7 "·' r,_3 ,_q 5 I I, ~..l Al 1·3 s 7`.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/275")) func aTableReadForItsLabelsAloneIsNoTranscription() throws {
    try #require(EnglishText.wordCounts("the") != nil, "no system English lexicon")
    func counts(_ name: String) throws -> TextLayerPlausibility.WordCounts {
        let fixture = try SourceLayoutFixture.load(name)
        return try #require(EnglishText.wordCounts(fixture.lines.map(\.text).joined(separator: "\n")))
    }
    typealias Rule = TextLayerPlausibility
    let handwritten = try counts("blue-150")
    // Every test the layer used to meet, in the order the issue tabulates them: a fifth of its
    // tokens held a digit, so it was exempt; it read over half English if judged anyway; and it
    // misread well under a tenth of its words. None of that was a reading of the page.
    #expect(Double(handwritten.numericTokens) >= Double(handwritten.tokens) * Rule.maximumNumericShare)
    #expect(Double(handwritten.english) >= Double(handwritten.judged) * Rule.minimumEnglishShare)
    #expect(Double(handwritten.misread) < Double(handwritten.words) * Rule.minimumMisreadShare)
    // What the two narrowings see: the noise in the cells holds digits without being numbers, and
    // most of the page's English is the letter `I`, one per ruled column, alone on its line.
    #expect(Double(handwritten.numberTokens) < Double(handwritten.tokens) * Rule.maximumNumericShare)
    #expect(handwritten.lonelyLetters * 2 > handwritten.english)
    guard case .fewEnglishWords(let english, let judged)? = Rule.wordFinding(handwritten) else {
        Issue.record("blue-150: \(handwritten)"); return
    }
    #expect(Double(english) < Double(judged) * Rule.minimumEnglishShare)
    // Page 33 of the same book is the other shape the rule sees: `FIGURE 7`'s chart, whose layer
    // is the twelve month initials of six year-long axes and the ticks between them. Its caption
    // is read correctly and its plot is not read at all.
    let chart = try counts("blue-33")
    #expect(chart.lonelyLetters > 0)
    if case .fewEnglishWords? = Rule.wordFinding(chart) {} else { Issue.record("blue-33: \(chart)") }
    // Page 74 of the same book and the same scan, whose table's values are typewritten, keeps its
    // text on the narrowed exemption itself: the figures it states really are numbers, so a fifth
    // of its tokens are numbers and the word tests do not judge it. Page 150 reaches a fifth only
    // by counting the digits in its misread ink.
    let typewritten = try counts("blue-74")
    #expect(Double(typewritten.numberTokens) >= Double(typewritten.tokens) * Rule.maximumNumericShare)
    #expect(Rule.wordFinding(typewritten) == nil, "blue-74: \(typewritten)")
    // Positive controls: a born-digital statistical table, two printed tables of flag sizes, the
    // Warren report's prose and its index of numbers all keep their text. Three of them hold
    // lonely letters of their own, which decide nothing because the pages read as English anyway.
    for name in ["census-1", "flag-27", "flag-30", "warren-50", "warren-910", "blue-5", "blue-12"] {
        let value = try counts(name)
        #expect(Rule.wordFinding(value) == nil, "\(name): \(value)")
    }
    #expect(try counts("warren-910").lonelyLetters > 0)
    #expect(try counts("blue-5").lonelyLetters > 0)
    // And the carbon typescript #7 is built on keeps the finding that has it compared with a
    // fresh reading rather than replaced by one: its bare letters stand in sentences.
    let typescript = try counts("warren-636")
    #expect(typescript.lonelyLetters == 0)
    if case .misreadWords? = Rule.wordFinding(typescript) {} else { Issue.record("warren-636: \(typescript)") }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/93")) func misreadWordsAreDamagedWordsNoNeighbourCompletes() {
    let lexicon: Set<String> = ["the", "field", "strength", "with", "when"]
    let counts = EnglishText.wordCounts("tbe fi e ld stre ngth witb vhen McDonald sreANee th e") { lexicon.contains($0) }
    // Misread: tbe, witb, vhen, sreANee. Split, not misread: fi e ld, stre ngth, th e (joined with a
    // neighbor they make field, strength, the). A compound name's capitals are not damage.
    #expect(counts.misread == 4)
    #expect(counts.misreadExamples == ["tbe", "witb", "vhen"])
    #expect(counts.neutral == 1)
    typealias Counts = TextLayerPlausibility.WordCounts
    #expect(TextLayerPlausibility.wordFinding(Counts(english: 18, damaged: 2, neutral: 0, tokens: 20, misread: 2,
                                                     misreadExamples: ["tbe"]))
        == .misreadWords(misread: 2, words: 20, examples: ["tbe"]))
    #expect(TextLayerPlausibility.wordFinding(Counts(english: 18, damaged: 2, neutral: 4, tokens: 24, misread: 2)) == nil)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/216")) func damagedTypescriptsCrossTheMeasuredMisreadBoundary() {
    typealias Counts = TextLayerPlausibility.WordCounts
    // Source survey: Warren 649, 655, 657, 659 and 661 fall between 8.7% and 9.7%; the
    // highest unaffected Blue Book page is 8.0%. Preserve that separation at the boundary.
    #expect(TextLayerPlausibility.wordFinding(Counts(english: 182, damaged: 18, tokens: 200,
                                                     misread: 17))
        == .misreadWords(misread: 17, words: 200, examples: []))
    #expect(TextLayerPlausibility.wordFinding(Counts(english: 184, damaged: 16, tokens: 200,
                                                     misread: 16)) == nil)
    // The numeric-table exemption still wins even when a page contains damaged words.
    #expect(TextLayerPlausibility.wordFinding(Counts(english: 182, damaged: 18, numberTokens: 40,
                                                     tokens: 200, misread: 17)) == nil)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/93")) func otherScriptsAreDamageAndRecognizedTitlesMustReadAsWords() throws {
    try #require(EnglishText.wordCounts("the") != nil, "no system English lexicon")
    // Recognition of handwriting and of the comic's all-caps exclamations.
    let mixed = EnglishText.wordCounts("DeالasTaxaع НИН the") { $0 == "the" }
    #expect(mixed.damaged == 2 && mixed.english == 1)
    #expect(EnglishText.foreignLetters("НИН?!") == 3)
    #expect(EnglishText.foreignLetters("Besançon, Việt, ﬁeld") == 0)
    for title in ["INDEX OF TABLES", "Table A59. Evaluation of All Sightings for 1952", "SEPTEMBER", "SECTION D",
                  "PARKLAND MEMORIAL HOSPITAL"] {
        #expect(EnglishText.readsAsWords(title), "\(title)")
    }
    // Table cells and handwriting read at heading size under `--ocr always`.
    for noise in ["139", "1952 1950", "a0 0.0", "• a0", "0 00 a0 a0 a o e 00.00 a0", "Pags", "Certaia Doubtlul Total Cotai",
                  "Tag De Praciy Glii tant ami She", "стрлда ві. 1)", "Crมn C Tม Cour oi Ica"] {
        #expect(!EnglishText.readsAsWords(noise), "\(noise)")
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/93")) func recognitionIsJudgedByItsEnglishShareUnlessItIsAnotherLanguage() throws {
    try #require(EnglishText.wordCounts("the") != nil, "no system English lexicon")
    func lines(_ text: String) -> [TextLine] { [TextLine(text: text, rect: CGRect(x: 0, y: 0, width: 100, height: 10), fontSize: 10)] }
    // Handwriting recognition, abridged: read as noise.
    let noise = "PARKLAND MEMORIAL HOSPITAL ADMISSION NOTE iar mhele aandeuzen tro gret ancr fuom lhe sae intr ond deta "
        + "vrenl mit shert oo kaat pols reat erad huoi fis tne aad lov ot pert"
    #expect(TextLayerPlausibility.judgeRecognized(lines: lines(noise), language: "en") != nil)
    #expect(TextLayerPlausibility.judgeRecognized(lines: lines(noise), language: "fr") == nil)
    // A page in French is text, not noise, in a book declared English.
    let french = "Le général a été élevé à Besançon, où l'été est très chaud. Après la rentrée, les élèves répètent leurs "
        + "leçons à côté du théâtre. La société française préfère les fenêtres ouvertes même en hiver."
    #expect(EnglishText.readsAsAnotherLanguage(french))
    #expect(TextLayerPlausibility.judgeRecognized(lines: lines(french), language: "en") == nil)
    // Misreading a tenth of its words does not discard a recognition that reads as English.
    let comic = Array(repeating: "MAN I FORGOT I HAD THIS. IT USED TO BE MY DAD'S powtred radic", count: 3).joined(separator: " ")
    #expect(TextLayerPlausibility.judgeRecognized(lines: lines(comic), language: "en") == nil)
    #expect(TextLayerPlausibility.readsBetter(lines(comic), than: 30, of: 100, language: "en"))
    #expect(!TextLayerPlausibility.readsBetter(lines(comic), than: 1, of: 100, language: "en"))
    #expect(!TextLayerPlausibility.readsBetter(lines(noise), than: 50, of: 100, language: "en"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/93")) func warningStatesWhatFailedAndWhatWasDone() {
    let words = TextLayerPlausibility.message(.fewEnglishWords(english: 31, judged: 95), outcome: .replaced, referencesDisabled: false)
    #expect(words == "Existing text over a page-sized image does not read as English: only 31 of 95 words are English words "
        + "(misspelled, wrongly capitalized or letter-spaced text). The existing text was discarded and replaced by OCR "
        + "of the page image; review this page against the original page image.")
    let ink = TextLayerPlausibility.message(.missingText(uncoveredFraction: 0.876, uncoveredRows: 13, englishWords: 1),
                                            outcome: .retained, referencesDisabled: true)
    #expect(ink == "Existing text over a page-sized image is missing most of the page's text: about 87% of the page's "
        + "text-shaped ink (13 rows) lies outside its lines, which hold 1 English word. The existing text is retained "
        + "because the OCR policy keeps it; read the source PDF instead.")
    #expect(TextLayerPlausibility.message(.fewEnglishWords(english: 1, judged: 20), outcome: .pageImage, referencesDisabled: false)
        .hasSuffix("The existing text was discarded, but OCR of the page image failed or found no text, so the page is preserved as an image."))
    let misread = TextLayerPlausibility.message(.misreadWords(misread: 58, words: 244, examples: ["tcld", "ftboot", "ftt"]),
                                                outcome: .keptOverRecognition, referencesDisabled: false)
    #expect(misread == "Existing text over a page-sized image is a damaged transcription: 58 of its 244 words are misread, "
        + "not English words or names (such as \u{201C}tcld\u{201D}, \u{201C}ftboot\u{201D}, \u{201C}ftt\u{201D}). The page image was "
        + "recognized again, but OCR failed or read it no better, so the existing text is retained; read the accompanying "
        + "original page image instead.")
    #expect(TextLayerPlausibility.message(.fewEnglishWords(english: 10, judged: 31), outcome: .implausibleRecognition,
                                          referencesDisabled: false)
        .hasSuffix("OCR of the page image does not read as English either, so the page is preserved as an image and does not reflow."))
    #expect(TextLayerPlausibility.recognitionMessage(.fewEnglishWords(english: 12, judged: 87))
        == "OCR of this page image does not read as English: only 12 of 87 words are English words (handwriting, or print "
        + "recognition cannot read). The recognized text was discarded; the page is preserved as an image and does not reflow.")
}

// MARK: End to end

/// A one-page PDF whose page-sized image shows `imageLines` in 14-point Helvetica, with invisible
/// text drawn over it: `layerLines[i]` at the position of image line `i` (nil draws nothing there).
private func imageBackedPDF(imageLines: [String], layerLines: [String?]) throws -> Data {
    let page = CGRect(x: 0, y: 0, width: 612, height: 792)
    let scale = 2.0
    let font = pdfKitGated { CTFontCreateWithName("Helvetica" as CFString, 14, nil) }
    func baseline(_ index: Int) -> CGFloat { 700 - CGFloat(index) * 26 }
    func line(_ text: String, font: CTFont) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]))
    }
    let bitmap = try #require(CGContext(data: nil, width: Int(page.width * scale), height: Int(page.height * scale),
        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    bitmap.setFillColor(gray: 1, alpha: 1)
    bitmap.fill(CGRect(x: 0, y: 0, width: page.width * scale, height: page.height * scale))
    bitmap.setFillColor(gray: 0, alpha: 1)
    pdfKitGated {
        let large = CTFontCreateWithName("Helvetica" as CFString, 14 * scale, nil)
        for (index, text) in imageLines.enumerated() {
            bitmap.textPosition = CGPoint(x: 72 * scale, y: baseline(index) * scale)
            CTLineDraw(line(text, font: large), bitmap)
        }
    }
    let image = try #require(bitmap.makeImage())
    let data = NSMutableData()
    var box = page
    let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
    let pdf = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
    pdf.beginPDFPage(nil)
    pdf.draw(image, in: page)
    pdf.setTextDrawingMode(.invisible)
    pdfKitGated {
        for (index, text) in layerLines.enumerated() {
            guard let text else { continue }
            pdf.textPosition = CGPoint(x: 72, y: baseline(index))
            CTLineDraw(line(text, font: font), pdf)
        }
    }
    pdf.endPDFPage()
    pdf.closePDF()
    return data as Data
}

private let dialogue = [
    "In other news, several people have been hospitalized",
    "after a strange virus began spreading rapidly through",
    "the southeast. Scientists have not identified the virus",
    "yet, but symptoms include slow movement, slurred speech",
    "and violent tendencies. The Centers for Disease Control",
    "recommend that people stay away from anyone showing",
    "these symptoms and gather emergency supplies at home.",
    "They are also asking families to make plans in case",
    "they are told to evacuate. You can get more information",
    "at the emergency web site. Stay tuned for more news.",
]

/// The same dialogue with light single-letter damage (`h` to `b`, an OCR-style confusion) in about
/// 15% of words, unlike `garbledDialogue`'s heavier leetspeak: enough to misread in place
/// (`.misreadWords`, #7's `RecognitionPlan.Mode.compare` path) without also failing the English-share test
/// (`.fewEnglishWords`), which `garbledDialogue` exercises instead. `RecognitionPlan.Mode.compare` and its
/// downstream branches in `PDFReflowLibPipeline.swift` (kept-over-recognition, replaced-with-
/// warning-removal) have no other end-to-end coverage; `TextLayerPlausibilityTests` otherwise only
/// calls `wordFinding`/`readsBetter` directly, never through the real pipeline.
private let misreadInPlaceDialogue = [
    "In otber news, several people bave been bospitalized",
    "after a strange virus began spreading rapidly through",
    "tbe southeast. Scientists bave not identified tbe virus",
    "yet, but symptoms include slow movement, slurred speecb",
    "and violent tendencies. Tbe Centers for Disease Control",
    "recommend tbat people stay away from anyone showing",
    "tbese symptoms and gatber emergency supplies at bome.",
    "Tbey are also asking families to make plans in case",
    "tbey are told to evacuate. You can get more information",
    "at tbe emergency web site. Stay tuned for more news.",
]

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/93")) func misreadInPlaceLayerComparesAgainstRecognitionEndToEnd() async throws {
    try #require(EnglishText.wordCounts("the") != nil, "no system English lexicon")
    let counts = try #require(EnglishText.wordCounts(misreadInPlaceDialogue.joined(separator: "\n")))
    guard case .misreadWords? = TextLayerPlausibility.wordFinding(counts) else {
        Issue.record("fixture no longer misreads in place: \(counts)"); return
    }
    let garbled = try imageBackedPDF(imageLines: dialogue, layerLines: misreadInPlaceDialogue)
    let (result, text) = try await convert(garbled, policy: .automatic)
    let warning = try #require(result.warnings.first { $0.code == .implausibleTextLayer })
    #expect(warning.message.contains("is a damaged transcription:"), "\(warning.message)")
    // The underlying image is clean, so recognition reads better than the damaged layer: replaced,
    // exactly like the plain fewEnglishWords case, but reached through the comparison plan this time.
    #expect(warning.message.contains("replaced by OCR"), "\(warning.message)")
    #expect(result.recognizedPageCount == 1)
    #expect(result.warnings.contains { $0.code == .ocrUsed })
    #expect(text.contains("strange virus"), "\(text)")
    #expect(!text.contains("otber") && !text.contains("bave"))
    // The comparison layer's own unverifiedTextLayer review warning does not linger once it loses.
    #expect(!result.warnings.contains { $0.code == .unverifiedTextLayer })
}

private let garbledDialogue = [
    "in otHee News, seveeAL people HAve eeeN Hosp/rAL/zed",
    "Afree a sreANee v/eus eeeAN speeAd/Ng eAp/dLy rheoueh",
    "rhe sourheAsr. sc/eNr/srs HAveN'r ideNr/f/ed rhe v/eus",
    "yer, eur symproms iNCLUde slo w movemeNr, sLueeed speech",
    "ANd v/olbnt reNdeNc/es. thb ceNrees foe d /s b a s b",
    "coNreoL eecoMMeNd rhAr peop Le srAy AwAy fRoM ANyoNe",
    "sHow/Ng rHese symproms ANd eAr Hee eMeeeeNcy supp L/es",
    "rHey Ar e ALso Ask/Ng fAM/L/es ro MAke p LANs /N cAse",
    "rHey Ar e ro Ld ro evAcuAre. you cAN eer MoRe /NfoeMAr/oN",
    "Ar rhe eMeeeeNcy web s/re. srAy ruNed foe MoRe News.",
]

private func convert(_ data: Data, policy: ConversionOptions.OCRPolicy) async throws
    -> (result: PDFReflowLibPipeline.Result, text: String) {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let source = dir.appendingPathComponent("source.pdf")
    try data.write(to: source)
    var options = ConversionOptions(); options.ocr = policy
    let result = try await PDFReflowLibPipeline.reconstruct(from: source, options: options,
        workspace: dir.appendingPathComponent("work"), progress: { _ in })
    return (result, result.book.blocks.map(\.text).joined(separator: " "))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/93")) func implausibleInheritedWordsAreReplacedByDefaultAndReportedUnderEveryPolicy() async throws {
    try #require(EnglishText.wordCounts("the") != nil, "no system English lexicon")
    let garbled = try imageBackedPDF(imageLines: dialogue, layerLines: garbledDialogue)
    for policy in [ConversionOptions.OCRPolicy.automatic, .automaticKeepingImageBackedText, .never,
                   .automaticIncludingImageBackedText, .always] {
        let (result, text) = try await convert(garbled, policy: policy)
        let warning = try #require(result.warnings.first { $0.code == .implausibleTextLayer }, "\(policy)")
        #expect(warning.page == 1)
        #expect(warning.message.hasPrefix("Existing text over a page-sized image does not read as English: only "))
        let replaced = policy != .automaticKeepingImageBackedText && policy != .never
        #expect(result.recognizedPageCount == (replaced ? 1 : 0), "\(policy)")
        #expect(warning.message.contains("replaced by OCR") == replaced)
        #expect(result.warnings.contains { $0.code == .ocrUsed } == replaced)
        #expect(result.warnings.contains { $0.code == .unverifiedTextLayer } == !replaced)
        if replaced {
            #expect(text.contains("strange virus"), "\(policy): \(text)")
            #expect(!text.contains("sreANee"))
        } else {
            #expect(text.contains("sreANee"), "\(policy): \(text)")
        }
    }
    // Over a blank image recognition finds nothing: the warning says the page became an image.
    let blank = try imageBackedPDF(imageLines: [], layerLines: garbledDialogue)
    let (empty, _) = try await convert(blank, policy: .automatic)
    let emptyWarning = try #require(empty.warnings.first { $0.code == .implausibleTextLayer })
    #expect(emptyWarning.message.hasSuffix("OCR of the page image failed or found no text, so the page is preserved as an image."))
    #expect(empty.warnings.contains { $0.code == .pageImageFallback })
    // Control: the same image under a faithful layer keeps its text, unreported and unrecognized.
    let faithful = try imageBackedPDF(imageLines: dialogue, layerLines: dialogue)
    let (control, text) = try await convert(faithful, policy: .automatic)
    #expect(!control.warnings.contains { $0.code == .implausibleTextLayer })
    #expect(control.recognizedPageCount == 0)
    #expect(control.warnings.contains { $0.code == .unverifiedTextLayer })
    #expect(text.contains("strange virus"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/93")) func inheritedLayerMissingMostOfThePageTextIsReplaced() async throws {
    let caption = try imageBackedPDF(imageLines: dialogue,
        layerLines: [nil, nil, nil, nil, nil, nil, nil, nil, nil, "at the emergency web site."])
    let (result, text) = try await convert(caption, policy: .automatic)
    let warning = try #require(result.warnings.first { $0.code == .implausibleTextLayer })
    #expect(warning.message.hasPrefix("Existing text over a page-sized image is missing most of the page's text: about "))
    #expect(result.recognizedPageCount == 1)
    #expect(text.contains("strange virus"), "\(text)")
    // Kept by the opt-out policy, still reported.
    let (kept, keptText) = try await convert(caption, policy: .automaticKeepingImageBackedText)
    #expect(kept.warnings.contains { $0.code == .implausibleTextLayer && $0.message.contains("is retained") })
    #expect(kept.recognizedPageCount == 0 && !keptText.contains("strange virus"))
    // Control: the complete layer covers the page's text.
    let complete = try imageBackedPDF(imageLines: dialogue, layerLines: dialogue)
    let (control, _) = try await convert(complete, policy: .automatic)
    #expect(!control.warnings.contains { $0.code == .implausibleTextLayer })
    #expect(control.recognizedPageCount == 0)
}

/// A raster of `background` luminance with `rows` rows of five hollow 10x12 boxes of `ink`
/// luminance, which `OCRTextCoverage` reads as glyph-sized components standing in a row.
private func raster(width: Int = 400, height: Int = 200, background: UInt8, ink: UInt8,
                    rows: Int, top: Int = 20) -> OCRTextCoverage.GrayRaster {
    var pixels = [UInt8](repeating: background, count: width * height)
    for row in 0..<rows {
        let y0 = top + row * 40
        for glyph in 0..<5 {
            let x0 = 20 + glyph * 24
            for y in y0..<(y0 + 12) {
                for x in x0..<(x0 + 10) where x == x0 || x == x0 + 9 || y == y0 || y == y0 + 11 {
                    pixels[y * width + x] = ink
                }
            }
        }
    }
    return OCRTextCoverage.GrayRaster(width: width, height: height, pixels: pixels)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/176")) func darkPageWithNoInkRowsIsMeasuredAgainstItsOwnBackground() {
    // White writing on a dark ground: every pixel of the ground is below any ink threshold, so
    // the darker side is one page-sized component and no row is found until the page is inverted.
    let light = raster(background: 40, ink: 255, rows: 3)
    #expect(light.inkIsBackground())
    #expect(OCRTextCoverage.measure(light, boxes: [], excluded: [], pixelsPerPoint: 1).textRows == 3)
    // Control: the same writing dark on white needs no inversion and reads the same rows.
    let dark = raster(background: 255, ink: 0, rows: 3)
    #expect(!dark.inkIsBackground())
    #expect(OCRTextCoverage.measure(dark, boxes: [], excluded: [], pixelsPerPoint: 1).textRows == 3)
    // Control: a dark page with no writing on it stays empty both ways.
    let blank = raster(background: 40, ink: 255, rows: 0)
    #expect(OCRTextCoverage.measure(blank, boxes: [], excluded: [], pixelsPerPoint: 1).textRows == 0)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/182"))
func aLightOnDarkPageIsJudgedForWritingAReadingLeftOut() {
    // The deck's shape, and the pin for #182's third defect. Rendered at 180 DPI, 97.6% of
    // `ntrs-20180003024-earthdata-slides-2018`'s slide 5 is darker than the page's own ink
    // threshold, and measured as drawn it yields no text row at all: the loss rule has nothing
    // to weigh, and the slide cannot be judged. Measured against the page's own background it
    // yields rows, so a reading that came back with only part of the page is caught on such a
    // page as on any other.
    let slide = raster(width: 400, height: 440, background: 40, ink: 255, rows: 10)
    #expect(slide.inkIsBackground())
    // The first two rows of writing, as a reading that stopped after them would report them.
    func box(_ row: Int) -> CGRect {
        let y0 = 20 + row * 40
        return CGRect(x: 20 / 400.0, y: (440.0 - Double(y0 + 12)) / 440,
                      width: 106 / 400.0, height: 12 / 440.0)
    }
    let partial = OCRTextCoverage.measure(slide, boxes: [box(0), box(1)], excluded: [], pixelsPerPoint: 1)
    #expect(partial.textRows == 10)
    #expect(partial.uncoveredRows == 8)
    #expect(partial.indicatesLoss)
    // Control: the same writing printed dark on white is judged identically, so nothing about
    // the verdict depends on which side of the threshold the page's ink is on.
    let printed = OCRTextCoverage.measure(raster(width: 400, height: 440, background: 255, ink: 0, rows: 10),
                                          boxes: [box(0), box(1)], excluded: [], pixelsPerPoint: 1)
    #expect(printed.textRows == partial.textRows)
    #expect(printed.uncoveredRows == partial.uncoveredRows)
    #expect(printed.indicatesLoss)
    // Control: a reading that covered every row of the light-on-dark page reports no loss.
    let complete = OCRTextCoverage.measure(slide, boxes: (0..<10).map(box), excluded: [], pixelsPerPoint: 1)
    #expect(complete.textRows == 10)
    #expect(complete.uncoveredRows == 0)
    #expect(!complete.indicatesLoss)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/176")) func aPageWhoseDarkInkAlreadyFormsRowsIsNeverInverted() {
    // A mostly dark page — a full-bleed photograph — whose printed text is dark on a light panel.
    var pixels = [UInt8](repeating: 20, count: 400 * 200)
    for y in 0..<90 { for x in 0..<400 { pixels[y * 400 + x] = 250 } }
    var page = OCRTextCoverage.GrayRaster(width: 400, height: 200, pixels: pixels)
    let writing = raster(background: 250, ink: 0, rows: 2)
    for y in 0..<80 { for x in 0..<400 { page.pixels[y * 400 + x] = writing.pixels[y * 400 + x] } }
    #expect(page.inkIsBackground())  // more than half the page is darker than the threshold
    let measured = OCRTextCoverage.measure(page, boxes: [], excluded: [], pixelsPerPoint: 1)
    #expect(measured.textRows == 2)  // read as printed, not inverted
}

// MARK: - The rule

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/176")) func aLayerWithNoLetterReflowsNoWords() {
    func lines(_ texts: [String]) -> [TextLine] {
        texts.map { TextLine(text: $0, rect: CGRect(x: 0, y: 0, width: 10, height: 10), fontSize: 10) }
    }
    #expect(TextLayerPlausibility.reflowsNoWords([]))
    #expect(TextLayerPlausibility.reflowsNoWords(lines(["5"])))          // a folio
    #expect(TextLayerPlausibility.reflowsNoWords(lines(["10-12"])))      // a section folio
    #expect(TextLayerPlausibility.reflowsNoWords(lines(["37) 5 2 √ + 3 √", "38) 3"])))  // an answer key
    #expect(!TextLayerPlausibility.reflowsNoWords(lines(["5", "Goals"])))
    #expect(!TextLayerPlausibility.reflowsNoWords(lines(["a"])))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/176")) func drawnTextNeedsMoreThanOneRowOutsideTheLayer() {
    func measurement(_ uncovered: Int) -> OCRTextCoverage.Measurement {
        OCRTextCoverage.Measurement(textRows: 40, uncoveredRows: uncovered, textInk: 100, uncoveredInk: 100)
    }
    #expect(TextLayerPlausibility.carriesDrawnText(measurement(2)))
    #expect(TextLayerPlausibility.carriesDrawnText(measurement(3)))
    #expect(!TextLayerPlausibility.carriesDrawnText(measurement(1)))  // one row is a figure's label
    #expect(!TextLayerPlausibility.carriesDrawnText(measurement(0)))  // an answer key the layer covers
    // Sparse layers are judged in every language, including a layer holding a real word.
    var renders = 0
    let writing = measurement(3)
    #expect(TextLayerPlausibility.judgeImageOnly(lines: [], language: "en") { renders += 1; return writing })
    #expect(TextLayerPlausibility.judgeImageOnly(lines: [], language: "ar") { renders += 1; return writing })
    let worded = [TextLine(text: "Goals", rect: CGRect(x: 0, y: 0, width: 10, height: 10), fontSize: 10)]
    #expect(TextLayerPlausibility.judgeImageOnly(lines: worded, language: "en") { renders += 1; return writing })
    for text in ["www.uscis.gov", "A complete native title", String(repeating: "字", count: 33)] {
        let lines = [TextLine(text: text, rect: .zero, fontSize: 10)]
        #expect(!TextLayerPlausibility.judgeImageOnly(lines: lines, language: "zh-Hans") {
            renders += 1; return writing
        })
    }
    #expect(renders == 3)
}

// MARK: - End to end

/// A one-slide PDF: a full-bleed `background` fill, `sentence` drawn as filled glyph outlines in
/// `ink` (no text layer at all), an optional real-text `folio`, and optional decoration instead of
/// the sentence. This is how Google Slides exported slide 5 of the Earthdata deck.
private func drawnTextPDF(sentence: [String], folio: String?, background: CGFloat,
                          ink: CGFloat, decoration: Bool = false, nativeWord: String? = nil) throws -> Data {
    let page = CGRect(x: 0, y: 0, width: 720, height: 405)
    let font = pdfKitGated { CTFontCreateWithName("Helvetica" as CFString, 40, nil) }
    let data = NSMutableData()
    var box = page
    let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
    let pdf = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
    pdf.beginPDFPage(nil)
    pdf.setFillColor(gray: background, alpha: 1)
    pdf.fill(page)
    pdf.setFillColor(gray: ink, alpha: 1)
    pdfKitGated {
        if decoration {
            // Art with no writing in it: three plain discs, the size of the sentence's words.
            for index in 0..<3 {
                pdf.fillEllipse(in: CGRect(x: 120 + index * 180, y: 160, width: 120, height: 120))
            }
        } else {
            for (index, text) in sentence.enumerated() {
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font]))
                let origin = CGPoint(x: index == 0 && nativeWord != nil ? 220 : 90, y: 240 - CGFloat(index) * 60)
                for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
                    let count = CTRunGetGlyphCount(run)
                    var glyphs = [CGGlyph](repeating: 0, count: count)
                    var positions = [CGPoint](repeating: .zero, count: count)
                    CTRunGetGlyphs(run, CFRange(), &glyphs)
                    CTRunGetPositions(run, CFRange(), &positions)
                    for (glyph, position) in zip(glyphs, positions) {
                        guard let path = CTFontCreatePathForGlyph(font, glyph, nil) else { continue }
                        var transform = CGAffineTransform(translationX: origin.x + position.x,
                                                          y: origin.y + position.y)
                        if let moved = path.copy(using: &transform) { pdf.addPath(moved) }
                    }
                }
                pdf.fillPath()
            }
        }
        if let nativeWord {
            let nativeFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 40, nil)
            pdf.textPosition = CGPoint(x: 90, y: 240)
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: nativeWord, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): nativeFont,
                NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true])), pdf)
        }
        if let folio {
            let small = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
            pdf.textPosition = CGPoint(x: 680, y: 24)
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: folio, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): small,
                NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true])), pdf)
        }
    }
    pdf.endPDFPage()
    pdf.closePDF()
    return data as Data
}

private let question = ["How do we support user analysis", "of very large data volumes?"]

private func reflow(_ data: Data, policy: ConversionOptions.OCRPolicy = .automatic, language: String = "en",
                    recognize: PDFReflowLibPipeline.Recognizer? = nil) async throws
    -> (result: PDFReflowLibPipeline.Result, text: String) {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let source = dir.appendingPathComponent("source.pdf")
    try data.write(to: source)
    var options = ConversionOptions(); options.ocr = policy; options.language = language
    let result = try await PDFReflowLibPipeline.reconstruct(from: source, options: options,
        workspace: dir.appendingPathComponent("work"), recognize: recognize, progress: { _ in })
    return (result, result.book.blocks.map(\.text).joined(separator: " "))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/176")) func aSlideWhoseOnlyWritingIsDrawnWhiteOnDarkIsRecognized() async throws {
    let slide = try drawnTextPDF(sentence: question, folio: "5", background: 0.25, ink: 1)
    let (result, text) = try await reflow(slide)
    #expect(result.recognizedPageCount == 1)
    #expect(result.warnings.contains { $0.code == .ocrUsed && $0.page == 1 })
    #expect(text.lowercased().contains("large data volumes"), "\(text)")
    // The policy that keeps image-backed text still recognizes a page that has no text layer.
    let (kept, keptText) = try await reflow(slide, policy: .automaticKeepingImageBackedText)
    #expect(kept.recognizedPageCount == 1)
    #expect(keptText.lowercased().contains("large data volumes"), "\(keptText)")
    // `.never` recognizes nothing: the slide keeps its art and reflows no sentence.
    let (never, neverText) = try await reflow(slide, policy: .never)
    #expect(never.recognizedPageCount == 0)
    #expect(!neverText.lowercased().contains("large data volumes"), "\(neverText)")
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/176")) func theSameSlidePrintedDarkOnLightIsRecognizedToo() async throws {
    let slide = try drawnTextPDF(sentence: question, folio: "5", background: 1, ink: 0)
    let (result, text) = try await reflow(slide)
    #expect(result.recognizedPageCount == 1)
    #expect(text.lowercased().contains("large data volumes"), "\(text)")
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/176")) func writingInsideAPhotographIsNotThePageWriting() async throws {
    // A page whose only writing is inside a picture — the Arabic civics cards' blackboard photo,
    // and Mount Rushmore, whose strata the ink test reads as rows of glyphs. Its crop keeps it.
    let photographed = try photographPDF(sentence: question, folio: "56")
    let (result, text) = try await reflow(photographed)
    #expect(result.recognizedPageCount == 0)
    #expect(!result.warnings.contains { $0.code == .ocrUsed })
    #expect(!text.lowercased().contains("large data volumes"), "\(text)")
}

/// The same slide with its sentence inside a placed raster rather than drawn on the page.
private func photographPDF(sentence: [String], folio: String) throws -> Data {
    let page = CGRect(x: 0, y: 0, width: 720, height: 405)
    let scale = 3.0
    let picture = CGRect(x: 60, y: 90, width: 600, height: 240)
    let bitmap = try #require(CGContext(data: nil, width: Int(picture.width * scale),
        height: Int(picture.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    bitmap.setFillColor(gray: 0.25, alpha: 1)
    bitmap.fill(CGRect(x: 0, y: 0, width: picture.width * scale, height: picture.height * scale))
    bitmap.setFillColor(gray: 1, alpha: 1)
    pdfKitGated {
        let large = CTFontCreateWithName("Helvetica" as CFString, 40 * scale, nil)
        for (index, text) in sentence.enumerated() {
            bitmap.textPosition = CGPoint(x: 30 * scale, y: (150 - CGFloat(index) * 60) * scale)
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): large,
                NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true])), bitmap)
        }
    }
    let image = try #require(bitmap.makeImage())
    let data = NSMutableData()
    var box = page
    let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
    let pdf = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
    pdf.beginPDFPage(nil)
    pdf.setFillColor(gray: 0.25, alpha: 1)
    pdf.fill(page)
    pdf.draw(image, in: picture)
    pdf.setFillColor(gray: 1, alpha: 1)
    pdfKitGated {
        let small = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        pdf.textPosition = CGPoint(x: 670, y: 24)
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: folio, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): small,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true])), pdf)
    }
    pdf.endPDFPage()
    pdf.closePDF()
    return data as Data
}

/// The drawn-text slide, but its background is an actual placed raster image spanning the page
/// (not a solid content-stream fill, which `GraphicsReader` does not track as a region) so
/// `imageBackedText` (#93's own precondition) is true here, unlike `drawnTextPDF`'s pages. Its
/// only real text-layer line is the folio, so it also satisfies #176's `reflowsNoWords`
/// candidacy — the two features' preconditions overlap on this one page, where #7's
/// `RecognitionPlan.Mode.compare` cannot reach (see `misreadInPlaceAndReflowsNoWordsCannotBothHoldForTheSameLines`).
/// The sentence is drawn on top of, and spatially within, that same full-page placed image.
private func drawnTextOverPlacedImagePDF(sentence: [String], folio: String) throws -> Data {
    let page = CGRect(x: 0, y: 0, width: 720, height: 405)
    let bitmap = try #require(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    bitmap.setFillColor(gray: 0.25, alpha: 1)
    bitmap.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    let image = try #require(bitmap.makeImage())
    let font = pdfKitGated { CTFontCreateWithName("Helvetica" as CFString, 40, nil) }
    let data = NSMutableData()
    var box = page
    let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
    let pdf = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
    pdf.beginPDFPage(nil)
    pdf.draw(image, in: page)
    pdf.setFillColor(gray: 1, alpha: 1)
    pdfKitGated {
        for (index, text) in sentence.enumerated() {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font]))
            let origin = CGPoint(x: 90, y: 240 - CGFloat(index) * 60)
            for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
                let count = CTRunGetGlyphCount(run)
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                CTRunGetGlyphs(run, CFRange(), &glyphs)
                CTRunGetPositions(run, CFRange(), &positions)
                for (glyph, position) in zip(glyphs, positions) {
                    guard let path = CTFontCreatePathForGlyph(font, glyph, nil) else { continue }
                    var transform = CGAffineTransform(translationX: origin.x + position.x, y: origin.y + position.y)
                    if let moved = path.copy(using: &transform) { pdf.addPath(moved) }
                }
            }
            pdf.fillPath()
        }
        let small = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        pdf.textPosition = CGPoint(x: 680, y: 24)
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: folio, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): small,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true])), pdf)
    }
    pdf.endPDFPage()
    pdf.closePDF()
    return data as Data
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/176")) func aPageWhoseOnlyRowsSitInsideAFullPagePlacedImageIsNotRecognizedEitherWay() async throws {
    // Verifies, rather than assumes, how #93's ink-test path and #176's drawnText candidacy
    // interact when their preconditions overlap (imageBackedText true, and the layer's only line
    // a folio). They do not double-fire and neither wrongly recognizes the page: #93's ink test
    // needs 7 uncovered rows (`minimumUncoveredRows`) and this two-line sentence supplies only 2,
    // so it stays nil regardless; #176's own, lower threshold (2 rows, `minimumImageOnlyRows`)
    // would otherwise be cleared by the same two rows, but `measureInk`'s `excluding: placedImages`
    // (the same exclusion `writingInsideAPhotographIsNotThePageWriting` relies on) removes ink
    // inside the placed image's bounds from the count. Because the background image spans the
    // whole page, that exclusion also removes the sentence drawn on top of it, so drawnText's own
    // ink test finds no rows either. The page is correctly left exactly as extracted (folio only,
    // preserved crops), not silently recognized by one path when the other's precondition holds,
    // and not double-warned.
    let slide = try drawnTextOverPlacedImagePDF(sentence: question, folio: "5")
    let (result, text) = try await reflow(slide)
    #expect(result.recognizedPageCount == 0)
    #expect(!result.warnings.contains { $0.code == .ocrUsed })
    #expect(!result.warnings.contains { $0.code == .implausibleTextLayer })
    #expect(result.warnings.contains { $0.code == .unverifiedTextLayer })
    #expect(!text.lowercased().contains("large data volumes"), "\(text)")
    #expect(text.contains("5"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/176")) func decorativeArtWithoutWritingIsNotRecognized() async throws {
    // Negative control: the same dark slide, the same folio, art that is not writing.
    let decorated = try drawnTextPDF(sentence: [], folio: "5", background: 0.25, ink: 1, decoration: true)
    let (result, _) = try await reflow(decorated)
    #expect(result.recognizedPageCount == 0)
    #expect(!result.warnings.contains { $0.code == .ocrUsed })
    // Negative control: a slide whose sentence is real text is never rendered or recognized.
    let native = try nativeSlidePDF()
    let (control, text) = try await reflow(native)
    #expect(control.recognizedPageCount == 0)
    #expect(!control.warnings.contains { $0.code == .ocrUsed })
    #expect(text.contains("How do we support user analysis"), "\(text)")
}

/// The same slide with its sentence drawn as ordinary visible text over the dark fill.
private func nativeSlidePDF() throws -> Data {
    let page = CGRect(x: 0, y: 0, width: 720, height: 405)
    let data = NSMutableData()
    var box = page
    let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
    let pdf = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
    pdf.beginPDFPage(nil)
    pdf.setFillColor(gray: 0.25, alpha: 1)
    pdf.fill(page)
    pdf.setFillColor(gray: 1, alpha: 1)
    pdfKitGated {
        let font = CTFontCreateWithName("Helvetica" as CFString, 40, nil)
        for (index, text) in question.enumerated() {
            pdf.textPosition = CGPoint(x: 90, y: 240 - CGFloat(index) * 60)
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true])), pdf)
        }
    }
    pdf.endPDFPage()
    pdf.closePDF()
    return data as Data
}

// MARK: - Recognition that left the page's writing out (#116)

/// The normalized, lower-left-origin box of one of `raster`'s rows, as a recognized line covering
/// it would be. Rows stand 12 px tall at `top + row * 40` from the top of a `height` px page.
private func rowBox(_ row: Int, height: Int, top: Int = 20) -> CGRect {
    let y0 = top + row * 40
    return CGRect(x: 20.0 / 400, y: 1 - Double(y0 + 12) / Double(height),
                  width: 5 * 24.0 / 400, height: 12.0 / Double(height))
}

/// A page of `rows` rows of printed writing, of which the first `covered` are read.
private func reading(rows: Int, covered: Int, height: Int = 2400) -> OCRTextCoverage.Measurement {
    let page = raster(height: height, background: 255, ink: 0, rows: rows)
    return OCRTextCoverage.measure(page, boxes: (0..<covered).map { rowBox($0, height: height) },
                                   excluded: [], pixelsPerPoint: 1)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/116"))
func aRecognitionMissingWholeRowsOfThePagesWritingIndicatesLoss() {
    // Every row read: the page's writing is accounted for.
    let complete = reading(rows: 16, covered: 16)
    #expect(complete.textRows == 16)
    #expect(complete.uncoveredRows == 0)
    #expect(!complete.indicatesLoss)

    // Half the page's rows never read: a dropped paragraph, not a clipped ascender.
    let lossy = reading(rows: 16, covered: 8)
    #expect(lossy.uncoveredRows == 8)
    #expect(lossy.uncoveredFraction == 0.5)
    #expect(lossy.indicatesLoss)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/116"))
func bothTheRowCountAndTheShareAreNeededToCallARecognitionIncomplete() {
    // Six uncovered rows are more than a fifth of this page's ink and still not loss: a caption
    // Vision folded into its neighbor, a stamp it read as art, a running head it skipped.
    let few = reading(rows: 16, covered: 10)
    #expect(few.uncoveredRows == 6)
    #expect(few.uncoveredFraction > OCRTextCoverage.minimumUncoveredFraction)
    #expect(!few.indicatesLoss)

    // Eight uncovered rows on a dense page are a small share of it, and not loss either.
    let sparse = reading(rows: 50, covered: 42)
    #expect(sparse.uncoveredRows == 8)
    #expect(sparse.uncoveredFraction < OCRTextCoverage.minimumUncoveredFraction)
    #expect(!sparse.indicatesLoss)

    // Both together: the same eight rows on a page whose writing is only forty rows.
    let loss = reading(rows: 40, covered: 32)
    #expect(loss.uncoveredRows == 8)
    #expect(loss.uncoveredFraction >= OCRTextCoverage.minimumUncoveredFraction)
    #expect(loss.indicatesLoss)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/116"))
func theRetrysBandsCoverThePageWithoutTranscribingTheirSharedStripTwice() throws {
    // The bands' geometry: two 60% bands sharing the middle fifth of the page.
    #expect(OCRReader.retryBands == [0.4...1.0, 0.0...0.6])
    #expect(OCRReader.retryBands.allSatisfy { $0.contains(OCRReader.retryBandSplit) })

    func band(_ lines: [(String, Double)]) -> OCRReader.Recognition {
        OCRReader.Recognition(lines: lines.map {
            OCRReader.Recognition.Line(text: $0.0, box: CGRect(x: 0.1, y: $0.1, width: 0.8, height: 0.02),
                                       wraps: nil)
        })
    }
    // Each band reads the strip it shares with the other, so "shared" is read twice in band
    // coordinates: once near the bottom of the top band, once near the top of the bottom band.
    // Whichever band holds its center keeps it, so the page is transcribed once.
    let top = band([("heading", 0.9), ("shared", 0.18)])
    let bottom = band([("shared", 0.83), ("footnote", 0.05)])
    let merged = OCRReader.mergeBands([(top, 0.4, 0.6), (bottom, 0.0, 0.6)])
    #expect(merged.lines.map(\.text) == ["heading", "shared", "footnote"])

    // Every line is back in page coordinates, inside the band's own share of the page.
    let heading = try #require(merged.lines.first)
    #expect(abs(heading.box.minY - (0.4 + 0.9 * 0.6)) < 1e-9)
    #expect(abs(heading.box.height - 0.02 * 0.6) < 1e-9)
    #expect(merged.lines.allSatisfy { (0.0...1.0).contains($0.box.minY) })
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/116"))
func aTableTheBandsCutInTwoIsJoinedRatherThanReportedTwice() throws {
    func band(_ tables: [CGRect]) -> OCRReader.Recognition {
        OCRReader.Recognition(lines: [], tables: tables)
    }
    // One table across the middle of the page: each band sees the part that falls inside it.
    let top = band([CGRect(x: 0.1, y: 0.0, width: 0.8, height: 0.5)])       // 0.40-0.70 of the page
    let bottom = band([CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.3)])    // 0.42-0.60 of the page
    let merged = OCRReader.mergeBands([(top, 0.4, 0.6), (bottom, 0.0, 0.6)])
    #expect(merged.tables.count == 1)
    let table = try #require(merged.tables.first)
    #expect(abs(table.minY - 0.4) < 1e-9)
    #expect(abs(table.maxY - 0.7) < 1e-9)
}

// MARK: - A reading measured by what it wrote, not by where it looked (#240)

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/240"))
func aLineCoversOnlyAsMuchOfItsRowAsItsTranscriptionCanFill() {
    let page = raster(height: 2400, background: 255, ink: 0, rows: 16)
    let boxes = (0..<16).map { rowBox($0, height: 2400) }

    // A box over every row of the page, believed on its own, accounts for all of its writing.
    // This is what the page's own text layer is measured as, before any recognition (#93, #176).
    let believed = OCRTextCoverage.measure(page, boxes: boxes, excluded: [], pixelsPerPoint: 1)
    #expect(believed.textRows == 16)
    #expect(believed.uncoveredRows == 0)
    #expect(!believed.indicatesLoss)

    // The same boxes from a reading that came back with four characters where each row holds
    // fifteen: most of every row is writing the reading did not transcribe, and a box cannot
    // vouch for writing its own text cannot fill. This is the Warren endnote failure — Vision
    // returns the line it found and part of what it says, and the box hides the rest.
    let truncated = OCRTextCoverage.measure(page, lines: boxes.map {
        OCRTextCoverage.Line(box: $0, advances: 4)
    }, excluded: [], pixelsPerPoint: 1)
    #expect(truncated.textRows == 16)
    #expect(truncated.uncoveredRows == 16)
    #expect(truncated.indicatesLoss)

    // A transcription that fills its box covers it, so a complete reading is unchanged.
    let complete = OCRTextCoverage.measure(page, lines: boxes.map {
        OCRTextCoverage.Line(box: $0, advances: 16)
    }, excluded: [], pixelsPerPoint: 1)
    #expect(complete.uncoveredRows == 0)
    #expect(!complete.indicatesLoss)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/240"))
func aWidelyDrawnScriptIsNotMistakenForAReadingThatDroppedHalfThePage() {
    // A fullwidth or ideographic character is drawn about twice as wide as a Latin one, so it
    // counts twice: without that, a sound reading of a Chinese page measures as one that came
    // back with half the writing.
    #expect(OCRTextCoverage.advances(of: "abcd") == 4)
    #expect(OCRTextCoverage.advances(of: "a b\tc\nd") == 4)
    #expect(OCRTextCoverage.advances(of: "報稅") == 4)
    #expect(OCRTextCoverage.advances(of: "第 1 頁") == 5)   // two ideographs and a digit
    #expect(OCRTextCoverage.advances(of: "") == 0)

    // The same eight-character row, read in each script, covers the same width of writing.
    let page = raster(height: 2400, background: 255, ink: 0, rows: 16)
    let boxes = (0..<16).map { rowBox($0, height: 2400) }
    func measure(_ text: String) -> OCRTextCoverage.Measurement {
        OCRTextCoverage.measure(page, lines: boxes.map {
            OCRTextCoverage.Line(box: $0, advances: OCRTextCoverage.advances(of: text))
        }, excluded: [], pixelsPerPoint: 1)
    }
    #expect(measure("abcdefghijklmnop").uncoveredRows == measure("報稅表格的第一頁").uncoveredRows)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/240"))
func aRetryThatCostsThePageWordsIsNotKept() {
    // The retry is kept for covering more of the page's writing.
    #expect(OCRReader.bandsAreKept(uncoveredInk: 100, words: 500, overUncoveredInk: 400, words: 300))
    // Covering no more of it is no reason to prefer it.
    #expect(!OCRReader.bandsAreKept(uncoveredInk: 400, words: 900, overUncoveredInk: 400, words: 300))
    // Covering more of it while saying less is a reading spread wider and read thinner: the page
    // keeps the reading it had, so no page loses words to the retry.
    #expect(!OCRReader.bandsAreKept(uncoveredInk: 100, words: 299, overUncoveredInk: 400, words: 300))
    // Equal words and more cover is still a gain: the same words over more of the page.
    #expect(OCRReader.bandsAreKept(uncoveredInk: 100, words: 300, overUncoveredInk: 400, words: 300))
}

// #7's own page, replayed rather than re-measured (#269, #281).
//
// Warren report page 636 is the faint carbon typescript this library's inherited-layer rules were
// built on: `tcld t» ftboot` for "told me about". Its layer fails the misread test, so the page is
// planned `.compare` — recognized again, and the layer kept unless the fresh reading misreads a
// smaller share of its own words.
//
// The corpus case `gpo-warren-1964-suspect-text-excerpt` used to pin which side of that comparison
// won: two phrases read off the source raster, the absence of the discarded layer's `ftboot`, and
// the `ocrUsed` warning. It cannot. The comparison turns on a margin of about five points between
// the reading's misread share and the layer's 23.8%, and the reading is Vision's, which differs
// between two runs of one binary on one host: three captures of this page taken minutes apart in
// one session returned 28 lines each and 1,653, — and 1,647 characters, and the first held both
// phrases where the third held neither. The lane therefore reported FAIL for a condition of the
// host, on a tree that had not changed (#269, #281, #284).
//
// So the contract pins the finding and the page image, which every run agrees on, and the
// comparison is replayed here from two captures: the layer as PDFKit hands it over, and one
// recognition of the same page as Vision returned it. What this says is what the library does with
// that reading. It says nothing about which reading Vision will return next, and it is not
// supposed to.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/269"))
func aMisreadCarbonTypescriptIsReplacedByARecognitionThatReadsBetter() throws {
    try #require(EnglishText.wordCounts("the") != nil, "no system English lexicon")
    let excerptSHA256 = "bfe984ba3327be017dd38bc4a100251292489efa6faa643b80682dae49b53348"
    let layer = try SourceLayoutFixture.load("warren-636")
    let capture = try SourceRecognitionFixture.load("warren-636")
    #expect(capture.sourceSHA256 == excerptSHA256)
    #expect(capture.page == 4)

    // The layer's own evidence, which is fixed and is what the corpus contract still pins.
    let counts = try #require(EnglishText.wordCounts(layer.lines.map(\.text).joined(separator: "\n")))
    guard case .misreadWords(let misread, let words, _)? = TextLayerPlausibility.wordFinding(counts) else {
        Issue.record("warren-636 no longer reads as a misread layer: \(counts)"); return
    }
    let finding = TextLayerPlausibility.Finding.misreadWords(misread: misread, words: words,
                                                             examples: counts.misreadExamples)
    let evidence = PageEvidence(requiresPageImage: false, hasText: true,
                                characters: layer.lines.map(\.text.count).reduce(0, +),
                                replacementCharacters: 0, imageBackedText: false,
                                damagedEncoding: false, implausibleLayer: finding, drawnText: false)
    // A layer this damaged is compared, not replaced outright and not kept (#7).
    let plan = RecognitionPolicy.plan(evidence, policy: .automatic)
    #expect(plan == .recognize(.compare(misread: misread, words: words), keepCropsIfUnread: false))

    // Given this reading, the comparison goes to the recognition.
    let reading = capture.reading()
    let resolution = RecognitionPolicy.resolve(plan, evidence: evidence, outcome: .read(reading),
                                               judge: .english(language: "en"))
    guard case .replaced(let replacement) = resolution.disposition else {
        Issue.record("the layer was kept over this reading: \(resolution.disposition)"); return
    }
    #expect(resolution.warnings.contains(.ocrUsed))
    // Both phrases were read directly off the source raster when the case was reviewed, and the
    // discarded layer's own misread token is gone.
    let text = replacement.lines.map(\.text).joined(separator: " ")
    #expect(text.contains("and he told me about the things at"))
    #expect(text.contains("At 6:00 PM I instructed the officers to bring"))
    #expect(!text.contains("ftboot"))
    #expect(layer.lines.contains { $0.text.contains("ftboot") })
    // And the layer's finding is reported whichever side wins, which is why the contract can pin
    // it: the page says its layer was damaged either way.
    #expect(resolution.warnings.contains { if case .implausibleTextLayer = $0 { true } else { false } })
    let kept = RecognitionPolicy.resolve(plan, evidence: evidence, outcome: .failed,
                                         judge: .english(language: "en"))
    #expect(kept.disposition == .keptLayer)
    #expect(kept.warnings.contains { if case .implausibleTextLayer = $0 { true } else { false } })
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/192")) func drawnWritingIsRecoveredBesideARealWordInAnyDeclaredLanguage() async throws {
    let slide = try drawnTextPDF(sentence: question, folio: "Goals", background: 0.25, ink: 1)
    for language in ["en", "ar", "zh-Hans"] {
        let (result, text) = try await reflow(slide, language: language)
        #expect(result.recognizedPageCount == 1)
        #expect(text.contains("Goals"))
        #expect(text.lowercased().contains("large data volumes"), "\(language): \(text)")
        #expect(result.imageCount >= 2)
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/192")) func aNativeWordAndDrawnWordsOnOneRowAreNotDuplicated() async throws {
    let slide = try drawnTextPDF(sentence: ["support user analysis", "of very large data volumes?"],
                                 folio: nil, background: 0.25, ink: 1, nativeWord: "Goals")
    let (result, text) = try await reflow(slide, recognize: { page, options in
        let reading = try await OCRReader.read(page: page, options: options, wordPositions: true)
        #expect(reading.lines.contains { $0.text.contains("Goals support user analysis") })
        return reading
    })
    #expect(result.recognizedPageCount == 1)
    #expect(text.components(separatedBy: "Goals").count == 2, "\(text)")
    #expect(text.contains("Goals support user analysis of very large data volumes?"), "\(text)")
    #expect(result.book.blocks.contains { block in
        let inline: InlineText
        switch block.content {
        case .paragraph(let text), .heading(_, let text, _): inline = text
        default: return false
        }
        return inline.elements.contains { if case .text(let text, let style) = $0 {
            return text.contains("Goals") && style.contains(.bold)
        }; return false }
    })
}
