import Foundation
import PDFKit

@main struct Probe {
    static func main() throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let document = PDFDocument(url: url)!
        let index = try StructureTreeReader.read(url)
        for n in CommandLine.arguments.dropFirst(2).compactMap({ Int($0) }) {
            let page = document.page(at: n - 1)!
            var lines = try NativeTextReader.lines(on: page, limit: 1_000_000, includeStyle: true)
            var status = "untagged"
            if let tags = index.pages[n], !tags.isEmpty, let ref = page.pageRef {
                let ok = StructureTreeReader.validates(tags, owners: index.owners[n] ?? [:], page: ref)
                    && MarkedTextReader.apply(tags, page: ref, lines: &lines)
                status = ok ? "tagged" : "fallback"
            }
            print("=== page \(n) \(status)")
            for l in lines {
                let fonts = l.content.elements.compactMap { e -> String? in
                    if case let .text(v, s) = e { return "\(s.contains(.bold) ? "B" : "")\(s.contains(.italic) ? "I" : "")\(v.count)" }
                    return nil
                }.joined(separator: ",")
                let tag = l.structure.map { "g\($0.group)/L\($0.headingLevel)" } ?? "-"
                print(String(format: "%6.1f %6.1f %6.1f %5.1f %5.2f", l.rect.minX, l.rect.minY, l.rect.width, l.rect.height, l.fontSize), tag, fonts, String(l.text.prefix(80)))
            }
        }
    }
}
