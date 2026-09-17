import Foundation
import PDFKit
import AppKit
import CoreText

// Scan PDFKit line selections for lines whose base-size runs are uniformly lowered while a
// smaller digit run sits at offset zero (a note marker the baseline was measured on).
struct Run { var text: String; var size: Double; var offset: Double }

func runs(_ attributed: NSAttributedString) -> [Run] {
    var result: [Run] = []
    attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attrs, range, _ in
        let font = attrs[.font] as? NSFont
        let offset = (attrs[NSAttributedString.Key(kCTBaselineOffsetAttributeName as String)] as? NSNumber
            ?? attrs[.baselineOffset] as? NSNumber)?.doubleValue ?? 0
        result.append(Run(text: (attributed.string as NSString).substring(with: range),
                          size: Double(font?.pointSize ?? 0), offset: offset))
    }
    return result
}

let args = CommandLine.arguments.dropFirst()
var total = 0
for path in args {
    guard let document = PDFDocument(url: URL(fileURLWithPath: path)) else { print("cannot open", path); continue }
    var hits = 0, lowered = 0
    for index in 0..<document.pageCount {
        autoreleasepool {
            guard let page = document.page(at: index),
                  let selection = page.selection(for: page.bounds(for: .cropBox)) else { return }
            for line in selection.selectionsByLine() {
                guard let attributed = line.attributedString, attributed.length > 0 else { continue }
                let all = runs(attributed).filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                guard let base = all.map(\.size).max(), base > 0 else { continue }
                let tolerance = max(0.5, base * 0.12)
                let full = all.filter { abs($0.size - base) <= base * 0.1 }
                let small = all.filter { $0.size <= base * 0.7 }
                guard !small.isEmpty, full.count + small.count == all.count else { continue }
                let offsets = full.map(\.offset)
                guard let low = offsets.min(), let high = offsets.max(), high < -tolerance,
                      high - low <= tolerance, low >= -base * 0.75 else { continue }
                lowered += 1
                let digits = small.allSatisfy { run in
                    let t = run.text.trimmingCharacters(in: .whitespaces)
                    return (1...3).contains(t.count) && t.allSatisfy(\.isNumber) && abs(run.offset) <= tolerance
                }
                let text = attributed.string.replacingOccurrences(of: "\n", with: "⏎")
                print(digits ? "HIT" : "lowered-other", URL(fileURLWithPath: path).lastPathComponent, "page", index + 1,
                      String(text.prefix(90)), all.map { String(format: "[%@ %.2f %.2f]", $0.text.prefix(12) as CVarArg, $0.size, $0.offset) }.joined())
                // Strict: every small run is a 1-3 digit marker at 0.4-0.7 of the base size, directly after a
                // base run ending in a non-space, at the line end or before whitespace; base lowered 0.2-0.5 size.
                var strict = digits && -high >= base * 0.2 && -low <= base * 0.5
                if strict {
                    for (i, run) in all.enumerated() where run.size <= base * 0.7 {
                        let ratio = run.size / base
                        let before = i > 0 ? all[i - 1] : nil
                        let after = i + 1 < all.count ? all[i + 1] : nil
                        if !(ratio >= 0.4 && ratio <= 0.7) || before == nil || before!.size <= base * 0.7
                            || before!.text.last?.isWhitespace != false
                            || (after != nil && run.text.last?.isWhitespace != true && after!.text.first?.isWhitespace != true) {
                            strict = false
                        }
                    }
                }
                let closing = Set("\u{201D}\u{2019}\"')].,;:")
                let punctuationOnly = full.allSatisfy { $0.text.trimmingCharacters(in: .whitespaces).allSatisfy(closing.contains) }
                if strict && punctuationOnly { print("PUNCT", URL(fileURLWithPath: path).lastPathComponent, "page", index + 1, String(text.prefix(60))) }
                if strict && punctuationOnly { hits += 1 }
            }
        }
    }
    print("SUMMARY", URL(fileURLWithPath: path).lastPathComponent, "pages", document.pageCount, "hits", hits, "loweredLines", lowered)
    total += hits
}
