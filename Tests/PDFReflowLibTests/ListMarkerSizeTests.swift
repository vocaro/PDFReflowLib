import Foundation
import Testing
@testable import PDFReflowLib

// A list marker is drawn at its own size and must not state the line's (#183).

private func marked(marker: String, markerSize: Double, text: String, textSize: Double) -> NSAttributedString {
    let result = NSMutableAttributedString(string: marker, attributes: [
        .font: pdfKitGated { PlatformFont(name: "Helvetica", size: markerSize) }!,
    ])
    result.append(NSAttributedString(string: text, attributes: [
        .font: pdfKitGated { PlatformFont(name: "Helvetica", size: textSize) }!,
    ]))
    return result
}

private func size(_ attributed: NSAttributedString) -> CGFloat {
    NativeTextReader.textLine(semantic: attributed.string,
                              bounds: CGRect(x: 40, y: 400, width: 300, height: 12),
                              attributed: attributed).fontSize
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/183")) func aBulletLargerThanItsItemDoesNotStateTheLineSize() {
    // The Fed's page 58 sets a 10-point bullet over 8-point text on 14 lines.
    #expect(size(marked(marker: "• ", markerSize: 10, text: "an item set smaller than its bullet", textSize: 8)) == 8)
    // IRS Publication 596 sets one large enough that its bulleted sentences read as headings.
    #expect(size(marked(marker: "• ", markerSize: 14, text: "您提交了附表 E（表格 1040）。", textSize: 9)) == 9)
    #expect(size(marked(marker: "− ", markerSize: 12, text: "a dash item", textSize: 9)) == 9)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/183")) func nothingElseAtTheStartOfALineIsTreatedAsAMarker() {
    // A marker smaller than its text understates the line the same way, but correcting it here
    // promotes IRS Publication 596's starred footnotes into headings, so it is left alone.
    #expect(size(marked(marker: "* ", markerSize: 6, text: "a footnote set larger than its star", textSize: 9)) == 6)
    // A drop cap, an opening quotation mark and a contents line's leaders are not markers: each
    // keeps the size its first character gives, as before.
    #expect(size(marked(marker: "T", markerSize: 44, text: "he opening of a paragraph.", textSize: 9)) == 44)
    #expect(size(marked(marker: "“I", markerSize: 18, text: " PLEDGE ALLEGIANCE", textSize: 18)) == 18)
    #expect(size(marked(marker: "1 Overview", markerSize: 12, text: " . . . . . 1", textSize: 7)) == 12)
    // A marker with no text after it states the line, having nothing else to state it.
    #expect(size(marked(marker: "• ", markerSize: 10, text: "", textSize: 8)) == 10)
}
