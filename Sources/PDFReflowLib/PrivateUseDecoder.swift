import Foundation
import CoreGraphics

/// Characters for the private-use code points symbol fonts give PDFKit (#155).
///
/// A TrueType symbol font's Microsoft symbol `cmap` places its built-in code `xx` at U+F0xx, and Word
/// copies those values into the font's ToUnicode map: the NASA paper's `SymbolMT` maps its alpha to
/// U+F061 and its bullet to U+F0B7, the Supreme Court opinion's `BDGFGH+SymbolMT` its bullet to
/// U+F0B7. Adobe's glyph list also assigns the Symbol font's bracket, brace and arrow pieces and its
/// serif and sans trademark signs to private use (U+F8E6–U+F8FE, U+F6D9–U+F6DB). Wallace's `CMEX10` map
/// writes them for `parenlefttp` (U+F8EB), and PDFKit reports them itself for the glyphs a font names so
/// without a map: the DASC paper's built-in-encoded TeX `CMEX10` (`braceex` as U+F8F4, #163), or a
/// built-in `Symbol` Type1 font's `bracerighttp`. Readers draw nothing or a box for these.
///
/// The characters come from each font's own evidence, never from the code point alone:
/// - with a ToUnicode map, a glyph name the font's `Differences` array gives the mapped code
///   (`parenlefttp` → ⎛, `uni2022` → •); otherwise a Symbol font (`BaseFont`, descriptor `FontName` or
///   `FontFamily` naming Symbol) reads U+F0xx through its built-in Symbol encoding, and a Wingdings font
///   the list bullets Word inserts from it (`§` ▪, `Ø` ➢, `ü` ✔);
/// - without one, the glyph names the font states (its `Differences`, the built-in encoding of its
///   embedded Type 1 program, its descriptor's `CharSet`) that Adobe assigns to private use, and every
///   such piece of a Symbol font.
/// The descriptor's `Symbolic` flag is not evidence either way: Word writes `Nonsymbolic` for the NASA
/// paper's SymbolMT. A code point one font on the page maps without evidence, or two fonts decode
/// differently, stays as PDFKit reported it.
enum PrivateUseDecoder {
    static let maximumFonts = 256
    static let maximumFormDepth = 4

    static func isPrivateUse(_ scalar: Unicode.Scalar) -> Bool { (0xE000...0xF8FF).contains(scalar.value) }

    static func containsPrivateUse(_ text: String) -> Bool { text.unicodeScalars.contains(where: isPrivateUse) }

    /// The page's decodable private-use code points: those every font resource of the page (and of its
    /// nested Forms) that yields them decodes to the same character.
    static func characters(on page: CGPDFPage) -> [UInt32: String] {
        guard let dictionary = page.dictionary else { return [:] }
        var resources: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources else { return [:] }
        var claims: [UInt32: String?] = [:]
        var examined = 0
        collect(resources, depth: 0, examined: &examined, claims: &claims)
        return claims.compactMapValues { $0 }
    }

    private static func collect(_ resources: CGPDFDictionaryRef, depth: Int, examined: inout Int, claims: inout [UInt32: String?]) {
        var fonts: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(resources, "Font", &fonts), let fonts {
            var dictionaries: [CGPDFDictionaryRef] = []
            CGPDFDictionaryApplyBlock(fonts, { _, value, _ in
                guard examined + dictionaries.count < maximumFonts else { return false }
                var font: CGPDFDictionaryRef?
                if CGPDFObjectGetValue(value, .dictionary, &font), let font { dictionaries.append(font) }
                return true
            }, nil)
            examined += dictionaries.count
            for font in dictionaries {
                for (scalar, character) in fontCharacters(font) {
                    if let existing = claims[scalar] {
                        if existing != character { claims[scalar] = .some(nil) }
                    } else {
                        claims[scalar] = .some(character)
                    }
                }
            }
        }
        guard depth < maximumFormDepth, examined < maximumFonts else { return }
        var xobjects: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(resources, "XObject", &xobjects), let xobjects else { return }
        var nested: [CGPDFDictionaryRef] = []
        CGPDFDictionaryApplyBlock(xobjects, { _, value, _ in
            guard nested.count < maximumFonts else { return false }
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(value, .stream, &stream), let stream,
                  let dictionary = CGPDFStreamGetDictionary(stream), name(dictionary, "Subtype") == "Form" else { return true }
            var inner: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(dictionary, "Resources", &inner), let inner, inner != resources { nested.append(inner) }
            return true
        }, nil)
        for inner in nested where examined < maximumFonts {
            collect(inner, depth: depth + 1, examined: &examined, claims: &claims)
        }
    }

