import Foundation
import CryptoKit
import CoreText
import PDFKit
#if os(macOS)
import AppKit
private typealias SurveyFont = NSFont
#else
import UIKit
private typealias SurveyFont = UIFont
#endif

// Survey-only instrumentation for #180 item 1. Run from the repository root:
//
//   swiftc -O Sources/PDFReflowLib/NativeTextReader.swift … tools/…/survey-marker-sizes.swift
//   ./survey-marker-sizes <corpus-case-id>
//
// It writes one TSV row per PDFKit line with more than one run, which is every line whose measured
// size could differ from the size of its text. Columns:
//
//   page  lineIndex  firstSize  restSize  restConsistent  runCount  firstRun  text
//
// No library behaviour is read from this file; it re-walks PDFKit's selections the way
// `NativeTextReader.extractLines` does, without the repairs that do not change a run's point size.
@main struct SurveyMarkerSizes {
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 2 else { fatalError("usage: survey-marker-sizes <corpus-case-id>") }
        let manifest = try JSONSerialization.jsonObject(
            with: Data(contentsOf: URL(fileURLWithPath: "corpus/manifest.json"))) as! [String: Any]
        let cases = manifest["documents"] as! [[String: Any]]
        guard let item = cases.first(where: { $0["id"] as? String == arguments[1] }),
              let file = item["filename"] as? String, let expected = item["sha256"] as? String else {
            fatalError("Unknown corpus case")
        }
        let source = URL(fileURLWithPath: "corpus/cache/" + file)
        let data = try Data(contentsOf: source)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == expected else { fatalError("Source identity mismatch") }
        guard let document = PDFDocument(url: source) else { throw CocoaError(.fileReadCorruptFile) }
        let out = FileHandle.standardOutput
        func emit(_ line: String) { out.write(Data((line + "\n").utf8)) }
        emit("page\tline\tfirstSize\trestSize\trestConsistent\truns\tfirstRun\ttext")
        for index in 0..<document.pageCount {
            autoreleasepool {
                guard let page = document.page(at: index),
                      let selection = page.selection(for: page.bounds(for: .cropBox)) else { return }
                for (order, piece) in selection.selectionsByLine().enumerated() {
                    guard let attributed = piece.attributedString, attributed.length > 0 else { continue }
                    let text = attributed.string.replacingOccurrences(of: "\u{FFFC}", with: " ")
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    var runs: [(String, Double)] = []
                    attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, range, _ in
                        let font = attributes[.font] as? SurveyFont
                        runs.append(((attributed.string as NSString).substring(with: range),
                                     Double(font?.pointSize ?? 0)))
                    }
                    guard let first = runs.first, first.1 > 0, runs.count > 1 else { continue }
                    let rest = runs.dropFirst().filter { !$0.0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    guard let second = rest.first else { continue }
                    let consistent = rest.allSatisfy { abs($0.1 - second.1) <= second.1 * 0.1 }
                    func escape(_ value: String) -> String {
                        value.replacingOccurrences(of: "\\", with: "\\\\")
                            .replacingOccurrences(of: "\t", with: "\\t")
                            .replacingOccurrences(of: "\n", with: "\\n")
                            .replacingOccurrences(of: "\r", with: "\\r")
                    }
                    emit("\(index + 1)\t\(order)\t\(first.1)\t\(second.1)\t\(consistent)\t\(runs.count)\t"
                        + "\(escape(String(first.0.prefix(12))))\t\(escape(String(text.prefix(120))))")
                }
            }
        }
    }
}
