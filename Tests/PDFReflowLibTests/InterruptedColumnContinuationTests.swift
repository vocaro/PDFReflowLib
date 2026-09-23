import Foundation
import Testing
@testable import PDFReflowLib

private func continuationSource(_ number: Int) throws -> (PageContent, [LayoutReconstructor.Element]) {
    let fixture = try SourceLayoutFixture.load("usda-magazine-\(number)")
    #expect(fixture.sourceSHA256 == "2673d1fded74ad89c8b5c59dc325c7884601e1aca5b5755b15a105c1f5b0d761")
    let page = fixture.content()
    func line(_ index: Int) -> LayoutReconstructor.Element {
        .init(rect: page.lines[index].rect, line: page.lines[index])
    }
    if number == 12 {
        let quote = stride(from: 18, through: 30, by: 2).map { page.lines[$0] }
        return (page, (0...17).map(line)
            + [.init(rect: quote.reduce(CGRect.null) { $0.union($1.rect) }, quotation: quote),
               .init(rect: page.pictures[1], image: "quotation-background")]
            + (32...52).map(line))
    }
    return (page, (1...55).map(line) + [line(0), .init(rect: page.pictures[0], image: "thermometer")]
        + (80...83).map(line) + (56...79).map(line) + (84...99).map(line))
}

@Test(arguments: [12, 17]) func magazineInterruptedColumnsResumeOnlySourceProse(number: Int) throws {
    let (_, elements) = try continuationSource(number)
    let roles: [LineRole?] = elements.map { $0.line == nil ? nil : .prose }
    let pairs = InterruptedColumnContinuation.pairs(elements, roles: roles, body: 10.5)
    let actual = pairs.map { (elements[$0.value].line!.text, elements[$0.key].line!.text) }
    if number == 12 {
        #expect(actual.count == 2)
        #expect(actual.contains { $0.0 == "Areawide Pest Management Research"
            && $0.1 == "Unit’s Aerial Application Technology" })
        #expect(actual.contains { $0.0 == "and sizes—hand-held, backpack, truck-"
            && $0.1 == "mounted, and thermal foggers with water" })
    } else {
        #expect(actual.count == 1)
        #expect(actual.first?.0 == "postharvest were in the 10˚ to 15˚F range,")
        #expect(actual.first?.1 == "consistently higher than the 3˚")
    }
}

@Test func interruptedColumnPlanRejectsNewParagraphsAndUnownedBlocks() throws {
    let (_, original) = try continuationSource(17)
    let roles: [LineRole?] = original.map { $0.line == nil ? nil : .prose }
    let pair = try #require(InterruptedColumnContinuation.pairs(original, roles: roles, body: 10.5).first)
    var indented = original
    indented[pair.key].line!.rect.origin.x += 10
    #expect(InterruptedColumnContinuation.pairs(indented, roles: roles, body: 10.5).isEmpty)
    var ended = original
    let old = ended[pair.value].line!
    ended[pair.value].line = TextLine(text: old.text + ".", rect: old.rect, fontSize: old.fontSize)
    #expect(InterruptedColumnContinuation.pairs(ended, roles: roles, body: 10.5).isEmpty)
    var competing = original
    let credit = pair.value + 1
    competing[credit].line = TextLine(text: "Independent body paragraph", rect: original[credit].rect, fontSize: 10.5)
    #expect(InterruptedColumnContinuation.pairs(competing, roles: roles, body: 10.5).isEmpty)
    var detached = original
    detached[credit].line!.rect.origin.x = 40
    #expect(InterruptedColumnContinuation.pairs(detached, roles: roles, body: 10.5).isEmpty)
    var headed = roles
    headed[pair.key] = .heading
    #expect(InterruptedColumnContinuation.pairs(original, roles: headed, body: 10.5).isEmpty)
    let picture = try #require(original.indices.first { original[$0].image != nil })
    var spanning = original
    spanning[picture].rect.size.width = 500
    #expect(InterruptedColumnContinuation.pairs(spanning, roles: roles, body: 10.5).isEmpty)
    var distant = original
    distant[picture].rect.origin.x = 800
    #expect(InterruptedColumnContinuation.pairs(distant, roles: roles, body: 10.5).isEmpty)
}

@Test(arguments: [12, 17]) func interruptedMagazineParagraphSurvivesCompleteReconstruction(number: Int) throws {
    let fixture = try SourceLayoutFixture.load("usda-magazine-\(number)")
    var original = fixture.content()
    // Restore the captured native styles, particularly Helvetica-Bold section labels.
    original.lines = original.lines.map { line in
        guard let attributed = fixture.attributedLines.first(where: { $0.text == line.text }) else { return line }
        return TextLine(content: NativeTextReader.inlineText(from: attributed.attributedString()),
                        rect: line.rect, fontSize: line.fontSize, monospaced: line.monospaced)
    }
    let page = TextBackdrop.compose(original, graphics: .init(regions: original.graphics,
        unsupported: false, images: original.pictures, paints: fixture.paints))
    let crops = LayoutReconstructor.graphicsWithLabels(page)
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page,
        images: crops.enumerated().map { ($0.element, "image-\($0.offset)") },
        vocabulary: LayoutReconstructor.vocabulary(in: [page]), warnings: &warnings,
        labelStyles: LayoutReconstructor.labelEvidence(on: page))
    let phrase = number == 12 ? "Areawide Pest Management Research Unit’s Aerial Application Technology"
        : "postharvest were in the 10˚ to 15˚F range, consistently higher than the 3˚"
    let paragraph = try #require(blocks.first { $0.text.contains(phrase) })
    guard case .paragraph = paragraph.content else { Issue.record("Expected continued paragraph"); return }
    if number == 12 {
        #expect(paragraph.text.contains("truck-mounted, and thermal foggers"))
        #expect(blocks.filter { if case .quotation = $0.content { true } else { false } }.count == 1)
        #expect(!paragraph.text.contains("Whenever you get a new"))
    } else {
        #expect(paragraph.text.contains("that were not water stressed."))
        #expect(!paragraph.text.contains("DONG WANG"))
        #expect(!paragraph.text.contains("Infrared thermometer"))
        #expect(blocks.contains { $0.text == "DONG WANG (D2686-1)" })
        #expect(!paragraph.text.contains("How Much Pressure"))
        #expect(blocks.contains {
            if case .heading = $0.content { $0.text == "How Much Pressure Can a Leaf Take?" } else { false }
        })
    }
}
