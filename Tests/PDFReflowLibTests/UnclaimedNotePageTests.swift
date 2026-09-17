import Foundation
import Testing
@testable import PDFReflowLib

// 9/11 notes pages 543, 571, 572, 578 and 581–583 were refused by the numbered-note run, so each
// note's first line became a `<pre>` and its wrapped lines separate paragraphs (#80). Four pages
// lost lines around web addresses with `=` to formula crops, two carry `NOTES TO CHAPTERS 9-10`
// heads, and two hold a list inside a note.

private let gpo911SHA256 = "657d41475eb3a9a5e3e87a6c7c51ac1dfbe1af7566d1abff7bf7286e7e1c0e1b"

/// The page as the pipeline reconstructs it: the head's chapters read before furniture removal
/// takes the head, and graphical regions (including formula crops) preserved as images.
private func pipelineBlocks(_ name: String) throws -> (page: PageContent, blocks: [ReflowBlock], chapters: ClosedRange<Int>?) {
    let fixture = try SourceLayoutFixture.load(name)
    #expect(fixture.sourceSHA256 == gpo911SHA256)
    var page = fixture.content()
    let chapters = NumberedNoteDetector.chapters(on: page)
    let head = try #require(page.lines.max { $0.rect.midY < $1.rect.midY })
    #expect(head.text.contains("NOTES TO CHAPTER"))
    page.lines.removeAll { $0 == head }
    let regions = LayoutReconstructor.graphicsWithLabels(page).enumerated().map { ($0.element, "image-\($0.offset)") }
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: regions, vocabulary: [], warnings: &warnings,
        noteChapter: chapters?.lowerBound, noteLastChapter: chapters?.upperBound)
    return (page, blocks, chapters)
}

private func sources(_ texts: [String]) -> [Character] {
    texts.joined().filter { !$0.isWhitespace }.sorted()
}

@Test(arguments: [
    ("911-543", 7...7, [7: Array(100...107)]),
    ("911-571", 9...9, [9: Array(194...208)]),
    ("911-572", 9...10, [9: [209, 210], 10: Array(1...8)]),
    ("911-578", 10...11, [10: Array(76...86), 11: Array(1...13)]),
    ("911-581", 12...12, [12: Array(14...32)]),
    ("911-582", 12...12, [12: Array(33...38)]),
    ("911-583", 12...12, [12: Array(39...42), 13: Array(1...4)]),
])
func refusedNotesPagesNowReflowEachNoteWhole(name: String, head: ClosedRange<Int>, notes: [Int: [Int]]) throws {
    let (page, blocks, chapters) = try pipelineBlocks(name)
    // 583's head names chapter 12 only; the page switches to 13 at its `13 How to Do It?` heading,
    // as page 484 does.
    #expect(chapters == head)
    // No line is lost to a crop, no note line is preformatted, and every source character survives.
    #expect(!blocks.contains { if case .image = $0.content { true } else { false } })
    #expect(!blocks.contains { if case .preformatted = $0.content { true } else { false } })
    #expect(sources(blocks.map(\.text)) == sources(page.lines.map(\.text).filter { !$0.contains("NOTES TO CHAPTER") }))
    var found: [Int: [Int]] = [:]
    for block in blocks {
        guard let key = block.note, case let .chapter(chapter) = key.scope else { continue }
        found[chapter, default: []].append(key.number)
        #expect(block.text.hasPrefix("\(key.number)."), "\(name) note \(key.number)")
    }
    #expect(found == notes)
    // Each note holds all of its wrapped lines: the block ends where the next numbered start
    // or the page's next paragraph begins, so no paragraph opens with a lowercase wrap.
    #expect(!blocks.contains { block in
        guard case .paragraph = block.content, let first = block.text.first else { return false }
        return first.isLowercase && block.note == nil && block.text != blocks.first?.text
    }, "\(name)")
}

