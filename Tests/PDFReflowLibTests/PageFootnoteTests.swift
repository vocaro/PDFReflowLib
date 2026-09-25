import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// Notes a page sets at its own foot belong to the raised numbers in its text that refer to them
// (#299). Every page here is a checksum-pinned capture, read against the printed page, never
// converter output.

/// A captured page with each line's attributed runs restored, so a raised number is raised.
private func styledPage(_ name: String) throws -> PageContent {
    let fixture = try SourceLayoutFixture.load(name)
    var page = fixture.content()
    for index in page.lines.indices {
        let line = page.lines[index]
        if let source = fixture.attributedLines.first(where: { $0.text == line.text }) {
            page.lines[index] = NativeTextReader.textLine(semantic: line.text, bounds: line.rect,
                                                          attributed: source.attributedString())
        }
    }
    return page
}

private let runningFooter = "Dietary Guidelines for Americans, 2025–2030 |"

/// Dietary Guidelines page 2 as reconstruction receives it: the running footer is gone, because
/// the furniture pass removes it from every page first (`furnitureRemoved` on page 2).
private func dietaryGuidelinesPage() throws -> PageContent {
    var page = try styledPage("dga-2")
    page.lines.removeAll { $0.text.hasPrefix(runningFooter) }
    return page
}

private func blocks(_ page: PageContent) -> [ReflowBlock] {
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings)
}

/// Every note link in the blocks' text, as (target, linked text, the words before it).
private func noteLinks(_ blocks: [ReflowBlock]) -> [(id: String, text: String, before: String)] {
    blocks.flatMap { block -> [(id: String, text: String, before: String)] in
        guard case let .paragraph(text) = block.content else { return [] }
        return text.elements.indices.compactMap { index in
            guard case let .link(.note(id), linked) = text.elements[index] else { return nil }
            let before = text.elements[..<index].reduce(into: "") { result, element in
                if case let .text(value, _) = element { result += value }
            }
            return (id, linked.text, String(before.suffix(12)))
        }
    }
}

