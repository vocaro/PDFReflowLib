import Foundation
import PDFKit

// usage: edgesurvey <pdf>
// For every composed crop holding an image paint and text lines: the first condition of
// TintDetector.withoutEdgeBands it fails, with the page and the lines, as TSV.
@main struct EdgeSurvey {
    static func f(_ r: CGRect) -> String { String(format: "[%.0f %.0f %.0f %.0f]", r.minX, r.minY, r.maxX, r.maxY) }
    static func main() throws {
        let args = CommandLine.arguments
        let doc = PDFDocument(url: URL(fileURLWithPath: args[1]))!
        var counts: [String: Int] = [:]
        for p in 1...doc.pageCount {
            autoreleasepool {
                guard let page = doc.page(at: p - 1), let ref = page.pageRef else { return }
                let bounds = page.bounds(for: .cropBox)
                let g = GraphicsReader.read(ref)
                guard !g.unsupported, var lines = try? NativeTextReader.lines(on: page, limit: 10_000_000, includeStyle: true,
                    columnJoints: GraphicsReader.columnJoints(g.paints.map(\.rect)), borderlessTableInk: g.paints.map(\.rect)) else { return }
                _ = HiddenTextFilter.removeHidden(&lines, graphics: g)
                let area = bounds.width * bounds.height
                if g.regions.contains(where: { $0.width * $0.height > area * 0.75 }) { return }
                let composed = TintDetector.compose(g.paints, lines: lines, bounds: bounds)
                let paints = g.paints
                let images = paints.filter { $0.image }.map(\.rect)
                let body = max(4, LayoutReconstructor.bodySize(lines))
                func reads(_ line: TextLine) -> Bool {
                    guard !line.monospaced else { return false }
                    if line.fontSize >= body * 1.25, line.text.range(of: #"\p{L}{3,}"#, options: .regularExpression) != nil { return true }
                    return line.text.split(whereSeparator: { !$0.isLetter }).filter { $0.count >= 2 }.count >= 4
                }
                for hull in composed.graphics {
                    let art = images.filter { hull.insetBy(dx: -1, dy: -1).contains($0) }
                    guard !art.isEmpty else { continue }
                    let held = lines.filter { $0.rect.intersects(hull) }
                    guard !held.isEmpty else { continue }
                    var reason = "trimmed"
                    let backdrops = paints.filter { paint in
                        paint.filled && held.contains { paint.rect.contains(CGPoint(x: $0.rect.midX, y: $0.rect.midY)) }
                    }.map(\.rect)
                    let strip = union(backdrops + held.map(\.rect))
                    if !held.allSatisfy(reads) { reason = "1-labels" }
                    else if !held.allSatisfy({ line in backdrops.contains { $0.contains(CGPoint(x: line.rect.midX, y: line.rect.midY)) } }) { reason = "2-noBackdrop" }
                    else if union(backdrops).width < hull.width * 0.9 { reason = "3-narrowBackdrop" }
                    else if !(strip.minY <= hull.minY + 1 || strip.maxY >= hull.maxY - 1) { reason = "4-notAtEdge" }
                    else {
                        let (low, high) = strip.minY <= hull.minY + 1 ? (strip.maxY + 0.5, hull.maxY) : (hull.minY, strip.minY - 0.5)
                        let rest = CGRect(x: hull.minX, y: low, width: hull.width, height: max(0, high - low))
                        if high - low < hull.height / 3 { reason = "5-shortRest" }
                        else if TintDetector.coverage(of: rest, by: art) < 0.9 { reason = "7-notImage" }
                    }
                    counts[reason, default: 0] += 1
                    print("\(p)\t\(reason)\t\(f(hull))\t\(held.count)\t" + held.prefix(4).map { "\"\($0.text.prefix(40))\" \(Int($0.fontSize))" }.joined(separator: " | "))
                }
            }
        }
        FileHandle.standardError.write("\(counts.sorted { $0.key < $1.key })\n".data(using: .utf8)!)
    }
}
