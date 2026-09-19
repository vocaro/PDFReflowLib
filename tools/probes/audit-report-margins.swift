import Foundation
import CryptoKit
import PDFKit

// Diagnostic extraction only: preserve the source margin rows and the detector's decisions.
@main struct AuditReportMargins {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            fatalError("usage: audit-report-margins <pinned-full-report.pdf> <output.json>")
        }
        let source = URL(fileURLWithPath: CommandLine.arguments[1])
        let hash = SHA256.hash(data: try Data(contentsOf: source)).map { String(format: "%02x", $0) }.joined()
        guard hash == "657d41475eb3a9a5e3e87a6c7c51ac1dfbe1af7566d1abff7bf7286e7e1c0e1b",
              let document = PDFDocument(url: source), document.pageCount == 585 else {
            fatalError("Expected the pinned full 9/11 report")
        }
        var pages: [PageContent] = try (0..<document.pageCount).map { index in
            try autoreleasepool {
                let page = document.page(at: index)!
                return PageContent(number: index + 1, bounds: page.bounds(for: .cropBox),
                                   lines: try NativeTextReader.lines(on: page, limit: 100_000), graphics: [])
            }
        }
        let original = pages
        _ = FurnitureDetector.strip(&pages)
        let records: [[String: Any]] = zip(original, pages).map { before, after in
            let rows: [[String: Any]] = before.lines.filter {
                ($0.rect.midY - before.bounds.minY) / before.bounds.height >= 0.90
            }.map { line in
                ["text": line.text, "rect": [line.rect.minX, line.rect.minY, line.rect.width, line.rect.height],
                 "fontSize": line.fontSize, "removed": !after.lines.contains { $0.text == line.text && $0.rect == line.rect }]
            }
            return ["page": before.number, "topRows": rows]
        }
        let payload: [String: Any] = ["sourceSHA256": hash, "pages": records,
            "scope": "Native extraction and current margin detector; no OCR, reconstruction, or correctness annotation."]
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            .write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    }
}
