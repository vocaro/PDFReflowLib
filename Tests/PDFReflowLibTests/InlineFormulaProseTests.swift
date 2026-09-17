import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

// Prose with inline mathematics beside preserved formulas and figures (#51, #58, #49, #77).
// A line whose row reads as prose on its paragraph's measure is not a displayed formula, a
// formula's margin stops short of neighbouring text, and a form's bounding box claims only the
// part its clip lets show. Fixtures are native extraction from the checksum-pinned corpus
// documents; the expected lines were read from the rendered source pages.

private let algebraSHA256 = "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678"
private let faaSHA256 = "247929cace0ab56b376e683eba540cc4c8f39f199ab35414e8b604e24f395cb7"

private func sourcePage(_ name: String, sha256: String) throws -> PageContent {
    let fixture = try SourceLayoutFixture.load(name)
    #expect(fixture.sourceSHA256 == sha256)
    var page = fixture.content()
    page.lines.removeAll { $0.text == String(fixture.page) }   // the folio the furniture pass removes
    return page
}

private func reflow(_ page: PageContent, _ crops: [CGRect]) -> [ReflowBlock] {
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: crops.enumerated().map { ($0.element, "image-\($0.offset)") },
        vocabulary: LayoutReconstructor.vocabulary(in: [page]), warnings: &warnings)
}

private func line(_ page: PageContent, _ text: String) throws -> TextLine {
    try #require(page.lines.first { $0.text.contains(text) }, "no source line \(text)")
}

private func expectOutsideCrops(_ page: PageContent, _ crops: [CGRect], _ texts: [String],
                                sourceLocation: SourceLocation = #_sourceLocation) throws {
    for text in texts {
        let rect = try line(page, text).rect
        #expect(!crops.contains { $0.intersects(rect) }, "prose inside a crop: \(text)", sourceLocation: sourceLocation)
    }
}

private func expectInsideCrops(_ page: PageContent, _ crops: [CGRect], _ texts: [String],
                               sourceLocation: SourceLocation = #_sourceLocation) throws {
    for text in texts {
        let rect = try line(page, text).rect
        #expect(crops.contains { $0.contains(rect) }, "display outside every crop: \(text)", sourceLocation: sourceLocation)
    }
}

// Wallace page 288 (#58): sentences carrying inline radicals (`√25`, `√8`, `√36·5`) reflow; the
// Example 377 table of square roots and the displayed product rule stay preserved whole.
@Test func radicalProseReflowsBesideSquareRootDisplays() throws {
    let page = try sourcePage("algebra-288", sha256: algebraSHA256)
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    try expectOutsideCrops(page, crops, [
        "Square roots are the most common type of radical used.",
        "squares” a number. For example, because 52",
        "= 25 we say the square root of 25 is 5.",
        "The square root of 25 is written as",
        "The final example,− 81",
        "is currently undefined as negatives have no square root.",
        "This is because if we square a positive or a negative",
        "for now we will simply say they are undefined.",
        "Not all numbers have a nice even square root.",
        "our calculator, the answer would be",
        "We can use the product rule to simplify an expression such as",
        "it into two roots, 36",
        "and simplifying the first root, 6 5",
    ])
    try expectInsideCrops(page, crops, ["√ = Undefined", "√ =25", "Product Rule of Square Roots:", "√ = a"])
    #expect(crops.count == 2)
    let text = reflow(page, crops).map(\.text).joined(separator: "\n")
    for phrase in ["Square roots are the most common type of radical used.",
                   "Not all numbers have a nice even square root.",
                   "We can use the product rule to simplify an expression such as",
                   "The trick in this"] {
        #expect(text.contains(phrase), "missing prose: \(phrase)")
    }
}

