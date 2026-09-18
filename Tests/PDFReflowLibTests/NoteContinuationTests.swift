import Foundation
import CoreText
import Testing
#if os(macOS)
import AppKit
private typealias TestFont = NSFont
#else
import UIKit
private typealias TestFont = UIFont
#endif
@testable import PDFReflowLib

// 9/11 endnotes whose text runs onto the next page opening with a capital, a digit or a quote (#11):
// the lines above the page's first note start were spatial prose, joined to the note only when they
// opened lowercase, and split wherever an indented line or a list-like `2002.` came. And two body
// markers PDFKit measured as base text (`”12` on page 362, `”32` on page 369).

private let gpo911SHA256 = "657d41475eb3a9a5e3e87a6c7c51ac1dfbe1af7566d1abff7bf7286e7e1c0e1b"

private struct Chain {
    var blocks: [ReflowBlock] = []
    var layouts: [Int: NumberedNoteDetector.Layout] = [:]
}

/// Notes pages reconstructed in order as the pipeline does: the head read before its removal, the
/// previous page's open list and last note handed to the next physical page (when `carry` is on),
/// and adjacent pages joined with the detector's continuation evidence.
private func chain(_ names: [String], carry: Bool = true) throws -> Chain {
    var result = Chain()
    var previous: PageContent?
    var open: NumberedNoteDetector.OpenList?
    var last: NumberedNoteDetector.Layout.Note?
    for name in names {
        let fixture = try SourceLayoutFixture.load(name)
        #expect(fixture.sourceSHA256 == gpo911SHA256)
        var page = fixture.content()
        let heads = try #require(NumberedNoteDetector.chapters(on: page))
        page.lines.removeAll { $0.text.contains("NOTES TO CHAPTER") }
        let adjacent = previous?.number == page.number - 1
        var warnings: [ConversionWarning] = []
        var layout: NumberedNoteDetector.Layout?
        let blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings,
            noteChapter: heads.lowerBound, noteLastChapter: heads.upperBound,
            continuingNoteList: carry && adjacent ? open : nil, noteLayout: { layout = $0 },
            continuingNote: carry && adjacent ? last : nil)
        result.layouts[page.number] = try #require(layout, "\(name)")
        open = layout?.openList
        last = layout?.lastNote
        LayoutReconstructor.appendPage(blocks, page: page, previousPage: adjacent ? previous : nil,
            to: &result.blocks, vocabulary: [], continuesNote: carry && layout?.continuesParagraph == true,
            warnings: &warnings)
        previous = page
    }
    return result
}

private func block(_ blocks: [ReflowBlock], containing text: String) -> ReflowBlock? {
    blocks.first { $0.text.contains(text) }
}

private func note(_ blocks: [ReflowBlock], _ number: Int, chapter: Int) -> ReflowBlock? {
    blocks.first { $0.note == NoteKey(number: number, scope: .chapter(chapter)) }
}

@Test func noteContinuedWithAQuoteJoinsThePreviousPagesNote() throws {
    // Page 531 ends chapter 7's note 2 on `see, e.g., CIA analytic report,`; page 532 opens at the
    // dedented edge with `“Alternate View: …` and then note 3.
    let notes = try chain(["911-531", "911-532"])
    let layout = try #require(notes.layouts[532])
    #expect(layout.continuesParagraph)
    #expect(notes.layouts[531]?.lastNote == .init(number: 2, chapter: 7))
    let joined = try #require(note(notes.blocks, 2, chapter: 7))
    #expect(joined.text.contains("CIA analytic report, “Alternate View:Two 11 September Hijackers"))
    #expect(joined.text.contains("concentrate on that mission"))
    #expect(joined.sourcePages == [532])
    #expect(!notes.blocks.contains { $0.content == .sourcePage(532) })
    // Note 3 follows its predecessor; nothing unkeyed sits between them.
    let index = try #require(notes.blocks.firstIndex { $0.note == NoteKey(number: 2, scope: .chapter(7)) })
    #expect(notes.blocks[index + 1].note == NoteKey(number: 3, scope: .chapter(7)))

    // Negative control: without the hand-off the page reads as before, the quote a paragraph of its own.
    let before = try chain(["911-531", "911-532"], carry: false)
    #expect(before.layouts[532]?.continuesParagraph == false)
    #expect(block(before.blocks, containing: "“Alternate View:")?.note == nil)
    #expect(block(before.blocks, containing: "“Alternate View:")?.text.hasPrefix("“Alternate View:") == true)
}

