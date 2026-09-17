import Foundation
import PDFKit

// Lists short lines set wholly in one emphasised style (italic, bold, bold-italic) on FAA pages,
// with size, tag status and position, for comparison with converter output.
@main struct Titles {
    static func main() throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let document = PDFDocument(url: url)!
        let index = try StructureTreeReader.read(url)
        for n in 1...document.pageCount {
            let page = document.page(at: n - 1)!
            var lines = try NativeTextReader.lines(on: page, limit: 1_000_000, includeStyle: true)
            var status = "untagged"
            if let tags = index.pages[n], !tags.isEmpty, let ref = page.pageRef {
                let ok = StructureTreeReader.validates(tags, owners: index.owners[n] ?? [:], page: ref)
                    && MarkedTextReader.apply(tags, page: ref, lines: &lines)
                status = ok ? "tagged" : "rejected"
            }
            for l in lines {
                let text = l.text.trimmingCharacters(in: .whitespaces)
                guard text.count >= 3, text.count < 80, text.first?.isUppercase == true,
                      !".:;,".contains(text.last!) else { continue }
                var styles = Set<String>()
                for e in l.content.elements {
                    if case let .text(v, s) = e, v.contains(where: { !$0.isWhitespace }) {
                        styles.insert((s.contains(.bold) ? "B" : "") + (s.contains(.italic) ? "I" : ""))
                    }
                }
                guard styles.count == 1, let style = styles.first, !style.isEmpty else { continue }
                print("\(n)\t\(status)\t\(l.structure == nil ? "-" : "tag")\t\(style)\t\(String(format: "%.1f", l.fontSize))\t\(Int(l.rect.minX))\t\(text)")
            }
        }
    }
}
