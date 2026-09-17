import Foundation
import CryptoKit
import PDFKit

// Run from the repository root. Reports, for every page of the named corpus cases, each place
// where `NativeTextReader.lines` returns something other than the line PDFKit itself returned:
// a line split into pieces (#14, #65, #121) and a line whose characters changed (#119, #128,
// #143, #155). Extraction evidence only; no conversion output is involved.
//
// Build (from the repository root) with the library sources the reader needs, then:
//   survey-line-changes <case-id> [<case-id> …]
@main struct SurveyLineChanges {
    static func squeezed(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func main() throws {
        let manifest = try JSONSerialization.jsonObject(
            with: Data(contentsOf: URL(fileURLWithPath: "corpus/manifest.json"))) as! [String: Any]
        let documents = manifest["documents"] as! [[String: Any]]
        for id in CommandLine.arguments.dropFirst() {
            guard let item = documents.first(where: { $0["id"] as? String == id }),
                  let file = item["filename"] as? String, let expected = item["sha256"] as? String else {
                FileHandle.standardError.write(Data("unknown case \(id)\n".utf8)); continue
            }
            let source = URL(fileURLWithPath: "corpus/cache/" + file)
            let data = try Data(contentsOf: source)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest == expected else { fatalError("Source identity mismatch for \(id)") }
            guard let document = PDFDocument(url: source) else { fatalError("unreadable \(id)") }
            let decodings = (try? GlyphIndexDecoder.read(source, language: "en")) ?? [:]
            for number in 0..<document.pageCount {
                guard let page = document.page(at: number), let reference = page.pageRef else { continue }
                let raw = (page.selection(for: page.bounds(for: .cropBox))?.selectionsByLine() ?? [])
                    .compactMap { $0.string.map { squeezed($0.replacingOccurrences(of: "\u{FFFC}", with: " ")) } }
                    .filter { !$0.isEmpty }
                let graphics = GraphicsReader.read(reference)
                guard let lines = try? NativeTextReader.lines(
                    on: page, limit: 100_000,
                    columnJoints: GraphicsReader.columnJoints(graphics.paints.map(\.rect)),
                    borderlessTableInk: graphics.paints.map(\.rect),
                    glyphDecodings: decodings) else { continue }
                let read = lines.map { squeezed($0.text) }.filter { !$0.isEmpty }
                // Align the reader's lines with PDFKit's on the characters alone: each PDFKit line
                // is one or more of them, and only their spaces may differ (#119, #128).
                func bare(_ text: String) -> String { text.filter { !$0.isWhitespace } }
                var index = 0, aligned = true
                for source in raw where aligned {
                    let target = bare(source)
                    var taken: [String] = [], joined = ""
                    while index < read.count, joined != target, joined.count < target.count {
                        taken.append(read[index]); joined += bare(read[index]); index += 1
                    }
                    guard joined == target else {
                        print("\(id) p\(number + 1) UNALIGNED raw=\(source.debugDescription) "
                              + "read=\(taken.map(\.debugDescription).joined(separator: " | "))")
                        aligned = false; continue
                    }
                    if taken.count > 1 {
                        print("\(id) p\(number + 1) SPLIT \(taken.count) raw=\(source.debugDescription) "
                              + "pieces=\(taken.map(\.debugDescription).joined(separator: " | "))")
                    } else if let only = taken.first, only != source {
                        print("\(id) p\(number + 1) TEXT raw=\(source.debugDescription) now=\(only.debugDescription)")
                    }
                }
                while aligned && index < read.count {
                    print("\(id) p\(number + 1) EXTRA now=\(read[index].debugDescription)")
                    index += 1
                }
            }
            FileHandle.standardError.write(Data("done \(id)\n".utf8))
        }
    }
}
