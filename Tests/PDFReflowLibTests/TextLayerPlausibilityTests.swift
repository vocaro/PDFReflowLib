import CoreGraphics
import CoreText
import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

// #93: inherited text over a page-sized image that fails the English plausibility test is
// replaced by OCR under `.automatic`, kept under `.automaticKeepingImageBackedText` and `.never`,
// and reported as `implausibleTextLayer` either way.

@Test func wordCountsSortEnglishDamagedAndNeutralWords() {
    let lexicon: Set<String> = ["the", "movie", "strange"]
    let counts = TextLayerPlausibility.wordCounts("a sreANee v/eus n e x t The NASA Kennedy movie's 42 strange vrius") {
        lexicon.contains($0)
    }
    // English: a, The, movie('s), strange. Damaged: sreANee (capitalization), n e x t (stray
    // letters), vrius (unknown lower case). Neutral: v/eus (symbol), NASA, Kennedy (names).
    #expect(counts.english == 4)
    #expect(counts.damaged == 6)
    #expect(counts.neutral == 3)
    #expect(counts.numericTokens == 1 && counts.tokens == 14)
}

@Test func wordTestNeedsEnoughWordsFewerThanHalfEnglishAndFewNumbers() {
    typealias Counts = TextLayerPlausibility.WordCounts
    #expect(TextLayerPlausibility.wordFinding(Counts(english: 9, damaged: 11, tokens: 20))
        == .fewEnglishWords(english: 9, judged: 20))
    #expect(TextLayerPlausibility.wordFinding(Counts(english: 10, damaged: 10, tokens: 20)) == nil)  // half English
    #expect(TextLayerPlausibility.wordFinding(Counts(english: 5, damaged: 14, tokens: 19)) == nil)   // 19 judged
    #expect(TextLayerPlausibility.wordFinding(Counts(english: 5, damaged: 15, numericTokens: 5, tokens: 25)) == nil)
    #expect(TextLayerPlausibility.wordFinding(Counts(english: 5, damaged: 15, numericTokens: 4, tokens: 25)) != nil)
}

@Test func inkTestNeedsMostTextInkUncoveredInSevenRowsAndFewerWordsThanRows() {
    func measurement(rows: Int, uncovered: Int) -> OCRTextCoverage.Measurement {
        OCRTextCoverage.Measurement(textRows: 10, uncoveredRows: rows, textInk: 100, uncoveredInk: uncovered)
    }
    #expect(TextLayerPlausibility.inkFinding(measurement(rows: 7, uncovered: 75), englishWords: 6)
        == .missingText(uncoveredFraction: 0.75, uncoveredRows: 7, englishWords: 6))
    #expect(TextLayerPlausibility.inkFinding(measurement(rows: 6, uncovered: 90), englishWords: 0) == nil)
    #expect(TextLayerPlausibility.inkFinding(measurement(rows: 9, uncovered: 74), englishWords: 0) == nil)
    #expect(TextLayerPlausibility.inkFinding(measurement(rows: 7, uncovered: 90), englishWords: 7) == nil)
}

// #7's `RecognitionPlan.Mode.compare` (misread-in-place) and #176's `drawnText` candidacy (`reflowsNoWords`) are
// gated on opposite ends of the same word count, so a page can never trigger both at once: a
// `.misreadWords` finding needs `judged >= minimumJudgedWords` (20), while `reflowsNoWords` holds
// only when literally no line has a single letter, which leaves the layer's `words`/`judged`
// counts at zero (`wordCounts` drops any token with no letter before it ever reaches a word
// bucket). This is a structural proof, not a sampled negative control: the two thresholds cannot
// both be satisfied by the same `lines`.
@Test func misreadInPlaceAndReflowsNoWordsCannotBothHoldForTheSameLines() {
    let noLetters = [TextLine(text: "5", rect: .zero, fontSize: 10), TextLine(text: "10-12", rect: .zero, fontSize: 10),
                     TextLine(text: "37) 5 2 3", rect: .zero, fontSize: 10)]
    #expect(TextLayerPlausibility.reflowsNoWords(noLetters))
    let counts = TextLayerPlausibility.wordCounts(noLetters.map(\.text).joined(separator: "\n")) { _ in true }
    #expect(counts.judged == 0 && counts.words == 0)
    #expect(TextLayerPlausibility.wordFinding(counts) == nil)
    // Any lines that satisfy reflowsNoWords contain no letters at all, so no `isWord` closure
    // (real lexicon or this permissive stub) can ever find a judged word among them.
    typealias Counts = TextLayerPlausibility.WordCounts
    #expect(TextLayerPlausibility.wordFinding(Counts(english: 0, damaged: 0, tokens: noLetters.count)) == nil)
}

