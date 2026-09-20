import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// Original minimal PDFs, so the clip cases are testable one at a time without a downloaded
// corpus. Each content stream below is the operator sequence a real page uses to place art
// larger than the frame that shows it.
private func read(_ content: String, formContent: String = "0 0 60 40 re f",
                  formBox: String = "[0 0 60 40]", formMatrix: String = "[1 0 0 1 0 0]",
                  mediaBox: String = "[0 0 612 792]") throws -> GraphicsReader.Result {
    GraphicsReader.read(try operatorPage(content, formContent: formContent, formBox: formBox,
                                         formMatrix: formMatrix, mediaBox: mediaBox))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/98"))
func paintedPathIsBoundedByTheClipThatPaintedIt() throws {
    // A streamline drawn 400 points wide under a 100-point frame reaches the next column.
    let result = try read("q 100 500 100 80 re W n 20 520 400 40 re f Q")
    #expect(!result.unsupported)
    #expect(result.regions == [CGRect(x: 98, y: 518, width: 104, height: 44)])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/98"))
func aPathWhollyOutsideItsClipIsNotFigureInk() throws {
    let result = try read("q 100 500 100 80 re W n 300 200 80 40 re f Q")
    #expect(!result.unsupported)
    #expect(result.regions.isEmpty)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/52"))
func placedImageIsBoundedByItsClip() throws {
    // FAA page 19's shape: a map placed far larger than the frame it shows through.
    let result = try read("q 300 600 120 90 re W n q 400 0 0 400 250 500 cm /Im Do Q Q")
    #expect(!result.unsupported)
    #expect(result.regions == [CGRect(x: 300, y: 600, width: 120, height: 90)])
    #expect(result.images == result.regions)
}

@Test func clipRestoredByQDoesNotBoundLaterPaint() throws {
    let result = try read("q 100 500 100 80 re W n 20 520 400 40 re f Q 20 100 400 40 re f")
    #expect(!result.unsupported)
    #expect(result.regions.contains(CGRect(x: 98, y: 518, width: 104, height: 44)))
    #expect(result.regions.contains(CGRect(x: 18, y: 98, width: 404, height: 44)))
}

@Test func nestedClipsIntersectAndTheOuterOneSurvivesTheInner() throws {
    // The inner clip bounds what it wraps; after its Q the outer one bounds the rest, and a
    // paint outside the outer clip is recorded nowhere.
    let result = try read("q 100 500 200 200 re W n q 100 500 40 40 re W n 0 0 600 700 re f Q"
        + " 250 650 40 40 re f 400 200 40 40 re f Q")
    #expect(!result.unsupported)
    #expect(result.regions == [CGRect(x: 98, y: 498, width: 44, height: 44),
                               CGRect(x: 248, y: 648, width: 44, height: 44)])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/52"))
func formBoxAndItsContentAreBoundedByTheClipInForce() throws {
    // The form's own matrix places its box; the clip at the Do site bounds both the box the
    // reader records for the figure's labels and everything the form paints.
    let result = try read("q 100 500 40 30 re W n q 2 0 0 2 100 500 cm /Fm Do Q Q",
                          formContent: "0 0 60 40 re f", formBox: "[0 0 60 40]",
                          formMatrix: "[1 0 0 1 10 10]")
    #expect(!result.unsupported)
    #expect(!result.regions.isEmpty)
    #expect(result.regions.allSatisfy { CGRect(x: 98, y: 498, width: 44, height: 34).contains($0) })
}

@Test func aFormsOwnBoxClipsItsContentAndIsRestoredAfterwards() throws {
    // The form paints ten times its own box; only the box shows. What follows it is unbounded.
    let result = try read("q 1 0 0 1 100 500 cm /Fm Do Q 20 100 400 40 re f",
                          formContent: "-200 -200 600 600 re f", formBox: "[0 0 60 40]")
    #expect(!result.unsupported)
    #expect(result.regions.contains(CGRect(x: 98, y: 498, width: 64, height: 44)))
    #expect(result.regions.contains(CGRect(x: 18, y: 98, width: 404, height: 44)))
}

@Test func aRuleOfNoHeightInsideItsClipIsStillRecorded() throws {
    // A horizontal rule is a path of no area. Clipping an unpadded footprint would discard
    // every one of them, and with them the table and fraction evidence they seed.
    let result = try read("q 100 500 200 80 re W n 120 540 m 280 540 l S Q")
    #expect(!result.unsupported)
    #expect(result.regions == [CGRect(x: 118, y: 538, width: 164, height: 4)])
}

@Test func aClipPathThatReachedNoCoordinateLeavesTheClipAlone() throws {
    let result = try read("q W n 20 100 400 40 re f Q")
    #expect(!result.unsupported)
    #expect(result.regions == [CGRect(x: 18, y: 98, width: 404, height: 44)])
}

@Test func paintOnTheClipBoundaryKeepsItsTolerance() throws {
    // A frame drawn exactly on the clip that bounds it is not cut by it, so its footprint is
    // the same two points wider than the ink as an unclipped one.
    let clipped = try read("q 100 500 200 80 re W n 100 500 200 80 re f Q")
    let unclipped = try read("100 500 200 80 re f")
    #expect(clipped.regions == unclipped.regions)
    #expect(clipped.regions == [CGRect(x: 98, y: 498, width: 204, height: 84)])
}

@Test func aClipSetInsideAFormDoesNotOutliveIt() throws {
    // The form clips itself to a tenth of its box. That clip must not still be in force for the
    // page's own paint afterwards, which is far outside it.
    let result = try read("q 1 0 0 1 100 500 cm /Fm Do Q 20 100 400 40 re f",
                          formContent: "q 0 0 10 10 re W n 0 0 60 40 re f Q", formBox: "[0 0 60 40]")
    #expect(!result.unsupported)
    #expect(result.regions.contains(CGRect(x: 18, y: 98, width: 404, height: 44)))
    // The figure's own footprint is its clipped paint together with the box the reader records
    // for the form's labels, and neither reaches past the box.
    #expect(result.regions.allSatisfy { $0.minY < 200 || CGRect(x: 98, y: 498, width: 64, height: 44).contains($0) })
}
