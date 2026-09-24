import CoreGraphics
import Foundation

/// Recovered panel prose stays one reading unit beside the paragraph it accompanies. Its
/// painted rectangle supplies grouping evidence; type size alone cannot make an aside.
enum NativeTextPanels {
    static func ordered(_ elements: [LayoutReconstructor.Element], panels: [CGRect], body: CGFloat,
                        rightToLeft: Bool) -> [LayoutReconstructor.Element] {
        guard !panels.isEmpty, panels.count <= 128, elements.count <= 2_000 else { return elements }
        // structuredOrder has already validated these tags and their intervening barriers.
        // Geometry may group untagged prose, but cannot override the source's reading order.
        let tagged = elements.indices.filter { elements[$0].line?.structure != nil }
        struct Group { var rect: CGRect; var indices: Set<Int>; var first: Int; var span: Range<Int> }
        var groups: [Group] = [], claimed: Set<Int> = []
        for panel in panels.sorted(by: { $0.width * $0.height < $1.width * $1.height }) {
            // Figures and semantic tables within a panel have their own reading structure.
            // This rule groups native prose only; it does not flatten those elements.
            guard !elements.contains(where: { $0.line == nil && $0.rect.intersects(panel.insetBy(dx: 2,dy: 2)) }) else { continue }
            let members = Set(elements.indices.filter { index in
                guard !claimed.contains(index), let line = elements[index].line,
                      line.turn == .upright, !line.monospaced else { return false }
                return panel.insetBy(dx: -1,dy: -1).contains(line.rect)
            })
            guard members.count >= 3, members.reduce(0,{ $0 + (elements[$1].line?.text.count ?? 0) }) >= 100 else { continue }
            // A painted panel can stop between items of one list. Earthdata slide 7's panel
            // contains `a.` but leaves `b.` immediately below it. Recursing over just the
            // panel would take away the sibling that establishes `a.` as a marker (#219).
            let panelLines = elements.compactMap(\.line)
            let cutsMarkerRun = members.contains { index in
                guard let marker = elements[index].line,
                      let kind = LayoutReconstructor.markerKind(of: marker.text, whole: true),
                      LayoutReconstructor.opensAloneAsMarker(marker, in: panelLines, body: body)
                else { return false }
                return elements.indices.contains { sibling in
                    guard !members.contains(sibling), let next = elements[sibling].line,
                          LayoutReconstructor.markerKind(of: next.text, whole: true) == kind,
                          next.hasSize(marker.fontSize),
                          abs(next.rect.minX - marker.rect.minX) < body * 0.5 else { return false }
                    return abs(next.rect.minY - marker.rect.minY) <= body * 3
                }
            }
            if cutsMarkerRun { continue }
            let first = members.min()!, last = members.max()!
            guard !tagged.contains(where: { first <= $0 && $0 <= last }) else { continue }
            let lower = (tagged.last(where: { $0 < first }) ?? -1) + 1
            let upper = tagged.first(where: { $0 > last }) ?? elements.count
            groups.append(Group(rect: panel, indices: members, first: first, span: lower..<upper))
            claimed.formUnion(members)
        }
        guard !groups.isEmpty else { return elements }
        let outside = elements.indices.filter { !claimed.contains($0) }
        var runs: [[Int]] = []
        for index in outside.sorted(by: { elements[$0].rect.maxY > elements[$1].rect.maxY }) {
            guard let line = elements[index].line, line.structure == nil,
                  line.turn == .upright, !line.monospaced else { continue }
            if let run = runs.indices.last(where: { number in
                let items = runs[number], previous = elements[items.last!].line!, size = max(line.fontSize,previous.fontSize)
                let drop = previous.rect.minY - line.rect.minY
                let leading = items.count >= 2 ? elements[items[0]].rect.minY - elements[items[1]].rect.minY : drop
                let edge = rightToLeft ? abs(line.rect.maxX - previous.rect.maxX) : abs(line.rect.minX - previous.rect.minX)
                return abs(line.fontSize - previous.fontSize) <= size * 0.1
                    && edge <= size * 0.3
                    && drop >= size * 0.8 && drop <= size * 2.2
                    && abs(drop - leading) <= max(1,leading * 0.2)
            }) { runs[run].append(index) }
            else { runs.append([index]) }
        }
        var insertions: [Int: [[LayoutReconstructor.Element]]] = [:]
        var continuationStarts: [Int: CGRect] = [:]
        for group in groups.sorted(by: { $0.first < $1.first }) {
            // A narrow panel cannot precede complete full-measure rows printed above it.
            // Whitespace column planning can place the small panel first; require two
            // untagged prose rows crossing its measure before repairing that placement.
            let panelLast = group.indices.max()!
            let above = outside.filter { index in
                guard index > panelLast, group.span.contains(index), let line = elements[index].line,
                      line.structure == nil, LayoutReconstructor.readsAsSentence(line) else { return false }
                return line.rect.minY > group.rect.maxY && line.rect.minX < group.rect.minX
                    && line.rect.maxX > group.rect.maxX - body * 2
            }
            let premature = above.count >= 2 && !outside.contains { index in
                index > panelLast && index < above.last! && elements[index].line == nil
            }
            let adjacent = runs.filter { run in
                guard run.count >= 3, run.allSatisfy(group.span.contains), run.filter({ LayoutReconstructor.readsAsSentence(elements[$0].line!) }).count >= 2 else { return false }
                // A paragraph in a neighboring, already ordered column is not interrupted
                // by this panel. Retain that order unless the source proves a broken word
                // continuing into the wider measure immediately below this panel.
                guard let first = run.min(), let last = run.max(), let panelLast = group.indices.max(),
                      (first < panelLast && last > group.first) || widerContinuation(run) != nil || premature else { return false }
                let bounds = union(run.map { elements[$0].rect })
                let overlap = min(bounds.maxY,group.rect.maxY) - max(bounds.minY,group.rect.minY)
                guard overlap >= min(bounds.height,group.rect.height) * 0.5 else { return false }
                let rows = run.map { elements[$0].rect }.filter { $0.maxY > group.rect.minY && $0.minY < group.rect.maxY }
                return !rows.isEmpty && ((rows.allSatisfy { $0.maxX <= group.rect.minX + 1 }
                    && rows.filter { group.rect.minX - $0.maxX <= body * 5 }.count >= min(2,rows.count))
                    || (rows.allSatisfy { $0.minX >= group.rect.maxX - 1 }
                    && rows.filter { $0.minX - group.rect.maxX <= body * 5 }.count >= min(2,rows.count)))
            }
            // Complete the adjacent paragraph, including its wider continuation below the
            // panel. The panel cannot interrupt a word merely because its midpoint is higher.
            func widerContinuation(_ run: [Int]) -> [Int]? {
                let last = run.last!, before = elements[last].line!
                guard before.text.hasSuffix("-") || before.text.hasSuffix("\u{00ad}") else { return nil }
                let size = before.fontSize
                let leading = elements[run[0]].rect.minY - elements[run[1]].rect.minY
                let following = runs.filter { next in
                    guard next.count >= 2, next.allSatisfy(group.span.contains),
                          let first = next.first, first > last,
                          let after = elements[first].line, after.text.first?.isLowercase == true,
                          abs(after.fontSize - size) <= size * 0.1,
                          abs(before.rect.minY - after.rect.minY - leading) <= max(1, leading * 0.2),
                          before.rect.minY >= group.rect.minY - size * 2,
                          after.rect.maxY <= group.rect.minY + size * 0.2,
                          after.rect.width >= before.rect.width + size * 2 else { return false }
                    // A broken word may finish in the wider measure immediately below a
                    // panel. Its new outer edge follows that panel, while its far edge still
                    // reaches the original text column. Other columns cannot supply a row.
                    let nearGap = rightToLeft ? group.rect.minX - before.rect.maxX
                                             : before.rect.minX - group.rect.maxX
                    let outerEdge = rightToLeft ? abs(after.rect.maxX - group.rect.maxX)
                                               : abs(after.rect.minX - group.rect.minX)
                    let reachesColumn = rightToLeft ? after.rect.minX <= before.rect.minX + size * 3
                                                   : after.rect.maxX >= before.rect.maxX - size * 3
                    guard nearGap >= -1, nearGap <= body * 5, outerEdge <= size,
                          reachesColumn else { return false }
                    return !elements.indices.contains { index in
                        index > last && index < first && !group.indices.contains(index)
                    }
                }
                guard following.count == 1 else { return nil }
                return following[0]
            }
            let anchor = adjacent.map { run -> Int in
                let last = run.last!
                guard let following = widerContinuation(run) else { return last }
                continuationStarts[following.first!] = elements[last].rect
                return following.last!
            }.max() ?? (premature ? above.last : nil) ?? outside.last(where: { $0 < group.first }) ?? -1
            let members = LayoutReconstructor.ordered(group.indices.sorted().map { elements[$0] }, bodySize: body,
                                                       rightToLeft: rightToLeft)
            let unit = LayoutReconstructor.Element(rect: group.rect, nativePanel: members.compactMap(\.line))
            insertions[anchor, default: []].append([unit])
        }
        var result = (insertions[-1] ?? []).flatMap { $0 }
        for index in outside {
            var element = elements[index]
            element.panelContinuationFrom = continuationStarts[index]
            result.append(element); result += (insertions[index] ?? []).flatMap { $0 }
        }
        return result
    }
}
