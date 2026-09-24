import Foundation
import Testing
@testable import PDFReflowLib

private func styledOutlineFixture(_ name: String) throws -> PageContent {
    let source = try SourceLayoutFixture.load(name)
    var page = source.content()
    for index in page.lines.indices {
        let line = page.lines[index]
        guard let styled = source.attributedLines.first(where: {
            $0.text == line.text && $0.rect.map { abs($0[1] - line.rect.minY) < 1 } == true
        }) else { continue }
        page.lines[index] = TextLine(content: NativeTextReader.inlineText(from: styled.attributedString()),
                                     rect: line.rect, fontSize: line.fontSize, monospaced: line.monospaced)
    }
    return page
}

private func styledFormPage(_ number: Int) throws -> PageContent {
    let name = "uscourts-\(number)"
    let source = try SourceLayoutFixture.load(name)
    #expect(source.sourceSHA256 == "9fe218570d311b0deab9413e39efda41210e60f2a5221eb360d43912ce05a118")
    return try styledOutlineFixture(name)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/211"))
func proSeOutlineTiersCarryAcrossPages() throws {
    let pages = try (1...5).map(styledFormPage)
    let established = FormOutlineEvidence.established(pages.flatMap(FormOutlineEvidence.candidates))
    #expect(Dictionary(grouping: established, by: \.page).mapValues { $0.map(\.text) } == [
        1: ["I. The Parties to This Complaint", "A. The Plaintiff(s)", "B. The Defendant(s)"],
        3: ["II. Basis for Jurisdiction", "A. If the Basis for Jurisdiction Is a Federal Question",
            "B. If the Basis for Jurisdiction Is Diversity of Citizenship", "1. The Plaintiff(s)", "2. The Defendant(s)"],
        4: ["3. The Amount in Controversy", "III. Statement of Claim", "IV. Relief"],
        5: ["V. Certification and Closing", "A. For Parties Without an Attorney", "B. For Attorneys"],
    ])
    #expect(Set(established.compactMap(\.tier)) == [0, 1, 2])
    #expect(!established.contains { $0.text.hasPrefix("a.") || $0.text.hasPrefix("b.") })
    var document = DocumentEvidence(chapterCandidates: [], language: "en")
    var options = ConversionOptions()
    options.removeRepeatedHeadersAndFooters = false
    for (index, page) in pages.enumerated() {
        try document.collect(page, pageIndex: index, suppliesVocabulary: true, options: options)
    }
    let plan = document.resolved(options: options)
    let resolved = plan.formOutline
    #expect(resolved[1]?.map(\.text) == ["I. The Parties to This Complaint", "A. The Plaintiff(s)",
                                       "B. The Defendant(s)"])
    #expect(resolved[2] == nil)
    #expect(resolved[4]?.contains { $0.text == "IV. Relief" } == true)
    let third = FormOutlineEvidence.joined(pages[2].lines, candidates: resolved[3] ?? [])
    #expect(third.lines.contains { $0.text == "a. If the plaintiff is an individual" })
    #expect(third.lines.contains { $0.text == "b. If the plaintiff is a corporation" })
    let fourth = FormOutlineEvidence.joined(pages[3].lines, candidates: resolved[4] ?? [])
    #expect(fourth.lines.contains { $0.text == "b. If the defendant is a corporation" })
    var blocks: [ReflowBlock] = []
    for page in pages {
        var warnings: [ConversionWarning] = []
        blocks += LayoutReconstructor.blocks(page: page, images: [], context: plan.context,
            formOutline: resolved[page.number] ?? [], formOutlineBaseLevel: plan.formOutlineBaseLevel,
            formOutlineOuterTier: plan.formOutlineOuterTier, warnings: &warnings)
    }
    let ranked = blocks.compactMap { block -> (String, Int)? in
        if case let .heading(_, text, level) = block.content { return (text.text, level) }
        return nil
    }
    #expect(ranked.contains { $0.0 == "I. The Parties to This Complaint" && $0.1 == 4 })
    #expect(ranked.contains { $0.0 == "A. For Parties Without an Attorney" && $0.1 == 5 })
    #expect(ranked.contains { $0.0 == "3. The Amount in Controversy" && $0.1 == 6 })
    let lower = blocks.compactMap { block -> ReflowBlock.ListItem? in
        if case let .listItem(item) = block.content, item.kind == .lettered(uppercase: false) { return item }
        return nil
    }
    #expect(lower.map(\.marker) == ["a.", "b.", "a.", "b."])
    #expect(!blocks.contains { block in
        if case .preformatted = block.content { return block.text.hasPrefix("a. ") || block.text.hasPrefix("b. ") }
        return false
    })
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/211"))
func aSingleNumberedListDoesNotEstablishAnOutline() throws {
    var page = try styledFormPage(1)
    page.lines = [
        TextLine(content: InlineText("1. The Plaintiff(s)", style: .bold),
                 rect: CGRect(x: 110, y: 400, width: 130, height: 12), fontSize: 11),
        TextLine(content: InlineText("2. The Defendant(s)", style: .bold),
                 rect: CGRect(x: 110, y: 380, width: 130, height: 12), fontSize: 11),
    ]
    #expect(FormOutlineEvidence.established(FormOutlineEvidence.candidates(on: page)).isEmpty)
    let noaa = try SourceLayoutFixture.load("noaa-701").content()
    #expect(FormOutlineEvidence.established(FormOutlineEvidence.candidates(on: noaa)).isEmpty)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/211"))
func unrelatedSourcePagesDoNotEstablishFormOutlines() throws {
    for names in [["911-69", "911-70", "911-71"], ["faa-416", "faa-438"],
                  ["usda-magazine-3", "usda-magazine-16", "usda-magazine-24"],
                  ["noaa-384", "noaa-701"]] {
        let pages = try names.map(styledOutlineFixture)
        #expect(FormOutlineEvidence.established(pages.flatMap(FormOutlineEvidence.candidates)).isEmpty,
                "\(names)")
    }
}