    /// Every private-use code point a font yields, with its character, or nil where the font gives no
    /// evidence for one.
    static func fontCharacters(_ font: CGPDFDictionaryRef) -> [UInt32: String?] {
        let subtype = name(font, "Subtype") ?? ""
        var result: [UInt32: String?] = [:]
        let family = fontFamily(font)
        var stream: CGPDFStreamRef?
        if CGPDFDictionaryGetStream(font, "ToUnicode", &stream), let stream {
            var format = CGPDFDataFormat.raw
            guard let data = CGPDFStreamCopyData(stream, &format).map({ $0 as Data }), format == .raw else { return [:] }
            var targets: [(glyphName: String?, scalar: UInt32)] = []
            if subtype == "Type0" {
                for (_, value) in FontWeightReader.wideUnicodeMap(data) ?? [:] {
                    if let scalar = privateUseScalar(value) { targets.append((nil, scalar)) }
                }
            } else {
                let names = differenceNames(font)
                for (code, value) in NativeSpacingReader.simpleFontUnicodeMap(data) ?? FontWeightReader.oneByteUnicodeMap(data) ?? [:] {
                    if let scalar = privateUseScalar(value) { targets.append((names[code], scalar)) }
                }
            }
            for (glyphName, scalar) in targets {
                let character = glyphName.flatMap(character(glyphName:)) ?? character(scalar, family: family)
                if let existing = result[scalar], existing != character { result[scalar] = .some(nil) } else { result[scalar] = character }
            }
        } else {
            // Without a map PDFKit reads the glyph names and reports Adobe's private-use values for the
            // pieces among them; a Symbol font's built-in encoding holds all of them.
            if family == .symbol {
                for (scalar, character) in adobePrivateUse { result[scalar] = character }
            }
            let names = Set(differenceNames(font).values).union(builtInEncodingNames(font)).union(charSetNames(font))
            for name in names {
                guard let value = symbolGlyphNames[name]?.unicodeScalars.first?.value,
                      let character = adobePrivateUse[value] else { continue }
                result[value] = character
            }
        }
        return result
    }

    /// The descriptor of a simple font, or of a composite font's descendant.
    private static func descriptor(_ font: CGPDFDictionaryRef) -> CGPDFDictionaryRef? {
        var owner = font
        var descendants: CGPDFArrayRef?, first: CGPDFDictionaryRef?
        if CGPDFDictionaryGetArray(font, "DescendantFonts", &descendants), let descendants,
           CGPDFArrayGetCount(descendants) >= 1, CGPDFArrayGetDictionary(descendants, 0, &first), let first {
            owner = first
        }
        var descriptor: CGPDFDictionaryRef?
        return CGPDFDictionaryGetDictionary(owner, "FontDescriptor", &descriptor) ? descriptor : nil
    }

    /// The glyph names an embedded Type 1 program's built-in encoding assigns (`dup 62 /braceex put`),
    /// read from the program's clear-text part.
    static func builtInEncodingNames(_ font: CGPDFDictionaryRef) -> Set<String> {
        var stream: CGPDFStreamRef?
        guard name(font, "Subtype") == "Type1" || name(font, "Subtype") == "MMType1", let descriptor = descriptor(font),
              CGPDFDictionaryGetStream(descriptor, "FontFile", &stream), let stream,
              let dictionary = CGPDFStreamGetDictionary(stream) else { return [] }
        var format = CGPDFDataFormat.raw
        guard let data = CGPDFStreamCopyData(stream, &format).map({ $0 as Data }), format == .raw else { return [] }
        var clearText: CGPDFInteger = 0
        let length = CGPDFDictionaryGetInteger(dictionary, "Length1", &clearText) && clearText > 0 ? clearText : data.count
        return builtInEncodingNames(String(decoding: data.prefix(min(length, 65_536)), as: UTF8.self))
    }

