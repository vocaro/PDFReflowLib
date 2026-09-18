import Foundation
import PDFKit

// usage: entrysurvey <pdf> [first last]
// One block per page holding a spaced-entry edge (#181) that is not already a hanging-entry edge
// (#134): the edge, and every line on it top to bottom, marked `>>` where `opensHangingEntry`'s
// ends-early test would open a new entry after the line above (a superset of what `blocks` does:
// no furniture removal, crops, tags or reading order).
@main struct EntrySurvey {
    static func f(_ r: CGRect) -> String { String(format: "[%.1f %.1f %.1f %.1f]", r.minX, r.minY, r.maxX, r.maxY) }
    static func main() throws {
        let args = CommandLine.arguments
        let doc = PDFDocument(url: URL(fileURLWithPath: args[1]))!
        let first = args.count > 3 ? Int(args[2])! : 1
        let last = args.count > 3 ? Int(args[3])! : doc.pageCount
        var pagesWithEdges = 0, splits = 0
        func pageLines(_ p: Int) -> (PDFPage, [TextLine])? {
            guard let page = doc.page(at: p - 1), let ref = page.pageRef else { return nil }
            let g = GraphicsReader.read(ref)
            if g.unsupported || page.rotation % 360 != 0 || g.hasOnlyInvisibleText { return nil }
            guard var lines = try? NativeTextReader.lines(on: page, limit: 10_000_000, includeStyle: true,
                columnJoints: GraphicsReader.columnJoints(g.paints.map(\.rect)), borderlessTableInk: g.paints.map(\.rect)) else { return nil }
            _ = HiddenTextFilter.removeHidden(&lines, graphics: g)
            return (page, lines)
        }
        var evidence: [Int: [CGFloat]] = [:]
        for p in 1...doc.pageCount {
            autoreleasepool {
                guard let (page, lines) = pageLines(p) else { return }
                let content = PageContent(number: p, bounds: page.bounds(for: .cropBox), lines: lines, graphics: [])
                if let wrap = LayoutReconstructor.wrapEvidence(on: content) { evidence[wrap.size, default: []].append(wrap.gap) }
            }
        }
        let bookWraps = LayoutReconstructor.bookWraps(from: evidence)
        print("BOOK WRAPS", bookWraps.sorted { $0.key < $1.key }.map { "\(Double($0.key) / 2):\(String(format: "%.2f", $0.value))" })
        for p in first...last {
            autoreleasepool {
                guard let page = doc.page(at: p - 1), let ref = page.pageRef else { return }
                let g = GraphicsReader.read(ref)
                if g.unsupported || page.rotation % 360 != 0 { return }
                guard var lines = try? NativeTextReader.lines(on: page, limit: 10_000_000, includeStyle: true,
                    columnJoints: GraphicsReader.columnJoints(g.paints.map(\.rect)), borderlessTableInk: g.paints.map(\.rect)) else { return }
                _ = HiddenTextFilter.removeHidden(&lines, graphics: g)
                if g.hasOnlyInvisibleText { return }
                let body = LayoutReconstructor.bodySize(lines)
                let hanging = LayoutReconstructor.hangingEntryEdges(lines, body: body)
                let spaced = LayoutReconstructor.spacedEntryEdges(lines, body: body, bookWrap: bookWraps[LayoutReconstructor.wrapKey(body)]).filter { edge in
                    !hanging.contains { abs($0.x - edge.x) <= edge.size * 0.5 && abs($0.size - edge.size) <= edge.size * 0.1 }
                }
                guard !spaced.isEmpty else { return }
                pagesWithEdges += 1
                var out = "\(p)\tbody=\(String(format: "%.1f", body))\tedges=\(spaced.map { String(format: "%.1f@%.1f", $0.x, $0.size) }.joined(separator: ","))"
                for edge in spaced {
                    let on = lines.filter { abs($0.rect.minX - edge.x) <= edge.size * 0.5 && abs($0.fontSize - edge.size) <= edge.size * 0.1 }
                        .sorted { $0.rect.maxY > $1.rect.maxY }
                    let right = on.map(\.rect.maxX).max() ?? 0
                    var prev: TextLine?
                    for line in on {
                        var mark = "  "
                        if let prev {
                            let gap = prev.rect.minY - line.rect.maxY
                            let word = line.text.split(whereSeparator: \.isWhitespace).first ?? ""
                            let wordWidth = line.rect.width * CGFloat(word.count + 1) / CGFloat(max(1, line.text.count))
                            let opens = gap >= -edge.size * 0.4 && gap < edge.size * 0.9
                                && line.text.first(where: \.isLetter)?.isLowercase == false
                                && prev.text.last.map({ "-\u{00AD}/".contains($0) }) == false
                                && !LayoutReconstructor.LabelStyle(prev, body: body).bold && !LayoutReconstructor.LabelStyle(line, body: body).bold
                                && prev.rect.maxX + wordWidth + edge.size * 0.5 <= right
                                && gap >= (edge.spacing ?? 0)
                            if opens { mark = ">>"; splits += 1 }
                            out += String(format: "\n   %@ gap %5.1f %@ %@", mark, gap, f(line.rect), String(line.text.prefix(80)))
                        } else {
                            out += String(format: "\n   %@ gap   --- %@ %@", mark, f(line.rect), String(line.text.prefix(80)))
                        }
                        prev = line
                    }
                }
                print(out)
            }
        }
        print("TOTAL pages \(pagesWithEdges) splits \(splits)")
    }
}
