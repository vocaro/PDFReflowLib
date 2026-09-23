// Standalone Vision probe for #108 item 2. Apple SDKs only: Core Text draws a few lines of
// synthetic type into a bitmap, and Vision reads that bitmap under each recognition language.
//
//   xcrun swiftc -O probe.swift -o vision-language-probe
//   ./vision-language-probe [font-size, default 40]
//
// What it measures: whether an all-capital Cyrillic word whose every letter is drawn the same as
// a Latin letter (`КОМАР ТАРА`) comes back as Latin under `ru` and `ru-RU`, whether the same
// happens to a word holding a letter with no Latin look-alike (`ЖУРНАЛ`), to lower case, and to
// Latin all-look-alike words standing in a Russian text (`TAX COMPACT`), which is what a repair
// keyed on the declared language would have to leave alone. The pixels are hashed so a reading
// that differs between languages cannot be a difference in what Vision was shown.
import CryptoKit
import CoreText
import Foundation
import Vision

let fontSize = CommandLine.arguments.count > 1 ? (Double(CommandLine.arguments[1]) ?? 40) : 40

/// Each bitmap is one "page" of the lines listed, so a reading of one line cannot borrow its
/// language from a neighbour of another script.
let pages: [(name: String, lines: [String])] = [
    ("capitals-look-alike", ["КОМАР ТАРА", "МОРЕ СОРТ ХОР", "ВОРОН ТОРТ МАМА"]),
    ("capitals-control", ["ЖУРНАЛ ДОМ", "ГОРОД ЛЕС", "ЗИМА ШУМ"]),
    ("lowercase-look-alike", ["комар тара", "море сорт хор", "ворон торт мама"]),
    ("russian-sentence", ["Мама мыла раму.", "Комар сел на торт.", "Сахар и кофе на столе."]),
    ("latin-in-russian", ["TAX COMPACT", "NASA MOCK", "Отчёт NASA за год."]),
    ("mixed-capitals", ["КОМАР TAX", "PACT ТОРТ"]),
    // A look-alike word beside one with a letter outside the table, on one line: does Vision
    // decide the script per line or per word?
    ("look-alike-beside-control", ["КОМАР NASA", "ТОРТ ЖУК", "МОСКВА USA"]),
    // Acronyms and names a Russian book sets in capitals, made only of look-alike letters.
    ("russian-acronyms", ["МОСКВА", "ТАСС СССР НАТО", "ОТЧЕТ"]),
    // Lower-case Latin beside Russian, which the rule leaves alone whatever Vision does.
    ("lowercase-mixed", ["комар tax", "море compact хор"]),
    // Roman numerals and initials a Russian book sets beside its capitals: a numeral of X, C and
    // M alone is made of look-alike letters, and so is an initial.
    ("roman-and-initials", ["XX ВЕК", "ГЛАВА XX", "XIX ВЕК", "М. ГОРЬКИЙ", "С. ЕСЕНИН"]),
]

func render(_ lines: [String]) -> (CGImage, String) {
    let width = 1400, lineHeight = Int(fontSize * 1.8), margin = 60
    let height = lineHeight * lines.count + margin * 2
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { exit(1) }
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let font = CTFontCreateWithName("Times New Roman" as CFString, fontSize, nil)
    for (index, text) in lines.enumerated() {
        let attributed = NSAttributedString(string: text, attributes: [
            kCTFontAttributeName as NSAttributedString.Key: font,
            kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(gray: 0, alpha: 1)])
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = CGPoint(x: margin, y: height - margin - lineHeight * (index + 1) + Int(fontSize * 0.4))
        CTLineDraw(line, context)
    }
    let pixels = Data(bytes: context.data!, count: context.bytesPerRow * height)
    let digest = SHA256.hash(data: pixels).map { String(format: "%02x", $0) }.joined()
    return (context.makeImage()!, String(digest.prefix(12)))
}

func read(_ image: CGImage, language: String?) async throws -> [String] {
    var request = RecognizeDocumentsRequest()
    request.textRecognitionOptions.useLanguageCorrection = false
    if let language {
        request.textRecognitionOptions.recognitionLanguages = [Locale.Language(identifier: language)]
    }
    let observations = try await request.perform(on: image, orientation: nil)
    return observations.first?.document.text.lines.compactMap { $0.topCandidates(1).first?.string } ?? []
}

func script(_ text: String) -> String {
    let cyrillic = text.unicodeScalars.filter { (0x0400...0x04FF).contains($0.value) }.count
    let latin = text.unicodeScalars.filter { $0.properties.isAlphabetic && $0.isASCII }.count
    return "cyr=\(cyrillic) lat=\(latin)"
}

let probe = RecognizeDocumentsRequest()
let supported = probe.supportedRecognitionLanguages
print("supportedRecognitionLanguages: \(supported.map(\.minimalIdentifier).joined(separator: " "))")
print("default recognitionLanguages: \(probe.textRecognitionOptions.recognitionLanguages.map(\.minimalIdentifier))")
for tag in ["ru", "ru-RU", "uk", "uk-UA", "en", "en-US"] {
    print("contains(\(tag)) = \(supported.contains(Locale.Language(identifier: tag)))")
}
print("font size \(fontSize)")
for page in pages {
    let (image, digest) = render(page.lines)
    print("\n== \(page.name) (pixels \(digest))")
    for line in page.lines { print("   drawn: \(line)") }
    for language in [nil, "ru", "ru-RU", "uk-UA", "en-US"] as [String?] {
        let lines = try await read(image, language: language)
        print("  [\(language ?? "default")]")
        for line in lines { print("     \(line)   (\(script(line)))") }
    }
}