// Wallace page 289 (#49): the opening sentence with inline `√180` and `√36·5` reflows instead of
// starting the page mid-sentence at `fastest method`; the three derivations stay preserved.
@Test func openingSentenceWithInlineRadicalsReflowsAboveDerivations() throws {
    let page = try sourcePage("algebra-289", sha256: algebraSHA256)
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    try expectOutsideCrops(page, crops, ["process is being able to translate a problem like 180", ". There are sev-",
                                         "eral ways this can be done.", "fastest method, is to find perfect squares"])
    try expectInsideCrops(page, crops, ["75 is divisible by 25, a perfect square", "5 3 √ Our Solution",
                                        "63 is divisible by 9, a perfect square", "5· 3 7 √ Multiply coeﬃcients",
                                        "72 is divisible by 9, a perfect square", "3· 2 2 √ Multiply"])
    // PDFKit extracts the inline radicals as separate row pieces; they rejoin their row and the
    // sentence continues into one paragraph (#95, `RowPiecesAndSpacedParagraphTests`).
    let text = reflow(page, crops).map(\.text).joined(separator: "\n")
    let opening = try #require(text.range(of: "process is being able to translate a problem like 180"))
    let method = try #require(text.range(of: "eral ways this can be done. The most common and, with a bit of practice, the fastest method"))
    let example = try #require(text.range(of: "Example 378."))
    #expect(opening.lowerBound < method.lowerBound && method.lowerBound < example.lowerBound)
}

// Wallace page 291 (#49): the instruction `Simplify.` reflows; every radical exercise stays inside
// a crop (the full exercise check is `squareRootExercisesStayInsidePreservedRegionsWithoutStrayText`).
@Test func practiceInstructionStaysOutOfRadicalExerciseCrops() throws {
    let page = try sourcePage("algebra-291", sha256: algebraSHA256)
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    let instruction = try #require(page.lines.first { $0.text == "Simplify." })
    #expect(!crops.contains { $0.intersects(instruction.rect) })
    try expectInsideCrops(page, crops, ["1) 245", "2) 125", "41)− 4 54mnp2", "42)− 8 32m2p4q"])
    #expect(reflow(page, crops).contains { $0.text == "Simplify." })
}

// FAA page 227 (#77): the compass-rose figure's group box overhangs its rounded frame by 13 pt
// into the column above; its clip keeps the crop off `true course desired.`. The word
// equations beneath `Step 1:`, `Step 2:` and `course is known:` read as the column text they
// are; the correction card and the figure stay preserved.
@Test func compassFigureLeavesTheSentenceAboveItToProse() throws {
    let page = try sourcePage("faa-227", sha256: faaSHA256)
    let sentenceEnd = try line(page, "true course desired.")
    #expect(!page.graphics.contains { $0.intersects(sentenceEnd.rect) })
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    try expectOutsideCrops(page, crops, ["true course desired.", "Step 1: Determine the Magnetic Course",
                                         "True Course (180°) ± Variation (+10°) = Magnetic Course",
                                         "correction card) = Compass Course (188°)", "course is known:"])
    #expect(crops.count == 2)
    let figure = try #require(page.graphics.first { $0.minX < 100 && $0.height > 100 })
    #expect(crops.contains { $0.contains(figure) })
    let paragraphs = reflow(page, crops).map(\.text)
    #expect(paragraphs.contains { $0.hasSuffix("as shown below, starting from the true course desired.") })
    #expect(paragraphs.contains { $0.contains("Step 1: Determine the Magnetic Course True Course (180°) ± Variation (+10°) = Magnetic Course (190°)") })
}

// FAA page 195: once a clipped form box ends exactly at a figure's crop edge, trimming must still
// cut the crop away from the lines it only touches (a rebuilt rectangle fell 0.00001 pt short of
// the edge it shared with the figure and the crop absorbed the caption and the column's last line).
@Test func figureBoxEndingAtItsCropEdgeLeavesTouchingLinesToProse() throws {
    let page = try sourcePage("faa-195", sha256: faaSHA256)
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    try expectOutsideCrops(page, crops, ["Figure 7-40. High performance airplane pressurization system.",
                                         "is designed, a further increase in aircraft altitude will result"])
    let figure = try #require(page.graphics.first { $0.minX < 10 && $0.height > 300 })
    #expect(crops.contains { $0.contains(figure.insetBy(dx: 0.5, dy: 0.5)) })
}

