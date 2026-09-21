import Foundation
import PDFKit

// Diagnostic only: prints the elements one page hands `LayoutReconstructor.ordered`, in the
// order it returns them. No converter output, no crops, no rasters. Build it beside the library
// files it calls (the record gives the command) and run it from the repository root:
//
//     dump-order corpus/cache/November-December2012.pdf 6,17 /tmp/order.json
@main struct DumpOrder {
    static func main() throws {
        let path = CommandLine.arguments[1]
        let pageNumbers = CommandLine.arguments[2].split(separator: ",").map { Int($0)! }
        guard let document = PDFDocument(url: URL(fileURLWithPath: path)) else { fatalError("no document") }
        func r(_ x: CGRect) -> [Double] { [x.minX, x.minY, x.width, x.height].map { Double($0) } }
        // The document body, over every native page, as the pipeline computes it.
        var weights: [Int: Int] = [:]
        for index in 0..<document.pageCount {
            let page = document.page(at: index)!
            LayoutReconstructor.addBodyWeights(of: try NativeTextReader.lines(on: page, limit: 100_000), to: &weights)
        }
        let documentBody = LayoutReconstructor.bodySize(weights: weights)
        var out: [[String: Any]] = []
        for number in pageNumbers {
            let page = document.page(at: number - 1)!
            let graphics = GraphicsReader.read(page.pageRef!)
            let content = PageContent(number: number, bounds: page.bounds(for: .cropBox),
                                      lines: try NativeTextReader.lines(on: page, limit: 100_000),
                                      graphics: graphics.regions, pictures: graphics.images)
            let crops = LayoutReconstructor.graphicsWithLabels(content)
            let overPicture = PageDiagnosis.proseOverPictures(lines: content.lines, pictures: content.pictures,
                                                             crops: crops, bounds: content.bounds, language: "en")
            let lines = content.lines.enumerated().filter { index, line in
                overPicture.contains(index) || !crops.contains { $0.intersects(line.rect) }
            }.map(\.element)
            let typography = PageTypography(pageLines: content.lines, reflowableLines: lines,
                                            documentBody: documentBody)
            let elements = lines.map { LayoutReconstructor.Element(rect: $0.readingRect ?? $0.rect, line: $0) }
                + crops.map { LayoutReconstructor.Element(rect: $0, image: "crop") }
            var exhausted = false
            let ordered = LayoutReconstructor.ordered(elements, bodySize: typography.body, exhausted: &exhausted)
            out.append(["page": number, "bounds": r(content.bounds), "body": Double(typography.body),
                        "documentBody": documentBody.map { Double($0) } ?? -1, "exhausted": exhausted,
                        "crops": crops.map(r),
                        "elements": ordered.map { ["rect": r($0.rect), "text": $0.line?.text ?? "<image>"] }])
        }
        try JSONSerialization.data(withJSONObject: ["pages": out],
                                   options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            .write(to: URL(fileURLWithPath: CommandLine.arguments[3]))
    }
}
