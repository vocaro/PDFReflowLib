import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// DGA page 2 (#141): the header title and welcome line are set on a tab and a band across the lower
// edge of the header photograph, and clustered with it into one crop; the four footnotes are set two
// to a column beneath the signatures, numbered down each column, and read along the rows. The
// fixture is native extraction from the checksum-pinned source (#117's capture); expectations were
// read from the rendered page.

private let dgaSHA256 = "c34f1bec5c9416265670b7fcb24556bb8616ba95e8de2f2890460b6bbca1a472"

private func dgaPage2() throws -> SourceLayoutFixture {
    let fixture = try SourceLayoutFixture.load("dga-2-illustrated")
    #expect(fixture.sourceSHA256 == dgaSHA256)
    #expect(fixture.page == 2)
    return fixture
}

private func blocks(_ page: PageContent) -> (crops: [CGRect], blocks: [ReflowBlock]) {
    var page = page
    // The running foot furniture removal takes.
    page.lines.removeAll { $0.rect.maxY < 60 }
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: crops.enumerated().map { ($0.element, "image-\($0.offset)") },
                                            vocabulary: [], warnings: &warnings)
    return (crops, blocks)
}

@Test func dgaPage2HeaderTitleAndWelcomeLineLeaveThePhotographsCrop() throws {
    let source = try dgaPage2()
    let page = source.content()
    let (crops, result) = blocks(page)
    let title = try #require(page.lines.first { $0.text == "Message from the Secretaries" })
    let welcome = try #require(page.lines.first { $0.text.hasPrefix("Welcome to the Dietary Guidelines") })
    #expect(!crops.contains { $0.intersects(title.rect) || $0.intersects(welcome.rect) })
    // The photograph keeps a crop of its own, above the tab, across the page.
    let header = try #require(crops.first { $0.maxY >= 791 })
    #expect(header.minX <= 0.5 && header.maxX >= 611.5)
    #expect(header.minY > 740 && header.minY < 741)
    // Reading order: the photograph, the title as a heading, the welcome line, the body.
    let texts = result.map(\.text)
    let heading = try #require(result.firstIndex { if case .heading = $0.content { $0.text == "Message from the Secretaries" } else { false } })
    if case .image = result[0].content {} else { Issue.record("the page does not open with the photograph") }
    #expect(heading == 1)
    #expect(texts[heading + 1].hasPrefix("Welcome to the Dietary Guidelines"))
    #expect(texts[heading + 2].hasPrefix("These Guidelines mark"))
    // Negative control: with the tab and band gone the lines sit on nothing painted beneath them,
    // and the photograph's crop takes them as before.
    var bare = page
    let paints = (source.paints ?? []).filter { $0.image == true || !($0.rect[1] > 660 && $0.rect[1] < 710 && $0.rect[2] >= 300) }
    #expect(paints.count == (source.paints ?? []).count - 2)
    bare.graphics = TintDetector.compose(paints.map { GraphicsReader.Paint(rect: CGRect(x: $0.rect[0], y: $0.rect[1], width: $0.rect[2], height: $0.rect[3]),
                                                                           frame: $0.frame, image: $0.image ?? false, filled: $0.filled ?? false) },
                                         lines: page.lines, bounds: page.bounds).graphics
    #expect(LayoutReconstructor.graphicsWithLabels(bare).contains { $0.intersects(title.rect) })
}

@Test func dgaPage2FootnotesReadDownTheirColumns() throws {
    let page = try dgaPage2().styledContent()
    let notes = blocks(page).blocks.map(\.text).filter { $0.contains("https://") }
    #expect(notes.count == 4)
    for (index, note) in notes.enumerated() {
        #expect(note.hasPrefix("\(index + 1) "), "\(note)")
    }
    // Negative control: the reading-order sort alone reads the notes along their rows.
    let elements = page.lines.filter { $0.text.contains("https://") }.map { LayoutReconstructor.Element(rect: $0.rect, line: $0) }
    let rows = LayoutReconstructor.sortedByRows(elements, bodySize: 10.5).compactMap { $0.line.flatMap(LayoutReconstructor.raisedNoteNumber) }
    #expect(rows == [1, 3, 2, 4])
    let columns = LayoutReconstructor.noteColumnsInNumberOrder(LayoutReconstructor.sortedByRows(elements, bodySize: 10.5), bodySize: 10.5)
    #expect(columns.compactMap { $0.line.flatMap(LayoutReconstructor.raisedNoteNumber) } == [1, 2, 3, 4])
}

