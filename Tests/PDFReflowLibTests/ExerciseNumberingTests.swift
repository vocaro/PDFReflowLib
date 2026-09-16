import Foundation
import Testing
@testable import PDFReflowLib

// Source-derived qualification of algebra exercise and answer-key numbering (#29). Fixtures are
// native extraction from the checksum-pinned Wallace book; expected numbers and values were read
// from the rendered source pages, not from converter output.

private let algebraSHA256 = "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678"
private let marker = try! NSRegularExpression(pattern: "^([0-9]+)\\)")

private func number(_ text: String) -> Int? {
    guard let match = marker.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let range = Range(match.range(at: 1), in: text) else { return nil }
    return Int(text[range])
}

private func reconstruct(_ name: String, regions: Bool = false) throws -> (PageContent, [ReflowBlock], [CGRect]) {
    let fixture = try SourceLayoutFixture.load(name)
    #expect(fixture.sourceSHA256 == algebraSHA256)
    var page = fixture.content()
    page.lines.removeAll { $0.text == String(fixture.page) }   // the folio the furniture pass removes
    let crops = regions ? LayoutReconstructor.graphicsWithLabels(page) : []
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: crops.enumerated().map { ($0.element, "image-\($0.offset)") },
        vocabulary: [], warnings: &warnings)
    return (page, blocks, crops)
}

private func numbered(_ blocks: [ReflowBlock]) -> [(Int, String, ReflowBlock.Content)] {
    blocks.compactMap { block in number(block.text).map { ($0, block.text, block.content) } }
}

private func isPreformatted(_ content: ReflowBlock.Content) -> Bool {
    if case .preformatted = content { return true } else { return false }
}

// Page 10, "0.1 Practice - Integers": 44 exercises in two columns, each its own block with its number.
@Test func integerExercisesKeepAllFortyFourNumbersAsSeparateBlocks() throws {
    let (_, blocks, _) = try reconstruct("algebra-10")
    let entries = numbered(blocks)
    #expect(entries.map(\.0).sorted() == Array(1...44))
    #expect(entries.allSatisfy { isPreformatted($0.2) })
    #expect(entries.allSatisfy { $0.1.filter { $0 == ")" }.count == $0.1.filter { $0 == "(" }.count + 1 })
    // Reviewed exercises keep their expressions.
    #expect(entries.contains { $0.1 == "1) 1− 3" })
    #expect(entries.contains { $0.1 == "31) (4)(− 1)" })
    #expect(entries.contains { $0.1 == "44) (− 3)(− 9)" })
    // Each column reads top to bottom; the instruction lines stay separate paragraphs in place.
    let texts = blocks.map(\.text)
    let odd = entries.map(\.0).filter { $0 % 2 == 1 }, even = entries.map(\.0).filter { $0 % 2 == 0 }
    #expect(odd == odd.sorted() && even == even.sorted())
    let product = try #require(texts.firstIndex(of: "Find each product."))
    #expect(texts.firstIndex(of: "29) (− 7) +7")! < product && product < texts.firstIndex(of: "31) (4)(− 1)")!)
    #expect(texts.contains("Evaluate each expression."))
}

// Page 438, "Answers - Chapter 0", 0.1: 60 answers in three columns. Negative answers extract as
// "1)− 2" with no space after the marker; they must not merge into one prose paragraph.
@Test func integerAnswerKeyKeepsSixtySeparateEntriesWithReviewedValues() throws {
    let (_, blocks, _) = try reconstruct("algebra-438", regions: true)
    let entries = numbered(blocks)
    #expect(entries.map(\.0).sorted() == Array(1...60))
    #expect(entries.allSatisfy { isPreformatted($0.2) })
    for expected in ["1)− 2", "2) 5", "5)− 6", "6)− 5", "14)− 9", "21)− 7", "22) 0", "42) 4", "43)− 20", "54)− 10", "60)− 9"] {
        #expect(entries.contains { $0.1 == expected }, "missing \(expected)")
    }
    #expect(!blocks.contains { $0.text.contains("5)− 6 6)− 5") })
    let columns = [entries.map(\.0).filter { $0 <= 21 }, entries.map(\.0).filter { (22...42).contains($0) },
                   entries.map(\.0).filter { $0 >= 43 }]
    #expect(columns.allSatisfy { $0 == $0.sorted() })
    // The 0.2 fraction answers below are preserved regions, so their numbers do not collide.
    #expect(blocks.contains { $0.text == "Answers - Integers" })
}

// Every exercise number on page 10 has exactly one answer entry on page 438, and reviewed pairs agree.
@Test func exerciseAndAnswerNumbersCorrespondOneToOne() throws {
    let exercises = numbered(try reconstruct("algebra-10").1)
    let answers = numbered(try reconstruct("algebra-438", regions: true).1)
    for n in 1...44 {
        #expect(exercises.filter { $0.0 == n }.count == 1)
        #expect(answers.filter { $0.0 == n }.count == 1)
    }
    let reviewed = [(1, "1) 1− 3", "1)− 2"), (2, "2) 4− (− 1)", "2) 5"), (13, "13) 6− 3", "13) 3"),
                    (31, "31) (4)(− 1)", "31)− 4"), (44, "44) (− 3)(− 9)", "44) 27")]
    for (n, exercise, answer) in reviewed {
        #expect(exercises.first { $0.0 == n }?.1 == exercise)
        #expect(answers.first { $0.0 == n }?.1 == answer)
    }
}

