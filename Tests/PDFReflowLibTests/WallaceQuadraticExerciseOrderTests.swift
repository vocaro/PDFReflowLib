import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/29"))
func wallaceQuadraticMathRowsFollowPrintedPairs() throws {
    let fixture = try SourceLayoutFixture.load("algebra-347")
    #expect(fixture.sourceSHA256 == "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678")
    #expect(fixture.page == 347)
    let page = fixture.content()
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    #expect(crops.count == 2)
    let document = try #require(PDFDocument(url: URL(fileURLWithPath:
        "corpus/cache/Beginning_and_Intermediate_Algebra.pdf")))
    let reference = try #require(document.page(at: 346)?.pageRef)
    let glyphs = try NativeTextReader.withExtractionLock { MathRecognizer.glyphs(on: reference) }
    let body = LayoutReconstructor.bodySize(page.lines)
    let rows = crops.flatMap { crop in
        MathRecognizer.rows(in: crop, page: glyphs, graphics: page.graphics,
                            lines: page.lines, body: body) ?? []
    }
    #expect(rows.count == 40)
    let columns = crops.compactMap { crop in
        MathRecognizer.rows(in: crop, page: glyphs, graphics: page.graphics,
                            lines: page.lines, body: body)
    }
    #expect(columns.count == 2)
    #expect(columns.allSatisfy { MathRecognizer.pairedExerciseColumn($0, body: body) })
    var noPair = columns[0]
    noPair[1].label = "2)"
    #expect(!MathRecognizer.pairedExerciseColumn(noPair, body: body))
    #expect(!MathRecognizer.pairedExerciseColumn(Array(columns[0].prefix(2)), body: body))
    noPair = columns[0]
    noPair[1].note = "Worked step"
    #expect(!MathRecognizer.pairedExerciseColumn(noPair, body: body))
    let numbers = rows.compactMap { Int($0.label?.dropLast() ?? "") }
    #expect(Set(numbers) == Set(1...40))
    let images = rows.compactMap { row -> (CGRect, String)? in
        guard let number = Int(row.label?.dropLast() ?? "") else { return nil }
        return (row.rect, "equation-\(number)")
    }
    #expect(images.count == 40)
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: images, vocabulary: [], warnings: &warnings)
    let ordered = blocks.compactMap { block -> Int? in
        guard case let .image(image) = block.content else { return nil }
        return Int(image.assetID.replacingOccurrences(of: "equation-", with: ""))
    }
    #expect(ordered == Array(1...40))
}
