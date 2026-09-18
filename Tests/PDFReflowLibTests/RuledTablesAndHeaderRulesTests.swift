import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

// A ruled table whose header cells PDFKit merges into one line (#65, The Fed Explained page 46,
// Table 3.1) and the running-header rule emitted as an isolated crop on every Fed page (#66).
// The merged header is split at the rule grid's column joints with PDFKit's own selections, and
// the grid then reads as a text table; a thin rule that no text sits against is decoration.

private let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)

private func reflowed(_ page: PageContent) -> (regions: [CGRect], blocks: [ReflowBlock]) {
    let regions = LayoutReconstructor.graphicsWithLabels(page)
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: regions.enumerated().map { ($0.element, "image-\($0.offset)") },
        vocabulary: LayoutReconstructor.vocabulary(in: [page]), warnings: &warnings)
    return (regions, blocks)
}

private func table(in blocks: [ReflowBlock]) -> ReflowBlock.Table? {
    blocks.compactMap { if case let .table(table) = $0.content { table } else { nil } }.first
}

private func rect(_ values: [Double]) -> CGRect { CGRect(x: values[0], y: values[1], width: values[2], height: values[3]) }

// MARK: Column joints and the header split (#65)

/// A three-column grid drawn as InDesign draws it: one stroked segment per column per rule row.
private func gridPDF(header: [(String, CGFloat)], prose: String?) -> Data {
    let rows: [CGFloat] = [400, 362, 300, 240]
    var content = "0 G 0.5 w\n"
    for y in rows {
        for (start, end) in [(91.0, 215.4), (215.4, 360.0), (360.0, 521.0)] {
            content += "\(start) \(y) m \(end) \(y) l S\n"
        }
    }
    for (text, x) in header { content += "BT /F1 8 Tf \(x) 372 Td (\(text)) Tj ET\n" }
    if let prose { content += "BT /F1 8 Tf 94.5 385 Td (\(prose)) Tj ET\n" }
    for (text, x) in [("Discount window", 94.5), ("Lending to banks", 219.4), ("A ceiling on rates", 364.0)] {
        content += "BT /F1 8 Tf \(x) 340 Td (\(text)) Tj ET\n"
    }
    return testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
        testPDFStream(content),
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>",
    ])
}

