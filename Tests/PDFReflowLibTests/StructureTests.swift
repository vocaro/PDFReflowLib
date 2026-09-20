import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

private let taggedPageContent = """
/P << /MCID 0 >> BDC BT /F1 12 Tf 1 0 0 1 40 700 Tm (Small heading) Tj ET EMC
/Span << /MCID 1 >> BDC BT /F1 24 Tf 1 0 0 1 40 580 Tm (First paragraph line) Tj ET EMC
/P << /MCID 2 >> BDC BT /F1 24 Tf 1 0 0 1 80 510 Tm (second paragraph line.) Tj ET EMC
"""

private func taggedObjects() -> [String] {
    [
        "<< /Type /Catalog /Pages 2 0 R /StructTreeRoot 6 0 R /MarkInfo << /Marked false >> >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R /StructParents 0 >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        testPDFStream(taggedPageContent),
        "<< /Type /StructTreeRoot /K [8 0 R 9 0 R] /ParentTree 7 0 R >>",
        "<< /Nums [0 [8 0 R 10 0 R 9 0 R]] >>",
        "<< /Type /StructElem /S /H3 /P 6 0 R /Pg 3 0 R /K 0 >>",
        "<< /Type /StructElem /S /P /P 6 0 R /Pg 3 0 R /K [10 0 R 2] >>",
        "<< /Type /StructElem /S /Span /P 9 0 R /K 1 >>",
    ]
}

private func withTaggedPDF<T>(_ objects: [String], _ body: (URL, CGPDFPage) throws -> T) throws -> T {
    let directory = try testPDFDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("tagged.pdf")
    try testPDF(objects: objects).write(to: url)
    let document = try #require(CGPDFDocument(url as CFURL))
    let page = try #require(document.page(at: 1))
    return try body(url, page)
}

// Independent expected geometry for the three explicit text origins in taggedObjects().
// PDFKit extraction itself is exercised by the complete corpus; these parser unit tests
// avoid additional concurrent attributed-font access in PDFKit.
private func taggedLines() -> [TextLine] {
    [TextLine(text: "Small heading", rect: CGRect(x: 40, y: 697, width: 150, height: 15), fontSize: 12),
     TextLine(text: "First paragraph line", rect: CGRect(x: 40, y: 575, width: 250, height: 28), fontSize: 24),
     TextLine(text: "second paragraph line.", rect: CGRect(x: 80, y: 505, width: 260, height: 28), fontSize: 24)]
}

private func taggedBlocks(_ url: URL, _ page: CGPDFPage) throws -> [ReflowBlock] {
    let tree = try StructureTreeReader.read(url)
    var lines = taggedLines()
    #expect(StructureTreeReader.validates(try #require(tree.pages[1]), owners: try #require(tree.owners[1]), page: page))
    #expect(MarkedTextReader.apply(try #require(tree.pages[1]), page: page, lines: &lines))
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: .init(number: 1, bounds: page.getBoxRect(.cropBox), lines: lines, graphics: []),
        images: [], vocabulary: [], warnings: &warnings)
    #expect(warnings.isEmpty)
    return blocks
}

@Test func structureRolesOverrideFontsAndDrawingTagsWithMarkedFalse() throws {
    try withTaggedPDF(taggedObjects()) { url, page in
        let blocks = try taggedBlocks(url, page)
        #expect(blocks.map(\.text) == ["Small heading", "First paragraph line second paragraph line."])
        guard case .heading(_, _, 3) = blocks[0].content, case .paragraph = blocks[1].content else {
            Issue.record("Expected tree H3 and grouped P, regardless of font size and BDC names"); return
        }
    }
}

@Test func logicalGroupOrderOverridesSpatialOrder() throws {
    var objects = taggedObjects()
    objects[5] = objects[5].replacingOccurrences(of: "[8 0 R 9 0 R]", with: "[9 0 R 8 0 R]")
    try withTaggedPDF(objects) { url, page in
        let blocks = try taggedBlocks(url, page)
        #expect(blocks.map(\.text) == ["First paragraph line second paragraph line.", "Small heading"])
    }
}

@Test func roleMapAndMCRPageReferencesAreResolved() throws {
    var objects = taggedObjects()
    objects[5] = objects[5].replacingOccurrences(of: "/K [", with: "/RoleMap << /Title /H3 >> /K [")
    objects[7] = "<< /Type /StructElem /S /Title /P 6 0 R /K << /Type /MCR /Pg 3 0 R /MCID 0 >> >>"
    try withTaggedPDF(objects) { url, page in
        let blocks = try taggedBlocks(url, page)
        #expect(blocks.count == 2)
    }
}