private func footnotes(_ blocks: [ReflowBlock]) -> [ReflowBlock] {
    blocks.filter { $0.note?.kind == .footnote }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/299"))
func dietaryGuidelinesFootnotesAreLinkedFromTheirRaisedReferences() throws {
    let result = blocks(try dietaryGuidelinesPage())
    // The page prints four notes at its foot in two columns, 1 and 2 at x=54 and 3 and 4 at
    // x=315, each a URL, and reads them down each column.
    let notes = footnotes(result)
    #expect(notes.map(\.note?.id) == ["note-fn-2-1", "note-fn-2-2", "note-fn-2-3", "note-fn-2-4"])
    #expect(notes.map { $0.text.hasPrefix("\($0.note!.id.last!) ") } == [true, true, true, true])
    #expect(notes[0].text.contains("cdc.gov/chronic-disease/data-research/facts-stats/index.html"))
    #expect(notes[1].text.contains("cdc.gov/nchs/fastats/obesity-overweight.htm"))
    #expect(notes[2].text.contains("gis.cdc.gov/grasp/diabetes/diabetesatlas-spotlight.html"))
    #expect(notes[3].text.contains("cdc.gov/physical-activity/php/military-readiness/unfit-to-serve.html"))
    // The body raises each number once, where the page prints it.
    let links = noteLinks(result)
    #expect(links.map(\.id) == ["note-fn-2-1", "note-fn-2-2", "note-fn-2-3", "note-fn-2-4"])
    #expect(links.map(\.text) == ["1", "2", "3", "4"])
    #expect(zip(links.map(\.before), ["chronic diseases.", "overweight or obese.", "has prediabetes.", "upward mobility."])
        .allSatisfy { $1.hasSuffix($0) })
    // Serialized, a note is a footnote aside and a reference a noteref the writer resolves.
    let note = try EPUBTextEncoder.piece(for: notes[0], imagePaths: [:]).markup
    #expect(note.hasPrefix("<aside epub:type=\"footnote\" role=\"doc-footnote\" id=\"note-fn-2-1\"><p>"))
    let body = try #require(result.first { $0.text.contains("chronic diseases.") })
    let reference = try EPUBTextEncoder.piece(for: body, imagePaths: [:]).markup
    #expect(reference.contains("<a epub:type=\"noteref\" role=\"doc-noteref\" href=\"pdfreflow:note:note-fn-2-1:"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/299"))
func aFootnoteGathersTheLinesThatContinueIt() throws {
    // Loper Bright page 56 prints note 1 over five lines beneath a rule, and raises the 1 after
    // "Term." in the body above it.
    let result = blocks(try styledPage("loper-56"))
    let notes = footnotes(result)
    #expect(notes.map(\.note?.id) == ["note-fn-56-1"])
    #expect(notes.first?.text.hasPrefix("1 For relevant databases of decisions") == true)
    #expect(notes.first?.text.hasSuffix("http://supremecourtdatabase.org.") == true, "\(notes.first?.text ?? "")")
    #expect(noteLinks(result).map(\.id) == ["note-fn-56-1"])
    #expect(noteLinks(result).map(\.before) == ["s each Term."])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/299"))
func aPageThatStillCarriesItsRunningFooterIsNotReadForFootnotes() throws {
    // The same page with its footer: a line of the body's size stands below the notes, so they are
    // not the foot of the page, and nothing is linked. The notes are still in the book, as text.
    let page = try styledPage("dga-2")
    #expect(page.lines.contains { $0.text.hasPrefix(runningFooter) })
    let result = blocks(page)
    #expect(footnotes(result).isEmpty)
    #expect(noteLinks(result).isEmpty)
    #expect(result.contains { $0.text.contains("diabetesatlas-spotlight.html") })
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/299"))
func everyNoteMustBeRaisedExactlyOnceInTheTextAboveIt() throws {
    let page = try dietaryGuidelinesPage()
    func restyled(_ transform: (InlineText) -> InlineText) -> PageContent {
        var copy = page
        copy.lines = copy.lines.map { line in
            let content = transform(line.content)
            guard content != line.content else { return line }
            return TextLine(content: content, rect: line.rect, fontSize: line.fontSize)
        }
        return copy
    }
    // Reference 3 set on the line instead of raised: note 3 has nothing referring to it.
    let unraised = restyled { text in
        InlineText(elements: text.elements.map { element in
            if case .text("3", let style) = element, style.contains(.superscript) { return .text("3", []) }
            return element
        })
    }
    #expect(PageFootnotes.plan(page: unraised, lines: unraised.lines, body: 10.5) == nil)
    #expect(footnotes(blocks(unraised)).isEmpty)
    // Reference 2 raised a second time: which one the note answers is not the page's to say.
    let twice = restyled { text in
        guard text.text.contains("overweight or obese.") else { return text }
        return InlineText(elements: text.elements + [.text(" Obesity is common", []), .text("2", .superscript)])
    }
    #expect(PageFootnotes.plan(page: twice, lines: twice.lines, body: 10.5) == nil)
    // The unaltered page is accepted by the same call.
    #expect(PageFootnotes.plan(page: page, lines: page.lines, body: 10.5)?.notes.map(\.number) == [1, 2, 3, 4])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/299"))
func anExponentIsNotANoteReferenceEvenBeneathANoteShapedFoot() throws {
    // Wallace page 281 raises unit exponents in its prose: square inches `in²`, cubic feet `ft³`,
    // `(ft²)`. Two note-shaped lines numbered 2 and 3 are added at its foot, set smaller than the
    // body, so that the only thing between the page and a footnote reading is whether a raised
    // number is a reference.
    var page = try styledPage("algebra-281")
    #expect(page.lines.contains { line in
        line.content.elements.contains { if case .text("2", let style) = $0 { style.contains(.superscript) } else { false } }
    })
    for (number, y) in [(2, 40.0), (3, 30.0)] {
        page.lines.append(TextLine(content: InlineText(elements: [.text("\(number)", .superscript),
                                                                  .text(" A unit squared or cubed carries its exponent.", [])]),
                                   rect: CGRect(x: 85, y: y, width: 220, height: 8), fontSize: 7.97))
    }
    let body = LayoutReconstructor.bodySize(page.lines)
    #expect(PageFootnotes.plan(page: page, lines: page.lines, body: body) == nil)
    let result = blocks(page)
    #expect(footnotes(result).isEmpty)
    #expect(noteLinks(result).isEmpty)
    // The rule that refuses them, one exponent at a time.
    for (before, raised) in [("square inches - in", "2"), ("(x", "4"), ("a", "2"), ("10", "3"), ("area = side", "2")] {
        #expect(PageFootnotes.reference(in: [.text(before, []), .text(raised, .superscript)], at: 1) == nil,
                "\(before)^\(raised)")
    }
    #expect(PageFootnotes.reference(in: [.text("chronic diseases.", []), .text("1", .superscript)], at: 1) == 1)
    // An ordinal is a word, not a reference.
    #expect(PageFootnotes.reference(in: [.text("the", []), .text("4", .superscript), .text("th", [])], at: 1) == nil)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/299"))
func notesThatDoNotRunOnByOneDownTheirColumnsAreRefused() throws {
    var page = try dietaryGuidelinesPage()
    // Swap the left column's two notes: 2 above 1.
    let one = try #require(page.lines.firstIndex { $0.text.hasPrefix("1 ") && $0.rect.minY < 100 })
    let two = try #require(page.lines.firstIndex { $0.text.hasPrefix("2 ") && $0.rect.minY < 100 })
    let upper = page.lines[one].rect, lower = page.lines[two].rect
    page.lines[one].rect = lower
    page.lines[two].rect = upper
    #expect(PageFootnotes.plan(page: page, lines: page.lines, body: 10.5) == nil)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/299"))
func footnoteReferencesResolveToTheSpineDocumentHoldingTheNote() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let text = InlineText(elements: [.text("chronic diseases.", []),
        .link(.note("note-fn-2-1"), InlineText("1", style: .superscript))])
    let book = ReflowDocument(metadata: .init(title: "Notes", language: "en"), blocks: [
        .init(content: .sourcePage(2), page: 2),
        .init(content: .paragraph(text), page: 2),
        .init(content: .paragraph(InlineText("1 https://www.cdc.gov/")), note: .init(id: "note-fn-2-1", kind: .footnote), page: 2),
    ], assets: [])
    _ = try await EPUBWriter.write(book, maximumOutputBytes: 1_000_000, directory: dir, progress: { _ in })
    let chapter = try String(contentsOf: dir.appendingPathComponent("EPUB/chapter-1.xhtml"), encoding: .utf8)
    #expect(chapter.contains("<a epub:type=\"noteref\" role=\"doc-noteref\" href=\"chapter-1.xhtml#note-fn-2-1\"><sup>1</sup></a>"))
    #expect(chapter.contains("<aside epub:type=\"footnote\" role=\"doc-footnote\" id=\"note-fn-2-1\"><p>1 https://www.cdc.gov/</p></aside>"))
    #expect(!chapter.contains("pdfreflow:note:"))
}
