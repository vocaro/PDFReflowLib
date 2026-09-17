// Corpus survey for #101: which line-end hyphen decisions change when the book vocabulary stops
// counting the word that opens a line after a line-end hyphen. Not part of the package; to run,
// copy it into the test target and name the cases:
//
//   cp measurements/hyphen-fragments/FragmentSurvey.swift Tests/PDFReflowLibTests/
//   FRAGMENT_SURVEY=fed-explained-2021,gpo-911-2004 FRAGMENT_SURVEY_OUT=/tmp/survey \
//     swift test --filter fragmentSurvey
//   rm Tests/PDFReflowLibTests/FragmentSurvey.swift
//
// Evidence is native extraction (`NativeTextReader`, hidden text removed as the pipeline does, no
// OCR, before furniture and layout). `old` is the vocabulary as collected before #101 (every word
// of every line); `new` is `LayoutReconstructor.addVocabulary`. Every consecutive pair of lines on
// a page is joined with the real `LayoutReconstructor.join` under both, carrying the text after
// the last space so an address broken over several lines stays whole. The pipeline joins lines
// that layout groups, so a pair here is a candidate join: the lane EPUB diffs confirm the rest.
import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

@Test func fragmentSurvey() throws {
    guard let cases = ProcessInfo.processInfo.environment["FRAGMENT_SURVEY"],
          let out = ProcessInfo.processInfo.environment["FRAGMENT_SURVEY_OUT"] else { return }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("corpus/manifest.json"))) as! [String: Any]
    let documents = manifest["documents"] as! [[String: Any]]
    try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
    for id in cases.split(separator: ",").map(String.init) {
        let item = try #require(documents.first { $0["id"] as? String == id })
        let url = root.appendingPathComponent("corpus/cache/" + (item["filename"] as! String))
        let document = try #require(PDFDocument(url: url))
        var report = "# \(id)\n"
        var pages: [PageContent] = []
        for index in 0..<document.pageCount {
            try autoreleasepool {
                guard let page = document.page(at: index), let reference = page.pageRef else { return }
                let graphics = GraphicsReader.read(reference)
                var lines = try NativeTextReader.lines(on: page, limit: 10_000_000, includeStyle: false)
                _ = HiddenTextFilter.removeHidden(&lines, graphics: graphics)
                pages.append(PageContent(number: index + 1, bounds: page.bounds(for: .cropBox), lines: lines, graphics: []))
            }
        }
        // Old and new vocabularies, and per word how often it opens a line after a hyphen
        // (`continuation`, a word without a hyphen) and how often it occurs anywhere else.
        var old: Set<String> = [], new: Set<String> = []
        var continuation: [String: Int] = [:], elsewhere: [String: Int] = [:]
        for page in pages {
            LayoutReconstructor.addVocabulary(of: page, to: &new)
            var previous: String?
            for line in page.lines {
                let words = line.text.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "-" }).map(String.init)
                old.formUnion(words)
                LayoutReconstructor.addAddressVocabulary(of: line.text, to: &old)
                let opens = previous.map { $0.hasSuffix("-") || $0.hasSuffix("\u{00ad}") } == true
                    && line.text.first?.isLowercase == true
                for (offset, word) in words.enumerated() {
                    if opens && offset == 0 && !word.contains("-") { continuation[word, default: 0] += 1 } else { elsewhere[word, default: 0] += 1 }
                }
                previous = line.text
            }
        }
        let fragments = old.subtracting(new)
        #expect(fragments.allSatisfy { elsewhere[$0] == nil })
        report += "pages \(pages.count), words \(old.filter { !$0.hasPrefix("\u{1}") }.count), fragment-only words removed \(fragments.count)\n"
        func counts(_ word: String) -> String {
            "\(word)[c\(continuation[word] ?? 0)/e\(elsewhere[word] ?? 0)]"
        }
        var breaks = 0, changed = 0, addressBreaks = 0
        for page in pages {
            var oldTail = "", newTail = ""
            for line in page.lines {
                defer {
                    func tail(_ left: String, _ vocabulary: Set<String>) -> String {
                        var warnings: [ConversionWarning] = []
                        let text = left.isEmpty ? line.text
                            : LayoutReconstructor.join(left, line.text, vocabulary: vocabulary, page: page.number, warnings: &warnings)
                        return String(text.split(separator: " ", omittingEmptySubsequences: false).last ?? "")
                    }
                    oldTail = tail(oldTail, old)
                    newTail = tail(newTail, new)
                }
                guard !oldTail.isEmpty, oldTail.hasSuffix("-") || oldTail.hasSuffix("\u{00ad}"),
                      line.text.first?.isLowercase == true else { continue }
                breaks += 1
                let isAddress = LayoutReconstructor.trailingAddress(oldTail) != nil
                if isAddress { addressBreaks += 1 }
                var oldWarnings: [ConversionWarning] = [], newWarnings: [ConversionWarning] = []
                let right = String(line.text.prefix(60))
                let before = LayoutReconstructor.join(oldTail, right, vocabulary: old, page: page.number, warnings: &oldWarnings)
                let after = LayoutReconstructor.join(newTail, right, vocabulary: new, page: page.number, warnings: &newWarnings)
                let prefix = String(oldTail.dropLast().reversed().prefix(while: { $0.isLetter }).reversed()).lowercased()
                let suffix = String(line.text.prefix(while: { $0.isLetter })).lowercased()
                let evidence = "\(counts(prefix)) \(counts(suffix)) \(counts(prefix + suffix)) \(counts(prefix + "-" + suffix))"
                let beforeWord = before.split(separator: " ").first.map(String.init) ?? before
                let afterWord = after.split(separator: " ").first.map(String.init) ?? after
                if beforeWord != afterWord || oldWarnings.map(\.code) != newWarnings.map(\.code) {
                    changed += 1
                    report += "CHANGED p\(page.number)\(isAddress ? " address" : "") \(oldTail.suffix(50)) + \(right.prefix(30))\n"
                    report += "  old \(beforeWord.suffix(70))\(oldWarnings.isEmpty ? "" : " [warn]")\n"
                    report += "  new \(afterWord.suffix(70))\(newWarnings.isEmpty ? "" : " [warn]")\n"
                    report += "  evidence prefix,suffix,joined,compound: \(evidence)\n"
                }
                if isAddress {
                    // #88's word tier accepts one non-word piece because `cations` was a book word.
                    // List every address break the new vocabulary removes through that allowance.
                    let whole = !(oldTail.dropLast().dropLast(prefix.count).last?.isNumber ?? false)
                        && !(line.text.dropFirst(suffix.count).first?.isNumber ?? false)
                    let tierWord = whole && !prefix.isEmpty && !suffix.isEmpty && new.contains(prefix + suffix)
                    var probe: [ConversionWarning] = []
                    let withoutWord = LayoutReconstructor.join(newTail, right, vocabulary: new.subtracting([prefix + suffix]), page: page.number, warnings: &probe)
                    let decidedByWordTier = tierWord && withoutWord != after
                    report += "ADDRESS p\(page.number) \(oldTail.suffix(40)) + \(right.prefix(25)) -> \(afterWord.suffix(40))"
                        + "\(newWarnings.isEmpty ? "" : " [warn]")\(decidedByWordTier ? " wordTier(prefixKnown=\(new.contains(prefix)) suffixKnown=\(new.contains(suffix)); old prefixKnown=\(old.contains(prefix)) suffixKnown=\(old.contains(suffix)))" : "") \(evidence)\n"
                }
            }
        }
        report += "breaks \(breaks), address breaks \(addressBreaks), changed \(changed)\n"
        report += "fragment-only words: \(fragments.sorted().joined(separator: " "))\n"
        try report.write(toFile: out + "/\(id).txt", atomically: true, encoding: .utf8)
    }
}
