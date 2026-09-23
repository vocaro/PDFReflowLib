import Foundation

/// A full prose column carries an unfinished sentence past its bottom figure into the next
/// column (#160). The figure and its caption keep their blocks; only that sentence resumes.
enum ColumnContinuation {
    static func pairs(_ elements: [LayoutReconstructor.Element], roles: [LineRole?],
                      body: CGFloat) -> [Int: Int] {
        guard elements.count == roles.count else { return [:] }
        var result: [Int: Int] = [:]
        for start in elements.indices {
            // No continuation plan can cross prose before its first figure. Reject this
            // common case before searching column geometry on a text-heavy page.
            guard start + 1 < elements.count, elements[start + 1].image != nil,
                  roles[start] == .prose, let last = elements[start].line,
                  !LayoutReconstructor.isCaption(last.text), last.turn == .upright,
                  last.rect.width >= body * 12,
                  last.text.last.map({ $0.isLetter || $0 == "-" }) == true else { continue }
            // A filled column, not an isolated label: two preceding lines state its measure.
            let above = elements.indices[..<start].filter { index in
                guard roles[index] == .prose, let line = elements[index].line,
                      !LayoutReconstructor.isCaption(line.text) else { return false }
                return line.hasSize(last.fontSize) && abs(line.rect.minX - last.rect.minX) < body * 0.5
                    && abs(line.rect.maxX - last.rect.maxX) < body * 0.5
                    && line.rect.minY > last.rect.minY && line.rect.minY - last.rect.minY < body * 4
            }
            guard above.count >= 2 else { continue }
            var index = start + 1
            var figures = 0
            var caption: TextLine?
            while index < elements.count {
                let element = elements[index]
                if element.image != nil {
                    guard element.rect.minX >= last.rect.minX - body,
                          element.rect.maxX <= last.rect.maxX + body,
                          element.rect.maxY <= last.rect.minY + body * 0.5 else { break }
                    figures += 1
                    caption = nil
                } else if let line = element.line, figures > 0,
                          line.rect.minX >= last.rect.minX - body,
                          line.rect.maxX <= last.rect.maxX + body,
                          line.rect.maxY < last.rect.minY {
                    if LayoutReconstructor.isCaption(line.text) {
                        caption = line
                    } else if let previous = caption, previous.hasSize(line.fontSize),
                              abs(previous.rect.minX - line.rect.minX) < body,
                              previous.rect.minY - line.rect.maxY >= -body * 0.4,
                              previous.rect.minY - line.rect.maxY < body {
                        caption = line
                    } else { break }
                } else { break }
                index += 1
            }
            guard figures > 0, index < elements.count, roles[index] == .prose,
                  let next = elements[index].line, next.turn == .upright,
                  next.hasSize(last.fontSize), !LayoutReconstructor.isCaption(next.text),
                  next.text.first?.isLetter == true,
                  next.rect.minX > last.rect.maxX + body * 0.5,
                  next.rect.minY > last.rect.maxY + body,
                  abs(next.rect.width - last.rect.width) < body,
                  last.structure?.group == next.structure?.group,
                  (last.structure?.headingLevel ?? 0) == 0,
                  (next.structure?.headingLevel ?? 0) == 0 else { continue }
            // The continuation opens the next column's prose, rather than a lone graphic label.
            let below = elements.indices.dropFirst(index + 1).filter { offset in
                guard roles[offset] == .prose, let line = elements[offset].line,
                      !LayoutReconstructor.isCaption(line.text) else { return false }
                return line.hasSize(next.fontSize) && abs(line.rect.minX - next.rect.minX) < body * 0.5
                    && line.rect.maxY < next.rect.maxY && next.rect.maxY - line.rect.maxY < body * 5
            }
            guard below.count >= 2 else { continue }
            result[index] = start
        }
        return result
    }
}
