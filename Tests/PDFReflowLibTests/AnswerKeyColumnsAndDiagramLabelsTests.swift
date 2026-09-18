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
// columns are entirely crops, reads down its columns by the numbers under the crops (#185, below).
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

// MARK: - #185, keys whose numbers are under crops, and their titles

/// The key numbers of a reconstructed page in reading order: a text entry's own number, and for a
/// preserved crop the numbers printed on the lines it covers, top to bottom.
private func keyNumbers(_ result: (page: PageContent, blocks: [ReflowBlock], crops: [CGRect])) -> [Int] {
    let regions = result.crops
    return result.blocks.flatMap { block -> [Int] in
        if case let .image(image) = block.content, image.assetID.hasPrefix("image-"),
           let index = Int(image.assetID.dropFirst("image-".count)), regions.indices.contains(index) {
            let held = LayoutReconstructor.heldLines(of: regions[index], in: result.page.lines, among: regions)
            let element = LayoutReconstructor.Element(rect: regions[index], image: image.assetID, held: held)
            return LayoutReconstructor.numberedMarkers([element]).sorted { $0.rect.maxY > $1.rect.maxY }.map(\.number)
        }
        return entryNumbers([block])
    }
}

// Every key on these pages reads in printed number order, the numbers under its crops included:
// the numbering only ever steps back to restart a key at 1. Before #185, page 441's first chapter-1
// key read across its rows, 444's and 462's keys interleaved with the keys stacked on them, 447's
// graphs read down their columns, 482's teamwork key read its first column before its title, and
// 486's first key read its middle column's crop before the left column's.
@Test(arguments: ["algebra-441", "algebra-444", "algebra-447", "algebra-462", "algebra-463", "algebra-465",
                  "algebra-482", "algebra-486"])
func everyAnswerKeyReadsInNumberOrder(name: String) throws {
    let numbers = keyNumbers(try reconstruct(name))
    #expect(numbers.count >= 8)
    let steps = zip(numbers, numbers.dropFirst())
    #expect(steps.allSatisfy { $1 > $0 || $1 == 1 }, "\(name) reads \(numbers)")
}

// Page 486's first key sets 3–9 as text over a crop of 10–16 in its left column, 16.6 pt from a crop
// of 17–29 and a crop of 30–40. The narrow gutter fails the prose test, and the row sort read the
// middle crop, whose top stands higher, before the left one.
@Test func aKeyWhoseColumnsAreCropsReadsDownThem() throws {
    let result = try reconstruct("algebra-486")
    let texts = result.blocks.map(\.text)
    let title = try #require(texts.firstIndex(of: "Answers - Exponential Functions"))
    let first = keyNumbers((result.page, Array(result.blocks[..<title]), result.crops))
    #expect(first == Array(3...40))
}

// A key's section number and title read ahead of it, and a section number under a key's last row
// reads after the key. Page 463's `Answers - Trinomials where a 1` stood 3.2 pt over its entries and
// read after the left column; so did page 465's `Answers - Solve by Factoring`, 7.9 pt over a crop,
// and page 482's `Answers - Teamwork` and `Answers - Revenue and Distance`, while its `Answers -
// Simultaneous Product` read ahead of its `9.9`.
@Test func keyTitlesHeadTheirKeys() throws {
    func expectOrder(_ name: String, _ order: [String]) throws {
        let texts = try reconstruct(name).blocks.map { $0.text.trimmingCharacters(in: .whitespaces) }
        var cursor = 0
        for text in order {
            let index = try #require(texts[cursor...].firstIndex { $0.hasPrefix(text) }, "\(name): \(text) out of order")
            cursor = index + 1
        }
    }
    try expectOrder("algebra-463", ["34)", "6.4", "Answers - Trinomials where a 1", "1)", "14)", "15)", "40)", "6.5",
                                    "Answers - Factoring Special Products", "1)"])
    try expectOrder("algebra-465", ["42)", "6.7", "Answers - Solve by Factoring", "1)", "7)", "13)"])
    try expectOrder("algebra-482", ["9.8", "Answers - Teamwork", "1)", "10)", "11)", "28)", "9.9",
                                    "Answers - Simultaneous Product", "4)", "12)", "9.10", "Answers - Revenue and Distance",
                                    "1)", "8)", "9)", "22)", "9.11"])
    // Page 444 sets `1.6` and its title under the crops closing the previous key.
    try expectOrder("algebra-444", ["1.6", "Answers to Absolute Value Equations", "1)", "13)", "30)", "1.7",
                                    "Answers - Variation"])
}

