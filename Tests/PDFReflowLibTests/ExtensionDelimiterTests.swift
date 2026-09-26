import CoreGraphics
import CoreText
import Foundation
import PDFKit
import Testing
import ZIPFoundation
@testable import PDFReflowLib

// TeX's sized delimiters, which no map states and PDFKit reads as nothing (#305).

// MARK: - Glyph names

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/305"))
func sizedDelimiterNamesStateTheirCharacterAndNoOtherExtensionGlyphDoes() {
    func read(_ name: String) -> String? { ExtensionDelimiterReader.glyph(named: name)?.character }
    // CMEX10 draws a delimiter in four sizes, each named for its shape and size.
    #expect(read("parenleftbig") == "(" && read("parenrightBig") == ")")
    #expect(read("bracketleftbigg") == "[" && read("bracketrightBigg") == "]")
    #expect(read("braceleftbig") == "{" && read("bracerightBigg") == "}")
    #expect(read("floorleftBig") == "\u{230A}" && read("ceilingrightbigg") == "\u{2309}")
    #expect(read("angbracketleftbig") == "\u{27E8}" && read("angbracketrightBig") == "\u{27E9}")
    #expect(read("slashbigg") == "/" && read("backslashBig") == "\\")
    #expect(ExtensionDelimiterReader.glyph(named: "parenleftbig")?.side == .opening)
    #expect(ExtensionDelimiterReader.glyph(named: "parenrightbigg")?.side == .closing)
    #expect(ExtensionDelimiterReader.glyph(named: "slashbig")?.side == .neither)
    // Each size reaches its own depth below the origin (CMEX10: 1.16, 1.76, 2.36 and 2.96 em).
    #expect(["parenleftbig", "parenleftBig", "parenleftbigg", "parenleftBigg"]
        .compactMap { ExtensionDelimiterReader.glyph(named: $0)?.depth } == [1.16, 1.76, 2.36, 2.96])
    // Negative controls: extensible pieces, radicals, big operators, the text font's own
    // parenthesis and a bare size are not sized delimiters.
    for name in ["parenlefttp", "parenleftex", "parenrightbt", "bracelefttp", "braceex", "vextendsingle",
                 "radicalbig", "radicalBigg", "summationtext", "uniontext", "parenleft", "bracketright",
                 "big", "Bigg", "a", ""] {
        #expect(ExtensionDelimiterReader.glyph(named: name) == nil, "\(name)")
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/305"))
func aType1ProgramsBuiltInEncodingNamesItsCodes() {
    // The arXiv paper's txexs names its two codes only in its program's clear text.
    let program = """
    %!PS-AdobeFont-1.0: txexs 3.0
    /FontName /UMEVBP+txexs def
    /Encoding 256 array
    0 1 255 {1 index exch /.notdef put} for
    dup 16 /parenleftBig put
    dup 17 /parenrightBig put
    readonly def
    currentdict end
    currentfile eexec
    """
    #expect(ExtensionDelimiterReader.builtInEncoding(program) == [16: "parenleftBig", 17: "parenrightBig"])
    #expect(ExtensionDelimiterReader.builtInEncoding("/Encoding StandardEncoding def\ncurrentfile eexec").isEmpty)
    #expect(ExtensionDelimiterReader.builtInEncoding("/FontName /X def").isEmpty)
}

// MARK: - A page drawing Wallace page 178's (a²)³

/// Type 1 charstring number encoding (Adobe Type 1 Font Format, 6.2).
private func charstringNumber(_ value: Int) -> [UInt8] {
    switch value {
    case -107...107: return [UInt8(value + 139)]
    case 108...1131: let w = value - 108; return [UInt8(247 + w / 256), UInt8(w % 256)]
    case -1131 ... -108: let w = -value - 108; return [UInt8(251 + w / 256), UInt8(w % 256)]
    default:
        let u = UInt32(bitPattern: Int32(value))
        return [255, UInt8(u >> 24 & 0xFF), UInt8(u >> 16 & 0xFF), UInt8(u >> 8 & 0xFF), UInt8(u & 0xFF)]
    }
}

/// Type 1 encryption: `eexec` (55665) and charstring (4330) keys.
private func type1Encrypt(_ plain: [UInt8], key: UInt16) -> [UInt8] {
    var r = key
    return plain.map { byte in
        let cipher = byte ^ UInt8(r >> 8)
        r = (UInt16(cipher) &+ r) &* 52845 &+ 22719
        return cipher
    }
}

/// A complete Type 1 font program whose built-in encoding names `glyphs`, each drawn as a bar that
/// hangs from its origin as a TeX extension delimiter does: the only place the font names them.
private func type1Program(_ name: String, glyphs: [(code: Int, name: String, width: Int)]) -> (data: Data, clear: Int, binary: Int) {
    var clear = """
    %!PS-AdobeFont-1.0: \(name) 001.000
    12 dict begin
    /FontInfo 2 dict dup begin /FullName (\(name)) readonly def /FamilyName (\(name)) readonly def end readonly def
    /FontName /\(name) def
    /PaintType 0 def
    /FontType 1 def
    /FontMatrix [0.001 0 0 0.001 0 0] readonly def
    /FontBBox {0 -1160 600 40} readonly def
    /Encoding 256 array
    0 1 255 {1 index exch /.notdef put} for

    """
    for glyph in glyphs { clear += "dup \(glyph.code) /\(glyph.name) put\n" }
    clear += "readonly def\ncurrentdict end\ncurrentfile eexec\n"
    var secret = Array("""
    dup /Private 8 dict dup begin
    /RD {string currentfile exch readstring pop} executeonly def
    /ND {noaccess def} executeonly def
    /NP {noaccess put} executeonly def
    /BlueValues [] ND
    /MinFeature {16 16} ND
    /password 5839 def
    /Subrs 0 array ND
    2 index /CharStrings \(glyphs.count + 1) dict dup begin

    """.utf8)
    func add(_ glyph: String, _ program: [UInt8]) {
        let encrypted = type1Encrypt([0, 0, 0, 0] + program, key: 4330)
        secret += Array("/\(glyph) \(encrypted.count) RD ".utf8) + encrypted + Array(" ND\n".utf8)
    }
    let n = charstringNumber
    add(".notdef", n(0) + n(0) + [13, 14])
    for glyph in glyphs {
        // hsbw, then a bar from 1.16 em below the origin to 0.04 em above it, closepath endchar.
        add(glyph.name, n(0) + n(glyph.width) + [13] + n(100) + n(-1160) + [21] + n(60) + n(0) + [5]
            + n(0) + n(1200) + [5] + n(-60) + n(0) + [5] + [9, 14])
    }
    secret += Array("end\nend\nreadonly put\nnoaccess put\ndup /FontName get exch definefont pop\nmark currentfile closefile\n".utf8)
    let binary = type1Encrypt([0x41, 0x42, 0x43, 0x44] + secret, key: 55665)
    var data = Data(clear.utf8)
    data.append(contentsOf: binary)
    data.append(Data((String(repeating: String(repeating: "0", count: 64) + "\n", count: 8) + "cleartomark\n").utf8))
    return (data, clear.utf8.count, binary.count)
}

/// How the page's extension font states its two delimiter codes.
private enum ExtensionFont {
    /// CMEX10 as Wallace's Ghostscript output embeds it: a `Differences` array naming each code,
    /// and no `ToUnicode` entry for it.
    case differences
    /// An embedded Type 1 program names the codes in its own built-in encoding, as the arXiv
    /// paper's txexs does; the font dictionary has no `/Encoding` and no `ToUnicode`.
    case builtIn
    /// Negative control: a `ToUnicode` map that states the parentheses correctly.
    case mapped
    /// Negative control: a Symbol font whose codes name a bracket's extensible pieces.
    case symbolPieces
    /// Negative control: a TeX extension font whose codes name a radical and a piece.
    case radicalAndPiece
}

/// Wallace page 178, Example 202, as its source places it (#305): the tall parentheses hang from
/// origins 9.48 points above the baseline, the ² is raised 4.32 and the ³, set over the closing
/// parenthesis, 7.44. The text is Helvetica with stated widths, so the page's shows are measured.
private func powerOfAPowerPage(_ font: ExtensionFont) -> Data {
    var builder = PDFBytes()
    let widths = (32...126).map { $0 == 32 ? "278" : "556" }.joined(separator: " ")
    let text = builder.add("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding /FirstChar 32 /LastChar 126 /Widths [\(widths)] >>")
    let named = "/Encoding << /Type /Encoding /Differences [0 /parenleftbig /parenrightbig] >>"
    func embedded(_ extra: String) -> String {
        let program = type1Program("PRFXEX", glyphs: [(0, "parenleftbig", 458), (1, "parenrightbig", 458)])
        // `PDFBytes` writes through Latin-1, which carries the program's binary part byte for byte.
        let file = builder.addStream(String(data: program.data, encoding: .isoLatin1)!,
            extra: " /Length1 \(program.clear) /Length2 \(program.binary) /Length3 \(program.data.count - program.clear - program.binary)")
        let descriptor = builder.add("<< /Type /FontDescriptor /FontName /PRFXEX /Flags 4 /FontBBox [0 -1160 600 40] /ItalicAngle 0 /Ascent 40 /Descent -1160 /CapHeight 40 /StemV 50 /CharSet (/parenleftbig/parenrightbig) /FontFile \(file) >>")
        return builder.add("<< /Type /Font /Subtype /Type1 /BaseFont /PRFXEX /FirstChar 0 /LastChar 1 /Widths [458 458] /FontDescriptor \(descriptor)\(extra) >>")
    }
    let extensionFont: String
    switch font {
    case .differences:
        extensionFont = builder.add("<< /Type /Font /Subtype /Type1 /BaseFont /CMEX10 /FirstChar 0 /LastChar 1 /Widths [458 458] \(named) >>")
    case .builtIn:
        extensionFont = embedded("")
    case .mapped:
        // The program embedded, so PDFKit has the glyphs to read through the map: without them it
        // reads nothing at these codes whatever the map says.
        let map = builder.addStream("/CIDInit /ProcSet findresource begin\n12 dict begin\nbegincmap\n1 begincodespacerange\n<00> <FF>\nendcodespacerange\n2 beginbfchar\n<00> <0028>\n<01> <0029>\nendbfchar\nendcmap\nCMapName currentdict /CMap defineresource pop\nend\nend")
        extensionFont = embedded(" /ToUnicode \(map)")
    case .symbolPieces:
        extensionFont = builder.add("<< /Type /Font /Subtype /Type1 /BaseFont /Symbol /FirstChar 0 /LastChar 1 /Widths [384 384] /Encoding << /Type /Encoding /Differences [0 /parenlefttp /parenrightbt] >> >>")
    case .radicalAndPiece:
        extensionFont = builder.add("<< /Type /Font /Subtype /Type1 /BaseFont /CMEX10 /FirstChar 0 /LastChar 1 /Widths [458 458] /Encoding << /Type /Encoding /Differences [0 /radicalbig /parenlefttp] >> >>")
    }
    let contents = builder.addStream("""
    BT /F1 12 Tf 40 720 Td (Example 202.) Tj ET
    BT /X 11.9552 Tf 60 689.48 Td (\\000) Tj ET
    BT /F1 11.9552 Tf 65.48 680 Td (a) Tj ET
    BT /F1 7.97 Tf 72.2 684.32 Td (2) Tj ET
    BT /X 11.9552 Tf 77.5 689.48 Td (\\001) Tj ET
    BT /F1 7.97 Tf 82.66 687.44 Td (3) Tj ET
    BT /F1 11.9552 Tf 110 680 Td (This means we have a) Tj ET
    BT /F1 7.97 Tf 227 684.32 Td (2) Tj ET
    BT /F1 11.9552 Tf 234 680 Td (three times) Tj ET
    """)
    let parent = builder.reserve()
    let page = builder.add("<< /Type /Page /Parent \(parent) /MediaBox [0 0 400 760] /Resources << /Font << /F1 \(text) /X \(extensionFont) >> >> /Contents \(contents) >>")
    builder.fill(parent, "<< /Type /Pages /Kids [\(page)] /Count 1 >>")
    let catalog = builder.add("<< /Type /Catalog /Pages \(parent) >>")
    return builder.data(root: catalog)
}

private func delimiters(_ font: ExtensionFont) throws -> [ExtensionDelimiterReader.Delimiter] {
    let data = powerOfAPowerPage(font)
    let document = try #require(CGDataProvider(data: data as CFData).flatMap(CGPDFDocument.init))
    return ExtensionDelimiterReader.read(try #require(document.page(at: 1)))
}

/// The page converted, as the chapter's HTML.
private func converted(_ font: ExtensionFont) async throws -> String {
    let dir = try testPDFDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let pdf = dir.appendingPathComponent("source.pdf"), epub = dir.appendingPathComponent("book.epub")
    try powerOfAPowerPage(font).write(to: pdf)
    _ = try await PDFConverter().convert(from: pdf, to: epub)
    return try Archive(url: epub, accessMode: .read).chapter()
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/305"))
func tallParenthesesNamedOnlyByTheirFontAreRead() throws {
    for font in [ExtensionFont.differences, .builtIn] {
        let found = try delimiters(font)
        #expect(found.map(\.character) == ["(", ")"], "\(font)")
        #expect(found.map(\.side) == [.opening, .closing], "\(font)")
        #expect(found.allSatisfy { $0.alone }, "\(font)")
        // Placed where the page draws them: the advance from the show's origin, the size in page
        // space, and the depth of TeX's `big` size below the origin.
        #expect(zip(found.map(\.origin.x), [60, 77.5]).allSatisfy { abs($0 - $1) < 0.001 }, "\(font)")
        #expect(found.allSatisfy { abs($0.origin.y - 689.48) < 0.001 && abs($0.size - 11.9552) < 0.001 }, "\(font)")
        #expect(found.allSatisfy { abs($0.end - $0.origin.x - 0.458 * 11.9552) < 0.001 && $0.depth == 1.16 }, "\(font)")
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/305"))
func delimitersDrawnInOneShowArePlacedByTheirAdvances() throws {
    // Two delimiters in one show, two across an adjustment, and one beside a radical, which is
    // no delimiter: that show's other glyph is unknown to the reader, so its delimiter is not alone.
    let data = testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /Resources << /Font << /X 5 0 R >> >> /Contents 4 0 R >>",
        testPDFStream(#"""
        BT /X 12 Tf 10 50 Td (\000\000) Tj ET
        BT /X 12 Tf 50 50 Td [(\001) -500 (\001)] TJ ET
        BT /X 12 Tf 2 Tc 90 50 Td (\000\002) Tj ET
        """#),
        "<< /Type /Font /Subtype /Type1 /BaseFont /CMEX10 /FirstChar 0 /LastChar 2 /Widths [458 458 1000] /Encoding << /Type /Encoding /Differences [0 /parenleftbig /parenrightbig /radicalbig] >> >>",
    ])
    let document = try #require(CGDataProvider(data: data as CFData).flatMap(CGPDFDocument.init))
    let found = ExtensionDelimiterReader.read(try #require(document.page(at: 1)))
    #expect(found.map(\.character) == ["(", "(", ")", ")", "("])
    let x = found.map(\.origin.x), expected: [CGFloat] = [10, 15.496, 50, 61.496, 90]
    #expect(zip(x, expected).allSatisfy { abs($0 - $1) < 0.001 }, "\(x)")
    #expect(found.map { $0.alone } == [true, true, true, true, false])
    #expect(found.map(\.show) == [CGPoint(x: 10, y: 50), CGPoint(x: 10, y: 50), CGPoint(x: 50, y: 50),
                                  CGPoint(x: 50, y: 50), CGPoint(x: 90, y: 50)])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/305"))
func aMapThatStatesTheParenthesesOrANonDelimiterFontLeavesThePageToPDFKit() throws {
    // Negative controls: a code the font's map states is PDFKit's to read, and names that are not
    // sized delimiters (a Symbol font's bracket pieces, a radical, a piece) are never read.
    for font in [ExtensionFont.mapped, .symbolPieces, .radicalAndPiece] {
        #expect(try delimiters(font).isEmpty, "\(font)")
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/305"))
func wallacePage178PowerOfAPowerKeepsItsTallParenthesesAndItsExponent() async throws {
    // The reproducer. Without the reader PDFKit reads `a2 3`, and the ³ reads as a second
    // exponent of a (`a<sup>2 3 </sup>`, #302), which cannot be told from a²³.
    for font in [ExtensionFont.differences, .builtIn] {
        let html = try await converted(font)
        #expect(html.contains("(a<sup>2</sup>)<sup>3"), "\(font): \(html)")
        #expect(!html.contains("a<sup>2 3"), "\(font)")
        // Nothing else on the page moves: the example's title keeps its own line, whose rectangle
        // PDFKit stretches over the opening parenthesis where the program is embedded, and the
        // running text's a² is untouched.
        #expect(html.contains("<p>Example 202.</p>"), "\(font)")
        #expect(html.contains("This means we have a<sup>2 </sup>three times"), "\(font)")
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/305"))
func pagesWhoseParenthesesPDFKitReadsOrWhoseFontsNameNoDelimiterAreUnaffected() async throws {
    // A correct map: PDFKit reads each parenthesis itself, once, and nothing is added beside it.
    let mapped = try #require(body(try await converted(.mapped)))
    #expect(mapped.contains("a<sup>2") && mapped.contains("This means we have a<sup>2 </sup>three times"))
    #expect(mapped.filter { $0 == "(" }.count == 1 && mapped.filter { $0 == ")" }.count == 1, "\(mapped)")
    // A Symbol font's pieces and a radical are not written as parentheses.
    for font in [ExtensionFont.symbolPieces, .radicalAndPiece] {
        let html = try #require(body(try await converted(font)))
        #expect(!html.contains("(") && !html.contains(")"), "\(font): \(html)")
        #expect(html.contains("This means we have a<sup>2 </sup>three times"), "\(font)")
    }
}

/// A chapter's body, without the document head.
private func body(_ html: String) -> String? {
    html.range(of: "<body").map { String(html[$0.lowerBound...]) }
}

// MARK: - Placement

private func show(_ text: String?, x: CGFloat, end: CGFloat, y: CGFloat, size: CGFloat) -> NativeSpacingReader.Evidence {
    NativeSpacingReader.Evidence(origin: CGPoint(x: x, y: y), unicode: text, end: end, size: size)
}

private func delimiter(_ character: String, _ side: ExtensionDelimiterReader.Side, x: CGFloat, y: CGFloat,
                       size: CGFloat = 12, depth: CGFloat = 1.16) -> ExtensionDelimiterReader.Delimiter {
    ExtensionDelimiterReader.Delimiter(character: character, side: side, origin: CGPoint(x: x, y: y),
                                       end: x + 0.458 * size, size: size, depth: depth,
                                       show: CGPoint(x: x, y: y), alone: true)
}

/// Each line's text once the delimiters are placed, from PDFKit's reading of it and the page's
/// shows, among which each delimiter's own show reads as no text, as the spacing reader has it.
private func placed(_ delimiters: [ExtensionDelimiterReader.Delimiter], shows: [NativeSpacingReader.Evidence],
                    lines: [(String, CGRect)]) -> [String] {
    let all = shows + delimiters.map { show(nil, x: $0.origin.x, end: $0.end, y: $0.origin.y, size: $0.size) }
    let placements = ExtensionDelimiterReader.placements(delimiters, shows: all, lines: lines.map(\.1),
                                                         texts: lines.map(\.0))
    let font = pdfKitGated { PlatformFont(name: "Helvetica", size: 12) }!
    return lines.indices.map { index in
        ExtensionDelimiterReader.apply(placements[index] ?? [], shows: all, delimiters: delimiters,
                                       to: NSAttributedString(string: lines[index].0, attributes: [.font: font]),
                                       bounds: lines[index].1).string
    }
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/305"))
func aDelimiterGoesWhereTheTextOfTheShowsAroundItPlacesIt() {
    // `f(x) = y` with a `big` pair around x on a 100-point baseline: TeX centres the pair on the
    // axis, a quarter em up, so each hangs from 100 + 3 + 0.6 em - 0.04 em.
    let top: CGFloat = 100 + 3 + 12 * 0.6 - 12 * 0.04
    let shows = [show("f", x: 10, end: 16, y: 100, size: 12), show("x", x: 22, end: 28, y: 100, size: 12),
                 show("= y", x: 36, end: 60, y: 100, size: 12)]
    let pair = [delimiter("(", .opening, x: 16.2, y: top), delimiter(")", .closing, x: 28.2, y: top)]
    let line = CGRect(x: 10, y: 96, width: 50, height: 16)
    // PDFKit sets a space in each gap the unread parentheses leave. Nothing stands inside the
    // pair, and the space after `)` is where the page leaves a word gap before `=`.
    #expect(placed(pair, shows: shows, lines: [("f x = y", line)]) == ["f (x) = y"])
    // A rectangle a tall glyph stretched over the row holds the anchors' origins too, but its text
    // does not spell them: the pair goes into the one line whose text does.
    let stretched = CGRect(x: 0, y: 90, width: 70, height: 40)
    #expect(placed(pair, shows: shows, lines: [("Example 7.", stretched), ("f x = y", line)])
            == ["Example 7.", "f (x) = y"])
    // Two lines that would both take the pair: neither does.
    #expect(placed(pair, shows: shows, lines: [("f x = y", line), ("f x = y", stretched)])
            == ["f x = y", "f x = y"])
    // Nothing stands inside the pair even where the page leaves a word-sized gap there.
    let wide = [show("f", x: 10, end: 16, y: 100, size: 12), show("x", x: 24.5, end: 30.5, y: 100, size: 12),
                show("= y", x: 42, end: 66, y: 100, size: 12)]
    let widePair = [delimiter("(", .opening, x: 16.2, y: top), delimiter(")", .closing, x: 33, y: top)]
    #expect(placed(widePair, shows: wide, lines: [("f x = y", line)]) == ["f (x) = y"])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/305"))
func aTallParenthesisAroundAFractionEnclosesNoRowAndStaysOut() {
    // `(3/4)²` displayed: a `bigg` pair centred on the axis, the numerator and denominator in the
    // body size well above and below the baseline. The first glyph of the pair's size inside it is
    // off the row's baseline, so the pair encloses no row and is not written into a line.
    let top: CGFloat = 100 + 3 + 12 * 1.2 - 12 * 0.04
    let pair = [delimiter("(", .opening, x: 16, y: top, depth: 2.36), delimiter(")", .closing, x: 29, y: top, depth: 2.36)]
    let line = CGRect(x: 16, y: 88, width: 30, height: 30)
    let fraction = [show("3", x: 22, end: 28, y: 108.2, size: 12), show("4", x: 22, end: 28, y: 91.8, size: 12),
                    show("2", x: 35, end: 39, y: 110, size: 8)]
    #expect(placed(pair, shows: fraction, lines: [("3 2", line)]) == ["3 2"])
    // Control: the same pair around a glyph on the baseline encloses it.
    let row = [show("3", x: 22, end: 28, y: 100, size: 12), show("2", x: 35, end: 39, y: 110, size: 8)]
    #expect(placed(pair, shows: row, lines: [("3 2", line)]) == ["(3)2"])
}

// MARK: - A script set against a restored delimiter

/// Each tuple is one run as `inlineText` receives it: text, baseline offset, font size, and, for a
/// restored delimiter, its reach above and below the baseline.
private func runs(_ values: [(String, Double, Double, (Double, Double)?)]) -> String {
    let input = NSMutableAttributedString(string: "")
    for (text, offset, size, reach) in values {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: pdfKitGated { PlatformFont(name: "Helvetica", size: size) }!,
            NSAttributedString.Key(kCTBaselineOffsetAttributeName as String): offset,
        ]
        if let reach {
            attributes[ExtensionDelimiterReader.reachAttribute] =
                ExtensionDelimiterReader.Reach(above: reach.0, below: reach.1, size: size)
        }
        input.append(NSAttributedString(string: text, attributes: attributes))
    }
    return EPUBTextEncoder.inline(NativeTextReader.inlineText(from: input))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/305"))
func anExponentRaisedOverARestoredParenthesisIsItsSuperscript() {
    // Wallace page 178 as the reader hands it on: the `)` reaches 9.96 points above the baseline
    // and the ³ is raised 7.44 on 7.97 points, past three quarters of its own size.
    let big = (9.96, 4.46)
    #expect(runs([("(", 0, 11.96, big), ("a", 0, 11.96, nil), ("2", 4.32, 7.97, nil), (")", 0, 11.96, big),
                  ("3 ", 7.44, 7.97, nil), ("This means", 0, 11.96, nil)])
            == "(a<sup>2</sup>)<sup>3 </sup>This means")
    // A subscript lowered from a taller delimiter's foot, deeper than its own size admits.
    #expect(runs([("x", 0, 11.96, nil), (")", 0, 11.96, (14.3, 18.9)), ("i", -6.5, 7.97, nil)]) == "x)<sub>i</sub>")
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/305"))
func onlyASmallerRunWithinARestoredDelimitersReachIsItsScript() {
    // Negative controls. The same ³ after a parenthesis PDFKit read itself, which carries no reach,
    // is measured against its own size alone and stays on the line.
    #expect(runs([("a", 0, 11.96, nil), ("2", 4.32, 7.97, nil), (")", 0, 11.96, nil), ("3", 7.44, 7.97, nil)])
            == "a<sup>2</sup>)3")
    // Raised above the delimiter's top it is no script of it, and neither is a run of the
    // delimiter's own size, nor one a glyph on the baseline separates from it.
    #expect(runs([(")", 0, 11.96, (6, 4)), ("3", 7.44, 7.97, nil)]) == ")3")
    let reach = ExtensionDelimiterReader.Reach(above: 9.96, below: 4.46, size: 11.96)
    #expect(ExtensionDelimiterReader.script(after: reach, at: 0, offset: 7.44, size: 11.96, tolerance: 1.44).isEmpty)
    #expect(ExtensionDelimiterReader.script(after: reach, at: 0, offset: 0.4, size: 7.97, tolerance: 0.96).isEmpty)
    #expect(runs([(")", 0, 11.96, (9.96, 4.46)), (" + ", 0, 11.96, nil), ("3", 7.44, 7.97, nil)]) == ") + 3")
}
