import Foundation
import CoreGraphics

/// Evidence from a font's own resources that a glyph draws a different character than its
/// `ToUnicode` map reports (#217, two of #186's five upstream fixes, ported from the abandoned
/// `claude/fable-agents-coordination-d95da7` branch's commit `3c794a3`). PDFKit's attributed text
/// always reads a glyph through its font's `ToUnicode` map; two kinds of font disagree with what
/// they actually draw:
///
/// - A **dingbat font** (Zapf Dingbats and its clones: Monotype Sorts, `Dingbats`) whose map
///   copies its pictograph codes as if they were ASCII text, so a bullet or arrow is reported as
///   the letter or punctuation mark sharing its code point (the USDA ARS magazine's back cover
///   reads a bullet between two web addresses as a literal `l`).
/// - A **non-symbolic Type 1 font** whose map disagrees with its own `/Encoding` only in letter
///   case: a small-caps credit line reuses a capital letter's code point (its glyph draws the
///   capital) but keeps a `ToUnicode` entry spelling the original word's lower-case letter for
///   copy/paste, so PDFKit reports the word in the wrong case (`BRAD FRITz`).
///
/// This is deliberately a small, narrowly-scoped evidence reader in the mold of
/// `NativeSpacingReader`, not the reference branch's general font/glyph decoder: it reads only
/// simple (Type1/MMType1) and Type0/Identity-H fonts' own resources directly on a page's content
/// stream, follows no Form XObjects, and disqualifies anything it cannot fully decode. It never
/// invents a character; every replacement traces to the font's own map, encoding or name.
enum GlyphIdentityReader {
    struct Show {
        /// Page-space origin of the show, or (for a show drawn straight after another without a
        /// positioning operator) the previous show's origin.
        var origin: CGPoint
        /// The show's text as its font's `ToUnicode` map reports it (PDFKit's own reading).
        var reported: String
        /// The same text with each glyph the font's own evidence contradicts rewritten as drawn.
        /// Never equal to `reported`: a show whose evidence agrees with `ToUnicode` throughout is
        /// not recorded at all.
        var drawn: String
    }

    // MARK: - Font classification

    /// The name without a subset tag (`WVUHWN+`).
    private static func strippedName(_ baseFont: String) -> String {
        guard let plus = baseFont.firstIndex(of: "+"), baseFont.distance(from: baseFont.startIndex, to: plus) == 6,
              baseFont[..<plus].allSatisfy({ $0.isUppercase && $0.isLetter }) else { return baseFont }
        return String(baseFont[baseFont.index(after: plus)...])
    }

    /// Zapf Dingbats and its clones (Monotype Sorts, `Dingbats`), subset tags and case aside.
    private static func isDingbatFamily(_ name: String) -> Bool {
        let letters = strippedName(name).lowercased().filter(\.isLetter)
        return letters.hasPrefix("zapfdingbats") || letters.hasPrefix("itczapfdingbats") || letters == "dingbats"
            || letters.hasPrefix("monotypesorts")
    }

    /// The Zapf Dingbats encoding: Adobe's `a1`-`a191` glyphs by code, as the Adobe Glyph List for
    /// New Fonts maps them. Codes 0x21-0x7E follow the Unicode Dingbats block (U+2700 + code -
    /// 0x20) except where Unicode already held the pictograph (a telephone, pen, star, circle,
    /// square, triangles, diamond, reflex arrow).
    private static let zapfDingbats: [UInt8: String] = {
        var table: [UInt8: String] = [:]
        func set(_ code: Int, _ scalar: Int) { table[UInt8(code)] = String(UnicodeScalar(UInt32(scalar))!) }
        for code in 0x21...0x7E { set(code, 0x2700 + code - 0x20) }
        for (code, scalar) in [(0x25, 0x260E), (0x2A, 0x261B), (0x2B, 0x261E), (0x48, 0x2605), (0x6C, 0x25CF),
                               (0x6E, 0x25A0), (0x73, 0x25B2), (0x74, 0x25BC), (0x75, 0x25C6), (0x77, 0x25D7)] {
            set(code, scalar)
        }
        for code in 0xA1...0xA7 { set(code, 0x2761 + code - 0xA1) }
        for (code, scalar) in [(0xA8, 0x2663), (0xA9, 0x2666), (0xAA, 0x2665), (0xAB, 0x2660)] { set(code, scalar) }
        for code in 0xAC...0xB5 { set(code, 0x2460 + code - 0xAC) }
        for code in 0xB6...0xD4 { set(code, 0x2776 + code - 0xB6) }
        for (code, scalar) in [(0xD5, 0x2192), (0xD6, 0x2194), (0xD7, 0x2195)] { set(code, scalar) }
        for code in 0xD8...0xEF { set(code, 0x2798 + code - 0xD8) }
        for code in 0xF1...0xFE { set(code, 0x27B1 + code - 0xF1) }
        return table
    }()

