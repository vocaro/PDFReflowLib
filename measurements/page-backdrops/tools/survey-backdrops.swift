import Foundation
import PDFKit

// #164 survey: one TSV row per page whose painted regions cluster into a page-sized one. Repeats
// the pipeline's extraction up to the page-sized-graphic decision and reports what the page-sized
// paints are, whether the page paints only its backdrop, and what its crops take before and after
// the backdrops are set aside. Build with build-tool.sh and run from the repository root.
@main struct SurveyBackdrops {
    static func area(_ rect: CGRect) -> Double { Double(rect.width) * Double(rect.height) }

    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count >= 3 else { fatalError("usage: survey-backdrops <label> <pdf>") }
        let label = arguments[1]
        guard let document = PDFDocument(url: URL(fileURLWithPath: arguments[2])) else { fatalError("unreadable") }
        print("book\tpage\tlines\twords\tinvisible\tpageSizedPaints\tkinds\tbackdropOnly"
              + "\tbaseCrops\tbaseTakenWords\tbaseApart\tcandCrops\tcandTakenWords\tcandApart")
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i), let reference = page.pageRef else { continue }
            let bounds = page.bounds(for: .cropBox)
            let graphics = GraphicsReader.read(reference)
            guard !graphics.unsupported, page.rotation % 360 == 0,
                  graphics.regions.contains(where: { area($0) > area(bounds) * 0.75 }) else { continue }
            var content = PageContent(number: i + 1, bounds: bounds,
                lines: try NativeTextReader.lines(on: page, limit: 2_000_000, includeStyle: true,
                    columnJoints: GraphicsReader.columnJoints(graphics.paints.map(\.rect)),
                    borderlessTableInk: graphics.paints.map(\.rect),
                    glyphDecodings: [:], report: NativeTextReader.IndexGlyphReport()),
                graphics: graphics.regions)
            _ = HiddenTextFilter.removeHidden(&content.lines, graphics: graphics)
            let art = PDFReflowLibPipeline.artBesideBackdrops(graphics.paints, lines: content.lines, bounds: bounds)
            func outcome(_ paints: [GraphicsReader.Paint]) -> (crops: Int, taken: Int, apart: Bool) {
                var page = content
                page.graphics = TintDetector.compose(paints, lines: content.lines, bounds: bounds).graphics
                let measured = PDFReflowLibPipeline.cropOutcome(page)
                return (page.graphics.count, measured.taken,
                        PDFReflowLibPipeline.layoutComesApart(page, graphics: graphics))
            }
            let base = outcome(graphics.paints)
            let candidate = outcome(art ?? graphics.paints)
            let pageSized = graphics.paints.filter { area($0.rect) > area(bounds) * 0.75 }
            let kinds = Set(pageSized.map { $0.image ? "image" : ($0.filled ? "fill" : "outline") })
            print([label, "\(i + 1)", "\(content.lines.count)", "\(PDFReflowLibPipeline.cropOutcome(content).total)",
                   "\(graphics.hasInvisibleText)", "\(pageSized.count)", kinds.sorted().joined(separator: ","),
                   "\(art != nil)", "\(base.crops)", "\(base.taken)", "\(base.apart)",
                   "\(candidate.crops)", "\(candidate.taken)", "\(candidate.apart)"].joined(separator: "\t"))
        }
    }
}
