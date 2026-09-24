import CoreGraphics
import Foundation

/// Recovered panel prose stays one reading unit beside the paragraph it accompanies. Its
/// painted rectangle supplies grouping evidence; type size alone cannot make an aside.
enum NativeTextPanels {
    static func ordered(_ elements: [LayoutReconstructor.Element], panels: [CGRect], body: CGFloat,
                        rightToLeft: Bool) -> [LayoutReconstructor.Element] {
        guard !panels.isEmpty, panels.count <= 128, elements.count <= 2_000 else { return elements }
        struct Group { var rect: CGRect; var indices: Set<Int>; var first: Int }
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
            let tags = Set(members.compactMap { elements[$0].line?.structure?.group })
            guard !elements.indices.contains(where: { index in
                !members.contains(index) && elements[index].line?.structure.map { tags.contains($0.group) } == true
            }) else { continue }
            groups.append(Group(rect: panel, indices: members, first: members.min()!)); claimed.formUnion(members)
        }
        guard !groups.isEmpty else { return elements }
        let outside = elements.indices.filter { !claimed.contains($0) }
        var runs: [[Int]] = []
        for index in outside.sorted(by: { elements[$0].rect.maxY > elements[$1].rect.maxY }) {
            guard let line = elements[index].line, line.turn == .upright, !line.monospaced else { continue }
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
        for group in groups.sorted(by: { $0.first < $1.first }) {
            let adjacent = runs.filter { run in
                guard run.count >= 3, run.filter({ LayoutReconstructor.readsAsSentence(elements[$0].line!) }).count >= 2 else { return false }
                // A paragraph in a neighboring, already ordered column is not interrupted
                // by this panel. Move only a group whose current range overlaps that run;
                // otherwise retain the column order already established above.
                guard let first = run.min(), let last = run.max(), let panelLast = group.indices.max(),
                      first < panelLast && last > group.first else { return false }
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
            let anchor = adjacent.compactMap(\.last).max() ?? outside.last(where: { $0 < group.first }) ?? -1
            let members = LayoutReconstructor.ordered(group.indices.sorted().map { elements[$0] }, bodySize: body,
                                                       rightToLeft: rightToLeft)
            let unit = LayoutReconstructor.Element(rect: group.rect, nativePanel: members.compactMap(\.line))
            insertions[anchor, default: []].append([unit])
        }
        var result = (insertions[-1] ?? []).flatMap { $0 }
        for index in outside {
            result.append(elements[index]); result += (insertions[index] ?? []).flatMap { $0 }
        }
        return result
    }
}