@Test(arguments: ["parent", "parentTree", "duplicate", "missingPage", "cycle", "roleCycle", "negative", "hugeID"])
func malformedStructureFallsBack(_ failure: String) throws {
    var objects = taggedObjects()
    switch failure {
    case "parent": objects[7] = objects[7].replacingOccurrences(of: "/P 6 0 R", with: "/P 9 0 R")
    case "parentTree": objects[6] = "<< /Nums [0 [9 0 R 10 0 R 9 0 R]] >>"
    case "duplicate": objects[8] = objects[8].replacingOccurrences(of: "10 0 R 2", with: "10 0 R 0")
    case "missingPage": objects[7] = objects[7].replacingOccurrences(of: "/Pg 3 0 R", with: "/Pg 2 0 R")
    case "cycle": objects[8] = objects[8].replacingOccurrences(of: "10 0 R 2", with: "9 0 R")
    case "roleCycle":
        objects[5] = objects[5].replacingOccurrences(of: "/K [", with: "/RoleMap << /Title /Title >> /K [")
        objects[7] = objects[7].replacingOccurrences(of: "/H3", with: "/Title")
    case "negative": objects[7] = objects[7].replacingOccurrences(of: "/K 0", with: "/K -1")
    default: objects[7] = objects[7].replacingOccurrences(of: "/K 0", with: "/K 1000000000")
    }
    try withTaggedPDF(objects) { url, page in
        let index = try StructureTreeReader.read(url)
        if failure == "parentTree" {
            #expect(!StructureTreeReader.validates(try #require(index.pages[1]), owners: try #require(index.owners[1]), page: page))
        } else { #expect(index.present && index.rejected && index.pages.isEmpty) }
    }
}

@Test(arguments: ["unknownCursor", "unbalanced", "unmarkedOverlap", "missingMCID", "form", "initialAdjustment",
                  "unknownCursorInGroup", "invisibleOutsideArtifact", "clippingMode"])
func ambiguousMarkedContentKeepsNativeText(_ failure: String) throws {
    var objects = taggedObjects()
    switch failure {
    case "unknownCursor": objects[4] = testPDFStream("BT /F1 12 Tf 40 700 Td (First) Tj ( second) Tj ET")
    case "unbalanced": objects[4] = testPDFStream("/P <</MCID 0>> BDC BT /F1 12 Tf 40 700 Td (First) Tj ET")
    case "unmarkedOverlap": objects[4] = testPDFStream("/P <</MCID 0>> BDC BT /F1 12 Tf 40 700 Td (First) Tj ET EMC BT /F1 12 Tf 50 700 Td (Other) Tj ET")
    case "missingMCID": objects[4] = testPDFStream("BT /F1 12 Tf 40 700 Td (Untagged) Tj ET")
    case "form": objects[4] = testPDFStream("/Unknown Do")
    // The origin of a show in a marked section costs that section's group, not the page; the
    // three groups here each lose one, so nothing is tagged either way (#67).
    case "unknownCursorInGroup":
        objects[4] = testPDFStream("/P <</MCID 0>> BDC BT /F1 12 Tf 40 700 Td (First) Tj ( second) Tj ET EMC")
    // Invisible text is inherited transcription unless an artifact owns it (#91).
    case "invisibleOutsideArtifact":
        objects[4] = testPDFStream("/P <</MCID 0>> BDC BT /F1 12 Tf 3 Tr 40 700 Td (First) Tj ET EMC")
    case "clippingMode":
        objects[4] = testPDFStream("/P <</MCID 0>> BDC BT /F1 12 Tf 7 Tr 40 700 Td (First) Tj ET EMC")
    default: objects[4] = testPDFStream("/P <</MCID 0>> BDC BT /F1 12 Tf 40 700 Td [120 (First)] TJ ET EMC")
    }
    try withTaggedPDF(objects) { url, page in
        let index = try StructureTreeReader.read(url)
        var lines = taggedLines()
        let original = lines.map(\.content)
        #expect(!MarkedTextReader.apply(try #require(index.pages[1]), page: page, lines: &lines))
        #expect(lines.map(\.content) == original)
        #expect(lines.allSatisfy { $0.structure == nil })
    }
}

@Test func figureChildrenDoNotBecomeParagraphSemantics() throws {
    var objects = taggedObjects()
    objects[9] = objects[9].replacingOccurrences(of: "/Span", with: "/Figure")
    try withTaggedPDF(objects) { url, _ in
        let index = try StructureTreeReader.read(url)
        #expect(index.rejected)
        #expect(index.pages[1]?.keys.sorted() == [0])
    }
}

@Test func tagsCannotReorderAcrossImagesOrUnmappedText() {
    func element(_ text: String, group: Int, order: Int, count: Int) -> LayoutReconstructor.Element {
        var line = TextLine(text: text, rect: CGRect(x: 0, y: 0, width: 100, height: 12), fontSize: 12)
        line.structure = .init(group: group, order: order, headingLevel: 0, lineCount: count)
        return .init(rect: line.rect, line: line)
    }
    let first = element("First", group: 1, order: 2, count: 2)
    let last = element("Last", group: 1, order: 1, count: 2)
    let image = LayoutReconstructor.Element(rect: .zero, image: "image")
    var warnings: [ConversionWarning] = []
    let result = LayoutReconstructor.structuredOrder([first, image, last], page: 1, warnings: &warnings)
    #expect(result.map { $0.line?.text ?? $0.image! } == ["First", "image", "Last"])
    #expect(result.allSatisfy { $0.line?.structure == nil })
    #expect(warnings.map(\.code) == [.structureFallback])
    warnings = []
    #expect(LayoutReconstructor.structuredOrder([first], page: 1, warnings: &warnings)[0].line?.structure == nil)
}

@Test func ourFlagTwoLineTitleUsesSingleSourceH3() throws {
    let native = try SourceLayoutFixture.load("our-flag-page-29")
    struct Evidence: Decodable { var sourceSHA256: String; var contentStream: String; var headingRole: String; var headingMCID: Int }
    let file = fixtureURL("our-flag-page-29-tags.json")
    let evidence = try JSONDecoder().decode(Evidence.self, from: Data(contentsOf: file))
    #expect(evidence.sourceSHA256 == native.sourceSHA256)
    #expect(evidence.headingRole == "H3" && evidence.headingMCID == 0)
    var objects = taggedObjects()
    // A minimal resource/structure wrapper around the unchanged source stream. Geometry and
    // Unicode come from the independently captured native source, not these placeholder fonts.
    objects[2] = "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 423 652] /Resources << /XObject << /Im0 11 0 R >> >> /Contents 5 0 R /StructParents 0 >>"
    objects[4] = testPDFStream(evidence.contentStream)
    objects[5] = "<< /Type /StructTreeRoot /K [8 0 R] /ParentTree 7 0 R >>"
    objects[6] = "<< /Nums [0 [8 0 R]] >>"
    objects.append(testPDFStream("xxx", extra: "/Type /XObject /Subtype /Image /Width 1 /Height 1 /ColorSpace /DeviceRGB /BitsPerComponent 8"))
    try withTaggedPDF(objects) { url, page in
        var content = native.content()
        var warnings: [ConversionWarning] = []
        let baseline = LayoutReconstructor.blocks(page: content, images: [], vocabulary: [], warnings: &warnings)
        #expect(baseline.filter { if case .heading = $0.content { true } else { false } }.count == 2)
        let tree = try StructureTreeReader.read(url)
        #expect(MarkedTextReader.apply(try #require(tree.pages[1]), page: page, lines: &content.lines))
        let blocks = LayoutReconstructor.blocks(page: content, images: [], vocabulary: [], warnings: &warnings)
        let headings = blocks.filter { if case .heading = $0.content { true } else { false } }
        #expect(headings.count == 1)
        #expect(headings.first?.text == "How to Obtain a Flag Flown Over the Capitol")
        guard case .heading(_, _, 3) = headings.first?.content else { Issue.record("Lost source H3"); return }
        #expect(blocks.flatMap { $0.text.split(whereSeparator: \.isWhitespace) }
            == baseline.flatMap { $0.text.split(whereSeparator: \.isWhitespace) })
    }
}

