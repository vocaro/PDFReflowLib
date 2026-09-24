import Foundation
import Testing
@testable import PDFReflowLib

// Geometry follows the intact PDFKit columns on TUFS Hoshino p1 (#44): 12-point-wide,
// 323-point-tall body columns with descending x positions, a vertical title and author, and
// horizontal journal running heads above them. The text is synthetic.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/44"))
func intactJapaneseBodyColumnsCarryTheirDirection() {
    let prose = String(repeating: "日本語の文章を縦に読んでいます。", count: 3)
    let header = TextLine(text: "東京外国語大学", rect: CGRect(x: 194, y: 800, width: 240, height: 12), fontSize: 12)
    let title = TextLine(text: "日本語で考えることと言葉にすること",
                         rect: CGRect(x: 508, y: 230, width: 30, height: 527), fontSize: 14)
    let author = TextLine(text: "報告者の名前", rect: CGRect(x: 472, y: 148, width: 14, height: 98), fontSize: 12)
    let body = (0..<6).map { index in
        TextLine(text: prose, rect: CGRect(x: 430 - index * 18, y: 420 - index, width: 12, height: 323),
                 fontSize: 12)
    }
    let oriented = VerticalJapaneseColumns.oriented([header, title, author] + body,
                                                    language: "ja", pageWidth: 595)
    #expect(oriented[0].turn == .upright)
    #expect(oriented.dropFirst().allSatisfy { $0.turn == .clockwise })
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/44"))
func sparseOrHorizontalJapaneseDoesNotStateVerticalProse() {
    let prose = String(repeating: "日本語の文章を読みます。", count: 4)
    let horizontal = (0..<8).map { index in
        TextLine(text: prose, rect: CGRect(x: 50, y: 700 - index * 18, width: 360, height: 12), fontSize: 12)
    }
    #expect(VerticalJapaneseColumns.oriented(horizontal, language: "ja", pageWidth: 595) == horizontal)

    let margin = [TextLine(text: prose, rect: CGRect(x: 520, y: 350, width: 12, height: 300), fontSize: 12)]
        + horizontal
    #expect(VerticalJapaneseColumns.oriented(margin, language: "ja", pageWidth: 595) == margin)

    let tableHeads = (0..<6).map { index in
        TextLine(text: "日本語の表題", rect: CGRect(x: 430 - index * 35, y: 550, width: 12, height: 85), fontSize: 12)
    }
    #expect(VerticalJapaneseColumns.oriented(tableHeads, language: "ja", pageWidth: 595) == tableHeads)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/44"))
func fragmentedTategakiNeedsASeparateFallback() {
    // The Overleaf p1 PDFKit baseline returns 320 selections, mostly one glyph per 11-by-10
    // rectangle. Labelling those fragments with a turn cannot reconstruct their columns.
    let fragments = (0..<320).map { index in
        TextLine(text: "日", rect: CGRect(x: 41 + (index / 40) * 18,
                                         y: 473 - (index % 40) * 11, width: 11, height: 10), fontSize: 10)
    }
    #expect(VerticalJapaneseColumns.oriented(fragments, language: "ja", pageWidth: 420) == fragments)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/44"))
func horizontalFolioOutsideNativeVerticalBodyKeepsTheTwoPrintedBandsInOrder() {
    func line(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat,
              turn: QuarterTurn = .upright) -> LayoutReconstructor.Element {
        let item = TextLine(text: text, rect: CGRect(x: x, y: y, width: width, height: height),
                            fontSize: 12, turn: turn)
        return .init(rect: item.rect, line: item)
    }
    let header = line("journal", x: 194, y: 800, width: 240, height: 12)
    let title = line("title", x: 508, y: 230, width: 30, height: 527, turn: .clockwise)
    let author = line("author", x: 472, y: 148, width: 14, height: 98, turn: .clockwise)
    let prose = String(repeating: "日本語の文章を縦に読んでいます。", count: 3)
    let upper = (0..<6).map { index in
        line(prose + " upper\(index)", x: 430 - CGFloat(index) * 18, y: 420, width: 12, height: 323,
             turn: .clockwise)
    }
    let lower = (0..<6).map { index in
        line(prose + " lower\(index)", x: 412 - CGFloat(index) * 18, y: 56, width: 12, height: 336,
             turn: .clockwise)
    }
    let footer = line("licence", x: 109, y: 23, width: 327, height: 12)
    let graphic = LayoutReconstructor.Element(rect: CGRect(x: 62, y: 28, width: 42, height: 15),
                                               image: "licence-mark")
    let elements = [header, title, author] + upper + lower + [footer, graphic]
    let order = LayoutReconstructor.ordered(elements, bodySize: 12)
        .map { $0.line?.text.split(separator: " ").last.map(String.init) ?? $0.image! }
    #expect(Array(order.prefix(15)) == ["journal", "title", "author"]
        + (0..<6).map { "upper\($0)" } + (0..<6).map { "lower\($0)" })
    #expect(Set(order.suffix(2)) == ["licence", "licence-mark"])
    let sourceLines = elements.compactMap(\.line)
    #expect(!VerticalJapaneseColumns.needsImageFallback(sourceLines,
        regions: [graphic.rect], language: "ja"))

    // A horizontal note or table inside the vertical body band makes its relationship to
    // individual columns ambiguous; the isolated-band rule must decline the mixed page.
    let interior = line("horizontal inset", x: 200, y: 500, width: 120, height: 12)
    #expect(VerticalJapaneseColumns.needsImageFallback(sourceLines + [interior.line!],
        regions: [graphic.rect], language: "ja"))
    #expect(VerticalJapaneseColumns.needsImageFallback(sourceLines,
        regions: [CGRect(x: 200, y: 500, width: 120, height: 80)], language: "ja"))
    #expect(!VerticalJapaneseColumns.needsImageFallback(sourceLines + [interior.line!],
        regions: [graphic.rect], language: "en"))
    let guarded = LayoutReconstructor.ordered(elements + [interior], bodySize: 12)
        .map { $0.line?.text.split(separator: " ").last.map(String.init) ?? $0.image! }
    #expect(guarded != order + ["inset"])
}
