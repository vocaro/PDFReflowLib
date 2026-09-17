import Foundation
import Testing
@testable import PDFReflowLib

// 9/11 endnote markers left unlinked after #80 (#87): page 496's head misprints chapter 4 over
// chapter 3's notes 93–112, and page 544 continues note 107's candidate list from page 543, whose
// items 7–9 read as chapter 7's notes 7–9 while page 545's item 10 stayed a preformatted line.

private let gpo911SHA256 = "657d41475eb3a9a5e3e87a6c7c51ac1dfbe1af7566d1abff7bf7286e7e1c0e1b"

private struct NotesRun {
    var blocks: [ReflowBlock] = []
    var heads: [Int: ClosedRange<Int>] = [:]
    var layouts: [Int: NumberedNoteDetector.Layout] = [:]
    var pages: [Int: [ReflowBlock]] = [:]
}

/// Source pages reconstructed in order as the pipeline does: the head read before its removal,
/// the previous page's open list handed to the next physical page (when `carry` is on), and
/// adjacent pages joined.
private func run(_ names: [String], carry: Bool = true) throws -> NotesRun {
    var result = NotesRun()
    var previous: PageContent?
    var open: NumberedNoteDetector.OpenList?
    for name in names {
        let fixture = try SourceLayoutFixture.load(name)
        #expect(fixture.sourceSHA256 == gpo911SHA256)
        var page = fixture.content()
        let heads = try #require(NumberedNoteDetector.chapters(on: page))
        result.heads[page.number] = heads
        page.lines.removeAll { $0.text.contains("NOTES TO CHAPTER") }
        let adjacent = previous?.number == page.number - 1
        var warnings: [ConversionWarning] = []
        var layout: NumberedNoteDetector.Layout?
        let blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings,
            noteChapter: heads.lowerBound, noteLastChapter: heads.upperBound,
            continuingNoteList: carry && adjacent ? open : nil, noteLayout: { layout = $0 })
        result.layouts[page.number] = try #require(layout, "\(name)")
        result.pages[page.number] = blocks
        open = layout?.openList
        LayoutReconstructor.appendPage(blocks, page: page, previousPage: adjacent ? previous : nil,
            to: &result.blocks, vocabulary: [], warnings: &warnings)
        previous = page
    }
    return result
}

private func keys(_ blocks: [ReflowBlock], page: Int) -> [NoteKey] {
    blocks.filter { $0.page == page }.compactMap(\.note)
}

private func chapterKeys(_ numbers: ClosedRange<Int>, _ chapter: Int) -> [NoteKey] {
    numbers.map { NoteKey(number: $0, scope: .chapter(chapter)) }
}

private func body(_ marker: String, page: Int) -> ReflowBlock {
    ReflowBlock(content: .paragraph(InlineText(elements: [.text("Cited.", []), .text(marker, .superscript)])), page: page)
}

@Test func misprintedNotesHeadIsScopedByNumberingContinuity() throws {
    // Page 495 ends chapter 3's note 92; page 496, headed NOTES TO CHAPTER 4, holds 93–112; page 497
    // continues with 113–114 and opens chapter 4 at note 1; page 502 holds chapter 4's real 93–112.
    var notes = try run(["911-495", "911-496", "911-497", "911-502"])
    #expect(notes.heads == [495: 3...3, 496: 4...4, 497: 3...3, 502: 4...4])
    // Reproducer: as printed, 496's notes collide with 502's in chapter 4.
    #expect(keys(notes.blocks, page: 496) == chapterKeys(93...112, 4))
    #expect(keys(notes.blocks, page: 502).suffix(20) == chapterKeys(93...112, 4)[...])
    var unscoped = notes.blocks + [body("93", page: 115), body("93", page: 143)]
    let before = NoteLinker.link(&unscoped) { $0 == 115 ? 3 : $0 == 143 ? 4 : nil }
    #expect(before.linked == 0 && before.missing == 1 && before.ambiguous == 1 && before.ambiguousNotes == 20)

    let decisions = NumberedNoteDetector.scopeByContinuity(&notes.blocks, heads: notes.heads)
    #expect(decisions == [.init(page: 496, printed: 4, chapter: 3, numbers: 93...112)])
    #expect(keys(notes.blocks, page: 496) == chapterKeys(93...112, 3))
    #expect(keys(notes.blocks, page: 495).last == NoteKey(number: 92, scope: .chapter(3)))
    #expect(keys(notes.blocks, page: 497) == chapterKeys(113...114, 3) + chapterKeys(1...7, 4))
    #expect(keys(notes.blocks, page: 502).suffix(20) == chapterKeys(93...112, 4)[...])
    let note93 = try #require(notes.blocks.first { $0.note == NoteKey(number: 93, scope: .chapter(3)) })
    #expect(note93.text.hasPrefix("93.John Hamre interview"))
    var blocks = notes.blocks + [body("93", page: 115), body("93", page: 143)]
    let after = NoteLinker.link(&blocks) { $0 == 115 ? 3 : $0 == 143 ? 4 : nil }
    #expect(after.linked == 2 && after.ambiguous == 0 && after.ambiguousNotes == 0)
    // A second pass finds nothing further to move.
    #expect(NumberedNoteDetector.scopeByContinuity(&notes.blocks, heads: notes.heads).isEmpty)
}