    static func builtInEncodingNames(_ program: String) -> Set<String> {
        guard let start = program.range(of: "/Encoding") else { return [] }
        let text = program[start.upperBound...]
        let end = text.range(of: "readonly def")?.lowerBound ?? text.range(of: "currentdict end")?.lowerBound ?? text.endIndex
        let entries = try! NSRegularExpression(pattern: #"dup\s+\d{1,3}\s*/([A-Za-z0-9._]{1,64})\s+put"#)
        let body = String(text[..<end])
        var result: Set<String> = []
        for match in entries.matches(in: body, range: NSRange(body.startIndex..., in: body)).prefix(256) {
            if let range = Range(match.range(at: 1), in: body) { result.insert(String(body[range])) }
        }
        return result
    }

    /// The glyph names a descriptor's `CharSet` string lists (`/braceex/bracerightbt`).
    private static func charSetNames(_ font: CGPDFDictionaryRef) -> Set<String> {
        var value: CGPDFStringRef?
        guard let descriptor = descriptor(font), CGPDFDictionaryGetString(descriptor, "CharSet", &value), let value,
              let text = CGPDFStringCopyTextString(value) as String?, text.utf16.count <= 65_536 else { return [] }
        return Set(text.split(separator: "/").map(String.init).filter { !$0.isEmpty && $0.count <= 64 })
    }

    enum Family: Equatable { case symbol, wingdings, other }

    /// Symbol or Wingdings, as the font's `BaseFont`, or its descriptor's `FontName` or `FontFamily`,
    /// names it (subset tags and PostScript suffixes aside: `BDGFGH+SymbolMT`, `Wingdings-Regular`).
    static func fontFamily(_ font: CGPDFDictionaryRef) -> Family {
        var names: [String] = []
        if let base = name(font, "BaseFont") { names.append(base) }
        if let descriptor = descriptor(font) {
            if let fontName = name(descriptor, "FontName") { names.append(fontName) }
            var family: CGPDFStringRef?
            if CGPDFDictionaryGetString(descriptor, "FontFamily", &family), let family,
               let text = CGPDFStringCopyTextString(family) as String? { names.append(text) }
        }
        return names.lazy.map(family(named:)).first { $0 != .other } ?? .other
    }

    static func family(named name: String) -> Family {
        let stripped = FontWeightReader.strippedName(name).lowercased()
        let root = String(stripped.prefix { $0.isLetter })
        if ["symbol", "symbolmt"].contains(root) { return .symbol }
        if root.hasPrefix("wingdings") { return .wingdings }
        return .other
    }

    /// The character of a private-use code point in a font of `family`.
    static func character(_ scalar: UInt32, family: Family) -> String? {
        switch family {
        case .symbol:
            if (0xF020...0xF0FF).contains(scalar), let character = symbolEncoding[UInt8(scalar - 0xF000)] {
                return adobePrivateUse[character.unicodeScalars.first!.value] ?? character
            }
            return adobePrivateUse[scalar]
        case .wingdings:
            return (0xF020...0xF0FF).contains(scalar) ? wingdingsBullets[UInt8(scalar - 0xF000)] : nil
        case .other:
            return nil
        }
    }

    /// A glyph name's character, outside the private-use area: `uniXXXX`, `uXXXX`, the Symbol
    /// encoding's names and the names `NativeSpacingReader.differenceGlyphs` knows.
    static func character(glyphName: String) -> String? {
        var candidate: String?
        if let known = symbolGlyphNames[glyphName] ?? NativeSpacingReader.differenceGlyphs[glyphName] {
            candidate = known
        } else if glyphName.hasPrefix("uni"), glyphName.count == 7, let value = UInt32(glyphName.dropFirst(3), radix: 16) {
            candidate = UnicodeScalar(value).map { String($0) }
        } else if glyphName.hasPrefix("u"), (5...7).contains(glyphName.count), let value = UInt32(glyphName.dropFirst(), radix: 16) {
            candidate = UnicodeScalar(value).map { String($0) }
        }
        guard let candidate, let scalar = candidate.unicodeScalars.first else { return nil }
        if let piece = adobePrivateUse[scalar.value] { return piece }
        return candidate.unicodeScalars.contains(where: { isPrivateUse($0) || $0.value < 0x20 }) ? nil : candidate
    }

    /// Replaces the decodable private-use characters of a PDFKit line; every replacement is one UTF-16
    /// unit, so attribute ranges are unchanged.
    static func decode(_ text: String, _ characters: [UInt32: String]) -> String {
        guard !characters.isEmpty, containsPrivateUse(text) else { return text }
        var result = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if isPrivateUse(scalar), let character = characters[scalar.value], character.utf16.count == 1 {
                result.append(contentsOf: character.unicodeScalars)
            } else {
                result.append(scalar)
            }
        }
        return String(result)
    }

