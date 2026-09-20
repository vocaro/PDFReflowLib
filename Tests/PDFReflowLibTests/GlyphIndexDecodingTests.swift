import Foundation
import CoreGraphics
import CoreText
import PDFKit
import Testing
@testable import PDFReflowLib

// Issue #143/#226: the Census report's TeX fonts name their glyphs `G<index>` with no ToUnicode,
// and the index is a position in the font program, not a character. The fixtures below reproduce
// that mechanism with Type 1 fonts drawn through `TJ` (the operator Distiller emits), so the
// decoder's evidence, its offset search and its line repair can each be exercised without the
// corpus. `DamagedEncodingTests`'s own `'`-drawn Type 3 fixture stays a pure #38 control.

/// The Census body prose, three sentences of it, as the document's own words for the offset
/// search: enough English for the gate (20 words, 10 of four letters or more).
private let corpusLines = [
    "This paper describes methods for masking microdata so that it is better",
    "protected against re-identification. The masking methods are rank swapping",
    "and additive noise. The empirical comparisons use variants of the framework",
    "for measuring information loss that were introduced by the other authors.",
]

/// A simple Type 1 font whose `Differences` names each code by its index. `offsets` maps a
/// character to the index its glyph name carries; a character absent from it is named at
/// `character + offset`.
private struct IndexFont {
    var name: String
    var characters: Set<Character>
    var offset: Int
    /// Index names that break the constant offset, for the permuted control.
    var overrides: [Character: Int] = [:]

    var codes: [Character] { characters.sorted() }

    func index(of character: Character) -> Int {
        overrides[character] ?? Int(character.unicodeScalars.first!.value) + offset
    }

    /// The font dictionary, numbering codes from 1 in `codes` order as Distiller does.
    var dictionary: String {
        let differences = codes.enumerated().map { "\($0.offset + 1) /G\(index(of: $0.element))" }.joined(separator: " ")
        return "<< /Type /Font /Subtype /Type1 /BaseFont /ABCDEF+\(name) /FirstChar 1 /LastChar \(codes.count) "
            + "/Widths [\(codes.map { _ in "500" }.joined(separator: " "))] "
            + "/Encoding << /Type /Encoding /Differences [\(differences)] >> >>"
    }

    /// The one-byte code of a character in this font.
    func code(of character: Character) -> Int? { codes.firstIndex(of: character).map { $0 + 1 } }
}

/// A page's text: one `TJ` array per line, with a negative adjustment at each word gap (the
/// Census report's own −430, well past `wordGapEms`) and a kern between letters.
private func showLine(_ text: String, font: IndexFont, resource: String, size: Int,
                      spacing: String = "0", x: Int = 20, y: Int) -> String {
    var elements: [String] = []
    var run = ""
    func flush() {
        guard !run.isEmpty else { return }
        elements.append("<\(run)>")
        run = ""
    }
    for character in text {
        if character == " " {
            flush()
            elements.append("-430")
            continue
        }
        guard let code = font.code(of: character) else { continue }
        run += String(format: "%02X", code)
    }
    flush()
    return "BT /\(resource) \(size) Tf \(spacing) Tc 1 0 0 1 \(x) \(y) Tm [\(elements.joined())] TJ ET"
}

private func indexGlyphPDF(fonts: [IndexFont], lines: [Line]) -> Data {
    var resources = ""
    for index in fonts.indices { resources += "/F\(index) \(5 + index) 0 R " }
    let content = lines.map { line in
        showLine(line.text, font: fonts[line.font], resource: "F\(line.font)", size: line.size,
                 spacing: line.spacing, y: line.y)
    }.joined(separator: "\n")
    return testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << \(resources)>> >> /Contents 4 0 R >>",
        testPDFStream(content),
    ] + fonts.map(\.dictionary))
}

