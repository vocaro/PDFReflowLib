import CoreText
import Foundation
import PDFKit
import Testing
import ZIPFoundation
@testable import PDFReflowLib

// First-level scripts measured from the text they are set against, not from PDFKit's line
// reference, and TeX superscripts raised over a stack of their own (#304).

/// Each tuple is one run as PDFKit hands it over: text, baseline offset, font size.
private func runs(_ values: [(String, Double, Double)]) -> String {
    let input = NSMutableAttributedString(string: "")
    for (index, value) in values.enumerated() {
        let (text, offset, size) = value
        input.append(NSAttributedString(string: text, attributes: [
            .font: pdfKitGated { PlatformFont(name: "Helvetica", size: size) }!,
            NSAttributedString.Key(kCTBaselineOffsetAttributeName as String): offset,
            NSAttributedString.Key("test.run"): index,
        ]))
    }
    return EPUBTextEncoder.inline(NativeTextReader.inlineText(from: input))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/304"))
func aScriptIsMeasuredFromTheTextItIsSetAgainst() {
    // Wallace (corpus/cache/Beginning_and_Intermediate_Algebra.pdf) page 178, Example 202: PDFKit
    // measures `a²` from the exponent's baseline, so `a` read lowered and `2` flat.
    #expect(runs([("a", -4.32, 11.96), ("2", 0, 7.97)]) == "a<sup>2</sup>")
    // Page 178, Example 201: the reference halfway between, every base at −2.16.
    #expect(runs([("5a", -2.16, 11.96), ("3", 2.16, 7.97), ("b", -2.16, 11.96), ("5", 2.16, 7.97),
                  ("c", -2.16, 11.96), ("2", 2.16, 7.97)]) == "5a<sup>3</sup>b<sup>5</sup>c<sup>2</sup>")
    // Page 178, Example 200's denominator 7⁵, both runs below the reference.
    #expect(runs([("7", -7.80, 11.96), ("5", -4.32, 7.97)]) == "7<sup>5</sup>")
    // A base PDFKit places above its reference carries a subscript at the reference.
    #expect(runs([("x", 3, 12), ("i", 0, 8), (" = 0", 3, 12)]) == "x<sub>i</sub> = 0")
    // DASC (corpus/cache/20190030725.pdf) page 5, display (8): `STA` at −2.71 and its superscript
    // at +2.71 read `<sub>STA</sub><sup>n…`; display (10): `A` at −7.90 and `n` at −1.50 read
    // `A<sub>n…` where the page raises n.
    #expect(runs([("STA", -2.71, 9.96), ("n", 2.71, 6.97), ("i", 5.72, 4.98)]) == "STA<sup>n<sup>i</sup></sup>")
    #expect(runs([("A", -7.90, 9.96), ("n", -1.50, 6.97), ("i", 1.50, 4.98)]) == "A<sup>n<sup>i</sup></sup>")
    // DASC page 6: the outer subscript `f` of the STA before, which PDFKit hands over at the start
    // of this line, is lowered from the text it stands beside, not from the reference.
    #expect(runs([("f", -7.41, 6.97), ("= STA", -4.40, 9.96), ("r", 1.06, 6.97), ("f", 0, 4.98), ("(k)", 1.06, 6.97)])
            == "<sub>f</sub>= STA<sup>r<sub>f</sub>(k)</sup>")
    // Chemical formulas, ordinals and note markers read the same on a shifted reference.
    #expect(runs([("C", -3, 12), ("6", -6, 8), ("H", -3, 12), ("12", -6, 8), ("O", -3, 12), ("6", -6, 8)])
            == "C<sub>6</sub>H<sub>12</sub>O<sub>6</sub>")
    #expect(runs([("the 21", -4, 12), ("st", 0, 8), (" century", -4, 12)]) == "the 21<sup>st</sup> century")
    #expect(runs([("at 7:45.", -4, 12), ("4", 0, 8), (" In another", -4, 12)]) == "at 7:45.<sup>4</sup> In another")
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/304"))
func aTeXSuperscriptCarryingAScriptOfItsOwnIsRaisedPastItsOwnSize() {
    // DASC page 5, "For each STA^{n^i_h}_h": n is 6.97 points raised 5.42, past three quarters of
    // its size (5.23), because TeX raises a superscript that carries its own scripts.
    #expect(runs([("For each STA", 0, 9.96), ("n", 5.42, 6.97), ("i", 8.43, 4.98), (" occurring", 0, 9.96)])
            == "For each STA<sup>n<sup>i</sup></sup> occurring")
    // Page 5, `A^{n^i_f,j}_f`: n raised 6.39; `,j` resumes at n's height after the second level.
    #expect(runs([("windows A", 0, 9.96), ("n", 6.39, 6.97), ("i", 9.40, 4.98), (",j", 6.39, 6.97), (" satisfy", 0, 9.96)])
            == "windows A<sup>n<sup>i</sup>,j</sup> satisfy")
    // Page 6, `STA^{r_f(k)}_f`: r raised 5.46 over its own lowered f.
    #expect(runs([("If every computed STA", 0, 9.96), ("r", 5.46, 6.97), ("f ", 4.40, 4.98), ("(k)", 5.46, 6.97)])
            == "If every computed STA<sup>r<sub>f </sub>(k)</sup>")
    // Both at once: page 6 hands over the same superscript on a reference at r's baseline.
    #expect(runs([("STA", -5.46, 9.96), ("r", 0, 6.97), ("f ", -1.06, 4.98), ("(k+1)", 0, 6.97)])
            == "STA<sup>r<sub>f </sub>(k+1)</sup>")
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/304"))
func numeratorsAndRunsOnAnotherBaselineAreNotScripts() {
    // Negative controls. Wallace page 51, `E = mv²/2` set inline: a numerator starts a new operand
    // after `=`, although it carries an exponent of its own.
    #expect(runs([("10) E =", 0, 11.96), ("mv", 6.24, 7.97), ("2", 9.12, 5.98)]) == "10) E =mv2")
    // Page 187, exercise 13: a numerator carrying exponents beside the problem number, which
    // PDFKit places 6.24 below the reference. The numerator is not raised over `13)`.
    let exercise = runs([("13)", -6.24, 11.96), ("u", 0, 7.97), ("2", 2.88, 5.98), ("v ", 0, 7.97), ("1", 2.88, 5.98)])
    #expect(!exercise.contains("<sup>u") && exercise.contains("u<sup>2</sup>v <sup>1</sup>"))
    // Page 14, the mixed number 1½, and page 245, a fraction after `the solution`: numerators after
    // a digit or a letter carry no second level of their own and stay on the line.
    #expect(runs([("the mixed number 1", 0, 11.96), ("1", 6.24, 7.97)]) == "the mixed number 11")
    #expect(runs([("the solution", 0, 11.96), ("x− 5", 6.12, 7.97)]) == "the solutionx− 5")
    // Nor is a smaller run a line's distance below such a numerator its second level.
    #expect(!runs([("so x", 0, 11.96), ("mv", 6.24, 7.97), ("2", -4.8, 5.98)]).contains("<sup>mv"))
    // Replay Clocks (corpus/cache/2311.07842v1.pdf) page 5, ⌊mpt.f / I⌋: a numerator after an
    // opening bracket is not measured from the bracket.
    #expect(!runs([("∴−1 < (", -4.76, 8.97), ("𝑚𝑝𝑡.𝑓", 0, 7.27)]).contains("<sup>"))
    // Census (corpus/cache/rrs2002-01.pdf) page 18: PDFKit measures a sum sign from its top, 7.44
    // above the line's text, and its upper limit K reads lower than the sign. Body text on two
    // baselines leaves the reference where PDFKit put it, wherever in the line the sign stands.
    #expect(!runs([("mixture distribution ", 0, 10.08), ("S", 7.44, 10.08), ("K", 5.04, 7.08)]).contains("<sub>"))
    #expect(!runs([("S", 7.44, 10.08), ("K", 5.04, 7.08), (" over the components", 0, 10.08)]).contains("<sub>"))
    // A body-size run shifted by a full line, with a smaller run after it, is no base.
    #expect(runs([("Upper line", 14, 12), ("x", 0, 8), (" lower line", 0, 12)]) == "Upper linex lower line")
    #expect(!runs([("line one", 0, 12), ("2", 4, 8), ("line two", -14, 12), ("3", -10, 8)]).contains("<sub>"))
}

