import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import PDFReflowLib

// Symbol-font characters PDFKit reports as private-use code points (#155). The font dictionaries and
// ToUnicode maps below are copied from the corpus sources (no font program is embedded, so PDFKit reads
// the codes through the maps alone): the NASA GWL paper's Word `SymbolMT` (object 115 and its
// descendant, page 4: alpha at U+F061, page 13: bullet at U+F0B7, descriptor flags 32), the Supreme
// Court opinion's `BDGFGH+SymbolMT` (page 86: bullet at U+F0B7, flags 4, family `Symbol`) and Wallace's
// `RRTZXD+CMEX10` (page 312: `parenlefttp` at U+F8EB).

private func cmap(_ codespace: String, _ entries: String) -> String {
    testPDFStream("""
        /CIDInit /ProcSet findresource begin 12 dict begin begincmap
        /CMapName /Test-UCS def /CMapType 2 def
        1 begincodespacerange \(codespace) endcodespacerange
        \(entries)
        endcmap CMapName currentdict /CMap defineresource pop end end
        """)
}

/// A composite Identity-H font as Word writes SymbolMT, and its descendant and descriptor objects.
private func compositeFont(name: String, flags: Int, family: String? = nil, map: Int) -> [String] {
    let familyEntry = family.map { " /FontFamily (\($0))" } ?? ""
    return [
        "<< /Type /Font /Subtype /Type0 /BaseFont /\(name) /Encoding /Identity-H /DescendantFonts [PLACEHOLDER_CID 0 R] /ToUnicode \(map) 0 R >>",
        "<< /Type /Font /Subtype /CIDFontType2 /BaseFont /\(name) /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> /CIDToGIDMap /Identity /DW 1000 /FontDescriptor PLACEHOLDER_DESCRIPTOR 0 R >>",
        "<< /Type /FontDescriptor /FontName /\(name) /Flags \(flags)\(familyEntry) /FontBBox [0 -216 1113 1005] /ItalicAngle 0 /Ascent 1005 /Descent -216 /CapHeight 693 /StemV 60 >>",
    ]
}

/// One page whose resources name `fonts` (`F1` is Helvetica; symbol fonts follow as `F2`, `F3`, …),
/// drawing `content`. Each symbol font is given as its object strings; `PLACEHOLDER_*` are resolved.
private func document(content: String, symbolFonts: [[String]], form: Bool = false) throws -> PDFDocument {
    var objects = [
        "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "PAGE", testPDFStream(form ? "q /X0 Do Q" : content),
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
    ]
    var fontEntries = "/F1 5 0 R"
    for (index, font) in symbolFonts.enumerated() {
        let first = objects.count + 1
        var resolved = font
        for position in resolved.indices {
            resolved[position] = resolved[position]
                .replacingOccurrences(of: "PLACEHOLDER_CID", with: "\(first + 1)")
                .replacingOccurrences(of: "PLACEHOLDER_DESCRIPTOR", with: "\(first + 2)")
                .replacingOccurrences(of: "PLACEHOLDER_MAP", with: "\(first + font.count - 1)")
        }
        objects += resolved
        fontEntries += " /F\(index + 2) \(first) 0 R"
    }
    if form {
        objects.append(testPDFStream(content, extra: "/Type /XObject /Subtype /Form /BBox [0 0 612 792] /Resources << /Font << \(fontEntries) >> >>"))
        objects[2] = "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /XObject << /X0 \(objects.count) 0 R >> >> /Contents 4 0 R >>"
    } else {
        objects[2] = "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << \(fontEntries) >> >> /Contents 4 0 R >>"
    }
    return try #require(PDFDocument(data: testPDF(objects: objects)))
}

/// Word's SymbolMT, as object strings with its ToUnicode map last.
private func wordSymbol(name: String = "SymbolMT", flags: Int = 32, family: String? = nil) -> [String] {
    var font = compositeFont(name: name, flags: flags, family: family, map: 0)
    font[0] = font[0].replacingOccurrences(of: "/ToUnicode 0 0 R", with: "/ToUnicode PLACEHOLDER_MAP 0 R")
    return font + [cmap("<0000> <FFFF>", "2 beginbfchar <0044> <F061> <0078> <F0B7> endbfchar")]
}

