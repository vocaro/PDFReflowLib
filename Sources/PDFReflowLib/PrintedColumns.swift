import CoreGraphics
import Foundation

/// Persistent text margins can state columns even when a title or decorative rule crosses
/// their gutters. Short aligned cells do not establish these margins: each column needs several
/// wide lines of words of its own.
enum PrintedColumns {
    typealias Element = LayoutReconstructor.Element
    struct Plan { var before: [Int: [Element]]; var columns: [[Element]]; var after: [Int: [Element]] }

    static func plan(_ elements: [Element], body: CGFloat) -> Plan? {
        guard elements.count <= 2_000, body > 0 else { return nil }
        let captionLines = elements.flatMap { $0.caption ?? $0.pictureCaption ?? [] }
        let quoteLines = elements.flatMap { $0.quotation ?? [] }
        let writing = elements.flatMap { element -> [TextLine] in
            if let quote = element.quotation { return quote }
            if let caption = element.caption ?? element.pictureCaption { return caption }
            return element.line.map { [$0] } ?? []
        }
        let evidence = writing.filter {
            $0.turn == .upright && !$0.monospaced && ($0.fontSize >= body * 0.9 && $0.fontSize <= body * 1.1 || quoteLines.contains($0)) && $0.rect.width >= body * 8
                && $0.text.split(whereSeparator: \.isWhitespace).count >= 4
                || captionLines.contains($0)
        }.sorted { $0.rect.minX < $1.rect.minX }
        var groups: [[TextLine]] = []
        for line in evidence {
            if let last = groups.last, line.rect.minX - last[0].rect.minX <= body * 3 {
                groups[groups.count - 1].append(line)
            } else { groups.append([line]) }
        }
        // A caption can use the photograph's wider margin above an indented body column.
        // Merge only vertically disjoint measures with substantial horizontal overlap and
        // already proved caption ownership; simultaneous neighboring columns stay separate.
        var index = 0
        while index + 1 < groups.count {
            let a = union(groups[index].map(\.rect)), b = union(groups[index + 1].map(\.rect))
            let overlap = min(a.maxX,b.maxX) - max(a.minX,b.minX)
            if (groups[index] + groups[index + 1]).contains(where: { captionLines.contains($0) }),
               overlap >= min(a.width,b.width) * 0.75,
               a.maxY <= b.minY || b.maxY <= a.minY {
                groups[index] += groups.remove(at: index + 1)
            } else { index += 1 }
        }
        groups = groups.filter { group in
            group.count >= 6 && group.filter { $0.rect.width >= body * 12 }.count >= 2
                && union(group.map(\.rect)).height >= body * 6
        }
        guard (2...4).contains(groups.count) else { return nil }
        let lefts = groups.map { $0.map(\.rect.minX).min()! }
        let rights = groups.map { group -> CGFloat in
            let edges = group.map(\.rect.maxX).sorted()
            return edges[min(edges.count - 1, Int(Double(edges.count) * 0.8))]
        }
        var cuts: [CGFloat] = []
        for index in 0..<(groups.count - 1) {
            guard lefts[index + 1] - rights[index] >= body * 0.6 else { return nil }
            cuts.append((lefts[index + 1] + rights[index]) / 2)
        }
        var columns = Array(repeating: [Element](), count: groups.count)
        var floating: [Element] = []
        for element in elements {
            let column = cuts.firstIndex { element.rect.midX < $0 } ?? cuts.count
            // A picture frame can extend into the empty gutter while remaining clear of
            // every neighboring text column. Its padding is not a spanning reading unit.
            let graphical = element.line == nil
            let minX = column == 0 ? -CGFloat.infinity
                : graphical ? rights[column - 1] + body * 0.2 : cuts[column - 1]
            let maxX = column == cuts.count ? CGFloat.infinity
                : graphical ? lefts[column + 1] - body * 0.2 : cuts[column]
            if element.rect.minX >= minX - 1 && element.rect.maxX <= maxX + 1 {
                columns[column].append(element)
            } else { floating.append(element) }
        }
        guard columns.allSatisfy({ !$0.isEmpty }) else { return nil }
        var before: [Int: [Element]] = [:], after: [Int: [Element]] = [:]
        for element in floating {
            let touched = groups.indices.filter {
                element.rect.maxX > lefts[$0] && element.rect.minX < rights[$0]
            }
            guard let first = touched.first, let last = touched.last else { return nil }
            let top = touched.flatMap { groups[$0] }.map(\.rect.maxY).max()!
            let bottom = touched.flatMap { groups[$0] }.map(\.rect.minY).min()!
            if element.rect.minY >= top - 1 { before[first, default: []].append(element) }
            else if element.rect.maxY <= bottom + 1 { after[last, default: []].append(element) }
            // A preserved background can cross the gutter and overlap several columns.
            // Native paragraph ownership was proved before ordering; retain the crop after
            // those columns instead of allowing its bounds to interleave their rows.
            else if element.image != nil && element.proseBackdrop { after[last, default: []].append(element) }
            else { return nil }
        }
        return Plan(before: before, columns: columns, after: after)
    }
}