    static func decode(_ attributed: NSAttributedString, _ characters: [UInt32: String]) -> NSAttributedString {
        guard !characters.isEmpty, containsPrivateUse(attributed.string) else { return attributed }
        let result = NSMutableAttributedString(attributedString: attributed)
        let string = attributed.string as NSString
        for index in 0..<string.length {
            let unit = UInt32(string.character(at: index))
            guard (0xE000...0xF8FF).contains(unit), let character = characters[unit], character.utf16.count == 1 else { continue }
            result.replaceCharacters(in: NSRange(location: index, length: 1), with: character)
        }
        return result
    }

    private static func privateUseScalar(_ value: String) -> UInt32? {
        let scalars = value.unicodeScalars
        guard scalars.count == 1, let scalar = scalars.first, isPrivateUse(scalar) else { return nil }
        return scalar.value
    }

    private static func differenceNames(_ font: CGPDFDictionaryRef) -> [UInt8: String] {
        var encoding: CGPDFDictionaryRef?, differences: CGPDFArrayRef?
        guard CGPDFDictionaryGetDictionary(font, "Encoding", &encoding), let encoding,
              CGPDFDictionaryGetArray(encoding, "Differences", &differences), let differences,
              CGPDFArrayGetCount(differences) <= 512 else { return [:] }
        var result: [UInt8: String] = [:], next: Int?
        for position in 0..<CGPDFArrayGetCount(differences) {
            var code: CGPDFInteger = 0, glyph: UnsafePointer<CChar>?
            if CGPDFArrayGetInteger(differences, position, &code) {
                next = (0...255).contains(code) ? code : nil
            } else if CGPDFArrayGetName(differences, position, &glyph), let glyph, let code = next, code <= 255 {
                result[UInt8(code)] = String(cString: glyph)
                next = code + 1
            } else { return [:] }
        }
        return result
    }

    private static func name(_ dict: CGPDFDictionaryRef, _ key: String) -> String? {
        var value: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(dict, key, &value), let value else { return nil }
        return String(cString: value)
    }

    // MARK: - Tables

