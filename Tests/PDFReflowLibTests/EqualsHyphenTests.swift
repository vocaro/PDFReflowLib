import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// The 9/11 report's chapters 5–9 print every line-end word break with the Bembo `equal` glyph, which
// extracts as `=` (#126): hyphen repair never saw a hyphen, 933 `word= word` breaks reached the book,
// and short `=` lines read as equations whose crops swallowed body lines and five note markers. And
// codes broken at a hyphen before a digit or capital (`265A-NY-` + `280350-HQ`) rejoined with a
// space (#127).

private let gpo911SHA256 = "657d41475eb3a9a5e3e87a6c7c51ac1dfbe1af7566d1abff7bf7286e7e1c0e1b"

/// The five body markers the issue found inside crops: fixture, chapter, marker, the text it ends,
/// and whether a crop still swallows it as extracted. Page 255's `=` lines stopped seeding over its
/// marker once #119 restored the page's word spaces, so it is a control.
private let swallowedMarkers: [(name: String, chapter: Int, marker: Int, context: String, swallowed: Bool)] = [
    ("911-172", 5, 36, "was only one of many.", true),
    ("911-210", 6, 132, "from the Yemeni photograph.)", true),
    ("911-235", 7, 16, "went their separate ways.", true),
    ("911-255", 7, 116, "to commit mass murder.", false),
    ("911-313", 9, 91, "from this location came at 9:52.", true),
]

private func linked(_ page: PageContent, images: [CGRect], chapter: Int, marker: Int, context: String) -> Bool {
    var warnings: [ConversionWarning] = []
    var blocks = LayoutReconstructor.blocks(page: page, images: images.enumerated().map { ($1, "image-\($0)") },
                                            vocabulary: [], warnings: &warnings)
    let key = NoteKey(number: marker, scope: .chapter(chapter))
    blocks.append(ReflowBlock(content: .paragraph(InlineText("\(marker). Note.")), note: key, page: 500))
    _ = NoteLinker.link(&blocks) { $0 == page.number ? chapter : nil }
    return blocks.contains { block in
        guard case let .paragraph(text) = block.content, text.text.contains(context) else { return false }
        return text.elements.contains(.noteReference(String(marker), [], key))
    }
}

@Test func equalsHyphenLinesNoLongerSeedCropsOverBodyTextAndTheFiveMarkersLink() throws {
    for item in swallowedMarkers {
        let fixture = try SourceLayoutFixture.load(item.name)
        #expect(fixture.sourceSHA256 == gpo911SHA256)
        let source = fixture.styledContent()
        #expect(source.lines.contains { $0.text.hasSuffix("=") }, "\(item.name)")
        var restored = source
        LayoutReconstructor.restoreEqualsHyphens(&restored)
        #expect(!restored.lines.contains { $0.text.hasSuffix("=") }, "\(item.name)")
        #expect(restored.lines.contains { $0.text.hasSuffix("-") }, "\(item.name)")

        // Reproducer: as extracted, a `=` line seeds a crop over the marker's line, and the marker
        // survives only as pixels.
        let before = LayoutReconstructor.graphicsWithLabels(source)
        let markerLine = try #require(source.lines.first { $0.text.hasSuffix(String(item.context.suffix(6)) + "\(item.marker)") },
                                      "\(item.name)")
        #expect(before.contains { $0.intersects(markerLine.rect) } == item.swallowed, "\(item.name)")
        #expect(linked(source, images: before, chapter: item.chapter, marker: item.marker, context: item.context) == !item.swallowed,
                "\(item.name)")

        // With the book's hyphen restored the page has no crop, and the marker links.
        let after = LayoutReconstructor.graphicsWithLabels(restored)
        #expect(after.isEmpty, "\(item.name): \(after)")
        #expect(linked(restored, images: after, chapter: item.chapter, marker: item.marker, context: item.context), "\(item.name)")
    }
}