// MARK: Edge bands (synthetic)

private let bounds = CGRect(x: 0, y: 0, width: 600, height: 800)

private func line(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat = 300, size: CGFloat = 12) -> TextLine {
    TextLine(text: text, rect: CGRect(x: x, y: y, width: width, height: size * 1.3), fontSize: size)
}

private let body = (0..<8).map { line("Body prose that sets the ordinary size of this page \($0)", x: 54, y: 500 - CGFloat($0) * 16, width: 480, size: 10.5) }

/// A photograph across the page top (y 700–800) with a title on a tab over its lower edge and a
/// band across the page beneath it holding the welcome line.
private struct Header {
    var photo = GraphicsReader.Paint(rect: CGRect(x: 0, y: 700, width: 600, height: 100), frame: false, image: true)
    var tab = GraphicsReader.Paint(rect: CGRect(x: 0, y: 698, width: 320, height: 40), frame: false, filled: true)
    var band = GraphicsReader.Paint(rect: CGRect(x: 0, y: 670, width: 600, height: 45), frame: true, filled: true)
    var title = line("Message from the Secretaries", x: 55, y: 706, width: 220, size: 18)
    var welcome = line("Welcome to the Guidelines for Americans", x: 54, y: 680, width: 290, size: 12)
    var paints: [GraphicsReader.Paint] { [photo, tab, band] }
    var lines: [TextLine] { body + [title, welcome] }
    func crops() -> [CGRect] { TintDetector.compose(paints, lines: lines, bounds: bounds).graphics }
    func trimmed() -> Bool {
        let crops = crops()
        return !crops.contains { $0.intersects(title.rect) || $0.intersects(welcome.rect) } && crops.contains { $0.maxY == 800 }
    }
}

@Test func anEdgeBandOverAPhotographLeavesItsTitleAndProse() {
    let header = Header()
    #expect(header.trimmed())
    #expect(header.crops().contains(CGRect(x: 0, y: 738.5, width: 600, height: 61.5)))
    // A photograph narrower than its band keeps its own width.
    var inset = Header(); inset.photo.rect = CGRect(x: 10, y: 700, width: 580, height: 100)
    #expect(inset.crops().contains(CGRect(x: 10, y: 738.5, width: 580, height: 61.5)))
    // The same band over the photograph's upper edge.
    var top = Header()
    top.photo.rect = CGRect(x: 0, y: 560, width: 600, height: 100)
    top.tab.rect = CGRect(x: 0, y: 622, width: 320, height: 40)
    top.band.rect = CGRect(x: 0, y: 645, width: 600, height: 45)
    top.title.rect.origin.y = 630
    top.welcome.rect.origin.y = 660
    let crops = top.crops()
    #expect(!crops.contains { $0.intersects(top.title.rect) || $0.intersects(top.welcome.rect) })
    #expect(crops.contains(CGRect(x: 0, y: 560, width: 600, height: 61.5)))
}

