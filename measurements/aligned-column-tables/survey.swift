// Survey for #150/#137: every table of aligned columns the library reads in a PDF.
//
// Each page is extracted as the pipeline extracts it (glyph-index decoding, column-joint,
// borderless and aligned-column splits), then `ColumnGrid` reads the lines as layout does
// (`BorderlessTableDetector.alignedTables` is this, less its tag checks). One record per table:
// page, columns, rows, then its first rows as cells.
//
// Build (from the repository root):
//   swiftc -O Sources/PDFReflowLib/NativeTextReader.swift Sources/PDFReflowLib/ConversionTypes.swift \
//     Sources/PDFReflowLib/DocumentModel.swift Sources/PDFReflowLib/ReflowDocument.swift \
//     Sources/PDFReflowLib/GraphicsReader.swift Sources/PDFReflowLib/NativeSpacingReader.swift \
//     Sources/PDFReflowLib/StructureTreeReader.swift Sources/PDFReflowLib/MarkedTextReader.swift \
//     Sources/PDFReflowLib/FontWeightReader.swift Sources/PDFReflowLib/PrivateUseDecoder.swift \
//     Sources/PDFReflowLib/GlyphIndexDecoder.swift Sources/PDFReflowLib/TextEncodingCheck.swift \
//     Sources/PDFReflowLib/ColumnGrid.swift measurements/aligned-column-tables/survey.swift \
//     -module-name survey -parse-as-library -o <scratch>/survey
// Run:
//   <scratch>/survey corpus/cache/<file>.pdf [rows] > measurements/aligned-column-tables/survey/<case>.txt
import Foundation
import PDFKit

@main
struct Survey {
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count >= 2 else { fatalError("usage: survey <pdf> [rows]") }
        let url = URL(fileURLWithPath: arguments[1])
        let shown = arguments.count >= 3 ? Int(arguments[2]) ?? 4 : 4
        guard let document = PDFDocument(url: url) else { fatalError("unreadable PDF") }
        let decodings = try GlyphIndexDecoder.read(url, language: "en")
        var count = 0
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index), let reference = page.pageRef else { continue }
            let graphics = GraphicsReader.read(reference)
            let lines = try NativeTextReader.lines(on: page, limit: 100_000,
                columnJoints: GraphicsReader.columnJoints(graphics.paints.map(\.rect)),
                borderlessTableInk: graphics.paints.map(\.rect), glyphDecodings: decodings)
            let usable = lines.filter { !$0.monospaced }
            let pieces = usable.enumerated().map {
                ColumnGrid.Piece(rect: $0.element.rect, text: $0.element.text, size: $0.element.fontSize, id: $0.offset)
            }
            for region in ColumnGrid.regions(in: pieces, capped: true) {
                for grid in ColumnGrid.grids(in: region.rows, beside: region.beside) {
                    count += 1
                    var cells = [[String]](repeating: [String](repeating: "", count: grid.columns), count: grid.rows)
                    for (baseline, placements) in grid.placements.enumerated() {
                        for (position, placement) in placements.enumerated() {
                            guard let placement else { continue }
                            let text = region.rows[baseline][position].text
                            let column = placement.columns.lowerBound
                            cells[placement.row][column] += (cells[placement.row][column].isEmpty ? "" : " ") + text
                                + (placement.columns.count > 1 ? " {\(placement.columns.count)}" : "")
                        }
                    }
                    print("page \(index + 1)\tcolumns \(grid.columns)\theaderRows \(grid.headerRows)\trows \(grid.rows)")
                    for (row, values) in cells.prefix(grid.headerRows + shown).enumerated() {
                        print("    " + (row < grid.headerRows ? "H " : "  ") + values.joined(separator: " | "))
                    }
                }
            }
        }
        print("tables \(count)")
    }
}
