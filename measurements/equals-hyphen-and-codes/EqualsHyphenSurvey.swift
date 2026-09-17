// Corpus survey for #126: `=` as a book's line-end hyphen. Not part of the package; to run, copy it
// into the test target and name the cases:
//
//   cp measurements/equals-hyphen-and-codes/EqualsHyphenSurvey.swift Tests/PDFReflowLibTests/
//   EQUALS_SURVEY=gpo-911-2004,wallace-algebra-2010 EQUALS_SURVEY_OUT=/tmp/survey \
//     swift test --filter equalsHyphenSurvey
//   rm Tests/PDFReflowLibTests/EqualsHyphenSurvey.swift
//
// Evidence is native extraction (`NativeTextReader`, hidden text removed as the pipeline does, no
// OCR, before furniture and layout), as in `measurements/hyphen-fragments/FragmentSurvey.swift`.
// Per book it prints `EqualsHyphenEvidence` and every line `endsWithEqualsHyphen` accepts. In a
// book the evidence marks, each such line is rewritten by `restoreEqualsHyphens` and joined to the
// next line on its page with the real `LayoutReconstructor.join` and the book's vocabulary, and the
// decision is classified by the policy tier that made it. The pipeline joins lines that layout
// groups, so a pair here is a candidate join; the lane EPUB diff confirms the rest.
import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

@Test func equalsHyphenSurvey() throws {
    guard let cases = ProcessInfo.processInfo.environment["EQUALS_SURVEY"],
          let out = ProcessInfo.processInfo.environment["EQUALS_SURVEY_OUT"] else { return }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("corpus/manifest.json"))) as! [String: Any]
    let documents = manifest["documents"] as! [[String: Any]]
    try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
    for id in cases.split(separator: ",").map(String.init) {
        let item = try #require(documents.first { $0["id"] as? String == id })
        let url = root.appendingPathComponent("corpus/cache/" + (item["filename"] as! String))
        let document = try #require(PDFDocument(url: url))
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
        var vocabulary: Set<String> = []
        var evidence = LayoutReconstructor.EqualsHyphenEvidence()
        for page in pages {
            LayoutReconstructor.addVocabulary(of: page, to: &vocabulary)
            evidence.add(page)
        }
        var report = "# \(id)\npages \(pages.count), breaks \(evidence.breaks), other = lines \(evidence.equations), marks hyphens \(evidence.marksHyphens)\n"
        var tiers: [String: Int] = [:]
        for var page in pages {
            let original = page.lines.map(\.text)
            if evidence.marksHyphens { LayoutReconstructor.restoreEqualsHyphens(&page) }
            for index in page.lines.indices where LayoutReconstructor.endsWithEqualsHyphen(original[index]) {
                guard evidence.marksHyphens else {
                    report += "p\(page.number)\taccepted, not rewritten\t\(original[index].suffix(40))\n"
                    continue
                }
                let left = page.lines[index].text
                guard index + 1 < page.lines.count else {
                    tiers["page end", default: 0] += 1
                    report += "p\(page.number)\tpage end\t\(left.suffix(30))\n"
                    continue
                }
                let right = page.lines[index + 1].text
                var warnings: [ConversionWarning] = []
                let joined = LayoutReconstructor.join(left, right, vocabulary: vocabulary, page: page.number, warnings: &warnings)
                let prefix = String(left.dropLast().reversed().prefix { $0.isLetter }.reversed()).lowercased()
                let suffix = right.prefix { $0.isLetter }.lowercased()
                let tier: String
                if joined == left + " " + right {
                    tier = "space (next opens \(right.first.map { $0.isNumber ? "digit" : $0.isUppercase ? "capital" : "other" } ?? "empty"))"
                } else if joined == String(left.dropLast()) + right {
                    tier = vocabulary.contains(prefix + suffix) && !vocabulary.contains(prefix + "-" + suffix)
                        ? "removed (joined word)" : "removed (inflected form)"
                } else if warnings.isEmpty {
                    tier = "kept (compound)"
                } else {
                    tier = "kept, warned"
                }
                tiers[tier, default: 0] += 1
                let shown = left.suffix(25) + " | " + right.prefix(25)
                report += "p\(page.number)\t\(tier)\t\(prefix)-\(suffix)\t\(shown)\n"
            }
        }
        // #127: every consecutive pair broken at a hyphen before a digit or capital, and whether
        // `codeContinues` joins it as a code (after any `=` rewrite).
        var codes = 0, others = 0
        for var page in pages {
            if evidence.marksHyphens { LayoutReconstructor.restoreEqualsHyphens(&page) }
            for (left, right) in zip(page.lines, page.lines.dropFirst()) where left.text.hasSuffix("-") {
                guard let next = right.text.first, next.isASCII, next.isNumber || next.isUppercase else { continue }
                let joins = LayoutReconstructor.codeContinues(left.text, right.text)
                if joins { codes += 1 } else { others += 1 }
                report += "code\tp\(page.number)\t\(joins ? "joins" : "space")\t\(left.text.suffix(30)) | \(right.text.prefix(25))\n"
            }
        }
        report += "code breaks: joined \(codes), spaced \(others)\n"
        report += "tiers " + tiers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: ", ") + "\n"
        try report.write(toFile: out + "/\(id).txt", atomically: true, encoding: .utf8)
    }
}
