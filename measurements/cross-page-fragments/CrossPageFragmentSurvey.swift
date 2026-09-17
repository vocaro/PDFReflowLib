// Corpus survey for #107: what the vocabulary's fragment rule (#101, carried across page breaks by
// #148) still misses when matter outside the body text stream — a folio, a running foot, a note —
// stands between a page's hyphenated last body line and the next page's continuation. Not part of
// the package; to run, copy it into the test target and name the cases:
//
//   cp measurements/cross-page-fragments/CrossPageFragmentSurvey.swift Tests/PDFReflowLibTests/
//   XPAGE_SURVEY=fed-explained-2021,wallace-algebra-2010 XPAGE_SURVEY_OUT=/tmp/xpage \
//     swift test --filter crossPageFragmentSurvey
//   rm Tests/PDFReflowLibTests/CrossPageFragmentSurvey.swift
//
// Evidence is native extraction (`NativeTextReader`, hidden text removed as the pipeline does, no
// OCR, before layout), which is what the pipeline collects vocabulary from.
//
// Three carries are compared, each over the same lines, so the vocabularies differ only by which
// words the fragment rule skips:
//   old — the rule before this change: the carried line stands until the page's first body-sized
//         line, which then replaces it together with every line after it, so a folio or a note
//         under the last body line is what the next page reads.
//   new — the rule this change adopts: the carried line stands until the page's first text-stream
//         line, every line stands as the line above the one below it, and the line carried to the
//         next page is the last text-stream line.
//   ref — what the rule would see if it ran after furniture removal: `FurnitureDetector.strip`
//         runs over the same pages, the previous line is simply the previous surviving line, and
//         the carry is the stripped page's last line. Words of the removed lines still count,
//         since furniture words are not fragments.
// `build` mirrors `LayoutReconstructor.addVocabulary` with the skip decision supplied; the survey
// asserts that the mirror under `new` equals `LayoutReconstructor.vocabulary(in:)`, so a drift
// between the survey and the library fails the run rather than biasing the counts.
import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

private func hyphenEnd(_ text: String?) -> Bool {
    guard let text else { return false }
    return text.hasSuffix("-") || text.hasSuffix("\u{00ad}") || LayoutReconstructor.endsWithEqualsHyphen(text)
}

private func pageMeasures(_ page: PageContent) -> [Int: CGFloat] {
    page.recognized || page.hasSyntheticTextStyle ? [:] : LayoutReconstructor.justifiedMeasures(page.lines)
}

/// The text a line carries on with, given the hyphen its page printed where extraction lost one.
private func carried(_ line: TextLine, measures: [Int: CGFloat]) -> String {
    line.text + (LayoutReconstructor.endsShortOfMeasure(line, measures: measures) ? "-" : "")
}

private func isBody(_ line: TextLine, _ body: CGFloat) -> Bool { abs(line.fontSize - body) <= body * 0.15 }

/// A line of the page's own text stream: set in the body's size and printing a lowercase letter.
/// A running head or a folio the book sets in the body's own size prints none beside its page
/// number (`84 THE 9/11 COMMISSION REPORT`, `62`).
private func isTextStream(_ line: TextLine, _ body: CGFloat) -> Bool {
    isBody(line, body) && line.text.contains(where: \.isLowercase)
}

/// Whether the line opening after `previous` opens with the rest of a broken word.
private func skips(previous: String?, line: TextLine) -> Bool {
    guard hyphenEnd(previous), line.text.first?.isLowercase == true else { return false }
    guard let first = line.text.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "-" }).first else { return false }
    return !first.contains("-")
}

