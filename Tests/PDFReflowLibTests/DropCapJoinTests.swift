import Foundation
import Testing
@testable import PDFReflowLib

/// #135: a drop cap's initial joins the rest of its word (`T he` → `The`); display numerals,
/// ordinary capitals and one-letter words the book spells alone keep their spaces.
private func nativePage(_ name: String) throws -> PageContent {
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

private func joinedText(_ name: String, vocabulary: Set<String> = []) throws -> (page: PageContent, text: String) {
    var page = try nativePage(name)
    LayoutReconstructor.joinDropCapInitials(&page, vocabulary: vocabulary)
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: vocabulary, warnings: &warnings)
    return (page, blocks.map(\.text).joined(separator: "\n"))
}

@Test func flagDropCapsJoinTheirWords() throws {
    for (name, words) in [("flag-7", ["The Stars and Stripes originated"]),
                          ("flag-9", ["The first flag of the colonists"]),
                          ("flag-27", ["The life of your flag", "The size of the flag"]),
                          ("flag-30", ["The American War Mothers"]),
                          ("flag-31", ["Any honorably discharged veteran"]),
                          ("our-flag-page-29", ["Constituents may arrange"])] {
        let result = try joinedText(name)
        for word in words { #expect(result.text.contains(word), "\(name): \(word)") }
        #expect(result.text.range(of: #"(^|\n)[A-Z] [a-z]"#, options: .regularExpression) == nil, "\(name)")
        // The joined line keeps its drop-cap geometry and body size.
        let line = try #require(result.page.lines.first { $0.text.hasPrefix(words[0]) })
        #expect(line.readingRect != nil && line.fontSize == 9, "\(name)")
    }
    // Without the join the split is what reconstruction reads (the defect).
    var warnings: [ConversionWarning] = []
    let split = LayoutReconstructor.blocks(page: try nativePage("flag-7"), images: [], vocabulary: [], warnings: &warnings)
    #expect(split.contains { $0.text.hasPrefix("T he Stars") })
}

@Test func displayNumeralsCapitalsAndUnevidencedLinesKeepTheirSpaces() throws {
    // The Fed's 70-point chapter numerals and the Blue Book's scanned `I` beside capitals.
    for name in ["fed-8", "fed-14", "fed-24", "blue-5"] {
        let original = try nativePage(name)
        var page = original
        LayoutReconstructor.joinDropCapInitials(&page, vocabulary: [])
        #expect(page == original, "\(name)")
    }
    // The same text without drop-cap evidence (no reading rectangle) is not joined.
    var page = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 400, height: 600),
        lines: [TextLine(text: "T he plain line", rect: CGRect(x: 10, y: 10, width: 200, height: 12), fontSize: 12)], graphics: [])
    LayoutReconstructor.joinDropCapInitials(&page, vocabulary: [])
    #expect(page.lines[0].text == "T he plain line")
}

@Test func oneLetterWordInitialsJoinUnlessTheBookSpellsTheFragmentAlone() throws {
    #expect(!LayoutReconstructor.dropCapKeepsSpace(initial: "T", fragment: "he", vocabulary: ["he", "the"]))
    #expect(!LayoutReconstructor.dropCapKeepsSpace(initial: "A", fragment: "ny", vocabulary: ["any"]))
    #expect(!LayoutReconstructor.dropCapKeepsSpace(initial: "A", fragment: "rcheological", vocabulary: []))
    #expect(LayoutReconstructor.dropCapKeepsSpace(initial: "A", fragment: "new", vocabulary: ["new"]))
    #expect(!LayoutReconstructor.dropCapKeepsSpace(initial: "A", fragment: "gain", vocabulary: ["gain", "again"]))
    #expect(LayoutReconstructor.dropCapKeepsSpace(initial: "I", fragment: "n", vocabulary: ["n"]))
    // Our Flag page 31 with a vocabulary that holds `ny` as a word keeps `A ny`.
    #expect(try joinedText("flag-31", vocabulary: ["ny"]).text.contains("A ny honorably"))
}

@Test func dropCapFragmentsNeverEnterTheVocabulary() throws {
    var vocabulary: Set<String> = []
    LayoutReconstructor.addVocabulary(of: try nativePage("flag-31"), to: &vocabulary)
    #expect(!vocabulary.contains("ny"))
    #expect(vocabulary.contains("honorably"))
    vocabulary = []
    LayoutReconstructor.addVocabulary(of: try nativePage("flag-7"), to: &vocabulary)
    #expect(vocabulary.contains("the"))
    #expect(!vocabulary.contains("t"))
}

@Test func joinedDropCapLineKeepsEveryOtherProperty() throws {
    var line = TextLine(content: InlineText(elements: [.text("T ", []), .text("he line reads on", [.italic])]),
                        rect: CGRect(x: 10, y: 20, width: 300, height: 44), fontSize: 9, monospaced: false, wraps: true)
    line.readingRect = CGRect(x: 10, y: 55, width: 300, height: 9)
    line.structure = TextStructure(group: 4, order: 2, headingLevel: 0, lineCount: 3, opensWithSplitMarker: true)
    line.readingDirection = CGVector(dx: 0, dy: 1)
    var page = PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 400, height: 600), lines: [line], graphics: [])
    LayoutReconstructor.joinDropCapInitials(&page, vocabulary: [])
    let joined = page.lines[0]
    #expect(joined.text == "The line reads on")
    #expect(joined.content.elements == [.text("T", []), .text("he line reads on", [.italic])])
    // Every stored property other than the text, including any added later, is unchanged.
    func properties(_ line: TextLine) -> [String: String] {
        Dictionary(uniqueKeysWithValues: Mirror(reflecting: line).children.map { ($0.label ?? "", String(describing: $0.value)) })
    }
    let before = properties(line), after = properties(joined)
    #expect(before.keys.sorted() == after.keys.sorted())
    #expect(before.count >= 9)
    for key in before.keys where key != "content" && key != "text" {
        #expect(before[key] == after[key], "\(key)")
    }
    var expected = line
    expected.replaceContent(joined.content)
    #expect(joined == expected)
}