@Test func explicitParagraphBoundariesPreventHeuristicPageJoin() {
    let bounds = CGRect(x: 0, y: 0, width: 600, height: 800)
    let previous = PageContent(number: 1, bounds: bounds,
        lines: [.init(text: "continues", rect: CGRect(x: 40, y: 40, width: 300, height: 12), fontSize: 12)], graphics: [])
    let page = PageContent(number: 2, bounds: bounds,
        lines: [.init(text: "lowercase", rect: CGRect(x: 40, y: 750, width: 300, height: 12), fontSize: 12)], graphics: [])
    var blocks = [ReflowBlock(content: .paragraph(InlineText("continues")), structureGroup: 1, page: 1)]
    var warnings: [ConversionWarning] = []
    LayoutReconstructor.appendPage([.init(content: .paragraph(InlineText("lowercase")), structureGroup: 2, page: 2)],
        page: page, previousPage: previous, to: &blocks, vocabulary: [], warnings: &warnings)
    #expect(blocks.map(\.text) == ["continues", "", "lowercase"])
    // A page whose tags were not applied states no paragraph identity, so one identity against
    // none leaves the join to the geometric rule, as it was before either page carried a tag.
    var mixed = [ReflowBlock(content: .paragraph(InlineText("continues")), page: 1)]
    LayoutReconstructor.appendPage([.init(content: .paragraph(InlineText("lowercase")), structureGroup: 2, page: 2)],
        page: page, previousPage: previous, to: &mixed, vocabulary: [], warnings: &warnings)
    #expect(mixed.map(\.text) == ["continues lowercase"])
}

