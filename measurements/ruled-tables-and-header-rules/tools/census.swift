import Foundation
import PDFKit

// Census of the #65 header split: per page, the rule grid's column joints and every line PDFKit
// returns across a joint, split or kept whole. Compile from the repository root with the reader
// sources, as tools/capture-layout-fixture.swift is compiled (see census.sh).
@main struct SplitCensus {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { fatalError("usage: census <pdf>") }
        guard let document = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1])) else { fatalError("unreadable") }
        var pagesWithJoints = 0, crossing = 0, split = 0
        for index in 0..<document.pageCount {
            try autoreleasepool {
                guard let page = document.page(at: index), let reference = page.pageRef else { return }
                let graphics = GraphicsReader.read(reference)
                guard !graphics.unsupported, page.rotation % 360 == 0 else { return }
                let joints = GraphicsReader.columnJoints(graphics.paints.map(\.rect))
                guard !joints.isEmpty else { return }
                pagesWithJoints += 1
                let whole = try NativeTextReader.lines(on: page, limit: 1_000_000)
                let pieces = try NativeTextReader.lines(on: page, limit: 1_000_000, columnJoints: joints)
                let crossed = whole.filter { !NativeTextReader.crossedJoints($0, joints).isEmpty }
                crossing += crossed.count
                let splitLines = whole.filter { line in !pieces.contains { $0.text == line.text && $0.rect == line.rect } }
                split += splitLines.count
                print("page \(index + 1): joints \(joints.map { Int($0.x.rounded()) }); crossing \(crossed.count); split \(splitLines.count)")
                for line in splitLines {
                    let parts = pieces.filter { line.rect.insetBy(dx: -1, dy: -1).contains($0.rect) && !whole.contains($0) }
                    print("  split: \(line.text.debugDescription) -> \(parts.map(\.text))")
                }
                for line in crossed where !splitLines.contains(line) {
                    print("  whole: \(String(line.text.prefix(90)).debugDescription)")
                }
            }
        }
        print("pages with joints \(pagesWithJoints); lines crossing a joint \(crossing); split \(split)")
    }
}
