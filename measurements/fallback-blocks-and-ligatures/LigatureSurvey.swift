// Corpus survey for #123 item 1: which line-end hyphen decisions change when the vocabulary folds
// the Latin ligatures U+FB00–U+FB06 (`LayoutReconstructor.vocabularyForm`). Not part of the
// package. It prints every decision, so run it in the candidate tree and in a `git archive` of the
// baseline and diff the outputs:
//
//   cp measurements/fallback-blocks-and-ligatures/LigatureSurvey.swift Tests/PDFReflowLibTests/
//   LIGATURE_SURVEY=wallace-algebra-2010 LIGATURE_SURVEY_OUT=/tmp/survey \
//     swift test --filter ligatureSurvey
//   rm Tests/PDFReflowLibTests/LigatureSurvey.swift
//
// Evidence is native extraction (`NativeTextReader`, hidden text removed as the pipeline does, no
// OCR, before furniture and layout) with the pipeline's vocabulary (`addVocabulary`). Every
// consecutive pair of lines on a page is a candidate join, carrying the text after the last space
// so an address broken over several lines stays whole, as #101's and #115's surveys do. Every
// break at a line-end hyphen before a lowercase letter is listed with the joined text and whether
// it warned, prose and address breaks alike. The survey also counts the vocabulary's words that
// hold a ligature and the words it gains by folding.
import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

@Test func ligatureSurvey() throws {
    guard let cases = ProcessInfo.processInfo.environment["LIGATURE_SURVEY"],
          let out = ProcessInfo.processInfo.environment["LIGATURE_SURVEY_OUT"] else { return }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("corpus/manifest.json"))) as! [String: Any]
    let documents = manifest["documents"] as! [[String: Any]]
    try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
    let ligatures = Set("\u{FB00}\u{FB01}\u{FB02}\u{FB03}\u{FB04}\u{FB05}\u{FB06}")
    for id in cases.split(separator: ",").map(String.init) {
        let item = try #require(documents.first { $0["id"] as? String == id })
        let url = root.appendingPathComponent("corpus/cache/" + (item["filename"] as! String))
        let document = try #require(PDFDocument(url: url))
        var pages: [PageContent] = []
        var vocabulary: Set<String> = []
        var ligatureLines = 0
        for index in 0..<document.pageCount {
            try autoreleasepool {
                guard let page = document.page(at: index), let reference = page.pageRef else { return }
                let graphics = GraphicsReader.read(reference)
                var lines = try NativeTextReader.lines(on: page, limit: 10_000_000, includeStyle: false)
                _ = HiddenTextFilter.removeHidden(&lines, graphics: graphics)
                ligatureLines += lines.filter { $0.text.contains(where: ligatures.contains) }.count
                let content = PageContent(number: index + 1, bounds: page.bounds(for: .cropBox), lines: lines, graphics: [])
                LayoutReconstructor.addVocabulary(of: content, to: &vocabulary)
                pages.append(content)
            }
        }
        var report = "# \(id)\n"
        var breaks = 0, warned = 0
        for page in pages {
            var tail = ""
            for line in page.lines {
                var warnings: [ConversionWarning] = []
                let text = tail.isEmpty ? line.text
                    : LayoutReconstructor.join(tail, line.text, vocabulary: vocabulary, page: page.number, warnings: &warnings)
                if !tail.isEmpty, tail.hasSuffix("-"), line.text.first?.isLowercase == true {
                    breaks += 1
                    if !warnings.isEmpty { warned += 1 }
                    let joined = text.dropFirst(max(0, tail.count - 30)).prefix(60)
                    report += "p\(page.number) \(tail.suffix(30)) + \(line.text.prefix(30)) -> \(joined)\(warnings.isEmpty ? "" : " [uncertainHyphen]")\n"
                }
                tail = String(text.split(separator: " ", omittingEmptySubsequences: false).last ?? "")
            }
        }
        let ligatureWords = vocabulary.filter { $0.contains(where: ligatures.contains) }.count
        report += "breaks \(breaks), warned \(warned), lines with ligatures \(ligatureLines), vocabulary words with ligatures \(ligatureWords), vocabulary \(vocabulary.count)\n"
        try report.write(toFile: out + "/\(id).txt", atomically: true, encoding: .utf8)
    }
}
