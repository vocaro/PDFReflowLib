import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

// #91: the two remaining wrong tag rejections of the #75 census. A show of only spaces that lies
// past every extracted line (FAA 145 shows on 65 pages, DGA 35 on 8), and invisible render mode
// set inside an `/Artifact` (Fed page 131). Lines use independent expected geometry, as in
// `StructureTests`, so PDFKit extraction is not exercised here.

/// A ToUnicode map as Adobe PDF Library writes it for a simple font (FAA, DGA, Fed): one-byte
/// entries under a two-byte codespace.
private let adobeUnicodeMap = """
/CIDInit /ProcSet findresource begin 12 dict begin begincmap
/CMapName /Adobe-Identity-UCS def /CMapType 2 def
1 begincodespacerange
<0000> <FFFF>
endcodespacerange
4 beginbfchar
<20> <0020>
<61> <0061>
<65> <0065>
<78> <0078>
endbfchar
1 beginbfrange
<41> <5A> <0041>
endbfrange
endcmap CMapName currentdict /CMap defineresource pop end end
"""

enum BlankShowFont: String, CaseIterable, CustomStringConvertible {
    case adobeMap, oneByteMap, winAnsiWithoutMap
    // Negative controls: fonts whose code 32 this reader cannot know to be a space.
    case mapsSpaceToLetter, builtInEncoding, type3, composite, twoByteEntries
    var description: String { rawValue }
    var recognisesSpace: Bool { [.adobeMap, .oneByteMap, .winAnsiWithoutMap].contains(self) }
    /// The font dictionary (object 4) and, where it has one, its ToUnicode stream (object 10).
    var objects: (font: String, map: String?) {
        let mapped = "<< /Type /Font /Subtype /TrueType /BaseFont /Helvetica /Encoding /WinAnsiEncoding /ToUnicode 10 0 R >>"
        switch self {
        case .adobeMap: return (mapped, adobeUnicodeMap)
        case .oneByteMap: return (mapped, adobeUnicodeMap.replacingOccurrences(of: "<0000> <FFFF>", with: "<00> <FF>"))
        case .winAnsiWithoutMap: return ("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>", nil)
        case .mapsSpaceToLetter: return (mapped, adobeUnicodeMap.replacingOccurrences(of: "<20> <0020>", with: "<20> <0041>"))
        case .builtInEncoding: return ("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>", nil)
        case .type3:
            return ("<< /Type /Font /Subtype /Type3 /FontBBox [0 0 1 1] /FontMatrix [0.001 0 0 0.001 0 0] /CharProcs << >> /Encoding << /Differences [32 /space] >> /FirstChar 32 /LastChar 32 /Widths [250] /ToUnicode 10 0 R >>", adobeUnicodeMap)
        case .composite:
            return ("<< /Type /Font /Subtype /Type0 /BaseFont /Helvetica /Encoding /Identity-H /DescendantFonts [] /ToUnicode 10 0 R >>", adobeUnicodeMap)
        case .twoByteEntries: return (mapped, adobeUnicodeMap.replacingOccurrences(of: "<20> <0020>", with: "<0020> <0020>"))
        }
    }
}

/// A heading (MCID 0) and one paragraph tagged in two pieces (MCIDs 1 and 2). `paragraphEnd` is
/// appended inside MCID 2's text object after its line; `before` and `after` wrap the marked content.
private func pageObjects(font: BlankShowFont = .adobeMap, paragraphEnd: String = "", before: String = "",
                         after: String = "", blankMCID: Bool = false) -> [String] {
    let (fontObject, map) = font.objects
    let blank = blankMCID ? "\n/P << /MCID 3 >> BDC BT /F1 24 Tf 1 0 0 1 80 470 Tm ( ) Tj ET EMC" : ""
    return [
        "<< /Type /Catalog /Pages 2 0 R /StructTreeRoot 6 0 R /MarkInfo << /Marked true >> >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Resources << /Font << /F1 4 0 R /F2 11 0 R >> >> /Contents 5 0 R /StructParents 0 >>",
        fontObject,
        testPDFStream(before + """
        /H3 << /MCID 0 >> BDC BT /F1 12 Tf 1 0 0 1 40 700 Tm (Small heading) Tj ET EMC
        /P << /MCID 1 >> BDC BT /F1 24 Tf 1 0 0 1 40 580 Tm (First paragraph line) Tj ET EMC
        /P << /MCID 2 >> BDC BT /F1 24 Tf 1 0 0 1 80 510 Tm (second paragraph line.) Tj \(paragraphEnd) ET EMC
        """ + blank + after),
        "<< /Type /StructTreeRoot /K [8 0 R 9 0 R] /ParentTree 7 0 R >>",
        blankMCID ? "<< /Nums [0 [8 0 R 9 0 R 9 0 R 9 0 R]] >>" : "<< /Nums [0 [8 0 R 9 0 R 9 0 R]] >>",
        "<< /Type /StructElem /S /H3 /P 6 0 R /Pg 3 0 R /K 0 >>",
        blankMCID ? "<< /Type /StructElem /S /P /P 6 0 R /Pg 3 0 R /K [1 2 3] >>"
            : "<< /Type /StructElem /S /P /P 6 0 R /Pg 3 0 R /K [1 2] >>",
        testPDFStream(map ?? adobeUnicodeMap),
        // A font with no space codes, for the render-mode tests.
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]
}