// A form XObject reports its bounding box as figure ink, limited to the clip in force when it is
// drawn. Control: the same form without the clip still reports its whole box.
@Test func formBoundingBoxIsLimitedToItsClip() throws {
    func paints(clipped: Bool) throws -> [CGRect] {
        let content = (clipped ? "q 20 20 100 60 re W n " : "q ") + "/Fm Do Q"
        let data = testPDF(objects: [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 300] /Resources << /XObject << /Fm 5 0 R >> >> /Contents 4 0 R >>",
            testPDFStream(content),
            testPDFStream("0 0 1 rg 30 30 80 40 re f", extra: "/Type /XObject /Subtype /Form /BBox [10 10 200 150]"),
        ])
        let document = try #require(PDFDocument(data: data))
        return GraphicsReader.read(try #require(document.page(at: 0)?.pageRef)).paints.map(\.rect)
    }
    let clip = CGRect(x: 20, y: 20, width: 100, height: 60)
    let clipped = try paints(clipped: true)
    #expect(clipped.contains(clip))
    #expect(!clipped.contains { $0.maxY > clip.maxY + 2.01 || $0.maxX > clip.maxX + 2.01 })
    let open = try paints(clipped: false)
    #expect(open.contains(CGRect(x: 10, y: 10, width: 190, height: 140)))
}

// Synthetic controls on 10-pt justified prose (12-pt leading, 12.4-pt line rectangles).
private func proseLine(_ text: String, x: CGFloat = 72, baseline: CGFloat, width: CGFloat = 450, height: CGFloat = 12.4) -> TextLine {
    TextLine(text: text, rect: CGRect(x: x, y: baseline - 3, width: width, height: height), fontSize: 10)
}

private let paragraphAbove = [
    proseLine("The motion of the particle follows from the equations derived in the previous section and", baseline: 700),
    proseLine("the boundary conditions stated there. We now combine the two results into a single relation", baseline: 688),
]
private let paragraphBelow = [
    proseLine("which holds for every admissible choice of the parameters. The next section extends the result", baseline: 640),
    proseLine("to the general case and shows how the constants depend on the initial state of the system.", baseline: 628),
]

// A displayed equation centred between paragraphs stays a crop; its margin reaches neither
// paragraph. An inline equation in a justified line of the same paragraph reflows.
@Test func displayedEquationStaysPreservedWhileInlineEquationReflows() throws {
    let display = proseLine("E = m c2 + p v", x: 260, baseline: 664, width: 74, height: 16)
    let page = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792),
                           lines: paragraphAbove + [display] + paragraphBelow, graphics: [])
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    #expect(crops.count == 1)
    #expect(crops.first?.contains(display.rect) == true)
    for prose in paragraphAbove + paragraphBelow {
        #expect(!crops.contains { $0.intersects(prose.rect) }, "prose inside the display crop: \(prose.text)")
    }

    let inline = proseLine("the boundary conditions give E = m c2 so that the energy of the particle is fixed and", baseline: 676)
    let prose = PageContent(number: 1, bounds: page.bounds, lines: paragraphAbove + [inline] + paragraphBelow, graphics: [])
    #expect(LayoutReconstructor.graphicsWithLabels(prose).isEmpty)
}

// A full-measure display of stacked terms without a sentence (`sin⁻¹(opposite/hypotenuse) = θ`,
// Wallace page 428) stays a formula even though it shares the paragraph's edges.
@Test func stackedDisplayOnTheMeasureWithoutASentenceStaysPreserved() throws {
    let display = proseLine("sin 1 opposite hypotenuse= θ cos 1 adjacent hypotenuse= θ", baseline: 664, height: 30)
    let page = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792),
                           lines: paragraphAbove + [display] + paragraphBelow, graphics: [])
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    #expect(crops.contains { $0.contains(display.rect) })
}