@Test func noteContinuationsOpeningWithDigitsBracketsAndCapitalsJoin() throws {
    // 472 → 473: note 54 continues `(Sept.` + `24,2003);`.
    let first = try chain(["911-472", "911-473"])
    let note54 = try #require(note(first.blocks, 54, chapter: 1))
    #expect(note54.text.contains("(Sept. 24,2003);Linda Povinelli interview"))
    #expect(first.layouts[473]?.continuesParagraph == true)

    // 579 → 580 → 581 → 582: chapter 11's note 39 continues with `(Nov. 10, 2003)`, chapter 12's
    // note 13 with `2003).For the request`, and note 32 with `Waleed al Shehri`.
    let second = try chain(["911-579", "911-580", "911-581", "911-582"])
    #expect(note(second.blocks, 39, chapter: 11)?.text.contains("Louis Andre interview (Nov. 10, 2003)") == true)
    #expect(note(second.blocks, 13, chapter: 12)?.text.contains("(Oct. 2003).For the request") == true)
    #expect(note(second.blocks, 32, chapter: 12)?.text.contains("(Wail al Shehri, Waleed al Shehri,") == true)
    for page in [580, 581, 582] {
        #expect(second.layouts[page]?.continuesParagraph == true, "\(page)")
        #expect(!second.blocks.contains { $0.content == .sourcePage(page) }, "\(page)")
    }
    // Without the hand-off each continuation stays a separate unkeyed paragraph, except that the
    // body join carries `Waleed al Shehri` on after the parenthesis `(Wail al Shehri,` leaves open
    // (#145).
    let before = try chain(["911-579", "911-580", "911-581", "911-582"], carry: false)
    for opening in ["(Nov. 10, 2003)", "2003).For the request"] {
        #expect(block(before.blocks, containing: opening)?.text.hasPrefix(opening) == true, "\(opening)")
    }
    #expect(block(before.blocks, containing: "Waleed al Shehri, Mohand")?.text.contains("(Wail al Shehri, Waleed al Shehri, Mohand") == true)
}

@Test func furtherParagraphAtTheIndentStaysItsOwnParagraphButKeepsItsWrappedLines() throws {
    // Page 497 ends chapter 4's note 7 with a full stop; page 498 opens at the note indent with a
    // further paragraph, `President Clinton, in a February 2002 speech … did` / `not accept …`.
    let notes = try chain(["911-497", "911-498"])
    let layout = try #require(notes.layouts[498])
    #expect(!layout.continuesParagraph)
    let paragraph = try #require(block(notes.blocks, containing: "President Clinton, in a February 2002"))
    #expect(paragraph.note == nil && paragraph.text.hasPrefix("President Clinton"))
    #expect(paragraph.text.contains("the United States did not accept a Sudanese offer"))
    #expect(block(notes.blocks, containing: "much recent controversy.")?.text.contains("controversy. After repeatedly demanding") == true)
    #expect(notes.blocks.contains { $0.content == .sourcePage(498) })
    // Before, spatial prose split each further paragraph after its first line. Since #147 an indented
    // opening line runs onto its wrapped lines without the hand-off too.
    let before = try chain(["911-497", "911-498"], carry: false)
    #expect(block(before.blocks, containing: "President Clinton, in a February 2002")?.text.contains("the United States did not accept") == true)
}

@Test func paragraphAfterAListThatEndsShortIsNotJoined() throws {
    // Page 583 ends chapter 13's note 4 with a bullet whose last line is short; page 584 opens flush
    // left with `The proposed National Counterterrorism Center…`, a new paragraph of that note.
    let notes = try chain(["911-583", "911-584"])
    #expect(notes.layouts[584]?.continuesParagraph == true)
    let paragraph = try #require(block(notes.blocks, containing: "The proposed National Counterterrorism Center"))
    #expect(paragraph.text.hasPrefix("The proposed National Counterterrorism Center"))
    #expect(notes.blocks.contains { $0.content == .sourcePage(584) })
    #expect(block(notes.blocks, containing: "foreign policy mission.")?.text.hasSuffix("foreign policy mission.") == true)
    // Its further paragraphs keep their wrapped lines.
    #expect(block(notes.blocks, containing: "The NCTC will not eliminate")?.text.contains("analytic units. But it would enable") == true)
}

