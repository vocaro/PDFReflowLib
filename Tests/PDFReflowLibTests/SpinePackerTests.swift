import Foundation
import Testing
@testable import PDFReflowLib

/// Spine packing and progress composition as pure values: no ZIP, no files, no PDF.
private func piece(_ markup: String, pages: [Int] = [], heading: (String, String)? = nil) -> SpinePacker.Piece {
    SpinePacker.Piece(markup: markup, sourcePages: pages, heading: heading.map { (id: $0.0, text: $0.1) })
}

private let unlimited = Int64.max

@Test func smallBlocksPackIntoOneDocumentAndTheTargetSplitsThem() throws {
    var packer = SpinePacker(bodyTargetBytes: 100, chapterStartPages: [])
    #expect(try packer.add(piece("<p>one</p>"), budgetRemaining: unlimited).isEmpty)
    #expect(try packer.add(piece("<p>two</p>"), budgetRemaining: unlimited).isEmpty)
    let finished = try packer.finish(budgetRemaining: unlimited)
    #expect(finished == [.init(name: "chapter-1.xhtml", body: "<p>one</p><p>two</p>")])
    #expect(packer.documentNames == ["chapter-1.xhtml"])

    var splitting = SpinePacker(bodyTargetBytes: 20, chapterStartPages: [])
    #expect(try splitting.add(piece("<p>first one</p>"), budgetRemaining: unlimited).isEmpty)
    // The next block would pass the target, so the open body closes first.
    let closed = try splitting.add(piece("<p>second one</p>"), budgetRemaining: unlimited)
    #expect(closed == [.init(name: "chapter-1.xhtml", body: "<p>first one</p>")])
    #expect(try splitting.finish(budgetRemaining: unlimited) == [.init(name: "chapter-2.xhtml", body: "<p>second one</p>")])
    // An oversized block is never split; it closes its own document at once.
    var oversized = SpinePacker(bodyTargetBytes: 5, chapterStartPages: [])
    #expect(try oversized.add(piece("<p>a long paragraph</p>"), budgetRemaining: unlimited)
            == [.init(name: "chapter-1.xhtml", body: "<p>a long paragraph</p>")])
    #expect(try oversized.finish(budgetRemaining: unlimited).isEmpty)
}

@Test func trailingHeadingsTravelWithTheirContent() throws {
    // A heading run is carried only while it is short (a tenth of the target); a 600-byte target
    // keeps a 21-byte heading.
    var packer = SpinePacker(bodyTargetBytes: 600, chapterStartPages: [])
    let paragraph = "<p>" + String(repeating: "a", count: 500) + "</p>"
    let content = "<p>" + String(repeating: "b", count: 100) + "</p>"
    _ = try packer.add(piece(paragraph), budgetRemaining: unlimited)
    _ = try packer.add(piece("<h2 id=\"h\">Title</h2>", heading: ("h", "Title")), budgetRemaining: unlimited)
    #expect(packer.toc == [.init(file: "chapter-1.xhtml", fragment: "h", text: "Title")])
    // The content after the heading does not fit: the heading is carried into the next document
    // and its navigation entry follows it.
    let closed = try packer.add(piece(content), budgetRemaining: unlimited)
    #expect(closed == [.init(name: "chapter-1.xhtml", body: paragraph)])
    #expect(packer.toc == [.init(file: "chapter-2.xhtml", fragment: "h", text: "Title")])
    let rest = try packer.finish(budgetRemaining: unlimited)
    #expect(rest == [.init(name: "chapter-2.xhtml", body: "<h2 id=\"h\">Title</h2>" + content)])
    #expect(packer.toc[0].markup == "<li><a href=\"chapter-2.xhtml#h\">Title</a></li>")
    // Heading text and identifiers are escaped in the entry.
    var escaping = SpinePacker(bodyTargetBytes: 1000, chapterStartPages: [])
    _ = try escaping.add(piece("<h2>x</h2>", heading: ("a<b", "Fish & Chips")), budgetRemaining: unlimited)
    #expect(escaping.toc[0].markup == "<li><a href=\"chapter-1.xhtml#a&lt;b\">Fish &amp; Chips</a></li>")
}

