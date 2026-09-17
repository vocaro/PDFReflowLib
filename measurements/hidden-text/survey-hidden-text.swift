import Foundation
import PDFKit

// usage: survey-hidden-text <pdf> [first last]
// One TSV row per native line HiddenTextFilter would drop, with the page's structure tag (if
// MarkedTextReader applies one) and why each admitted show is hidden. Mirrors extractPage:
// pages that require a page image are skipped, as the pipeline skips them.
let args = CommandLine.arguments
let url = URL(fileURLWithPath: args[1])
let doc = PDFDocument(url: url)!
let first = args.count > 3 ? Int(args[2])! : 1
let last = args.count > 3 ? Int(args[3])! : doc.pageCount
let index = try? StructureTreeReader.read(url)
var dropped = 0, pagesWithDrops = 0, skippedInvisible = 0, skippedPlacement = 0, pagesEmptied = 0
// DEBUG_PAGE=n: for that page, print each line and the first show that keeps it visible.
if let debug = ProcessInfo.processInfo.environment["DEBUG_PAGE"].flatMap(Int.init) {
    let page = doc.page(at: debug - 1)!
    let g = GraphicsReader.read(page.pageRef!)
    print("unsupported \(g.unsupported) invisible \(g.hasInvisibleText) placement \(g.textPlacementUnsupported) shows \(g.textShows.count) covers \(g.covers.count)")
    for c in g.covers { print("cover \(c.sequence) \(c.rect)") }
    let lines = (try? NativeTextReader.lines(on: page, limit: 10_000_000, includeStyle: false)) ?? []
    for line in lines {
        let r = line.rect
        let margin = max(1, r.height * 0.25)
        let blockers = g.textShows.filter { $0.baseline >= r.minY - margin && $0.baseline <= r.maxY + margin && $0.left <= r.maxX + 1
            && !HiddenTextFilter.isHidden($0, in: r, covers: g.covers) }
        print("\(r) \(line.text.prefix(60)) :: \(blockers.prefix(3).map { "seq \($0.sequence) base \($0.baseline) left \($0.left) origin \(String(describing: $0.origin)) clip \($0.clip)" })")
    }
    exit(0)
}
print("page\tline\ttagged\treason\tx\ty\tw\th\ttext")
for n in first...last {
    autoreleasepool {
        let page = doc.page(at: n - 1)!
        let ref = page.pageRef!
        let g = GraphicsReader.read(ref)
        let requires = g.unsupported || page.rotation % 360 != 0
        guard !requires else { return }
        if g.hasInvisibleText { skippedInvisible += 1; return }
        if g.textPlacementUnsupported { skippedPlacement += 1; return }
        var lines = (try? NativeTextReader.lines(on: page, limit: 10_000_000, includeStyle: !g.hasOnlyInvisibleText)) ?? []
        if let index, let tags = index.pages[n], !tags.isEmpty,
           StructureTreeReader.validates(tags, owners: index.owners[n] ?? [:], page: ref) {
            _ = MarkedTextReader.apply(tags, page: ref, lines: &lines)
        }
        let hidden = HiddenTextFilter.hiddenLines(lines, graphics: g)
        guard !hidden.isEmpty else { return }
        pagesWithDrops += 1
        FileHandle.standardError.write("drops \(n) \(hidden.count)/\(lines.count) covers \(g.covers.count)\n".data(using: .utf8)!)
        if hidden.count == lines.count { pagesEmptied += 1 }
        for i in hidden {
            dropped += 1
            let line = lines[i]
            let r = line.rect
            let margin = max(1, r.height * 0.25)
            var reasons = Set<String>()
            // Why the shows that start inside the line are hidden (outside the clip, or covered).
            for show in g.textShows where show.baseline >= r.minY - margin && show.baseline <= r.maxY + margin
                && show.origin.map(r.insetBy(dx: -0.75, dy: -0.75).contains) == true {
                let b = r.insetBy(dx: -1, dy: -1)
                let c = show.clip
                if c.isNull || b.maxX < c.minX || b.minX > c.maxX || b.maxY < c.minY || b.minY > c.maxY { reasons.insert("clip") }
                else { reasons.insert("cover") }
            }
            let text = line.text.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
            print("\(n)\t\(i)\t\(line.structure.map { "g\($0.group)/h\($0.headingLevel)" } ?? "-")\t\(reasons.sorted().joined(separator: "+"))\t\(Int(r.minX))\t\(Int(r.minY))\t\(Int(r.width))\t\(Int(r.height))\t\(text.prefix(160))")
        }
    }
}
FileHandle.standardError.write("pages \(doc.pageCount); dropped lines \(dropped) on \(pagesWithDrops) pages (\(pagesEmptied) emptied); skipped: invisible-text \(skippedInvisible), placement-unsupported \(skippedPlacement)\n".data(using: .utf8)!)
