import CoreText
import Foundation
import PDFKit
import Testing
import ZIPFoundation
@testable import PDFReflowLib

// A line PDFKit measured from the baseline of smaller text beside it is measured from its own
// baseline (#308), and a script measured from the text it is set against is not.

private let baselineKey = NSAttributedString.Key(kCTBaselineOffsetAttributeName as String)

/// One PDFKit line: its runs as PDFKit hands them over (text, baseline offset, font size) and its
/// rectangle (x, y, width, height).
private func item(_ runs: [(String, Double, Double)], _ rect: (Double, Double, Double, Double))
    -> BorrowedLineReference.Item {
    let text = NSMutableAttributedString(string: "")
    for (string, offset, size) in runs {
        text.append(NSAttributedString(string: string, attributes: [
            .font: pdfKitGated { PlatformFont(name: "Helvetica", size: size) }!, baselineKey: offset,
        ]))
    }
    return (text.string, CGRect(x: rect.0, y: rect.1, width: rect.2, height: rect.3), text)
}

/// Each line as `inlineText` reads it once the rule has run over the page's lines.
private func read(_ items: [BorrowedLineReference.Item]) -> [String] {
    BorrowedLineReference.rebased(items).map { EPUBTextEncoder.inline(NativeTextReader.inlineText(from: $0.attributed!)) }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/308"))
func aNumberPDFKitMeasuresFromTheSmallerTextBesideItStandsOnItsOwnBaseline() {
    // Wallace (corpus/cache/Beginning_and_Intermediate_Algebra.pdf) page 210, exercise 1: PDFKit
    // measures the row from the numerator's baseline and hands the number over alone, 6.24 below
    // it, in a rectangle exactly as tall as the numerator's piece beside it.
    let numerator = item([("20x", 0, 7.97), ("4 ", 2.88, 5.98), ("+ x", 0, 7.97), ("3 ", 2.88, 5.98),
                          ("+ 2x", 0, 7.97), ("2", 2.88, 5.98)], (100.56, 685.54, 56.93, 16.16))
    #expect(read([item([("1) ", -6.24, 11.96)], (84.96, 685.54, 10.44, 16.16)), numerator])
            == ["1)", "20x<sup>4 </sup>+ x<sup>3 </sup>+ 2x<sup>2</sup>"])
    // Page 21, exercise 21: the piece beside the number opens with `6·` on the number's own
    // baseline, and only the numerator after it stands on PDFKit's reference.
    #expect(read([item([("21) ", -6.24, 11.96)], (84.96, 372.62, 16.32, 23.70)),
                  item([("6·", -6.24, 11.96), ("− 8− 4 + (− 4)− [− 4− (− 3)]", 0, 7.97)], (105.24, 372.62, 127.63, 23.70))])
            .first == "21)")
    // The Fed (corpus/cache/the-fed-explained.pdf) page 83: a regulation's letters beside its name
    // in a table, 12 points beside 8, the letters 2.74 below the name's baseline.
    #expect(read([item([("LL ", -2.74, 12)], (99, 598.20, 12, 14.21)),
                  item([("Savings and Loan Holding Companies ", 0, 8)], (122.5, 598.20, 94.47, 14.21))])
            == ["LL", "Savings and Loan Holding Companies"])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/308"))
