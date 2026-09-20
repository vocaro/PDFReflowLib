// Standalone PDFKit text-extraction probe. Apple SDKs only: no PDFReflowLib, no third-party code.
// It opens one page, asks PDFKit for its lines, and prints what PDFKit says about each of them.
//
//   xcrun swiftc -O probe.swift -o pdfkit-text-probe
//   ./pdfkit-text-probe input.pdf <page> lines|chars|fonts
//
// lines  one row per line: index, rect, PDFKit's string with control characters escaped
// chars  one row per character: index, scalar, escaped character, characterBounds
// fonts  one row per attribute run: range, font name, point size, symbolic traits
import AppKit
import Foundation
import PDFKit

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 3, let pageNumber = Int(arguments[1]),
      ["lines", "chars", "fonts"].contains(arguments[2]) else {
    fputs("Usage: pdfkit-text-probe input.pdf <page, 1-based> lines|chars|fonts\n", stderr)
    exit(2)
}
guard let document = PDFDocument(url: URL(fileURLWithPath: arguments[0])),
      pageNumber >= 1, pageNumber <= document.pageCount,
      let page = document.page(at: pageNumber - 1) else {
    fputs("Cannot open that page\n", stderr)
    exit(2)
}

/// Every character PDFKit returns, with anything outside printable ASCII shown as its scalar.
func escaped(_ text: String) -> String {
    text.unicodeScalars.map { scalar in
        switch scalar.value {
        case 0x20...0x7E: String(scalar)
        case 0x0A: "\\n"
        case 0x09: "\\t"
        default: scalar.value < 0x80 || scalar.value > 0x2000
            ? String(format: "\\u{%04X}", scalar.value) : String(scalar)
        }
    }.joined()
}

func row(_ rect: CGRect) -> String {
    String(format: "x=%.2f y=%.2f w=%.2f h=%.2f", rect.origin.x, rect.origin.y, rect.width, rect.height)
}

switch arguments[2] {
case "lines":
    guard let selection = page.selection(for: page.bounds(for: .cropBox)) else { exit(1) }
    for (index, line) in selection.selectionsByLine().enumerated() {
        let rect = line.bounds(for: page)
        print("line \(index)\t\(row(rect))\t\(escaped(line.string ?? ""))")
    }
case "chars":
    let text = page.string ?? ""
    for (index, scalar) in text.unicodeScalars.enumerated() {
        let bounds = index < page.numberOfCharacters ? page.characterBounds(at: index) : .null
        print(String(format: "char %4d\tU+%04X\t%@\t%@", index, scalar.value,
                     escaped(String(scalar)), row(bounds)))
    }
case "fonts":
    guard let attributed = page.attributedString else { exit(1) }
    attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, range, _ in
        let font = attributes[.font] as? NSFont
        let traits = font.map { String(describing: $0.fontDescriptor.symbolicTraits) } ?? "-"
        let text = (attributed.string as NSString).substring(with: range)
        print("run \(range.location)+\(range.length)\t\(font?.fontName ?? "-")\t"
              + String(format: "%.2f pt", font?.pointSize ?? 0) + "\ttraits=\(traits)\t\(escaped(text))")
    }
default: exit(2)
}
