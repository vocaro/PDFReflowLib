import Foundation
import PDFKit

// Diagnostic only: replicates per-page extraction (lines, tags, hidden filter, tint composition)
// and graphicsWithLabels, then reports every line with its hidden flag and the crop it falls in.
@main struct Survey {
    static func r(_ rect: CGRect) -> [Double] {
        [rect.minX, rect.minY, rect.width, rect.height].map { (v: CGFloat) -> Double in (Double(v) * 100).rounded() / 100 }
    }
    static func main() throws {
        let args = CommandLine.arguments
        let url = URL(fileURLWithPath: args[1])
        let first = Int(args[2])!, last = Int(args[3])!
        let out = FileHandle(forWritingAtPath: args[4]) ?? {
            FileManager.default.createFile(atPath: args[4], contents: nil)
            return FileHandle(forWritingAtPath: args[4])!
        }()
        out.seekToEndOfFile()
        let document = PDFDocument(url: url)!
        let structure = try? StructureTreeReader.read(url)
        for number in first...min(last, document.pageCount) {
            try autoreleasepool {
                let page = document.page(at: number - 1)!
                let reference = page.pageRef!
                let bounds = page.bounds(for: .cropBox)
                let graphics = GraphicsReader.read(reference)
                var content = PageContent(number: number, bounds: bounds,
                                          lines: try NativeTextReader.lines(on: page, limit: 1_000_000), graphics: graphics.regions)
                if let structure, let tags = structure.pages[number], !tags.isEmpty,
                   StructureTreeReader.validates(tags, owners: structure.owners[number] ?? [:], page: reference) {
                    _ = MarkedTextReader.apply(tags, page: reference, lines: &content.lines)
                }
                let all = content.lines
                _ = HiddenTextFilter.removeHidden(&content.lines, graphics: graphics)
                let composed = TintDetector.compose(graphics.paints, lines: content.lines, bounds: bounds)
                content.graphics = composed.graphics
                content.tints = composed.tints
                content.separators = composed.separators
                let crops = graphics.unsupported ? [] : LayoutReconstructor.graphicsWithLabels(content)
                var lines: [[String: Any]] = []
                for line in all {
                    let hidden = !content.lines.contains(line)
                    let inside = crops.indices.filter { crops[$0].intersects(line.rect) }
                    lines.append(["t": line.text, "r": r(line.rect), "h": hidden, "c": inside, "s": line.fontSize])
                }
                if ProcessInfo.processInfo.environment["SURVEY_DEBUG"] != nil {
                    print("page \(number) regions \(graphics.regions.count) paints \(graphics.paints.count)")
                    for (i, g) in content.graphics.enumerated() {
                        let touched = content.lines.filter { $0.rect.intersects(g) }.map { String($0.text.prefix(40)) }
                        print(" g\(i) \(r(g)) touches \(touched.count): \(touched.prefix(6))")
                    }
                    for p in graphics.paints where p.rect.width * p.rect.height > 400 {
                        let touched = content.lines.filter { $0.rect.intersects(p.rect) }.count
                        if touched > 0 { print("  paint \(r(p.rect)) frame=\(p.frame) touches \(touched)") }
                    }
                    for (i, c) in crops.enumerated() { print(" crop\(i) \(r(c))") }
                }
                let payload: [String: Any] = [
                    "page": number, "unsupported": graphics.unsupported,
                    "crops": crops.map(r), "graphics": content.graphics.map(r), "regions": graphics.regions.map(r),
                    "lines": lines,
                ]
                var data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
                data.append(0x0A)
                out.write(data)
            }
        }
    }
}