private func extracted(_ data: Data, split: Bool) throws -> [TextLine] {
    let document = try #require(PDFDocument(data: data))
    let page = try #require(document.page(at: 0))
    let paints = GraphicsReader.read(try #require(page.pageRef)).paints
    return try NativeTextReader.lines(on: page, limit: 100_000,
        columnJoints: split ? GraphicsReader.columnJoints(paints.map(\.rect)) : [])
}

@Test func mergedHeaderCellsAreSplitAtTheRuleGridsColumnJoints() throws {
    let data = gridPDF(header: [("Tool", 94.5), ("Definition", 219.4), ("In practice", 364)], prose: nil)
    // Reproducer: PDFKit returns the three header cells as one line.
    let merged = try extracted(data, split: false)
    #expect(merged.contains { $0.text == "Tool Definition In practice" })
    let lines = try extracted(data, split: true)
    let header = lines.filter { abs($0.rect.minY - merged.first { $0.text.hasPrefix("Tool") }!.rect.minY) < 1 }
        .sorted { $0.rect.minX < $1.rect.minX }
    #expect(header.map(\.text) == ["Tool", "Definition", "In practice"])
    #expect(header.map { ($0.rect.minX * 2).rounded() / 2 } == [94.5, 219.5, 364])
    // Each piece's box ends at its own glyphs, not at the stretched space before the next cell.
    #expect(header.allSatisfy { $0.rect.width < 60 })
    // The styled runs survive the split.
    #expect(header.allSatisfy { $0.content.elements.contains { if case let .text(_, style) = $0 { style.contains(.bold) } else { false } } })
}

@Test func proseAndWordGapsAcrossAJointStayWhole() throws {
    // A title crossing the joints has only word spaces there; a cell that ends within an em of
    // the next column's text is not split either.
    let data = gridPDF(header: [("Tool", 94.5), ("Definition", 219.4), ("In practice", 364)],
                       prose: "Traditional tools in an ample reserves regime for implementing policy in the banking system")
    let lines = try extracted(data, split: true)
    #expect(lines.contains { $0.text == "Traditional tools in an ample reserves regime for implementing policy in the banking system" })
    let tight = gridPDF(header: [("Interest on reserve balances paid", 94.5), ("Definition", 219.4)], prose: nil)
    let tightLines = try extracted(tight, split: true)
    #expect(tightLines.contains { $0.text.hasPrefix("Interest on reserve balances paid") && $0.text.hasSuffix("Definition") })
}

@Test func columnJointsNeedAbuttingSegmentsInThreeRuleRows() throws {
    let fixture = try SourceLayoutFixture.load("fed-46")
    let joints = GraphicsReader.columnJoints(try #require(fixture.paints).map { rect($0.rect) })
    #expect(joints.count == 2)
    #expect(joints.map { ($0.x * 10).rounded() / 10 } == [215.4, 360])
    #expect(joints.allSatisfy { $0.minY < 80 && $0.maxY > 420 })
    func segments(_ y: CGFloat, gap: CGFloat = 0) -> [CGRect] {
        [CGRect(x: 89, y: y, width: 128.4, height: 4), CGRect(x: 213.4 + gap, y: y, width: 148.6, height: 4)]
    }
    // Controls: two rows, segments separated by a gap, a single full-width rule per row, and a
    // thick bar are not a ruled grid.
    #expect(GraphicsReader.columnJoints(segments(100) + segments(200)).isEmpty)
    #expect(GraphicsReader.columnJoints(segments(100, gap: 12) + segments(200, gap: 12) + segments(300, gap: 12)).isEmpty)
    #expect(GraphicsReader.columnJoints([100, 200, 300].map { CGRect(x: 89, y: $0, width: 430, height: 4) }).isEmpty)
    #expect(GraphicsReader.columnJoints([100, 200, 300].flatMap { segments($0) }).count == 1)
    #expect(GraphicsReader.columnJoints([100, 200, 300].flatMap { y in segments(y).map { $0.insetBy(dx: 0, dy: -4) } }).isEmpty)
}

// MARK: Table 3.1 (#65)

/// Fed page 46 as the fixture was captured (header split), or with the header cells merged
/// back into the single line PDFKit returns, composed as the pipeline composes it.
private func fed46(mergedHeader: Bool, paints edit: ([GraphicsReader.Paint]) -> [GraphicsReader.Paint] = { $0 }) throws -> PageContent {
    let fixture = try SourceLayoutFixture.load("fed-46")
    var page = fixture.content(tinted: false)
    if mergedHeader {
        let cells = page.lines.filter { ["Tool", "Definition", "In practice"].contains($0.text) }
        #expect(cells.count == 3)
        page.lines.removeAll { cells.contains($0) }
        let index = try #require(page.lines.firstIndex { $0.text == "Interest on reserve balances" })
        page.lines.insert(TextLine(text: "Tool Definition In practice", rect: union(cells.map(\.rect)), fontSize: 8), at: index)
    }
    let paints = edit(try #require(fixture.paints).map { GraphicsReader.Paint(rect: rect($0.rect), frame: $0.frame) })
    let composed = TintDetector.compose(paints, lines: page.lines, bounds: page.bounds)
    page.graphics = composed.graphics
    page.tints = composed.tints
    page.separators = composed.separators
    return page
}

@Test func fedTable31ReadsAsAThreeColumnTableWithItsHeader() throws {
    // Reproducer: with the header merged, the grid stays one crop holding every cell.
    let before = try fed46(mergedHeader: true)
    let (beforeRegions, beforeBlocks) = reflowed(before)
    #expect(table(in: beforeBlocks) == nil)
    #expect(beforeRegions.contains { $0.height > 300 && $0.contains(CGPoint(x: 300, y: 200)) })

    let page = try fed46(mergedHeader: false)
    let (regions, blocks) = reflowed(page)
    #expect(regions.isEmpty)
    let table = try #require(table(in: blocks))
    #expect(table.columns == 3 && table.rows.count == 5)
    #expect(table.rows[0].header && table.rows[0].cells.map(\.text.text) == ["Tool", "Definition", "In practice"])
    #expect(table.rows.dropFirst().map { $0.cells[0].text.text } == ["Interest on reserve balances (IORB)",
        "Overnight reverse repurchase agreement (ON RRP) facility", "Open market operations", "Discount window"])
    #expect(table.rows.dropFirst().allSatisfy { !$0.header && $0.cells.count == 3 })
    #expect(table.rows[1].cells[1].text.text == "Interest paid on funds that banks hold in their reserve balance accounts at their Federal Reserve Bank.")
    #expect(table.rows[2].cells[2].text.text.hasSuffix("acts as a supplementary tool for moving the federal funds rate within the target range."))
    #expect(table.rows[4].cells[2].text.text == "Because banks are unlikely to borrow at a rate that’s higher than the discount rate, the discount window helps put a ceiling on the federal funds rate.")
    // The title band is the table's caption (#113); the body prose and the sidebar keep reading.
    let texts = blocks.map(\.text)
    #expect(table.caption.map(\.text) == ["Table 3.1 Traditional tools in an ample-reserves regime",
        "In recent years, the Federal Reserve has successfully implemented monetary policy with a varying degree of ample reserves in the banking system."])
    #expect(!blocks.contains { if case .table = $0.content { false } else { $0.text.contains("Traditional tools in an ample-reserves regime") } })
    #expect(texts.contains { $0.contains("risks to the economic outlook were implemented") })
    #expect(texts.contains { $0.hasPrefix("Learn more about how the Fed uses") })
}