@Test func restoredEqualsHyphensGoThroughTheHyphenPolicy() throws {
    let pages = try ["911-172", "911-235", "911-242"].map { try SourceLayoutFixture.load($0).styledContent() }
    let vocabulary = LayoutReconstructor.vocabulary(in: pages)
    // A continuation after `=` is a fragment, not a book word, as after `-` (#101).
    #expect(!vocabulary.contains("ruary") && !vocabulary.contains("tional"))
    var text: [Int: String] = [:]
    var warnings: [ConversionWarning] = []
    for var page in pages {
        LayoutReconstructor.restoreEqualsHyphens(&page)
        text[page.number] = LayoutReconstructor.blocks(page: page, images: [], vocabulary: vocabulary, warnings: &warnings)
            .map(\.text).joined(separator: "\n")
    }
    for (number, value) in text {
        #expect(value.range(of: "[A-Za-z]= ", options: .regularExpression) == nil, "\(number)")
        #expect(value.range(of: "[A-Za-z]- [a-z]", options: .regularExpression) == nil, "\(number): a restored hyphen spaced")
    }
    // Removed: the book prints the joined word (`February 1, 2000`).
    #expect(text[235]?.contains("interviewed many times about the February 1, 2000, lunch") == true)
    // Kept with a warning: neither `exceptional` nor `excep-tional` is on these pages.
    #expect(text[172]?.contains("could supply such excep-tional commodities.") == true)
    #expect(warnings.contains { $0.code == .uncertainHyphen && $0.page == 172 })
    // Before a digit the restored hyphen follows the prose rule, as a printed `-` does (`a mid-` +
    // `1990s peak` in AddressJoinTests): these three pages never set `mid-` before a number inside
    // a line, so the space stays; the whole book does, and joins `mid-1990s` (#131).
    #expect(text[242]?.contains("had taken lessons in the mid- 1990s), Atta started") == true)
}

@Test func equalsLineEndShapeAndBookEvidence() {
    for accepted in ["community of local worship=", "Long Beach,Cal=", "lessons in the mid=", "(knowl=", "Slope=", "16oz="] {
        #expect(LayoutReconstructor.endsWithEqualsHyphen(accepted), "\(accepted)")
    }
    for rejected in ["4x =", "− b=", "31) R=", "hypotenuse tanθ=", "1501=", "y = 7 or y=",
                     "companies_list.asp?letter=", "www.example.org/index=", "worship", "worship= more"] {
        #expect(!LayoutReconstructor.endsWithEqualsHyphen(rejected), "\(rejected)")
    }

    func page(_ texts: [String], number: Int, recognized: Bool = false) -> PageContent {
        var result = PageContent(number: number, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: texts.enumerated().map {
            TextLine(text: $1, rect: CGRect(x: 72, y: 700 - CGFloat($0) * 14, width: 400, height: 12), fontSize: 10)
        }, graphics: [])
        result.recognized = recognized
        return result
    }
    func evidence(breaks: Int, equations: Int, recognized: Bool = false) -> LayoutReconstructor.EqualsHyphenEvidence {
        var result = LayoutReconstructor.EqualsHyphenEvidence()
        for index in 0..<breaks { result.add(page(["a terror=", "ist safehouse"], number: index + 1, recognized: recognized)) }
        for index in 0..<equations { result.add(page(["so x = 4"], number: breaks + index + 1)) }
        return result
    }
    #expect(evidence(breaks: 100, equations: 10).marksHyphens)
    #expect(!evidence(breaks: 99, equations: 0).marksHyphens)
    #expect(!evidence(breaks: 100, equations: 11).marksHyphens)
    #expect(evidence(breaks: 100, equations: 0, recognized: true).breaks == 0)
    // A `word=` line that does not continue lowercase is no break (Wallace's `slope=` + `1`).
    var numbers = LayoutReconstructor.EqualsHyphenEvidence()
    numbers.add(page(["through (2, 2), slope=", "1", "a terror=", "Ist"], number: 1))
    #expect(numbers.breaks == 0 && numbers.equations == 0)
}