    /// The printable-ASCII glyph name of every capital and lower-case Latin letter: the only
    /// names a case-disagreement `Differences` entry can vouch for (`encodedUnicodeMap`).
    private static let singleLetterGlyphs: [String: String] = {
        var table: [String: String] = [:]
        for scalar in UInt8(ascii: "A")...UInt8(ascii: "Z") {
            let upper = String(UnicodeScalar(scalar))
            table[upper] = upper
            table[upper.lowercased()] = upper.lowercased()
        }
        return table
    }()

    /// A code's character under a simple font's own `/Encoding` (#217). Every standard base
    /// encoding (`WinAnsiEncoding`, `MacRomanEncoding`, `StandardEncoding`, or the built-in
    /// encoding an absent `/Encoding` key implies) draws printable ASCII at its own code point, so
    /// the base alone fills codes 32-126; a `Differences` array can still reassign any of them to
    /// another glyph, most commonly reusing a capital letter's code for a small-caps run. A
    /// `Differences` name this reader does not recognize (not a bare Latin letter) removes its
    /// code instead of guessing: the case check below only ever trusts a single alphabetic letter
    /// differing from `ToUnicode`, so a base's non-ASCII differences never matter here.
    private static func encodedUnicodeMap(_ dict: CGPDFDictionaryRef) -> [UInt8: String]? {
        var table: [UInt8: String] = [:]
        for code in UInt8(32)...126 { table[code] = String(UnicodeScalar(code)) }
        var plainName: UnsafePointer<CChar>?
        if CGPDFDictionaryGetName(dict, "Encoding", &plainName) { return table }
        var encodingDict: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(dict, "Encoding", &encodingDict), let encodingDict else { return table }
        var array: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(encodingDict, "Differences", &array), let array else { return table }
        let count = CGPDFArrayGetCount(array)
        guard count <= 4096 else { return nil }
        var next = 0
        for index in 0..<count {
            var code: CGPDFInteger = 0, glyph: UnsafePointer<CChar>?
            if CGPDFArrayGetInteger(array, index, &code) {
                guard (0...255).contains(code) else { return nil }
                next = code
            } else if CGPDFArrayGetName(array, index, &glyph), let glyph {
                guard (0...255).contains(next) else { return nil }
                if let letter = singleLetterGlyphs[String(cString: glyph)] { table[UInt8(next)] = letter }
                else { table.removeValue(forKey: UInt8(next)) }
                next += 1
            } else { return nil }
        }
        return table
    }

    /// The glyph names a descriptor's `CharSet` lists (`/parenleft/A/B`).
    private static func charSet(_ descriptor: CGPDFDictionaryRef) -> Set<String>? {
        var value: CGPDFStringRef?
        guard CGPDFDictionaryGetString(descriptor, "CharSet", &value), let value,
              let text = CGPDFStringCopyTextString(value) as String?, text.utf16.count <= 65_536 else { return nil }
        return Set(text.split(separator: "/").map(String.init).filter { !$0.isEmpty && $0.count <= 64 })
    }