/// A page PDFKit can actually read: `DamagedEncodingTests`'s Type 3 font, whose glyph procedures
/// draw the real letters through Helvetica while its `Differences` names each code `G<code + 3>`,
/// but shown through `TJ` arrays with the Census report's own word-gap adjustments rather than
/// through `'`. `overrides` breaks the constant offset for a permuted control.
private func drawnIndexGlyphPDF(_ lines: [String], overrides: [Character: Int] = [:]) -> Data {
    let helvetica = pdfKitGated { CTFontCreateWithName("Helvetica" as CFString, 1000, nil) }
    func width(_ code: Int) -> Int {
        var character = UniChar(code), glyph = CGGlyph()
        return pdfKitGated {
            CTFontGetGlyphsForCharacters(helvetica, &character, &glyph, 1)
            return Int(CTFontGetAdvancesForGlyphs(helvetica, .horizontal, &glyph, nil, 1).rounded())
        }
    }
    func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
    }
    func name(_ code: Int) -> Int { overrides[Character(UnicodeScalar(UInt8(code)))] ?? code + 3 }
    let codes = Set(lines.joined().unicodeScalars.map(\.value).filter { $0 != 32 }).sorted().map(Int.init)
    // 1 catalog, 2 pages, 3 Helvetica, 4 page, 5 content, 6 font, 7 encoding, 8 CharProcs, then
    // one glyph procedure per code.
    let font = 6, encoding = 7, charProcs = 8
    let procedure = { (code: Int) in 9 + codes.firstIndex(of: code)! }
    let first = codes.min() ?? 33, last = codes.max() ?? 33
    let widths = (first...last).map { codes.contains($0) ? width($0) : 0 }
    var content = ""
    for (index, line) in lines.enumerated() {
        var elements = "", run = ""
        for character in line {
            if character == " " {
                if !run.isEmpty { elements += "<\(run)>"; run = "" }
                elements += "-430"
                continue
            }
            run += String(format: "%02X", Int(character.unicodeScalars.first!.value))
        }
        if !run.isEmpty { elements += "<\(run)>" }
        content += "BT /T 10 Tf 0 Tc 1 0 0 1 20 \(700 - index * 14) Tm [\(elements)] TJ ET\n"
    }
    var objects = [
        "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [4 0 R] /Count 1 >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /T \(font) 0 R >> >> /Contents 5 0 R >>",
        testPDFStream(content),
        "<< /Type /Font /Subtype /Type3 /FontBBox [0 0 1000 800] /FontMatrix [0.001 0 0 0.001 0 0] "
            + "/CharProcs \(charProcs) 0 R /Encoding \(encoding) 0 R /FirstChar \(first) /LastChar \(last) "
            + "/Widths [\(widths.map(String.init).joined(separator: " "))] /Resources << /Font << /F1 3 0 R >> >> >>",
        "<< /Type /Encoding /Differences [" + codes.map { "\($0) /G\(name($0))" }.joined(separator: " ") + "] >>",
        "<< " + codes.map { "/G\(name($0)) \(procedure($0)) 0 R" }.joined(separator: " ") + " >>",
    ]
    for code in codes {
        objects.append(testPDFStream("\(width(code)) 0 d0 BT /F1 1000 Tf 0 0 Td (\(escaped(String(UnicodeScalar(code)!)))) Tj ET"))
    }
    return testPDF(objects: objects)
}

/// The document's body font: Cork-named, so its codes read through the Cork table.
private func bodyFont(_ name: String = "dcr10084", offset: Int = 3,
                      overrides: [Character: Int] = [:]) -> IndexFont {
    IndexFont(name: name, characters: Set(corpusLines.joined().filter { $0 != " " }),
              offset: offset, overrides: overrides)
}

