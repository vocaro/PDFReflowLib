import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// Answer keys numbered down their columns read down them (#178), and a drawing keeps its own
// vertex and side labels (#179). Both are Wallace's answer sections: the keys set short numeric
// entries in two or three columns under a title that runs across every gutter, and the
// trigonometry answers draw a right triangle for each exercise and letter its vertices a word
// space from the ink. Fixtures are native extraction from the checksum-pinned book; every
// expected number, label and order was read from the rendered source page.

private let algebraSHA256 = "856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678"

private func keyPage(_ name: String) throws -> PageContent {
    let fixture = try SourceLayoutFixture.load(name)
    #expect(fixture.sourceSHA256 == algebraSHA256)
    var page = fixture.content()
    page.lines.removeAll { $0.text == String(fixture.page) }   // the folio the furniture pass removes
    return page
}

private func reconstruct(_ name: String) throws -> (page: PageContent, blocks: [ReflowBlock], crops: [CGRect]) {
    let page = try keyPage(name)
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: crops.enumerated().map { ($0.element, "image-\($0.offset)") },
        vocabulary: [], warnings: &warnings)
    return (page, blocks, crops)
}

/// The entry numbers the page reflows as text, in reading order.
private func entryNumbers(_ blocks: [ReflowBlock]) -> [Int] {
    blocks.compactMap { block in
        let text = block.text.trimmingCharacters(in: .whitespaces)
        guard let range = text.range(of: #"^[0-9]{1,3}(?=\))"#, options: .regularExpression) else { return nil }
        return Int(text[range])
    }
}

/// Whether `numbers` never steps backwards: an answer key read down its columns counts up, while
/// one read across its rows returns to the left column's next entry after the right column's.
private func countsUp(_ numbers: [Int]) -> Bool {
    zip(numbers, numbers.dropFirst()).allSatisfy { $1 > $0 }
}

// MARK: - #178, keys numbered down their columns

// Page 465 stacks two keys. The first prints 11–26 down the left column and 27–42 down the right;
// the second, "Answers - Solve by Factoring", prints 1–12, 13–24 and 25–34 down three columns.
// The titles bridge every gutter and the keys sit 4.6 pt apart, so the page found no cut at all and
// read `11)`, `27)`, `12)`, `28)`… and then `7)`, `30)`, `31)`, `21)`, `32)`, `22)`… along its rows.
@Test func stackedAnswerKeysReadDownTheirColumns() throws {
    let result = try reconstruct("algebra-465")
    let numbers = entryNumbers(result.blocks)
    // The first key's thirty-two entries, in printed order, then the second key's.
    #expect(Array(numbers.prefix(32)) == Array(11...42))
    #expect(countsUp(Array(numbers.dropFirst(32))))
    for entry in ["11) n(n− 1)", "26) (4m− n)(16m2 +4mn +n2)", "27) (3x− 4)(9x2 + 12x +16)",
                  "42) v2(2u− 5v)(u− 3v)", "1) 7,− 2", "24) 4, 0"] {
        #expect(result.blocks.contains { $0.text.trimmingCharacters(in: .whitespaces) == entry }, "lost \(entry)")
    }
    // Entry 22's second line is set beneath the first and stays with it, not with the next column.
    let texts = result.blocks.map(\.text)
    let split = try #require(texts.firstIndex(of: "22) (4m +3n)(16m2"))
    #expect(texts[split + 1].contains("− 12mn +9n2)"))
    #expect(texts.contains("Answers - Solve by Factoring"))
}

// Page 486's second key, "Answers - Exponential Functions": 1–14, 15–28 and 29–40 down three
// columns, where a fraction answer is a preserved crop so a row mixes text entries and images.
// It read `1) 0`, `15) 1`, `29) 0`, `2)− 1`… The first key on the page, whose middle and right
// columns are entirely crops, carries no numbering evidence and is unchanged.
@Test func aThreeColumnAnswerKeyMixedWithCropsReadsDownItsColumns() throws {
    let result = try reconstruct("algebra-486")
    let texts = result.blocks.map(\.text)
    let title = try #require(texts.firstIndex(of: "Answers - Exponential Functions"))
    let key = entryNumbers(Array(result.blocks[title...]))
    #expect(countsUp(key))
    #expect(key.first == 1 && key.last == 40)
    for entry in ["1) 0", "12) 0", "15) 1", "17) No solution", "29) 0", "40) No solution"] {
        #expect(texts.contains(entry), "lost \(entry)")
    }
    // The title heads the key rather than reading inside it.
    #expect(entryNumbers(Array(result.blocks[..<title])).allSatisfy { (3...9).contains($0) })
}

// Page 463 stacks three keys, the last of them only four entries wide. Each is cut on its own.
@Test func everyKeyOfAPageIsCutOnItsOwn() throws {
    let result = try reconstruct("algebra-463")
    let texts = result.blocks.map(\.text)
    let second = try #require(texts.firstIndex(of: "6.4"))
    let third = try #require(texts.firstIndex(of: "6.5"))
    #expect(entryNumbers(Array(result.blocks[..<second])) == Array(7...34))
    #expect(entryNumbers(Array(result.blocks[second..<third])) == Array(1...40))
    #expect(entryNumbers(Array(result.blocks[third...])) == Array(1...4))
}

// The rule itself, at page 486's measured geometry: three columns at x 85, 233 and 382, the first
// numbered 1–14 down the column, the second 15–28 and the third 29–40.
@Test func onlyNumbersRunningDownTheColumnsReadDownThem() {
    func markers(_ columns: [[Int]], edges: [CGFloat] = [85, 233, 382]) -> [(rect: CGRect, number: Int)] {
        columns.enumerated().flatMap { column, numbers in
            numbers.enumerated().map { row, number in
                (CGRect(x: edges[column], y: 390 - CGFloat(row) * 22, width: 26, height: 12), number)
            }
        }
    }
    func reads(_ columns: [[Int]], edges: [CGFloat] = [85, 233, 382]) -> Bool {
        LayoutReconstructor.readsDownColumns(markers(columns, edges: edges), bodySize: 12)
    }
    #expect(reads([[1, 2, 3, 4], [15, 16, 17], [29, 30, 31]]))
    #expect(reads([[1, 2], [15, 16]]))
    // #78's grids are numbered along their rows, so the columns' numbers interleave.
    #expect(!reads([[15, 18, 21], [16, 19, 22], [17, 20, 23]]))
    #expect(!reads([[1, 3, 5], [2, 4, 6]]))
    // A column that counts down, a repeated number, a single column and a column of one entry.
    #expect(!reads([[4, 3, 2, 1], [15, 16]]))
    #expect(!reads([[1, 2, 2], [15, 16]]))
    #expect(!reads([[1, 2, 3, 4]]))
    #expect(!reads([[1, 2, 3], [15]]))
    // Two runs on one edge are one column, not two: the edges must stand 1.5 bodies apart.
    #expect(!reads([[1, 2, 3], [15, 16, 17]], edges: [85, 95]))
}

// The band itself: only a numbering that restarts marks a key boundary, so a band inside one key
// and a key the entries above continue give none, and a key numbered along its rows gives none at
// any band.
@Test func aKeyBandNeedsANumberingThatRestarts() {
    func element(_ text: String, x: CGFloat, y: CGFloat) -> LayoutReconstructor.Element {
        LayoutReconstructor.Element(rect: CGRect(x: x, y: y, width: 26, height: 12),
                                    line: TextLine(text: text, rect: CGRect(x: x, y: y, width: 26, height: 12), fontSize: 12))
    }
    // Page 486's geometry: one key of 3–9 in a single column over a second key of 1–12 in three,
    // with a 9.6-pt band between them.
    func key(_ columns: [[Int]], top: CGFloat) -> [LayoutReconstructor.Element] {
        columns.enumerated().flatMap { column, numbers in
            numbers.enumerated().map { row, number in
                element("\(number)) 0", x: [85, 233, 382][column], y: top - CGFloat(row) * 22)
            }
        }
    }
    let upper = key([[3, 4, 5, 6, 7, 8, 9]], top: 600)
    let lower = key([[1, 2, 3, 4], [15, 16, 17, 18], [29, 30, 31, 32]], top: 400)
    #expect(LayoutReconstructor.numberedKeyBand(upper + lower, bodySize: 12) != nil)
    // One key alone: every band inside it leaves the key's own first entry above, so what is
    // below opens higher and no band reads as a boundary.
    #expect(LayoutReconstructor.numberedKeyBand(lower, bodySize: 12) == nil)
    // A key the upper entries continue is one key, not two.
    #expect(LayoutReconstructor.numberedKeyBand(key([[1, 2, 3, 4, 5, 6, 7]], top: 600)
        + key([[8, 9, 10, 11], [15, 16, 17, 18], [29, 30, 31, 32]], top: 400), bodySize: 12) == nil)
    // A grid numbered along its rows is refused, above the band and below it.
    #expect(LayoutReconstructor.numberedKeyBand(upper
        + key([[1, 4, 7, 10], [2, 5, 8, 11], [3, 6, 9, 12]], top: 400), bodySize: 12) == nil)
    // A figure spanning the whitespace between the keys binds them: no band runs between them,
    // and the bands inside the lower key open higher than the entries above them.
    var bridged = upper + lower
    bridged.append(LayoutReconstructor.Element(rect: CGRect(x: 85, y: 380, width: 26, height: 220),
                                               image: "spanning-figure"))
    #expect(LayoutReconstructor.numberedKeyBand(bridged, bodySize: 12) == nil)
    // Too few entries below to be a key of columns.
    #expect(LayoutReconstructor.numberedKeyBand(upper + key([[1, 2], [15]], top: 400), bodySize: 12) == nil)
    // Fewer than six markers on the region is too little of a key to read a boundary from.
    #expect(LayoutReconstructor.numberedKeyBand(key([[9]], top: 600)
        + key([[1, 2], [15, 16]], top: 400), bodySize: 12) == nil)
}

