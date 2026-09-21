import Foundation
import PDFKit

// Diagnostic only: prints, for each named page, the native lines PDFKit returns, the crops
// `graphicsWithLabels` forms, which lines those crops take, and the blocks reconstruction
// makes of the page. No converter output, no rasters.
//
//     dump-page corpus/cache/GPO-911REPORT.pdf 448 /tmp/p448.json
@main struct DumpPage {
    static func main() throws {
        let path = CommandLine.arguments[1]
        let pageNumbers = CommandLine.arguments[2].split(separator: ",").map { Int($0)! }
        let output = CommandLine.arguments[3]
        guard let document = PDFDocument(url: URL(fileURLWithPath: path)) else { fatalError("no document") }
        func r(_ x: CGRect) -> [Double] { [x.minX, x.minY, x.width, x.height].map { Double($0) } }
        var weights: [Int: Int] = [:]
        let bodyPages = ProcessInfo.processInfo.environment["DUMP_BODY_PAGES"].flatMap { Int($0) } ?? document.pageCount
        for index in 0..<min(bodyPages, document.pageCount) {
            let page = document.page(at: index)!
            LayoutReconstructor.addBodyWeights(of: try NativeTextReader.lines(on: page, limit: 100_000), to: &weights)
        }
        let documentBody = LayoutReconstructor.bodySize(weights: weights)
        var contents: [PageContent] = []
        for number in pageNumbers {
            let page = document.page(at: number - 1)!
            let graphics = GraphicsReader.read(page.pageRef!)
            contents.append(PageContent(number: number, bounds: page.bounds(for: .cropBox),
                                        lines: try NativeTextReader.lines(on: page, limit: 100_000),
                                        graphics: graphics.regions, pictures: graphics.images))
        }
        let vocabulary = LayoutReconstructor.vocabulary(in: contents)
        var out: [[String: Any]] = []
        for content in contents {
            let crops = LayoutReconstructor.graphicsWithLabels(content)
            let overPicture = PageDiagnosis.proseOverPictures(lines: content.lines, pictures: content.pictures,
                                                             crops: crops, bounds: content.bounds, language: "en")
            var warnings: [ConversionWarning] = []
            let blocks = LayoutReconstructor.blocks(page: content, images: crops.map { ($0, "crop") },
                                                    vocabulary: vocabulary, warnings: &warnings,
                                                    documentBody: documentBody)
            let reflowable = content.lines.enumerated().filter { index, line in
                overPicture.contains(index) || !crops.contains { $0.intersects(line.rect) }
            }.map(\.element)
            let typography = PageTypography(pageLines: content.lines, reflowableLines: reflowable,
                                            documentBody: documentBody)
            let body = max(4, LayoutReconstructor.bodySize(content.lines))
            let headers = TableRegionDetector.columnHeaders(in: content, body: body)
            var record: [String: Any] = [:]
            record["page"] = content.number
            record["bounds"] = r(content.bounds)
            record["body"] = Double(typography.body)
            record["documentBody"] = documentBody.map { Double($0) } ?? -1
            record["crops"] = crops.map(r)
            record["pictures"] = content.pictures.map(r)
            record["graphics"] = content.graphics.map(r)
            record["tableRegions"] = TableRegionDetector.regions(in: content).map(r)
            record["underlinedColumns"] = TableRegionDetector.underlinedColumnRegions(in: content).map(r)
            record["columnHeaders"] = headers.map(r)
            record["fractionRegions"] = FractionRegionDetector.regions(in: content, body: body).map(r)
            var lineRecords: [[String: Any]] = []
            for (index, line) in content.lines.enumerated() {
                let buried = !overPicture.contains(index) && crops.contains { crop in
                    LayoutReconstructor.takes(crop, line)
                        && !LayoutReconstructor.reachesInto(crop, line, among: content.lines,
                                                            pictures: content.pictures,
                                                            bounds: content.bounds, columnHeaders: headers)
                }
                var entry: [String: Any] = [:]
                entry["text"] = line.text
                entry["rect"] = r(line.rect)
                entry["size"] = Double(line.fontSize)
                entry["mono"] = line.monospaced
                entry["buried"] = buried
                entry["overPicture"] = overPicture.contains(index)
                lineRecords.append(entry)
            }
            record["lines"] = lineRecords
            var blockRecords: [[String: Any]] = []
            for block in blocks {
                let kind: String
                switch block.content {
                case .paragraph: kind = "paragraph"
                case .heading: kind = "heading"
                case .preformatted: kind = "pre"
                case .image: kind = "image"
                case .sourcePage: kind = "sourcePage"
                }
                var entry: [String: Any] = [:]
                entry["kind"] = kind
                entry["text"] = block.text
                blockRecords.append(entry)
            }
            record["blocks"] = blockRecords
            record["warnings"] = warnings.map { "\($0)" }
            out.append(record)
        }
        try JSONSerialization.data(withJSONObject: ["pages": out],
                                   options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            .write(to: URL(fileURLWithPath: output))
    }
}