    /// Adobe's Symbol encoding (`symbol.txt`), code to glyph name and character. Greek capitals take
    /// their Greek letters (not U+2206 increment or U+2126 ohm); the pieces Adobe assigns to private
    /// use appear here by their private-use value and read through `adobePrivateUse`.
    static let symbolTable: [(code: UInt8, name: String, character: String)] = [
        (0x20, "space", " "), (0x21, "exclam", "!"), (0x22, "universal", "\u{2200}"), (0x23, "numbersign", "#"),
        (0x24, "existential", "\u{2203}"), (0x25, "percent", "%"), (0x26, "ampersand", "&"), (0x27, "suchthat", "\u{220B}"),
        (0x28, "parenleft", "("), (0x29, "parenright", ")"), (0x2A, "asteriskmath", "\u{2217}"), (0x2B, "plus", "+"),
        (0x2C, "comma", ","), (0x2D, "minus", "\u{2212}"), (0x2E, "period", "."), (0x2F, "slash", "/"),
        (0x30, "zero", "0"), (0x31, "one", "1"), (0x32, "two", "2"), (0x33, "three", "3"), (0x34, "four", "4"),
        (0x35, "five", "5"), (0x36, "six", "6"), (0x37, "seven", "7"), (0x38, "eight", "8"), (0x39, "nine", "9"),
        (0x3A, "colon", ":"), (0x3B, "semicolon", ";"), (0x3C, "less", "<"), (0x3D, "equal", "="), (0x3E, "greater", ">"),
        (0x3F, "question", "?"), (0x40, "congruent", "\u{2245}"),
        (0x41, "Alpha", "\u{0391}"), (0x42, "Beta", "\u{0392}"), (0x43, "Chi", "\u{03A7}"), (0x44, "Delta", "\u{0394}"),
        (0x45, "Epsilon", "\u{0395}"), (0x46, "Phi", "\u{03A6}"), (0x47, "Gamma", "\u{0393}"), (0x48, "Eta", "\u{0397}"),
        (0x49, "Iota", "\u{0399}"), (0x4A, "theta1", "\u{03D1}"), (0x4B, "Kappa", "\u{039A}"), (0x4C, "Lambda", "\u{039B}"),
        (0x4D, "Mu", "\u{039C}"), (0x4E, "Nu", "\u{039D}"), (0x4F, "Omicron", "\u{039F}"), (0x50, "Pi", "\u{03A0}"),
        (0x51, "Theta", "\u{0398}"), (0x52, "Rho", "\u{03A1}"), (0x53, "Sigma", "\u{03A3}"), (0x54, "Tau", "\u{03A4}"),
        (0x55, "Upsilon", "\u{03A5}"), (0x56, "sigma1", "\u{03C2}"), (0x57, "Omega", "\u{03A9}"), (0x58, "Xi", "\u{039E}"),
        (0x59, "Psi", "\u{03A8}"), (0x5A, "Zeta", "\u{0396}"), (0x5B, "bracketleft", "["), (0x5C, "therefore", "\u{2234}"),
        (0x5D, "bracketright", "]"), (0x5E, "perpendicular", "\u{22A5}"), (0x5F, "underscore", "_"),
        (0x61, "alpha", "\u{03B1}"), (0x62, "beta", "\u{03B2}"), (0x63, "chi", "\u{03C7}"), (0x64, "delta", "\u{03B4}"),
        (0x65, "epsilon", "\u{03B5}"), (0x66, "phi", "\u{03C6}"), (0x67, "gamma", "\u{03B3}"), (0x68, "eta", "\u{03B7}"),
        (0x69, "iota", "\u{03B9}"), (0x6A, "phi1", "\u{03D5}"), (0x6B, "kappa", "\u{03BA}"), (0x6C, "lambda", "\u{03BB}"),
        (0x6D, "mu", "\u{03BC}"), (0x6E, "nu", "\u{03BD}"), (0x6F, "omicron", "\u{03BF}"), (0x70, "pi", "\u{03C0}"),
        (0x71, "theta", "\u{03B8}"), (0x72, "rho", "\u{03C1}"), (0x73, "sigma", "\u{03C3}"), (0x74, "tau", "\u{03C4}"),
        (0x75, "upsilon", "\u{03C5}"), (0x76, "omega1", "\u{03D6}"), (0x77, "omega", "\u{03C9}"), (0x78, "xi", "\u{03BE}"),
        (0x79, "psi", "\u{03C8}"), (0x7A, "zeta", "\u{03B6}"), (0x7B, "braceleft", "{"), (0x7C, "bar", "|"),
        (0x7D, "braceright", "}"), (0x7E, "similar", "\u{223C}"),
        (0xA0, "Euro", "\u{20AC}"), (0xA1, "Upsilon1", "\u{03D2}"), (0xA2, "minute", "\u{2032}"), (0xA3, "lessequal", "\u{2264}"),
        (0xA4, "fraction", "\u{2044}"), (0xA5, "infinity", "\u{221E}"), (0xA6, "florin", "\u{0192}"), (0xA7, "club", "\u{2663}"),
        (0xA8, "diamond", "\u{2666}"), (0xA9, "heart", "\u{2665}"), (0xAA, "spade", "\u{2660}"), (0xAB, "arrowboth", "\u{2194}"),
        (0xAC, "arrowleft", "\u{2190}"), (0xAD, "arrowup", "\u{2191}"), (0xAE, "arrowright", "\u{2192}"), (0xAF, "arrowdown", "\u{2193}"),
        (0xB0, "degree", "\u{00B0}"), (0xB1, "plusminus", "\u{00B1}"), (0xB2, "second", "\u{2033}"), (0xB3, "greaterequal", "\u{2265}"),
        (0xB4, "multiply", "\u{00D7}"), (0xB5, "proportional", "\u{221D}"), (0xB6, "partialdiff", "\u{2202}"), (0xB7, "bullet", "\u{2022}"),
        (0xB8, "divide", "\u{00F7}"), (0xB9, "notequal", "\u{2260}"), (0xBA, "equivalence", "\u{2261}"), (0xBB, "approxequal", "\u{2248}"),
        (0xBC, "ellipsis", "\u{2026}"), (0xBD, "arrowvertex", "\u{F8E6}"), (0xBE, "arrowhorizex", "\u{F8E7}"), (0xBF, "carriagereturn", "\u{21B5}"),
        (0xC0, "aleph", "\u{2135}"), (0xC1, "Ifraktur", "\u{2111}"), (0xC2, "Rfraktur", "\u{211C}"), (0xC3, "weierstrass", "\u{2118}"),
        (0xC4, "circlemultiply", "\u{2297}"), (0xC5, "circleplus", "\u{2295}"), (0xC6, "emptyset", "\u{2205}"), (0xC7, "intersection", "\u{2229}"),
        (0xC8, "union", "\u{222A}"), (0xC9, "propersuperset", "\u{2283}"), (0xCA, "reflexsuperset", "\u{2287}"), (0xCB, "notsubset", "\u{2284}"),
        (0xCC, "propersubset", "\u{2282}"), (0xCD, "reflexsubset", "\u{2286}"), (0xCE, "element", "\u{2208}"), (0xCF, "notelement", "\u{2209}"),
        (0xD0, "angle", "\u{2220}"), (0xD1, "gradient", "\u{2207}"), (0xD2, "registerserif", "\u{F6DA}"), (0xD3, "copyrightserif", "\u{F6D9}"),
        (0xD4, "trademarkserif", "\u{F6DB}"), (0xD5, "product", "\u{220F}"), (0xD6, "radical", "\u{221A}"), (0xD7, "dotmath", "\u{22C5}"),
        (0xD8, "logicalnot", "\u{00AC}"), (0xD9, "logicaland", "\u{2227}"), (0xDA, "logicalor", "\u{2228}"), (0xDB, "arrowdblboth", "\u{21D4}"),
        (0xDC, "arrowdblleft", "\u{21D0}"), (0xDD, "arrowdblup", "\u{21D1}"), (0xDE, "arrowdblright", "\u{21D2}"), (0xDF, "arrowdbldown", "\u{21D3}"),
        (0xE0, "lozenge", "\u{25CA}"), (0xE1, "angleleft", "\u{2329}"), (0xE2, "registersans", "\u{F8E8}"), (0xE3, "copyrightsans", "\u{F8E9}"),
        (0xE4, "trademarksans", "\u{F8EA}"), (0xE5, "summation", "\u{2211}"), (0xE6, "parenlefttp", "\u{F8EB}"), (0xE7, "parenleftex", "\u{F8EC}"),
        (0xE8, "parenleftbt", "\u{F8ED}"), (0xE9, "bracketlefttp", "\u{F8EE}"), (0xEA, "bracketleftex", "\u{F8EF}"), (0xEB, "bracketleftbt", "\u{F8F0}"),
        (0xEC, "bracelefttp", "\u{F8F1}"), (0xED, "braceleftmid", "\u{F8F2}"), (0xEE, "braceleftbt", "\u{F8F3}"), (0xEF, "braceex", "\u{F8F4}"),
        (0xF1, "angleright", "\u{232A}"), (0xF2, "integral", "\u{222B}"), (0xF3, "integraltp", "\u{2320}"), (0xF4, "integralex", "\u{F8F5}"),
        (0xF5, "integralbt", "\u{2321}"), (0xF6, "parenrighttp", "\u{F8F6}"), (0xF7, "parenrightex", "\u{F8F7}"), (0xF8, "parenrightbt", "\u{F8F8}"),
        (0xF9, "bracketrighttp", "\u{F8F9}"), (0xFA, "bracketrightex", "\u{F8FA}"), (0xFB, "bracketrightbt", "\u{F8FB}"), (0xFC, "bracerighttp", "\u{F8FC}"),
        (0xFD, "bracerightmid", "\u{F8FD}"), (0xFE, "bracerightbt", "\u{F8FE}"),
    ]

