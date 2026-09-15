import Foundation
import CryptoKit
import PDFKit

// Inspect pinned source metadata and native text, never reconstructed output.
@main struct InspectChapterBoundaries {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { fatalError("usage: inspect-chapter-boundaries <corpus-case>") }
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "corpus/manifest.json"))) as! [String: Any]
        let item = (manifest["documents"] as! [[String: Any]]).first { $0["id"] as? String == CommandLine.arguments[1] }!
        let url = URL(fileURLWithPath: "corpus/cache/" + (item["filename"] as! String))
        let digest = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
        guard digest == item["sha256"] as? String else { fatalError("Source identity mismatch") }
        let candidates = try ChapterBoundaryReader.read(url)
        let source = try PDFPageSource(url: url)
        var results: [[String: Any]] = []
        for candidate in candidates {
            try autoreleasepool {
                let page = try source.page(at: candidate.page - 1)
                let content = PageContent(number: candidate.page, bounds: page.bounds(for: .cropBox),
                    lines: try NativeTextReader.lines(on: page, limit: 100_000), graphics: [])
                results.append(["number": candidate.number, "title": candidate.title, "page": candidate.page,
                    "matches": ChapterBoundaryReader.matches(candidate, page: content),
                    "lines": content.lines.map(\.text)])
            }
        }
        let result: [String: Any] = ["case": item["id"]!, "sourceSHA256": digest, "chapters": results]
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]))
    }
}
