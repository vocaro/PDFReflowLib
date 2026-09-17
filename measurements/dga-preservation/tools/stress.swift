import Foundation
import CoreGraphics

// The stress page of `vectorDensePagesStayBoundedAndKeepTheirClustering`, scaled: n filled marks
// overlapping in rows plus a title band, and m isolated strokes; times compose and seedClusters.
@main struct Stress {
    static func main() {
        var lines = [TextLine(text: "Consume Dairy Every Day", rect: CGRect(x: 114, y: 160, width: 108, height: 24), fontSize: 18)]
        lines += (0..<6).map {
            TextLine(text: "Body prose that sets the ordinary size of this page \($0)", rect: CGRect(x: 60, y: 20 + CGFloat($0) * 16, width: 480, height: 13), fontSize: 10)
        }
        let page = CGRect(x: 0, y: 0, width: 600, height: 800)
        for (rows, columns) in [(15, 67), (30, 67), (60, 67), (90, 110)] {
            var paints: [GraphicsReader.Paint] = []
            for row in 0..<rows {
                for column in 0..<columns {
                    paints.append(GraphicsReader.Paint(rect: CGRect(x: CGFloat(column) * 600 / CGFloat(columns), y: 230 + CGFloat(row) * 540 / CGFloat(rows), width: 10, height: 10), frame: false, filled: true))
                }
            }
            paints.append(GraphicsReader.Paint(rect: CGRect(x: 100.4, y: 155, width: 477.9, height: 32.7), frame: false, filled: true))
            let start = Date()
            _ = TintDetector.compose(paints, lines: lines, bounds: page)
            print(String(format: "marks %5d compose %.3fs", paints.count, Date().timeIntervalSince(start)))
        }
        for (rows, columns) in [(24, 25), (48, 50), (96, 100)] {
            var strokes: [CGRect] = []
            for row in 0..<rows {
                for column in 0..<columns {
                    strokes.append(CGRect(x: CGFloat(column) * 600 / CGFloat(columns), y: 220 + CGFloat(row) * 560 / CGFloat(rows), width: 2, height: 3))
                }
            }
            let start = Date()
            _ = TintDetector.seedClusters(strokes, lines: lines)
            let t1 = Date().timeIntervalSince(start)
            let plain = Date()
            _ = clusters(strokes, distance: 4)
            print(String(format: "strokes %5d seedClusters %.3fs (clusters alone %.3fs)", strokes.count, t1, Date().timeIntervalSince(plain)))
        }
    }
}
