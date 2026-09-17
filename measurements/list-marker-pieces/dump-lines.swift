// Writes every page's native lines (text, rect, font size, monospaced) as one JSON object per
// line of output, for survey-markers.py. Extraction evidence only, never reconstructed output.
//
//   swiftc -parse-as-library Sources/PDFReflowLib/NativeTextReader.swift \
//     Sources/PDFReflowLib/ConversionTypes.swift Sources/PDFReflowLib/DocumentModel.swift \
//     Sources/PDFReflowLib/ReflowDocument.swift Sources/PDFReflowLib/GraphicsReader.swift \
//     Sources/PDFReflowLib/NativeSpacingReader.swift measurements/list-marker-pieces/dump-lines.swift \
//     -o /tmp/dump-lines
//   /tmp/dump-lines corpus/cache/GPO-911REPORT.pdf /tmp/lines/lines-gpo-911-2004.jsonl
import Foundation
import PDFKit

@main struct DumpLines {
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 3, let document = PDFDocument(url: URL(fileURLWithPath: args[1])) else {
            fatalError("usage: dumplines input.pdf output.jsonl")
        }
        FileManager.default.createFile(atPath: args[2], contents: nil)
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: args[2]))
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let lines = (try? NativeTextReader.lines(on: page, limit: 100_000)) ?? []
            let bounds = page.bounds(for: .cropBox)
            let rows: [[String: Any]] = lines.map {
                ["t": $0.text, "x": $0.rect.minX, "y": $0.rect.minY, "w": $0.rect.width, "h": $0.rect.height,
                 "s": $0.fontSize, "m": $0.monospaced]
            }
            let object: [String: Any] = ["page": index + 1, "width": bounds.width, "height": bounds.height, "lines": rows]
            handle.write(try JSONSerialization.data(withJSONObject: object))
            handle.write("\n".data(using: .utf8)!)
        }
        try handle.close()
    }
}
