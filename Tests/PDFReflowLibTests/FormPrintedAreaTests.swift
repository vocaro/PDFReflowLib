import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/211"))
func federalClaimsPrintedWritingLinesAndEmptyCells() throws {
    let source = try SourceLayoutFixture.load("uscfc-6b-211-no-widget")
    #expect(source.sourceSHA256 == "69adaf6fa1306ed6a5ed1d58e9f598bdb642ea4a12c6bc22f24dd202f2097a05")
    let page = source.content()
    let writing = PrintedFormAreas.normalizedWritingLines(page.lines)
    #expect(writing.filter { $0.text == FormBlank.text }.count == 5)
    #expect(writing.contains { $0.text == "To: ______________________________" })
    let box = try #require(PrintedFormAreas.emptyBox(regions: page.graphics,
        paints: source.paints.map(\.rect), lines: page.lines, bounds: page.bounds))
    #expect(box.rows.map(\.text) == ["Place: ____", "Date and Time: ____"])
    #expect(box.region.width > 470 && box.region.height > 39)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/211"))
func printedAnswerCellsNeedIndependentFormAndEmptyInteriorEvidence() throws {
    let source = try SourceLayoutFixture.load("uscfc-6b-211-no-widget")
    let page = source.content()
    let stack = page.lines.filter { $0.text.allSatisfy { $0 == "_" } && $0.text.count > 20 }
    let labels = page.lines.filter { $0.text == "Place:" || $0.text == "Date and Time:" }
    let other = page.lines.filter { !stack.contains($0) && !labels.contains($0) }
    #expect(PrintedFormAreas.emptyBox(regions: page.graphics, paints: source.paints.map(\.rect),
        lines: other + labels, bounds: page.bounds) == nil)
    let filled = TextLine(text: "Filled value", rect: CGRect(x: 100, y: 392, width: 80, height: 12), fontSize: 10)
    #expect(PrintedFormAreas.emptyBox(regions: page.graphics, paints: source.paints.map(\.rect),
        lines: page.lines + [filled], bounds: page.bounds) == nil)
    let drawnValue = CGRect(x: 100, y: 392, width: 40, height: 3)
    #expect(PrintedFormAreas.emptyBox(regions: page.graphics,
        paints: source.paints.map(\.rect) + [drawnValue],
        lines: page.lines, bounds: page.bounds) == nil)
    let noaa = try SourceLayoutFixture.load("noaa-701")
    let noaaPage = noaa.content()
    #expect(PrintedFormAreas.emptyBox(regions: noaaPage.graphics, paints: noaa.paints.map(\.rect),
        lines: noaaPage.lines, bounds: noaaPage.bounds) == nil)
    let lone = TextLine(text: "_________________________________",
        rect: CGRect(x: 72, y: 600, width: 165, height: 13), fontSize: 10)
    #expect(PrintedFormAreas.normalizedWritingLines([lone]).first?.text == lone.text)
}
