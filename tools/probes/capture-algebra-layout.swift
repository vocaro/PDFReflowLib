import Foundation
import CryptoKit
import PDFKit

@main struct CaptureLayout {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            fatalError("usage: capture-algebra-layout <pinned-algebra.pdf> <output.json>")
        }
        let source = URL(fileURLWithPath: CommandLine.arguments[1])
        let digest = SHA256.hash(data: try Data(contentsOf: source)).map { String(format: "%02x", $0) }.joined()
        guard digest == "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678" else { fatalError("Source identity mismatch") }
        guard let document = PDFDocument(url: source), let page = document.page(at: 16),
              let reference = page.pageRef else { throw CocoaError(.fileReadCorruptFile) }
        func rect(_ r: CGRect) -> [Double] { [r.minX, r.minY, r.width, r.height] }
        let lines = try NativeTextReader.lines(on: page, limit: 100_000)
        let graphics = GraphicsReader.read(reference)
        let payload: [String: Any] = [
            "sourceSHA256": digest, "page": 17,
            "sourceURL": "https://s3.amazonaws.com/myopenmath/cfiles/19515/Beginning_and_Intermediate_Algebra.pdf",
            "attribution": "Beginning and Intermediate Algebra, Tyler Wallace (2010), CC BY 3.0. Extracted text and geometry; no page artwork.",
            "licenseURL": "https://creativecommons.org/licenses/by/3.0/",
            "bounds": rect(page.bounds(for: .cropBox)), "graphics": graphics.regions.map(rect),
            "lines": lines.map { ["text": $0.text, "rect": rect($0.rect), "fontSize": Double($0.fontSize), "monospaced": $0.monospaced] as [String: Any] },
        ]
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            .write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    }
}