@Test func gpo911NoteWrapsAndAddressesStayInsideTheirNotes() throws {
    let (_, page543, _) = try pipelineBlocks("911-543")
    let note104 = try #require(page543.first { $0.text.hasPrefix("104.") })
    #expect(note104.text.hasPrefix("104. Intelligence reports, interrogations of KSM, May 15, 2003; Jan. 9, 2004;Apr. 2, 2004; Intelligence report, interrogation of Khallad, Apr. 13, 2004;"))
    // Note 107 introduces a numbered list whose items are further paragraphs of the note: each
    // item wraps back to the note indent and keeps those lines.
    let items = page543.filter { $0.note == nil && $0.text.range(of: "^(?:[1-6]|4 and 5)\\. ", options: .regularExpression) != nil }
    #expect(items.map { String($0.text.prefix(2)) } == ["1.", "2.", "3.", "4 ", "6."])
    #expect(items[0].text.contains("he is the last known Saudi mus-cle candidate"))
    #expect(items[3].text.hasPrefix("4 and 5. Saeed al Baluchi and Qutaybah al Najdi. Both were sent to Saudi Arabia via Bahrain, where Najdi"))
    let note107 = try #require(page543.first { $0.text.hasPrefix("107.") })
    #expect(note107.text.hasSuffix("20, 2004. The candidate operatives were"))

    let (_, page571, _) = try pipelineBlocks("911-571")
    let note200 = try #require(page571.first { $0.text.hasPrefix("200.") })
    #expect(note200.text.contains("(online at http://worldtradeaftermath.com/wta/contacts/companies_list.asp?letter=a); CNN,WTC tenants, 2001 (online at www.cnn.com/SPECIALS/2001/trade.center/tenants1.html); September 11 personal tributes"))

    let (_, page581, _) = try pipelineBlocks("911-581")
    let note24 = try #require(page581.first { $0.text.hasPrefix("24.") })
    // The address broken after `content_` rejoins without a space (#79).
    #expect(note24.text.hasSuffix("(online at www.pewtrusts.com/ideas/ideas_item.cfm?content_item_id=1645&content_type_id=7)."))

    let (_, page583, _) = try pipelineBlocks("911-583")
    let bullets = page583.filter { $0.text.hasPrefix("• ") }
    #expect(bullets.count == 5 && bullets.allSatisfy { $0.note == nil })
    // Without a book vocabulary the line-ending hyphens stay literal.
    #expect(bullets[1].text == "• Similarly, the FBI’s Counterterrorism Division would remain, as now, the operational arm of the Bureau to combat terrorism.As it does now, it would work with other agencies in carrying out these missions, retain-ing the JTTF structure now in place.The Counterterrorism Division would rely on the FBI’s Office of Intel-ligence to train and equip its personnel, helping to process and report the information gathered in the field.")
    let note4 = try #require(page583.first { $0.note == NoteKey(number: 4, scope: .chapter(13)) })
    #expect(note4.text.hasSuffix("should be concentrated more effectively than they are now."))
}

@Test func twoChapterNotesHeadsNameOnlyConsecutiveChapters() {
    func page(_ head: String) -> PageContent {
        PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 600, height: 800), lines: [
            TextLine(text: head, rect: CGRect(x: 40, y: 754, width: 200, height: 10), fontSize: 10),
        ], graphics: [])
    }
    #expect(NumberedNoteDetector.chapters(on: page("554 NOTES TO CHAPTERS 9-10")) == 9...10)
    #expect(NumberedNoteDetector.chapters(on: page("NOTES TO CHAPTERS 9\u{2013}10 554")) == 9...10)
    #expect(NumberedNoteDetector.chapters(on: page("NOTES TO CHAPTER 9 551")) == 9...9)
    #expect(NumberedNoteDetector.chapter(on: page("554 NOTES TO CHAPTERS 9-10")) == 9)
    for head in ["NOTES TO CHAPTERS 9-11", "NOTES TO CHAPTERS 10-9", "NOTES TO CHAPTER 9-10",
                 "NOTES TO CHAPTERS 9", "NOTES TO CHAPTERS 9-", "NOTES TO CHAPTERS 0-1", "NOTES TO CHAPTERS 9-10-11"] {
        #expect(NumberedNoteDetector.chapters(on: page(head)) == nil, "\(head)")
    }
}

