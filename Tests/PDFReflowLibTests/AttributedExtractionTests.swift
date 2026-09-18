import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib
#if canImport(AppKit)
import AppKit
private typealias PlatformFont = NSFont
#else
import UIKit
private typealias PlatformFont = UIFont
#endif

/// #4: PDFKit leaks every attributed string it returns (FB24783799), so a page's styled lines are
/// read with one request for their union and sliced, instead of one request per line. Each slice
/// must carry exactly what the line's own request returns; a page whose union does not align
/// with its lines falls back to requests per line.
private let page = testPDF(objects: [
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R /F2 6 0 R /F3 7 0 R >> >> /Contents 4 0 R >>",
    testPDFStream("""
    BT /F2 18 Tf 1 0 0 1 72 720 Tm (A Heading Set in Bold) Tj ET
    BT /F1 12 Tf 1 0 0 1 72 690 Tm (The body opens with an ordinary line of prose,) Tj ET
    BT /F1 12 Tf 1 0 0 1 72 674 Tm (and it continues with ) Tj /F3 12 Tf (an italic phrase) Tj /F1 12 Tf ( inside.) Tj ET
    BT /F1 10 Tf 1 0 0 1 72 640 Tm (Associate Editor:) Tj ET
    BT /F1 10 Tf 1 0 0 1 400 640 Tm (\\(301\\) 504-1623) Tj ET
    BT /F1 12 Tf 1 0 0 1 72 610 Tm (A last line closes the page.) Tj ET
    """),
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>",
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Oblique /Encoding /WinAnsiEncoding >>",
])

@Test func unionSlicesCarryEachLinesOwnAttributedText() throws {
    let document = try #require(PDFDocument(data: page))
    let pdfPage = try #require(document.page(at: 0))
    let selections = try #require(pdfPage.selection(for: pdfPage.bounds(for: .cropBox))).selectionsByLine()
    let texts = selections.map(\.string)
    let indices = selections.indices.filter { !(texts[$0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    // PDFKit reads the two pieces of the `Associate Editor:` row as one line.
    #expect(indices.count == 5)
    let sliced = NativeTextReader.attributedTexts(of: indices, in: selections, texts: texts, on: pdfPage)
    // Every styled line comes from the one request: none is left to a request of its own.
    #expect(Set(sliced.keys) == Set(indices))
    for index in indices {
        let own = try #require(selections[index].attributedString)
        let slice = try #require(sliced[index])
        #expect(slice.isEqual(to: own), "line \(index): \(own.string)")
    }
    let fonts = indices.compactMap { (sliced[$0]?.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont)?.fontName }
    #expect(fonts.contains { $0.contains("Bold") })
}

@Test func unionTextAlignsOnlyWithLinesInOrder() {
    // PDFKit separates rows with a newline and runs the pieces of one row together.
    #expect(NativeTextReader.lineRanges(of: ["One", "Two", "Three"], in: "One\nTwoThree")
        == [NSRange(location: 0, length: 3), NSRange(location: 4, length: 3), NSRange(location: 7, length: 5)])
    #expect(NativeTextReader.lineRanges(of: ["a\u{FFFC}b", "c"], in: "a\u{FFFC}b\nc")
        == [NSRange(location: 0, length: 3), NSRange(location: 4, length: 1)])
    // A line the union repeats (a row piece equal to the next line's start) still lies at the cursor.
    #expect(NativeTextReader.lineRanges(of: ["ab", "abc"], in: "ababc")
        == [NSRange(location: 0, length: 2), NSRange(location: 2, length: 3)])
    // Anything else falls back to requests per line: lines out of order, text left over,
    // a separator other than one newline, an empty line, or characters that differ only by
    // canonical equivalence.
    #expect(NativeTextReader.lineRanges(of: ["Two", "One"], in: "One\nTwo") == nil)
    #expect(NativeTextReader.lineRanges(of: ["One"], in: "One\nTwo") == nil)
    #expect(NativeTextReader.lineRanges(of: ["One", "Two"], in: "One\n\nTwo") == nil)
    #expect(NativeTextReader.lineRanges(of: ["One", "Two"], in: "One Two") == nil)
    #expect(NativeTextReader.lineRanges(of: ["", "One"], in: "One") == nil)
    #expect(NativeTextReader.lineRanges(of: ["caf\u{E9}"], in: "cafe\u{301}") == nil)
}
