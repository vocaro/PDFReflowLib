import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

// Labels set against opposite sides of a figure that PDFKit returns as one line (#14, the
// *Dietary Guidelines* cover: `& Healthy Fats` labels the left of the food pyramid and
// `& Fruits` its right, and PDFKit joins them with a space glyph 343 pt wide). The content
// stream's text-show positions say where each label begins, and PDFKit's own rectangle
// selections then measure the empty space between them. Column gaps, cells, word spaces and
// pages whose shows the reader cannot read must keep their lines exactly as PDFKit read them.

private let pageWidth: CGFloat = 612

/// A page of upright shows, each `(text, x, y)` in page space, in a simple font with widths and
/// a WinAnsi encoding (the evidence `NativeSpacingReader` needs).
private func showPDF(_ shows: [(String, CGFloat, CGFloat)], size: CGFloat = 18,
                     widths: Bool = true, unreadable: Bool = false) -> Data {
    var content = ""
    for (text, x, y) in shows {
        content += "BT /F1 \(size) Tf "
        // A text-rendering mode this reader does not model disqualifies the page's evidence.
        if unreadable { content += "1 Tr " }
        content += "\(x) \(y) Td (\(text)) Tj ET\n"
    }
    let widthList = (32...126).map { _ in "556" }.joined(separator: " ")
    let font = widths
        ? "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding"
            + " /FirstChar 32 /LastChar 126 /Widths [\(widthList)] >>"
        : "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>"
    return testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 \(pageWidth) 792] /Resources << /Font << /F1 5 0 R >> >>"
            + " /Contents 4 0 R >>",
        testPDFStream(content),
        font,
    ])
}

private func page(_ data: Data) throws -> PDFPage {
    let document = try #require(PDFDocument(data: data))
    return try #require(document.page(at: 0))
}

/// The lines PDFKit itself returns, before any repair.
private func native(_ page: PDFPage) -> [String] {
    pdfKitGated {
        (page.selection(for: page.bounds(for: .cropBox))?.selectionsByLine() ?? [])
            .compactMap { $0.string?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private func read(_ page: PDFPage) throws -> [TextLine] {
    try NativeTextReader.lines(on: page, limit: 100_000).sorted { $0.rect.minX < $1.rect.minX }
}

// MARK: The reproducer

@Test func labelsOnOppositeSidesOfAFigureAreReadAsSeparateLines() throws {
    // The cover's geometry: both labels on one baseline, 349 pt of empty page between them.
    let source = try page(showPDF([("& Healthy Fats", 39.4, 450), ("& Fruits", 507.3, 450)]))
    // Reproducer: PDFKit returns the two labels as one line.
    #expect(native(source) == ["& Healthy Fats & Fruits"])
    let lines = try read(source)
    #expect(lines.map(\.text) == ["& Healthy Fats", "& Fruits"])
    // Each piece's box ends at its own glyphs, not at the stretched space between them.
    #expect(lines[0].rect.maxX < 200)
    #expect(lines[1].rect.minX > 500)
    #expect(lines.allSatisfy { abs($0.rect.minY - lines[0].rect.minY) < 1 })
}

@Test func aSplitLabelKeepsItsStyledRun() throws {
    let lines = try read(page(showPDF([("& Healthy Fats", 39.4, 450), ("& Fruits", 507.3, 450)])))
    #expect(lines.count == 2)
    #expect(lines.allSatisfy { line in
        line.content.elements.contains { if case let .text(_, style) = $0 { style.contains(.bold) } else { false } }
    })
}

@Test func threeDetachedLabelsOnOneBaselineAreAllSeparated() throws {
    let source = try page(showPDF([("Left", 30, 450), ("Middle", 290, 450), ("Right", 540, 450)], size: 12))
    #expect(native(source) == ["Left Middle Right"])
    #expect(try read(source).map(\.text) == ["Left", "Middle", "Right"])
}

// MARK: Controls — lines PDFKit merges that must stay merged

@Test func aTableRowsColumnGapDoesNotSplitItsCells() throws {
    // The FAA's beacon table (page 416) leaves 103 pt between `H` and `50–1999` on a 594 pt
    // page: ten ems, but well under a quarter of the page.
    let source = try page(showPDF([("H", 240, 450), ("50-1999", 343, 450)], size: 10))
    #expect(native(source) == ["H 50-1999"])
    #expect(try read(source).map(\.text) == ["H 50-1999"])
}

@Test func aGapNoWiderThanTheTextAroundItDoesNotSplitItsLine() throws {
    // A row whose pieces carry more ink than the space between them (164 pt of gap against 195 pt
    // of text, Our Flag page 4's committee rows): the empty page no longer dominates the row, so
    // it reads as a row of text and not as detached content, although the gap passes both
    // distance thresholds.
    let source = try page(showPDF([("H", 240, 450), ("Representative from Ohio, Chairman", 410, 450)], size: 10))
    #expect(native(source) == ["H Representative from Ohio, Chairman"])
    #expect(try read(source).map(\.text) == ["H Representative from Ohio, Chairman"])
}

@Test func proseWithOrdinaryWordSpacesIsNeverSplit() throws {
    let source = try page(showPDF([("The quick brown fox jumps over the lazy dog again and again", 40, 450)], size: 11))
    #expect(try read(source).map(\.text) == ["The quick brown fox jumps over the lazy dog again and again"])
}

@Test func aShortLineIsNotSplitHoweverItsShowsStand() throws {
    // The line itself is narrower than a quarter of the page, so no cut inside it can be one.
    let source = try page(showPDF([("A", 40, 450), ("B", 170, 450)], size: 6))
    #expect(native(source) == ["A B"])
    #expect(try read(source).map(\.text) == ["A B"])
}

@Test func labelsOnSeparateBaselinesKeepTheirOwnLines() throws {
    let source = try page(showPDF([("& Healthy Fats", 39.4, 470), ("& Fruits", 507.3, 450)]))
    #expect(Set(native(source)) == ["& Healthy Fats", "& Fruits"])
    #expect(Set(try read(source).map(\.text)) == ["& Healthy Fats", "& Fruits"])
}

@Test func aPageWithoutShowEvidenceKeepsPDFKitsLine() throws {
    // Without widths the page has no supported font, so the reader collects no show positions
    // and can propose no cut. Every ruled-table and prose fixture captured before #14 is in
    // this state, which is why none of them changed.
    let source = try page(showPDF([("& Healthy Fats", 39.4, 450), ("& Fruits", 507.3, 450)], widths: false))
    #expect(native(source) == ["& Healthy Fats & Fruits"])
    #expect(try read(source).map(\.text) == ["& Healthy Fats & Fruits"])
}

@Test func unmodelledTextStateKeepsPDFKitsLine() throws {
    // A text-rendering mode the spacing reader does not model disqualifies the whole page's
    // evidence, so no cut is proposed there either.
    let source = try page(showPDF([("& Healthy Fats", 39.4, 450), ("& Fruits", 507.3, 450)], unreadable: true))
    #expect(NativeSpacingReader.read(try #require(source.pageRef)).isEmpty)
    #expect(try read(source).map(\.text) == ["& Healthy Fats & Fruits"])
}

// MARK: The measured thresholds

@Test func theDetachedGapThresholdsAreTheMeasuredOnes() {
    // Column and cell gaps across the corpus reach 11.6 ems and 19% of the page; detached
    // content begins at 17.8 ems and 34%.
    #expect(NativeTextReader.detachedShowGap == 8)
    #expect(NativeTextReader.detachedShowPageShare == 0.25)
}
