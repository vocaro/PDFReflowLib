import CoreGraphics
import Foundation

/// Rebuilds a form's printed row from the text pieces on either side of its writing rules.
enum FormBlankRows {
    static func joined(_ lines: [TextLine], blanks: [FormBlank]) -> [TextLine] {
        guard !blanks.isEmpty else { return lines }
        func eligible(_ line: TextLine) -> Bool {
            line.structure == nil && !line.monospaced && line.turn == .upright
                && !line.text.trimmingCharacters(in: .whitespaces).isEmpty
        }
        var parent = Array(lines.indices)
        func root(_ index: Int) -> Int {
            var index = index
            while parent[index] != index { index = parent[index] }
            return index
        }
        var rowBlanks: [(piece: Int, rule: CGRect)] = []
        for blank in blanks {
            let rule = blank.rule.insetBy(dx: 2, dy: 0)
            let row = lines.indices.filter { eligible(lines[$0]) && blank.sharesRow(with: lines[$0].rect) }
            // Text printed on the rule is a value, not an empty writing space.
            guard !row.contains(where: { lines[$0].rect.maxX > rule.minX + 2 && lines[$0].rect.minX < rule.maxX - 2 })
            else { continue }
            let left = row.filter { lines[$0].rect.maxX <= rule.minX + 2 }
                .max { lines[$0].rect.maxX < lines[$1].rect.maxX }
            let right = row.filter { lines[$0].rect.minX >= rule.maxX - 2 }
                .min { lines[$0].rect.minX < lines[$1].rect.minX }
            guard let anchor = left ?? right else { continue }
            if let left, let right { parent[root(right)] = root(left) }
            rowBlanks.append((anchor, rule))
        }
        guard !rowBlanks.isEmpty else { return lines }
        var replaced: [Int: TextLine] = [:]
        var removed = Set<Int>()
        let rows = Dictionary(grouping: lines.indices.filter { index in
            rowBlanks.contains { root($0.piece) == root(index) }
        }, by: root)
        for (_, members) in rows {
            enum Item { case piece(Int), blank(CGRect) }
            let blanksHere = rowBlanks.filter { root($0.piece) == root(members[0]) }.map(\.rule)
            let items = (members.map { Item.piece($0) } + blanksHere.map { Item.blank($0) }).sorted { a, b in
                func x(_ item: Item) -> CGFloat {
                    switch item { case let .piece(index): lines[index].rect.midX; case let .blank(rule): rule.midX }
                }
                return x(a) < x(b)
            }
            var content = InlineText()
            var afterBlank = false
            for item in items {
                switch item {
                case let .piece(index):
                    let closesUp = afterBlank && lines[index].text.first.map { ",.;:)!?".contains($0) } == true
                    if !content.elements.isEmpty && !closesUp { content.append(InlineText(" ")) }
                    content.append(lines[index].content)
                    afterBlank = false
                case .blank:
                    if !content.elements.isEmpty { content.append(InlineText(" ")) }
                    content.append(InlineText(FormBlank.text))
                    afterBlank = true
                }
            }
            let pieces = members.map { lines[$0] }
            let text = union(pieces.map(\.rect))
            let extent = union(pieces.map(\.rect) + blanksHere)
            let last = pieces.max { $0.rect.maxX < $1.rect.maxX }!
            let joined = TextLine(content: content,
                                  rect: CGRect(x: extent.minX, y: text.minY, width: extent.width, height: text.height),
                                  fontSize: pieces.map(\.fontSize).max() ?? last.fontSize,
                                  wraps: afterBlank ? false : last.wraps)
            let anchor = members.min()!
            replaced[anchor] = joined
            removed.formUnion(members.filter { $0 != anchor })
        }
        return lines.indices.compactMap { index in removed.contains(index) ? nil : replaced[index] ?? lines[index] }
    }
}
