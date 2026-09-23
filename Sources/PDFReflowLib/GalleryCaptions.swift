import Foundation

/// A row of equally wide, top-aligned pictures states separate caption measures even when
/// the pictures have different heights. Sorting their caption lines by height would interleave
/// the three TechPort page-5 descriptions. Keep the original lines (and their styles/links)
/// with the picture that establishes their measure; callers emit each pair as one element.
enum GalleryCaptions {
    struct Group {
        let image: Int
        let lines: [Int]
        /// Reading footprint, not a crop: all cards in one row share its vertical band.
        let rect: CGRect
    }

    static func groups(lines: [TextLine], images: [CGRect], body: CGFloat) -> [Group] {
        guard body > 0, lines.count <= 2000, images.count <= 100 else { return [] }
        let candidates = images.indices.filter {
            images[$0].width >= body * 6 && images[$0].height >= body * 2
        }.sorted { images[$0].maxY > images[$1].maxY }
        var visited: Set<Int> = []
        var result: [Group] = []
        for seed in candidates where !visited.contains(seed) {
            let row = candidates.filter {
                abs(images[$0].maxY - images[seed].maxY) <= body * 0.5
            }.sorted { images[$0].minX < images[$1].minX }
            visited.formUnion(row)
            guard (2...4).contains(row.count),
                  row.allSatisfy({ images[$0].width / images[seed].width >= 0.8
                      && images[$0].width / images[seed].width <= 1.25 }),
                  zip(row, row.dropFirst()).allSatisfy({
                      images[$1].minX - images[$0].maxX >= body * 0.4
                  }) else { continue }
            var groups: [Group] = []
            for image in row {
                let picture = images[image]
                let below = lines.indices.filter {
                    let line = lines[$0]
                    return line.turn == .upright && !line.monospaced
                        && abs(line.rect.minX - picture.minX) <= body * 0.5
                        && line.rect.maxX <= picture.maxX + body * 0.5
                        && line.rect.maxY <= picture.minY + 1
                        && line.rect.minY >= picture.minY - body * 14
                }.sorted { lines[$0].rect.maxY > lines[$1].rect.maxY }
                var caption: [Int] = []
                var bottom = picture.minY
                for index in below {
                    let line = lines[index]
                    let gap = bottom - line.rect.maxY
                    guard gap >= -1, gap <= body * 0.8,
                          line.fontSize >= body * 0.7, line.fontSize <= body * 1.15,
                          caption.count < 12 else { break }
                    caption.append(index)
                    bottom = line.rect.minY
                }
                guard caption.count >= 2 else { continue }
                let rect = caption.reduce(picture) { $0.union(lines[$1].rect) }
                let claimed = Set(caption)
                // A line crossing the caption's measure or a second picture inside it is
                // ambiguous ownership, not a gallery. Do not silently skip that evidence.
                guard !lines.indices.contains(where: {
                    !claimed.contains($0) && lines[$0].rect.midY < picture.minY
                        && lines[$0].rect.midY >= rect.minY
                        && lines[$0].rect.maxX > rect.minX && lines[$0].rect.minX < rect.maxX
                }), !images.indices.contains(where: {
                    $0 != image && images[$0].intersects(rect)
                }) else { continue }
                groups.append(Group(image: image, lines: caption, rect: rect))
            }
            // Repetition is the evidence: a single picture next to unrelated artwork does
            // not establish a gallery caption measure.
            guard groups.count == row.count else { continue }
            let band = groups.reduce(CGRect.null) { $0.union($1.rect) }
            let claimed = Set(groups.flatMap(\.lines))
            guard !lines.indices.contains(where: {
                !claimed.contains($0) && band.contains(CGPoint(x: lines[$0].rect.midX,
                                                              y: lines[$0].rect.midY))
            }) else { continue }
            // Shared upper edges establish the row. Different image/caption heights must not
            // make the shortest card's center sort ahead of its left-hand neighbors. Only the
            // reading footprint is extended through this verified empty part of the row.
            result += groups.map {
                Group(image: $0.image, lines: $0.lines,
                      rect: CGRect(x: $0.rect.minX, y: band.minY,
                                   width: $0.rect.width, height: band.height))
            }
        }
        return result
    }
}