@Test func splitRegulationLettersStillJoinTheirNamesInOneCell() throws {
    // Fed page 83 recaptured with the split: the regulation letter and its name are separate
    // lines at the grid's joint, and the shaded-table reader still joins them as the source's
    // "Regulation (by letter and name)" column (#54).
    let page = try SourceLayoutFixture.load("fed-83").content()
    #expect(page.lines.contains { $0.text == "Y" } && page.lines.contains { $0.text == "Bank Holding Companies and Change in Bank" })
    let table = try #require(table(in: reflowed(page).blocks))
    #expect(table.columns == 2)
    #expect(table.rows.contains { $0.cells.count == 2 && $0.cells[0].text.text == "Y Bank Holding Companies and Change in Bank Control" })
    #expect(table.rows.contains { $0.cells.count == 2 && $0.cells[0].text.text == "X Borrowers of Securities Credit" })
}

@Test func ruledGridsWithoutAReadableHeaderOrWithInkKeepTheirImage() throws {
    // Without the shaded header band the grid has no header row this detector trusts.
    let unbanded = try fed46(mergedHeader: false) { paints in
        paints.filter { !($0.frame && abs($0.rect.minY - 359.952) < 1) }
    }
    #expect(table(in: reflowed(unbanded).blocks) == nil)
    // The grid's crop holds it whole. Since #158 its parts seed separate regions, because the
    // cells' text runs through the hull between them; whole-line expansion joins them again.
    #expect(reflowed(unbanded).regions.contains { $0.height > 300 })
    // A chart painted inside the frame keeps the grid an image.
    let charted = try fed46(mergedHeader: false) { $0 + [GraphicsReader.Paint(rect: CGRect(x: 380, y: 200, width: 60, height: 40), frame: false)] }
    #expect(table(in: reflowed(charted).blocks) == nil)
    #expect(reflowed(charted).regions.contains { $0.height > 300 })
    // A line crossing the columns inside the grid means the grid was misread; it stays an image.
    var noted = try fed46(mergedHeader: false)
    noted.lines.append(TextLine(text: "Source: Federal Reserve Board of Governors staff calculations from the discount window", rect: CGRect(x: 94.5, y: 176, width: 380, height: 9), fontSize: 8))
    let recomposed = TintDetector.compose(try #require(SourceLayoutFixture.load("fed-46").paints).map {
        GraphicsReader.Paint(rect: rect($0.rect), frame: $0.frame) }, lines: noted.lines, bounds: noted.bounds)
    noted.graphics = recomposed.graphics
    noted.tints = recomposed.tints
    noted.separators = recomposed.separators
    #expect(reflowed(noted).regions.contains { $0.height > 300 })
}

// MARK: Decoration rules (#66)

private func page(lines: [TextLine], graphics: [CGRect]) -> PageContent {
    PageContent(number: 1, bounds: pageBounds, lines: lines, graphics: graphics)
}