func aScriptBesideTheLargerTextItIsSetAgainstKeepsItsOffset() {
    // Negative controls: the text on the reference is larger, so the lone line is its script. A
    // subscript PDFKit splits from its row (#303), a note number returned as a line of its own
    // (#314) and a chemical formula's subscript.
    #expect(read([item([("For each STA", 0, 9.96)], (40, 236, 60, 14)), item([("h", -2.1, 6.97)], (101, 236, 4, 14))])
            == ["For each STA", "<sub>h</sub>"])
    #expect(read([item([("The sum was small.", 0, 10)], (40, 236, 90, 14)), item([("4", 3.5, 7)], (131, 236, 4, 14))])
            == ["The sum was small.", "<sup>4</sup>"])
    #expect(read([item([("Carbon dioxide is CO", 0, 10)], (40, 236, 100, 14)), item([("2", -2.5, 7)], (140.5, 236, 4, 14))])
            == ["Carbon dioxide is CO", "<sub>2</sub>"])
    // A line at the size of the reference text beside it: a script is set smaller than its base,
    // so nothing shows this one is not the whole row lowered.
    #expect(read([item([("the row", 0, 12)], (40, 236, 40, 14)), item([("x", -3, 11.5)], (81, 236, 6, 14))])[1]
            == "<sub>x</sub>")
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/308"))
func aLoneLineWithoutAPieceOfItsOwnRowBesideItKeepsItsOffset() {
    let number = item([("1) ", -6.24, 11.96)], (84.96, 685.54, 10.44, 16.16))
    // No piece shares its vertical extent: nothing shows what its offset is measured from.
    #expect(read([number, item([("20x", 0, 7.97)], (100.56, 685.34, 56.93, 16.36))])[0] == "<sub>1)</sub>")
    // A piece of the same extent more than one em away is another column's.
    #expect(read([number, item([("20x", 0, 7.97)], (107.5, 685.54, 56.93, 16.16))])[0] == "<sub>1)</sub>")
    // Text beside it larger than the line, or at its size on another baseline: the line may be a
    // script of that text, or of text PDFKit did not hand over beside it.
    #expect(read([number, item([("Big", 2, 14.5), ("20x", 0, 7.97)], (100.56, 685.54, 56.93, 16.16))])[0]
            == "<sub>1)</sub>")
    #expect(read([number, item([("6·", -3, 11.96), ("20x", 0, 7.97)], (100.56, 685.54, 56.93, 16.16))])[0]
            == "<sub>1)</sub>")
    // Nothing beside it stands on the reference.
    #expect(read([number, item([("20x", 2.4, 7.97)], (100.56, 685.54, 56.93, 16.16))])[0] == "<sub>1)</sub>")
    // A line holding runs on two offsets is measured by `inlineText` from what it holds (#304), not
    // moved here: Wallace page 210's `13)` beside the numerator's `v²`.
    let row = [item([("13)", -3.12, 11.96), ("v", 3.12, 7.97), ("2", 6, 5.98)], (84.96, 529.06, 29.57, 16.16)),
               item([("− 2v− 89", 0, 7.97)], (115.92, 529.06, 35.13, 16.16))]
    #expect(zip(row, BorrowedLineReference.rebased(row)).allSatisfy { $0.attributed == $1.attributed })
}

/// A 400 × 300 page setting each content stream in Helvetica.
private func page(_ content: String) -> Data {
    testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 300] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
        testPDFStream(content),
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/308"))
func anExerciseNumberBesideAnInlineFractionReadsOnTheLine() async throws {
    // Wallace page 210's exercise 1 at its own geometry: `1)` at 12 points, the numerator 6.24 up
    // at 8 with its exponents 2.88 above that, the terms 1.46 apart as TeX sets them, the bar and
    // the denominator. PDFKit breaks the row after the number and measures it from the numerator.
    // A chemical formula and a note number follow as negative controls.
    let content = """
    BT /F1 12 Tf 1 0 0 1 40 270 Tm (Divide.) Tj ET
    BT /F1 12 Tf 1 0 0 1 40 245 Tm (1\\)) Tj
    /F1 8 Tf 1 0 0 1 55.83 251.24 Tm (20x) Tj /F1 6 Tf 1 0 0 1 68.73 254.12 Tm (4) Tj
    /F1 8 Tf 1 0 0 1 73.57 251.24 Tm (+) Tj 1 0 0 1 79.7 251.24 Tm (x) Tj /F1 6 Tf 1 0 0 1 83.7 254.12 Tm (3) Tj
    /F1 8 Tf 1 0 0 1 88.54 251.24 Tm (+) Tj 1 0 0 1 94.67 251.24 Tm (2x) Tj /F1 6 Tf 1 0 0 1 103.12 254.12 Tm (2) Tj
    /F1 8 Tf 1 0 0 1 72 240.08 Tm (4x) Tj /F1 6 Tf 1 0 0 1 80.45 242.36 Tm (3) Tj ET
    55.83 248.2 m 106.5 248.2 l S
    BT /F1 12 Tf 1 0 0 1 40 190 Tm (Carbon dioxide is CO) Tj /F1 8 Tf -3 Ts (2) Tj /F1 12 Tf 0 Ts (, and the sum was small.) Tj \
    /F1 8 Tf 5 Ts (4) Tj ET
    """
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let pdf = dir.appendingPathComponent("source.pdf"), epub = dir.appendingPathComponent("book.epub")
    try page(content).write(to: pdf)

    // PDFKit hands the number over alone, 6.24 below the numerator it measures it from, in a
    // rectangle as tall as the numerator's piece beside it.
    let document = try #require(PDFDocument(url: pdf))
    let pdfPage = try #require(document.page(at: 0))
    let pieces: [(bounds: CGRect, runs: [(text: String, offset: Double, size: Double)])] = pdfKitGated {
        (pdfPage.selection(for: pdfPage.bounds(for: .cropBox))?.selectionsByLine() ?? []).map { line in
            var runs: [(text: String, offset: Double, size: Double)] = []
            if let text = line.attributedString {
                text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
                    let offset = (attributes[baselineKey] as? NSNumber)?.doubleValue ?? 0
                    let size = Double((attributes[.font] as? PlatformFont)?.pointSize ?? 0)
                    runs.append(((text.string as NSString).substring(with: range),
                                 (offset * 100).rounded() / 100, (size * 100).rounded() / 100))
                }
            }
            return (line.bounds(for: pdfPage), runs)
        }
    }
    let number = try #require(pieces.first { $0.runs.map(\.text).joined() == "1) " })
    #expect(number.runs.count == 1 && number.runs[0].offset == -6.24 && number.runs[0].size == 12)
    #expect(pieces.contains { piece in
        piece.bounds != number.bounds && abs(piece.bounds.minY - number.bounds.minY) < 0.01
            && abs(piece.bounds.maxY - number.bounds.maxY) < 0.01
            && piece.runs.first.map { $0.text == "20x" && $0.offset == 0 && $0.size == 8 } == true
    })

    // Read as a conversion reads it, the number stands on the line.
    let lines = try PageReader.read(pageIndex: 0, from: PDFPageSource(url: pdf), limit: 100_000,
                                    options: ConversionOptions(), structure: nil).content.lines
    #expect(lines.map { EPUBTextEncoder.inline($0.content) }.contains("1)"))
    let html = try await { () async throws -> String in
        _ = try await PDFConverter().convert(from: pdf, to: epub)
        return try Archive(url: epub, accessMode: .read).chapter()
    }()
    #expect(html.contains("1)") && !html.contains("<sub>1)"))
    #expect(html.contains("Carbon dioxide is CO<sub>2</sub>, and the sum was small.<sup>4</sup>"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/308"))
