import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

private func taggedObjects() -> [String] {
    [
        "<< /Type /Catalog /Pages 2 0 R /StructTreeRoot 6 0 R /MarkInfo << /Marked false >> >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R /StructParents 0 >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        testPDFStream("""
        /P << /MCID 0 >> BDC BT /F1 12 Tf 1 0 0 1 40 700 Tm (Small heading) Tj ET EMC
        /Span << /MCID 1 >> BDC BT /F1 24 Tf 1 0 0 1 40 580 Tm (First paragraph line) Tj ET EMC
        /P << /MCID 2 >> BDC BT /F1 24 Tf 1 0 0 1 80 510 Tm (second paragraph line.) Tj ET EMC
        """),
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

@Test(arguments: ["unknownCursor", "unbalanced", "unmarkedOverlap", "missingMCID", "form", "initialAdjustment"])
func ambiguousMarkedContentKeepsNativeText(_ failure: String) throws {
    var objects = taggedObjects()
    switch failure {
    case "unknownCursor": objects[4] = testPDFStream("BT /F1 12 Tf 40 700 Td (First) Tj ( second) Tj ET")
    case "unbalanced": objects[4] = testPDFStream("/P <</MCID 0>> BDC BT /F1 12 Tf 40 700 Td (First) Tj ET")
    case "unmarkedOverlap": objects[4] = testPDFStream("/P <</MCID 0>> BDC BT /F1 12 Tf 40 700 Td (First) Tj ET EMC BT /F1 12 Tf 50 700 Td (Other) Tj ET")
    case "missingMCID": objects[4] = testPDFStream("BT /F1 12 Tf 40 700 Td (Untagged) Tj ET")
    case "form": objects[4] = testPDFStream("/Unknown Do")
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
    let file = Bundle.module.resourceURL!.appendingPathComponent("fixtures/our-flag-page-29-tags.json")
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
        // Spatially the two stacked title lines merge into one heading (#55); the tag supplies the level.
        #expect(baseline.filter { if case .heading = $0.content { true } else { false } }.count == 1)
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

// MARK: - Unknown text-show origins (#67)

/// The Fed Explained's running head: a positioned show, then further `/Artifact` sections whose
/// shows carry no positioning operator of their own. An artifact holds no structure, so an origin
/// this reader cannot derive inside one must cost the page's tags nothing.
private let artifactRunningHead = """
/Artifact << /O /Layout >> BDC BT /F1 8 Tf 1 0 0 1 40 760 Tm (vi) Tj EMC
/Artifact << >> BDC ( ) Tj EMC
/Artifact << >> BDC 2 0 Td (The Fed Explained) Tj EMC ET
"""

@Test func artifactShowWithoutAPositioningOperatorKeepsEveryGroupOnThePage() throws {
    var objects = taggedObjects()
    objects[4] = testPDFStream(artifactRunningHead + "\n" + """
    /P << /MCID 0 >> BDC BT /F1 12 Tf 1 0 0 1 40 700 Tm (Small heading) Tj ET EMC
    /Span << /MCID 1 >> BDC BT /F1 24 Tf 1 0 0 1 40 580 Tm (First paragraph line) Tj ET EMC
    /P << /MCID 2 >> BDC BT /F1 24 Tf 1 0 0 1 80 510 Tm (second paragraph line.) Tj ET EMC
    """)
    try withTaggedPDF(objects) { url, page in
        let blocks = try taggedBlocks(url, page)
        #expect(blocks.map(\.text) == ["Small heading", "First paragraph line second paragraph line."])
    }
}

@Test func unknownOriginInsideATaggedGroupRejectsOnlyThatGroup() throws {
    var objects = taggedObjects()
    // The paragraph's second show continues the first show's cursor, as a run-in style change
    // does; its origin needs the font's glyph widths, which this reader deliberately lacks.
    objects[4] = testPDFStream("""
    /P << /MCID 0 >> BDC BT /F1 12 Tf 1 0 0 1 40 700 Tm (Small heading) Tj ET EMC
    /Span << /MCID 1 >> BDC BT /F1 24 Tf 1 0 0 1 40 580 Tm (First paragraph line) Tj ET EMC
    /P << /MCID 2 >> BDC BT /F1 24 Tf 1 0 0 1 80 510 Tm (second paragraph) Tj ( line.) Tj ET EMC
    """)
    try withTaggedPDF(objects) { url, page in
        let tree = try StructureTreeReader.read(url)
        let tags = try #require(tree.pages[1])
        #expect(StructureTreeReader.validates(tags, owners: try #require(tree.owners[1]), page: page))
        var lines = taggedLines()
        // Only the paragraph group that showed the unplaceable text falls back. The heading
        // beside it keeps its validated role, which the whole-page rule used to discard.
        #expect(!MarkedTextReader.apply(tags, page: page, lines: &lines))
        #expect(lines[0].structure?.headingLevel == 3)
        #expect(lines[1].structure == nil && lines[2].structure == nil)
    }
}

/// A chapter numeral set in display type shares one extracted line with the title beside it, and
/// that line's box is tall enough to cover the origin of the title's second line.
private func displayInitialObjects() -> [String] {
    [
        "<< /Type /Catalog /Pages 2 0 R /StructTreeRoot 6 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R /StructParents 0 >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        testPDFStream(artifactRunningHead + "\n" + """
        /Span << /MCID 1 >> BDC BT /F1 70 Tf 1 0 0 1 40 600 Tm (1) Tj ET EMC
        /H2 << /MCID 0 >> BDC BT /F1 24 Tf 1 0 0 1 120 690 Tm (Overview of the) Tj 0 -30 Td (Federal Reserve) Tj ET EMC
        """),
        "<< /Type /StructTreeRoot /K [8 0 R] /ParentTree 7 0 R >>",
        "<< /Nums [0 [8 0 R 9 0 R]] >>",
        "<< /Type /StructElem /S /H2 /P 6 0 R /Pg 3 0 R /K [9 0 R 0] >>",
        "<< /Type /StructElem /S /Span /P 8 0 R /K 1 >>",
    ]
}

@Test(arguments: [true, false])
func displayInitialLineDoesNotCaptureTheNextLineOrigin(_ startsAtTheOrigin: Bool) throws {
    try withTaggedPDF(displayInitialObjects()) { url, page in
        let tree = try StructureTreeReader.read(url)
        let tags = try #require(tree.pages[1])
        #expect(StructureTreeReader.validates(tags, owners: try #require(tree.owners[1]), page: page))
        // The numeral's 70-point box spans both title lines. Only the ambiguity that exactly one
        // left edge at the show's own origin resolves is used; anything else still falls back.
        var lines = [TextLine(text: "1 Overview of the",
                              rect: CGRect(x: 40, y: 590, width: 260, height: 120), fontSize: 24),
                     TextLine(text: "Federal Reserve",
                              rect: CGRect(x: startsAtTheOrigin ? 120 : 60, y: 655, width: 180, height: 26),
                              fontSize: 24)]
        #expect(MarkedTextReader.apply(tags, page: page, lines: &lines) == startsAtTheOrigin)
        #expect(lines.allSatisfy { ($0.structure != nil) == startsAtTheOrigin })
        #expect(!startsAtTheOrigin || lines[0].structure?.headingLevel == 2)
    }
}

// MARK: - Consuming levels a partly reconstructable hierarchy supplies (#67)

private func ranked(_ blocks: [(size: CGFloat, tagged: Int?)]) -> [Int] {
    var document = blocks.enumerated().map { index, block -> ReflowBlock in
        var result = ReflowBlock(content: .heading(id: "h\(index)", text: InlineText("Heading \(index)"), level: 2),
                                 page: index + 1)
        result.headingSize = block.size
        result.taggedLevel = block.tagged
        return result
    }
    LayoutReconstructor.rankHeadingLevels(&document)
    return document.map { if case let .heading(_, _, level) = $0.content { level } else { 0 } }
}

@Test func aValidatedLevelYieldsWhenALargerHeadingWouldShareIt() {
    // A cover title at 30 and chapter titles at 24 that the tags never reached, tagged `H3`
    // sections at 16 over untagged 14 and 12. The typographic scale is 30/24/14/12, so the
    // chapters already rank 3 and the sections' validated 3 would make them siblings of the
    // larger titles above them: they rank by size instead, joining the scale they are ranked on.
    #expect(ranked([(30, nil), (24, nil), (16, 3), (14, nil), (12, nil)]) == [2, 3, 4, 5, 6])
    // With no such heading between them, the validated level holds and never joins the scale,
    // so the untagged headings rank exactly as they did before any tag applied.
    #expect(ranked([(30, nil), (16, 3), (12, nil)]) == [2, 3, 3])
    #expect(ranked([(30, nil), (12, nil)]) == [2, 3])
    // Nothing outranks a cover's `H1`, so it keeps level 1 and adds no tier of its own.
    #expect(ranked([(30, 1), (24, nil), (12, nil)]) == [1, 2, 3])
    #expect(ranked([(30, nil), (24, nil), (16, nil), (12, nil)]) == [2, 3, 4, 5])
    // Our Flag's shape: `H3` tagged from 18 to 21 points with an untagged 20-point sibling inside
    // that range. The sibling is not larger than every `H3`, so the validated levels hold.
    #expect(ranked([(30, 1), (22, 2), (22, nil), (21, 3), (20, nil), (18, 3)]) == [1, 2, 2, 3, 3, 3])
    // The Fed's shape: once `H3` yields to the larger untagged chapter titles, the `H4` and `H5`
    // beneath it yield too, so the tagged 12-point `H5` cannot land beside the 14-point `H4`.
    #expect(ranked([(40, 1), (24, nil), (16, 3), (14, 4), (12, 5)]) == [1, 2, 3, 4, 5])
    #expect(ranked([(40, 1), (30, nil), (24, nil), (16, 3), (14, 4), (12, 5)]) == [1, 2, 3, 4, 5, 6])
}

/// A 20-point line tagged as a paragraph, in one of four page shapes.
private enum LabelShape: String, CaseIterable {
    /// Over the body it introduces, sharing its left edge (the Fed's `Advisory Councils`).
    case overItsBody
    /// Above a larger title (the Fed cover's `PUBLIC EDUCATION & OUTREACH`).
    case aboveATitle
    /// Centred well right of the text under it (Our Flag's title-page imprint).
    case centredImprint
    /// Heading the right column while the left column's text interleaves in reading order
    /// (FAA page 194's `Pressurized Aircraft`).
    case rightColumn
}

private func labelledPage(_ shape: LabelShape) -> PageContent {
    let prose = "Five advisory committees assist and advise the Board on public policy."
    var lines: [TextLine] = []
    let labelX: CGFloat = switch shape { case .centredImprint: 200; case .rightColumn: 320; default: 60 }
    var label = TextLine(text: "Advisory Councils", rect: CGRect(x: labelX, y: 700, width: 180, height: 20), fontSize: 20)
    label.structure = TextStructure(group: 2, order: 2, headingLevel: 0, lineCount: 1)
    lines.append(label)
    if shape == .aboveATitle {
        lines.append(TextLine(text: "Our Flag Explained", rect: CGRect(x: 60, y: 650, width: 300, height: 28), fontSize: 28))
    }
    let bodyX: CGFloat = shape == .rightColumn ? 320 : 60
    let width: CGFloat = shape == .rightColumn ? 230 : 420
    for i in 0..<6 {
        lines.append(TextLine(text: prose, rect: CGRect(x: bodyX, y: 600 - CGFloat(i) * 13, width: width, height: 10),
                              fontSize: 10))
        if shape == .rightColumn {
            lines.append(TextLine(text: "the ground is a second disadvantage of the tailwheel landing gear.",
                                  rect: CGRect(x: 60, y: 606 - CGFloat(i) * 13, width: 230, height: 10), fontSize: 10))
        }
    }
    return PageContent(number: 1, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), lines: lines, graphics: [])
}

@Test(arguments: LabelShape.allCases)
private func aParagraphTagInHeadingTypeKeepsItsSpatialReadingOnlyWhereItHeadsTheTextBelow(_ shape: LabelShape) {
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: labelledPage(shape), images: [], vocabulary: [], warnings: &warnings)
    let headings = blocks.compactMap { block -> String? in
        if case let .heading(_, text, _) = block.content { text.text } else { nil }
    }
    // A display-type paragraph over the body it introduces, in its own column, keeps the heading
    // the page's own typography gives it. Above a larger title, or centred well right of the text
    // under it, it heads nothing and stays the paragraph the source tagged.
    let heads = shape == .overItsBody || shape == .rightColumn
    #expect(headings.contains("Advisory Councils") == heads, "\(shape.rawValue)")
    #expect(blocks.contains { $0.text.hasPrefix("Five advisory committees") })
}
