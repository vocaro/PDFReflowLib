import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

// Figure crops bounded by what their clip lets show (#98, #52). A path's or an image's extent is
// not its ink: FAA illustrations draw streamlines, arrows, photographs and maps far beyond the
// frame that clips them, into the neighbouring column, and `GraphicsReader` recorded the whole
// extent, so the crop took the prose beside the figure. Fixtures are native extraction from the
// checksum-pinned FAA handbook, captured with the clipped reader; the expected lines were read
// from the rendered source pages.

private let faaSHA256 = "247929cace0ab56b376e683eba540cc4c8f39f199ab35414e8b604e24f395cb7"

private func sourcePage(_ name: String) throws -> PageContent {
    let fixture = try SourceLayoutFixture.load(name)
    #expect(fixture.sourceSHA256 == faaSHA256)
    return fixture.content()
}

private func reflowedText(_ page: PageContent, _ crops: [CGRect]) -> String {
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: crops.enumerated().map { ($0.element, "image-\($0.offset)") },
        vocabulary: LayoutReconstructor.vocabulary(in: [page]), warnings: &warnings)
        .map(\.text).joined(separator: "\n")
}

private func line(_ page: PageContent, _ text: String) throws -> TextLine {
    try #require(page.lines.first { $0.text.hasPrefix(text) }, "no source line \(text)")
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
        #expect(crops.contains { $0.contains(rect) }, "label outside every crop: \(text)", sourceLocation: sourceLocation)
    }
}

/// Each figure's clip frame (read from the page's content stream) must lie inside one crop.
private func expectFramesKept(_ crops: [CGRect], _ frames: [CGRect], sourceLocation: SourceLocation = #_sourceLocation) {
    for frame in frames {
        #expect(crops.contains { $0.insetBy(dx: -1, dy: -1).contains(frame) }, "figure frame cut: \(frame)",
                sourceLocation: sourceLocation)
    }
}

private func expectInOrder(_ text: String, _ phrases: [String], sourceLocation: SourceLocation = #_sourceLocation) {
    let positions = phrases.map { text.range(of: $0)?.lowerBound }
    for (phrase, position) in zip(phrases, positions) where position == nil {
        Issue.record("missing prose: \(phrase)", sourceLocation: sourceLocation)
    }
    let found = positions.compactMap { $0 }
    #expect(found == found.sorted(), "prose out of order: \(phrases)", sourceLocation: sourceLocation)
}

// MARK: Reader: footprints limited to their clip

private func paints(_ content: String) throws -> [CGRect] {
    let data = testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Resources << /XObject << /Im 5 0 R >> >> /Contents 4 0 R >>",
        testPDFStream(content),
        testPDFStream("808080>", extra: "/Type /XObject /Subtype /Image /Width 1 /Height 1 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /ASCIIHexDecode"),
    ])
    let document = try #require(PDFDocument(data: data))
    return GraphicsReader.read(try #require(document.page(at: 0)?.pageRef)).paints.map(\.rect)
}

private let frame = CGRect(x: 300, y: 500, width: 200, height: 150)
private let clipFrame = "300 500 200 150 re W n "

// A stroked curve whose control points reach far left of the frame that clips it (FAA page 96's
// streamlines, page 130's arrows) claims only the frame. Control: unclipped, its whole extent.
@Test func strokedPathBeyondItsClipClaimsOnlyTheClip() throws {
    let curve = "0 0 1 RG 2 w 100 520 m 250 700 450 600 480 640 c S "
    let clipped = try paints("q " + clipFrame + curve + "Q")
    #expect(!clipped.isEmpty)
    #expect(clipped.allSatisfy { frame.insetBy(dx: -0.01, dy: -0.01).contains($0) })
    let open = try paints("q " + curve + "Q")
    #expect(open.contains { $0.minX <= 98.01 && $0.maxY >= 701.99 })
}

// A photograph or map placed larger than its frame (FAA page 19's airmail map, 338 × 400 pt under a
// 207 × 129 pt clip; page 191's switch) claims only the frame. Control: unclipped, its placement.
@Test func imageBeyondItsClipClaimsOnlyTheClip() throws {
    let place = "400 0 0 400 150 400 cm /Im Do "
    #expect(try paints("q " + clipFrame + place + "Q") == [frame])
    #expect(try paints("q " + place + "Q") == [CGRect(x: 150, y: 400, width: 400, height: 400)])
}

// A fill wholly outside its clip paints nothing (the bleed rectangle beside FAA page 361's figure).
// Control: the same fill inside the clip is a footprint.
@Test func fillWhollyOutsideItsClipPaintsNothing() throws {
    #expect(try paints("q " + clipFrame + "0 0 1 rg 100 100 50 50 re f Q").isEmpty)
    #expect(try paints("q " + clipFrame + "0 0 1 rg 350 550 50 50 re f Q") == [CGRect(x: 348, y: 548, width: 54, height: 54)])
}