    /// A `ToUnicode` CMap's one-value `bfchar` entries, keyed by their code (`codeDigits` hex
    /// digits: 2 for a simple font's one-byte codes, 4 for a Type0/Identity-H font's two-byte
    /// codes). Only complete bfchar blocks whose value is a single UTF-16 code unit are supported;
    /// a range, an inherited map or an unsupported entry fails the whole map, so a font this
    /// cannot fully read supplies no evidence. Unlike `NativeSpacingReader.characterMap`, any
    /// declared codespace is accepted: the Agricultural Research magazine's own Helvetica-Condensed
    /// credit font declares a two-byte codespace but still writes one-byte `bfchar` codes.
    private static func bfCharMap(_ data: Data, codeDigits: Int) -> [UInt32: String]? {
        guard data.count <= 65_536, let input = String(data: data, encoding: .ascii) else { return nil }
        let text = input.replacingOccurrences(of: "%[^\\r\\n]*", with: "", options: .regularExpression)
        guard !text.contains("beginbfrange"), !text.contains("usecmap") else { return nil }
        let blocks = try! NSRegularExpression(pattern: #"(\d+)\s+beginbfchar\s*([\s\S]*?)\s*endbfchar"#)
        let pairs = try! NSRegularExpression(pattern: "<([0-9a-fA-F]{\(codeDigits)})>\\s*<([0-9a-fA-F]{4})>")
        let ns = text as NSString
        let matches = blocks.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty, matches.count <= 256,
              matches.count == text.components(separatedBy: "beginbfchar").count - 1 else { return nil }
        var result: [UInt32: String] = [:]
        for block in matches {
            let body = ns.substring(with: block.range(at: 2)), bodyNS = body as NSString
            let entries = pairs.matches(in: body, range: NSRange(location: 0, length: bodyNS.length))
            guard Int(ns.substring(with: block.range(at: 1))) == entries.count,
                  pairs.stringByReplacingMatches(in: body, range: NSRange(location: 0, length: bodyNS.length), withTemplate: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            for entry in entries {
                guard let code = UInt32(bodyNS.substring(with: entry.range(at: 1)), radix: 16), result[code] == nil else { return nil }
                guard let value = UInt32(bodyNS.substring(with: entry.range(at: 2)), radix: 16),
                      let scalar = UnicodeScalar(value) else { return nil }
                result[code] = String(scalar)
            }
        }
        return result.isEmpty ? nil : result
    }

    private struct FontInfo {
        var wide: Bool
        var unicode: [UInt16: String]
        var isDingbat: Bool
        var encoded: [UInt8: String]?
        var charSet: Set<String>?
    }

    private static func name(_ dict: CGPDFDictionaryRef, _ key: String) -> String? {
        var value: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(dict, key, &value), let value else { return nil }
        return String(cString: value)
    }

    /// A font's evidence, or nil for a font this reader has nothing to check (not a dingbat
    /// family and not a non-symbolic Type1/MMType1 font, or its `ToUnicode` map cannot be fully
    /// read). The case check is gated on the descriptor's `Flags`: bit 6 (Nonsymbolic, 32) set and
    /// bit 3 (Symbolic, 4) clear, matching a plain text font whose encoding names ordinary letters.
    private static func fontInfo(_ dict: CGPDFDictionaryRef) -> FontInfo? {
        guard let subtype = name(dict, "Subtype") else { return nil }
        let wide = subtype == "Type0"
        var names: [String] = []
        if let base = name(dict, "BaseFont") { names.append(base) }
        var descriptorOwner = dict
        if wide {
            var descendants: CGPDFArrayRef?, first: CGPDFDictionaryRef?
            guard let encoding = name(dict, "Encoding"), encoding == "Identity-H" || encoding == "Identity-V",
                  CGPDFDictionaryGetArray(dict, "DescendantFonts", &descendants), let descendants,
                  CGPDFArrayGetCount(descendants) >= 1, CGPDFArrayGetDictionary(descendants, 0, &first), let first
            else { return nil }
            descriptorOwner = first
        }
        var descriptor: CGPDFDictionaryRef?
        _ = CGPDFDictionaryGetDictionary(descriptorOwner, "FontDescriptor", &descriptor)
        var flags: Int?
        if let descriptor {
            if let fontName = name(descriptor, "FontName") { names.append(fontName) }
            var family: CGPDFStringRef?
            if CGPDFDictionaryGetString(descriptor, "FontFamily", &family), let family,
               let text = CGPDFStringCopyTextString(family) as String? { names.append(text) }
            var value: CGPDFInteger = 0
            if CGPDFDictionaryGetInteger(descriptor, "Flags", &value) { flags = value }
        }
        let isDingbat = names.contains(where: isDingbatFamily)
        let caseCheckCandidate = !wide && ["Type1", "MMType1"].contains(subtype)
            && flags.map { $0 & 32 != 0 && $0 & 4 == 0 } == true
        guard isDingbat || caseCheckCandidate else { return nil }
        var stream: CGPDFStreamRef?
        guard CGPDFDictionaryGetStream(dict, "ToUnicode", &stream), let stream else { return nil }
        var format = CGPDFDataFormat.raw
        guard let data = CGPDFStreamCopyData(stream, &format), format == .raw,
              let map = bfCharMap(data as Data, codeDigits: wide ? 4 : 2) else { return nil }
        let unicode = Dictionary(uniqueKeysWithValues: map.map { (UInt16($0.key), $0.value) })
        var encoded: [UInt8: String]?
        var charSet: Set<String>?
        if caseCheckCandidate {
            guard let table = encodedUnicodeMap(dict) else { return nil }
            encoded = table
            charSet = descriptor.flatMap(Self.charSet)
        }
        return FontInfo(wide: wide, unicode: unicode, isDingbat: isDingbat, encoded: encoded, charSet: charSet)
    }

    /// The character a glyph draws, where the font's own evidence contradicts `reported` (its
    /// `ToUnicode` character): a dingbat font's pictograph for the ASCII code `reported` names, or
    /// a case-check font's `Differences`/base-encoded letter, guarded to a single ASCII letter
    /// differing from `reported` only in case and, where the descriptor lists a `CharSet`, listing
    /// the drawn letter but not the reported one.
    private static func drawnCharacter(_ code: UInt16, reported: String, font: FontInfo) -> String {
        if font.isDingbat, reported.unicodeScalars.count == 1, let scalar = reported.unicodeScalars.first,
           scalar.value <= 0xFF, let pictograph = zapfDingbats[UInt8(scalar.value)] {
            return pictograph
        }
        if let encoded = font.encoded, code <= 0xFF, let candidate = encoded[UInt8(code)], candidate != reported,
           reported.count == 1, candidate.count == 1,
           let r = reported.unicodeScalars.first, let d = candidate.unicodeScalars.first,
           r.isASCII, d.isASCII, r.properties.isAlphabetic, d.properties.isAlphabetic,
           reported.lowercased() == candidate.lowercased(),
           font.charSet.map({ $0.contains(candidate) && !$0.contains(reported) }) ?? true {
            return candidate
        }
        return reported
    }

    // MARK: - Page scan

    private final class State {
        var matrix = CGAffineTransform.identity
        var line = CGAffineTransform.identity
        var font: FontInfo?
        var size: CGFloat = 0
        var leading: CGFloat = 0
        var saved: [(CGAffineTransform, FontInfo?, CGFloat, CGFloat)] = []
        var inText = false
        var positioned = false
        var lastOrigin: CGPoint?
        var invalid = false
        var operations = 0
        var fonts: [Int: FontInfo?] = [:]
        var shows: [Show] = []

        func accept(_ scanner: CGPDFScannerRef) -> Bool {
            operations += 1
            if operations > 200_000 || Task.isCancelled { invalid = true }
            if invalid { CGPDFScannerStop(scanner) }
            return !invalid
        }

        func show(_ scanner: CGPDFScannerRef, array: Bool) {
            guard accept(scanner), inText, shows.count < 10_000 else { invalid = true; return }
            let transform = line.concatenating(matrix)
            guard transform.tx.isFinite, transform.ty.isFinite, transform.a.isFinite, transform.d.isFinite else {
                positioned = false; return
            }
            // Rotated or mirrored text supplies no evidence for upright lines.
            guard transform.b == 0, transform.c == 0, transform.a > 0, transform.d > 0 else {
                positioned = false; lastOrigin = nil; return
            }
            let origin: CGPoint
            if positioned { origin = CGPoint(x: transform.tx, y: transform.ty) }
            else if let last = lastOrigin { origin = last }
            else { positioned = false; return }
            positioned = false
            lastOrigin = origin
            guard let font else { return }
            var reported = "", drawn = "", ok = true
            func append(_ string: CGPDFStringRef) {
                let count = CGPDFStringGetLength(string)
                guard let bytes = CGPDFStringGetBytePtr(string), count <= 4096 else { ok = false; return }
                if font.wide {
                    guard count % 2 == 0 else { ok = false; return }
                    var index = 0
                    while index < count {
                        let code = UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1])
                        guard let r = font.unicode[code], reported.utf16.count < 8192 else { ok = false; return }
                        reported += r
                        drawn += drawnCharacter(code, reported: r, font: font)
                        index += 2
                    }
                } else {
                    for index in 0..<count {
                        let code = UInt16(bytes[index])
                        guard let r = font.unicode[code], reported.utf16.count < 8192 else { ok = false; return }
                        reported += r
                        drawn += drawnCharacter(code, reported: r, font: font)
                    }
                }
            }
            if array {
                var values: CGPDFArrayRef?
                guard CGPDFScannerPopArray(scanner, &values), let values, CGPDFArrayGetCount(values) <= 4096 else {
                    invalid = true; return
                }
                for i in 0..<CGPDFArrayGetCount(values) {
                    var string: CGPDFStringRef?
                    if CGPDFArrayGetString(values, i, &string), let string { append(string) }
                }
            } else {
                var string: CGPDFStringRef?
                guard CGPDFScannerPopString(scanner, &string), let string else { invalid = true; return }
                append(string)
            }
            guard ok, !reported.isEmpty, drawn != reported else { return }
            shows.append(Show(origin: origin, reported: reported, drawn: drawn))
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

    private static func makeTable() -> CGPDFOperatorTableRef? {
        guard let table = CGPDFOperatorTableCreate() else { return nil }
        CGPDFOperatorTableSetCallback(table, "q") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), s.saved.count < 256 else { s.invalid = true; return }
            s.saved.append((s.matrix, s.font, s.size, s.leading))
        }
        CGPDFOperatorTableSetCallback(table, "Q") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), let saved = s.saved.popLast() else { s.invalid = true; return }
            (s.matrix, s.font, s.size, s.leading) = saved
        }
        CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), let n = Self.numbers(scanner, 6) else { s.invalid = true; return }
            s.matrix = CGAffineTransform(a: n[0], b: n[1], c: n[2], d: n[3], tx: n[4], ty: n[5]).concatenating(s.matrix)
        }
        CGPDFOperatorTableSetCallback(table, "Tf") { scanner, info in
            let s = Self.state(info)
            var fontName: UnsafePointer<CChar>?, dict: CGPDFDictionaryRef?
            guard s.accept(scanner), let n = Self.numbers(scanner, 1),
                  CGPDFScannerPopName(scanner, &fontName), let fontName else { s.invalid = true; return }
            s.size = n[0]
            guard let object = CGPDFContentStreamGetResource(CGPDFScannerGetContentStream(scanner), "Font", fontName),
                  CGPDFObjectGetValue(object, .dictionary, &dict), let dict else { s.font = nil; return }
            let id = unsafeBitCast(dict, to: Int.self)
            if let cached = s.fonts[id] { s.font = cached }
            else {
                guard s.fonts.count < 1024 else { s.invalid = true; return }
                let info = Self.fontInfo(dict)
                s.fonts[id] = info
                s.font = info
            }
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
        // Numeric TJ adjustments carry no text; this reader tracks no advance or spacing, only
        // each show's decoded content and origin.
        CGPDFOperatorTableSetCallback(table, "TJ") { scanner, info in Self.state(info).show(scanner, array: true) }
        CGPDFOperatorTableSetCallback(table, "Tj") { scanner, info in Self.state(info).show(scanner, array: false) }
        return table
    }

    private final class FontPresence { var found = false }

    /// Whether any font resource on `page` is a dingbat family or a non-symbolic Type1/MMType1
    /// font: the only fonts this reader can ever flag. Skips the full content-stream scan on the
    /// vast majority of pages, which have neither.
    private static func hasCandidateFont(_ page: CGPDFPage) -> Bool {
        var node: CGPDFDictionaryRef? = page.dictionary
        for _ in 0..<64 {
            guard let current = node else { return false }
            var resources: CGPDFDictionaryRef?, fontsDict: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(current, "Resources", &resources), let resources {
                guard CGPDFDictionaryGetDictionary(resources, "Font", &fontsDict), let fontsDict else { return false }
                let presence = FontPresence()
                CGPDFDictionaryApplyFunction(fontsDict, { _, object, info in
                    var dict: CGPDFDictionaryRef?
                    guard CGPDFObjectGetValue(object, .dictionary, &dict), let dict else { return }
                    if Self.fontInfo(dict) != nil {
                        Unmanaged<FontPresence>.fromOpaque(info!).takeUnretainedValue().found = true
                    }
                }, Unmanaged.passUnretained(presence).toOpaque())
                return presence.found
            }
            var parent: CGPDFDictionaryRef?
            _ = CGPDFDictionaryGetDictionary(current, "Parent", &parent)
            node = parent
        }
        return false
    }

    /// The page's shows whose drawn text differs from what their font's `ToUnicode` map reports,
    /// or none when the page has no candidate font, its content stream cannot be scanned, or it is
    /// rotated (this reader's transform math assumes an upright page, matching
    /// `NativeSpacingReader`). This reader follows no Form XObjects: both motivating fixes (the
    /// magazine's back-cover bullet and its page-15 photo credit) draw directly on their own
    /// page's content stream.
    static func read(_ page: CGPDFPage) -> [Show] {
        guard page.rotationAngle == 0, hasCandidateFont(page), let table = makeTable() else { return [] }
        defer { CGPDFOperatorTableRelease(table) }
        let s = State()
        let stream = CGPDFContentStreamCreateWithPage(page)
        defer { CGPDFContentStreamRelease(stream) }
        let scanner = CGPDFScannerCreate(stream, table, Unmanaged.passUnretained(s).toOpaque())
        defer { CGPDFScannerRelease(scanner) }
        guard CGPDFScannerScan(scanner), !s.invalid, s.saved.isEmpty, !s.inText else { return [] }
        return s.shows
    }

    // MARK: - Lines

    /// Set on a character this reader rewrote where the reported text it replaced also stood on
    /// its own between word spaces (or a line edge), e.g. the magazine's bullet, printed between
    /// two spaces, misread as the letter `l`. A lone dingbat pictograph is not an inline
    /// superscript or subscript, however its substituted font's metrics happen to place it
    /// (`NativeTextReader.inlineText` consults this attribute).
    static let isolatedAttribute = NSAttributedString.Key("PDFReflowGlyphIsolated")

    /// Every range of `text` in `attributed`, and whether it stands alone between word spaces (or
    /// a line edge) on both sides.
    private static func occurrences(_ text: String, in attributed: NSAttributedString) -> [(range: NSRange, isolated: Bool)] {
        guard !text.isEmpty, text.utf16.count <= attributed.length else { return [] }
        let string = attributed.string as NSString
        var ranges: [NSRange] = []
        var start = 0
        while start <= string.length {
            let found = string.range(of: text, options: [], range: NSRange(location: start, length: string.length - start))
            guard found.location != NSNotFound else { break }
            ranges.append(found)
            start = found.location + max(found.length, 1)
        }
        func whitespace(at index: Int) -> Bool {
            guard index >= 0, index < string.length else { return true }
            guard let scalar = UnicodeScalar(UInt32(string.character(at: index))) else { return false }
            return CharacterSet.whitespacesAndNewlines.contains(scalar)
        }
        return ranges.map { ($0, whitespace(at: $0.location - 1) && whitespace(at: $0.location + $0.length)) }
    }

    /// The one range of `text` to rewrite in `attributed`: its only occurrence, or, where it
    /// occurs more than once (the magazine's back cover also spells `l` twice within `Follow`),
    /// the one occurrence that stands alone between word spaces — matching how the reported text
    /// of a redrawn glyph actually appears on its line. More than one such occurrence, or none,
    /// leaves the ambiguity unresolved.
    private static func candidateRange(_ text: String, in attributed: NSAttributedString) -> (range: NSRange, isolated: Bool)? {
        let found = occurrences(text, in: attributed)
        if found.count == 1 { return found[0] }
        let isolated = found.filter(\.isolated)
        return isolated.count == 1 ? isolated[0] : nil
    }

    /// Rewrites `attributed` (a PDFKit line with `bounds`) wherever exactly one show's origin lies
    /// in its bounds and in no other line's, and that show's reported text has exactly one
    /// unambiguous occurrence in the line (`candidateRange`). Anything else (no unique show, an
    /// ambiguous or missing occurrence) leaves the line as PDFKit read it: this reader would
    /// rather miss a fix than risk rewriting the wrong text.
    static func apply(_ shows: [Show], to attributed: NSAttributedString, bounds: CGRect,
                      allBounds: [CGRect]) -> NSAttributedString {
        guard !shows.isEmpty, shows.count <= 10_000, allBounds.count <= 10_000,
              shows.count * max(1, allBounds.count) <= 2_000_000 else { return attributed }
        let area = bounds.insetBy(dx: -0.75, dy: -0.75)
        let matches = shows.filter { area.contains($0.origin) }
        guard matches.count == 1, let match = matches.first,
              allBounds.filter({ $0.insetBy(dx: -0.75, dy: -0.75).contains(match.origin) }).count == 1,
              let (range, isolated) = candidateRange(match.reported, in: attributed)
        else { return attributed }
        let result = NSMutableAttributedString(attributedString: attributed)
        result.replaceCharacters(in: range, with: match.drawn)
        if isolated {
            let drawnRange = NSRange(location: range.location, length: (match.drawn as NSString).length)
            result.addAttribute(isolatedAttribute, value: true, range: drawnRange)
        }
        return result
    }
}