@Test func twoChapterHeadRequiresTheSecondChaptersOpening() throws {
    // Source page 572 opens chapter 10 at `10 Wartime`, after chapter 9's notes 209 and 210.
    var page = try SourceLayoutFixture.load("911-572").content()
    page.lines.removeAll { $0.text.contains("NOTES TO CHAPTERS") }
    let elements = page.lines.map { LayoutReconstructor.Element(rect: $0.rect, line: $0) }
    let layout = try #require(NumberedNoteDetector.layout(in: elements, page: page, chapter: 9, lastChapter: 10))
    #expect(Set(layout.notes.values.map(\.chapter)) == [9, 10])
    // The two-chapter head adds nothing else: read as a one-chapter head the page is the same.
    #expect(NumberedNoteDetector.layout(in: elements, page: page, chapter: 9) == layout)
    // A page headed 1-2 whose notes never open chapter 2 is refused; headed 1 it is accepted.
    let single = listNotePage([])
    let lines = single.lines.map { LayoutReconstructor.Element(rect: $0.rect, line: $0) }
    #expect(NumberedNoteDetector.layout(in: lines, page: single, chapter: 1) != nil)
    #expect(NumberedNoteDetector.layout(in: lines, page: single, chapter: 1, lastChapter: 1) != nil)
    #expect(NumberedNoteDetector.layout(in: lines, page: single, chapter: 1, lastChapter: 2) == nil)
    var headed = single
    headed.lines.insert(TextLine(text: "NOTES TO CHAPTERS 1-2", rect: CGRect(x: 40, y: 754, width: 180, height: 10), fontSize: 10), at: 0)
    #expect(NumberedNoteDetector.groups(in: headed.lines.map { .init(rect: $0.rect, line: $0) }, page: headed).isEmpty)
    headed.lines[0] = TextLine(text: "NOTES TO CHAPTER 1", rect: headed.lines[0].rect, fontSize: 10)
    #expect(!NumberedNoteDetector.groups(in: headed.lines.map { .init(rect: $0.rect, line: $0) }, page: headed).isEmpty)
}

/// A synthetic chapter-1 notes page: notes 38–40, the second wrapping to the dedented edge.
private func listNotePage(_ extra: [TextLine]) -> PageContent {
    func line(_ text: String, _ x: Double, _ y: Double, _ width: Double = 400) -> TextLine {
        TextLine(text: text, rect: CGRect(x: x, y: y, width: width, height: 10), fontSize: 10)
    }
    return PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 600, height: 800), lines: [
        line("38. First source citation.", 60, 700, 200),
        line("39.Second citation begins with sufficient text to wrap", 60, 688),
        line("and continues on the following line.", 40, 676),
        line("40. Third source citation introduces its list:", 60, 664),
    ] + extra, graphics: [])
}

private func listLayout(_ extra: [TextLine]) -> NumberedNoteDetector.Layout? {
    let page = listNotePage(extra)
    return NumberedNoteDetector.layout(in: page.lines.map { .init(rect: $0.rect, line: $0) }, page: page, chapter: 1)
}

private func line(_ text: String, _ x: Double, _ y: Double, width: Double = 400) -> TextLine {
    TextLine(text: text, rect: CGRect(x: x, y: y, width: width, height: 10), fontSize: 10)
}