@Test func continuedNoteReadingNeedsTheNextNoteNumberAndTheNotesGeometry() throws {
    let fixture = try SourceLayoutFixture.load("911-532")
    var page = fixture.content()
    page.lines.removeAll { $0.text.contains("NOTES TO CHAPTER") }
    var warnings: [ConversionWarning] = []
    func layout(_ lines: [TextLine], continued: NumberedNoteDetector.Layout.Note?) -> NumberedNoteDetector.Layout? {
        var copy = page
        copy.lines = lines
        var result: NumberedNoteDetector.Layout?
        _ = LayoutReconstructor.blocks(page: copy, images: [], vocabulary: [], warnings: &warnings,
            noteChapter: 7, noteLayout: { result = $0 }, continuingNote: continued)
        return result
    }
    let open = NumberedNoteDetector.Layout.Note(number: 2, chapter: 7)
    #expect(layout(page.lines, continued: open)?.continuesParagraph == true)
    #expect(layout(page.lines, continued: open)?.lastNote?.chapter == 7)
    // The page's first start must be the continued note's successor, in the same chapter.
    for other in [NumberedNoteDetector.Layout.Note(number: 1, chapter: 7), .init(number: 3, chapter: 7),
                  .init(number: 2, chapter: 6)] {
        let refused = layout(page.lines, continued: other)
        #expect(refused != nil && refused?.continuesParagraph == false, "\(other)")
        #expect(refused?.paragraphs[0] == nil, "\(other)")
    }
    let top = try #require(page.lines.max { $0.rect.minY < $1.rect.minY })
    func replacingTop(_ change: (inout TextLine) -> Void) -> [TextLine] {
        page.lines.map { line in
            guard line == top else { return line }
            var copy = line
            change(&copy)
            return copy
        }
    }
    // A larger line (a chapter's title), a line off both edges, and a numbered line at the indent
    // out of sequence keep the old reading, where the lines above the first start are not notes.
    let controls: [(String, [TextLine])] = [
        ("larger", replacingTop { $0.fontSize *= 1.5 }),
        ("off edge", replacingTop { $0.rect.origin.x += top.fontSize * 0.6 }),
        ("numbered", replacingTop {
            $0 = TextLine(text: "7. Alternate View: Two 11 September Hijackers Possibly Involved", rect: CGRect(
                x: top.rect.minX + top.fontSize * 1.71, y: top.rect.minY, width: top.rect.width, height: top.rect.height),
                fontSize: top.fontSize)
        }),
    ]
    for (name, lines) in controls {
        let refused = layout(lines, continued: open)
        #expect(refused?.continuesParagraph != true, "\(name)")
        #expect(refused?.paragraphs[0] == nil, "\(name)")
    }
}

@Test func appendPageJoinsACapitalOpeningOnlyWithTheDetectorsEvidence() throws {
    let notes = try chain(["911-531"])
    let fixture = try SourceLayoutFixture.load("911-532")
    var page = fixture.content()
    page.lines.removeAll { $0.text.contains("NOTES TO CHAPTER") }
    let previous = try SourceLayoutFixture.load("911-531").content()
    var warnings: [ConversionWarning] = []
    let pageBlocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings,
        noteChapter: 7, continuingNote: .init(number: 2, chapter: 7))
    for evidence in [false, true] {
        var blocks = notes.blocks
        LayoutReconstructor.appendPage(pageBlocks, page: page, previousPage: previous, to: &blocks,
            vocabulary: [], continuesNote: evidence, warnings: &warnings)
        #expect(blocks.contains { $0.content == .sourcePage(532) } == !evidence)
    }
    // A keyed note never continues another.
    var keyed = pageBlocks
    keyed[0].note = NoteKey(number: 3, scope: .chapter(7))
    var blocks = notes.blocks
    LayoutReconstructor.appendPage(keyed, page: page, previousPage: previous, to: &blocks, vocabulary: [],
        continuesNote: true, warnings: &warnings)
    #expect(blocks.contains { $0.content == .sourcePage(532) })
}

// MARK: - Markers PDFKit measured as base text

private func attributed(_ runs: [(String, CGFloat, Double)]) -> NSAttributedString {
    let value = NSMutableAttributedString()
    for (text, size, offset) in runs {
        value.append(NSAttributedString(string: text, attributes: [
            .font: pdfKitGated { TestFont(name: "Helvetica", size: size) }!,
            NSAttributedString.Key(kCTBaselineOffsetAttributeName as String): offset,
        ]))
    }
    return value
}

