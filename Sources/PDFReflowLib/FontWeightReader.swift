import Foundation
import CoreGraphics

/// Bold evidence from the PDF's own font resources (#125). PDFKit's attributed runs name a font
/// only when the system has one by that name: every Fed, 9/11 and Wallace run reports
/// `Helvetica`, and runs in two embedded fonts of one colour merge. A font's `BaseFont` and
/// `FontDescriptor` still state its weight (`FranklinGothicLTPro-Dm`, `/FontWeight 600`). This
/// reader scans a page's text shows, following Form XObjects, and records for each its origin,
/// size, decoded text where the font's map allows, and its font's weight. `apply` then marks a
/// PDFKit line's characters bold only where the shows explain the line: every show drawn on the
/// line is in one bold font, or the shows' decoded text spells the line and assigns each
/// character a weight. Anything else leaves the line as PDFKit read it.
enum FontWeightReader {
    /// Set on the characters of an attributed line drawn in a bold font resource.
    static let boldAttribute = NSAttributedString.Key("PDFReflowFontResourceBold")
    /// Set on the characters of an attributed line drawn in an italic text font resource (#133).
    static let italicAttribute = NSAttributedString.Key("PDFReflowFontResourceItalic")

    enum Weight: Equatable { case bold, regular }

    // MARK: - Font classification

    /// A weight word of a font name, from a name token: `bold`, `demi`, `semibold`, `heavy`,
    /// `black`, `extrabold`, `ultrabold` anywhere, and the abbreviations type foundries use in a
    /// style suffix (`Dm`, `Bd`, `SmBd`, `SemiBd`, `Sb`, `Hv`, `Blk`, `XBd`). Light, book,
    /// medium, regular and thin words state a weight that is not bold.
    enum NameWeight: Equatable { case bold, notBold, unstated }

    static let boldSuffixTokens: Set<String> = [
        "bd", "dm", "db", "dmbd", "smbd", "semibd", "sembd", "sb", "sbd", "hv", "hvy", "blk", "xbd", "exbd",
        "extbd", "xbold", "ub", "ubd",
    ]
    static let boldWords = ["bold", "demi", "heavy", "black"]
    static let lighterWords = ["light", "book", "medium", "regular", "thin", "hairline"]
    static let lighterSuffixTokens: Set<String> = ["lt", "bk", "md", "med", "reg", "rg", "th", "roman", "rom", "normal"]

    /// The name without a subset tag (`KGIFBZ+`) or a composite font's CMap suffix.
    static func strippedName(_ baseFont: String) -> String {
        var name = baseFont
        if let plus = name.firstIndex(of: "+"), name.distance(from: name.startIndex, to: plus) == 6,
           name[..<plus].allSatisfy({ $0.isUppercase && $0.isLetter }) {
            name = String(name[name.index(after: plus)...])
        }
        for suffix in ["-Identity-H", "-Identity-V"] where name.hasSuffix(suffix) {
            name.removeLast(suffix.count)
        }
        return name
    }

    /// Camel-case and digit boundaries split a style suffix: `DmIt` is `dm`, `it`.
    static func tokens(_ text: String) -> [String] {
        var result: [String] = [], current = ""
        for character in text {
            if !character.isLetter {
                if !current.isEmpty { result.append(current.lowercased()); current = "" }
                continue
            }
            if character.isUppercase, let last = current.last, last.isLowercase {
                result.append(current.lowercased()); current = ""
            }
            current.append(character)
        }
        if !current.isEmpty { result.append(current.lowercased()) }
        return result
    }