@Test func equationBooksHaveNoEqualsHyphenEvidence() throws {
    // Wallace page 110 ends lines in `slope=` (the shape alone), and its neighbours, NBS page 7 and
    // FAA page 227 set equations; none continues a `word=` line lowercase.
    var equations = LayoutReconstructor.EqualsHyphenEvidence()
    let wallace = try SourceLayoutFixture.load("algebra-110").content()
    #expect(wallace.lines.contains { LayoutReconstructor.endsWithEqualsHyphen($0.text) })
    for name in ["algebra-110", "algebra-288", "algebra-289", "algebra-291", "nbs-7", "faa-227"] {
        equations.add(try SourceLayoutFixture.load(name).content())
    }
    #expect(equations.breaks == 0 && equations.equations > 0)
    #expect(!equations.marksHyphens)

    // The 9/11 pages carry only breaks.
    var book = LayoutReconstructor.EqualsHyphenEvidence()
    for name in ["911-172", "911-210", "911-235", "911-242", "911-255", "911-313"] {
        book.add(try SourceLayoutFixture.load(name).content())
    }
    #expect(book.breaks >= 30 && book.equations == 0)
}

@Test func restoringKeepsTheLinesGeometryAndStyle() throws {
    let source = try SourceLayoutFixture.load("911-235").styledContent()
    var restored = source
    LayoutReconstructor.restoreEqualsHyphens(&restored)
    #expect(restored.lines.count == source.lines.count)
    for (old, new) in zip(source.lines, restored.lines) {
        #expect(old.rect == new.rect && old.fontSize == new.fontSize && old.structure == new.structure)
        if old.text.hasSuffix("="), LayoutReconstructor.endsWithEqualsHyphen(old.text) {
            #expect(new.text == old.text.dropLast() + "-")
            #expect(new.content.elements.count == old.content.elements.count)
        } else {
            #expect(new == old)
        }
    }
}

// MARK: - #127

private func join(_ left: String, _ right: String) -> String {
    var warnings: [ConversionWarning] = []
    return LayoutReconstructor.join(left, right, vocabulary: [], page: 1, warnings: &warnings)
}

@Test func hyphenInsideAnAlphanumericCodeJoinsWithoutASpace() {
    let codes: [(String, String)] = [
        ("(citing 265A-NY-", "280350-HQ, serial 11297;"),
        ("citing 265A-", "NY-280350, serial 24808)."),
        ("315N-NY-280350-", "SD, serial 1522;"),
        ("265A-NY-280350-FD-", "302, serials 4718,"),
        ("280350-TP,serial 1474;265A-NY-", "280350-302, serial 1361)."),
        ("an unarmed National Guard C-", "130H cargo aircraft"),
        ("for an “American MI-", "5,” although"),
        ("Paths,” CTC 2003-", "40028CHX, Mar. 10, 2003."),
        ("Ressam, No. CR99-", "666C JCC"),
        ("Civil Aviation,” IC-2001-", "04A, July 31, 2001;"),
        ("a Piper Apache (PA-", "23). The aircraft"),
        ("include: 737-700 and 737-", "700C; G-IV"),
        ("Refer to 4-5-", "7e, ADS-B Limitations."),
    ]
    for (left, right) in codes {
        #expect(LayoutReconstructor.codeContinues(left, right), "\(left) | \(right)")
        #expect(join(left, right) == left + right, "\(left) | \(right)")
    }
    // Controls: prose compounds, citation ranges, hyphenated words before a folio or note number,
    // pure numbers, lone letters and continuations that are no code run are not codes. Citation
    // ranges and words before a folio keep today's space; compounds before a capital and number
    // codes follow their own rules (#131, `LineEndCompoundTests`).
    let others: [(left: String, right: String, spaced: Bool)] = [
        ("refused to meet with non-", "Muslims.The United", false),
        ("the Israeli-", "Palestinian peace process", false),
        ("a Small Group meeting in mid-", "November,the", false),
        ("taken lessons in the mid-", "1990s), Atta", true),
        ("The pre-", "9/11 FBI", true),
        ("(CENT-", "COM), 1997–2000", false),
        ("14 H 601-", "CE 1318; see also", true),
        ("12 H 183-", "WFAA-TV reel PKF-10", true),
        ("varies inversely as the pres-", "62", true),
        ("on the results of the investi-", "22S. 50 U.S.C.", true),
        ("Suspects,” CTC 96-", "30015,July 5,1996;", false),
        ("40-", "I", true),
        ("100-", "Location", true),
        ("in the less-than-", "5-second group.", true),
        ("a dash -", "5 more", true),
    ]
    for (left, right, spaced) in others {
        #expect(!LayoutReconstructor.codeContinues(left, right), "\(left) | \(right)")
        #expect(join(left, right) == left + (spaced ? " " : "") + right, "\(left) | \(right)")
    }
    // Addresses keep their own rules (#79): a hyphen before a digit continues with no space.
    #expect(join("http://english.daralhayat.com/Spec/02-", "2004/Article-20040213-ac4") ==
            "http://english.daralhayat.com/Spec/02-2004/Article-20040213-ac4")
    // Lowercase continuations stay with the hyphen policy.
    #expect(!LayoutReconstructor.codeContinues("the terror-", "ist safehouse"))
}

