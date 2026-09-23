import Foundation

/// A bounded path replay that recognizes only a rectangle with short rounded corners.
/// Curves must stay in a corner's small square; straight edges must follow the outer sides.
/// A cloud silhouette, ellipse or labeled illustration is not a text panel.
struct PanelOutline {
    private var start: CGPoint?
    private var segments: [[CGPoint]] = []
    private var valid = true

    mutating func move(_ point: CGPoint) {
        if start != nil { valid = false }
        start = point
    }
    mutating func append(_ points: [CGPoint]) {
        guard valid, start != nil, segments.count < 16 else { valid = false; return }
        segments.append(points)
    }
    mutating func invalidate() { valid = false }

    var isRoundedRectangle: Bool {
        guard valid, let start, (4...8).contains(segments.filter { $0.count == 3 }.count) else { return false }
        let points = [start] + segments.flatMap { $0 }
        let box = points.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
        let radius = min(box.width, box.height) * 0.15
        guard radius > 0 else { return false }
        let corners = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                       CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)]
        var seen: Set<Int> = []
        func onSide(_ a: CGPoint, _ b: CGPoint) -> Bool {
            [box.minX, box.maxX].contains { abs(a.x - $0) < 0.05 && abs(b.x - $0) < 0.05 }
                || [box.minY, box.maxY].contains { abs(a.y - $0) < 0.05 && abs(b.y - $0) < 0.05 }
        }
        var last = start
        for segment in segments + [[start]] {
            if segment.count == 1 {
                guard segment[0] == last || onSide(last, segment[0]) else { return false }
            } else {
                guard let corner = corners.indices.first(where: { index in
                    ([last] + segment).allSatisfy {
                        abs($0.x - corners[index].x) <= radius && abs($0.y - corners[index].y) <= radius
                    }
                }) else { return false }
                seen.insert(corner)
            }
            last = segment.last!
        }
        return seen.count == 4
    }
}
