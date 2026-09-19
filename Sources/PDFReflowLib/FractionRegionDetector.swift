import Foundation

/// Preserve spatial fractions around short painted bars. This does not transcribe mathematics.
enum FractionRegionDetector {
    static func regions(in page: PageContent, body: CGFloat? = nil) -> [CGRect] {
        let body = body ?? max(4, LayoutReconstructor.bodySize(page.lines))
        func term(_ line: TextLine) -> Bool {
            guard !line.monospaced, line.text.count <= 60,
                  line.text.range(of: #"[A-Za-z]{3,}"#, options: .regularExpression) == nil else { return false }
            let allowed = CharacterSet(charactersIn: "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ+-−×÷/().,²³⁴⁵⁶⁷⁸⁹⁰√ ")
            return !line.text.isEmpty && line.text.unicodeScalars.allSatisfy(allowed.contains)
        }
        return page.graphics.compactMap { bar in
            // GraphicsReader adds two points around painted paths. Long rules and connected
            // table grids supply no evidence for a standalone fraction.
            guard bar.height <= max(5, body * 0.5), bar.width >= 6,
                  bar.width <= body * 16, bar.width > bar.height * 1.5 else { return nil }
            let nearby = page.lines.filter { line in
                term(line) && line.rect.minX >= bar.minX - body * 0.3
                    && line.rect.maxX <= bar.maxX + body * 0.3
                    && line.rect.width >= bar.width * 0.15
            }
            let above = nearby.filter {
                $0.rect.midY > bar.midY && $0.rect.minY >= bar.minY
                    && $0.rect.minY - bar.maxY <= body * 1.2
            }.min { $0.rect.minY < $1.rect.minY }
            let below = nearby.filter {
                $0.rect.midY < bar.midY && $0.rect.maxY <= bar.maxY
                    && bar.minY - $0.rect.maxY <= body * 1.2
            }.max { $0.rect.maxY < $1.rect.maxY }
            guard let above, let below else { return nil }
            var region = bar.union(above.rect).union(below.rect)
            // A nearby equation prefix can be separated from the bar by ordinary math spacing.
            // Keep it in the same source image rather than emitting two equation fragments.
            if let prefix = page.lines.filter({ line in
                !line.monospaced && line.text.hasSuffix("=") && line.text.count < 40
                    && line.rect.maxX < bar.minX && bar.minX - line.rect.maxX <= body * 5
                    && abs(line.rect.midY - bar.midY) <= body
            }).max(by: { $0.rect.maxX < $1.rect.maxX }) {
                region = region.union(prefix.rect)
            }
            // Whole-line expansion supplies text margins once. Growing an already padded bar
            // again can capture unrelated prose beside a complete fraction.
            return region.intersection(page.bounds)
        }
    }
}