func rowsOfStackedScriptsPDFKitSplitsAreLeftAsTheyAre() throws {
    // #303's fixtures, whose scripts PDFKit returns in lines of their own: the rule moves none of
    // the pieces PDFKit hands over, before `SplitScriptRows` joins them.
    for content in [
        """
        BT /F1 10 Tf 40 240 Td (For each STA) Tj /F1 7 Tf 3.6 Ts (n) Tj /F1 5 Tf 6.6 Ts (i) Tj 1.5 Ts (h) Tj \
        /F1 7 Tf -2 Ts (h) Tj /F1 10 Tf 0 Ts ( in the schedule.) Tj ET
        """,
        """
        BT /F1 10 Tf 1 0 0 1 98.9 222.03 Tm (n) Tj /F1 7 Tf 1 0 0 1 104.88 226.14 Tm (1) Tj \
        1 0 0 1 104.88 219.57 Tm (f) Tj /F1 10 Tf 1 0 0 1 110.05 222.03 Tm (, n) Tj \
        /F1 7 Tf 1 0 0 1 123.22 226.14 Tm (2) Tj 1 0 0 1 123.22 219.57 Tm (f) Tj \
        /F1 10 Tf 1 0 0 1 128.39 222.03 Tm (, ..., n) Tj /F1 7 Tf 1 0 0 1 153.41 227.49 Tm (N) Tj \
        /F1 5 Tf 1 0 0 1 158.46 226.43 Tm (f) Tj /F1 7 Tf 1 0 0 1 153.41 219.02 Tm (f) Tj \
        /F1 10 Tf 1 0 0 1 160.4 222.03 Tm (.) Tj 1 0 0 1 250 222.03 Tm (\\(1\\)) Tj ET
        """,
    ] {
        let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("source.pdf")
        try page(content).write(to: url)
        let document = try #require(PDFDocument(url: url))
        let pdfPage = try #require(document.page(at: 0))
        let items: [BorrowedLineReference.Item] = pdfKitGated {
            (pdfPage.selection(for: pdfPage.bounds(for: .cropBox))?.selectionsByLine() ?? []).map { line in
                (line.string ?? "", line.bounds(for: pdfPage), line.attributedString)
            }
        }
        #expect(items.count > 1)
        let rebased = BorrowedLineReference.rebased(items)
        #expect(zip(items, rebased).allSatisfy { $0.attributed == $1.attributed })
    }
}
