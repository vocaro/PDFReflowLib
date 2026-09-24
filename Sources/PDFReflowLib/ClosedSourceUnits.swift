import CoreGraphics
import Foundation

/// Source-painted containers retain their block boundaries when a paragraph crosses a page.
/// This evidence never releases text from a crop or changes the container's internal order.
enum ClosedSourceUnits {
    static func frames(paints: [GraphicsReader.Paint], bounds: CGRect) -> [CGRect] {
        guard paints.count <= 2_000 else { return [] }
        let segments = paints.filter { $0.strokeOnly == true && !$0.image && $0.vertices.count == 2 }
            .map { ($0.vertices[0], $0.vertices[1]) }
        guard segments.count <= 512 else { return [] }
        let horizontal = segments.filter { abs($0.0.y - $0.1.y) <= 0.05
            && abs($0.0.x - $0.1.x) >= bounds.width * 0.5 }
        let vertical = segments.filter { abs($0.0.x - $0.1.x) <= 0.05 }
        guard horizontal.count <= 64 else { return [] }
        func covers(x: CGFloat, lower: CGFloat, upper: CGFloat) -> Bool {
            let intervals = vertical.filter { abs($0.0.x - x) <= 1 }.map {
                (min($0.0.y, $0.1.y), max($0.0.y, $0.1.y))
            }.sorted { $0.0 < $1.0 }
            var end = lower
            for interval in intervals where interval.1 >= lower - 1 && interval.0 <= upper + 1 {
                guard interval.0 <= end + 1 else { return false }
                end = max(end, interval.1)
                if end >= upper - 1 { return true }
            }
            return false
        }
        var result: [CGRect] = []
        for top in horizontal {
            if Task.isCancelled { return [] }
            let left = min(top.0.x, top.1.x), right = max(top.0.x, top.1.x)
            for bottom in horizontal where top.0.y - bottom.0.y >= bounds.height * 0.1 {
                guard abs(min(bottom.0.x,bottom.1.x) - left) <= 1,
                      abs(max(bottom.0.x,bottom.1.x) - right) <= 1,
                      covers(x: left, lower: bottom.0.y, upper: top.0.y),
                      covers(x: right, lower: bottom.0.y, upper: top.0.y) else { continue }
                let frame = CGRect(x: left, y: bottom.0.y, width: right - left, height: top.0.y - bottom.0.y)
                guard bounds.insetBy(dx: -1,dy: -1).contains(frame) else { continue }
                if !result.contains(frame) { result.append(frame) }
            }
        }
        return result
    }

    static func ranges(_ elements: [LayoutReconstructor.Element], panels: [CGRect]) -> [Range<Int>] {
        guard elements.count <= 2_000, panels.count <= 128 else { return [] }
        var claimed: Set<Int> = [], result: [Range<Int>] = []
        for panel in panels.sorted(by: { $0.width * $0.height > $1.width * $1.height }) {
            if Task.isCancelled { return [] }
            let bounds = panel.insetBy(dx: -2,dy: -2)
            let members = elements.indices.filter { bounds.contains(elements[$0].rect) }
            guard let first = members.first, let last = members.last,
                  members.count == last - first + 1,
                  members.allSatisfy({ !claimed.contains($0) }) else { continue }
            // An overlapping outside element is not owned by this container. A retained tag
            // shared with outside prose likewise prevents closing the group at this boundary.
            let memberSet = Set(members)
            guard elements.indices.allSatisfy({ memberSet.contains($0)
                || !elements[$0].rect.intersects(panel.insetBy(dx: 1,dy: 1)) }) else { continue }
            func lines(_ element: LayoutReconstructor.Element) -> [TextLine] {
                if let line = element.line { return [line] }
                return element.nativePanel ?? element.caption ?? element.pictureCaption
                    ?? element.aside ?? element.quotation ?? []
            }
            let inside = members.flatMap { lines(elements[$0]) }
            guard inside.count >= 3, inside.reduce(0, { $0 + $1.text.count }) >= 100 else { continue }
            let tags = Set(inside.compactMap { $0.structure?.group })
            guard !elements.indices.contains(where: { !memberSet.contains($0)
                && lines(elements[$0]).contains { $0.structure.map { tags.contains($0.group) } == true } }) else { continue }
            let range = first..<last + 1
            result.append(range); claimed.formUnion(range)
        }
        return result.sorted { $0.lowerBound < $1.lowerBound }
    }
}
