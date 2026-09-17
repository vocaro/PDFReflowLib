import Foundation
import PDFKit

// Private-use characters in PDFKit's line text, before and after `PrivateUseDecoder` (#155).
// Build from the repository root:
//   swiftc -parse-as-library Sources/PDFReflowLib/PrivateUseDecoder.swift Sources/PDFReflowLib/FontWeightReader.swift \
//     Sources/PDFReflowLib/NativeSpacingReader.swift Sources/PDFReflowLib/ConversionTypes.swift \
//     Sources/PDFReflowLib/DocumentModel.swift Sources/PDFReflowLib/ReflowDocument.swift \
//     measurements/symbol-fonts-and-script-bases/survey.swift -o /tmp/private-use-survey
// usage: private-use-survey <pdf>  prints one line per page with private-use characters, then totals.
@main struct PrivateUseSurvey {
    static func main() {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        guard let document = PDFDocument(url: url) else { fatalError("unreadable PDF") }
        var before: [String: Int] = [:], after: [String: Int] = [:]
        func name(_ scalar: Unicode.Scalar) -> String { String(format: "U+%04X", scalar.value) }
        for index in 0..<document.pageCount {
            autoreleasepool {
                guard let page = document.page(at: index), let reference = page.pageRef,
                      let selection = page.selection(for: page.bounds(for: .cropBox)) else { return }
                var characters: [UInt32: String]?
                var pageBefore: [String: Int] = [:], pageAfter: [String: Int] = [:], decoded: [String: String] = [:]
                for line in selection.selectionsByLine() {
                    guard let text = line.string, PrivateUseDecoder.containsPrivateUse(text) else { continue }
                    if characters == nil { characters = PrivateUseDecoder.characters(on: reference) }
                    for scalar in text.unicodeScalars where PrivateUseDecoder.isPrivateUse(scalar) {
                        pageBefore[name(scalar), default: 0] += 1
                        if let character = characters?[scalar.value] { decoded[name(scalar)] = character }
                    }
                    for scalar in PrivateUseDecoder.decode(text, characters ?? [:]).unicodeScalars where PrivateUseDecoder.isPrivateUse(scalar) {
                        pageAfter[name(scalar), default: 0] += 1
                    }
                }
                guard !pageBefore.isEmpty else { return }
                let summary = pageBefore.keys.sorted().map { key in
                    "\(key)×\(pageBefore[key]!)→\(decoded[key] ?? "(kept)")"
                }.joined(separator: " ")
                print("page \(index + 1): \(summary)")
                before.merge(pageBefore, uniquingKeysWith: +)
                after.merge(pageAfter, uniquingKeysWith: +)
            }
        }
        print("before \(before.values.reduce(0, +)) after \(after.values.reduce(0, +))",
              after.isEmpty ? "" : "kept: " + after.keys.sorted().map { "\($0)×\(after[$0]!)" }.joined(separator: " "))
    }
}