/// `CGPDFPage.document` is an unowned back-reference, so the document is returned beside the page
/// and every caller keeps it alive for as long as it reads the page.
private func page(of data: Data) throws -> (document: CGPDFDocument, page: CGPDFPage) {
    let provider = try #require(CGDataProvider(data: data as CFData))
    let document = try #require(CGPDFDocument(provider))
    GlyphIndexDecoder.forgetMemoizedDocument()
    return (document, try #require(document.page(at: 1)))
}

private typealias Line = (text: String, font: Int, size: Int, spacing: String, y: Int)

private func bodyLines(font: Int = 0, size: Int = 10, from top: Int = 700) -> [Line] {
    corpusLines.enumerated().map { (text: $0.element, font: font, size: size, spacing: "0", y: top - $0.offset * 14) }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/226"))
func theDocumentsOwnWordsEstablishOneOffsetPerFont() throws {
    let data = indexGlyphPDF(fonts: [bodyFont()], lines: bodyLines())
    let (document, reference) = try page(of: data)
    let table = GlyphIndexDecoder.read(document)
    let font = try #require(GlyphIndexDecoder.scan(reference)?.fonts.values.first)
    let characters = try #require(table[font.key])
    // Every code reads as the letter the document draws, through the Cork table its `dc` name
    // says it carries: the offset is whatever the words establish, not an assumed shift.
    for character in "Thispaperdescribesmethods" {
        let code = try #require(font.indexes.first { $0.value == Int(character.unicodeScalars.first!.value) + 3 })
        #expect(characters[code.key] == String(character), "\(character)")
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/226"))
func aFontWhoseGlyphOrderHasNoConstantOffsetIsLeftUndecoded() throws {
    // A permutation, not a shift: five letters carry indexes no single offset explains. Nothing
    // in the document states them, so the font decodes at no offset and #38's path stands.
    let permuted = bodyFont(overrides: ["e": 900, "t": 901, "a": 902, "o": 903, "s": 904])
    let data = indexGlyphPDF(fonts: [permuted], lines: bodyLines())
    let (document, reference) = try page(of: data)
    #expect(GlyphIndexDecoder.read(document).isEmpty)
    #expect(GlyphIdentityReader.read(reference).isEmpty)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/226"))
func tooFewWordsLeaveAFontUndecodedUnlessItsOwnFamilyEstablishesTheOffset() throws {
    // The typewriter font of #149 item 2: it draws one e-mail address, far under the 20 words any
    // statistics need, and #143's gate therefore left page 2 on recognition.
    let address = "{william.e.yancey,william.e.winkler,robert.h.creecy}@census.gov"
    let typewriter = IndexFont(name: "dctt10075", characters: Set(address), offset: 3)
    let alone = try page(of: indexGlyphPDF(fonts: [typewriter],
        lines: [(text: address, font: 0, size: 10, spacing: "0", y: 700)]))
    #expect(GlyphIndexDecoder.read(alone.document).isEmpty)

    // Beside the document's other Cork-named fonts, which establish +3 from thousands of glyphs,
    // it decodes completely at the offset they establish.
    let fonts = [bodyFont(), bodyFont("dcbx100120"), bodyFont("dcti10084"), typewriter]
    var lines = bodyLines()
    lines += bodyLines(font: 1, from: 640) + bodyLines(font: 2, from: 580)
    lines.append((text: address, font: 3, size: 10, spacing: "0", y: 520))
    let together = try page(of: indexGlyphPDF(fonts: fonts, lines: lines))
    let table = GlyphIndexDecoder.read(together.document)
    let scanned = try #require(GlyphIndexDecoder.scan(together.page))
    let key = try #require(scanned.fonts.values.first { $0.baseFont?.contains("dctt") == true }).key
    let characters = try #require(table[key])
    #expect(characters.count == typewriter.codes.count)
    for character in address where character != " " {
        let code = try #require(typewriter.code(of: character))
        #expect(characters[UInt8(code)] == String(character), "\(character)")
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/226"))
func corroborationNeedsTwoAgreeingCorkFontsAndACompleteReading() throws {
    let typewriter = IndexFont(name: "dctt10075", characters: Set("abcde"), offset: 3).asDecoderFont
    let decoded: [(font: GlyphIndexDecoder.Font, offset: Int)] = [
        (bodyFont("dcr10084").asDecoderFont, 3), (bodyFont("dcbx100120").asDecoderFont, 3),
    ]
    #expect(GlyphIndexDecoder.corroboratedOffset(for: typewriter, among: decoded) == 3)
    // One witness is not the document's family speaking.
    #expect(GlyphIndexDecoder.corroboratedOffset(for: typewriter, among: [decoded[0]]) == nil)
    // Two witnesses that disagree establish nothing.
    let split: [(font: GlyphIndexDecoder.Font, offset: Int)] = [
        (bodyFont("dcr10084").asDecoderFont, 3), (bodyFont("dcbx100120").asDecoderFont, 5),
    ]
    #expect(GlyphIndexDecoder.corroboratedOffset(for: typewriter, among: split) == nil)
    // A font that is not Cork-named never inherits a Cork offset, however many `dc` fonts agree.
    let math = IndexFont(name: "cmmi10084", characters: Set("abcde"), offset: 0).asDecoderFont
    #expect(GlyphIndexDecoder.corroboratedOffset(for: math, among: decoded) == nil)
    // Nor does a Cork-named font with a code the offset states no character for (index 0 lands on
    // Cork's `grave` accent slot, which sets no character of its own).
    let incomplete = IndexFont(name: "dcss1000", characters: Set("ab"), offset: 3, overrides: ["a": 3]).asDecoderFont
    #expect(GlyphIndexDecoder.corroboratedOffset(for: incomplete, among: decoded) == nil)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/226"))
func aLineIsRebuiltFromItsGlyphsOnlyWhenTheySpellWhatPDFKitRead() throws {
    let glyphs = [
        GlyphIdentityReader.IndexGlyph(reported: "w", drawn: "t", startsWord: false),
        GlyphIdentityReader.IndexGlyph(reported: "k", drawn: "h", startsWord: false),
        GlyphIdentityReader.IndexGlyph(reported: "h", drawn: "e", startsWord: false),
    ]
    let repaired = GlyphIdentityReader.repairIndexGlyphs(glyphs, in: NSAttributedString(string: "wkh"))
    #expect(repaired?.string == "the")
    // A character no glyph explains leaves the line exactly as PDFKit read it.
    #expect(GlyphIdentityReader.repairIndexGlyphs(glyphs, in: NSAttributedString(string: "wkhx")) == nil)
    // So does a glyph the line has no room for.
    #expect(GlyphIdentityReader.repairIndexGlyphs(glyphs, in: NSAttributedString(string: "wk")) == nil)
    // Blanks stand wherever PDFKit put them; a ligature PDFKit reports as nothing is placed where
    // it is drawn, after the space when its own gap opens the word.
    let withLigature = [
        GlyphIdentityReader.IndexGlyph(reported: "g", drawn: "d", startsWord: false),
        GlyphIdentityReader.IndexGlyph(reported: "", drawn: "\u{FB01}", startsWord: true),
        GlyphIdentityReader.IndexGlyph(reported: "o", drawn: "l", startsWord: false),
    ]
    #expect(GlyphIdentityReader.repairIndexGlyphs(withLigature, in: NSAttributedString(string: "g o"))?.string == "d \u{FB01}l")
    // A word gap the page's character spacing hid opens a word even where PDFKit set none.
    let spaced = [
        GlyphIdentityReader.IndexGlyph(reported: "4", drawn: "1", startsWord: false),
        GlyphIdentityReader.IndexGlyph(reported: "L", drawn: "I", startsWord: true),
        GlyphIdentityReader.IndexGlyph(reported: "q", drawn: "n", startsWord: false),
    ]
    #expect(GlyphIdentityReader.repairIndexGlyphs(spaced, in: NSAttributedString(string: "4Lq"))?.string == "1 In")
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/226"))
func aGlyphNoFontStatesBecomesAReplacementCharacterAndKeepsThePageOnItsOldPath() throws {
    // The footnote mark of page 2: one glyph of a font the document's words cannot reach. The
    // page's prose still decodes; the mark is admitted rather than guessed at.
    let mark = IndexFont(name: "cmmib10084", characters: ["\u{22C6}"], offset: 0, overrides: ["\u{22C6}": 66])
    var lines = bodyLines()
    lines.append((text: "\u{22C6}", font: 1, size: 10, spacing: "0", y: 640))
    let (document, reference) = try page(of: indexGlyphPDF(fonts: [bodyFont(), mark], lines: lines))
    _ = document
    let shows = GlyphIdentityReader.read(reference)
    let undecoded = try #require(shows.last?.indexGlyphs)
    #expect(undecoded.map(\.drawn) == [GlyphIndexDecoder.unknownCharacter])
    // The body font is unaffected by the font beside it.
    let bodyShow = try #require(shows.first?.indexGlyphs)
    #expect(bodyShow.map(\.drawn).joined().hasPrefix("Thispaper"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/226"))
func textTheLinesDidNotTakeIsCountedAgainstThePage() throws {
    let data = indexGlyphPDF(fonts: [bodyFont()], lines: bodyLines())
    let (document, reference) = try page(of: data)
    _ = document
    // The extracted text carries the decoded reading: nothing is unread.
    let decoded = corpusLines.joined(separator: "\n")
    #expect(GlyphIndexDecoder.unreadGlyphs(on: reference, in: decoded) == 0)
    // A page whose lines kept PDFKit's index-shifted reading instead has its prose counted.
    #expect(GlyphIndexDecoder.unreadGlyphs(on: reference, in: "") > 40)
    // A run with no function word in it is a table row or a column heading, not prose, and says
    // nothing about whether the page's sentences can be trusted.
    let rowOnly = IndexFont(name: "dcr10084", characters: Set("rnkswp0123456789."), offset: 3)
    let fonts = [bodyFont(), rowOnly]
    var lines = bodyLines()
    lines.append((text: "rnkswp05 0.8861 0.9620", font: 1, size: 10, spacing: "0", y: 640))
    let mixed = try page(of: indexGlyphPDF(fonts: fonts, lines: lines))
    #expect(GlyphIndexDecoder.unreadGlyphs(on: mixed.page, in: decoded) == 0)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/226"))
func aDecodedPageReflowsItsOwnWordsInsteadOfBeingRecognized() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let source = dir.appendingPathComponent("index-glyphs.pdf")
    try drawnIndexGlyphPDF(corpusLines).write(to: source)
    var options = ConversionOptions(); options.ocr = .automatic
    let result = try await PDFReflowLibPipeline.reconstruct(from: source, options: options,
        workspace: dir.appendingPathComponent("work"), progress: { _ in })
    #expect(!result.warnings.contains { $0.code == .damagedTextEncoding })
    #expect(result.recognizedPageCount == 0)
    let text = result.book.blocks.map(\.text).joined(separator: "\n")
    #expect(text.contains("This paper describes methods for masking microdata"))
    #expect(!text.contains("Wklv sdshu"))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/226"))
func aPermutedFontStillReportsTheDamagedEncodingAndIsRecognized() async throws {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let source = dir.appendingPathComponent("permuted.pdf")
    try drawnIndexGlyphPDF(corpusLines, overrides: ["e": 900, "t": 901, "a": 902, "o": 903, "s": 904]).write(to: source)
    var options = ConversionOptions(); options.ocr = .never
    let result = try await PDFReflowLibPipeline.reconstruct(from: source, options: options,
        workspace: dir.appendingPathComponent("work"), progress: { _ in })
    #expect(result.warnings.contains { $0.code == .damagedTextEncoding })
    let text = result.book.blocks.map(\.text).joined(separator: "\n")
    #expect(!text.contains("This paper describes"))
}

private extension IndexFont {
    /// The decoder's own value for this font, for the corroboration unit tests.
    var asDecoderFont: GlyphIndexDecoder.Font {
        var indexes: [UInt8: Int] = [:]
        for (position, character) in codes.enumerated() { indexes[UInt8(position + 1)] = index(of: character) }
        return GlyphIndexDecoder.Font(key: name, baseFont: "ABCDEF+\(name)", indexes: indexes, names: [:])
    }
}