// MARK: Layout: a clipped figure beside a prose column

private func twoColumnPage(clipped: Bool) throws -> PageContent {
    let prose = [
        "The airfoil is inclined against the airflow,", "producing a different flow caused by the",
        "relationship to the oncoming air. Think of a", "hand placed outside the car window at a high",
        "speed. If the hand is inclined in one direction", "or another, the hand will move up or down.",
        "This is caused by deflection, which in turn", "causes the air to turn about the object.",
    ].enumerated().map { "BT /F1 10 Tf 1 0 0 1 60 \(700 - $0.offset * 12) Tm (\($0.element)) Tj ET" }.joined(separator: "\n")
    // Streamlines drawn from x 100 across the prose to the frame's right edge, clipped to the frame.
    let figure = (clipped ? "q 300 560 240 150 re W n " : "q ")
        + "0 0 1 RG 2 w 100 600 m 250 720 450 560 540 700 c S 100 580 m 260 700 460 540 540 660 c S Q\n"
        + "BT /F1 9 Tf 1 0 0 1 380 630 Tm (Relative wind) Tj ET"
    let data = testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        testPDFStream(prose + "\n" + figure),
    ])
    let document = try #require(PDFDocument(data: data))
    let page = try #require(document.page(at: 0))
    let graphics = GraphicsReader.read(try #require(page.pageRef))
    let lines = try NativeTextReader.lines(on: page, limit: 100_000)
    var content = PageContent(number: 1, bounds: page.bounds(for: .cropBox), lines: lines, graphics: graphics.regions)
    let composed = TintDetector.compose(graphics.paints, lines: lines, bounds: content.bounds)
    content.graphics = composed.graphics
    return content
}

// The figure keeps its label inside its frame; the column beside it reflows. Control: the same
// streamlines drawn without a clip really do cross the prose, and the crop keeps what they paint.
@Test func clippedFigureLeavesTheColumnBesideItAndKeepsItsLabel() throws {
    let page = try twoColumnPage(clipped: true)
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    try expectOutsideCrops(page, crops, ["The airfoil is inclined", "producing a different flow", "relationship to the oncoming",
                                         "hand placed outside", "speed. If the hand", "This is caused by deflection"])
    try expectInsideCrops(page, crops, ["Relative wind"])
    #expect(crops.count == 1)
    let open = try twoColumnPage(clipped: false)
    let openCrops = LayoutReconstructor.graphicsWithLabels(open)
    let crossed = try line(open, "relationship to the oncoming").rect
    #expect(openCrops.contains { $0.intersects(crossed) })
}

// MARK: FAA handbook pages

// Page 19 (#52): the airmail-route map is placed 43 pt into the left column under its frame. The left
// column reflows whole and in order before the right column; the map and the photo stay preserved.
@Test func airmailMapLeavesTheLeftColumnWhole() throws {
    let page = try sourcePage("faa-19-clipped")
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    try expectOutsideCrops(page, crops, ["mass produced to serve as fighters", "Aviation advocates continued",
                                         "pilots and their planes into the program", "Transcontinental Air Mail Route",
                                         "miles with 13 intermediate stops", "which served as the cornerstone"])
    expectFramesKept(crops, [CGRect(x: 300.2, y: 555.6, width: 206.6, height: 128.9)])
    #expect(crops.count == 2)
    expectInOrder(reflowedText(page, crops), ["mass produced to serve as fighters", "Aviation advocates continued",
        "Airmail routes continued to expand", "United States. This legislation", "The Air Commerce Act charged",
        "Department of Commerce made significant"])
}

// Page 96 (#98): the tip-vortex streamlines reach x 258 behind the figure frame at x 322.7.
@Test func tipVortexFigureLeavesTheLeftColumnToProse() throws {
    let page = try sourcePage("faa-96-clipped")
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    try expectOutsideCrops(page, crops, ["are identical. In both examples", "responsible for creating lift.",
                                         "As an airfoil moves through air", "Figure 4-8. Tip vortex."])
    expectFramesKept(crops, [CGRect(x: 322.7, y: 550.9, width: 234.5, height: 177.6)])
    expectInOrder(reflowedText(page, crops), ["are identical. In both examples", "As an airfoil moves through air",
                                              "To this point, the discussion", "Modern general aviation aircraft"])
}

// Page 130: the propeller figure's arrows run past its two panel frames into the right column.
@Test func propellerFigureLeavesTheRightColumnOpening() throws {
    let page = try sourcePage("faa-130-clipped")
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    try expectOutsideCrops(page, crops, ["Load Factors in Aircraft Design", "The answer to the question",
                                         "possible loads are much too high", "normal operation under various"])
    expectFramesKept(crops, [CGRect(x: 103.1, y: 612.8, width: 91.1, height: 99.3), CGRect(x: 217.7, y: 608.4, width: 91.1, height: 99.3)])
    expectInOrder(reflowedText(page, crops), ["In aerodynamics, the maximum load factor", "Load Factors in Aircraft Design",
                                              "The answer to the question", "The problem of load factors"])
}