private func lines() -> [TextLine] {
    [TextLine(text: "Small heading", rect: CGRect(x: 40, y: 697, width: 150, height: 15), fontSize: 12),
     TextLine(text: "First paragraph line", rect: CGRect(x: 40, y: 575, width: 250, height: 28), fontSize: 24),
     TextLine(text: "second paragraph line.", rect: CGRect(x: 80, y: 505, width: 260, height: 28), fontSize: 24)]
}

/// Applies the page's tags to `lines()`; returns the reader's result and the lines.
private func apply(_ objects: [String]) throws -> (Bool, [TextLine]) {
    let directory = try testPDFDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("tagged.pdf")
    try testPDF(objects: objects).write(to: url)
    let document = try #require(CGPDFDocument(url as CFURL))
    let page = try #require(document.page(at: 1))
    let tree = try StructureTreeReader.read(url)
    let tags = try #require(tree.pages[1])
    #expect(StructureTreeReader.validates(tags, owners: try #require(tree.owners[1]), page: page))
    var result = lines()
    let applied = MarkedTextReader.apply(tags, page: page, lines: &result)
    return (applied, result)
}

private func paragraphTagged(_ lines: [TextLine]) -> Bool {
    lines[1].structure != nil && lines[1].structure?.group == lines[2].structure?.group
}

// MARK: - Space-only shows

enum BlankShowPlacement: String, CaseIterable, CustomStringConvertible {
    /// FAA page 18: the next line's origin, below every extracted line box.
    case nextLineStart = "0 -40 Td ( ) Tj"
    /// A trailing space PDFKit trimmed from the line's box.
    case pastTheLineEnd = "1 0 0 1 345 510 Tm ( ) Tj"
    /// Continuing the cursor: an origin the reader cannot derive.
    case unpositioned = "( ) Tj"
    case spacedArray = "0 -40 Td [( ) -250 (  )] TJ"
    var description: String {
        switch self {
        case .nextLineStart: "nextLineStart"
        case .pastTheLineEnd: "pastTheLineEnd"
        case .unpositioned: "unpositioned"
        case .spacedArray: "spacedArray"
        }
    }
}

@Test(arguments: BlankShowPlacement.allCases)
func aSpaceOnlyShowCostsItsGroupNothingWhereverItLies(_ placement: BlankShowPlacement) throws {
    let (applied, result) = try apply(pageObjects(paragraphEnd: placement.rawValue))
    #expect(applied)
    #expect(result[0].structure?.headingLevel == 3)
    #expect(paragraphTagged(result))
}

@Test(arguments: BlankShowPlacement.allCases)
func aVisibleShowInTheSamePlaceStillRejectsItsGroup(_ placement: BlankShowPlacement) throws {
    // Negative control: the same geometry with a letter is text the reader cannot place.
    let (applied, result) = try apply(pageObjects(paragraphEnd: placement.rawValue.replacingOccurrences(of: "( )", with: "(x)")))
    #expect(!applied)
    #expect(result[0].structure?.headingLevel == 3)
    #expect(result[1].structure == nil && result[2].structure == nil)
}

@Test(arguments: BlankShowFont.allCases)
func onlyAFontThatDeclaresItsSpaceCodeMakesAShowBlank(_ font: BlankShowFont) throws {
    let (applied, result) = try apply(pageObjects(font: font, paragraphEnd: BlankShowPlacement.nextLineStart.rawValue))
    #expect(applied == font.recognisesSpace)
    #expect(paragraphTagged(result) == font.recognisesSpace)
    #expect(result[0].structure?.headingLevel == 3)
}

