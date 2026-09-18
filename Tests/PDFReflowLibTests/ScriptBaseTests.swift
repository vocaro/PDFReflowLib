import CoreGraphics
import CoreText
import Foundation
import Testing
#if os(macOS)
import AppKit
private typealias ScriptFont = NSFont
#else
import UIKit
private typealias ScriptFont = UIFont
#endif
@testable import PDFReflowLib

// Fed pages 82/83 (#138): each regulation letter is a 12-point cell label top-aligned with its
// 8-point name, so PDFKit reports it 2.74 points below the name's baseline (`F ` beside `Limitations
// on Interbank Liabilities`), or alone in its selection when the name is a separate one (`KK `). It
// was written `<sub>F</sub>`. A script is set no larger than the text it is shifted from, so a
// shifted run needs another visible run of at least nearly its size in its selection.

private func line(_ runs: [(String, Double, Double)]) -> NSAttributedString {
    let value = NSMutableAttributedString(string: "")
    for (text, size, offset) in runs {
        value.append(NSAttributedString(string: text, attributes: [
            .font: pdfKitGated { ScriptFont(name: "Helvetica", size: size) }!,
            NSAttributedString.Key(kCTBaselineOffsetAttributeName as String): offset,
        ]))
    }
    return value
}

private func html(_ runs: [(String, Double, Double)]) -> String {
    EPUBTextEncoder.inline(NativeTextReader.inlineText(from: line(runs)))
}

@Test func fedRegulationLettersAreCellTextNotSubscripts() throws {
    let fixture = try SourceLayoutFixture.load("fed-83")
    // Fifteen letters on the page: six beside their names, nine (`LL` to `YY`) alone in their selections.
    let letters = fixture.attributedLines.filter { $0.runs.contains { $0.fontSize == 12 && $0.baselineOffset < -2 } }
    #expect(letters.count == 15)
    for source in letters {
        let model = NativeTextReader.inlineText(from: source.attributedString())
        #expect(model.text == source.text.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(!EPUBTextEncoder.inline(model).contains("<su"), "\(source.text)")
    }
    // Through reconstruction: the regulation table's cells carry no script markup.
    let page = fixture.styledContent()
    let regions = LayoutReconstructor.graphicsWithLabels(page)
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: regions.enumerated().map { ($0.element, "image-\($0.offset)") },
        vocabulary: LayoutReconstructor.vocabulary(in: [page]), warnings: &warnings)
    let table = try #require(blocks.compactMap { if case let .table(table) = $0.content { table } else { nil } }.first)
    let markup = EPUBTextEncoder.table(table)
    #expect(markup.contains(">Y Bank Holding Companies and Change in Bank"))
    #expect(markup.contains(">LL "))
    #expect(!markup.contains("<sub>") && !markup.contains("<sup>"))
}

@Test func shiftedRunsWithoutABaseOfTheirSizeAreNotScripts() {
    // A larger lowered or raised run beside smaller text, and a shifted run alone in its selection.
    #expect(html([("F ", 12, -2.744), ("Limitations on Interbank Liabilities ", 8, 0)]) == "F Limitations on Interbank Liabilities")
    #expect(html([("KK ", 12, -2.744)]) == "KK")
    #expect(html([("housing. ", 10, 5.25)]) == "housing.")
    #expect(html([("8x", 12, -2.16), ("3", 8, 2.16)]) == "8x<sup>3</sup>")
    // Whitespace is no base.
    #expect(html([("KE = mv", 10, -5), ("2", 7, 3), (" ", 10, 0)]) == "KE = mv<sup>2</sup>")
}

@Test func scriptsBesideTheirBaseAreUnchanged() throws {
    // Smaller scripts, a same-size script and one set slightly larger than its base still read.
    #expect(html([("H", 12, 0), ("2", 8, -3), ("O and x", 12, 0), ("2", 8, 4)]) == "H<sub>2</sub>O and x<sup>2</sup>")
    #expect(html([("x", 12, 0), ("upper", 12, 8), ("lower", 12, -8), ("base", 12, 0)]) == "x<sup>upper</sup><sub>lower</sub>base")
    #expect(html([("V", 10, 0), ("SO", 10.5, -2)]) == "V<sub>SO</sub>")
    // One tenth larger is the limit.
    #expect(html([("V", 10, 0), ("SO", 11.5, -2)]) == "VSO")
    // Source controls: a 9/11 endnote marker and its split closing-quote marker.
    let note = try #require(try SourceLayoutFixture.load("911-20").attributedLines.first { $0.text.contains("7:45.") })
    #expect(EPUBTextEncoder.inline(NativeTextReader.inlineText(from: note.attributedString())).contains("7:45.<sup>4</sup>"))
    let quote = try #require(try SourceLayoutFixture.load("911-362").attributedLines.first { $0.text == "”12" })
    #expect(EPUBTextEncoder.inline(NativeTextReader.inlineText(from: quote.attributedString())) == "”<sup>12</sup>")
}
