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
func wallaceIntegerAnswersStayBeneathTheirHeadingAndMatchExercises() throws {
    let fixture = try SourceLayoutFixture.load("algebra-438")
    #expect(fixture.sourceSHA256 == "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678")
    let page = fixture.content()
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page,
        images: crops.enumerated().map { ($0.element, "image-\($0.offset)") },
        vocabulary: [], warnings: &warnings)
    let text = blocks.map(\.text)
    let chapter = try #require(text.firstIndex(of: "Answers - Chapter 0"))
    let section = try #require(text.firstIndex(of: "0.1"))
    let title = try #require(text.firstIndex(of: "Answers - Integers"))
    let next = try #require(text.firstIndex(of: "0.2"))
    let fractionTitle = try #require(text.firstIndex(of: "Answers - Fractions"))
    #expect(chapter < section && section < title && title < next)
    #expect(next < fractionTitle)
    if next < fractionTitle {
        #expect(!blocks[(next + 1)..<fractionTitle].contains { if case .image = $0.content { true } else { false } })
    }
    guard title < next else { return }
    let answerText = text[(title + 1)..<next].joined(separator: " ")
    let pattern = try NSRegularExpression(pattern: #"(\d{1,2})\)\s*([−-]?\s*\d+)"#)
    let matches = pattern.matches(in: answerText, range: NSRange(answerText.startIndex..<answerText.endIndex,
                                                                 in: answerText))
    let answers = matches.compactMap { match -> (Int, Int)? in
        guard let key = Range(match.range(at: 1), in: answerText),
              let value = Range(match.range(at: 2), in: answerText),
              let number = Int(answerText[key]),
              let answer = Int(answerText[value].replacingOccurrences(of: "−", with: "-")
                .replacingOccurrences(of: " ", with: "")) else { return nil }
        return (number, answer)
    }
    let printed = [-2, 5, 2, 2, -6, -5, 8, 0, -2, -5, 4, -7, 3, -9, -2, -9, -1, -2, -3, 2, -7,
                   0, 11, 9, -3, -4, -3, 4, 0, -8, -4, -35, -80, 14, 8, 6, -56, -6, -36,
                   63, -10, 4, -20, 27, -24, -3, 7, 3, 2, 5, 2, 9, 7, -10, 4, 10, -8, 6, -6, -9]
    #expect(answers.map(\.0) == Array(1...60))
    #expect(answers.map(\.1) == printed)
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
