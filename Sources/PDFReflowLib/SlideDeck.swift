import CoreGraphics
import Foundation

/// Evidence for a sparse landscape page whose title occupies the top band (#165).
enum SlideDeck {
    static func title(in page: PageContent) -> [TextLine] {
        let bounds = page.bounds
        guard bounds.isFinite, bounds.width > bounds.height, bounds.height > 0,
              !page.hasSyntheticTextStyle,
              page.lines.reduce(0, { $0 + $1.text.count }) <= 600 else { return [] }
        let lines = page.lines.filter {
            $0.rect.isFinite && $0.fontSize > 0 && !$0.monospaced
                && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard let first = lines.max(by: { $0.rect.maxY < $1.rect.maxY }),
              bounds.maxY - first.rect.maxY <= bounds.height * 0.125,
              first.text.count < 200, first.text.filter(\.isLetter).count >= 2,
              !LayoutReconstructor.isList(first.text),
              let initial = first.text.first(where: { !$0.isWhitespace && !"([\u{201C}\"'".contains($0) }),
              initial.isUppercase || initial.isNumber,
              !".!?;:".contains(first.text.last ?? " "),
              !lines.contains(where: { $0 != first && $0.sharesRow(with: first) })
        else { return [] }
        var title = [first]
        while let next = lines.filter({ line in
            !title.contains(line) && LayoutReconstructor.stacksUnderHeading(line, after: title.last!)
        }).max(by: { $0.rect.maxY < $1.rect.maxY }) {
            title.append(next)
        }
        let bottom = title.map(\.rect.minY).min() ?? first.rect.minY
        if let highest = lines.filter({ !title.contains($0) && $0.rect.maxY < bottom }).map(\.rect.maxY).max(),
           bottom - highest < first.rect.height * 0.5 { return [] }
        return title
    }

    /// A smaller display line that heads a paragraph within the slide. Size alone would turn
    /// diagram labels into headings; the source must set a body sentence directly beneath it on
    /// the same edge. Earthdata's top title, diagram labels and large slide-10 callouts provide
    /// the bounds for this second tier (#175).
    static func secondaryHeadings(in page: PageContent, title: [TextLine], body: CGFloat) -> [TextLine] {
        guard let titleSize = title.map(\.fontSize).min(), body > 0 else { return [] }
        let titleBottom = title.map(\.rect.minY).min() ?? page.bounds.maxY
        return page.lines.filter { line in
            guard !title.contains(line), !line.monospaced,
                  line.fontSize >= body * 1.2 && line.fontSize <= titleSize * 0.9,
                  line.rect.maxY < titleBottom - body * 0.75,
                  line.text.count <= 80,
                  line.text.first?.isUppercase == true,
                  !LayoutReconstructor.isList(line.text),
                  !page.graphics.contains(where: { $0.intersects(line.rect) }),
                  !page.lines.contains(where: { $0 != line && $0.sharesRow(with: line) })
            else { return false }
            return page.lines.contains { following in
                guard following != line, !title.contains(following),
                      following.fontSize <= line.fontSize * 0.8,
                      following.rect.maxY < line.rect.minY,
                      abs(following.rect.minX - line.rect.minX) <= body * 0.5,
                      following.text.split(whereSeparator: \.isWhitespace).count >= 5,
                      !page.graphics.contains(where: { $0.intersects(following.rect) })
                else { return false }
                let gap = line.rect.minY - following.rect.maxY
                return gap >= body * 0.5 && gap <= line.fontSize * 2
            }
        }
    }

    /// The assembler has closed each heading before its level is assigned to navigation.
    static func levelSecondary(_ blocks: [ReflowBlock], candidates: [TextLine]) -> [ReflowBlock] {
        guard !candidates.isEmpty else { return blocks }
        return blocks.map { original in
            var block = original
            if case let .heading(id, text, _) = block.content,
               candidates.contains(where: { $0.content == text }) {
                block.content = .heading(id: id, text: text, level: 3)
            }
            return block
        }
    }

    /// A note keyed by a raised marker belongs after the slide's diagram, even when it is
    /// printed at the lower left and the spatial sort reaches it before boxes to its right
    /// (Earthdata slides 19–20, #175). Only a standalone block that reproduces that source line
    /// moves; a paragraph merely containing the same words stays in its source order.
    static func notesLast(_ blocks: [ReflowBlock], on page: PageContent) -> [ReflowBlock] {
        guard !title(in: page).isEmpty else { return blocks }
        let notes = Set(page.lines.compactMap { line -> String? in
            guard case let .text(value, style)? = line.content.elements.first,
                  style.contains(.superscript), line.content.elements.count > 1 else { return nil }
            let printed = value.trimmingCharacters(in: .whitespaces.union(.controlCharacters))
            guard (1...3).contains(printed.count), let number = Int(printed), number > 0,
                  page.lines.contains(where: { other in
                      other != line && other.content.elements.contains { element in
                          guard case let .text(mark, markStyle) = element,
                                markStyle.contains(.superscript) else { return false }
                          return Int(mark.trimmingCharacters(in: .whitespaces.union(.controlCharacters))) == number
                      }
                  }) else { return nil }
            return line.text
        })
        guard !notes.isEmpty else { return blocks }
        let moved = blocks.filter { notes.contains($0.text) }
        return moved.isEmpty ? blocks : blocks.filter { !notes.contains($0.text) } + moved
    }
}