@Test func parentNumberTreeKidsAndNamedPropertiesAreSupported() throws {
    var objects = taggedObjects()
    objects[6] = "<< /Kids [11 0 R] >>"
    objects.append("<< /Limits [0 0] /Nums [0 [8 0 R 10 0 R 9 0 R]] >>")
    objects[2] = objects[2].replacingOccurrences(of: "/Font <<", with: "/Properties << /Title << /MCID 0 >> >> /Font <<")
    objects[4] = objects[4].replacingOccurrences(of: "/P << /MCID 0 >> BDC", with: "/P /Title BDC")
    // Replacing stream bytes requires regenerating the length.
    let content = objects[4].components(separatedBy: "stream\n")[1].components(separatedBy: "\nendstream")[0]
    objects[4] = testPDFStream(content)
    try withTaggedPDF(objects) { url, page in
        let blocks = try taggedBlocks(url, page)
        #expect(blocks.count == 2)
    }
}

@Test func duplicatePaintIDsAreNotTrusted() throws {
    var objects = taggedObjects()
    let content = "/P << /MCID 0 >> BDC BT /F1 12 Tf 40 700 Td (First) Tj ET EMC\n/P << /MCID 0 >> BDC BT /F1 12 Tf 40 650 Td (Second) Tj ET EMC"
    objects[4] = testPDFStream(content)
    try withTaggedPDF(objects) { url, page in
        let index = try StructureTreeReader.read(url)
        var lines = taggedLines()
        #expect(!MarkedTextReader.apply(try #require(index.pages[1]), page: page, lines: &lines))
        #expect(lines.allSatisfy { $0.structure == nil })
    }
}

@Test func excessiveStructureDepthFallsBackWithoutRecursionFailure() throws {
    var objects = taggedObjects()
    objects[5] = "<< /Type /StructTreeRoot /K 11 0 R /ParentTree 7 0 R >>"
    for id in 11...80 {
        let parent = id == 11 ? 6 : id - 1
        objects.append("<< /Type /StructElem /S /Sect /P \(parent) 0 R /K \(id + 1) 0 R >>")
    }
    objects.append("<< /Type /StructElem /S /Sect /P 80 0 R >>")
    try withTaggedPDF(objects) { url, _ in
        let index = try StructureTreeReader.read(url)
        #expect(index.rejected && index.pages.isEmpty)
    }
}

@Test(arguments: ["Figure 3-15. Composite aircraft.", "Table 1. Measurements", "1. First exercise", "• First item", String(repeating: "long ", count: 45)])
func captionsListsAndOversizedHeadingsKeepSpatialBoundaries(_ text: String) {
    var label = TextLine(text: text, rect: .zero, fontSize: 12)
    label.structure = .init(group: 2, order: 2, headingLevel: text.hasPrefix("long") ? 4 : 0, lineCount: 1)
    var prose = TextLine(text: "Body", rect: .zero, fontSize: 12)
    prose.structure = .init(group: 1, order: 1, headingLevel: 0, lineCount: 1)
    var warnings: [ConversionWarning] = []
    let result = LayoutReconstructor.structuredOrder([.init(rect: .zero, line: label), .init(rect: .zero, line: prose)],
        page: 1, warnings: &warnings)
    #expect(result.map { $0.line!.text } == [text, "Body"])
    #expect(result[0].line?.structure == nil)
    #expect(warnings.contains { $0.code == .structureFallback })
}

@Test func formMCIDsCannotMasqueradeAsPageMCIDs() throws {
    var objects = taggedObjects()
    objects[2] = objects[2].replacingOccurrences(of: "/Font <<", with: "/XObject << /Fm 11 0 R >> /Font <<")
    objects[4] = testPDFStream("/Fm Do")
    objects.append(testPDFStream("/P <</MCID 0>> BDC BT /F1 12 Tf 40 700 Td (Small heading) Tj ET EMC",
        extra: "/Type /XObject /Subtype /Form /BBox [0 0 600 800] /Resources << /Font << /F1 4 0 R >> >>"))
    try withTaggedPDF(objects) { url, page in
        let tree = try StructureTreeReader.read(url)
        var lines = taggedLines()
        #expect(!MarkedTextReader.apply(try #require(tree.pages[1]), page: page, lines: &lines))
        #expect(lines.allSatisfy { $0.structure == nil })
    }
}

