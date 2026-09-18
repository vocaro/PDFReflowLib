import Foundation
import PDFKit

@main struct Probe {
    static func f(_ r: CGRect) -> String { String(format: "[%.1f %.1f %.1f %.1f]", r.minX, r.minY, r.maxX, r.maxY) }
    static func line(_ text: String, x: CGFloat, baseline: CGFloat, width: CGFloat, size: CGFloat = 9) -> TextLine {
        TextLine(text: text, rect: CGRect(x: x, y: baseline - 2.5, width: width, height: size * 1.25), fontSize: size)
    }
    static func column(x: CGFloat, top: CGFloat, width: CGFloat = 200, count: Int = 6, size: CGFloat = 9) -> [TextLine] {
        (0..<count).map {
            line("agriculture is exposed to negative influences from nature \($0)",
                 x: x, baseline: top - CGFloat($0) * (size * 1.4), width: width, size: size)
        }
    }
    static func paint(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, frame: Bool = false, image: Bool = false, filled: Bool = false) -> GraphicsReader.Paint {
        GraphicsReader.Paint(rect: CGRect(x: x, y: y, width: w, height: h), frame: frame, image: image, filled: filled)
    }
    static func main() {
        let background = paint(36, 54, 540, 165, image: true)
        do {
            let rect = background.rect
            let columns = column(x: 40, top: 210, width: 160) + column(x: 240, top: 210, width: 160)
            let body = max(4, LayoutReconstructor.bodySize(columns))
            let meeting = columns.filter { $0.rect.intersects(rect) }
            let inside = meeting.filter { l in let o = l.rect.intersection(rect); return !o.isNull && o.width * o.height >= l.rect.width * l.rect.height * 0.5 }
            let prose = inside.filter { !$0.monospaced && $0.fontSize >= body * 0.9 && $0.text.split(whereSeparator: { !$0.isLetter }).filter { $0.count >= 2 }.count >= 4 }
            print("meeting", meeting.count, "inside", inside.count, "prose", prose.count, "zone", f(union(inside.map(\.rect))), "rect", f(rect))
        }
        let columns = column(x: 40, top: 210, width: 160) + column(x: 240, top: 210, width: 160)
        print("body", LayoutReconstructor.bodySize(columns))
        print("background ->", TintDetector.withoutTextBackdrops([background], lines: columns).map { f($0.rect) })
        let tall = paint(36, 54, 540, 280, image: true)
        let running = columns + column(x: 40, top: 400, width: 160) + column(x: 240, top: 400, width: 160)
        print("tall ->", TintDetector.withoutTextBackdrops([tall], lines: running).map { f($0.rect) })
        let photograph = paint(288, 329, 288, 427, image: true)
        let title = [line("Finding Ways To Save", x: 34, baseline: 730, width: 268, size: 23.5),
                     line("Water in Peach Orchards", x: 34, baseline: 700, width: 308, size: 23.5)]
        let body = column(x: 36, top: 640, width: 234, count: 8, size: 10.5)
        print("title body", LayoutReconstructor.bodySize(title + body))
        print("photo ->", TintDetector.withoutTextBackdrops([photograph], lines: title + body).map { f($0.rect) })
        let band = paint(311, 334, 239, 43, frame: true, filled: true)
        let caption = (0..<3).map { line("Agricultural engineer Huihui Zhang measures peach tree leaf \($0)",
                                         x: 324, baseline: 370 - CGFloat($0) * 10, width: 213, size: 7.9) }
        print("band ->", TintDetector.withoutTextBackdrops([photograph, band], lines: caption + body).map { f($0.rect) })
        let swatch = paint(315, 340, 10, 10, filled: true)
        print("legend ->", TintDetector.withoutTextBackdrops([photograph, band, swatch], lines: caption + body).map { f($0.rect) })
        let over = paint(36, 54, 360, 440, image: true)
        let beside = column(x: 404, top: 210, width: 170)
        print("over ->", TintDetector.withoutTextBackdrops([background, over], lines: beside).map { f($0.rect) })
    }
}
