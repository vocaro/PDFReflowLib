import Foundation

// Scores page texts with the converter's own `TextLayerPlausibility` (#7): inherited layers from
// `../text-layer-plausibility/survey-pages.swift` (with their ink measurement) and recognitions
// from `survey-ocr.swift` (words only). One tab-separated row per page: word counts, the misread
// count and share, letters of other scripts, which test fails (`words`, `misread`, `ink` or `-`), and
// whether the text would be discarded as a recognition (`judgeRecognized`).
// Build: ../text-layer-plausibility/build-tool.sh score-text.swift <scratch>/score-text
// Usage: score-text <book>.jsonl ... > scores.tsv
@main struct ScoreText {
    struct Ink: Decodable { var dpi: Double, textRows: Int, uncoveredRows: Int, textInk: Int, uncoveredInk: Int }
    struct Record: Decodable { var page: Int, text: String, ink: [Ink]? }

    static func main() throws {
        print(["book", "page", "tokens", "numericTokens", "english", "damaged", "neutral", "misread", "englishShare",
               "misreadShare", "numericShare", "letters", "foreignLetters", "uncoveredRows", "uncoveredFraction",
               "fails", "recognitionFails", "examples"].joined(separator: "\t"))
        for path in CommandLine.arguments.dropFirst() {
            let book = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            for line in try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n") {
                let record = try JSONDecoder().decode(Record.self, from: Data(line.utf8))
                guard let counts = TextLayerPlausibility.englishWordCounts(record.text) else { fatalError("no lexicon") }
                let ink = record.ink?.first { $0.dpi == 180 }
                let measurement = ink.map {
                    OCRTextCoverage.Measurement(textRows: $0.textRows, uncoveredRows: $0.uncoveredRows,
                                                textInk: $0.textInk, uncoveredInk: $0.uncoveredInk)
                }
                let lines = [TextLine(text: record.text, rect: .zero, fontSize: 10)]
                let finding = TextLayerPlausibility.judge(lines: lines, language: "en") { measurement }
                let fails: String
                switch finding {
                case .fewEnglishWords: fails = "words"
                case .misreadWords: fails = "misread"
                case .missingText: fails = "ink"
                case nil: fails = "-"
                }
                func share(_ a: Int, _ b: Int) -> String { b == 0 ? "" : String(format: "%.3f", Double(a) / Double(b)) }
                let letters = record.text.unicodeScalars.filter(\.properties.isAlphabetic).count
                print([book, "\(record.page)", "\(counts.tokens)", "\(counts.numericTokens)", "\(counts.english)",
                       "\(counts.damaged)", "\(counts.neutral)", "\(counts.misread)", share(counts.english, counts.judged),
                       share(counts.misread, counts.words), share(counts.numericTokens, counts.tokens), "\(letters)",
                       "\(TextLayerPlausibility.foreignLetters(record.text))", ink.map { "\($0.uncoveredRows)" } ?? "",
                       ink.map { share($0.uncoveredInk, $0.textInk) } ?? "", fails,
                       TextLayerPlausibility.judgeRecognized(lines: lines, language: "en") == nil ? "-" : "words",
                       counts.misreadExamples.joined(separator: " ")].joined(separator: "\t"))
            }
        }
    }
}
