import Foundation
import Testing
@testable import PDFReflowLib

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/29"))
func wallaceAnswerKeyPage438IsNotMistakenForThreeTables() throws {
    let fixture = try SourceLayoutFixture.load("algebra-438")
    #expect(fixture.sourceSHA256 == "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678")
    let source = URL(fileURLWithPath: "corpus/cache/Beginning_and_Intermediate_Algebra.pdf")
    let document = try PDFPageSource(url: source)
    let content = try PageReader.read(pageIndex: 437, from: document, limit: 100_000,
                                      options: ConversionOptions(), structure: nil).content
    #expect(content.tables.isEmpty)
    let crops = LayoutReconstructor.graphicsWithLabels(content)
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: content,
        images: crops.enumerated().map { ($0.element, "image-\($0.offset)") },
        vocabulary: [], warnings: &warnings)
    #expect(blocks.filter { if case .table = $0.content { true } else { false } }.isEmpty)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/29"))
func numberedRowsNeedAnswerHeadingAndDownColumnRangesBeforeTableIsRefused() {
    let rows = [[1, 22, 43], [2, 23, 44], [3, 24, 45]].map { values in
        values.map { PageTable.Cell(content: InlineText("\($0) answer"), rect: .zero) }
    }
    let table = PageTable(rect: .zero, rows: rows)
    let heading = TextLine(text: "Answers - Integers", rect: .zero, fontSize: 12)
    #expect(!TableReader.numberedAnswerKey(table, on: [heading]))
    let marked = PageTable(rect: .zero, rows: rows.map { row in row.map { cell in
        .init(content: InlineText(cell.text.replacingOccurrences(of: " answer", with: ") answer")), rect: .zero)
    } })
    #expect(TableReader.numberedAnswerKey(marked, on: [heading]))
    #expect(!TableReader.numberedAnswerKey(marked, on: []))
    let across = PageTable(rect: .zero, rows: [[1, 2, 3], [4, 5, 6], [7, 8, 9]].map { values in
        values.map { PageTable.Cell(content: InlineText("\($0)) answer"), rect: .zero) }
    })
    #expect(!TableReader.numberedAnswerKey(across, on: [heading]))
}
