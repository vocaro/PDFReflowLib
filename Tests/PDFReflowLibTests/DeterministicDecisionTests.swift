import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// #140: a decision read out of a Dictionary or a Set is made in an order that changes from process
// to process, so two runs of one binary can reconstruct a page differently. Every such decision
// must be a function of the page alone.

private func line(_ text: String, size: CGFloat, y: CGFloat) -> TextLine {
    TextLine(text: text, rect: CGRect(x: 72, y: y, width: CGFloat(text.count) * size * 0.5, height: size),
             fontSize: size)
}

/// A page whose two type sizes carry exactly the same number of characters.
private func tiedPage(smaller: CGFloat, larger: CGFloat) -> [TextLine] {
    let text = "Both sizes carry the same characters"
    return [line(text, size: smaller, y: 700), line(text, size: larger, y: 600)]
}

@Test func bodySizeBreaksACharacterCountTieTowardTheSmallerSize() {
    // Sixty-four ties, so a body size drawn from a dictionary's order cannot pass by chance.
    for step in 0..<64 {
        let smaller = CGFloat(6 + step % 8), larger = smaller + CGFloat(1 + step / 8)
        let lines = tiedPage(smaller: smaller, larger: larger)
        #expect(LayoutReconstructor.bodySize(lines) == smaller)
        #expect(LayoutReconstructor.bodySize(lines.reversed()) == smaller)
    }
}

@Test func bodySizeIsIndependentOfTheOrderOfTheLines() {
    var generator = SeededGenerator(seed: 140)
    let lines = tiedPage(smaller: 9, larger: 12)
        + [line("A third size with fewer characters", size: 18, y: 500)]
    let expected = LayoutReconstructor.bodySize(lines)
    #expect(expected == 9)
    for _ in 0..<100 {
        #expect(LayoutReconstructor.bodySize(lines.shuffled(using: &generator)) == expected)
    }
    // The size holding the most characters still wins; the tie rule decides only equal counts.
    let dominant = lines + [line("More text at twelve points than at nine", size: 12, y: 400)]
    #expect(LayoutReconstructor.bodySize(dominant) == 12)
}

@Test func atiedBodySizeGivesOnePageTheSameBlocksEveryTime() {
    // The tie decides the page's body size, and with it what reads as a heading (Warren page 384's
    // caption block used to come back as a heading in some runs and preformatted text in others).
    let lines = tiedPage(smaller: 9, larger: 12)
    let page = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792),
                           lines: lines, graphics: [])
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings)
    for _ in 0..<20 {
        var repeated: [ConversionWarning] = []
        let again = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &repeated)
        #expect(again.map { "\($0.content)" } == blocks.map { "\($0.content)" })
    }
    // The same page measured against the smaller size explicitly: the tie is not a third behaviour.
    let smaller = PageContent(number: 1, bounds: page.bounds,
                              lines: lines + [line("nine", size: 9, y: 500)], graphics: [])
    var extra: [ConversionWarning] = []
    let smallerBlocks = LayoutReconstructor.blocks(page: smaller, images: [], vocabulary: [], warnings: &extra)
    #expect(smallerBlocks.map { "\($0.content)" }.prefix(blocks.count) == blocks.map { "\($0.content)" }.prefix(blocks.count))
}

@Test func uncoveredTextRowsAreCollectedInPageOrder() {
    // The scan stops at a work bound, so the order rows are read in decides which ones are counted
    // on a pathological page. It must be the page's own order, not a dictionary's.
    var raster = OCRTextCoverage.GrayRaster(width: 400, height: 400, pixels: [UInt8](repeating: 255, count: 160_000))
    for row in 0..<8 {
        for glyph in 0..<10 {
            let x0 = 20 + glyph * 25, y0 = 20 + row * 40
            // Ten glyph-sized marks a row: 10 by 12 pixels notched like a C, so each is one
            // connected component of a letter's ink density rather than a filled block.
            for y in y0..<(y0 + 12) {
                for x in x0..<(x0 + 10) where !(3...9).contains(x - x0) || !(5...6).contains(y - y0) {
                    raster.pixels[y * 400 + x] = 0
                }
            }
        }
    }
    let measurement = OCRTextCoverage.measure(raster, lines: [], excluded: [], pixelsPerPoint: 2.5,
                                              collectBoxes: true, minimumGlyphs: 5)
    #expect(measurement.uncoveredRows == 8)
    let boxes = measurement.uncoveredRowBoxes
    #expect(boxes.count == 8)
    #expect(boxes == boxes.sorted { ($0.minY, $0.minX) < ($1.minY, $1.minX) })
    // Repeating the measurement of one raster gives one measurement.
    for _ in 0..<10 {
        #expect(OCRTextCoverage.measure(raster, lines: [], excluded: [], pixelsPerPoint: 2.5,
                                        collectBoxes: true, minimumGlyphs: 5) == measurement)
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state >> 11
    }
}
