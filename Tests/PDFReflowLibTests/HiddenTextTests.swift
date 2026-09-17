import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

/// Text PDFKit extracts but the rendering never shows (#74, #85): a running head painted before
/// an opaque page-sized photograph (The Fed Explained, page 8) and a caption wholly outside its
/// artwork's clipping path (FAA handbook, page 159). Visible prose is drawn after `body`, so every
/// fixture keeps ordinary text beside whatever it hides.
private let visibleProse = """
BT /F1 11 Tf 1 0 0 1 60 600 Tm (Visible prose opens the first paragraph of the page.) Tj ET
BT /F1 11 Tf 1 0 0 1 60 560 Tm (A second paragraph follows it further down the page.) Tj ET
BT /F1 11 Tf 1 0 0 1 60 520 Tm (A third paragraph keeps the page mostly visible text.) Tj ET
BT /F1 11 Tf 1 0 0 1 60 480 Tm (The fourth paragraph closes the ordinary prose here.) Tj ET
"""

private func hiddenTextPDF(_ body: String, prose: String = visibleProse) -> Data {
    testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Resources << /Font << /F1 4 0 R >> /XObject << /Im 6 0 R /Masked 7 0 R /Stencil 9 0 R >> /ExtGState << /Half << /ca 0.5 /CA 0.5 >> /Multiply << /BM /Multiply >> /Masking << /SMask << /S /Luminosity /G 8 0 R >> >> /Opaque << /ca 1 /BM /Normal /SMask /None >> >> >> /Contents 5 0 R >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        testPDFStream(body + "\n" + prose),
        testPDFStream("808080>", extra: "/Type /XObject /Subtype /Image /Width 1 /Height 1 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /ASCIIHexDecode"),
        testPDFStream("808080>", extra: "/Type /XObject /Subtype /Image /Width 1 /Height 1 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /ASCIIHexDecode /SMask 8 0 R"),
        testPDFStream("80>", extra: "/Type /XObject /Subtype /Image /Width 1 /Height 1 /ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /ASCIIHexDecode"),
        testPDFStream("00>", extra: "/Type /XObject /Subtype /Image /Width 1 /Height 1 /ImageMask true /BitsPerComponent 1 /Filter /ASCIIHexDecode"),
    ])
}

private func blocks(_ pdf: Data) async throws -> (text: [String], warnings: [ConversionWarning]) {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("source.pdf")
    try pdf.write(to: url)
    var options = ConversionOptions(); options.ocr = .never
    let result = try await PDFReflowLibPipeline.reconstruct(from: url, options: options,
        workspace: dir.appendingPathComponent("work"), progress: { _ in })
    return (result.document.blocks.map(\.text).filter { !$0.isEmpty }, result.warnings)
}

