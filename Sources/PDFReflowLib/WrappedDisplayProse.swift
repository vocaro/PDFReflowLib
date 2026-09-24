import CoreGraphics
import Foundation

/// A long display paragraph can exceed the ordinary body size without becoming a sequence
/// of navigation headings. Its own wrapped-row evidence applies locally, not to other titles.
enum WrappedDisplayProse {
    struct Group {
        var indices: Set<Int>
        var lines: [TextLine]
        var rect: CGRect { union(lines.map(\.rect)) }
    }

    static func groups(in lines: [TextLine], threshold: CGFloat) -> [Group] {
        PageTypography.wrappedProseRuns(lines, ceiling: .greatestFiniteMagnitude).compactMap { run in
            guard let first = run.first, first.fontSize >= threshold,
                  first.text.first?.isUppercase == true,
                  run.allSatisfy({ $0.structure == nil && !LayoutReconstructor.isList($0.text) }) else { return nil }
            let text = run.map(\.text).joined(separator: " ")
            // Two complete sentences separate this proof from a long multiline title.
            guard text.last.map({ ".!?".contains($0) }) == true,
                  text.matches(of: /[.!?](?:\s+[A-Z]|$)/).count >= 2 else { return nil }
            let indices = Set(lines.indices.filter { run.contains(lines[$0]) })
            // Coincident duplicate lines do not establish unique ownership of a paragraph.
            guard indices.count == run.count else { return nil }
            let rect = union(run.map(\.rect))
            // A local paragraph cannot swallow another reading unit, including retained tags.
            guard lines.indices.allSatisfy({ indices.contains($0) || !lines[$0].rect.intersects(rect) }) else { return nil }
            return Group(indices: indices, lines: run)
        }
    }
}