@Test func fbiSerialsRejoinWithinAndAcrossNotesPages() throws {
    // Page 546 breaks `265A-NY-` + `280350-HQ, serial 11297;` inside note 58 of chapter 7.
    let page546 = try SourceLayoutFixture.load("911-546")
    #expect(page546.sourceSHA256 == gpo911SHA256)
    var warnings: [ConversionWarning] = []
    var content546 = page546.content()
    let heads546 = try #require(NumberedNoteDetector.chapters(on: content546))
    content546.lines.removeAll { $0.text.contains("NOTES TO CHAPTER") }
    let text546 = LayoutReconstructor.blocks(page: content546, images: [], vocabulary: [], warnings: &warnings,
        noteChapter: heads546.lowerBound, noteLastChapter: heads546.upperBound).map(\.text).joined(separator: "\n")
    #expect(text546.contains("265A-NY-280350-302, serial 7134; 265A-NY-280350-HQ, serial 11297;"))
    #expect(text546.contains("265A-NY-280350-CG, serial 1928; 265A-NY-280350-NK, serial 2851;"))
    #expect(!text546.contains("265A-NY- 280350"))

    // Page 550 ends `315N-NY-280350-FD-302; 315N-NY-280350-`; page 551 continues the note with `SD, serial 1522;`.
    var blocks: [ReflowBlock] = []
    var previous: PageContent?
    var last: NumberedNoteDetector.Layout.Note?
    for name in ["911-550", "911-551"] {
        var page = try SourceLayoutFixture.load(name).content()
        let heads = try #require(NumberedNoteDetector.chapters(on: page))
        page.lines.removeAll { $0.text.contains("NOTES TO CHAPTER") }
        var layout: NumberedNoteDetector.Layout?
        let pageBlocks = LayoutReconstructor.blocks(page: page, images: [], vocabulary: [], warnings: &warnings,
            noteChapter: heads.lowerBound, noteLastChapter: heads.upperBound, noteLayout: { layout = $0 },
            continuingNote: previous == nil ? nil : last)
        last = layout?.lastNote
        LayoutReconstructor.appendPage(pageBlocks, page: page, previousPage: previous, to: &blocks, vocabulary: [],
            continuesNote: layout?.continuesParagraph == true, warnings: &warnings)
        previous = page
    }
    let note = try #require(blocks.first { $0.text.contains("315N-NY-280350-FD-302;") })
    #expect(note.text.contains("315N-NY-280350-FD-302; 315N-NY-280350-SD, serial 1522;"), "\(note.text)")
    #expect(!blocks.contains { $0.text.contains("280350- SD") })
}
