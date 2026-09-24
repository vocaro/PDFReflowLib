import Foundation

/// Native lines inside a preserved drawing, positioned over the image so they remain
/// selectable without adding a second visible copy of the diagram's lettering (#212).
enum DiagramLabelTranscript {
    static func labels(page: PageContent, images: [(CGRect, String)], body: CGFloat)
        -> [String: [ReflowBlock.Image.SelectableLabel]] {
        var result: [String: [ReflowBlock.Image.SelectableLabel]] = [:]
        let marker = #"^[0-9]{1,3}\)"#
        let word = #"\p{L}{3,}"#
        // Three equal, separated near-square diagram stages on one row: the Earthdata workflow
        // draws Extract/Transform/Load in the first circle, Analyze in the second, Visualize in
        // the third. Their frame fills each crop, as a table frame can, so the trio and its
        // short centered labels must establish the different reading before the frame veto.
        let stages = images.filter { crop, _ in
            crop.width >= body * 6 && crop.height >= body * 6
                && (0.9...1.15).contains(crop.width / crop.height)
                && page.tables.allSatisfy { !$0.rect.intersects(crop) }
                && (1...3).contains(page.lines.count { LayoutReconstructor.takes(crop, $0) })
                && page.lines.filter { LayoutReconstructor.takes(crop, $0) }.allSatisfy {
                    $0.text.range(of: #"^[A-Z][a-z]{3,11}$"#, options: .regularExpression) != nil
                }
        }.sorted { $0.0.minX < $1.0.minX }
        var stageIDs: Set<String> = []
        if stages.count == 3, stages.map({ crop, _ in
            page.lines.count { LayoutReconstructor.takes(crop, $0) }
        }).sorted() == [1, 1, 3] {
            let rects = stages.map(\.0)
            let matched = zip(rects, rects.dropFirst()).allSatisfy { left, right in
                abs(left.minY - right.minY) < body * 0.2
                    && abs(left.width - right.width) < body * 0.2
                    && abs(left.height - right.height) < body * 0.2
                    && (body * 0.75...body * 3).contains(right.minX - left.maxX)
            }
            if matched { stageIDs = Set(stages.map(\.1)) }
        }
        for (crop, assetID) in images {
            let lines = page.lines.filter { LayoutReconstructor.takes(crop, $0) && !$0.text.isEmpty }
            // A ruled table's outer frame nearly fills its crop. Its short numeric cells are
            // not diagram labels: transcribing them as loose spans loses their row/column
            // associations (#210). Wallace's triangles have drawing ink inset on all sides.
            let hasTableFrame = page.graphics.contains { graphic in
                crop.intersects(graphic)
                    && graphic.width >= crop.width * 0.9
                    && graphic.height >= crop.height * 0.9
                    && abs(graphic.midX - crop.midX) <= body
                    && abs(graphic.midY - crop.midY) <= body
            }
            let stage = stageIDs.contains(assetID)
            guard (stage || (2...8).contains(lines.count)),
                  (stage || !hasTableFrame),
                  (stage || lines.allSatisfy({ line in
                      line.text.count <= 12
                          && (line.text.range(of: marker, options: .regularExpression) != nil
                              || line.text.range(of: word, options: .regularExpression) == nil)
                  })),
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
