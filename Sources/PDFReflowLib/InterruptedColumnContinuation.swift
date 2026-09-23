import Foundation

/// The end of one justified column can continue at the top of the next column while a
/// photograph or display quotation takes its own place between them. Only the paragraph
/// handle resumes; those intervening blocks retain their content and order.
enum InterruptedColumnContinuation {
    static func pairs(_ elements: [LayoutReconstructor.Element], roles: [LineRole?],
                      body: CGFloat) -> [Int: Int] {
        guard body > 0, elements.count == roles.count, elements.count <= 2000 else { return [:] }
        func prose(_ index: Int) -> TextLine? {
            guard roles[index] == .prose, let line = elements[index].line,
                  line.turn == .upright, !line.monospaced, line.hasSize(body),
                  !LayoutReconstructor.isCaption(line.text),
                  (line.structure?.headingLevel ?? 0) == 0 else { return nil }
            return line
        }
        let bodyRightEdge = elements.indices.compactMap { prose($0)?.rect.maxX }.max() ?? 0
        var result: [Int: Int] = [:]
        for start in elements.indices {
            guard let last = prose(start), last.rect.width >= body * 12,
                  let ending = last.text.last, ending.isLetter || ending == "," || ending == "-"
            else { continue }
            // This is the last body line in a filled column. A caption or an isolated label
            // cannot establish it, nor can a paragraph ending above more prose in that measure.
            let column = elements.indices.compactMap { index -> TextLine? in
                guard let line = prose(index), line.hasSize(last.fontSize),
                      abs(line.rect.minX - last.rect.minX) < body * 0.25,
                      abs(line.rect.maxX - last.rect.maxX) < body * 0.5 else { return nil }
                return line
            }
            guard column.count >= 3, !column.contains(where: { $0.rect.minY < last.rect.minY - 1 }),
                  elements.indices[..<start].contains(where: { index in
                      guard let line = prose(index) else { return false }
                      let step = line.rect.minY - last.rect.minY
                      return step > 0 && step <= body * 1.7
                          && line.rect.minX >= last.rect.minX - 1
                          && line.rect.minX <= last.rect.minX + body * 1.6
                          && abs(line.rect.maxX - last.rect.maxX) < body * 0.5
                  }) else { continue }
            var next = start + 1
            while next < elements.count, next - start <= 24 {
                let item = elements[next]
                if prose(next) != nil { break }
                if item.image != nil || item.quotation != nil { next += 1; continue }
                if let caption = item.caption, !caption.isEmpty,
                   caption.allSatisfy({ $0.turn == .upright && $0.fontSize < body * 0.85 }) {
                    next += 1; continue
                }
                // Smaller credit/caption lines are considered only provisionally; below they
                // must belong geometrically to an actual intervening picture.
                if let line = item.line, line.turn == .upright, line.fontSize < body * 0.85,
                   !line.monospaced { next += 1; continue }
                break
            }
            guard next < elements.count, let opening = prose(next),
                  opening.hasSize(last.fontSize), opening.text.first?.isLetter == true,
                  last.structure?.group == opening.structure?.group,
                  opening.rect.minX - last.rect.maxX >= body * 0.5,
                  opening.rect.minX - last.rect.maxX <= body * 3,
                  opening.rect.minY > last.rect.minY + body,
                  opening.rect.width >= last.rect.width * 0.65,
                  opening.rect.width <= last.rect.width * 1.1 else { continue }
            let between = Array(elements[(start + 1)..<next])
            // Without a separated display, only an explicit broken word licenses this path.
            guard !between.isEmpty || ending == "-" else { continue }
            let pictures = between.compactMap { $0.image == nil ? nil : $0.rect }
            guard between.allSatisfy({ item in
                if item.quotation != nil {
                    return item.rect.minX >= opening.rect.minX - body
                        && item.rect.maxX <= opening.rect.maxX + body
                        && item.rect.minY > opening.rect.maxY
                }
                if item.image != nil {
                    return item.rect.minX >= opening.rect.minX - body
                        && item.rect.minX <= opening.rect.maxX + body * 2
                        && item.rect.maxX <= bodyRightEdge + body
                        && item.rect.width <= opening.rect.width * 2
                        && item.rect.maxY >= opening.rect.maxY - body
                }
                let caption = item.caption ?? item.line.map { [$0] } ?? []
                return !caption.isEmpty && caption.allSatisfy { line in
                    pictures.contains { picture in
                        line.rect.minX >= picture.minX - body
                            && line.rect.maxX <= picture.maxX + body
                            && line.rect.minY >= picture.minY - body * 5
                            && line.rect.maxY <= picture.maxY + body * 2
                    }
                }
            }) else { continue }
            // The opening is flush with two body rows below it, at the top of that measure.
            // An indented new paragraph, an isolated graphic label or intervening prose fails.
            let followers = elements.indices.dropFirst(next + 1).compactMap { index -> TextLine? in
                guard let line = prose(index), line.hasSize(opening.fontSize),
                      abs(line.rect.minX - opening.rect.minX) < body * 0.25,
                      line.rect.maxX <= opening.rect.maxX + body * 0.5,
                      line.rect.minY < opening.rect.minY,
                      opening.rect.minY - line.rect.minY <= body * 3 else { return nil }
                return line
            }
            guard followers.count >= 2,
                  !elements.indices.contains(where: { index in
                      guard let line = prose(index) else { return false }
                      return abs(line.rect.minX - opening.rect.minX) < body * 0.25
                          && line.rect.minY > opening.rect.minY + 1
                  }) else { continue }
            result[next] = start
        }
        return result
    }
}
