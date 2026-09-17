// Corpus survey for #96: where the coded weather report recogniser fires. Not part of the package;
// to run, copy it into the test target and name the cases:
//
//   cp measurements/list-bullets-and-coded-reports/CodedReportSurvey.swift Tests/PDFReflowLibTests/
//   CODED_SURVEY=faa-phak-8083-25c CODED_SURVEY_OUT=/tmp/survey swift test --filter codedReportSurvey
//   rm Tests/PDFReflowLibTests/CodedReportSurvey.swift
//
// Evidence is native extraction (`NativeTextReader`, hidden text removed, no OCR, before furniture
// and layout), each page's lines in extraction order. It lists every line carrying at least two
// report groups (`codedReportGroupCount`), so near misses show, and every run `codedReportRuns`
// finds, with its joined text. The pipeline runs the recogniser over body reading order, where a
// run can also be cut by an image, table or note; the lane EPUB comparisons confirm the rest.
import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

@Test func codedReportSurvey() throws {
    guard let cases = ProcessInfo.processInfo.environment["CODED_SURVEY"],
          let out = ProcessInfo.processInfo.environment["CODED_SURVEY_OUT"] else { return }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("corpus/manifest.json"))) as! [String: Any]
    let documents = manifest["documents"] as! [[String: Any]]
    try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
    for id in cases.split(separator: ",").map(String.init) {
        let item = try #require(documents.first { $0["id"] as? String == id })
        let url = root.appendingPathComponent("corpus/cache/" + (item["filename"] as! String))
        let document = try #require(PDFDocument(url: url))
        var report = "# \(id)\n"
        var candidates = 0, runs = 0
        for index in 0..<document.pageCount {
            try autoreleasepool {
                guard let page = document.page(at: index), let reference = page.pageRef else { return }
                let graphics = GraphicsReader.read(reference)
                var lines = try NativeTextReader.lines(on: page, limit: 10_000_000, includeStyle: false)
                _ = HiddenTextFilter.removeHidden(&lines, graphics: graphics)
                let sizes = lines.map { Int($0.fontSize.rounded()) }
                let body = CGFloat(Dictionary(grouping: sizes, by: { $0 }).max { $0.value.count < $1.value.count }?.key ?? 10)
                for line in lines {
                    guard let count = LayoutReconstructor.codedReportGroupCount(line.text), count >= 2 else { continue }
                    candidates += 1
                    report += "line p\(index + 1) groups=\(count) \(line.text.prefix(90))\n"
                }
                for run in LayoutReconstructor.codedReportRuns(lines, body: body) {
                    runs += 1
                    let text = run.map { (lines[$0.index].text, $0.lineBreak) }.enumerated()
                        .map { $0.offset == 0 ? $0.element.0 : ($0.element.1 ? " ⏎ " : " ") + $0.element.0 }.joined()
                    report += "RUN p\(index + 1) lines=\(run.count) \(text)\n"
                }
            }
        }
        report += "lines with two or more groups \(candidates), runs \(runs)\n"
        try report.write(toFile: out + "/\(id).txt", atomically: true, encoding: .utf8)
    }
}
