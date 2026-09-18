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
    // The CDC comic's damaged dialogue and letter-spaced afterword, and Warren's handwritten exhibit.
    for name in ["cdc-5", "cdc-14", "cdc-23", "cdc-26", "cdc-34", "cdc-37", "warren-553"] {
        let value = try counts(name)
        #expect(TextLayerPlausibility.wordFinding(value) != nil, "\(name): \(value)")
    }
    // Prose, an index and a witness list (the plausible layer nearest the threshold, 0.65 English)
    // keep their text.
    for name in ["warren-50", "warren-520", "warren-910", "blue-12", "blue-5"] {
        let value = try counts(name)
        #expect(TextLayerPlausibility.wordFinding(value) == nil, "\(name): \(value)")
    }
    // Negative control for the numeric guard: a handwritten statistical table and a notes page read
    // under half English, and only their numbers keep them from being judged.
    for name in ["blue-149", "warren-885"] {
        let value = try counts(name)
        #expect(Double(value.english) < Double(value.judged) * TextLayerPlausibility.maximumEnglishShare, "\(name): \(value)")
        #expect(Double(value.numericTokens) >= Double(value.tokens) * TextLayerPlausibility.maximumNumericShare, "\(name): \(value)")
        #expect(TextLayerPlausibility.wordFinding(value) == nil, "\(name): \(value)")
    }
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