    /// TeX's Computer Modern and European Computer Modern short names state bold in their
    /// shape code: `cmbx12`, `cmb10`, `cmmib10`, `cmbsy10`, `cmssbx10`, `cmbxti10`, `dcbx10`, `ecbx1200`,
    /// and EC's and cm-super's bold italic, bold slanted and sans bold shapes (`ecbi1000`, `sfbx1200`, `sfsx1000`).
    static func isTeXBold(_ lower: String) -> Bool {
        lower.range(of: #"^(cm|dc|ec|tc)(ss)?(bx|b|mib|bsy)(sl|ti|sc)?[0-9]+$"#, options: .regularExpression) != nil
            || lower.range(of: #"^(dc|ec|tc|sf)(bx|bi|bl|sx|so)[0-9]+$"#, options: .regularExpression) != nil
    }

    /// The Linux Libertine and Biolinum Type 1 and OpenType names state their style in capitals
    /// after the family and its format letter (`T` or `O`): `B` bold, `Z` semibold, `I` italic,
    /// `O` Biolinum's oblique. arXiv's `LinLibertineTB` section titles state bold in nothing else.
    static func libertineStyle(_ name: String) -> (bold: Bool, italic: Bool)? {
        guard let match = name.range(of: #"^Lin(Libertine|Biolinum)(Display)?[TO]([BZ]?)([IO]?)$"#, options: .regularExpression) else {
            return nil
        }
        let family = name.hasPrefix("LinLibertine") ? "LinLibertine" : "LinBiolinum"
        var rest = name[match].dropFirst(family.count)
        if rest.hasPrefix("Display") { rest = rest.dropFirst("Display".count) }
        rest = rest.dropFirst()
        return (rest.contains("B") || rest.contains("Z"), rest.contains("I") || rest.contains("O"))
    }

    static func nameWeight(_ baseFont: String) -> NameWeight {
        let name = strippedName(baseFont)
        let lower = name.lowercased()
        if isTeXBold(lower) { return .bold }
        if let libertine = libertineStyle(name) { return libertine.bold ? .bold : .unstated }
        // A style suffix follows the family after a hyphen or comma (`Arial,Bold`); a name
        // without one is read whole for the weight words only.
        let separator = name.lastIndex(where: { $0 == "-" || $0 == "," })
        let suffix = separator.map { String(name[name.index(after: $0)...]) } ?? ""
        let suffixTokens = tokens(suffix)
        // A lighter weight word is read in the style suffix where there is one, so a family name
        // (`Bookman-Demi`) states no weight.
        let style = separator == nil ? lower : suffix.lowercased()
        let lighter = lighterWords.contains(where: style.contains)
            || suffixTokens.contains(where: lighterSuffixTokens.contains)
        let bold = boldWords.contains(where: lower.contains) || suffixTokens.contains(where: boldSuffixTokens.contains)
        // `DemiLight`, `SemiLight`: the lighter word decides. `Bold` always wins, as PDFKit's
        // own name rule already reads it.
        if lower.contains("bold") && !lower.contains("light") { return .bold }
        if bold && !lighter { return .bold }
        if lighter { return .notBold }
        return .unstated
    }

    /// A font's weight from its name and descriptor. The name decides when it states a weight;
    /// a stated demi or heavy weight contradicted by a descriptor `FontWeight` below 500 is not
    /// bold, and a stated lighter weight is never overridden. A name that states no weight is
    /// bold when its descriptor's `FontWeight` is at least 600 or its `ForceBold` flag is set.
    /// `StemV` is recorded by the survey but not used: stem widths vary by family and size.
    static func weight(baseFont: String?, fontWeight: CGFloat?, flags: Int?) -> Weight {
        let forceBold = (flags ?? 0) & (1 << 18) != 0
        switch baseFont.map(nameWeight) ?? .unstated {
        case .bold:
            let name = strippedName(baseFont ?? "").lowercased()
            if !name.contains("bold"), !isTeXBold(name), let fontWeight, fontWeight < 500 { return .regular }
            return .bold
        case .notBold:
            return .regular
        case .unstated:
            return (fontWeight ?? 0) >= 600 || forceBold ? .bold : .regular
        }
    }

    // MARK: - Slope (#133)

    /// What a font name states about its slope. Math italic is TeX's and newtx's variable face
    /// (`CMMI12`, `LibertineMathMI`): a notation, not emphasis, so it never reads italic.
    enum NameSlope: Equatable { case italic, upright, mathItalic, unstated }

    static let italicWords = ["italic", "oblique", "kursiv", "slanted", "inclined"]
    static let italicSuffixTokens: Set<String> = ["it", "ital", "obl"]
    static let uprightWords = ["roman", "upright", "regular", "normal"]
    static let uprightSuffixTokens: Set<String> = ["rom", "reg", "rg"]

    /// A TeX Computer Modern, European Computer Modern or cm-super short name (`cmti10`, `CMMI12`,
    /// `dcti10084`, `SFTI1000`) states its shape in full: its descriptor's `ItalicAngle` describes the design (TeX's `CMSY10`
    /// symbols lean at −14°), not the text.
    static func teXSlope(_ lower: String) -> NameSlope? {
        guard lower.range(of: #"^(cm|dc|ec|tc|sf)[a-z]+[0-9]+$"#, options: .regularExpression) != nil else { return nil }
        if lower.range(of: #"^cmmib?[0-9]+$"#, options: .regularExpression) != nil { return .mathItalic }
        if lower.range(of: #"^cm(ti|bxti|sl|bxsl|itt|sltt|ssi|ssqi|u)[0-9]+$"#, options: .regularExpression) != nil
            || lower.range(of: #"^(dc|ec|tc|sf)(ti|sl|bi|bl|si|so|it|st|ui)[0-9]+$"#, options: .regularExpression) != nil {
            return .italic
        }
        return .upright
    }

    static func nameSlope(_ baseFont: String) -> NameSlope {
        let name = strippedName(baseFont)
        let lower = name.lowercased()
        if let tex = teXSlope(lower) { return tex }
        if let libertine = libertineStyle(name) { return libertine.italic ? .italic : .upright }
        if lower.contains("mathmi") || lower.range(of: #"^(newtx|ntx|tx|zx)b?mi"#, options: .regularExpression) != nil {
            return .mathItalic
        }
        let separator = name.lastIndex(where: { $0 == "-" || $0 == "," })
        let suffix = separator.map { String(name[name.index(after: $0)...]) } ?? ""
        let suffixTokens = tokens(suffix)
        if italicWords.contains(where: lower.contains) || suffixTokens.contains(where: italicSuffixTokens.contains) {
            return .italic
        }
        // An upright word is read in the style suffix where there is one (`TimesNewRoman,Italic`).
        let style = separator == nil ? lower : suffix.lowercased()
        if uprightWords.contains(where: style.contains) || suffixTokens.contains(where: uprightSuffixTokens.contains) {
            return .upright
        }
        return .unstated
    }

    /// Whether a font sets italic text. The name decides when it states a slope; a name stating
    /// none is italic when its descriptor sets the `Italic` flag (bit 7) or leans by at least
    /// `minimumItalicAngle` degrees, unless it is a symbol font (`Symbolic` without `Nonsymbolic`)
    /// or a script face (the `Script` flag, or `Script` in its name): Our Flag's
    /// `SnellRoundhand-BoldScript` titles lean at 40° with the Italic flag, as calligraphy, not emphasis.
    static let minimumItalicAngle: CGFloat = 5
    static func isItalic(baseFont: String?, italicAngle: CGFloat?, flags: Int?) -> Bool {
        switch baseFont.map(nameSlope) ?? .unstated {
        case .italic: return true
        case .upright, .mathItalic: return false
        case .unstated:
            let flags = flags ?? 0
            let symbolic = flags & (1 << 2) != 0 && flags & (1 << 5) == 0
            let script = flags & (1 << 3) != 0 || baseFont.map { strippedName($0).lowercased().contains("script") } == true
            return !symbolic && !script && (flags & (1 << 6) != 0 || abs(italicAngle ?? 0) >= minimumItalicAngle)
        }
    }

    struct FontInfo {
        var baseFont: String?
        var subtype: String
        var fontWeight: CGFloat?
        var stemV: CGFloat?
        var flags: Int?
        var italicAngle: CGFloat? = nil
        var hasToUnicode: Bool
        /// Nil for a Type3 font with no descriptor: its glyphs are procedures with no weight.
        var weight: Weight?
        /// Nil exactly where `weight` is.
        var italic: Bool?
        /// A simple font's one-byte map: its ToUnicode map, or a Type1 font's WinAnsi encoding.
        var unicode: [UInt8: String]?
        /// A composite `Identity-H` font's two-byte ToUnicode map (#133).
        var wideUnicode: [UInt16: String]?
        /// A simple font that names its glyphs by index and has no ToUnicode map (#143).
        var indexGlyphs: IndexGlyphFont?
    }

    // MARK: - Index-named glyphs (#143)

    /// A simple font without a ToUnicode map whose `Differences` names at least half its codes
    /// `G<n>`, `g<n>`, `C<n>` or `c<n>`: Acrobat Distiller 4.05's TeX fonts in the Census report
    /// (`/G87` draws `T`). PDFKit reports such a glyph as the character U+n, so the Census text
    /// reads shifted by three letters. `key` identifies the font across pages and reopened
    /// documents (subtype, `BaseFont` and the whole `Differences` array); `indexes` maps each code
    /// the array names that way to its index, and `names` every other code it names.
    struct IndexGlyphFont: Equatable {
        var key: String
        var baseFont: String?
        var indexes: [UInt8: Int]
        var names: [UInt8: String] = [:]
    }

    /// The glyph index an index-style name states, or nil.
    static func glyphIndex(_ name: String) -> Int? {
        guard let first = name.first, "GgCc".contains(first), name.count >= 2, name.count <= 6 else { return nil }
        let digits = name.dropFirst()
        guard digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(digits)
    }

    /// What PDFKit reports for a glyph named with index `n` (measured on macOS 27 for
    /// `G`, `g`, `C` and `c` names in Type1 fonts): the character U+n for 33–126 and 161–255,
    /// and nothing for any other index.
    static func pdfKitText(index: Int) -> String {
        (33...126).contains(index) || (161...255).contains(index) ? String(UnicodeScalar(UInt8(index))) : ""
    }

    static func indexGlyphFont(_ dict: CGPDFDictionaryRef) -> IndexGlyphFont? {
        guard let subtype = name(dict, "Subtype"), ["Type1", "MMType1", "TrueType", "Type3"].contains(subtype) else { return nil }
        var stream: CGPDFStreamRef?, encoding: CGPDFDictionaryRef?, differences: CGPDFArrayRef?
        guard !CGPDFDictionaryGetStream(dict, "ToUnicode", &stream),
              CGPDFDictionaryGetDictionary(dict, "Encoding", &encoding), let encoding,
              CGPDFDictionaryGetArray(encoding, "Differences", &differences), let differences,
              CGPDFArrayGetCount(differences) <= 512 else { return nil }
        var indexes: [UInt8: Int] = [:], named: [UInt8: String] = [:], names = 0, key = subtype + "|" + (name(dict, "BaseFont") ?? "") + "|"
        var next: Int?
        for position in 0..<CGPDFArrayGetCount(differences) {
            var code: CGPDFInteger = 0, glyph: UnsafePointer<CChar>?
            if CGPDFArrayGetInteger(differences, position, &code) {
                guard (0...255).contains(code) else { return nil }
                next = code
                key += "\(code) "
            } else if CGPDFArrayGetName(differences, position, &glyph), let glyph {
                guard let code = next, code <= 255 else { return nil }
                let text = String(cString: glyph)
                names += 1
                if let index = glyphIndex(text) { indexes[UInt8(code)] = index } else { named[UInt8(code)] = text }
                key += "/" + text + " "
                next = code + 1
            } else { return nil }
        }
        guard !indexes.isEmpty, indexes.count * 2 >= names else { return nil }
        return IndexGlyphFont(key: key, baseFont: name(dict, "BaseFont"), indexes: indexes, names: named)
    }

    private static func name(_ dict: CGPDFDictionaryRef, _ key: String) -> String? {
        var value: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(dict, key, &value), let value else { return nil }
        return String(cString: value)
    }

    private static func number(_ dict: CGPDFDictionaryRef, _ key: String) -> CGFloat? {
        var value: CGPDFReal = 0
        return CGPDFDictionaryGetNumber(dict, key, &value) && value.isFinite ? value : nil
    }

    /// `decodings` maps an index-glyph font's `key` to the characters its codes draw, where the
    /// document's own text established them (`GlyphIndexDecoder`, #143).
    static func fontInfo(_ dict: CGPDFDictionaryRef, decodings: [String: [UInt8: String]] = [:]) -> FontInfo {
        let subtype = name(dict, "Subtype") ?? ""
        var descriptorOwner = dict
        if subtype == "Type0" {
            var descendants: CGPDFArrayRef?, first: CGPDFDictionaryRef?
            if CGPDFDictionaryGetArray(dict, "DescendantFonts", &descendants), let descendants,
               CGPDFArrayGetCount(descendants) >= 1, CGPDFArrayGetDictionary(descendants, 0, &first), let first {
                descriptorOwner = first
            }
        }
        var descriptor: CGPDFDictionaryRef?
        let hasDescriptor = CGPDFDictionaryGetDictionary(descriptorOwner, "FontDescriptor", &descriptor) && descriptor != nil
        var flags: Int?
        if let descriptor {
            var value: CGPDFInteger = 0
            if CGPDFDictionaryGetInteger(descriptor, "Flags", &value) { flags = value }
        }
        let baseFont = name(dict, "BaseFont")
        let fontWeight = descriptor.flatMap { number($0, "FontWeight") }
        var stream: CGPDFStreamRef?
        let hasMap = CGPDFDictionaryGetStream(dict, "ToUnicode", &stream) && stream != nil
        let italicAngle = descriptor.flatMap { number($0, "ItalicAngle") }
        var info = FontInfo(baseFont: baseFont, subtype: subtype, fontWeight: fontWeight,
                            stemV: descriptor.flatMap { number($0, "StemV") }, flags: flags, italicAngle: italicAngle,
                            hasToUnicode: hasMap)
        if subtype != "Type3" || hasDescriptor || baseFont != nil {
            info.weight = weight(baseFont: baseFont, fontWeight: fontWeight, flags: flags)
            info.italic = isItalic(baseFont: baseFont, italicAngle: italicAngle, flags: flags)
        }
        var format = CGPDFDataFormat.raw
        let data = hasMap ? stream.flatMap { CGPDFStreamCopyData($0, &format) }.flatMap { format == .raw ? $0 as Data : nil } : nil
        if ["Type1", "TrueType", "MMType1"].contains(subtype) {
            if let data {
                info.unicode = NativeSpacingReader.simpleFontUnicodeMap(data) ?? oneByteUnicodeMap(data)
            } else if !hasMap, subtype != "TrueType" {
                // Ghostscript's TeX output (Wallace) writes only a WinAnsi encoding (#110).
                info.unicode = NativeSpacingReader.encodingUnicodeMap(dict)
            }
        } else if subtype == "Type0", name(dict, "Encoding") == "Identity-H", let data {
            info.wideUnicode = wideUnicodeMap(data)
        }
        if !hasMap, let index = indexGlyphFont(dict) {
            info.indexGlyphs = index
            if let decoded = decodings[index.key] { info.unicode = decoded }
        }
        return info
    }

    /// A simple font's codes are one byte whatever codespace its ToUnicode map declares. PScript5
    /// writes a symbol-style `<00> <EF>` and `<F000> <FFFF>` pair over one-byte entries (the Supreme
    /// Court's Century Schoolbook), which `simpleFontUnicodeMap` refuses; here any codespace is
    /// read as one byte, and a two-byte entry still fails the parse.
    static func oneByteUnicodeMap(_ data: Data) -> [UInt8: String]? {
        guard data.count <= 65_536, let text = String(data: data, encoding: .isoLatin1),
              text.components(separatedBy: "begincodespacerange").count == 2,
              let normalized = text.replacingOccurrences(
                of: #"[0-9]+\s+begincodespacerange[\s\S]*?endcodespacerange"#,
                with: "1 begincodespacerange <00> <FF> endcodespacerange", options: .regularExpression
              ).data(using: .isoLatin1) else { return nil }
        return NativeSpacingReader.unicodeMap(normalized)
    }

    /// An `Identity-H` composite font's ToUnicode map: bfchar and bfrange entries from four-digit
    /// codes to UTF-16 (DGA's and NOAA's Type0 Roboto and Lora). Identity-H codes are two bytes, so
    /// the codespace must consist of two-byte ranges: `<0000> <FFFF>`, or the CDC comic's narrowed
    /// `<0001> <0022>`. Inherited maps, one-byte codespaces, duplicate codes and malformed entries fall back.
    static func wideUnicodeMap(_ data: Data) -> [UInt16: String]? {
        guard data.count <= 1_048_576, let input = String(data: data, encoding: .isoLatin1) else { return nil }
        let text = input.replacingOccurrences(of: "%[^\r\n]*", with: "", options: .regularExpression)
        guard !text.contains("usecmap"), text.contains("begincmap"),
              text.range(of: #"begincodespacerange(\s*<[0-9a-fA-F]{4}>\s*<[0-9a-fA-F]{4}>)+\s*endcodespacerange"#,
                         options: .regularExpression) != nil,
              text.components(separatedBy: "begincodespacerange").count == 2 else { return nil }
        func units(_ hex: String) -> [UInt16]? {
            guard hex.count % 4 == 0, !hex.isEmpty, hex.count <= 64 else { return nil }
            var result: [UInt16] = [], index = hex.startIndex
            while index < hex.endIndex {
                let next = hex.index(index, offsetBy: 4)
                guard let unit = UInt16(hex[index..<next], radix: 16) else { return nil }
                result.append(unit); index = next
            }
            return result
        }
        var result: [UInt16: String] = [:]
        func assign(_ code: Int, _ values: [UInt16]) -> Bool {
            let value = String(utf16CodeUnits: values, count: values.count)
            guard (0...0xFFFF).contains(code), result[UInt16(code)] == nil, Array(value.utf16) == values,
                  result.count < 65_536 else { return false }
            result[UInt16(code)] = value
            return true
        }
        let ns = text as NSString
        let blocks = try! NSRegularExpression(pattern: #"(\d+)\s+begin(bfchar|bfrange)\s*([\s\S]*?)\s*end\2"#)
        let chars = try! NSRegularExpression(pattern: #"<([0-9a-fA-F]{4})>\s*<([0-9a-fA-F]+)>"#)
        let ranges = try! NSRegularExpression(
            pattern: #"<([0-9a-fA-F]{4})>\s*<([0-9a-fA-F]{4})>\s*(?:<([0-9a-fA-F]+)>|\[((?:\s*<[0-9a-fA-F]+>)+)\s*\])"#)
        let hexes = try! NSRegularExpression(pattern: #"<([0-9a-fA-F]+)>"#)
        let matches = blocks.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty, matches.count <= 1024,
              matches.count == text.components(separatedBy: "beginbf").count - 1 else { return nil }
        for block in matches {
            let kind = ns.substring(with: block.range(at: 2))
            let body = ns.substring(with: block.range(at: 3)) as NSString
            let whole = NSRange(location: 0, length: body.length)
            let expression = kind == "bfchar" ? chars : ranges
            let entries = expression.matches(in: body as String, range: whole)
            guard Int(ns.substring(with: block.range(at: 1))) == entries.count,
                  expression.stringByReplacingMatches(in: body as String, range: whole, withTemplate: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            for entry in entries {
                guard let low = Int(body.substring(with: entry.range(at: 1)), radix: 16) else { return nil }
                if kind == "bfchar" {
                    guard let values = units(body.substring(with: entry.range(at: 2))), assign(low, values) else { return nil }
                    continue
                }
                guard let high = Int(body.substring(with: entry.range(at: 2)), radix: 16), high >= low,
                      high - low < 65_536 else { return nil }
                if entry.range(at: 3).location != NSNotFound {
                    guard var values = units(body.substring(with: entry.range(at: 3))), let last = values.last else { return nil }
                    for code in low...high {
                        guard Int(last) + (code - low) <= 0xFFFF else { return nil }
                        values[values.count - 1] = last + UInt16(code - low)
                        guard assign(code, values) else { return nil }
                    }
                } else {
                    let list = body.substring(with: entry.range(at: 4)) as NSString
                    let items = hexes.matches(in: list as String, range: NSRange(location: 0, length: list.length))
                    guard items.count == high - low + 1 else { return nil }
                    for (offset, item) in items.enumerated() {
                        guard let values = units(list.substring(with: item.range(at: 1))), assign(low + offset, values) else { return nil }
                    }
                }
            }
        }
        return result.isEmpty ? nil : result
    }

    // MARK: - Page scan

    struct Show {
        /// Page-space origin of the show; a show drawn straight after another without a
        /// positioning operator carries that show's origin and `placed == false`.
        var origin: CGPoint
        var size: CGFloat
        var font: Int
        var weight: Weight?
        /// The show's text through its font's one-byte ToUnicode map; nil when any code is unmapped.
        var text: String?
        var placed: Bool
        /// Drawn in an italic text font; nil where `weight` is.
        var italic: Bool? = false
        /// The show's glyphs where its font names them by index (#143); nil in any other font.
        var glyphs: [IndexGlyph]? = nil
        /// Identifies the index-glyph font (`IndexGlyphFont.key`); nil in any other font.
        var indexFont: String? = nil

        var styled: Bool { weight == .bold || italic == true }
    }

    /// One code of an index-glyph show: its index where the font's `Differences` names it by one,
    /// and whether a word-sized gap (`wordGap` em or more, from a TJ adjustment and character
    /// spacing) or the start of the show precedes it.
    struct IndexGlyph: Equatable {
        var code: UInt8
        var index: Int?
        var wordStart: Bool
        /// The character the document established for the code; nil where it established none.
        var text: String?
    }

    /// TeX's interword glue shrinks to about 0.17 em; kerns and italic corrections stay far below.
    static let wordGap: CGFloat = 0.15

    private final class State {
        var matrix = CGAffineTransform.identity
        var line = CGAffineTransform.identity
        var font: Int?
        var size: CGFloat = 0
        var leading: CGFloat = 0
        var saved: [(CGAffineTransform, Int?, CGFloat, CGFloat, CGFloat)] = []
        /// Character spacing (`Tc`) in unscaled text space units, for word gaps in index-glyph shows.
        var characterSpacing: CGFloat = 0
        var decodings: [String: [UInt8: String]] = [:]
        var inText = false
        var positioned = false
        var lastOrigin: CGPoint?
        var invalid = false
        var operations = 0
        var fonts: [Int: FontInfo] = [:]
        var shows: [Show] = []
        var formDepth = 0
        var table: CGPDFOperatorTableRef?

        func accept(_ scanner: CGPDFScannerRef) -> Bool {
            operations += 1
            if operations > 400_000 || Task.isCancelled { invalid = true }
            if invalid { CGPDFScannerStop(scanner) }
            return !invalid
        }
    }

    private static func state(_ info: UnsafeMutableRawPointer?) -> State {
        Unmanaged<State>.fromOpaque(info!).takeUnretainedValue()
    }

    private static func numbers(_ scanner: CGPDFScannerRef, _ count: Int) -> [CGFloat]? {
        var values = [CGFloat](repeating: 0, count: count)
        for i in values.indices.reversed() {
            var value: CGPDFReal = 0
            guard CGPDFScannerPopNumber(scanner, &value), value.isFinite else { return nil }
            values[i] = value
        }
        return values
    }

    /// `strings` pairs each string of a show with the sum of the TJ adjustments before it.
    private static func show(_ s: State, _ strings: [(CGPDFStringRef, CGFloat)]) {
        guard s.inText, s.shows.count < 50_000 else { s.invalid = true; return }
        let transform = s.line.concatenating(s.matrix)
        guard transform.tx.isFinite, transform.ty.isFinite, transform.a.isFinite, transform.d.isFinite else { return }
        // Rotated or mirrored text supplies no evidence for upright lines.
        guard transform.b == 0, transform.c == 0, transform.a > 0, transform.d > 0 else {
            s.positioned = false; s.lastOrigin = nil; return
        }
        let origin: CGPoint
        let placed = s.positioned
        if s.positioned {
            origin = CGPoint(x: transform.tx, y: transform.ty)
        } else if let last = s.lastOrigin {
            origin = last
        } else { return }
        s.positioned = false
        s.lastOrigin = origin
        let info = s.font.flatMap { s.fonts[$0] }
        var text: String? = info?.unicode == nil && info?.wideUnicode == nil ? nil : ""
        var glyphs: [IndexGlyph]?
        if let index = info?.indexGlyphs {
            glyphs = []
            // Character spacing moves every glyph; an adjustment moves the glyphs after it.
            let spacing = s.size > 0 ? s.characterSpacing / s.size : 0
            for (string, adjustment) in strings {
                let count = CGPDFStringGetLength(string)
                guard let bytes = CGPDFStringGetBytePtr(string), count <= 4096, (glyphs?.count ?? 0) + count <= 8192 else {
                    glyphs = nil; break
                }
                for offset in 0..<count {
                    let gap = spacing - (offset == 0 ? adjustment / 1000 : 0)
                    let start = (glyphs?.isEmpty ?? true) || gap >= wordGap
                    glyphs?.append(IndexGlyph(code: bytes[offset], index: index.indexes[bytes[offset]], wordStart: start,
                                              text: info?.unicode?[bytes[offset]]))
                }
            }
        }
        for (string, _) in strings where text != nil {
            let count = CGPDFStringGetLength(string)
            guard let bytes = CGPDFStringGetBytePtr(string), count <= 4096 else { text = nil; break }
            if let wide = info?.wideUnicode {
                // An Identity-H show's codes are two bytes, high byte first.
                guard count % 2 == 0 else { text = nil; break }
                for index in stride(from: 0, to: count, by: 2) {
                    guard let decoded = wide[UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1])],
                          (text?.utf16.count ?? 0) < 8192 else { text = nil; break }
                    text? += decoded
                }
            } else {
                for index in 0..<count {
                    guard let decoded = info?.unicode?[bytes[index]], (text?.utf16.count ?? 0) < 8192 else { text = nil; break }
                    text? += decoded
                }
            }
        }
        s.shows.append(Show(origin: origin, size: s.size * transform.d, font: s.font ?? 0,
                            weight: info?.weight, text: text, placed: placed, italic: info?.italic,
                            glyphs: glyphs, indexFont: info?.indexGlyphs?.key))
    }

    private static func scan(_ content: CGPDFContentStreamRef, _ s: State) {
        guard let table = s.table else { return }
        let scanner = CGPDFScannerCreate(content, table, Unmanaged.passUnretained(s).toOpaque())
        defer { CGPDFScannerRelease(scanner) }
        if !CGPDFScannerScan(scanner) { s.invalid = true }
    }

    private static func makeTable() -> CGPDFOperatorTableRef? {
        guard let table = CGPDFOperatorTableCreate() else { return nil }
        CGPDFOperatorTableSetCallback(table, "q") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), s.saved.count < 256 else { s.invalid = true; return }
            s.saved.append((s.matrix, s.font, s.size, s.leading, s.characterSpacing))
        }
        CGPDFOperatorTableSetCallback(table, "Q") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), let saved = s.saved.popLast() else { s.invalid = true; return }
            (s.matrix, s.font, s.size, s.leading, s.characterSpacing) = saved
        }
        CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), let n = Self.numbers(scanner, 6) else { s.invalid = true; return }
            s.matrix = CGAffineTransform(a: n[0], b: n[1], c: n[2], d: n[3], tx: n[4], ty: n[5]).concatenating(s.matrix)
        }
        CGPDFOperatorTableSetCallback(table, "Tf") { scanner, info in
            let s = Self.state(info)
            var name: UnsafePointer<CChar>?, dict: CGPDFDictionaryRef?
            guard s.accept(scanner), let n = Self.numbers(scanner, 1), CGPDFScannerPopName(scanner, &name), let name else {
                s.invalid = true; return
            }
            s.size = n[0]
            guard let object = CGPDFContentStreamGetResource(CGPDFScannerGetContentStream(scanner), "Font", name),
                  CGPDFObjectGetValue(object, .dictionary, &dict), let dict else { s.font = nil; return }
            let id = unsafeBitCast(dict, to: Int.self)
            if s.fonts[id] == nil {
                guard s.fonts.count < 1024 else { s.invalid = true; return }
                s.fonts[id] = Self.fontInfo(dict, decodings: s.decodings)
            }
            s.font = id
        }
        CGPDFOperatorTableSetCallback(table, "BT") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner) else { return }
            s.inText = true; s.line = .identity; s.positioned = true; s.lastOrigin = nil
        }
        CGPDFOperatorTableSetCallback(table, "ET") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner) else { return }
            s.inText = false; s.positioned = false; s.lastOrigin = nil
        }
        CGPDFOperatorTableSetCallback(table, "Tm") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), let n = Self.numbers(scanner, 6) else { s.invalid = true; return }
            s.line = CGAffineTransform(a: n[0], b: n[1], c: n[2], d: n[3], tx: n[4], ty: n[5]); s.positioned = true
        }
        CGPDFOperatorTableSetCallback(table, "Td") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), let n = Self.numbers(scanner, 2) else { s.invalid = true; return }
            s.line = s.line.translatedBy(x: n[0], y: n[1]); s.positioned = true
        }
        CGPDFOperatorTableSetCallback(table, "TD") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), let n = Self.numbers(scanner, 2) else { s.invalid = true; return }
            s.leading = -n[1]; s.line = s.line.translatedBy(x: n[0], y: n[1]); s.positioned = true
        }
        CGPDFOperatorTableSetCallback(table, "T*") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner) else { return }
            s.line = s.line.translatedBy(x: 0, y: -s.leading); s.positioned = true
        }
        CGPDFOperatorTableSetCallback(table, "TL") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), let n = Self.numbers(scanner, 1) else { s.invalid = true; return }
            s.leading = n[0]
        }
        CGPDFOperatorTableSetCallback(table, "Tj") { scanner, info in
            let s = Self.state(info)
            var string: CGPDFStringRef?
            guard s.accept(scanner), CGPDFScannerPopString(scanner, &string), let string else { s.invalid = true; return }
            Self.show(s, [(string, 0)])
        }
        CGPDFOperatorTableSetCallback(table, "'") { scanner, info in
            let s = Self.state(info)
            var string: CGPDFStringRef?
            guard s.accept(scanner), CGPDFScannerPopString(scanner, &string), let string else { s.invalid = true; return }
            s.line = s.line.translatedBy(x: 0, y: -s.leading); s.positioned = true
            Self.show(s, [(string, 0)])
        }
        CGPDFOperatorTableSetCallback(table, "\"") { scanner, info in
            let s = Self.state(info)
            var string: CGPDFStringRef?
            guard s.accept(scanner), CGPDFScannerPopString(scanner, &string), let string,
                  let n = Self.numbers(scanner, 2) else { s.invalid = true; return }
            s.characterSpacing = n[1]
            s.line = s.line.translatedBy(x: 0, y: -s.leading); s.positioned = true
            Self.show(s, [(string, 0)])
        }
        CGPDFOperatorTableSetCallback(table, "Tc") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), let n = Self.numbers(scanner, 1) else { s.invalid = true; return }
            s.characterSpacing = n[0]
        }
        CGPDFOperatorTableSetCallback(table, "TJ") { scanner, info in
            let s = Self.state(info)
            var array: CGPDFArrayRef?
            guard s.accept(scanner), CGPDFScannerPopArray(scanner, &array), let array,
                  CGPDFArrayGetCount(array) <= 8192 else { s.invalid = true; return }
            var strings: [(CGPDFStringRef, CGFloat)] = []
            var adjustment: CGFloat = 0
            for index in 0..<CGPDFArrayGetCount(array) {
                var string: CGPDFStringRef?, number: CGPDFReal = 0
                if CGPDFArrayGetString(array, index, &string), let string {
                    strings.append((string, adjustment)); adjustment = 0
                } else if CGPDFArrayGetNumber(array, index, &number), number.isFinite {
                    adjustment += number
                }
            }
            Self.show(s, strings)
        }
        // A Form XObject's text is drawn through the form's matrix with the form's resources.
        CGPDFOperatorTableSetCallback(table, "Do") { scanner, info in
            let s = Self.state(info)
            var name: UnsafePointer<CChar>?, stream: CGPDFStreamRef?
            guard s.accept(scanner), CGPDFScannerPopName(scanner, &name), let name else { s.invalid = true; return }
            let parent = CGPDFScannerGetContentStream(scanner)
            guard let object = CGPDFContentStreamGetResource(parent, "XObject", name),
                  CGPDFObjectGetValue(object, .stream, &stream), let stream,
                  let dict = CGPDFStreamGetDictionary(stream), Self.name(dict, "Subtype") == "Form",
                  s.formDepth < 8, !s.inText else { return }
            var matrix = CGAffineTransform.identity, array: CGPDFArrayRef?
            if CGPDFDictionaryGetArray(dict, "Matrix", &array), let array, CGPDFArrayGetCount(array) == 6 {
                var n = [CGFloat](repeating: 0, count: 6)
                for index in 0..<6 {
                    var value: CGPDFReal = 0
                    guard CGPDFArrayGetNumber(array, index, &value), value.isFinite else { s.invalid = true; return }
                    n[index] = value
                }
                matrix = CGAffineTransform(a: n[0], b: n[1], c: n[2], d: n[3], tx: n[4], ty: n[5])
            }
            // A form without its own resources is skipped; its text supplies no evidence.
            var resources: CGPDFDictionaryRef?
            guard CGPDFDictionaryGetDictionary(dict, "Resources", &resources), let resources else { return }
            let content = CGPDFContentStreamCreateWithStream(stream, resources, parent)
            defer { CGPDFContentStreamRelease(content) }
            let saved = (s.matrix, s.font, s.size, s.leading, s.saved.count, s.characterSpacing)
            s.matrix = matrix.concatenating(s.matrix)
            s.formDepth += 1
            Self.scan(content, s)
            s.formDepth -= 1
            s.inText = false
            s.saved.removeLast(max(0, s.saved.count - saved.4))
            (s.matrix, s.font, s.size, s.leading, s.characterSpacing) = (saved.0, saved.1, saved.2, saved.3, saved.5)
        }
        return table
    }

    /// The page's text shows, or none when the content stream cannot be scanned or no show is
    /// drawn in a bold or italic font (then no line can gain a style) or in an index-glyph font
    /// (then no line needs `repairIndexGlyphs`, #143). `decodings` are the characters the document
    /// established for index-glyph fonts.
    static func read(_ page: CGPDFPage, decodings: [String: [UInt8: String]] = [:]) -> [Show] {
        let shows = read(page, fonts: nil, decodings: decodings)
        return shows.contains(where: { $0.styled || $0.indexFont != nil }) ? shows : []
    }

    /// The page's shows and, when `fonts` is given, every font resource it selected (survey).
    static func read(_ page: CGPDFPage, fonts: ((Int, FontInfo) -> Void)?,
                     decodings: [String: [UInt8: String]] = [:]) -> [Show] {
        guard let table = makeTable() else { return [] }
        defer { CGPDFOperatorTableRelease(table) }
        let s = State()
        s.table = table
        s.decodings = decodings
        let content = CGPDFContentStreamCreateWithPage(page)
        defer { CGPDFContentStreamRelease(content) }
        scan(content, s)
        if let fonts { for (id, info) in s.fonts { fonts(id, info) } }
        guard !s.invalid else { return [] }
        return s.shows
    }

    // MARK: - Lines

    /// Marks the characters of `attributed` (a PDFKit line with `bounds`) drawn in bold font
    /// resources with `boldAttribute`, and those drawn in italic text fonts with `italicAttribute`
    /// (#133). The line's shows are those whose origin lies in its bounds and in no other line's.
    /// They explain the line when the leftmost starts within half an em of the line's left edge
    /// (so no show begun on another line draws its first glyphs) and, where every show decodes,
    /// their text spells the line apart from whitespace. Then a line whose shows all share a style
    /// carries it throughout; a line mixing styles is marked character by character from the
    /// decoded shows in reading order. A style the shows do not all share is left unmarked when
    /// they do not decode or do not spell the line. A line without a styled show is unchanged.
    static func apply(_ shows: [Show], to attributed: NSAttributedString, bounds: CGRect,
                      allBounds: [CGRect]) -> NSAttributedString {
        guard attributed.length > 0, let (matches, chosen) = lineShows(shows, bounds: bounds, allBounds: allBounds),
              matches.contains(where: \.styled),
              !chosen || matches.allSatisfy({ $0.text != nil }) else { return attributed }
        let decoded = matches.allSatisfy { $0.text != nil }
        // Per style, each letter's flag in reading order, or nil to mark the whole line.
        var styles: [(key: NSAttributedString.Key, flags: [Bool]?)] = []
        if decoded {
            var sequence: [(Unicode.Scalar, Show)] = []
            for show in readingOrder(matches) {
                sequence += letters(show.text ?? "").map { ($0, show) }
            }
            guard sequence.map(\.0) == letters(attributed.string),
                  sequence.allSatisfy({ $0.1.weight != nil }) else { return attributed }
            styles = [(boldAttribute, sequence.map { $0.1.weight == .bold }),
                      (italicAttribute, sequence.map { $0.1.italic == true })]
        } else {
            if matches.allSatisfy({ $0.weight == .bold }) { styles.append((boldAttribute, nil)) }
            if matches.allSatisfy({ $0.italic == true }) { styles.append((italicAttribute, nil)) }
            guard !styles.isEmpty else { return attributed }
        }
        var marks: [(key: NSAttributedString.Key, ranges: [NSRange])] = []
        for (key, flags) in styles {
            guard let flags else {
                marks.append((key, [NSRange(location: 0, length: attributed.length)]))
                continue
            }
            guard flags.contains(true) else { continue }
            guard let ranges = markedRanges(flags, in: attributed) else { return attributed }
            marks.append((key, ranges))
        }
        let result = NSMutableAttributedString(attributedString: attributed)
        for (key, ranges) in marks {
            for range in ranges { result.addAttribute(key, value: true, range: range) }
        }
        return result
    }

    /// The shows drawn on a line (with `bounds`), or nil when none is or their ownership is
    /// ambiguous; `chosen` when a show also lies in a taller line's bounds. The shows must start
    /// within half an em of the line's left edge, so no show begun on another line draws its first
    /// glyphs.
    private static func lineShows(_ shows: [Show], bounds: CGRect, allBounds: [CGRect],
                                  leftEdge: Bool = true) -> (shows: [Show], chosen: Bool)? {
        guard !shows.isEmpty, shows.count <= 50_000, allBounds.count <= 10_000,
              shows.count * max(1, allBounds.count) <= 4_000_000 else { return nil }
        let area = bounds.insetBy(dx: -0.75, dy: -0.75)
        // A show whose origin lies in several lines' bounds belongs to the clearly tightest of
        // them: a chapter opener's first line is as tall as its 70-point numeral and reaches over
        // the title's second baseline (Fed page 66). Overlaps of lines of like height stay
        // ambiguous, and a line that needed this choice must be confirmed by decoded text.
        var matches: [Show] = [], chosen = false
        for show in shows where area.contains(show.origin) {
            let owners = allBounds.filter { $0.insetBy(dx: -0.75, dy: -0.75).contains(show.origin) }
            guard owners.count > 1 else { matches.append(show); continue }
            let others = owners.filter { $0 != bounds }
            guard others.count == owners.count - 1 else { return nil }
            if others.allSatisfy({ bounds.height < $0.height * 0.75 }) {
                matches.append(show); chosen = true
            } else if others.contains(where: { $0.height < bounds.height * 0.75 }) {
                chosen = true
            } else { return nil }
        }
        guard let left = matches.map(\.origin.x).min(),
              !leftEdge || left - bounds.minX <= max(2, (matches.map(\.size).max() ?? 0) * 0.5) else { return nil }
        return (matches, chosen)
    }

    /// By origin; a show drawn straight after another keeps stream order.
    private static func readingOrder(_ shows: [Show]) -> [Show] {
        shows.enumerated().sorted(by: { ($0.element.origin.x, $0.offset) < ($1.element.origin.x, $1.offset) }).map(\.element)
    }

    /// Whether `repairIndexGlyphs` found index-glyph shows on a line, and rewrote it.
    enum IndexGlyphRepair: Equatable {
        /// No show on the line is drawn in an index-glyph font.
        case none
        /// Every show explains the line and every index glyph has an established character.
        case repaired
        /// An index-glyph show lies on the line but the line could not be rewritten.
        case unrepaired
    }

    /// One glyph as the letters PDFKit reports for it, the text that replaces them (nil: keep
    /// PDFKit's, for a glyph of another font) and whether a word gap precedes it.
    struct IndexGlyphSlot: Equatable {
        var view: [Unicode.Scalar]
        var text: String?
        var wordStart: Bool
    }

    /// The glyphs of a show that PDFKit continues on a following line of the same row (Census page
    /// 12's table rows: one show sets `rnkswp05` and its figures, and PDFKit reads the label and
    /// the figures as two lines).
    struct IndexGlyphCarry: Equatable {
        var slots: [IndexGlyphSlot]
        var row: CGRect
    }

    /// Replaces the characters PDFKit reports for index-named glyphs (#143: U+n for `/G<n>`, or
    /// nothing) with the characters the document established for their codes. The line's shows
    /// (`lineShows`) must all decode and their PDFKit characters, in reading order, must spell
    /// the line apart from whitespace. A glyph PDFKit reports as nothing (TeX's ligatures, `/G31`
    /// for `fi`) joins the glyph before it in its word, or the one after it where it starts a word;
    /// one standing between two word gaps cannot be placed. Characters of other fonts, whitespace
    /// and attributes are kept.
    ///
    /// Glyphs left after the line's last character are returned in `carry`. The next line spells
    /// them first when it continues the row to the right (Census page 17 reads a reference's
    /// number `[6]` as a line of its own), followed by the glyphs of its own shows; otherwise
    /// `abandoned` reports that an earlier line's glyphs went unread.
    static func repairIndexGlyphs(_ shows: [Show], in attributed: NSAttributedString, bounds: CGRect,
                                  allBounds: [CGRect], carry: inout IndexGlyphCarry?)
        -> (text: NSAttributedString, outcome: IndexGlyphRepair, abandoned: Bool) {
        let area = bounds.insetBy(dx: -0.75, dy: -0.75)
        var leading: [IndexGlyphSlot] = [], row = bounds, abandoned = false
        if let pending = carry {
            carry = nil
            if attributed.length > 0, bounds.minX >= pending.row.maxX - 1,
               bounds.midY > pending.row.minY, bounds.midY < pending.row.maxY {
                leading = pending.slots
                row = pending.row.union(bounds)
            } else {
                abandoned = true
            }
        }
        let owned = shows.contains { area.contains($0.origin) }
        guard !leading.isEmpty || shows.contains(where: { $0.indexFont != nil && area.contains($0.origin) }) else {
            return (attributed, .none, abandoned)
        }
        var slots = leading
        if owned {
            // Carried glyphs already start the line, so the line's own shows may start inside it.
            guard let (matches, _) = lineShows(shows, bounds: bounds, allBounds: allBounds, leftEdge: leading.isEmpty),
                  let own = indexGlyphSlots(readingOrder(matches)) else { return (attributed, .unrepaired, abandoned) }
            slots += own
        }
        guard attributed.length > 0, let spelled = spell(attributed, with: slots) else { return (attributed, .unrepaired, abandoned) }
        if spelled.consumed < slots.count {
            carry = IndexGlyphCarry(slots: Array(slots[spelled.consumed...]), row: row)
        }
        return (spelled.text, .repaired, abandoned)
    }

    /// Index-glyph shows whose origin lies in no line: PDFKit reads their glyphs on lines that no
    /// show explains, so those lines cannot be repaired.
    static func unplacedIndexShows(_ shows: [Show], allBounds: [CGRect]) -> Int {
        guard shows.count * max(1, allBounds.count) <= 4_000_000 else { return shows.filter { $0.indexFont != nil }.count }
        return shows.filter { show in
            show.indexFont != nil && !allBounds.contains { $0.insetBy(dx: -0.75, dy: -0.75).contains(show.origin) }
        }.count
    }

    /// The glyphs of shows in reading order, or nil when a glyph has no established character or a
    /// glyph PDFKit reports as nothing has no neighbour in its word to join.
    static func indexGlyphSlots(_ shows: [Show]) -> [IndexGlyphSlot]? {
        var units: [IndexGlyphSlot] = []
        for show in shows {
            if show.indexFont != nil {
                guard let glyphs = show.glyphs, show.text != nil else { return nil }
                var gap = false
                for glyph in glyphs {
                    guard let text = glyph.text else { return nil }
                    // A glyph with a standard name reads as its character; a space glyph separates words.
                    guard let index = glyph.index else {
                        if text.allSatisfy(\.isWhitespace) { gap = true; continue }
                        units.append(IndexGlyphSlot(view: letters(text), text: text, wordStart: glyph.wordStart || gap))
                        gap = false
                        continue
                    }
                    units.append(IndexGlyphSlot(view: letters(pdfKitText(index: index)), text: text, wordStart: glyph.wordStart || gap))
                    gap = false
                }
            } else {
                guard let text = show.text else { return nil }
                units += letters(text).map { IndexGlyphSlot(view: [$0], text: nil, wordStart: false) }
            }
        }
        var slots: [IndexGlyphSlot] = [], pending = ""
        for (position, unit) in units.enumerated() {
            if unit.view.isEmpty {
                guard let text = unit.text else { return nil }
                if pending.isEmpty, !unit.wordStart, let last = slots.last, let before = last.text {
                    slots[slots.count - 1].text = before + text
                } else {
                    guard position + 1 < units.count, !units[position + 1].wordStart, units[position + 1].text != nil else { return nil }
                    pending += text
                }
                continue
            }
            var slot = unit
            if !pending.isEmpty {
                slot.text = pending + (slot.text ?? "")
                pending = ""
            }
            slots.append(slot)
        }
        return pending.isEmpty ? slots : nil
    }

    /// PDFKit's characters of a line rewritten from `slots` consumed in order: each character's
    /// letters must be exactly the letters of the slots it consumes. Nil when they are not, or
    /// when the line holds more characters than the slots.
    private static func spell(_ attributed: NSAttributedString, with slots: [IndexGlyphSlot]) -> (text: NSAttributedString, consumed: Int)? {
        let string = attributed.string as NSString
        var replacements: [(range: NSRange, text: String)] = []
        var next = 0, position = 0
        while position < string.length {
            let range = string.rangeOfComposedCharacterSequence(at: position)
            position = range.location + range.length
            let expected = letters(string.substring(with: range))
            guard !expected.isEmpty else { continue }
            var spelled: [Unicode.Scalar] = [], texts: [String?] = []
            while spelled.count < expected.count, next < slots.count {
                spelled += slots[next].view
                texts.append(slots[next].text)
                next += 1
            }
            guard spelled == expected else { return nil }
            if texts.allSatisfy({ $0 == nil }) { continue }
            guard texts.allSatisfy({ $0 != nil }) else { return nil }
            replacements.append((range, texts.compactMap { $0 }.joined()))
        }
        guard next > 0 else { return nil }
        let result = NSMutableAttributedString(attributedString: attributed)
        for (range, text) in replacements.reversed() where text != string.substring(with: range) {
            result.replaceCharacters(in: range, with: NSAttributedString(string: text,
                attributes: attributed.attributes(at: range.location, effectiveRange: nil)))
        }
        return (result, next)
    }

    /// A line's visible letters: whitespace, attachments and soft hyphens removed, NFKC.
    private static func letters(_ text: String) -> [Unicode.Scalar] {
        text.precomposedStringWithCompatibilityMapping.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0) && $0 != "\u{FFFC}" && $0 != "\u{00AD}"
        }
    }

    /// The character ranges of `attributed` to mark, given each letter's flag in reading order: a
    /// character whose letters are all flagged, and whitespace as PDFKit's runs place it. Nil when
    /// the characters do not align with `flags`.
    private static func markedRanges(_ flags: [Bool], in attributed: NSAttributedString) -> [NSRange]? {
        let string = attributed.string as NSString
        var positions: [(range: NSRange, blank: Bool, marked: Bool)] = []
        var index = 0, position = 0
        while position < string.length {
            let range = string.rangeOfComposedCharacterSequence(at: position)
            let count = letters(string.substring(with: range)).count
            var marked = false
            if count > 0 {
                guard index + count <= flags.count else { return nil }
                marked = flags[index..<(index + count)].allSatisfy { $0 }
                index += count
            }
            positions.append((range, count == 0, marked))
            position = range.location + range.length
        }
        guard index == flags.count else { return nil }
        // Whitespace draws no style, so it follows PDFKit's run: a space inside a run whose other
        // characters are all marked is marked (`Figure 2-8. ` stays one bold run), and one inside a
        // wholly unmarked run or a run of spaces alone is not. In a run PDFKit merged across fonts
        // a space takes the style of the character before it (after it at the start).
        var ranges: [NSRange] = []
        var previous: Bool?
        var runs: [Int: Bool?] = [:]  // run start: all marked, all unmarked, or nil (mixed)
        for (offset, entry) in positions.enumerated() {
            guard entry.blank else {
                previous = entry.marked
                if entry.marked { ranges.append(entry.range) }
                continue
            }
            var run = NSRange()
            _ = attributed.attributes(at: entry.range.location, effectiveRange: &run)
            if runs[run.location] == nil {
                let neighbours = positions.filter { !$0.blank && NSIntersectionRange($0.range, run).length > 0 }
                runs[run.location] = neighbours.isEmpty ? false
                    : neighbours.allSatisfy(\.marked) ? true : neighbours.contains(where: \.marked) ? .some(nil) : false
            }
            let marked = (runs[run.location] ?? nil)
                ?? previous ?? positions[(offset + 1)...].first(where: { !$0.blank })?.marked ?? false
            if marked { ranges.append(entry.range) }
        }
        return ranges
    }
}