private func bodyLines(from top: CGFloat, count: Int = 20) -> [TextLine] {
    (0..<count).map { TextLine(text: "Reserve Banks provide the Federal Reserve System with a wealth of information \($0)",
                               rect: CGRect(x: 90, y: top - CGFloat($0) * 16, width: 432, height: 11.6), fontSize: 10) }
}

private let headerRule = CGRect(x: 56.8, y: 742.0121, width: 498.4, height: 4)
private let runningHead = [TextLine(text: "42", rect: CGRect(x: 58.8, y: 748.5, width: 9.6, height: 9.3), fontSize: 8),
                           TextLine(text: "The Fed Explained: What the Central Bank Does", rect: CGRect(x: 88.8, y: 748.5, width: 167.2, height: 9.3), fontSize: 8)]

@Test func runningHeaderRuleIsDecorationOnEveryFedFixture() throws {
    let fixtures = [103, 109, 11, 12, 120, 123, 13, 21, 22, 25, 32, 36, 37, 40, 45, 46, 54, 58, 64, 75, 77, 83, 9]
    for number in fixtures {
        let page = try SourceLayoutFixture.load("fed-\(number)").content()
        // The rule reaches layout as a graphic (56.8 or 58 pt from the left, alternating pages).
        let rule = try #require(page.graphics.first { abs($0.minY - 742) < 0.5 && $0.width > 490 && $0.height <= 6 }, "fed-\(number)")
        #expect(!LayoutReconstructor.graphicsWithLabels(page).contains { $0.intersects(rule) }, "fed-\(number)")
    }
    // With the running head removed as furniture (the default), nothing is near the rule at all.
    let removed = page(lines: bodyLines(from: 690), graphics: [headerRule])
    #expect(LayoutReconstructor.graphicsWithLabels(removed).isEmpty)
    let kept = page(lines: runningHead + bodyLines(from: 690), graphics: [headerRule])
    #expect(LayoutReconstructor.graphicsWithLabels(kept).isEmpty)
}

@Test func rulesThatTextOrInkSitsAgainstStayGraphics() throws {
    // Our Flag page 27: each rule sits 1.6 pt beneath a 22-pt section title; both stay regions.
    let flag = try SourceLayoutFixture.load("flag-27").content()
    let regions = LayoutReconstructor.graphicsWithLabels(flag)
    for rule in flag.graphics { #expect(regions.contains(rule)) }
    #expect(regions.count == 3)
    let body = bodyLines(from: 690)
    func kept(_ lines: [TextLine], _ graphics: [CGRect], _ rule: CGRect = headerRule) -> Bool {
        LayoutReconstructor.graphicsWithLabels(page(lines: lines, graphics: graphics)).contains { $0.contains(rule) }
    }
    // A heading-sized row beside the rule is a heading's rule, not a running head.
    let heading = [TextLine(text: "Monetary Policy", rect: CGRect(x: 58.8, y: 748.5, width: 190, height: 24), fontSize: 22)]
    #expect(kept(heading + body, [headerRule]))
    // A rule touching another graphic belongs to it.
    #expect(kept(body, [headerRule, CGRect(x: 300, y: 744, width: 80, height: 40)]))
    // A short rule is not a page rule.
    let short = CGRect(x: 90, y: 742, width: 120, height: 4)
    #expect(kept(body, [short], short))
    // Mid-page: text within a body size above and below.
    let middle = CGRect(x: 90, y: 395, width: 432, height: 4)
    let around = bodyLines(from: 690).filter { $0.rect.minY > 400 } + [TextLine(text: "Discount window lending rates",
        rect: CGRect(x: 90, y: 385, width: 200, height: 9.3), fontSize: 10)]
    #expect(kept(around, [middle], middle))
    // A body-sized row with more text beyond it is not a running head between rule and edge.
    let above = TextLine(text: "A note set above the running head", rect: CGRect(x: 300, y: 770, width: 150, height: 9.3), fontSize: 8)
    #expect(!kept(runningHead + body, [headerRule]))
    #expect(kept(runningHead + [above] + body, [headerRule]))
    // A body-sized row beside a rule away from the page's outer margin is a section rule.
    let lowered = headerRule.offsetBy(dx: 0, dy: -200)
    #expect(kept(runningHead.map { var line = $0; line.rect.origin.y -= 200; return line } + bodyLines(from: 490, count: 10), [lowered], lowered))
}
