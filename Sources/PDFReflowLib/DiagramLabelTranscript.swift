import Foundation

/// Native text swallowed by a preserved drawing still needs a selectable representation.
/// This transcribes only compact diagram labels; a crop remains the visual reference.
enum DiagramLabelTranscript {
    static func descriptions(page: PageContent, images: [(CGRect, String)], body: CGFloat) -> [String: String] {
        var result: [String: String] = [:]
        let marker = #"^[0-9]{1,3}\)"#
        let word = #"\p{L}{3,}"#
        for (crop, assetID) in images {
            let labels = page.lines.filter { LayoutReconstructor.takes(crop, $0) && !$0.text.isEmpty }
            guard (2...8).contains(labels.count),
                  labels.allSatisfy({ line in
                      line.text.count <= 12
                          && (line.text.range(of: marker, options: .regularExpression) != nil
                              || line.text.range(of: word, options: .regularExpression) == nil)
                  }),
                  page.graphics.contains(where: { crop.intersects($0) && $0.width >= body && $0.height >= body })
            else { continue }
            let ordered = labels.sorted { left, right in
                left.rect.midY == right.rect.midY
                    ? left.rect.minX < right.rect.minX : left.rect.midY > right.rect.midY
            }
            result[assetID] = "Preserved diagram from page \(page.number). Text in diagram: "
                + ordered.map(\.text).joined(separator: "; ")
        }
        return result
    }
}