/// `taggedObjects()`, with a Form XObject named `/Fm` that draws `content` and a page that
/// draws it with `draws` after its own three tagged paragraphs.
private func formObjects(_ content: String, draws: String = "/Fm Do") -> [String] {
    var objects = taggedObjects()
    objects[2] = objects[2].replacingOccurrences(of: "/Font <<", with: "/XObject << /Fm 11 0 R >> /Font <<")
    objects[4] = testPDFStream(taggedPageContent + "\n" + draws)
    objects.append(testPDFStream(content, extra: "/Type /XObject /Subtype /Form /BBox [0 0 600 800]"
        + " /Resources << /Font << /F1 4 0 R >> >>"))
    return objects
}

@Test func aFormThatShowsNoTextCostsThePageNothing() throws {
    // The form draws a rectangle, which places no line, so the page's own three groups apply
    // exactly as they would if the page drew nothing at all (#241).
    try withTaggedPDF(formObjects("q 10 10 100 100 re f Q")) { url, page in
        let scan = try #require(MarkedTextReader.scan(page))
        #expect(scan.formsRead == 1)
        #expect(scan.formShows == 0)
        let tree = try StructureTreeReader.read(url)
        var lines = taggedLines()
        #expect(MarkedTextReader.apply(try #require(tree.pages[1]), page: page, lines: &lines))
        #expect(lines.allSatisfy { $0.structure != nil })
    }
}

@Test func formTextRejectsTheLineItLandsInAndNoOther() throws {
    // A form's marked content is numbered in the form's own namespace, which the structure tree
    // reaches only through an `/MCR` with a `/Stm` — and those are rejected before this reader
    // sees them. So this show describes nothing: the line it lands in cannot take a tag, and
    // the page's other two groups are untouched (#241).
    try withTaggedPDF(formObjects("BT /F1 12 Tf 1 0 0 1 60 700 Tm (drawn by the form) Tj ET")) { url, page in
        let scan = try #require(MarkedTextReader.scan(page))
        #expect(scan.formShows == 1)
        #expect(scan.anchors.contains { $0.id == nil && $0.point == CGPoint(x: 60, y: 700) })
        let tree = try StructureTreeReader.read(url)
        var lines = taggedLines()
        #expect(!MarkedTextReader.apply(try #require(tree.pages[1]), page: page, lines: &lines))
        #expect(lines.map { $0.structure != nil } == [false, true, true])
    }
}

@Test func anUnplaceableShowInsideAFormStillRefusesThePage() throws {
    // The second show continues the cursor, so its origin is unknown, and nothing in the form
    // says which line it drew: outside an artifact that still costs the whole page (#67, #241).
    let content = "BT /F1 12 Tf 1 0 0 1 60 700 Tm (placed) Tj (continued) Tj ET"
    try withTaggedPDF(formObjects(content)) { url, page in
        #expect(MarkedTextReader.scan(page) == nil)
        let tree = try StructureTreeReader.read(url)
        var lines = taggedLines()
        #expect(!MarkedTextReader.apply(try #require(tree.pages[1]), page: page, lines: &lines))
        #expect(lines.allSatisfy { $0.structure == nil })
    }
}

@Test func aFormDrawnInsideAnArtifactCostsNothing() throws {
    // The same unplaceable show, drawn in the page's margin where the page has said the content
    // is furniture. An artifact carries no structure, in the page's own stream or in a form it
    // draws, so neither show costs a group (#67, #241).
    try withTaggedPDF(formObjects("BT /F1 12 Tf 1 0 0 1 500 60 Tm (placed) Tj (continued) Tj ET",
                                  draws: "/Artifact BMC /Fm Do EMC")) { url, page in
        let scan = try #require(MarkedTextReader.scan(page))
        #expect(scan.artifactUnknownOrigins == 1)
        #expect(scan.formShows == 2)
        let tree = try StructureTreeReader.read(url)
        var lines = taggedLines()
        #expect(MarkedTextReader.apply(try #require(tree.pages[1]), page: page, lines: &lines))
        #expect(lines.allSatisfy { $0.structure != nil })
    }
}

@Test func aFormMayNotCloseMarkedContentItsCallerOpened() throws {
    // Marked content begins and ends in one content stream. A form whose `EMC` would close the
    // page's open section, or whose own `BDC` it leaves open, is not a stream this reader can
    // account for, and the page keeps spatial reconstruction.
    // A stray `EMC`, a section the form leaves open, and the pair that would balance out while
    // silently closing the caller's section and opening one of the form's own in its place.
    for content in ["EMC", "/P << /MCID 9 >> BDC", "EMC /Span << /MCID 9 >> BDC"] {
        try withTaggedPDF(formObjects(content, draws: "/P << /MCID 3 >> BDC /Fm Do EMC")) { _, page in
            #expect(MarkedTextReader.scan(page) == nil)
        }
    }
}