    static let symbolEncoding: [UInt8: String] = Dictionary(uniqueKeysWithValues: symbolTable.map { ($0.code, $0.character) })

    static let symbolGlyphNames: [String: String] = Dictionary(uniqueKeysWithValues: symbolTable.map { ($0.name, $0.character) })

    /// Adobe's private-use values for the Symbol font's pieces and sign variants, and the characters
    /// for them: U+23D0 and U+23AF arrow extensions, U+239B–U+23AD bracket and brace pieces, and the
    /// ordinary registered, copyright and trademark signs. `radicalex` (U+F8E5) has none.
    static let adobePrivateUse: [UInt32: String] = [
        0xF6D9: "\u{00A9}", 0xF6DA: "\u{00AE}", 0xF6DB: "\u{2122}", 0xF8E8: "\u{00AE}", 0xF8E9: "\u{00A9}", 0xF8EA: "\u{2122}",
        0xF8E6: "\u{23D0}", 0xF8E7: "\u{23AF}",
        0xF8EB: "\u{239B}", 0xF8EC: "\u{239C}", 0xF8ED: "\u{239D}", 0xF8EE: "\u{23A1}", 0xF8EF: "\u{23A2}", 0xF8F0: "\u{23A3}",
        0xF8F1: "\u{23A7}", 0xF8F2: "\u{23A8}", 0xF8F3: "\u{23A9}", 0xF8F4: "\u{23AA}", 0xF8F5: "\u{23AE}",
        0xF8F6: "\u{239E}", 0xF8F7: "\u{239F}", 0xF8F8: "\u{23A0}", 0xF8F9: "\u{23A4}", 0xF8FA: "\u{23A5}", 0xF8FB: "\u{23A6}",
        0xF8FC: "\u{23AB}", 0xF8FD: "\u{23AC}", 0xF8FE: "\u{23AD}",
    ]

    /// The Wingdings codes Word's bullet gallery inserts: `l` ●, `n` ■, `q` ❑, `u` ◆, `v` ❖, `§` ▪,
    /// `Ø` ➢, `ü` ✔. Other Wingdings pictographs are left undecoded.
    static let wingdingsBullets: [UInt8: String] = [
        0x6C: "\u{25CF}", 0x6E: "\u{25A0}", 0x71: "\u{2751}", 0x75: "\u{25C6}", 0x76: "\u{2756}",
        0xA7: "\u{25AA}", 0xD8: "\u{27A2}", 0xFC: "\u{2714}",
    ]
}