// The rules themselves, at page 486's measured geometry.
@Test func keyNumbersUnderCropsDecideTheNarrowGutter() {
    func line(_ text: String, x: CGFloat, y: CGFloat) -> TextLine {
        TextLine(text: text, rect: CGRect(x: x, y: y, width: 26, height: 12), fontSize: 12)
    }
    func text(_ number: Int, x: CGFloat, y: CGFloat) -> LayoutReconstructor.Element {
        let held = line("\(number)) 0", x: x, y: y)
        return LayoutReconstructor.Element(rect: held.rect, line: held)
    }
    /// A crop at x covering one column of entries from `top`, 22 pt apart.
    func crop(_ numbers: ClosedRange<Int>, x: CGFloat, top: CGFloat, width: CGFloat = 125) -> LayoutReconstructor.Element {
        let held = numbers.enumerated().map { line("\($0.element)) f(x)", x: x + 4, y: top - CGFloat($0.offset) * 22) }
        let rect = CGRect(x: x, y: top - CGFloat(numbers.count - 1) * 22 - 2, width: width, height: CGFloat(numbers.count - 1) * 22 + 16)
        return LayoutReconstructor.Element(rect: rect, image: "crop-\(numbers.lowerBound)", held: held)
    }
    // 3–9 as text over a crop of 10–16, 16.6 pt from a crop of 17–29.
    let left = (3...9).map { text($0, x: 85, y: 745 - CGFloat($0 - 3) * 22) } + [crop(10...16, x: 81, top: 590, width: 131.8)]
    let middle = crop(17...29, x: 229.4, top: 745)
    let gutter = LayoutReconstructor.numberedColumns(left + [middle], bodySize: 12)
    #expect(gutter.map { $0 > 212.8 && $0 < 229.4 } == true)
    // The numbers must rise across the gutter, and a crop that holds no numbers gives no evidence.
    #expect(LayoutReconstructor.numberedColumns(left + [crop(1...2, x: 229.4, top: 745)], bodySize: 12) == nil)
    #expect(LayoutReconstructor.numberedColumns((3...9).map { text($0, x: 85, y: 745 - CGFloat($0 - 3) * 22) }
        + [LayoutReconstructor.Element(rect: middle.rect, image: "figure")], bodySize: 12) == nil)
    // A title alone in its row over the key heads it; one set beside another line does not.
    let title = LayoutReconstructor.Element(rect: CGRect(x: 212, y: 760, width: 170, height: 12),
                                            line: line("Answers - Exponential Functions", x: 212, y: 760))
    let heading = LayoutReconstructor.keyHeading(left + [middle, title], bodySize: 12)
    #expect(heading.map { $0.lower > 757 && $0.lower < 760 && $0.upper > 772 } == true)
    let beside = LayoutReconstructor.Element(rect: CGRect(x: 85, y: 760, width: 40, height: 12), line: line("10.4", x: 85, y: 760))
    #expect(LayoutReconstructor.keyHeading(left + [middle, title, beside], bodySize: 12) == nil)
    // A line held under two crops counts under the one it overlaps most, never under both.
    let straddling = line("5) 1", x: 100, y: 100)
    let crops = [CGRect(x: 90, y: 95, width: 20, height: 30), CGRect(x: 105, y: 90, width: 40, height: 40)]
    #expect(LayoutReconstructor.heldLines(of: crops[0], in: [straddling], among: crops).isEmpty)
    #expect(LayoutReconstructor.heldLines(of: crops[1], in: [straddling], among: crops) == [straddling])
}

// A key band may rest on the key above reading down its columns when the key below opens on the
// band: page 441's one-step key over the first row of the two-step key, which continues overleaf.
// A band under a key's upper rows leaves their continuation beneath it and is refused, however
// low a later key restarts at 1.
@Test func aKeyBandRestsOnTheKeyAboveOnlyWhereTheKeyBelowOpens() {
    func element(_ number: Int, x: CGFloat, y: CGFloat) -> LayoutReconstructor.Element {
        LayoutReconstructor.Element(rect: CGRect(x: x, y: y, width: 26, height: 12),
                                    line: TextLine(text: "\(number)) 0", rect: CGRect(x: x, y: y, width: 26, height: 12), fontSize: 12))
    }
    func column(_ numbers: ClosedRange<Int>, x: CGFloat, top: CGFloat) -> [LayoutReconstructor.Element] {
        numbers.enumerated().map { element($0.element, x: x, y: top - CGFloat($0.offset) * 22) }
    }
    let upper = column(1...4, x: 85, top: 600) + column(15...18, x: 233, top: 600) + column(29...32, x: 382, top: 600)
    // The next key's first row, `1)− 4 2) 7`, one merged line.
    let row = [element(1, x: 85, y: 480)]
    let band = LayoutReconstructor.numberedKeyBand(upper + row, bodySize: 12)
    #expect(band.map { $0 > 492 && $0 < 534 } == true)
    // Page 463: a band under the first key's upper rows, with its last row (16, 26) and a later key
    // restarting at 1 below it, is no boundary.
    let continued = column(7...9, x: 85, top: 700) + column(17...19, x: 233, top: 700) + column(27...29, x: 382, top: 700)
    let tail = [element(16, x: 85, y: 620), element(26, x: 233, y: 620)] + column(1...3, x: 85, top: 560)
        + column(15...17, x: 233, top: 560)
    #expect(LayoutReconstructor.numberedKeyBand(continued + tail, bodySize: 12).map { $0 < 620 } ?? true)
}

// Page 447 sets graphs 3–14 three to a row under labels numbered along the rows, but its right
// column drifts 4.4 pt lower each row, so `14)` stands 13.3 pt under `12)` and `13)` and the rows
// were not found by height: the graphs read 3, 6, 9, 12, 4… Rows are now counted down the columns.
@Test func aDriftingGridReadsAlongItsRows() throws {
    let result = try reconstruct("algebra-447")
    let labels = (3...14).map { "\($0))" }
    let texts = result.blocks.map { $0.text.trimmingCharacters(in: .whitespaces) }
    let indices = try labels.map { label in try #require(texts.firstIndex(of: label), "lost \(label)") }
    #expect(indices == indices.sorted())
    for index in indices {
        if case .image = result.blocks[index + 1].content {} else { Issue.record("\(texts[index]) is not followed by its graph") }
    }
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