/// `taggedObjects()` whose page draws a chain of `levels` forms, the innermost drawing a path.
private func nestedFormObjects(levels: Int) -> [String] {
    var objects = formObjects("q 10 10 10 10 re f Q")
    for level in 0..<levels where level + 1 < levels {
        // Form `11 + level` draws form `12 + level`; the last one, already in place, draws a path.
        objects[10 + level] = testPDFStream("/Fm Do", extra: "/Type /XObject /Subtype /Form"
            + " /BBox [0 0 600 800] /Resources << /XObject << /Fm \(12 + level) 0 R >> >>")
        objects.append(testPDFStream("q 10 10 10 10 re f Q",
            extra: "/Type /XObject /Subtype /Form /BBox [0 0 600 800]"))
    }
    return objects
}

@Test func formNestingPastTheDepthCapRefusesThePage() throws {
    // At the cap the whole chain is read; one level deeper the reader stops rather than trust
    // tags it has stopped checking, and the page's whole tag set falls back (#241).
    try withTaggedPDF(nestedFormObjects(levels: MarkedTextReader.maximumFormDepth)) { _, page in
        let scan = try #require(MarkedTextReader.scan(page))
        #expect(scan.formsRead == MarkedTextReader.maximumFormDepth)
    }
    try withTaggedPDF(nestedFormObjects(levels: MarkedTextReader.maximumFormDepth + 1)) { _, page in
        #expect(MarkedTextReader.scan(page) == nil)
    }
}

@Test func anXObjectThatIsNeitherImageNorFormStillRefusesThePage() throws {
    var objects = formObjects("")
    objects[10] = testPDFStream("", extra: "/Type /XObject /Subtype /PS")
    try withTaggedPDF(objects) { _, page in
        #expect(MarkedTextReader.scan(page) == nil)
    }
    // An XObject with no subtype at all says nothing about what it draws.
    objects[10] = testPDFStream("", extra: "/Type /XObject")
    try withTaggedPDF(objects) { _, page in
        #expect(MarkedTextReader.scan(page) == nil)
    }
}

@Test func emptyPageTreeCannotTrapStructureTraversal() throws {
    let directory = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("empty.pdf")
    var objects = taggedObjects()
    objects[1] = "<< /Type /Pages /Kids [] /Count 0 >>"
    try testPDF(objects: objects).write(to: url)
    let index = try StructureTreeReader.read(url)
    #expect(index.pages.isEmpty)
}

@Test func structureTraversalHonorsCancellation() async throws {
    let directory = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("cancel.pdf")
    try testPDF(objects: taggedObjects()).write(to: url)
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        _ = try StructureTreeReader.read(url)
    }
    await #expect(throws: CancellationError.self) { try await task.value }
}

@Test func artifactRunningHeadAndSpaceOnlyShowsKeepTheFedPageTags() throws {
    let fixture = try SourceTagFixture.load("fed-109")
    let native = try SourceLayoutFixture.load("fed-109")
    #expect(fixture.sourceSHA256 == native.sourceSHA256)
    try fixture.withPage { url, page in
        // The running head ends `( )Tj EMC /Artifact <<>> BDC (105)Tj`: a show with no
        // positioning operator inside an artifact, after two space-only shows (#67, #91).
        let scan = try #require(MarkedTextReader.scan(page))
        #expect(scan.artifactUnknownOrigins == 1)
        #expect(scan.blankShows == 2)
        // The Link and Note identifiers whose runs continue the cursor cost their own groups;
        // none carries a supported role, so the page's paragraphs and heading keep theirs.
        #expect(scan.unknownOrigins == [25, 26, 29, 34, 35, 37])
        let tree = try StructureTreeReader.read(url)
        let tags = try #require(tree.pages[1])
        #expect(Set(tags.values.map(\.group)).count == 3)
        #expect(StructureTreeReader.validates(tags, owners: try #require(tree.owners[1]), page: page))
        var content = native.content()
        #expect(MarkedTextReader.apply(tags, page: page, lines: &content.lines))
        let tagged = content.lines.filter { $0.structure != nil }
        #expect(tagged.count == 11)
        #expect(tagged.filter { $0.structure?.headingLevel == 4 }.map(\.text) == ["Expedited Funds Availability Act"])
    }
}