private func lineTexts(_ document: PDFDocument) throws -> [String] {
    let page = try #require(document.page(at: 0))
    return try NativeTextReader.lines(on: page, limit: 100_000).map(\.text)
}

private func hasPrivateUse(_ texts: [String]) -> Bool { texts.contains(where: PrivateUseDecoder.containsPrivateUse) }

private let alphaAndBullet = "BT /F1 12 Tf 72 700 Td (the exponent ) Tj /F2 12 Tf <0044> Tj /F1 12 Tf ( describes the profile shape.) Tj ET BT /F2 12 Tf 72 660 Td <0078> Tj /F1 12 Tf ( Peak bending moment due to lift) Tj ET"

@Test func wordSymbolFontAlphaAndBulletReadAsTheirCharacters() throws {
    // NASA page 4 and 13: SymbolMT by name, although its descriptor says Nonsymbolic.
    let texts = try lineTexts(document(content: alphaAndBullet, symbolFonts: [wordSymbol()]))
    #expect(texts.contains { $0.contains("the exponent α describes") }, "\(texts)")
    #expect(texts.contains { $0.hasPrefix("• Peak bending moment") }, "\(texts)")
    #expect(!hasPrivateUse(texts))
    // Supreme Court page 86: a subset tag, the Symbolic flag and family Symbol.
    let scotus = try lineTexts(document(content: alphaAndBullet, symbolFonts: [wordSymbol(name: "BDGFGH+SymbolMT", flags: 4, family: "Symbol")]))
    #expect(scotus.contains { $0.hasPrefix("• Peak") } && !hasPrivateUse(scotus))
    // The family alone names a subset font whose PostScript name does not.
    let family = try lineTexts(document(content: alphaAndBullet, symbolFonts: [wordSymbol(name: "ABCDEF+Font12", flags: 4, family: "Symbol")]))
    #expect(family.contains { $0.contains("α") } && !hasPrivateUse(family))
    // A Symbol font drawn inside a Form XObject.
    let form = try lineTexts(document(content: alphaAndBullet, symbolFonts: [wordSymbol()], form: true))
    #expect(form.contains { $0.contains("α") } && !hasPrivateUse(form), "\(form)")
}

@Test func privateUseCharactersWithoutFontEvidenceStay() throws {
    // Controls: the same map under another name, with or without the Symbolic flag, is not decoded;
    // neither is a name that only begins like Symbol's.
    for (name, flags) in [("SyntheticSans", 32), ("SyntheticSans", 4), ("SymbolicSans", 4)] {
        let texts = try lineTexts(document(content: alphaAndBullet, symbolFonts: [wordSymbol(name: name, flags: flags)]))
        #expect(texts.contains { $0.contains("\u{F061}") } && texts.contains { $0.contains("\u{F0B7}") }, "\(name) \(texts)")
    }
    // A Symbol font and a Wingdings font both yielding U+F0A7 (club, small square): the page cannot say
    // which drew it, so neither decodes; each alone does.
    let club = wordSymbol().map { $0.replacingOccurrences(of: "<0078> <F0B7>", with: "<0078> <F0A7>") }
    let wingdings = [
        "<< /Type /Font /Subtype /TrueType /BaseFont /Wingdings-Regular /FirstChar 32 /LastChar 255 /Encoding /WinAnsiEncoding /ToUnicode PLACEHOLDER_CID 0 R >>",
        cmap("<00> <FF>", "2 beginbfchar <A7> <F0A7> <D8> <F0D8> endbfchar"),
    ]
    let content = "BT /F2 12 Tf 72 700 Td <0078> Tj /F1 12 Tf ( club) Tj ET BT /F3 12 Tf 72 660 Td <A7D8> Tj /F1 12 Tf ( square and arrowhead) Tj ET"
    let both = try lineTexts(document(content: content, symbolFonts: [club, wingdings]))
    #expect(both.contains { $0.contains("\u{F0A7}") } && both.contains { $0.contains("\u{F0D8}") == false && $0.contains("➢") }, "\(both)")
    let alone = try lineTexts(document(content: "BT /F2 12 Tf 72 660 Td <A7D8> Tj /F1 12 Tf ( square and arrowhead) Tj ET", symbolFonts: [wingdings]))
    #expect(alone.contains { $0.hasPrefix("▪➢ square") }, "\(alone)")
    let symbolAlone = try lineTexts(document(content: "BT /F2 12 Tf 72 700 Td <0078> Tj /F1 12 Tf ( club) Tj ET", symbolFonts: [club]))
    #expect(symbolAlone.contains { $0.hasPrefix("♣ club") }, "\(symbolAlone)")
    // A Wingdings pictograph outside the bullet table stays.
    let pictograph = [wingdings[0], cmap("<00> <FF>", "1 beginbfchar <41> <F041> endbfchar")]
    let texts = try lineTexts(document(content: "BT /F2 12 Tf 72 660 Td <41> Tj /F1 12 Tf ( victory hand) Tj ET", symbolFonts: [pictograph]))
    #expect(texts.contains { $0.contains("\u{F041}") }, "\(texts)")
}