@Test func printedHeadsWinUnlessContinuityContradictsThemFromBothSides() {
    func note(_ number: Int, _ chapter: Int, page: Int) -> ReflowBlock {
        ReflowBlock(content: .paragraph(InlineText("\(number). Note.")), note: NoteKey(number: number, scope: .chapter(chapter)), page: page)
    }
    func notes(_ numbers: ClosedRange<Int>, _ chapter: Int, page: Int) -> [ReflowBlock] {
        numbers.map { note($0, chapter, page: page) }
    }
    // Page 11 is headed chapter 4 but continues page 10's chapter 3; chapter 4 opens on page 12
    // and holds 93–95 again on page 13.
    let pages: [Int: [ReflowBlock]] = [10: notes(90...92, 3, page: 10), 11: notes(93...95, 4, page: 11),
                                       12: notes(1...3, 4, page: 12), 13: notes(93...95, 4, page: 13)]
    let heads: [Int: ClosedRange<Int>] = [10: 3...3, 11: 4...4, 12: 4...4, 13: 4...4]
    func decide(_ pages: [Int: [ReflowBlock]], heads: [Int: ClosedRange<Int>] = heads) -> [NumberedNoteDetector.Rescope] {
        var blocks = pages.keys.sorted().flatMap { pages[$0]! }
        let saved = blocks
        let decisions = NumberedNoteDetector.scopeByContinuity(&blocks, heads: heads)
        if decisions.isEmpty { #expect(blocks == saved) }
        #expect(blocks.map(\.text) == saved.map(\.text))
        return decisions
    }
    #expect(decide(pages) == [.init(page: 11, printed: 4, chapter: 3, numbers: 93...95)])
    var controls: [(String, [Int: [ReflowBlock]], [Int: ClosedRange<Int>])] = []
    var variant = pages
    variant[11] = notes(1...3, 4, page: 11); variant[12] = notes(4...6, 4, page: 12)
    controls.append(("numbers restart at 1", variant, heads))
    variant = pages; variant[11] = notes(94...96, 4, page: 11)
    controls.append(("a gap after the previous page", variant, heads))
    variant = pages; variant[12] = notes(4...6, 4, page: 12)
    controls.append(("the printed chapter has no note 1 elsewhere", variant, heads))
    variant = pages; variant[13] = nil
    controls.append(("no collision in the printed chapter", variant, heads))
    variant = pages; variant[14] = notes(93...93, 3, page: 14)
    controls.append(("the continued chapter already claims a number", variant, heads.merging([14: 3...3]) { $1 }))
    controls.append(("a two-chapter head", pages, heads.merging([11: 3...4]) { $1 }))
    variant = pages; variant[9] = variant[10]!.map { var block = $0; block.page = 9; return block }; variant[10] = nil
    controls.append(("the previous notes page is not adjacent", variant, heads.merging([9: 3...3]) { $1 }))
    variant = pages; variant[10] = notes(90...92, 4, page: 10)
    controls.append(("a chapter's notes genuinely continue", variant, heads.merging([10: 4...4]) { $1 }))
    variant = pages; variant[11] = [note(93, 4, page: 11), note(1, 5, page: 11)]
    controls.append(("a page that switches chapters", variant, heads))
    for (reason, variant, heads) in controls {
        #expect(decide(variant, heads: heads).isEmpty, "\(reason)")
    }
}

@Test func candidateListContinuesNote107AcrossPages543To545() throws {
    let notes = try run(["911-543", "911-544", "911-545"])
    let open543 = try #require(notes.layouts[543]?.openList)
    #expect(open543.note == .init(number: 107, chapter: 7) && open543.next == 7 && abs(open543.inset - 12) < 0.01)
    #expect(notes.layouts[544]?.notes.isEmpty == true)
    #expect(notes.layouts[544]?.openList?.next == 10)
    #expect(notes.layouts[545]?.openList == nil)
    // Page 544 holds no note start: its items are further paragraphs of note 107.
    #expect(keys(notes.blocks, page: 544).isEmpty)
    #expect(keys(notes.blocks, page: 545) == chapterKeys(108...114, 7))
    let items = notes.blocks.filter { $0.text.range(of: "^(?:[7-9]|10)\\. ", options: .regularExpression) != nil }
    #expect(items.map { String($0.text.prefix(3)) } == ["7. ", "8. ", "9. ", "10."])
    #expect(items.allSatisfy { block in
        guard block.note == nil, case .paragraph = block.content else { return false }
        return true
    })
    #expect(items[3].text.hasPrefix("10. Abderraouf Jdey, a.k.a. Faruq al Tunisi. A Canadian passport holder, he may have trained in Afghanistan with Khalid al Mihdhar"))
    #expect(items[3].text.hasSuffix("Intelligence report, interrogation of KSM, July 1, 2003."))
    #expect(!notes.blocks.contains { if case .preformatted = $0.content { true } else { false } })
    let thereafter = try #require(notes.blocks.first { $0.text.hasPrefix("Thereafter, Hamlan") })
    #expect(thereafter.text.contains("Khalid al Zahrani, who asked why he had not returned to Afghanistan."))
    // Item 6 still continues from 543 onto 544, and item 9's last paragraph from 544 onto 545.
    #expect(notes.blocks.contains { $0.text.hasPrefix("6. Zuhair al Thubaiti") && $0.text.contains("(two reports).") })
    #expect(notes.blocks.contains { $0.text.hasPrefix("Despite instructions") && $0.text.hasSuffix("who confiscated his passport.") })
    // Every source character survives.
    var sources: [Character] = []
    for name in ["911-543", "911-544", "911-545"] {
        sources += try SourceLayoutFixture.load(name).content().lines.map(\.text)
            .filter { !$0.contains("NOTES TO CHAPTER") }.joined().filter { !$0.isWhitespace }
    }
    #expect(notes.blocks.map(\.text).joined().filter { !$0.isWhitespace && $0 != "-" }.sorted()
            == sources.filter { $0 != "-" }.sorted())

    // Negative control: without the carried list, 544's items are chapter 7's notes 7–9 (colliding
    // with page 532's) and 545's item 10 is a preformatted first line.
    let unlinked = try run(["911-543", "911-544", "911-545"], carry: false)
    #expect(keys(unlinked.blocks, page: 544) == chapterKeys(7...9, 7))
    #expect(unlinked.pages[545]?.contains { block in
        guard case .preformatted = block.content else { return false }
        return block.text == "10. Abderraouf Jdey, a.k.a. Faruq al Tunisi. A Canadian passport holder, he may have trained in"
    } == true)
}

