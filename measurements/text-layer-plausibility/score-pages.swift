import Foundation

// Scores survey-pages records with the converter's own `TextLayerPlausibility` (#93) and prints
// one tab-separated row per page: the word counts, the ink measurement at 180 DPI, and which test
// fails (`words`, `ink`, or `-`). The ink columns come from the survey, which measured every page;
// the converter renders only layers with fewer than `maximumWordsForInkTest` English words
// (`inkTested`).
// Build: build-tool.sh score-pages.swift <scratch>/score-pages
// Usage: score-pages <book>.jsonl ... > scores.tsv
@main struct ScorePages {
    struct Ink: Decodable { var dpi: Double, textRows: Int, uncoveredRows: Int, textInk: Int, uncoveredInk: Int }
    struct Record: Decodable { var page: Int, text: String, ink: [Ink] }

    static func main() throws {
        print(["book", "page", "tokens", "numericTokens", "english", "damaged", "neutral", "englishShare",
               "numericShare", "inkTested", "textRows", "uncoveredRows", "uncoveredFraction", "fails"]
            .joined(separator: "\t"))
        for path in CommandLine.arguments.dropFirst() {
            let book = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            for line in try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n") {
                let record = try JSONDecoder().decode(Record.self, from: Data(line.utf8))
                guard let counts = TextLayerPlausibility.englishWordCounts(record.text) else { fatalError("no lexicon") }
                let ink = record.ink.first { $0.dpi == 180 }!
                let measurement = OCRTextCoverage.Measurement(textRows: ink.textRows, uncoveredRows: ink.uncoveredRows,
                                                              textInk: ink.textInk, uncoveredInk: ink.uncoveredInk)
                let lines = [TextLine(text: record.text, rect: .zero, fontSize: 10)]
                let finding = TextLayerPlausibility.judge(lines: lines, language: "en") { measurement }
                let inkTested = TextLayerPlausibility.wordFinding(counts) == nil
                    && counts.english < TextLayerPlausibility.maximumWordsForInkTest
                let fails: String
                switch finding {
                case .fewEnglishWords: fails = "words"
                case .missingText: fails = "ink"
                case nil: fails = "-"
                }
                func share(_ a: Int, _ b: Int) -> String { b == 0 ? "" : String(format: "%.3f", Double(a) / Double(b)) }
                print([book, "\(record.page)", "\(counts.tokens)", "\(counts.numericTokens)", "\(counts.english)",
                       "\(counts.damaged)", "\(counts.neutral)", share(counts.english, counts.judged),
                       share(counts.numericTokens, counts.tokens), inkTested ? "1" : "0", "\(ink.textRows)",
                       "\(ink.uncoveredRows)", share(ink.uncoveredInk, ink.textInk), fails].joined(separator: "\t"))
            }
        }
    }
}