// MARK: - #179, a drawing's own labels

// Page 427 sets four right triangles, each lettered `A`, `B` and `C` with a side length and an
// angle. The labels that happened to touch the crop joined it under #46/#48; these stand
// 1.6–5.2 pt clear, a real word space, and reflowed as one-character paragraphs beside the image.
@Test func triangleVertexLettersJoinTheirTriangle() throws {
    let result = try reconstruct("algebra-427")
    for line in result.page.lines where ["A", "B", "C"].contains(line.text.trimmingCharacters(in: .whitespaces)) {
        #expect(result.crops.contains { $0.intersects(line.rect) }, "\(line.text) is outside every crop")
    }
    let texts = result.blocks.map { $0.text.trimmingCharacters(in: .whitespaces) }
    #expect(!texts.contains { ["A", "B", "C", "x", "11", "1.4", "13.1", "18.1"].contains($0) })
    // Each exercise number stays a text entry before its own diagram.
    for number in 37...40 {
        #expect(texts.contains("\(number))"), "lost exercise number \(number))")
    }
    let images = result.blocks.filter { if case .image = $0.content { true } else { false } }
    #expect(images.count == 4)
}

// The side lengths of page 424's triangles join them too, while its exercise numbers stay text
// (the contract #46/#48 pinned). Page 465, whose crops are fractions rather than drawings, is the
// control: no answer entry of its keys is taken into an image.
@Test func sideLengthsJoinTheirDiagramsAndFractionCropsTakeNoLabel() throws {
    let triangles = try reconstruct("algebra-424")
    let texts = triangles.blocks.map { $0.text.trimmingCharacters(in: .whitespaces) }
    #expect(!texts.contains { ["A", "B", "C"].contains($0) })
    for number in 13...20 {
        #expect(texts.contains("\(number))"), "lost exercise number \(number))")
    }
    // Page 465's crops are fractions, not drawings, so its short answer entries keep their text:
    // the first key's thirty-two entries and the seventeen of the second that are not fractions.
    let key = try reconstruct("algebra-465")
    #expect(entryNumbers(key.blocks).count == 32 + 17)
    for entry in ["1) 7,− 2", "13) 4, 0", "29)− 4, 1", "24) 4, 0"] {
        #expect(key.blocks.contains { $0.text.trimmingCharacters(in: .whitespaces) == entry }, "lost \(entry)")
    }
}