@Test func aMarkedSectionShowingOnlySpacesCountsAsShown() throws {
    // MCID 3 belongs to the paragraph and shows nothing visible; before #91 its group fell back
    // because the identifier anchored no line.
    let (applied, result) = try apply(pageObjects(blankMCID: true))
    #expect(applied)
    #expect(paragraphTagged(result))
}

@Test func anEmptyShowIsNotBlank() throws {
    let (applied, result) = try apply(pageObjects(paragraphEnd: "0 -40 Td () Tj"))
    #expect(!applied)
    #expect(result[1].structure == nil)
}

@Test func theFontIsRestoredWithTheGraphicsState() throws {
    // `q … /F2 Tf … Q` restores F1, whose code 32 is a space; without the restore F2 (no space
    // codes) would still be current and the show would reject the paragraph.
    let restored = "ET q BT /F2 24 Tf ET Q BT 1 0 0 1 80 470 Tm ( ) Tj"
    #expect(try apply(pageObjects(paragraphEnd: restored)).0)
    let changed = "ET BT /F2 24 Tf 1 0 0 1 80 470 Tm ( ) Tj"
    #expect(try !apply(pageObjects(paragraphEnd: changed)).0)
}

// MARK: - Invisible render mode

enum InvisibleShowShape: String, CaseIterable, CustomStringConvertible {
    /// Fed page 131: invisible spaces inside an artifact, reset before the tagged text.
    case artifactSpaces
    /// Invisible text (not spaces) inside an artifact.
    case artifactText
    /// The mode is saved and restored with the graphics state.
    case restoredByQ
    // Still refused: invisible text is inherited transcription wherever structure could own it.
    case markedBodyText, unmarkedText, leftOnAfterTheArtifact, nestedSpanInMarkedText, clippingModeInArtifact
    var description: String { rawValue }
    var applies: Bool { [.artifactSpaces, .artifactText, .restoredByQ].contains(self) }
    var content: (before: String, paragraphEnd: String, after: String) {
        switch self {
        case .artifactSpaces:
            return ("/Artifact << >> BDC BT /F2 1 Tf 3 Tr 8 0 0 8 60 750 Tm ( ) Tj 57.75 0 Td ( ) Tj ET EMC\nBT /Artifact << >> BDC 0 Tr 8 0 0 8 300 760 Tm (127) Tj EMC ET\n", "", "")
        case .artifactText:
            return ("/Artifact << >> BDC BT /F2 8 Tf 3 Tr 1 0 0 1 60 750 Tm (Running head) Tj 0 Tr ET EMC\n", "", "")
        case .restoredByQ:
            return ("q BT /F2 8 Tf 3 Tr ET Q\n", "", "")
        case .markedBodyText:
            return ("", "ET BT /F2 24 Tf 3 Tr 1 0 0 1 80 470 Tm (recognized text) Tj", "")
        case .unmarkedText:
            return ("", "", "\nBT /F2 12 Tf 3 Tr 1 0 0 1 40 300 Tm (Recognized fragment) Tj ET")
        case .leftOnAfterTheArtifact:
            return ("/Artifact << >> BDC BT /F2 8 Tf 3 Tr 1 0 0 1 60 750 Tm (Running head) Tj ET EMC\n", "", "")
        case .nestedSpanInMarkedText:
            return ("", "ET /Span << >> BDC BT /F2 24 Tf 3 Tr 1 0 0 1 80 470 Tm (recognized) Tj ET EMC BT", "")
        case .clippingModeInArtifact:
            return ("/Artifact << >> BDC BT /F2 8 Tf 7 Tr 1 0 0 1 60 750 Tm (Clip) Tj 0 Tr ET EMC\n", "", "")
        }
    }
}

@Test(arguments: InvisibleShowShape.allCases)
func invisibleTextCostsNothingOnlyInsideAnArtifact(_ shape: InvisibleShowShape) throws {
    let (before, paragraphEnd, after) = shape.content
    let (applied, result) = try apply(pageObjects(font: .builtInEncoding, paragraphEnd: paragraphEnd, before: before, after: after))
    #expect(applied == shape.applies)
    // A refusal is page-wide: no line keeps a tag, not even the heading beside it.
    #expect(result.allSatisfy { ($0.structure != nil) == shape.applies })
}