@Test func spaceOnlyShowsPastALineEndKeepTheirGroups() throws {
    let fixture = try SourceTagFixture.load("faa-81")
    let native = try SourceLayoutFixture.load("faa-81")
    #expect(fixture.sourceSHA256 == native.sourceSHA256)
    try fixture.withPage { url, page in
        let scan = try #require(MarkedTextReader.scan(page))
        // One show draws nothing but spaces, past the end of a line PDFKit trims (#91).
        #expect(scan.blankShows == 1)
        #expect(scan.blankIdentifiers == [7101])
        #expect(scan.unknownOrigins.isEmpty)
        let tree = try StructureTreeReader.read(url)
        let tags = try #require(tree.pages[1])
        #expect(Set(tags.values.map(\.group)).count == 13)
        #expect(StructureTreeReader.validates(tags, owners: try #require(tree.owners[1]), page: page))
        var content = native.content()
        // That show owns no line, so it neither places nor costs its group: the whole page's
        // tags apply, where main rejected the group and with it the page.
        #expect(MarkedTextReader.apply(tags, page: page, lines: &content.lines))
        #expect(content.lines.filter { $0.structure != nil }.count == 81)
        // The blank identifier counts as shown, and tags no line of its own.
        let blank = try #require(tags[7101]?.group)
        #expect(!content.lines.contains { $0.structure?.group == blank })
        #expect(Set(content.lines.compactMap { $0.structure?.group }).count == 12)
    }
}

@Test func anUnplaceableShowCostsOnlyItsOwnGroup() throws {
    let fixture = try SourceTagFixture.load("faa-91")
    let native = try SourceLayoutFixture.load("faa-91")
    #expect(fixture.sourceSHA256 == native.sourceSHA256)
    try fixture.withPage { url, page in
        let scan = try #require(MarkedTextReader.scan(page))
        // Two marked sections continue the cursor after a font change, so this reader cannot
        // derive their origin. Five more shows draw only spaces (#67, #91).
        #expect(scan.unknownOrigins == [7571, 7594])
        #expect(scan.blankIdentifiers == [7578, 7580, 7592, 7593, 7594])
        let tree = try StructureTreeReader.read(url)
        let tags = try #require(tree.pages[1])
        #expect(Set(tags.values.map(\.group)).count == 20)
        var content = native.content()
        // The two groups those shows belong to fall back; the other eighteen apply, where main
        // refused the page at the first of them.
        #expect(!MarkedTextReader.apply(tags, page: page, lines: &content.lines))
        #expect(Set(content.lines.compactMap { $0.structure?.group }).count == 18)
        #expect(content.lines.filter { $0.structure != nil }.count == 80)
        for id in scan.unknownOrigins {
            let group = try #require(tags[id]?.group)
            #expect(!content.lines.contains { $0.structure?.group == group })
        }
    }
}

@Test func invisibleTextInsideAnArtifactDoesNotRefuseThePage() throws {
    let fixture = try SourceTagFixture.load("loper-1")
    try fixture.withPage { url, page in
        // The opinion's page furniture is drawn in render mode 3 inside an artifact (#91).
        let scan = try #require(MarkedTextReader.scan(page))
        #expect(scan.invisibleArtifactShows == 37)
        #expect(scan.anchors.count == 93)
        let tree = try StructureTreeReader.read(url)
        let tags = try #require(tree.pages[1])
        #expect(Set(tags.values.map(\.group)).count == 12)
        #expect(StructureTreeReader.validates(tags, owners: try #require(tree.owners[1]), page: page))
    }
}

@Test func unmarkedTextFromAnUnknownOriginStillRefusesThePage() throws {
    let fixture = try SourceTagFixture.load("faa-365")
    try fixture.withPage { url, page in
        // Text shown from an origin this reader cannot derive, outside any marked content,
        // could belong to any line: the page's whole tag set stays unused, as before (#67).
        #expect(MarkedTextReader.scan(page) == nil)
        let tree = try StructureTreeReader.read(url)
        var lines: [TextLine] = []
        #expect(!MarkedTextReader.apply(try #require(tree.pages[1]), page: page, lines: &lines))
    }
}

@Test func textFreeFormArtworkNoLongerRefusesTheFAAPage() throws {
    let fixture = try SourceTagFixture.load("faa-16")
    let native = try SourceLayoutFixture.load("faa-16")
    #expect(fixture.sourceSHA256 == native.sourceSHA256)
    // Two forms, one of them nesting a third and selecting a font, and not one show between
    // them: the page's prose is entirely in its own stream (#241).
    #expect(fixture.xobjects.map(\.name) == ["Fm0", "Fm1", "Im0"])
    try fixture.withPage { url, page in
        let scan = try #require(MarkedTextReader.scan(page))
        #expect(scan.formsRead == 3)
        #expect(scan.formShows == 0)
        let tree = try StructureTreeReader.read(url)
        let tags = try #require(tree.pages[1])
        #expect(Set(tags.values.map(\.group)).count == 6)
        #expect(StructureTreeReader.validates(tags, owners: try #require(tree.owners[1]), page: page))
        var content = native.content()
        // Four of the six groups apply, where main refused the page at the first `Do`.
        #expect(!MarkedTextReader.apply(tags, page: page, lines: &content.lines))
        #expect(Set(content.lines.compactMap { $0.structure?.group }).count == 4)
        #expect(content.lines.filter { $0.structure != nil }.count == 17)
    }
}