@Test func edgeBandControlsKeepTextInItsArt() {
    // A label, not a title or prose (a chart's axis name, a map's place name).
    var label = Header(); label.welcome = line("Mid-Atlantic", x: 54, y: 680, width: 80, size: 12)
    #expect(!label.trimmed())
    // Text set on the art itself beside the tab, with nothing painted beneath it (a caption or a
    // chart title on the picture).
    let caption = line("Photograph courtesy of the Department of Agriculture", x: 350, y: 718, width: 240, size: 10.5)
    let bare = Header()
    let crops = TintDetector.compose(bare.paints, lines: bare.lines + [caption], bounds: bounds).graphics
    #expect(crops.contains { $0.intersects(caption.rect) && $0.intersects(bare.title.rect) })
    // Backdrops narrower than the art: an illustration's callout boxes.
    var callouts = Header()
    callouts.band.rect = CGRect(x: 40, y: 670, width: 320, height: 45)
    #expect(!callouts.trimmed())
    // A stroked outline is not a backdrop.
    var outlined = Header(); outlined.band.filled = false; outlined.band.frame = true
    #expect(!outlined.trimmed())
    // The band across the middle of the photograph, with art above and below it.
    var middle = Header()
    middle.photo.rect = CGRect(x: 0, y: 520, width: 600, height: 280)
    middle.band.rect = CGRect(x: 0, y: 640, width: 600, height: 48)
    middle.tab.rect = middle.band.rect
    middle.welcome.rect.origin.y = 643
    middle.title.rect.origin.y = 663
    #expect(middle.crops().contains { $0.intersects(middle.title.rect) && $0.intersects(middle.welcome.rect) })
    // Vector art beyond the band (clear of the title, beside and above its tab), with no image or
    // only a small one in it.
    var drawn = Header(); drawn.photo.image = false; drawn.photo.filled = true
    drawn.photo.rect = CGRect(x: 0, y: 736, width: 300, height: 64)
    let beside = GraphicsReader.Paint(rect: CGRect(x: 300, y: 710, width: 300, height: 90), frame: false, filled: true)
    let logo = GraphicsReader.Paint(rect: CGRect(x: 500, y: 760, width: 30, height: 30), frame: false, image: true)
    for extra in [[beside], [beside, logo]] {
        let crops = TintDetector.compose(drawn.paints + extra, lines: drawn.lines, bounds: bounds).graphics
        #expect(crops.contains { $0.intersects(drawn.title.rect) && $0.intersects(drawn.welcome.rect) && $0.maxY == 800 })
    }
    // A figure set in a tinted box whose tint runs beneath its title (NOAA's boxed photographs):
    // the backdrop reaches past both of the crop's edges, so nothing lies beyond it.
    var boxed = Header()
    boxed.band.rect = CGRect(x: 0, y: 600, width: 600, height: 200)
    boxed.tab.rect = CGRect(x: 0, y: 600, width: 600, height: 200)
    #expect(boxed.crops().contains { $0.intersects(boxed.title.rect) && $0.intersects(boxed.welcome.rect) })
    // Too little art beyond the band.
    var short = Header(); short.photo.rect = CGRect(x: 0, y: 700, width: 600, height: 45)
    #expect(short.crops().contains { $0.intersects(short.title.rect) && $0.intersects(short.welcome.rect) })
}

@Test func edgeBandsStayBoundedOnPagesOfManyPictures() {
    // Cells of a picture over a filled band holding a line of prose, each its own crop.
    func cells(_ count: Int) -> (paints: [GraphicsReader.Paint], lines: [TextLine]) {
        var paints: [GraphicsReader.Paint] = [], lines: [TextLine] = []
        for index in 0..<count {
            let x = CGFloat(index % 40) * 40, y = CGFloat(index / 40) * 50
            paints.append(GraphicsReader.Paint(rect: CGRect(x: x, y: y + 10, width: 30, height: 30), frame: false, image: true))
            paints.append(GraphicsReader.Paint(rect: CGRect(x: x, y: y, width: 30, height: 14), frame: true, filled: true))
            lines.append(TextLine(text: "aa bb cc dd", rect: CGRect(x: x + 1, y: y + 2, width: 28, height: 10), fontSize: 8))
        }
        return (paints, lines)
    }
    // The crops are handed in as clustering makes them (one per cell), so only this rule is timed.
    func crops(_ count: Int) -> [CGRect] {
        (0..<count).map { CGRect(x: CGFloat($0 % 40) * 40, y: CGFloat($0 / 40) * 50, width: 30, height: 40) }
    }
    let few = cells(80)
    let page = CGRect(x: 0, y: 0, width: 1600, height: 2000)
    #expect(clusters(few.paints.map(\.rect), distance: 4) == crops(80))
    let trimmed = TintDetector.withoutEdgeBands(crops(80), paints: few.paints, lines: few.lines)
    #expect(trimmed == crops(80).map { CGRect(x: $0.minX, y: $0.minY + 14.5, width: 30, height: 25.5) })
    #expect(TintDetector.compose(few.paints, lines: few.lines, bounds: page).graphics.sorted { ($0.minY, $0.minX) < ($1.minY, $1.minX) } == trimmed)
    // 1,600 crops times 4,800 images, lines and fills is past the work limit: the crops keep their lines.
    let many = cells(1_600)
    #expect(1_600 * 4_800 > TintDetector.seedClusterWorkLimit)
    let start = Date()
    let kept = TintDetector.withoutEdgeBands(crops(1_600), paints: many.paints, lines: many.lines)
    let seconds = Date().timeIntervalSince(start)
    #expect(kept == crops(1_600))
    #expect(seconds < 3, "edge bands \(seconds) s")
}