@Test func openListsResumeOnlyWhereNumbersContinueTheListNotTheChapter() throws {
    // Page 532 opens with chapter 7's genuine notes 3–13. Handed a list from note 2 whose next item
    // would be 3, the page keeps its notes: 3 continues the chapter as well.
    var page532 = try SourceLayoutFixture.load("911-532").content()
    page532.lines.removeAll { $0.text.contains("NOTES TO CHAPTER") }
    let elements532 = page532.lines.map { LayoutReconstructor.Element(rect: $0.rect, line: $0) }
    let plain532 = try #require(NumberedNoteDetector.layout(in: elements532, page: page532, chapter: 7))
    #expect(plain532.notes.values.map(\.number).sorted().prefix(3) == [3, 4, 5])
    let chapterContinues = NumberedNoteDetector.OpenList(note: .init(number: 2, chapter: 7), next: 3, inset: 12)
    #expect(NumberedNoteDetector.layout(in: elements532, page: page532, chapter: 7, continuing: chapterContinues) == plain532)
    let first532 = try #require(NumberedNoteDetector.firstStart(in: elements532))
    #expect(NumberedNoteDetector.resumption(elements532, open: chapterContinues, first: first532) == nil)
    // Nor is a list from another chapter resumed.
    let otherChapter = NumberedNoteDetector.OpenList(note: .init(number: 107, chapter: 6), next: 3, inset: 12)
    #expect(NumberedNoteDetector.layout(in: elements532, page: page532, chapter: 7, continuing: otherChapter) == plain532)

    // Page 545 with the list's expected item wrong, or its inset wrong, is read on its own.
    var page545 = try SourceLayoutFixture.load("911-545").content()
    page545.lines.removeAll { $0.text.contains("NOTES TO CHAPTER") }
    let elements545 = page545.lines.map { LayoutReconstructor.Element(rect: $0.rect, line: $0) }
    let plain545 = try #require(NumberedNoteDetector.layout(in: elements545, page: page545, chapter: 7))
    for open in [NumberedNoteDetector.OpenList(note: .init(number: 107, chapter: 7), next: 9, inset: 12),
                 NumberedNoteDetector.OpenList(note: .init(number: 107, chapter: 7), next: 10, inset: 24),
                 NumberedNoteDetector.OpenList(note: .init(number: 106, chapter: 7), next: 10, inset: 12)] {
        #expect(NumberedNoteDetector.layout(in: elements545, page: page545, chapter: 7, continuing: open) == plain545, "\(open)")
    }
    let resumed = try #require(NumberedNoteDetector.layout(in: elements545, page: page545, chapter: 7,
        continuing: .init(note: .init(number: 107, chapter: 7), next: 10, inset: 12)))
    #expect(resumed.notes.values.map(\.number).sorted() == Array(108...114))
    #expect(resumed.paragraphs[0] == 0 && plain545.paragraphs[0] == nil)

    // A page whose note list ends before the page does, or ends on a short line, leaves no open list;
    // bullets never do (page 583's note 4).
    #expect(plain545.openList == nil && plain532.openList == nil)
    var page583 = try SourceLayoutFixture.load("911-583").content()
    page583.lines.removeAll { $0.text.contains("NOTES TO CHAPTER") }
    let elements583 = page583.lines.map { LayoutReconstructor.Element(rect: $0.rect, line: $0) }
    #expect(NumberedNoteDetector.layout(in: elements583, page: page583, chapter: 12)?.openList == nil)
    func synthetic(lastWidth: Double) -> NumberedNoteDetector.Layout? {
        func line(_ text: String, _ x: Double, _ y: Double, _ width: Double = 400) -> TextLine {
            TextLine(text: text, rect: CGRect(x: x, y: y, width: width, height: 10), fontSize: 10)
        }
        let page = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 600, height: 800), lines: [
            line("38. First source citation.", 60, 700, 200),
            line("39.Second citation begins with sufficient text to wrap", 60, 688),
            line("and continues on the following line.", 40, 676, 420),
            line("40. Third source citation introduces its list:", 60, 664),
            line("1. First candidate operative, whose entry wraps", 77, 640, 383),
            line("back to the note indent on its second line.", 60, 626, lastWidth),
        ], graphics: [])
        return NumberedNoteDetector.layout(in: page.lines.map { .init(rect: $0.rect, line: $0) }, page: page, chapter: 1)
    }
    #expect(synthetic(lastWidth: 400)?.openList == .init(note: .init(number: 40, chapter: 1), next: 2, inset: 17))
    #expect(synthetic(lastWidth: 200)?.openList == nil)
}
