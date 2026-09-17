import Foundation
import PDFKit

// usage: minus-survey <pdf> ; prints page, and line text for lines opening with a U+2212, hyphen-minus or bullet-like dash followed by whitespace
let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard let document = PDFDocument(url: url) else { fatalError("open") }
let pattern = try NSRegularExpression(pattern: "^\\s*([−-])\\s")
for index in 0..<document.pageCount {
    autoreleasepool {
        guard let page = document.page(at: index) else { return }
        for selection in page.selection(for: page.bounds(for: .cropBox))?.selectionsByLine() ?? [] {
            guard let text = selection.string else { continue }
            let range = NSRange(text.startIndex..., in: text)
            if let match = pattern.firstMatch(in: text, range: range) {
                let rest = text[Range(match.range, in: text)!.upperBound...]
                let next = rest.first.map { $0.isNumber ? "digit" : $0.isLetter ? (rest.prefix(while: { $0.isLetter }).count <= 1 ? "variable" : "word") : "other" } ?? "end"
                let dash = (text as NSString).substring(with: match.range(at: 1)) == "−" ? "U+2212" : "hyphen"
                let b = selection.bounds(for: page)
                print("\(index + 1)\t\(dash)\t\(next)\tx=\(Int(b.minX))\t\(text.prefix(90))")
            }
        }
    }
}