// Page 146: paths of the lower panel drawn under the upper panel's frame (and a hidden copy
// whose group box misses its clip) reach x 328, over the right column's opening.
@Test func stallFiguresLeaveTheRightColumnOpening() throws {
    let page = try sourcePage("faa-146-clipped")
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    try expectOutsideCrops(page, crops, ["to cause a low-speed Mach buffet", "High altitudes—the higher",
                                         "G loading—an increase", "High Speed Flight Controls", "On high-speed aircraft"])
    expectFramesKept(crops, [CGRect(x: 72.5, y: 602.3, width: 237, height: 126.4), CGRect(x: 72.3, y: 450.8, width: 237, height: 126.4)])
    expectInOrder(reflowedText(page, crops), ["It is a characteristic of T-tail aircraft", "to cause a low-speed Mach buffet",
                                              "On high-speed aircraft"])
}

// Page 191: the master-switch art is 700 × 715 pt under a 161 × 202 pt frame; the whole page below
// the bus-bar paragraph was one crop.
@Test func masterSwitchFigureLeavesBothColumnsToProse() throws {
    let page = try sourcePage("faa-191-clipped")
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    try expectOutsideCrops(page, crops, ["electricity as a source of power", "Fuses or circuit breakers",
                                         "identify the circuit by name", "[Figure 7-35] The loadmeter", "Hydraulic Systems"])
    expectFramesKept(crops, [CGRect(x: 110, y: 108.1, width: 160.9, height: 201.7)])
    #expect(crops.count == 1)
    expectInOrder(reflowedText(page, crops), ["A bus bar is used as a terminal", "Fuses or circuit breakers",
                                              "An ammeter is used to monitor", "There are multiple applications"])
}

// Page 351: the pulsating-VASI light's glow path overhangs its 22 × 46 pt frame into the right column.
@Test func vasiFigureLeavesRunwayLightingToProse() throws {
    let page = try sourcePage("faa-351-clipped")
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    try expectOutsideCrops(page, crops, ["light. The “slightly below glidepath”", "day and up to ten miles at night.",
                                         "Runway Lighting", "There are various lights", "landing during night operations."])
    expectFramesKept(crops, [CGRect(x: 277.6, y: 651.7, width: 22.4, height: 46.4)])
    expectInOrder(reflowedText(page, crops), ["Pulsating VASIs normally consist", "There are various lights",
                                              "Runway end identifier lights"])
}

// Page 361: a rectangle wholly outside the vortex figure's clip reached the line above the frame.
@Test func vortexFigureLeavesTheEnRouteParagraphToProse() throws {
    let page = try sourcePage("faa-361-clipped")
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    try expectOutsideCrops(page, crops, ["En Route", "En route wake turbulence events", "(A380) and “Heavy”",
                                         "ground (until it touches down)", "from either ahead or behind"])
    expectFramesKept(crops, [CGRect(x: 73.25, y: 79.98, width: 485.77, height: 143.68)])
    expectInOrder(reflowedText(page, crops), ["En route wake turbulence events", "Vortices are generated from the moment"])
}

// Controls: figures whose labels are native text keep every label inside their clipped crops
// (page 159's trim-tab panels, page 401's wind triangle with its compass rose).
@Test func labelBearingFiguresKeepTheirLabels() throws {
    let trim = try sourcePage("faa-159-clipped")
    let trimCrops = LayoutReconstructor.graphicsWithLabels(trim)
    try expectInsideCrops(trim, trimCrops, ["Nose-down trim", "Nose-up trim", "Trim tab", "Elevator",
                                            "Tab up—elevator down", "Tab up—elevator up"])
    #expect(trimCrops.count == 2)
    let wind = try sourcePage("faa-401-clipped")
    let windCrops = LayoutReconstructor.graphicsWithLabels(wind)
    try expectInsideCrops(wind, windCrops, ["Heading and airspeed", "Course and groundspeed", "Wind direction and velocity"])
    for text in ["33", "30", "24", "21", "15", "12"] {
        let label = try #require(wind.lines.first { $0.text == text })
        #expect(windCrops.contains { $0.contains(label.rect) }, "compass label outside every crop: \(text)")
    }
}

// Page 401: the wind triangle's caption sits beneath the figure frame; the art that overhung the
// frame took it into the crop.
@Test func windTriangleCaptionLeavesItsCrop() throws {
    let wind = try sourcePage("faa-401-clipped")
    try expectOutsideCrops(wind, LayoutReconstructor.graphicsWithLabels(wind), ["Figure 16-19. Principle of the wind triangle."])
}