// MARK: Note columns (synthetic)

private func note(_ number: Int, _ text: String, x: CGFloat, y: CGFloat, size: CGFloat = 6) -> TextLine {
    TextLine(content: InlineText(elements: [.text("\(number)", .superscript), .text(" " + text, [])]),
             rect: CGRect(x: x, y: y, width: 180, height: size * 1.3), fontSize: size)
}

private func elements(_ lines: [TextLine]) -> [LayoutReconstructor.Element] {
    lines.map { LayoutReconstructor.Element(rect: $0.rect, line: $0) }
}

private func order(_ lines: [TextLine], size: CGFloat = 10.5) -> [String] {
    LayoutReconstructor.noteColumnsInNumberOrder(LayoutReconstructor.sortedByRows(elements(lines), bodySize: size), bodySize: size)
        .compactMap { $0.line?.text }
}

@Test func notesNumberedDownTheirColumnsReadInNumberOrder() {
    let columns = [note(1, "first", x: 54, y: 88), note(2, "second", x: 54, y: 77.5), note(3, "third", x: 315, y: 88),
                   note(4, "fourth", x: 315, y: 77.5)]
    #expect(order(columns) == ["1 first", "2 second", "3 third", "4 fourth"])
    // A wrapped note keeps its continuation beneath it.
    let wrapped = [note(1, "first", x: 54, y: 88), line("continued", x: 60, y: 80, width: 100, size: 6), note(2, "second", x: 54, y: 72),
                   note(3, "third", x: 315, y: 88), note(4, "fourth", x: 315, y: 80)]
    #expect(order(wrapped) == ["1 first", "continued", "2 second", "3 third", "4 fourth"])
    // A note continued at the head of the next column reads after it.
    let continued = [note(1, "first", x: 54, y: 88), note(2, "second", x: 54, y: 77.5), line("second, continued", x: 315, y: 88, width: 100, size: 6),
                     note(3, "third", x: 315, y: 77.5), note(4, "fourth", x: 315, y: 67)]
    #expect(order(continued) == ["1 first", "2 second", "second, continued", "3 third", "4 fourth"])
    // Text above the notes keeps its place.
    let prose = line("Body prose above the notes", x: 54, y: 120, width: 400, size: 10.5)
    #expect(order([prose] + columns).first == prose.text)
}