// A marker set tight against a minus sign is a list item; a period set tight against a word is not
// (dedented note continuations such as "5.This" keep their prose handling), and prose stays prose.
@Test func tightMinusMarkersAreListsButTightPeriodsAreNot() {
    func line(_ text: String, y: Double) -> TextLine {
        TextLine(text: text, rect: CGRect(x: 60, y: y, width: 200, height: 12), fontSize: 12)
    }
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 600, height: 800),
        lines: [line("3)− 14", y: 700), line("4)− 2", y: 686), line("5.This continues the note", y: 672),
                line("and ends here.", y: 658), line("2)(3) is a product", y: 644)], graphics: []),
        images: [], vocabulary: [], warnings: &warnings)
    #expect(blocks.map(\.text) == ["3)− 14", "4)− 2", "5.This continues the note and ends here. 2)(3) is a product"])
    #expect(blocks.prefix(2).allSatisfy { isPreformatted($0.content) })
}

// Page 291, "8.1 Practice - Square Roots": every radical exercise is preserved inside an image region
// with an explicit warning; no exercise number leaks out as a stray text fragment.
@Test func squareRootExercisesStayInsidePreservedRegionsWithoutStrayText() throws {
    let (page, blocks, crops) = try reconstruct("algebra-291", regions: true)
    let exercises = page.lines.filter { number($0.text) != nil }
    #expect(Set(exercises.compactMap { number($0.text) }) == Set(1...42))
    for line in exercises {
        #expect(crops.contains { $0.contains(line.rect) }, "uncropped \(line.text)")
    }
    #expect(numbered(blocks).isEmpty)
    #expect(blocks.contains { if case .image = $0.content { return true } else { return false } })
    #expect(blocks.contains { $0.text == "8.1 Practice - Square Roots" })
}

// Page 289: three worked square-root derivations stay preserved between their example labels while
// the surrounding prose reflows.
@Test func radicalDerivationsStayPreservedBetweenTheirExampleLabels() throws {
    let (page, blocks, crops) = try reconstruct("algebra-289", regions: true)
    for step in ["75 is divisible by 25, a perfect square", "63 is divisible by 9, a perfect square", "3 4 √ · 2"] {
        let line = try #require(page.lines.first { $0.text.contains(step) })
        #expect(crops.contains { $0.contains(line.rect) }, "uncropped \(step)")
    }
    let texts = blocks.map(\.text)
    let labels = ["Example 378.", "Example 379.", "Example 380."].compactMap { texts.firstIndex(of: $0) }
    #expect(labels.count == 3 && labels == labels.sorted())
    for index in labels {
        if case .image = blocks[index + 1].content {} else { Issue.record("no image after \(texts[index])") }
    }
    #expect(texts.contains { $0.contains("fastest method, is to find perfect squares that divide evenly into the radicand") })
    #expect(!texts.contains { $0.contains("Our Solution") })
}

// Page 471, "7.8 Answers - Dimensional Analysis": thirty text answers keep their numbers in column order.
@Test func dimensionalAnalysisAnswersKeepThirtyEntriesInColumnOrder() throws {
    let (_, blocks, _) = try reconstruct("algebra-471", regions: true)
    let expected = ["1) 12320 yd", "2) 0.0073125 T", "3) 0.0112 g", "4) 135,000 cm", "5) 6.1 mi", "6) 0.5 yd2",
                    "7) 0.435 km2", "8) 86,067,200 ft2", "9) 6,500,000 m3", "10) 239.58 cm3", "11) 0.0072 yd3",
                    "12) 5.13 ft/sec", "13) 6.31 mph", "14) 104.32 mi/hr", "15) 111 m/s",
                    "16) 2,623,269,600 km/yr", "17) 11.6 lb/in2", "18) 63,219.51 km/hr2", "19) 32.5 mph; 447 yd/oz",
                    "20) 6.608 mi/hr", "21)17280 pages/day; 103.4 reams/month", "22) 2,365,200,000 beats/lifetime",
                    "23) 1.28 g/L", "24) S3040", "25) 56 mph; 25 m/s", "26) 148.15 yd3; 113 m3",
                    "27) 3630 ft2, 522,720 in2", "28) 350,000 pages", "29) 15,603,840,000 ft3/week", "30) 621,200 mg; 1.42 lb"]
    let texts = blocks.map(\.text)
    let positions = expected.map { texts.firstIndex(of: $0) }
    #expect(!positions.contains(nil))
    let first = positions.prefix(15).compactMap { $0 }, second = positions.suffix(15).compactMap { $0 }
    #expect(first == first.sorted() && second == second.sorted())
    #expect(texts.contains("Answers - Dimensional Analysis"))
}
