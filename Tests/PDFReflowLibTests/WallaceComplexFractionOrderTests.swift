import Foundation
import Testing
@testable import PDFReflowLib

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/29"))
func wallaceComplexFractionPracticeReadsPairedRows() throws {
    let fixture = try SourceLayoutFixture.load("algebra-266")
    #expect(fixture.sourceSHA256 == "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678")
    let page = fixture.content()
    let markerElements = page.lines.filter { $0.text.range(of: #"^\d{1,2}\)"#, options: .regularExpression) != nil }
        .map { LayoutReconstructor.Element(rect: $0.rect, line: $0, image: nil) }
    var exhausted = false
    #expect(LayoutReconstructor.numberedExerciseRows(markerElements,
        body: LayoutReconstructor.bodySize(page.lines), rightToLeft: false,
        depth: 0, exhausted: &exhausted) != nil)
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page,
        images: crops.enumerated().map { ($0.element, "image-\($0.offset)") },
        vocabulary: [], warnings: &warnings)
    let markers = blocks.compactMap { block -> Int? in
        guard let range = block.text.range(of: #"^\d{1,2}(?=\))"#, options: .regularExpression) else { return nil }
        return Int(block.text[range])
    }
    let text = blocks.map(\.text)
    let title = try #require(text.firstIndex(of: "7.5 Practice - Complex Fractions"))
    let instruction = try #require(text.firstIndex(of: "Solve."))
    #expect(title < instruction)
    #expect(markers == Array(1...22))
    #expect(crops.count >= 18) // Complex stacked structures retain their source fallbacks.
    for number in 1...22 where number != 11 {
        let start = try #require(blocks.firstIndex { $0.text == "\(number))" })
        let end = number == 22 ? blocks.endIndex : try #require(blocks.firstIndex { $0.text == "\(number + 1))" })
        #expect(blocks[(start + 1)..<end].contains { if case .image = $0.content { true } else { false } },
                "Exercise \(number) must retain its own formula crop after its marker")
    }
}
