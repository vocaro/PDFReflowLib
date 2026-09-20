import Foundation
import CoreGraphics
import PDFKit

// Every page's reconstructed crops and extracted line boxes, as JSON lines, so an ink check can
// ask whether the page paints anything outside them.
@main struct DumpCrops {
    static func main() throws {
        for path in CommandLine.arguments.dropFirst() {
            let url = URL(fileURLWithPath: path)
            let source = try PDFPageSource(url: url)
            let structure = try StructureTreeReader.read(url)
            func box(_ r: CGRect) -> [Double] { [r.minX, r.minY, r.width, r.height] }
            for index in 0..<source.pageCount {
                try autoreleasepool {
                    let extracted = try PageReader.read(pageIndex: index, from: source, limit: 400_000,
                                                        options: ConversionOptions(), structure: structure)
                    let content = extracted.content
                    let payload: [String: Any] = [
                        "file": url.lastPathComponent, "page": index + 1,
                        "bounds": box(content.bounds),
                        "requiresPageImage": content.requiresPageImage,
                        "regions": content.graphics.map(box),
                        "crops": LayoutReconstructor.graphicsWithLabels(content).map(box),
                        "lines": content.lines.map { box($0.rect) },
                    ]
                    let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
                    FileHandle.standardOutput.write(data)
                    FileHandle.standardOutput.write(Data("\n".utf8))
                }
            }
        }
    }
}