/// The page's decodable characters, read straight from its font resources. PDFKit extracts no text for a
/// non-embedded Type 1 font it cannot find (`CMEX10`), so these fonts are checked through the decoder.
private func pageCharacters(_ symbolFonts: [[String]]) throws -> [UInt32: String] {
    let page = try #require(document(content: "BT /F2 12 Tf 72 700 Td (012) Tj ET", symbolFonts: symbolFonts).page(at: 0)?.pageRef)
    return PrivateUseDecoder.characters(on: page)
}

@Test func glyphNamesTheFontStatesDecodeAdobesPrivateUsePieces() throws {
    // Wallace page 312's CMEX10: Differences names and a ToUnicode map to Adobe's private-use pieces.
    func mapped(_ names: String) -> [String] {
        ["<< /Type /Font /Subtype /Type1 /BaseFont /RRTZXD+CMEX10 /FirstChar 48 /LastChar 50 /Widths [875 875 667] /Encoding << /Type /Encoding /BaseEncoding /WinAnsiEncoding /Differences [48 \(names)] >> /ToUnicode PLACEHOLDER_CID 0 R >>",
         cmap("<00><ff>", "3 beginbfrange <30><30><f8eb> <31><31><f8f6> <32><32><f8f0> endbfrange")]
    }
    #expect(try pageCharacters([mapped("/parenlefttp /parenrighttp /uni23A3")]) == [0xF8EB: "⎛", 0xF8F6: "⎞", 0xF8F0: "⎣"])
    // Control: index names give no character, and a non-Symbol font's map is not read as Symbol's.
    #expect(try pageCharacters([mapped("/g48 /g49 /g50")]).isEmpty)
    // The DASC paper's CMEX10 (#163): no map and no Differences; its embedded Type 1 program's built-in
    // encoding names the pieces PDFKit reports as private use (clear text as in the source, object 109).
    let program = """
        %!PS-AdobeFont-1.0: CMEX10 003.002
        11 dict begin
        /FontType 1 def
        /FontName /EYRYPR+CMEX10 def
        /Encoding 256 array
        0 1 255 {1 index exch /.notdef put} for
        dup 62 /braceex put
        dup 59 /bracerightbt put
        dup 16 /parenleftBig put
        dup 48 /parenlefttp put
        readonly def
        currentdict end
        currentfile eexec
        """
    #expect(PrivateUseDecoder.builtInEncodingNames(program) == ["braceex", "bracerightbt", "parenleftBig", "parenlefttp"])
    func builtIn(charSet: String?) -> [String] {
        let set = charSet.map { " /CharSet (\($0))" } ?? ""
        return ["<< /Type /Font /Subtype /Type1 /BaseFont /EYRYPR+CMEX10 /FirstChar 0 /LastChar 105 /FontDescriptor PLACEHOLDER_CID 0 R >>",
                "<< /Type /FontDescriptor /FontName /EYRYPR+CMEX10 /Flags 4\(set) /FontBBox [-24 -2960 1454 772] /ItalicAngle 0 /Ascent 40 /Descent -600 /CapHeight 0 /StemV 47 /FontFile PLACEHOLDER_DESCRIPTOR 0 R >>",
                testPDFStream(program, extra: "/Length1 \(program.utf8.count) /Length2 0 /Length3 0")]
    }
    #expect(try pageCharacters([builtIn(charSet: nil)]) == [0xF8F4: "⎪", 0xF8FE: "⎭", 0xF8EB: "⎛"])
    // The descriptor's CharSet alone, without a program.
    var listed = builtIn(charSet: "/bracketlefttp/bracketleftex/parenleftbig")
    listed[1] = listed[1].replacingOccurrences(of: " /FontFile PLACEHOLDER_DESCRIPTOR 0 R", with: "")
    #expect(try pageCharacters([listed]) == [0xF8EE: "⎡", 0xF8EF: "⎢"])
    // A built-in Symbol Type 1 font without a map: every Adobe piece (PDFKit reports `bracerighttp` as U+F8FC).
    let symbol = try pageCharacters([["<< /Type /Font /Subtype /Type1 /BaseFont /Symbol >>"]])
    #expect(symbol[0xF8FC] == "⎫" && symbol[0xF6DA] == "®" && symbol.count == PrivateUseDecoder.adobePrivateUse.count)
    // Controls: a Type 1 font whose program and CharSet name no piece claims nothing.
    let plain = builtIn(charSet: "/A/B").map { $0.replacingOccurrences(of: "/braceex", with: "/A").replacingOccurrences(of: "/bracerightbt", with: "/B")
        .replacingOccurrences(of: "/parenlefttp", with: "/C") }
    #expect(try pageCharacters([plain]).isEmpty)
}