/// The native lines `HiddenTextFilter` finds hidden, read straight from the page. `lines`
/// replaces PDFKit's lines when a fixture must reproduce a source's line boundaries exactly.
private func hidden(_ pdf: Data, lines replacement: [TextLine]? = nil) throws -> [String] {
    let document = try #require(PDFDocument(data: pdf))
    let page = try #require(document.page(at: 0))
    let graphics = GraphicsReader.read(try #require(page.pageRef))
    let lines = try replacement ?? NativeTextReader.lines(on: page, limit: 100_000, includeStyle: false)
    return HiddenTextFilter.hiddenLines(lines, graphics: graphics).map { lines[$0].text }
}

private let runningHead = "BT /F1 9 Tf 1 0 0 1 60 760 Tm (Running head under the photograph) Tj ET"
private let photograph = "q 600 0 0 800 0 0 cm /Im Do Q"

@Test func textPaintedBeneathAnOpaquePageImageIsNotReflowed() async throws {
    // Fed page 8: the head first, then the photograph, then the chapter title over it.
    let pdf = hiddenTextPDF(runningHead + "\n" + photograph
        + "\nBT /F1 24 Tf 1 0 0 1 60 700 Tm (Overview of the Federal Reserve) Tj ET")
    #expect(try hidden(pdf) == ["Running head under the photograph"])
    let result = try await blocks(pdf)
    #expect(!result.text.contains { $0.contains("Running head") })
    #expect(result.text.first == "Overview of the Federal Reserve")
    #expect(result.text.contains { $0.contains("fourth paragraph") })
    // The page-sized image still earns the review warning, as before.
    #expect(result.warnings.contains { $0.code == .unverifiedTextLayer })
}

@Test func textWhollyOutsideTheClipIsNotReflowed() async throws {
    // FAA page 159: a leftover two-line caption below the artwork's clip, set as a TJ whose
    // continuation shows have no positioning of their own; a label inside the clip stays.
    let pdf = hiddenTextPDF("""
        q 60 650 300 120 re W n
        BT /F1 9 Tf 1 0 0 1 80 700 Tm (Label inside the clipped artwork) Tj ET
        BT /F1 9 Tf 1 0 0 1 64 630 Tm [(Figure 5-16.)-250 (The leftover caption)] TJ ( outside the clip) Tj 0 -11 Td (continues on a second clipped line.) Tj ET
        Q
        """)
    #expect(try hidden(pdf) == ["Figure 5-16. The leftover caption outside the clip", "continues on a second clipped line."])
    let result = try await blocks(pdf)
    #expect(!result.text.contains { $0.contains("Figure 5-16") || $0.contains("second clipped line") })
    #expect(result.text.contains { $0.contains("Label inside the clipped artwork") })
}

@Test func aClippedLineOverprintingAVisibleCaptionOnAnotherBaselineIsHidden() throws {
    // FAA page 159's geometry: the clipped caption's first line starts 3.5 points right of the
    // visible caption's second line and 1.2 points below it; PDFKit keeps them as two lines.
    let pdf = hiddenTextPDF("""
        BT /F1 9 Tf 1 0 0 1 72 441.9 Tm (Figure 6-20. The movement of the elevator is opposite to the) Tj 0 -12.5 Td (direction of movement of the elevator trim tab.) Tj ET
        q 72 457.9 237 271.7 re W n
        BT /F1 9 Tf 1 0 0 1 75.5 428.3 Tm (Figure 5-16. The movement of the elevator is opposite to the) Tj 0 -10.8 Td (direction of movement of the elevator trim tab.) Tj ET
        Q
        """)
    let faa = [
        TextLine(text: "Figure 6-20. The movement of the elevator is opposite to the", rect: CGRect(x: 72, y: 439.1, width: 237.1, height: 10.8), fontSize: 9),
        TextLine(text: "direction of movement of the elevator trim tab.", rect: CGRect(x: 72, y: 427.2, width: 168, height: 10.2), fontSize: 9),
        TextLine(text: "Figure 5-16. The movement of the elevator is opposite to the", rect: CGRect(x: 75.5, y: 426.0, width: 220, height: 9.9), fontSize: 9),
        TextLine(text: "direction of movement of the elevator trim tab.", rect: CGRect(x: 75.5, y: 415.2, width: 166.7, height: 9.7), fontSize: 9),
    ]
    #expect(try hidden(pdf, lines: faa) == [faa[2].text, faa[3].text])
    // Control: a visible run that starts inside the candidate line, or on its baseline, keeps it.
    var inside = faa
    inside[1].rect.origin.x = 76
    inside[1].rect.size.width = 164
    let shifted = pdf.replacing(Data("0 -12.5 Td".utf8), with: Data("4 -12.5 Td".utf8))
    #expect(try hidden(shifted, lines: inside) == [faa[3].text])
    let sameBaseline = pdf.replacing(Data("0 -12.5 Td".utf8), with: Data("0 -13.6 Td".utf8))
    #expect(try hidden(sameBaseline, lines: faa) == [faa[3].text])
}

@Test func removingAHiddenTaggedLineKeepsItsGroupCountTrue() throws {
    // A tagged group that loses a hidden line reports the lines that remain, so no group-size
    // rule reads the removed line as missing; untouched groups keep their counts.
    let pdf = hiddenTextPDF("q 40 600 400 100 re W n BT /F1 9 Tf 1 0 0 1 60 760 Tm (Clipped leftover text) Tj ET Q")
    let document = try #require(PDFDocument(data: pdf))
    let page = try #require(document.page(at: 0))
    let graphics = GraphicsReader.read(try #require(page.pageRef))
    var lines = try NativeTextReader.lines(on: page, limit: 100_000, includeStyle: false)
    #expect(lines.count == 5)
    for index in lines.indices {
        lines[index].structure = TextStructure(group: index < 3 ? 1 : 2, order: index < 3 ? 1 : 2,
                                               headingLevel: 0, lineCount: index < 3 ? 3 : 2)
    }
    #expect(HiddenTextFilter.removeHidden(&lines, graphics: graphics) == 1)
    #expect(!lines.contains { $0.text == "Clipped leftover text" })
    #expect(lines.map { $0.structure?.lineCount } == [2, 2, 2, 2])
}

private let visibleCases: [String] = [
    // Text drawn over the photograph, as every chapter title is.
    photograph + "\n" + runningHead,
    // A translucent, multiplied, soft-masked, masked, stencil or smaller image leaves it visible.
    runningHead + "\nq /Half gs 600 0 0 800 0 0 cm /Im Do Q",
    runningHead + "\nq /Multiply gs 600 0 0 800 0 0 cm /Im Do Q",
    runningHead + "\nq /Masking gs 600 0 0 800 0 0 cm /Im Do Q",
    runningHead + "\nq 600 0 0 800 0 0 cm /Masked Do Q",
    runningHead + "\nq 600 0 0 800 0 0 cm /Stencil Do Q",
    runningHead + "\nq 100 0 0 20 60 755 cm /Im Do Q",
    // A slanted photograph's bounds are not what it paints; a triangular clip is not a rectangle.
    runningHead + "\nq 900 520 -800 1386 300 -600 cm /Im Do Q",
    runningHead + "\nq 0 0 m 600 0 l 600 800 l h W n 600 0 0 800 0 0 cm /Im Do Q",
    // A clip that contains the text, or one the text only partly leaves.
    "q 40 740 400 40 re W n " + runningHead + " Q",
    "q 40 764 400 40 re W n " + runningHead + " Q",
    // An inherited OCR layer beneath a scan belongs to the unverified-text-layer path.
    "BT /F1 9 Tf 3 Tr 1 0 0 1 60 760 Tm (Running head under the photograph) Tj ET\n" + photograph,
    // Optional content may be hidden in the rendering; a pattern fill can be transparent.
    runningHead + "\n/OC /Layer BDC " + photograph + " EMC",
    runningHead + "\n/Pattern cs /P0 scn 50 750 400 25 re f",
]

@Test(arguments: visibleCases)
func textThatCanBeSeenIsKept(_ body: String) throws {
    #expect(try hidden(hiddenTextPDF(body)).isEmpty, "\(body)")
}

@Test func anOpaqueFillOverTextHidesIt() throws {
    #expect(try hidden(hiddenTextPDF(runningHead + "\n1 g 50 750 400 25 re f")) == ["Running head under the photograph"])
    #expect(try hidden(hiddenTextPDF(runningHead + "\n/Opaque gs 0 0 1 rg 50 750 400 25 re f")) == ["Running head under the photograph"])
    // The same fill in a translucent state does not.
    #expect(try hidden(hiddenTextPDF(runningHead + "\n/Half gs 0 0 1 rg 50 750 400 25 re f")).isEmpty)
}

@Test func aTextLayerBeneathTheImageThatShowsItIsKept() async throws {
    // The CDC comic letters every balloon under its page artwork: when covers would hide half
    // the page's lines, the text is the image's transcription layer, not leftovers.
    let pdf = hiddenTextPDF(visibleProse + "\n" + photograph, prose: "")
    #expect(try hidden(pdf).isEmpty)
    let result = try await blocks(pdf)
    #expect(result.text.contains { $0.contains("Visible prose opens") })
    #expect(result.warnings.contains { $0.code == .unverifiedTextLayer })
    // A clip still hides text on such a page.
    let clipped = hiddenTextPDF(visibleProse + "\nq 0 0 600 100 re W n BT /F1 9 Tf 1 0 0 1 60 760 Tm (Clipped leftover) Tj ET Q\n" + photograph, prose: "")
    #expect(try hidden(clipped) == ["Clipped leftover"])
}

@Test func rotatedVisibleTextKeepsTheLinesItCrosses() throws {
    // A rotated label is placed as a ray, never on a horizontal baseline: a hidden line it
    // crosses cannot be proven free of its glyphs, so it stays.
    let clipped = "q 40 600 400 100 re W n BT /F1 9 Tf 1 0 0 1 60 760 Tm (Clipped leftover text) Tj ET Q"
    #expect(try hidden(hiddenTextPDF(clipped)) == ["Clipped leftover text"])
    #expect(try hidden(hiddenTextPDF(clipped + "\nBT /F1 9 Tf 0 1 -1 0 110 700 Tm (Rotated axis label) Tj ET")).isEmpty)
    #expect(try hidden(hiddenTextPDF(clipped + "\nBT /F1 9 Tf 0 1 -1 0 500 700 Tm (Rotated label elsewhere) Tj ET")) == ["Clipped leftover text"])
}

@Test func graphicsReaderPlacesTextShows() throws {
    let document = try #require(PDFDocument(data: hiddenTextPDF("""
        BT /F1 10 Tf 2 0 0 2 100 200 Tm 5 Ts (A) Tj [(B) 1000 (C)] TJ -1 Tc (DD) Tj 0 -10 Td [-500 (E)] TJ ET
        q 0 0 m 10 0 l 10 10 l W n BT /F1 10 Tf 1 0 0 1 20 20 Tm (F) Tj ET Q
        """, prose: "")))
    let graphics = GraphicsReader.read(try #require(document.page(at: 0)?.pageRef))
    let shows = graphics.textShows
    #expect(shows.count == 5)
    // Rise belongs to the text state, so it still raises the later text object's show.
    #expect(shows.map(\.baseline) == [210, 210, 210, 190, 25])
    // Positioned shows have exact origins; continuations have lower bounds on their start.
    #expect(shows[0].origin == CGPoint(x: 100, y: 210))
    #expect(shows[1].origin == nil && shows[1].left == 100 && shows[1].chainStart == CGPoint(x: 100, y: 210))
    // (−1000/1000 × 10) × 2 moves the start left by 20.
    #expect(abs(shows[2].left - 80) < 1e-9, "\(shows[2].left)")
    // A leading TJ number is an exact displacement: (500/1000 × 10) × 2.
    #expect(shows[3].origin == CGPoint(x: 110, y: 190))
    #expect(shows[4].clip == CGRect(x: 0, y: 0, width: 10, height: 10))
    #expect(!graphics.textPlacementUnsupported && graphics.covers.isEmpty)
}
