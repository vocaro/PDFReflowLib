// Corpus survey for #115: which line-end hyphen decisions the inflection tier
// (`LayoutReconstructor.inflectionVouches`) changes. Not part of the package; to run, copy it into
// the test target and name the cases:
//
//   cp measurements/list-bullets-and-coded-reports/InflectionSurvey.swift Tests/PDFReflowLibTests/
//   INFLECTION_SURVEY=wallace-algebra-2010 INFLECTION_SURVEY_OUT=/tmp/survey \
//     swift test --filter inflectionSurvey
//   rm Tests/PDFReflowLibTests/InflectionSurvey.swift
//
// Evidence is native extraction (`NativeTextReader`, hidden text removed as the pipeline does, no
// OCR, before furniture and layout), with the pipeline's vocabulary (`addVocabulary`). Every
// consecutive pair of lines on a page is a candidate join, carrying the text after the last space
// so an address broken over several lines stays whole, as #101's survey does. For each prose
// break (not an address) the survey records whether the decision reached the tier (neither the
// joined word nor the compound decided it) and whether the tier removes the hyphen. Every break
// the tier reaches is listed, with the book's forms that vouch or the reason it declines.
import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

@Test func inflectionSurvey() throws {
    guard let cases = ProcessInfo.processInfo.environment["INFLECTION_SURVEY"],
          let out = ProcessInfo.processInfo.environment["INFLECTION_SURVEY_OUT"] else { return }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("corpus/manifest.json"))) as! [String: Any]
    let documents = manifest["documents"] as! [[String: Any]]
    try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
    for id in cases.split(separator: ",").map(String.init) {
        let item = try #require(documents.first { $0["id"] as? String == id })
        let url = root.appendingPathComponent("corpus/cache/" + (item["filename"] as! String))
        let document = try #require(PDFDocument(url: url))
        var pages: [PageContent] = []
        var vocabulary: Set<String> = []
        for index in 0..<document.pageCount {
            try autoreleasepool {
                guard let page = document.page(at: index), let reference = page.pageRef else { return }
                let graphics = GraphicsReader.read(reference)
                var lines = try NativeTextReader.lines(on: page, limit: 10_000_000, includeStyle: false)
                _ = HiddenTextFilter.removeHidden(&lines, graphics: graphics)
                let content = PageContent(number: index + 1, bounds: page.bounds(for: .cropBox), lines: lines, graphics: [])
                LayoutReconstructor.addVocabulary(of: content, to: &vocabulary)
                pages.append(content)
            }
        }
        var report = "# \(id)\n"
        var breaks = 0, joinedDecides = 0, compoundDecides = 0, reached = 0, removed = 0
        for page in pages {
            var tail = ""
            for line in page.lines {
                defer {
                    var warnings: [ConversionWarning] = []
                    let text = tail.isEmpty ? line.text
                        : LayoutReconstructor.join(tail, line.text, vocabulary: vocabulary, page: page.number, warnings: &warnings)
                    tail = String(text.split(separator: " ", omittingEmptySubsequences: false).last ?? "")
                }
                guard !tail.isEmpty, tail.hasSuffix("-"), line.text.first?.isLowercase == true,
                      LayoutReconstructor.trailingAddress(tail) == nil else { continue }
                breaks += 1
                let prefix = String(tail.dropLast().reversed().prefix(while: { $0.isLetter }).reversed()).lowercased()
                let suffix = String(line.text.prefix(while: { $0.isLetter })).lowercased()
                let joined = prefix + suffix, compound = prefix + "-" + suffix
                if vocabulary.contains(joined), !vocabulary.contains(compound) { joinedDecides += 1; continue }
                if vocabulary.contains(compound) { compoundDecides += 1; continue }
                reached += 1
                let vouches = LayoutReconstructor.inflectionVouches(prefix: prefix, suffix: suffix, vocabulary: vocabulary)
                if vouches { removed += 1 }
                let forms = LayoutReconstructor.inflectedForms(joined).filter { $0 != joined && vocabulary.contains($0) }.sorted()
                let halves = "prefixWord=\(vocabulary.contains(prefix)) suffixWord=\(vocabulary.contains(suffix))"
                report += "\(vouches ? "REMOVED" : "kept   ") p\(page.number) \(tail.suffix(30)) + \(line.text.prefix(30)) -> \(vouches ? joined : compound)"
                    + " forms=[\(forms.joined(separator: ","))] \(halves)\n"
            }
        }
        report += "breaks \(breaks), joined decides \(joinedDecides), compound decides \(compoundDecides), reach tier \(reached), tier removes \(removed)\n"
        try report.write(toFile: out + "/\(id).txt", atomically: true, encoding: .utf8)
    }
}