@Test func judgeRendersOnlySparseEnglishLayers() throws {
    try #require(TextLayerPlausibility.englishWordCounts("the") != nil, "no system English lexicon")
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

@Test func realInheritedLayersFailOrPassTheWordTest() throws {
    try #require(TextLayerPlausibility.englishWordCounts("the") != nil, "no system English lexicon")
    func counts(_ name: String) throws -> TextLayerPlausibility.WordCounts {
        let fixture = try SourceLayoutFixture.load(name)
        return try #require(TextLayerPlausibility.englishWordCounts(fixture.lines.map(\.text).joined(separator: "\n")))
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
    #expect(Double(typescript.english) >= Double(typescript.judged) * TextLayerPlausibility.maximumEnglishShare)
    // So is the comic's page 4 (#168), 0.6 English.
    if case .misreadWords? = TextLayerPlausibility.wordFinding(try counts("cdc-4")) {} else { Issue.record("cdc-4 passed") }
}

@Test func misreadWordsAreDamagedWordsNoNeighbourCompletes() {
    let lexicon: Set<String> = ["the", "field", "strength", "with", "when"]
    let counts = TextLayerPlausibility.wordCounts("tbe fi e ld stre ngth witb vhen McDonald sreANee th e") { lexicon.contains($0) }
    // Misread: tbe, witb, vhen, sreANee. Split, not misread: fi e ld, stre ngth, th e (joined with a
    // neighbour they make field, strength, the). A compound name's capitals are not damage.
    #expect(counts.misread == 4)
    #expect(counts.misreadExamples == ["tbe", "witb", "vhen"])
    #expect(counts.neutral == 1)
    typealias Counts = TextLayerPlausibility.WordCounts
    #expect(TextLayerPlausibility.wordFinding(Counts(english: 18, damaged: 2, neutral: 0, tokens: 20, misread: 2,
                                                     misreadExamples: ["tbe"]))
        == .misreadWords(misread: 2, words: 20, examples: ["tbe"]))
    #expect(TextLayerPlausibility.wordFinding(Counts(english: 18, damaged: 2, neutral: 1, tokens: 21, misread: 2)) == nil)
}

@Test func otherScriptsAreDamageAndRecognizedTitlesMustReadAsWords() throws {
    try #require(TextLayerPlausibility.englishWordCounts("the") != nil, "no system English lexicon")
    // Recognition of handwriting and of the comic's all-caps exclamations.
    let mixed = TextLayerPlausibility.wordCounts("DeالasTaxaع НИН the") { $0 == "the" }
    #expect(mixed.damaged == 2 && mixed.english == 1)
    #expect(TextLayerPlausibility.foreignLetters("НИН?!") == 3)
    #expect(TextLayerPlausibility.foreignLetters("Besançon, Việt, ﬁeld") == 0)
    for title in ["INDEX OF TABLES", "Table A59. Evaluation of All Sightings for 1952", "SEPTEMBER", "SECTION D",
                  "PARKLAND MEMORIAL HOSPITAL"] {
        #expect(TextLayerPlausibility.readsAsWords(title), "\(title)")
    }
    // Table cells and handwriting read at heading size under `--ocr always`.
    for noise in ["139", "1952 1950", "a0 0.0", "• a0", "0 00 a0 a0 a o e 00.00 a0", "Pags", "Certaia Doubtlul Total Cotai",
                  "Tag De Praciy Glii tant ami She", "стрлда ві. 1)", "Crมn C Tม Cour oi Ica"] {
        #expect(!TextLayerPlausibility.readsAsWords(noise), "\(noise)")
    }
}

@Test func recognitionIsJudgedByItsEnglishShareUnlessItIsAnotherLanguage() throws {
    try #require(TextLayerPlausibility.englishWordCounts("the") != nil, "no system English lexicon")
    func lines(_ text: String) -> [TextLine] { [TextLine(text: text, rect: CGRect(x: 0, y: 0, width: 100, height: 10), fontSize: 10)] }
    // Handwriting recognition, abridged: read as noise.
    let noise = "PARKLAND MEMORIAL HOSPITAL ADMISSION NOTE iar mhele aandeuzen tro gret ancr fuom lhe sae intr ond deta "
        + "vrenl mit shert oo kaat pols reat erad huoi fis tne aad lov ot pert"
    #expect(TextLayerPlausibility.judgeRecognized(lines: lines(noise), language: "en") != nil)
    #expect(TextLayerPlausibility.judgeRecognized(lines: lines(noise), language: "fr") == nil)
    // A page in French is text, not noise, in a book declared English.
    let french = "Le général a été élevé à Besançon, où l'été est très chaud. Après la rentrée, les élèves répètent leurs "
        + "leçons à côté du théâtre. La société française préfère les fenêtres ouvertes même en hiver."
    #expect(TextLayerPlausibility.readsAsAnotherLanguage(french))
    #expect(TextLayerPlausibility.judgeRecognized(lines: lines(french), language: "en") == nil)
    // Misreading a tenth of its words does not discard a recognition that reads as English.
    let comic = Array(repeating: "MAN I FORGOT I HAD THIS. IT USED TO BE MY DAD'S powtred radic", count: 3).joined(separator: " ")
    #expect(TextLayerPlausibility.judgeRecognized(lines: lines(comic), language: "en") == nil)
    #expect(TextLayerPlausibility.readsBetter(lines(comic), than: 30, of: 100, language: "en"))
    #expect(!TextLayerPlausibility.readsBetter(lines(comic), than: 1, of: 100, language: "en"))
    #expect(!TextLayerPlausibility.readsBetter(lines(noise), than: 50, of: 100, language: "en"))
}

@Test func warningStatesWhatFailedAndWhatWasDone() {
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

@Test func misreadInPlaceLayerComparesAgainstRecognitionEndToEnd() async throws {
    try #require(TextLayerPlausibility.englishWordCounts("the") != nil, "no system English lexicon")
    let counts = try #require(TextLayerPlausibility.englishWordCounts(misreadInPlaceDialogue.joined(separator: "\n")))
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
    return (result, result.document.blocks.map(\.text).joined(separator: " "))
}

@Test func implausibleInheritedWordsAreReplacedByDefaultAndReportedUnderEveryPolicy() async throws {
    try #require(TextLayerPlausibility.englishWordCounts("the") != nil, "no system English lexicon")
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

@Test func inheritedLayerMissingMostOfThePageTextIsReplaced() async throws {
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