// The rule itself, at page 427's measured geometry: a triangle drawn 113.8 × 55.6 pt with its own
// short labels inside the crop.
@Test func onlyAShortLabelBesideADrawingJoinsIt() {
    let crop = CGRect(x: 319, y: 647.5, width: 138.3, height: 88)
    let drawing = CGRect(x: 329.8, y: 661.9, width: 113.8, height: 55.6)
    let held = ["1.4", "65◦", "x"].enumerated().map { index, text in
        TextLine(text: text, rect: CGRect(x: 360 + CGFloat(index) * 20, y: 680, width: 18, height: 12), fontSize: 12)
    }
    func page(_ graphics: [CGRect]) -> PageContent {
        PageContent(number: 427, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: held, graphics: graphics)
    }
    func label(_ text: String, width: CGFloat = 8, gap: CGFloat, beside: Bool = true) -> TextLine {
        let rect = beside
            ? CGRect(x: crop.maxX + gap, y: crop.midY, width: width, height: 12)
            : CGRect(x: crop.midX, y: crop.maxY + gap, width: width, height: 12)
        return TextLine(text: text, rect: rect, fontSize: 12)
    }
    func joins(_ line: TextLine, graphics: [CGRect] = [drawing], holding: [TextLine]? = nil) -> Bool {
        LayoutReconstructor.isDiagramLabel(line, bounds: crop, held: holding ?? held,
                                           page: page(graphics), body: 12)
    }
    // The measured labels: page 427's `B` 2.8 pt beside its triangle, page 424's `A` 6.4 pt,
    // page 422's `x` 11.2 pt, and a side length over the drawing.
    #expect(joins(label("B", gap: 2.8)))
    #expect(joins(label("A", gap: 6.4)))
    #expect(joins(label("x", gap: 11.153)))
    #expect(joins(label("13", width: 14, gap: 4.0, beside: false)))
    // A word space wider than a body is another element of the page.
    #expect(!joins(label("B", gap: 12.4)))
    // An exercise number carries its parenthesis, whatever it stands from the drawing: page 483's
    // `5)` is 0.54 pt from its graph and page 447's `3)` 2.3 pt.
    #expect(!joins(label("5)", width: 14, gap: 0.54)))
    #expect(!joins(label("3)", width: 14, gap: 2.3, beside: false)))
    // A longer run of figures and a monospaced piece are not labels.
    #expect(!joins(label("7.1", width: 18, gap: 2.0)))
    var monospaced = label("B", gap: 2.8)
    monospaced.monospaced = true
    #expect(!joins(monospaced))
    // Diagonally off a corner, overlapping neither span, it is beside nothing.
    #expect(!joins(TextLine(text: "B", rect: CGRect(x: crop.maxX + 3, y: crop.maxY + 3, width: 8, height: 12),
                            fontSize: 12)))
    // A fraction bar is painted a body wide and four points tall, so a derivation is no drawing:
    // page 13's `25` and `55` keep their text, and so does the `or` between the FAA's page-265
    // fractions.
    #expect(!joins(label("25", width: 14, gap: 2.0),
                   graphics: [CGRect(x: 330, y: 690, width: 36, height: 4)]))
    #expect(!joins(label("or", gap: 2.0), graphics: [CGRect(x: 330, y: 690, width: 36, height: 4)]))
    #expect(!joins(label("B", gap: 2.8), graphics: []))
    // A crop that holds prose is a figure with a caption or a worked example, not a labelled
    // drawing, and a crop holding many lines is a chart or a table.
    #expect(!joins(label("B", gap: 2.8),
                   holding: held + [TextLine(text: "Multiply numerators across",
                                             rect: CGRect(x: 360, y: 660, width: 140, height: 12), fontSize: 12)]))
    #expect(!joins(label("B", gap: 2.8), holding: (0..<9).map { index in
        TextLine(text: "\(index)", rect: CGRect(x: 360, y: 660 + CGFloat(index), width: 8, height: 12), fontSize: 12)
    }))
}