/// A PDF of one Helvetica page per content stream.
private func pagesPDF(_ contents: [String]) -> Data {
    let pages = contents.indices.map { index in
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 300] /Resources << /Font << /F1 3 0 R >> >> /Contents \(5 + 2 * index) 0 R >>"
    }
    let kids = contents.indices.map { "\(4 + 2 * $0) 0 R" }.joined(separator: " ")
    return testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [\(kids)] /Count \(contents.count) >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ] + zip(pages, contents).flatMap { [$0, testPDFStream($1)] })
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/304"))
func aPageSettingScriptsOffPDFKitsReferenceReadsThemFromTheirBase() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let pdf = dir.appendingPathComponent("source.pdf"), epub = dir.appendingPathComponent("book.epub")
    // One row to a page: PDFKit's reference for a row depends on the rows around it. Text rise
    // (`Ts`) is each run's whole baseline offset.
    try pagesPDF([
        // Wallace page 178's a².
        "BT /F1 12 Tf 40 150 Td (a) Tj /F1 8 Tf 4.32 Ts (2) Tj ET",
        // DASC page 5's STA^{n^i}, and A^{n^i}, each on a reference off the base.
        "BT /F1 10 Tf 40 150 Td (STA) Tj /F1 7 Tf 5.42 Ts (n) Tj /F1 5 Tf 8.43 Ts (i) Tj ET",
        "BT /F1 10 Tf 40 150 Td (A) Tj /F1 7 Tf 6.39 Ts (n) Tj /F1 5 Tf 9.40 Ts (i) Tj ET",
        // DASC page 6's STA^{r_f(k+1)}.
        "BT /F1 10 Tf 40 150 Td (STA) Tj /F1 7 Tf 5.46 Ts (r) Tj /F1 5 Tf 4.40 Ts (f) Tj /F1 7 Tf 5.46 Ts (\\(k+1\\)) Tj ET",
        // DASC page 5's A^{n^i,j} in running text, on the text's own baseline.
        "BT /F1 10 Tf 40 150 Td (Windows A) Tj /F1 7 Tf 6.39 Ts (n) Tj /F1 5 Tf 9.40 Ts (i) Tj /F1 7 Tf 6.39 Ts (,j) Tj "
            + "/F1 10 Tf 0 Ts ( satisfy all.) Tj ET",
        // Negative controls: a mixed number's numerator, and a numerator carrying an exponent beside
        // a problem number PDFKit places below the reference (Wallace pages 369 and 187).
        "BT /F1 12 Tf 40 150 Td (It fills in 4) Tj /F1 8 Tf 6.24 Ts (1) Tj /F1 12 Tf 0 Ts ( hours.) Tj ET",
        "BT /F1 12 Tf 40 150 Td (13\\)) Tj /F1 8 Tf 6.24 Ts (u) Tj /F1 6 Tf 9.12 Ts (2) Tj /F1 8 Tf 6.24 Ts (v) Tj ET",
    ]).write(to: pdf)

    // PDFKit states the bases off its line reference, as on the source pages: that is what is read.
    let document = try #require(PDFDocument(url: pdf))
    let offsets: [[Double]] = try [0, 1, 2, 3].map { index in
        let page = try #require(document.page(at: index))
        let line = try #require(pdfKitGated {
            page.selection(for: page.bounds(for: .cropBox))?.selectionsByLine().first?.attributedString
        })
        var offsets: [Double] = []
        line.enumerateAttributes(in: NSRange(location: 0, length: line.length)) { attributes, _, _ in
            offsets.append((attributes[NSAttributedString.Key(kCTBaselineOffsetAttributeName as String)] as? NSNumber)?.doubleValue ?? 0)
        }
        return offsets.map { ($0 * 100).rounded() / 100 }
    }
    #expect(offsets[0] == [-4.32, 0])
    #expect(offsets[1] == [-2.71, 2.71, 5.72])
    #expect(offsets[2] == [-7.89, -1.5, 1.51])
    #expect(offsets[3] == [-5.46, 0, -1.06, 0])

    let report = try await PDFConverter().convert(from: pdf, to: epub)
    #expect(report.imageCount == 0 && report.reflowedPageCount == 7)
    let html = try Archive(url: epub, accessMode: .read).chapter()
    #expect(html.contains("<p>a<sup>2</sup></p>"))
    #expect(html.contains("<p>STA<sup>n<sup>i</sup></sup></p>"))
    #expect(html.contains("<p>A<sup>n<sup>i</sup></sup></p>"))
    #expect(html.contains("<p>STA<sup>r<sub>f</sub>(k+1)</sup></p>"))
    #expect(html.contains("Windows A<sup>n<sup>i</sup>,j</sup> satisfy all."))
    #expect(html.contains("It fills in 41 hours."))
    #expect(html.contains("u<sup>2</sup>v") && !html.contains("<sup>u"))
}
