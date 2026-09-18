import Foundation

// usage: fixture <fixtures dir> <name> [all]
// Loads a source layout fixture the way the tests do (lines, graphics, paints) and prints the
// composed crops and the lines each takes.
@main struct FixtureTool {
    struct Fixture: Decodable {
        struct Line: Decodable {
            var text: String
            var rect: [CGFloat]
            var fontSize: CGFloat
            var monospaced: Bool?
            var wraps: Bool?
        }
        struct Paint: Decodable { var rect: [CGFloat]; var frame: Bool; var image: Bool?; var filled: Bool?; var grouped: Bool? }
        var bounds: [CGFloat]
        var page: Int?
        var lines: [Line]
        var graphics: [[CGFloat]]?
        var paints: [Paint]?
    }
    static func f(_ r: CGRect) -> String { String(format: "[%.1f %.1f %.1f %.1f]", r.minX, r.minY, r.maxX, r.maxY) }
    static func rect(_ v: [CGFloat]) -> CGRect { CGRect(x: v[0], y: v[1], width: v[2], height: v[3]) }
    static func main() throws {
        let args = CommandLine.arguments
        let url = URL(fileURLWithPath: args[1]).appendingPathComponent("\(args[2])-layout.json")
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        let bounds = rect(fixture.bounds)
        let lines = fixture.lines.map { line in
            TextLine(text: line.text, rect: rect(line.rect), fontSize: line.fontSize,
                     monospaced: line.monospaced ?? false, wraps: line.wraps ?? false)
        }
        var content = PageContent(number: fixture.page ?? 1, bounds: bounds, lines: lines,
                                  graphics: (fixture.graphics ?? []).map(rect))
        if var paints = fixture.paints {
            if let index = args.firstIndex(of: "dropFrameAt"), args.count > index + 1, let y = Double(args[index + 1]) {
                paints = paints.filter { !($0.frame && abs($0.rect[1] - CGFloat(y)) < 1) }
            }
            let composed = TintDetector.compose(paints.map {
                GraphicsReader.Paint(rect: rect($0.rect), frame: $0.frame, image: $0.image ?? false, filled: $0.filled ?? false, grouped: $0.grouped ?? false)
            }, lines: lines, bounds: bounds)
            content.graphics = composed.graphics
            content.tints = composed.tints
            content.separators = composed.separators
            print("paints \(paints.count), composed \(composed.graphics.count), tints \(composed.tints.count)")
            for r in composed.graphics { print("  seed", f(r)) }
            for r in composed.tints { print("  tint", f(r)) }
        }
        let crops = LayoutReconstructor.graphicsWithLabels(content)
        print("crops:")
        for c in crops {
            let taken = lines.filter { c.intersects($0.rect) }
            print("  ", f(c), "takes \(taken.count) lines")
            for l in taken.prefix(args.contains("all") ? 200 : 6) { print("      ", f(l.rect), l.text.prefix(60)) }
        }
        let bt = TintDetector.blockText(lines)
        print("blockText \(bt.count) of \(lines.count)")
    }
}