/// `LayoutReconstructor.addVocabulary`, with the skip decision supplied per line as `(page, line)`.
private func build(_ pages: [PageContent], skipping skipped: Set<String>) -> Set<String> {
    var vocabulary: Set<String> = []
    for page in pages {
        for (index, line) in page.lines.enumerated() {
            var words = line.text.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "-" })
            if skipped.contains("\(page.number):\(index)"), !words.isEmpty { words.removeFirst() }
            if let split = LayoutReconstructor.dropCapSplit(line), words.count >= 2 {
                words.removeFirst(2)
                if !"AIO".contains(split.initial) {
                    vocabulary.insert(String(split.initial).lowercased() + split.fragment.lowercased())
                }
            }
            for word in words {
                vocabulary.insert(String(word))
                if word.contains(where: LayoutReconstructor.isLigature) {
                    vocabulary.insert(LayoutReconstructor.ligaturesSpelledOut(word))
                }
            }
            LayoutReconstructor.addAddressVocabulary(of: line.text, to: &vocabulary)
            LayoutReconstructor.addNumberPrefixVocabulary(of: line.text, to: &vocabulary)
            LayoutReconstructor.addDashVocabulary(of: line.text, to: &vocabulary)
        }
    }
    return vocabulary
}

@Test func crossPageFragmentSurvey() throws {
    guard let cases = ProcessInfo.processInfo.environment["XPAGE_SURVEY"],
          let out = ProcessInfo.processInfo.environment["XPAGE_SURVEY_OUT"] else { return }
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
        var stripped = pages
        _ = FurnitureDetector.strip(&stripped)
        // Which original line each surviving line is, so a removal can be placed in the page.
        var survivors: [[Int]] = []
        for (page, clean) in zip(pages, stripped) {
            var indices: [Int] = [], next = 0
            for line in clean.lines {
                while next < page.lines.count, page.lines[next].text != line.text { next += 1 }
                if next < page.lines.count { indices.append(next); next += 1 }
            }
            survivors.append(indices.count == clean.lines.count ? indices : Array(page.lines.indices))
        }

        var removedHead = 0, removedFoot = 0, removedMiddle = 0, middleLines: [String] = []
        for (pageIndex, page) in pages.enumerated() {
            let kept = Set(survivors[pageIndex])
            let removed = page.lines.indices.filter { !kept.contains($0) }
            for (rank, index) in removed.enumerated() {
                if index == rank {
                    removedHead += 1
                } else if index == page.lines.count - (removed.count - rank) {
                    removedFoot += 1
                } else {
                    removedMiddle += 1
                    let above = index > 0 ? page.lines[index - 1].text : ""
                    let below = index + 1 < page.lines.count ? page.lines[index + 1].text : ""
                    let hides = hyphenEnd(above) && below.first?.isLowercase == true
                    if hides || middleLines.count < 10 {
                        middleLines.append("\(hides ? "MIDDLE-HIDES" : "MIDDLE") p\(page.number)#\(index)/\(page.lines.count)"
                            + " [\(above.suffix(40))] / [\(page.lines[index].text.prefix(40))] / [\(below.prefix(40))]")
                    }
                }
            }
        }

        // The three skip sets.
        var oldSkips: Set<String> = [], newSkips: Set<String> = [], referenceSkips: Set<String> = []
        var oldPrevious: String?, newPrevious: String?, referencePrevious: String?
        var oldCarries: [String?] = [], newCarries: [String?] = []
        for (pageIndex, page) in pages.enumerated() {
            let body = max(4, LayoutReconstructor.bodySize(page.lines))
            let measures = pageMeasures(page)
            oldCarries.append(oldPrevious)
            newCarries.append(newPrevious)
            // old: the carried line stands until the first body-sized line, which then replaces it
            // together with every line after it.
            var reachedBody = false, old = oldPrevious
            // new: the carried line stands until the first text-stream line, every line stands as
            // the line above the one below it, and the last text-stream line is carried on.
            let carry = newPrevious
            var reachedStream = false, above: String?, last: String?
            for (index, line) in page.lines.enumerated() {
                if skips(previous: old, line: line) { oldSkips.insert("\(page.number):\(index)") }
                if skips(previous: above, line: line) || (!reachedStream && skips(previous: carry, line: line)) {
                    newSkips.insert("\(page.number):\(index)")
                }
                if isBody(line, body) { reachedBody = true }
                if reachedBody { old = carried(line, measures: measures) }
                // Set in the body's own size and printing a lowercase letter: the page's own text,
                // not a running head or a folio the book sets at body size.
                if isTextStream(line, body) {
                    reachedStream = true
                    last = carried(line, measures: measures)
                }
                above = carried(line, measures: measures)
            }
            oldPrevious = old
            if let last { newPrevious = last }
            // The reference: the stripped page, with no furniture in the way at all.
            let clean = stripped[pageIndex]
            let cleanMeasures = pageMeasures(clean)
            var reference = referencePrevious
            for (cleanIndex, line) in clean.lines.enumerated() {
                if skips(previous: reference, line: line) {
                    referenceSkips.insert("\(page.number):\(survivors[pageIndex][cleanIndex])")
                }
                reference = carried(line, measures: cleanMeasures)
            }
            if !clean.lines.isEmpty { referencePrevious = reference }
        }

        let oldVocabulary = build(pages, skipping: oldSkips)
        let newVocabulary = build(pages, skipping: newSkips)
        let referenceVocabulary = build(pages, skipping: referenceSkips)
        // The mirror under the proposed rule must be the library's own vocabulary, so a drift
        // between the survey and the library fails the run rather than biasing the counts.
        #expect(newVocabulary == LayoutReconstructor.vocabulary(in: pages), "\(id): survey mirror drifted from the library")

        report += "pages \(pages.count), old words \(oldVocabulary.count), new words \(newVocabulary.count)"
            + ", reference words \(referenceVocabulary.count)\n"
        report += "furniture lines removed: head \(removedHead), foot \(removedFoot), middle \(removedMiddle)\n"
        for line in middleLines { report += "  \(line)\n" }
        report += "skips: old \(oldSkips.count), new \(newSkips.count), reference \(referenceSkips.count)\n"
        func show(_ set: Set<String>) -> String {
            set.sorted().map { $0.hasPrefix("\u{1}") ? String($0.dropFirst()) + "[key]" : $0 }.joined(separator: " ")
        }
        for (name, left, right) in [("new drops from old", oldVocabulary, newVocabulary),
                                    ("new adds over old", newVocabulary, oldVocabulary),
                                    ("reference drops that new keeps", newVocabulary, referenceVocabulary),
                                    ("reference keeps that new drops", referenceVocabulary, newVocabulary)] {
            let difference = left.subtracting(right)
            report += "\(name) \(difference.count): \(show(difference))\n"
        }
        // Every skip the three rules disagree on, with its source lines.
        for key in oldSkips.symmetricDifference(newSkips).union(newSkips.symmetricDifference(referenceSkips)).sorted() {
            let parts = key.split(separator: ":")
            guard let number = Int(parts[0]), let index = Int(parts[1]),
                  let pageIndex = pages.firstIndex(where: { $0.number == number }) else { continue }
            let page = pages[pageIndex]
            let above = index > 0 ? page.lines[index - 1].text
                : "«page \(pageIndex > 0 ? pages[pageIndex - 1].number : 0) carry» old [\(oldCarries[pageIndex]?.suffix(40) ?? "—")] new [\(newCarries[pageIndex]?.suffix(40) ?? "—")]"
            report += "SKIP \(key) old=\(oldSkips.contains(key)) new=\(newSkips.contains(key)) ref=\(referenceSkips.contains(key))"
                + " above [\(above.suffix(70))] line [\(page.lines[index].text.prefix(60))]\n"
        }

        // Every line-end hyphen decision that changes, under the same join the pipeline runs.
        func decisions(_ vocabulary: Set<String>) -> [String: (text: String, warned: Bool)] {
            var result: [String: (String, Bool)] = [:]
            for page in pages {
                var tail = ""
                for (index, line) in page.lines.enumerated() {
                    defer {
                        var warnings: [ConversionWarning] = []
                        let text = tail.isEmpty ? line.text
                            : LayoutReconstructor.join(tail, line.text, vocabulary: vocabulary, page: page.number, warnings: &warnings)
                        tail = String(text.split(separator: " ", omittingEmptySubsequences: false).last ?? "")
                    }
                    guard !tail.isEmpty, tail.hasSuffix("-") || tail.hasSuffix("\u{00ad}"),
                          line.text.first?.isLowercase == true else { continue }
                    var warnings: [ConversionWarning] = []
                    let joined = LayoutReconstructor.join(tail, String(line.text.prefix(60)), vocabulary: vocabulary,
                                                          page: page.number, warnings: &warnings)
                    result["\(page.number):\(index)"] = (String(joined.split(separator: " ").first.map(String.init) ?? joined),
                                                         !warnings.isEmpty)
                }
            }
            return result
        }
        let before = decisions(oldVocabulary), after = decisions(newVocabulary), ideal = decisions(referenceVocabulary)
        var changed = 0, residual = 0
        for key in Set(before.keys).sorted() {
            func show(_ value: (text: String, warned: Bool)?) -> String {
                value.map { "\($0.text)\($0.warned ? " [warn]" : "")" } ?? "—"
            }
            if before[key]?.text != after[key]?.text || before[key]?.warned != after[key]?.warned {
                changed += 1
                report += "CHANGED \(key) old \(show(before[key])) new \(show(after[key]))\n"
            }
            if after[key]?.text != ideal[key]?.text || after[key]?.warned != ideal[key]?.warned {
                residual += 1
                report += "RESIDUAL \(key) new \(show(after[key])) reference \(show(ideal[key]))\n"
            }
        }
        report += "in-page hyphen decisions changed: \(changed), still short of the reference: \(residual)\n"

        // Every page break whose carry ends in a hyphen, joined with the next page's opening line,
        // under both vocabularies. The pipeline decides these in block reconstruction; this shows
        // which of them the vocabulary change reaches.
        var crossPage = 0, crossPageChanged = 0
        for (pageIndex, page) in pages.enumerated() {
            guard let left = newCarries[pageIndex], hyphenEnd(left) else { continue }
            let body = max(4, LayoutReconstructor.bodySize(page.lines))
            var opening: TextLine?
            for line in page.lines {
                opening = line
                if isBody(line, body) { break }
            }
            guard let opening, opening.text.first?.isLowercase == true else { continue }
            crossPage += 1
            let right = String(opening.text.prefix(60))
            var oldWarnings: [ConversionWarning] = [], newWarnings: [ConversionWarning] = []
            let tail = String(left.split(separator: " ", omittingEmptySubsequences: false).last ?? "")
            let oldJoin = LayoutReconstructor.join(tail, right, vocabulary: oldVocabulary, page: page.number, warnings: &oldWarnings)
            let newJoin = LayoutReconstructor.join(tail, right, vocabulary: newVocabulary, page: page.number, warnings: &newWarnings)
            let differs = oldJoin != newJoin || oldWarnings.map(\.code) != newWarnings.map(\.code)
            if differs { crossPageChanged += 1 }
            report += "\(differs ? "XPAGECHANGED" : "XPAGE") p\(page.number) \(tail.suffix(40)) + \(right.prefix(30))"
                + " -> old \(oldJoin.split(separator: " ").first.map(String.init) ?? oldJoin)\(oldWarnings.isEmpty ? "" : " [warn]")"
                + " new \(newJoin.split(separator: " ").first.map(String.init) ?? newJoin)\(newWarnings.isEmpty ? "" : " [warn]")\n"
        }
        report += "cross-page hyphen breaks: \(crossPage), changed by the vocabulary: \(crossPageChanged)\n"
        try report.write(toFile: out + "/\(id).txt", atomically: true, encoding: .utf8)
    }
}
