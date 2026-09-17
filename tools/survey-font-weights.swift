import Foundation
import PDFKit
#if os(macOS)
import AppKit
private typealias SurveyFont = NSFont
#else
import UIKit
private typealias SurveyFont = UIFont
#endif

// Font weight and slope survey (#125, #133). Build from the repository root with the reader it measures:
//   swiftc -O -parse-as-library tools/survey-font-weights.swift Sources/PDFReflowLib/FontWeightReader.swift \
//       Sources/PDFReflowLib/NativeSpacingReader.swift -o <scratch>/survey-font-weights
//   <scratch>/survey-font-weights <corpus-case-id> [first-page last-page]
// Prints one tab-separated row per font resource (BaseFont, subtype, FontWeight, StemV, Flags,
// ItalicAngle, ToUnicode, text shows, PDFKit's font names on the runs of lines drawn in that
// resource alone, the name rule's bold verdict, the weight-aware verdict, the name slope, the
// name rule's italic verdict and the slope-aware verdict). Then the PDFKit line runs whose bold
// or italic status the reader changes, and the lines holding a styled show that the reader
// cannot mark because a show does not decode and the shows do not share the style.
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
        var runs = 0
        var boldBefore = 0, boldAfter = 0, italicBefore = 0, italicAfter = 0
        var boldChanged = 0, italicChanged = 0
        var boldPages: Set<Int> = [], italicPages: Set<Int> = []
        var boldExamples: [String] = [], italicExamples: [String] = []
        var unresolved: [String: Int] = [:], unresolvedPages: Set<Int> = []
        var unresolvedExamples: [String] = []
        for number in first...last {
            try autoreleasepool {
                guard let page = document.page(at: number - 1), let reference = page.pageRef else { return }
                var ids: [Int: FontWeightReader.FontInfo] = [:]
                let shows = FontWeightReader.read(reference) { id, info in ids[id] = info }
                if shows.isEmpty && !ids.isEmpty { unreadable += 1 }
                func key(_ info: FontWeightReader.FontInfo) -> String {
                    "\(info.baseFont ?? "-")|\(info.subtype)|\(info.fontWeight.map { "\($0)" } ?? "-")|\(info.stemV.map { "\($0)" } ?? "-")|\(info.flags.map(String.init) ?? "-")|\(info.italicAngle.map { "\($0)" } ?? "-")"
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
                    let alone = own.allSatisfy { show in bounds.filter { $0.insetBy(dx: -0.75, dy: -0.75).contains(show.origin) }.count == 1 }
                    if let font = own.first?.font, own.allSatisfy({ $0.font == font }), let info = ids[font], alone {
                        attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
                            let text = (attributed.string as NSString).substring(with: range)
                            guard text.contains(where: { $0.isLetter || $0.isNumber }), let name = (value as? SurveyFont)?.fontName else { return }
                            rows[key(info)]?.pdfkitNames[name, default: 0] += 1
                        }
                    }
                    let lineText = attributed.string.replacingOccurrences(of: "\n", with: " ").prefix(70)
                    // Unresolved: a styled show on the line, some show undecoded, and a style not shared by all.
                    if alone, own.contains(where: \.styled), own.contains(where: { $0.text == nil }),
                       !own.allSatisfy({ $0.weight == .bold }) && own.contains(where: { $0.weight == .bold })
                        || !own.allSatisfy({ $0.italic == true }) && own.contains(where: { $0.italic == true }) {
                        let kinds = Set(own.filter { $0.text == nil }.compactMap { ids[$0.font].map { info in
                            info.subtype == "Type0" ? "Type0" : info.hasToUnicode ? "\(info.subtype) map unsupported" : "\(info.subtype) no ToUnicode"
                        } }).sorted().joined(separator: "+")
                        unresolved[kinds, default: 0] += 1
                        unresolvedPages.insert(number)
                        if unresolvedExamples.count < 30 { unresolvedExamples.append("p\(number)\t\(kinds)\t\(lineText)") }
                    }
                    let marked = FontWeightReader.apply(shows, to: attributed, bounds: rect, allBounds: bounds)
                    marked.enumerateAttributes(in: NSRange(location: 0, length: marked.length)) { attributes, range, _ in
                        let text = (marked.string as NSString).substring(with: range)
                        guard text.contains(where: { $0.isLetter || $0.isNumber }) else { return }
                        runs += 1
                        let name = ((attributes[.font] as? SurveyFont)?.fontName ?? "").lowercased()
                        let example = "p\(number)\t\(name)\t\(text.replacingOccurrences(of: "\n", with: " ").prefix(70))"
                        let bold = (name.contains("bold"), name.contains("bold") || attributes[FontWeightReader.boldAttribute] != nil)
                        let italicName = name.contains("italic") || name.contains("oblique")
                        let italic = (italicName, italicName || attributes[FontWeightReader.italicAttribute] != nil)
                        if bold.0 { boldBefore += 1 }
                        if bold.1 { boldAfter += 1 }
                        if italic.0 { italicBefore += 1 }
                        if italic.1 { italicAfter += 1 }
                        if bold.0 != bold.1 {
                            boldChanged += 1; boldPages.insert(number)
                            if boldExamples.count < 40 { boldExamples.append(example) }
                        }
                        if italic.0 != italic.1 {
                            italicChanged += 1; italicPages.insert(number)
                            if italicExamples.count < 60 { italicExamples.append(example) }
                        }
                    }
                }
            }
        }
        print("# \(arguments[1]) pages \(first)-\(last); pages whose scan failed: \(unreadable)")
        print("baseFont\tsubtype\tFontWeight\tStemV\tFlags\tItalicAngle\tToUnicode\tshows\tPDFKit names\tname rule bold\tweight-aware bold\tname slope\tname rule italic\tslope-aware italic")
        for (_, row) in rows.sorted(by: { ($0.value.shows, $1.key) > ($1.value.shows, $0.key) }) {
            let info = row.info
            let names = row.pdfkitNames.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map { "\($0.key)×\($0.value)" }.joined(separator: ", ")
            // The name rule's verdicts on the font: its most frequent PDFKit name (runs of lines drawn
            // in this resource alone; `-` when no such line exists).
            let majority = row.pdfkitNames.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key.lowercased()
            let currentBold = majority.map { $0.contains("bold") ? "yes" : "no" } ?? "-"
            let currentItalic = majority.map { $0.contains("italic") || $0.contains("oblique") ? "yes" : "no" } ?? "-"
            let aware = info.weight.map { $0 == .bold ? "yes" : "no" } ?? "unknown"
            let slope = info.baseFont.map { "\(FontWeightReader.nameSlope($0))" } ?? "-"
            let italic = info.italic.map { $0 ? "yes" : "no" } ?? "unknown"
            let angle = info.italicAngle.map { String(format: "%g", Double($0)) } ?? "-"
            print("\(info.baseFont ?? "-")\t\(info.subtype)\t\(info.fontWeight.map { "\(Int($0))" } ?? "-")\t\(info.stemV.map { "\(Int($0))" } ?? "-")\t\(info.flags.map(String.init) ?? "-")\t\(angle)\t\(info.hasToUnicode ? "yes" : "no")\t\(row.shows)\t\(names)\t\(currentBold)\t\(aware)\t\(slope)\t\(currentItalic)\t\(italic)")
        }
        print("# line runs \(runs); bold by name rule \(boldBefore); bold with font resources \(boldAfter); changed \(boldChanged) on \(boldPages.count) pages")
        print("# italic by name rule \(italicBefore); italic with font resources \(italicAfter); changed \(italicChanged) on \(italicPages.count) pages")
        print("# unresolved mixed-style lines: \(unresolved.values.reduce(0, +)) on \(unresolvedPages.count) pages; by undecoded font kind: \(unresolved.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))")
        print("# pages with bold changes: \(boldPages.sorted().map(String.init).joined(separator: " "))")
        print("# pages with italic changes: \(italicPages.sorted().map(String.init).joined(separator: " "))")
        print("# bold examples")
        for example in boldExamples { print("  \(example)") }
        print("# italic examples")
        for example in italicExamples { print("  \(example)") }
        print("# unresolved examples")
        for example in unresolvedExamples { print("  \(example)") }
    }
}