@Test func symbolEncodingTablesAndFamilies() {
    #expect(PrivateUseDecoder.symbolEncoding.count == 188)
    #expect(PrivateUseDecoder.character(0xF061, family: .symbol) == "α")
    #expect(PrivateUseDecoder.character(0xF0B7, family: .symbol) == "•")
    #expect(PrivateUseDecoder.character(0xF057, family: .symbol) == "Ω")
    #expect(PrivateUseDecoder.character(0xF0E6, family: .symbol) == "⎛")
    #expect(PrivateUseDecoder.character(0xF8FC, family: .symbol) == "⎫")
    #expect(PrivateUseDecoder.character(0xF060, family: .symbol) == nil)
    #expect(PrivateUseDecoder.character(0xF0B7, family: .other) == nil)
    #expect(PrivateUseDecoder.character(0xF0A7, family: .wingdings) == "▪")
    #expect(PrivateUseDecoder.character(glyphName: "bullet") == "•")
    #expect(PrivateUseDecoder.character(glyphName: "uniF0B7") == nil)
    #expect(PrivateUseDecoder.character(glyphName: "G12") == nil)
    for name in ["Symbol", "SymbolMT", "BDGFGH+SymbolMT", "Symbol,Bold"] { #expect(PrivateUseDecoder.family(named: name) == .symbol, "\(name)") }
    for name in ["Wingdings-Regular", "Wingdings2", "ABCDEF+Wingdings"] { #expect(PrivateUseDecoder.family(named: name) == .wingdings, "\(name)") }
    for name in ["SymbolicSans", "CMSY10", "ZapfDingbats", "TimesNewRomanPSMT"] { #expect(PrivateUseDecoder.family(named: name) == .other, "\(name)") }
    // Decoding keeps attribute ranges: every replacement is one UTF-16 unit.
    let key = NSAttributedString.Key("mark")
    let attributed = NSMutableAttributedString(string: "a \u{F061} b")
    attributed.addAttribute(key, value: true, range: NSRange(location: 2, length: 1))
    let decoded = PrivateUseDecoder.decode(attributed, [0xF061: "α"])
    #expect(decoded.string == "a α b")
    var range = NSRange()
    #expect(decoded.attribute(key, at: 2, effectiveRange: &range) != nil && range == NSRange(location: 2, length: 1))
}
