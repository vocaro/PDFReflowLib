import Foundation

/// Native lines inside a preserved drawing, positioned over the image so they remain
/// selectable without adding a second visible copy of the diagram's lettering (#212).
enum DiagramLabelTranscript {
    static func labels(page: PageContent, images: [(CGRect, String)], body: CGFloat)
        -> [String: [ReflowBlock.Image.SelectableLabel]] {
        var result: [String: [ReflowBlock.Image.SelectableLabel]] = [:]
        let marker = #"^[0-9]{1,3}\)"#
        let word = #"\p{L}{3,}"#
        for (crop, assetID) in images {
            let lines = page.lines.filter { LayoutReconstructor.takes(crop, $0) && !$0.text.isEmpty }
            guard (2...8).contains(lines.count),
                  lines.allSatisfy({ line in
                      line.text.count <= 12
                          && (line.text.range(of: marker, options: .regularExpression) != nil
                              || line.text.range(of: word, options: .regularExpression) == nil)
                  }),
                  page.graphics.contains(where: { crop.intersects($0) && $0.width >= body && $0.height >= body })
            else { continue }
            let ordered = lines.sorted { left, right in
                left.rect.midY == right.rect.midY
                    ? left.rect.minX < right.rect.minX : left.rect.midY > right.rect.midY
            }
            result[assetID] = ordered.map { line in
                let clipped = crop.intersection(line.rect)
                return .init(text: line.text,
                             left: Double((clipped.minX - crop.minX) / crop.width),
                             top: Double((crop.maxY - clipped.maxY) / crop.height),
                             width: Double(clipped.width / crop.width),
                             height: Double(clipped.height / crop.height))
            }
        }
        return result
    }
}