@Test func noteColumnControlsKeepTheRowOrder() {
    // Numbered along the rows: the row order is already the number order.
    let rows = [note(1, "first", x: 54, y: 88), note(2, "second", x: 315, y: 88), note(3, "third", x: 54, y: 77.5),
                note(4, "fourth", x: 315, y: 77.5)]
    #expect(order(rows) == ["1 first", "2 second", "3 third", "4 fourth"])
    // Numbers that do not count on from column to column.
    let gaps = [note(1, "first", x: 54, y: 88), note(5, "fifth", x: 54, y: 77.5), note(3, "third", x: 315, y: 88),
                note(4, "fourth", x: 315, y: 77.5)]
    #expect(order(gaps) == ["1 first", "3 third", "5 fifth", "4 fourth"])
    // Two notes are too few.
    let two = [note(1, "first", x: 54, y: 88), note(2, "second", x: 315, y: 88), line("tail", x: 54, y: 77.5, width: 100, size: 6)]
    #expect(order(two) == ["1 first", "2 second", "tail"])
    // Body-size lines are not notes.
    let large = [note(1, "first", x: 54, y: 88, size: 10.5), note(2, "second", x: 54, y: 72, size: 10.5),
                 note(3, "third", x: 315, y: 88, size: 10.5), note(4, "fourth", x: 315, y: 72, size: 10.5)]
    #expect(order(large) == ["1 first", "3 third", "2 second", "4 fourth"])
    // Plain numbers are not raised markers.
    func plainNote(_ number: Int, _ text: String, x: CGFloat, y: CGFloat) -> TextLine {
        TextLine(content: InlineText(elements: [.text("\(number)", []), .text(" " + text, [])]),
                 rect: CGRect(x: x, y: y, width: 180, height: 7.8), fontSize: 6)
    }
    let plain = [plainNote(1, "first", x: 54, y: 88), plainNote(2, "second", x: 54, y: 77.5), plainNote(3, "third", x: 315, y: 88),
                 plainNote(4, "fourth", x: 315, y: 77.5)]
    #expect(order(plain) == ["1 first", "3 third", "2 second", "4 fourth"])
    // A small line left of every note's edge is not in a column.
    let outside = [note(1, "first", x: 54, y: 88), note(2, "second", x: 54, y: 77.5), note(3, "third", x: 315, y: 88),
                   line("stray", x: 20, y: 77.5, width: 20, size: 6), note(4, "fourth", x: 315, y: 77.5)]
    #expect(order(outside) == ["1 first", "3 third", "stray", "2 second", "4 fourth"])
    // Overlapping columns are not columns.
    let overlapping = [note(1, "first", x: 54, y: 88), note(2, "second", x: 54, y: 77.5), note(3, "third", x: 200, y: 88),
                       note(4, "fourth", x: 200, y: 77.5)]
    #expect(order(overlapping) == ["1 first", "3 third", "2 second", "4 fourth"])
}

@Test func eachRaisedNoteOpensItsOwnParagraph() {
    let page = PageContent(number: 1, bounds: bounds, lines: body + [
        note(1, "Foreign banking organizations operate through branches and agencies, as well", x: 54, y: 88),
        note(2, "Edge Act corporations are subsidiaries of banks or bank holding companies.", x: 54, y: 80),
    ], graphics: [])
    var warnings: [ConversionWarning] = []
    let notes = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings).map(\.text).filter { $0.contains("Foreign") || $0.contains("Edge") }
    #expect(notes.count == 2)
    // Control: a note's plain continuation line stays in its paragraph.
    let wrapped = PageContent(number: 1, bounds: bounds, lines: body + [
        note(1, "Foreign banking organizations operate through branches and agencies, as well", x: 54, y: 88),
        line("as through state member banks and holding companies.", x: 54, y: 80, width: 180, size: 6),
    ], graphics: [])
    let joined = LayoutReconstructor.blocks(page: wrapped, images: [], vocabulary: [], warnings: &warnings).map(\.text).filter { $0.contains("Foreign") }
    #expect(joined.count == 1 && joined[0].contains("state member banks"))
    // Control: a raised number opening a line of prose that is not a note stays in its paragraph.
    let reference = PageContent(number: 1, bounds: bounds, lines: body + [
        line("Foreign banking organizations operate through branches and agencies, as shown in studies", x: 54, y: 88, width: 180, size: 6),
        note(2, "and later reports on state member banks and holding companies.", x: 54, y: 80),
    ], graphics: [])
    let prose = LayoutReconstructor.blocks(page: reference, images: [], vocabulary: [], warnings: &warnings).map(\.text).filter { $0.contains("Foreign") }
    #expect(prose.count == 1 && prose[0].contains("later reports"))
}