@Test func pageBoundariesAndChapterStartsPlaceThemselves() throws {
    var packer = SpinePacker(bodyTargetBytes: 1000, chapterStartPages: [3])
    #expect(try packer.add(sourcePage: 1, markup: "[1]", budgetRemaining: unlimited).isEmpty)
    // A paragraph's own page list holds inline continuation boundaries, not the page it begins on.
    #expect(try packer.add(piece("<p>page one</p>"), budgetRemaining: unlimited).isEmpty)
    // Consecutive boundaries (an empty page 2) pack the earlier one normally.
    #expect(try packer.add(sourcePage: 2, markup: "[2]", budgetRemaining: unlimited).isEmpty)
    // A validated chapter start closes the open document; its marker travels with the next content.
    let closed = try packer.add(sourcePage: 3, markup: "[3]", budgetRemaining: unlimited)
    #expect(closed == [.init(name: "chapter-1.xhtml", body: "[1]<p>page one</p>[2]")])
    _ = try packer.add(piece("<p>chapter three</p>"), budgetRemaining: unlimited)
    #expect(try packer.finish(budgetRemaining: unlimited) == [.init(name: "chapter-2.xhtml", body: "[3]<p>chapter three</p>")])
    #expect(packer.pages.map(\.markup) == [
        "<li><a href=\"chapter-1.xhtml#page-1\">1</a></li>",
        "<li><a href=\"chapter-1.xhtml#page-2\">2</a></li>",
        "<li><a href=\"chapter-2.xhtml#page-3\">3</a></li>",
    ])
    // A trailing boundary is flushed by finish.
    var trailing = SpinePacker(bodyTargetBytes: 1000, chapterStartPages: [])
    _ = try trailing.add(piece("<p>x</p>"), budgetRemaining: unlimited)
    _ = try trailing.add(sourcePage: 9, markup: "[9]", budgetRemaining: unlimited)
    #expect(try trailing.finish(budgetRemaining: unlimited) == [.init(name: "chapter-1.xhtml", body: "<p>x</p>[9]")])
}

@Test func theBudgetRefusesABlockItCannotHold() throws {
    var packer = SpinePacker(bodyTargetBytes: 1000, chapterStartPages: [])
    #expect(throws: ConversionError.self) {
        try packer.add(piece("<p>twelve bytes</p>"), budgetRemaining: 10)
    }
    #expect(try packer.add(piece("<p>ok</p>"), budgetRemaining: 9).isEmpty)
}

@Test func progressBudgetIsMonotonicAcrossStages() {
    var last = 0.0
    var values: [Double] = [ProgressBudget.overall(pipeline: 0)]
    for page in 1...4 {
        values.append(ProgressBudget.overall(pipeline: ProgressBudget.pipeline(extractedPages: page, of: 4)))
    }
    for page in 1...4 {
        values.append(ProgressBudget.overall(pipeline: ProgressBudget.pipeline(reconstructedPages: page, of: 4)))
    }
    values.append(ProgressBudget.overall(writing: 0))
    for entry in 1...2 { values.append(ProgressBudget.overall(writing: ProgressBudget.writer(archivedEntries: entry, of: 2))) }
    for value in values {
        #expect(value >= last, "\(value) after \(last)")
        last = value
    }
    // The pipeline's end is clamped so the first writing update cannot step backward.
    #expect(ProgressBudget.overall(pipeline: 1) == ProgressBudget.pipelineEnd)
    #expect(ProgressBudget.overall(writing: 0) == ProgressBudget.pipelineEnd)
    #expect(abs(ProgressBudget.overall(writing: 1) - 0.99) < 1e-12)
    #expect(abs(ProgressBudget.overall(pipeline: ProgressBudget.pipeline(extractedPages: 2, of: 4)) - (0.02 + 0.55 * 0.5)) < 1e-12)
}

@Test func textLineStoredPropertiesMatchItsSpillEncoding() {
    // `TextLine` encodes itself by hand for the page store, so a new stored property would
    // silently drop between passes. This pins the stored properties; extend `CodingKeys` and
    // `PageStoreTests` together with this list.
    let line = TextLine(text: "x", rect: .zero, fontSize: 1)
    let stored = Mirror(reflecting: line).children.compactMap(\.label)
    #expect(stored == ["content", "text", "rect", "fontSize", "monospaced", "wraps", "turn", "readingRect", "structure"])
}