@Test func listsInsideNotesAreFurtherParagraphsOfTheirNote() throws {
    // Numbered items inside the note indent after added space (page 543), wrapping to the note
    // indent; an item's further paragraph at the item edge; then the next note.
    let numbered = [
        line("1. First candidate operative, whose entry wraps", 77, 640),
        line("back to the note indent on its second line.", 60, 626),
        line("2. Second candidate operative.", 77, 614, width: 200),
        line("A further paragraph under the second item.", 77, 602),
        line("3 and 4. Third and fourth operatives together.", 77, 590),
        line("41. The next note resumes the sequence.", 60, 578),
    ]
    let layout = try #require(listLayout(numbered))
    #expect(layout.notes.values.map(\.number).sorted() == [38, 39, 40, 41])
    #expect(layout.paragraphs[4] == 4 && layout.paragraphs[5] == 4)
    #expect(layout.paragraphs[6] == 6 && layout.paragraphs[7] == 7 && layout.paragraphs[8] == 8)
    #expect(layout.notes[4] == nil && layout.notes[9]?.number == 41)
    // Bullets at the note indent with hanging wraps (page 583).
    let bullets = [
        line("• The first bullet of the note runs long enough", 60, 650),
        line("to wrap to its hanging indent.", 64, 638),
        line("• The second bullet.", 60, 626, width: 200),
    ]
    let bulleted = try #require(listLayout(bullets))
    #expect(bulleted.paragraphs[4] == 4 && bulleted.paragraphs[5] == 4 && bulleted.paragraphs[6] == 6)
    #expect(bulleted.notes.count == 3)
    // Controls: a numbered list that does not open at 1, one set deeper than three body sizes,
    // one opened after more than 1.6 body sizes of space, one that skips an item, and a bullet
    // wrap set at neither the hanging nor the note edge all still refuse the page.
    var controls: [[TextLine]] = []
    controls.append([line("2. Opens mid-sequence.", 77, 640)])
    controls.append([line("1. Too deep for an item.", 95, 640)])
    controls.append([line("1. After a wide gap.", 77, 630)])
    controls.append([line("1. First item.", 77, 640, width: 200), line("3. Skips an item.", 77, 628, width: 200)])
    controls.append([line("• A bullet that runs long enough", 60, 650), line("to wrap far past its hanging edge.", 90, 638)])
    for control in controls {
        #expect(listLayout(control) == nil, "\(control.map(\.text))")
    }
    // The page without a list is accepted.
    #expect(listLayout([]) != nil)
}

@Test func urlQueryStringsDoNotSeedFormulaCrops() throws {
    for word in ["http://people-press.org/reports/print.php3?ReportID=145).", "www.dhs.gov/dhspublic/display?theme=45&content=3498&print=true).",
                 "www.nftc.org/newsflash/newsflash.asp?Mode=View&articleid=1686&Category=All).", "item_id=1645&content_type_id=7).",
                 "http://worldtradeaftermath.com/wta/contacts/companies_list.asp?letter=a);"] {
        #expect(LayoutReconstructor.isURLQuery(Substring(word)), "\(word)")
    }
    for word in ["x=2", "y=mx+b", "E=mc2", "a=b&c", "f(x)=3", "?=", "P(A?B)=0.5", "x&y=1"] {
        #expect(!LayoutReconstructor.isURLQuery(Substring(word)), "\(word)")
    }
    for name in ["911-571", "911-581", "911-582", "911-583"] {
        let page = try SourceLayoutFixture.load(name).content()
        #expect(page.lines.contains { $0.text.contains("=") })
        #expect(LayoutReconstructor.graphicsWithLabels(page).isEmpty, "\(name)")
    }
    // Controls: an equation, and an equation beside an address, are still preserved.
    let equation = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 600, height: 800), lines: [
        line("y = 2x + 3", 200, 500, width: 80),
        line("see www.example.gov/a.asp?b=1 where k = 4", 40, 300, width: 300),
    ], graphics: [])
    #expect(LayoutReconstructor.graphicsWithLabels(equation).count == 2)
}
