import CoreGraphics
import CoreText
import Foundation
import Testing
import ZIPFoundation
@testable import PDFReflowLib

// #106: the book language reaches Vision as a supported recognition language, and a language
// Vision does not list is reported once per conversion.

private let frenchLines = [
    "Le général a été élevé à Besançon, où l'été est très chaud.",
    "Après la rentrée, les élèves répètent leurs leçons à côté du théâtre.",
    "La société française préfère les fenêtres ouvertes même en hiver.",
    "Il était déjà là quand sa sœur arriva ; ça ne l'a pas étonné.",
    "Les numéros de téléphone sont écrits sur la première page du cahier.",
    "On a dû créer une bibliothèque près de l'hôpital et de la gare.",
]

private let accentedWords = ["général", "Besançon", "élèves", "leçons", "théâtre", "société", "française",
                             "préfère", "fenêtres", "étonné", "numéros", "téléphone", "première",
                             "bibliothèque", "hôpital"]

/// A page image of `lines` at 150 dpi, drawn at half resolution and scaled up like a soft scan.
private func scanImage(_ lines: [String]) throws -> CGImage {
    let width = 1_275, height = 1_650, scale: CGFloat = 0.5
    let space = CGColorSpaceCreateDeviceRGB(), info = CGImageAlphaInfo.noneSkipLast.rawValue
    let small = try #require(CGContext(data: nil, width: Int(CGFloat(width) * scale), height: Int(CGFloat(height) * scale),
                                       bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info))
    small.setFillColor(CGColor(gray: 1, alpha: 1))
    small.fill(CGRect(x: 0, y: 0, width: width, height: height))
    small.scaleBy(x: scale, y: scale)
    pdfKitGated {
        let font = CTFontCreateWithName("Times New Roman" as CFString, 30, nil)
        for (index, line) in lines.enumerated() {
            let text = NSAttributedString(string: line, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)])
            small.textPosition = CGPoint(x: 120, y: CGFloat(height - 200 - index * 52))
            CTLineDraw(CTLineCreateWithAttributedString(text), small)
        }
    }
    let big = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: space, bitmapInfo: info))
    big.interpolationQuality = .medium
    big.draw(try #require(small.makeImage()), in: CGRect(x: 0, y: 0, width: width, height: height))
    return try #require(big.makeImage())
}

/// A two-page image-only PDF (letter size), each page the same French scan.
private func frenchScanPDF(at url: URL) throws {
    var box = CGRect(x: 0, y: 0, width: 612, height: 792)
    let context = try #require(CGContext(url as CFURL, mediaBox: &box, nil))
    let image = try scanImage(frenchLines)
    for _ in 0..<2 {
        context.beginPDFPage(nil)
        context.draw(image, in: box)
        context.endPDFPage()
    }
    context.closePDF()
}

private func chapterText(_ url: URL) throws -> String {
    let archive = try Archive(url: url, accessMode: .read)
    var bytes = Data()
    _ = try archive.extract(try #require(archive["EPUB/chapter-1.xhtml"])) { bytes += $0 }
    return String(decoding: bytes, as: UTF8.self)
}

@Test func frenchScanIsRecognizedWithTheFrenchLanguageAndReadsItsAccents() async throws {
    #expect(OCRReader.recognitionRequest(language: "fr").textRecognitionOptions.recognitionLanguages
            == [Locale.Language(identifier: "fr-FR")])
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let source = dir.appendingPathComponent("french-scan.pdf")
    try frenchScanPDF(at: source)

    var hits: [String: Int] = [:]
    var reports: [String: ConversionReport] = [:]
    for language in ["fr", "en", "tlh"] {
        var options = ConversionOptions()
        options.language = language
        options.removeRepeatedHeadersAndFooters = false
        let output = dir.appendingPathComponent(language + ".epub")
        let report = try await PDFConverter().convert(from: source, to: output, options: options)
        #expect(report.recognizedPageCount == 2)
        let html = try chapterText(output)
        hits[language] = accentedWords.filter { html.components(separatedBy: $0).count - 1 == 2 }.count
        reports[language] = report
    }
    // Distinctive accented words read on both pages. On the macOS 27 SDK, with language correction
    // off, French and US English recognition read this scan identically, so the French run must
    // do at least as well rather than strictly better (measurements/ocr-language/record.md).
    let french = try #require(hits["fr"]), english = try #require(hits["en"])
    #expect(french >= accentedWords.count * 2 / 3)
    #expect(french >= english)

    // Only a language Vision does not list is reported, once, on the first recognized page.
    for language in ["fr", "en"] {
        #expect(!(reports[language]?.warnings ?? []).contains { $0.message.contains("Vision does not recognize") })
    }
    let fallback = (reports["tlh"]?.warnings ?? []).filter { $0.message.contains("Vision does not recognize") }
    #expect(fallback.count == 1)
    #expect(fallback.first?.code == .ocrUsed && fallback.first?.page == 1)
    #expect(fallback.first?.message.contains("book language tlh") == true)
    #expect(fallback.first?.message.contains("(en-US)") == true)
}