@Test func aFormsWatermarkIsReadAndDescribesNothing() throws {
    let fixture = try SourceTagFixture.load("faa-373")
    let native = try SourceLayoutFixture.load("faa-373")
    #expect(fixture.sourceSHA256 == native.sourceSHA256)
    try fixture.withPage { url, page in
        // `Fm2` shows "Not to be used for navigation" across the chart, rotated: real text in a
        // form, which no tag on this page describes. The reader reads it and gives it no
        // identifier; its origin falls in none of PDFKit's lines, so it costs nothing (#241).
        let scan = try #require(MarkedTextReader.scan(page))
        #expect(scan.formsRead == 3)
        #expect(scan.formShows == 1)
        let watermark = try #require(scan.anchors.last { $0.id == nil })
        #expect(abs(watermark.point.x - 78.8289) < 0.001 && abs(watermark.point.y - 220.6975) < 0.001)
        #expect(!native.lines.contains { line in
            AnchorMatcher.contains(CGRect(x: line.rect[0], y: line.rect[1], width: line.rect[2],
                                          height: line.rect[3]), watermark.point)
        })
        let tree = try StructureTreeReader.read(url)
        let tags = try #require(tree.pages[1])
        var content = native.content()
        #expect(MarkedTextReader.apply(tags, page: page, lines: &content.lines))
        #expect(content.lines.filter { $0.structure != nil }.count == 2)
    }
}

@Test func aPageWhoseTagsNameNoHeadingKeepsTheHeadingsItDraws() throws {
    let fixture = try SourceTagFixture.load("faa-81")
    let native = try SourceLayoutFixture.load("faa-81")
    #expect(fixture.sourceSHA256 == native.sourceSHA256)
    // The handbook's RoleMap sends every `AC_heading_N` style to `P`, so nothing this page's
    // tags say names a heading, although the page draws two in its recurring bold label style.
    #expect(fixture.identifiers(role: "AC_heading_3") == [7117, 7165])
    // The page's own bold runs, which `LabelStyle` needs, as `HeadingClassificationTests` does.
    var content = native.content()
    for i in content.lines.indices {
        if let source = native.attributedLines.first(where: {
            $0.text.trimmingCharacters(in: .whitespaces) == content.lines[i].text.trimmingCharacters(in: .whitespaces)
        }) {
            let line = content.lines[i]
            content.lines[i] = TextLine(content: NativeTextReader.inlineText(from: source.attributedString()),
                                        rect: line.rect, fontSize: line.fontSize, monospaced: line.monospaced)
        }
    }
    let body = LayoutReconstructor.bodySize(content.lines)
    let labels = Set(["Advantages of Composites", "Disadvantages of Composites"].compactMap { text in
        content.lines.first { $0.text == text }.map { LayoutReconstructor.LabelStyle($0, body: body) }
    })
    #expect(labels.count == 1 && labels.first?.bold == true)
    func headings(_ blocks: [ReflowBlock]) -> [String] {
        blocks.compactMap { if case .heading = $0.content { $0.text } else { nil } }
    }
    var warnings: [ConversionWarning] = []
    let spatial = LayoutReconstructor.blocks(page: content, images: [], vocabulary: [], warnings: &warnings,
                                             labelStyles: labels)
    #expect(headings(spatial) == ["Advantages of Composites", "Disadvantages of Composites"])
    try fixture.withPage { url, page in
        let tree = try StructureTreeReader.read(url)
        let tags = try #require(tree.pages[1])
        #expect(tags.values.allSatisfy { $0.headingLevel == 0 })
        #expect(MarkedTextReader.apply(tags, page: page, lines: &content.lines))
        warnings = []
        let tagged = LayoutReconstructor.blocks(page: content, images: [], vocabulary: [], warnings: &warnings,
                                                labelStyles: labels)
        // Both heading lines carry a paragraph tag, and the page keeps its headings anyway:
        // believing that role is what would take them away (#67).
        #expect(content.lines.filter { $0.structure != nil }.count == 81)
        #expect(["Advantages of Composites", "Disadvantages of Composites"].allSatisfy { text in
            content.lines.first { $0.text == text }?.structure?.headingLevel == 0 })
        #expect(headings(tagged) == headings(spatial))
    }
}
