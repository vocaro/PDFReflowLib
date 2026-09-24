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
}
