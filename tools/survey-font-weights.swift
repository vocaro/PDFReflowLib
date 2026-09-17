import Foundation
import PDFKit
#if os(macOS)
import AppKit
private typealias SurveyFont = NSFont
#else
import UIKit
private typealias SurveyFont = UIFont
#endif

// Font weight survey (#125). Build from the repository root with the reader it measures:
//   swiftc -O -parse-as-library tools/survey-font-weights.swift Sources/PDFReflowLib/FontWeightReader.swift \
//       Sources/PDFReflowLib/NativeSpacingReader.swift -o <scratch>/survey-font-weights
//   <scratch>/survey-font-weights <corpus-case-id> [first-page last-page]
// Prints one tab-separated row per font resource (BaseFont, subtype, FontWeight, StemV, Flags,
// ToUnicode, text shows, PDFKit's font names on the runs of lines drawn in that resource alone,
// the name rule's verdict and the weight-aware verdict), then the PDFKit line runs whose bold
// status the reader changes.
@main struct SurveyFontWeights {
    struct Row {
        var info: FontWeightReader.FontInfo
        var shows = 0
        var pdfkitNames: [String: Int] = [:]
    }

    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 2 || arguments.count == 4 else {
            fatalError("usage: survey-font-weights <corpus-case-id> [first-page last-page]")
        }
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "corpus/manifest.json"))) as! [String: Any]
        let cases = manifest["documents"] as! [[String: Any]]
        guard let item = cases.first(where: { $0["id"] as? String == arguments[1] }),
              let file = item["filename"] as? String,
              let document = PDFDocument(url: URL(fileURLWithPath: "corpus/cache/" + file)) else { fatalError("Unknown corpus case") }
        let first = arguments.count == 4 ? Int(arguments[2])! : 1
        let last = arguments.count == 4 ? min(Int(arguments[3])!, document.pageCount) : document.pageCount
        var rows: [String: Row] = [:]
        var unreadable = 0
        var changedRuns = 0, boldRunsBefore = 0, boldRunsAfter = 0, runs = 0
        var examples: [String] = []
        var changedByPage: [Int: Int] = [:]
        for number in first...last {
            try autoreleasepool {
                guard let page = document.page(at: number - 1), let reference = page.pageRef else { return }
                var ids: [Int: FontWeightReader.FontInfo] = [:]
                let shows = FontWeightReader.read(reference) { id, info in ids[id] = info }
                if shows.isEmpty && !ids.isEmpty { unreadable += 1 }
                func key(_ info: FontWeightReader.FontInfo) -> String {
                    "\(info.baseFont ?? "-")|\(info.subtype)|\(info.fontWeight.map { "\($0)" } ?? "-")|\(info.stemV.map { "\($0)" } ?? "-")|\(info.flags.map(String.init) ?? "-")"
                }
                for show in shows {
                    guard let info = ids[show.font] else { continue }
                    rows[key(info), default: Row(info: info)].shows += 1
                }
                for info in ids.values where rows[key(info)] == nil { rows[key(info)] = Row(info: info) }
                guard let selection = page.selection(for: page.bounds(for: .cropBox)) else { return }
                let lines = selection.selectionsByLine()
                let bounds = lines.map { $0.bounds(for: page) }
                for (line, rect) in zip(lines, bounds) {
                    guard let attributed = line.attributedString, attributed.length > 0 else { continue }
                    // PDFKit's names for a font resource: the runs of lines whose every show (origin in
                    // the line and in no other line) selects that one resource.
                    let area = rect.insetBy(dx: -0.75, dy: -0.75)
                    let own = shows.filter { area.contains($0.origin) }
                    if let font = own.first?.font, own.allSatisfy({ $0.font == font }), let info = ids[font],
                       own.allSatisfy({ show in bounds.filter { $0.insetBy(dx: -0.75, dy: -0.75).contains(show.origin) }.count == 1 }) {
                        attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
                            let text = (attributed.string as NSString).substring(with: range)
                            guard text.contains(where: { $0.isLetter || $0.isNumber }), let name = (value as? SurveyFont)?.fontName else { return }
                            rows[key(info)]?.pdfkitNames[name, default: 0] += 1
                        }
                    }
                    let marked = FontWeightReader.apply(shows, to: attributed, bounds: rect, allBounds: bounds)
                    marked.enumerateAttributes(in: NSRange(location: 0, length: marked.length)) { attributes, range, _ in
                        let text = (marked.string as NSString).substring(with: range)
                        guard text.contains(where: { $0.isLetter || $0.isNumber }) else { return }
                        runs += 1
                        let name = (attributes[.font] as? SurveyFont)?.fontName ?? ""
                        let before = name.lowercased().contains("bold")
                        let after = before || attributes[FontWeightReader.boldAttribute] != nil
                        if before { boldRunsBefore += 1 }
                        if after { boldRunsAfter += 1 }
                        if before != after {
                            changedRuns += 1
                            changedByPage[number, default: 0] += 1
                            if examples.count < 60 {
                                examples.append("p\(number)\t\(name)\t\(text.replacingOccurrences(of: "\n", with: " ").prefix(70))")
                            }
                        }
                    }
                }
            }
        }
        print("# \(arguments[1]) pages \(first)-\(last); pages whose scan failed: \(unreadable)")
        print("baseFont\tsubtype\tFontWeight\tStemV\tFlags\tToUnicode\tshows\tPDFKit names\tname rule bold\tweight-aware bold")
        for (_, row) in rows.sorted(by: { $0.value.shows > $1.value.shows }) {
            let info = row.info
            let names = row.pdfkitNames.sorted { $0.value > $1.value }.map { "\($0.key)×\($0.value)" }.joined(separator: ", ")
            // The name rule's verdict on the font: its most frequent PDFKit name (runs of lines drawn
            // in this resource alone; `-` when no such line exists).
            let majority = row.pdfkitNames.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
            let current = majority.map { $0.lowercased().contains("bold") ? "yes" : "no" } ?? "-"
            let aware = info.weight.map { $0 == .bold ? "yes" : "no" } ?? "unknown"
            print("\(info.baseFont ?? "-")\t\(info.subtype)\t\(info.fontWeight.map { "\(Int($0))" } ?? "-")\t\(info.stemV.map { "\(Int($0))" } ?? "-")\t\(info.flags.map(String.init) ?? "-")\t\(info.hasToUnicode ? "yes" : "no")\t\(row.shows)\t\(names)\t\(current)\t\(aware)")
        }
        print("# line runs \(runs); bold by name rule \(boldRunsBefore); bold with font resources \(boldRunsAfter); changed \(changedRuns) on \(changedByPage.count) pages")
        print("# pages with changes: \(changedByPage.keys.sorted().map(String.init).joined(separator: " "))")
        for example in examples { print("  \(example)") }
    }
}