@Test func markerPieceMeasuredOnTheMarkerReadsAsSuperscript() throws {
    for (name, text) in [("911-362", "\u{201D}12"), ("911-369", "\u{201D}32")] {
        let fixture = try SourceLayoutFixture.load(name)
        #expect(fixture.sourceSHA256 == gpo911SHA256)
        let source = try #require(fixture.attributedLines.first { $0.text == text })
        #expect(source.runs.count == 2 && source.runs[0].baselineOffset < -3.4 && source.runs[1].baselineOffset == 0)
        let styled = NativeTextReader.inlineText(from: source.attributedString())
        #expect(styled.elements == [.text("\u{201D}", []), .text(String(text.dropFirst()), .superscript)], "\(name)")
    }
    // Controls: a marker four digits long or at a third of the size (the Blue Book scan's `I39`), a
    // marker run into text, and quotes lowered unevenly. An exponent after a letter or digit is never
    // re-measured as a marker; it is read from its base's baseline instead (#163), and raised.
    for runs in [[("x", 10.25, -3.44), ("2", 5.125, 0)], [("3", 10.25, -3.44), ("2", 5.125, 0)]] as [[(String, CGFloat, Double)]] {
        #expect(NativeTextReader.inlineText(from: attributed(runs)).elements.last == .text("2", .superscript))
    }
    let controls: [(String, [(String, CGFloat, Double)])] = [
        ("four digits", [("\u{201D}", 10.25, -3.44), ("1234", 5.125, 0)]),
        ("small", [("\u{201D}", 31.9, -8.15), ("39", 7.24, 0)]),
        ("run on", [("\u{201D}", 10.25, -3.44), ("12", 5.125, 0), ("It", 10.25, -3.44)]),
        ("uneven", [("\u{201D}", 10.25, -3.44), ("12 ", 5.125, 0), ("\u{2019}", 10.25, -1.2)]),
        ("barely lowered", [("\u{201D}", 10.25, -1.0), ("12", 5.125, 0)]),
    ]
    for (name, runs) in controls {
        let styled = NativeTextReader.inlineText(from: attributed(runs))
        let raised = styled.elements.contains { element in
            if case let .text(value, style) = element { return style.contains(.superscript) && value.contains(where: \.isNumber) }
            return false
        }
        #expect(!raised, "\(name)")
    }
    // Page 20's ordinary marker keeps its reading.
    let page20 = try SourceLayoutFixture.load("911-20")
    let line = try #require(page20.attributedLines.first { $0.text.contains("7:45.") })
    #expect(EPUBTextEncoder.inline(NativeTextReader.inlineText(from: line.attributedString())).contains("7:45.<sup>4</sup>"))
}

@Test func recoveredMarkerLinksToItsChapterNote() throws {
    for (name, marker, context) in [("911-362", 12, "to routine."), ("911-369", 32, "\u{201C}actionable.")] {
        let fixture = try SourceLayoutFixture.load(name)
        var warnings: [ConversionWarning] = []
        let page = fixture.styledContent()
        var blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings)
        let index = try #require(blocks.firstIndex { $0.text.contains(context) }, "\(name)")
        let key = NoteKey(number: marker, scope: .chapter(11))
        blocks.append(ReflowBlock(content: .paragraph(InlineText("\(marker). Note.")), note: key, page: 580))
        let summary = NoteLinker.link(&blocks) { $0 == page.number ? 11 : nil }
        // The page's other markers have no note here; only this one is offered a note.
        #expect(summary.linked == 1 && summary.ambiguous == 0, "\(name)")
        #expect(!blocks.contains { $0.text.trimmingCharacters(in: .whitespaces) == "\u{201D}\(marker)" }, "\(name)")
        guard case let .paragraph(text) = blocks[index].content else { Issue.record("\(name)"); continue }
        #expect(text.elements.contains(.noteReference(String(marker), [], key)), "\(name)")
        #expect(text.text.contains("\(context)\u{201D}\(marker)"), "\(name): \(text.text)")
    }
}

@Test func quotedMarkerPieceAttachesOnlyAtTheEndOfItsRow() throws {
    let fixture = try SourceLayoutFixture.load("911-362")
    let page = fixture.styledContent()
    let piece = try #require(page.lines.first { $0.text == "\u{201D}12" })
    let base = try #require(page.lines.first { $0.text == "to routine." })
    func reconstructed(moving offset: CGPoint) -> [ReflowBlock] {
        var copy = page
        copy.lines = page.lines.map { line in
            guard line == piece else { return line }
            var moved = line
            moved.rect = line.rect.offsetBy(dx: offset.x, dy: offset.y)
            return moved
        }
        var warnings: [ConversionWarning] = []
        return LayoutReconstructor.blocks(page: copy, images: [], vocabulary: [], warnings: &warnings)
    }
    #expect(reconstructed(moving: .zero).contains { $0.text.hasSuffix("to routine.\u{201D}12") })
    // A body size past the line's end, or a line below it, is not the line's marker.
    for offset in [CGPoint(x: base.fontSize, y: 0), CGPoint(x: 0, y: -base.rect.height)] {
        #expect(!reconstructed(moving: offset).contains { $0.text.hasSuffix("to routine.\u{201D}12") }, "\(offset)")
    }
}
