import CoreGraphics
import Foundation

extension LayoutReconstructor {
    /// A printed two-column exercise grid whose paired markers state 1, 2, 3, 4 order.
    /// The source page may put a diagram beneath each marker or an instruction between rows.
    static func numberedExerciseRows(_ elements: [Element], body: CGFloat, rightToLeft: Bool,
                                     depth: Int, exhausted: inout Bool) -> [Element]? {
        struct Marker {
            let number: Int
            let rect: CGRect
        }
        func number(_ text: String) -> Int? {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard let close = trimmed.firstIndex(of: ")"),
                  close.utf16Offset(in: trimmed) <= 3,
                  let value = Int(trimmed[..<close]), value > 0 else { return nil }
            return value
        }
        let markers = elements.compactMap { element -> Marker? in
            guard element.image == nil, element.table == nil, let line = element.line,
                  line.turn == .upright, element.rect.width < body * 12,
                  let number = number(line.text) else { return nil }
            return Marker(number: number, rect: element.rect)
        }.sorted { $0.number < $1.number }
        guard markers.count >= 6, markers.count.isMultiple(of: 2),
              let first = markers.first,
              markers.enumerated().allSatisfy({ $0.element.number == first.number + $0.offset })
        else { return nil }

        let pairs = stride(from: 0, to: markers.count, by: 2).map { (markers[$0], markers[$0 + 1]) }
        let leftX = pairs[0].0.rect.minX, rightX = pairs[0].1.rect.minX
        guard rightX - leftX >= body * 6,
              pairs.allSatisfy({ pair in
                  let left = pair.0, right = pair.1
                  return left.rect.minX < right.rect.minX
                      // Stacked complex fractions can make one printed marker sit
                      // nearly a body-height above its partner despite sharing a row.
                      // The full consecutive odd/even run and fixed column starts
                      // still prove the pairing (Wallace page 266).
                      && abs(left.rect.midY - right.rect.midY)
                          <= max(body * 0.8, max(left.rect.height, right.rect.height) * 0.75)
                      && abs(left.rect.minX - leftX) <= body * 0.4
                      && abs(right.rect.minX - rightX) <= body * 0.4
              }),
              pairs.indices.dropFirst().allSatisfy({ index in
                  pairs[index - 1].0.rect.midY - pairs[index].0.rect.midY >= body * 0.5
              }) else { return nil }

        let split = rightX - body * 2
        let lastStep = pairs[pairs.count - 2].0.rect.midY - pairs.last!.0.rect.midY
        let bottom = pairs.last!.0.rect.minY - lastStep
        var before: [Element] = [], after: [Element] = []
        var left = Array(repeating: [Element](), count: pairs.count)
        var right = Array(repeating: [Element](), count: pairs.count)
        var between = Array(repeating: [Element](), count: pairs.count)
        for element in elements {
            let rect = element.rect
            if rect.midY > pairs[0].0.rect.maxY + body * 0.25 {
                before.append(element); continue
            }
            if rect.midY < bottom {
                after.append(element); continue
            }
            var row = 0
            for index in pairs.indices where rect.midY <= pairs[index].0.rect.maxY + body * 0.25 {
                row = index
            }
            // An instruction on the exercise column's leading, below a completed pair and
            // before the next, divides the runs. Wallace 10 puts `Find each product.` there.
            if row + 1 < pairs.count, let line = element.line,
               number(line.text) == nil,
               rect.maxY < pairs[row].0.rect.minY - body * 0.2,
               abs(rect.minX - leftX) <= body * 0.4,
               rect.width >= body * 7,
               line.text.split(whereSeparator: \.isWhitespace).count >= 2 {
                between[row].append(element); continue
            }
            // A figure reaching across the gutter is not two exercises whose own bounds can
            // be assigned to one marker each.
            if rect.minX < split - body * 0.5 && rect.maxX > split + body * 0.5 { return nil }
            if rect.midX < split { left[row].append(element) }
            else { right[row].append(element) }
        }
        func read(_ group: [Element]) -> [Element] {
            ordered(group, bodySize: body, rightToLeft: rightToLeft,
                    depth: depth + 1, exhausted: &exhausted)
        }
        func readCell(_ group: [Element]) -> [Element] {
            let numbered = group.filter { $0.line.flatMap { number($0.text) } != nil }
            // A tall fraction's numerator rises above its printed marker. The marker
            // still introduces that formula, and must precede its crop in reading order.
            if numbered.count == 1, group.contains(where: { $0.image != nil }),
               let marker = numbered.first,
               group.filter({ $0.image != nil }).allSatisfy({ $0.rect.minX >= marker.rect.minX }) {
                return [marker] + read(group.filter { $0.rect != marker.rect })
            }
            return read(group)
        }
        // A short heading/instruction stack above the grid is read top to bottom.
        // Its centred heading can otherwise look like a second column and follow
        // the left-aligned instruction (Wallace page 266).
        var result = before.count <= 3 && before.allSatisfy({ $0.line != nil })
            ? before.sorted { $0.rect.midY > $1.rect.midY }
            : read(before)
        for index in pairs.indices {
            result += readCell(left[index]) + readCell(right[index]) + read(between[index])
        }
        result += read(after)
        return result
    }
}
