import Foundation
import CoreGraphics

/// Repairs PDFKit word boundaries only where a supported text-show operation contradicts them:
/// it removes spaces that a Type3 TJ array places inside a word, and inserts the space that a
/// font change hides (a mathematical variable set in its own font, followed by prose at a
/// word-sized gap). This is deliberately a small evidence reader, not a replacement text
/// extractor.
enum NativeSpacingReader {
    struct Evidence {
        var origin: CGPoint
        var text: String?
        // UTF-16 boundaries with a positive gap of at most 0.01 em in the source TJ array.
        var smallGaps: Set<Int> = []
        /// The show decoded through any supported one-byte ToUnicode map; nil when a code
        /// has no mapping or the map is unsupported.
        var unicode: String?
        /// Page-space x where the show's glyph advances end; nil without complete widths.
        var end: CGFloat?
        /// Font size in page space and the font resource's identity, for gap and boundary tests.
        var size: CGFloat = 0
        var font: Int = 0

        func extraSpaces(in native: String) -> [Int]? {
            guard let text else { return nil }
            let source = Array(text.utf16), extracted = Array(native.utf16)
            var i = 0, j = 0, removed: [Int] = []
            func letter(_ value: UInt16) -> Bool { (65...90).contains(value) || (97...122).contains(value) }
            while i < source.count, j < extracted.count {
                if source[i] == extracted[j] { i += 1; j += 1; continue }
                guard extracted[j] == 32, i > 0, smallGaps.contains(i),
                      letter(source[i - 1]), letter(source[i]),
                      j + 1 < extracted.count, extracted[j + 1] == source[i] else { return nil }
                removed.append(j); j += 1
            }
            return i == source.count && j == extracted.count && !removed.isEmpty ? removed : nil
        }
    }

    /// Word boundaries that PDFKit drops at a font change: two consecutive shows on one
    /// baseline in different fonts, separated by at least 0.15 em (TeX's interword glue can
    /// shrink to about 0.17 em), with a letter or digit on either side. Returns the UTF-16
    /// offsets in `native` where a space is missing, or nil unless the shows spell the line
    /// exactly apart from PDFKit's own spaces.
    static func missingSpaces(in native: String, shows: [Evidence]) -> [Int]? {
        var source: [UInt16] = [], boundaries: Set<Int> = []
        var previous: Evidence?
        func word(_ character: Character?) -> Bool { character.map { $0.isLetter || $0.isNumber } ?? false }
        for show in shows.sorted(by: { $0.origin.x < $1.origin.x }) {
            guard let unicode = show.unicode, !unicode.isEmpty, source.count + unicode.utf16.count <= 8192 else { return nil }
            if let previous, let end = previous.end, previous.font != show.font,
               abs(previous.origin.y - show.origin.y) <= max(previous.size, show.size) * 0.1,
               show.origin.x - end >= max(previous.size, show.size) * 0.15,
               word(previous.unicode?.last), word(unicode.first) {
                boundaries.insert(source.count)
            }
            source += unicode.utf16
            previous = show
        }
        guard !boundaries.isEmpty else { return nil }
        let extracted = Array(native.utf16)
        func whitespace(_ value: UInt16) -> Bool {
            UnicodeScalar(value).map { CharacterSet.whitespacesAndNewlines.contains($0) } ?? false
        }
        var i = 0, j = 0, inserted: [Int] = []
        while i < source.count, j < extracted.count {
            if source[i] == extracted[j] {
                if boundaries.contains(i), j > 0, !whitespace(extracted[j - 1]) { inserted.append(j) }
                i += 1; j += 1
            } else if whitespace(extracted[j]) {
                j += 1
            } else { return nil }
        }
        while j < extracted.count, whitespace(extracted[j]) { j += 1 }
        return i == source.count && j == extracted.count && !inserted.isEmpty ? inserted : nil
    }

    /// Only complete one-byte bfchar maps are supported. Ranges, inherited maps, duplicate
    /// codes, ligatures and non-ASCII text fall back. A final mapped line break is tolerated.
    static func characterMap(_ data: Data) -> [UInt8: String]? {
        guard data.count <= 65_536, let input = String(data: data, encoding: .ascii) else { return nil }
        let text = input.replacingOccurrences(of: "%[^\\r\\n]*", with: "", options: .regularExpression)
        guard !text.contains("beginbfrange"), !text.contains("usecmap"),
              text.components(separatedBy: "begincodespacerange").count == 2,
              text.range(of: #"1\s+begincodespacerange\s*<00>\s*<[fF][fF]>\s*endcodespacerange"#,
                         options: .regularExpression) != nil else { return nil }
        let blocks = try! NSRegularExpression(pattern: #"(\d+)\s+beginbfchar\s*([\s\S]*?)\s*endbfchar"#)
        let pairs = try! NSRegularExpression(pattern: #"<([0-9a-fA-F]{2})>\s*<([0-9a-fA-F]{4}(?:000[Aa])?)>"#)
        let ns = text as NSString
        let matches = blocks.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty, matches.count <= 256,
              matches.count == text.components(separatedBy: "beginbfchar").count - 1 else { return nil }
        var result: [UInt8: String] = [:]
        for block in matches {
            let body = ns.substring(with: block.range(at: 2)), bodyNS = ns.substring(with: block.range(at: 2)) as NSString
            let entries = pairs.matches(in: body, range: NSRange(location: 0, length: bodyNS.length))
            guard Int(ns.substring(with: block.range(at: 1))) == entries.count,
                  pairs.stringByReplacingMatches(in: body, range: NSRange(location: 0, length: bodyNS.length), withTemplate: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            for entry in entries {
                guard let code = UInt8(bodyNS.substring(with: entry.range(at: 1)), radix: 16), result[code] == nil else { return nil }
                let hex = bodyNS.substring(with: entry.range(at: 2))
                guard let value = UInt32(hex.prefix(4), radix: 16), let scalar = UnicodeScalar(value) else { return nil }
                // Keep the entire map, but unsupported characters disqualify a show that uses them.
                result[code] = String(scalar) + (hex.count == 8 ? "\n" : "")
            }
        }
        return result
    }

    /// A one-byte ToUnicode map with bfchar and bfrange entries whose destinations are any
    /// number of UTF-16 code units (ligatures, surrogate pairs for mathematical alphanumerics).
    /// Inherited maps, multi-byte codespaces, duplicate codes and malformed entries fall back.
    static func unicodeMap(_ data: Data) -> [UInt8: String]? {
        guard data.count <= 65_536, let input = String(data: data, encoding: .isoLatin1) else { return nil }
        let text = input.replacingOccurrences(of: "%[^\\r\\n]*", with: "", options: .regularExpression)
        guard !text.contains("usecmap"), text.contains("begincmap"),
              text.components(separatedBy: "begincodespacerange").count == 2,
              text.range(of: #"begincodespacerange\s*<[0-9a-fA-F]{2}>\s*<[0-9a-fA-F]{2}>\s*endcodespacerange"#,
                         options: .regularExpression) != nil else { return nil }
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
        func string(_ values: [UInt16]) -> String? {
            let value = String(utf16CodeUnits: values, count: values.count)
            return Array(value.utf16) == values ? value : nil
        }
        var result: [UInt8: String] = [:]
        func assign(_ code: Int, _ values: [UInt16]) -> Bool {
            guard (0...255).contains(code), result[UInt8(code)] == nil, let value = string(values) else { return false }
            result[UInt8(code)] = value
            return true
        }
        let ns = text as NSString
        let blocks = try! NSRegularExpression(pattern: #"(\d+)\s+begin(bfchar|bfrange)\s*([\s\S]*?)\s*end\2"#)
        let chars = try! NSRegularExpression(pattern: #"<([0-9a-fA-F]{2})>\s*<([0-9a-fA-F]+)>"#)
        let ranges = try! NSRegularExpression(
            pattern: #"<([0-9a-fA-F]{2})>\s*<([0-9a-fA-F]{2})>\s*(?:<([0-9a-fA-F]+)>|\[((?:\s*<[0-9a-fA-F]+>)+)\s*\])"#)
        let hexes = try! NSRegularExpression(pattern: #"<([0-9a-fA-F]+)>"#)
        let matches = blocks.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty, matches.count <= 256,
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
                guard let high = Int(body.substring(with: entry.range(at: 2)), radix: 16), high >= low else { return nil }
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

    private struct Font {
        var id: Int
        /// The Type3 identity-matrix bfchar map that authorizes space removal.
        var map: [UInt8: String]?
        /// Any supported one-byte ToUnicode map, for word-boundary evidence.
        var unicode: [UInt8: String]?
        /// Simple-font glyph advances in text space per unit of font size.
        var widths: [UInt8: CGFloat]?
    }
    private final class State {
        var matrix = CGAffineTransform.identity
        var line = CGAffineTransform.identity
        var font: Font?
        var size: CGFloat = 0
        var leading: CGFloat = 0
        var saved: [(CGAffineTransform, Font?, CGFloat, CGFloat)] = []
        var inText = false
        var positioned = false
        var invalid = false
        var operations = 0
        var fontSelections = 0
        var fonts: [Int: Font?] = [:]
        var evidence: [Evidence] = []

        func accept(_ scanner: CGPDFScannerRef) -> Bool {
            operations += 1
            if operations > 100_000 || Task.isCancelled { invalid = true }
            if invalid { CGPDFScannerStop(scanner) }
            return !invalid
        }
        func show(_ scanner: CGPDFScannerRef, array: Bool) {
            guard accept(scanner), inText, evidence.count < 10_000 else { invalid = true; return }
            // Consume the operands before any other check so the scanner's stack stays consistent.
            var values: CGPDFArrayRef?, single: CGPDFStringRef?
            if array {
                guard CGPDFScannerPopArray(scanner, &values), let values,
                      CGPDFArrayGetCount(values) <= 4096 else { invalid = true; return }
            } else {
                guard CGPDFScannerPopString(scanner, &single), single != nil else { invalid = true; return }
            }
            guard positioned else { invalid = true; return }
            positioned = false
            let transform = line.concatenating(matrix)
            guard transform.tx.isFinite, transform.ty.isFinite, transform.a.isFinite else { invalid = true; return }
            // Rotated or mirrored text (a margin stamp) supplies no word-boundary evidence and
            // does not disqualify the page's upright text.
            guard transform.b == 0, transform.c == 0, transform.a > 0, transform.d > 0 else { return }
            var item = Evidence(origin: CGPoint(x: transform.tx, y: transform.ty), size: size * transform.a, font: font?.id ?? 0)
            var value = "", gaps: Set<Int> = [], valid = font?.map != nil && size > 0
            var unicode = "", advance: CGFloat = 0
            var decodable = font?.unicode != nil && size > 0, measurable = font?.widths != nil && size > 0
            func append(_ string: CGPDFStringRef) {
                let count = CGPDFStringGetLength(string)
                guard count <= 4096, value.utf16.count + count <= 4096,
                      let bytes = CGPDFStringGetBytePtr(string), let font else {
                    valid = false; decodable = false; measurable = false; return
                }
                for index in 0..<count {
                    let code = bytes[index]
                    if valid, let decoded = font.map?[code] { value += decoded } else { valid = false }
                    if decodable, let decoded = font.unicode?[code], unicode.utf16.count + decoded.utf16.count <= 4096 {
                        unicode += decoded
                    } else { decodable = false }
                    if measurable, let width = font.widths?[code] { advance += width * size } else { measurable = false }
                }
            }
            if let values {
                var previousWasString = false
                for i in 0..<CGPDFArrayGetCount(values) {
                    var string: CGPDFStringRef?
                    var number: CGPDFReal = 0
                    if CGPDFArrayGetString(values, i, &string), let string {
                        append(string); previousWasString = true
                    } else if CGPDFArrayGetNumber(values, i, &number), number.isFinite {
                        // Consecutive/initial adjustments and actual word-size gaps are ambiguous.
                        if !previousWasString || number < -10 { valid = false }
                        if number < 0 && number >= -10 { gaps.insert(value.utf16.count) }
                        previousWasString = false
                        advance -= number / 1000 * size
                    } else { valid = false; decodable = false; measurable = false }
                }
            } else if let single {
                append(single)
            }
            if value.hasSuffix("\n") { value.removeLast() }
            if valid, !value.isEmpty, value.utf16.allSatisfy({ (32...126).contains($0) }) {
                item.text = value; item.smallGaps = gaps
            }
            if decodable, !unicode.isEmpty { item.unicode = unicode }
            if measurable, advance.isFinite, advance >= 0 { item.end = transform.tx + advance * transform.a }
            evidence.append(item)
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
    private static func unicodeData(_ dict: CGPDFDictionaryRef) -> Data? {
        var stream: CGPDFStreamRef?
        var format = CGPDFDataFormat.raw
        guard CGPDFDictionaryGetStream(dict, "ToUnicode", &stream), let stream,
              let data = CGPDFStreamCopyData(stream, &format), format == .raw else { return nil }
        return data as Data
    }
    private static func font(_ dict: CGPDFDictionaryRef) -> Font? {
        var subtype: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(dict, "Subtype", &subtype), let subtype else { return nil }
        // The dictionary's identity distinguishes fonts; the value is never dereferenced.
        var result = Font(id: unsafeBitCast(dict, to: Int.self))
        let kind = String(cString: subtype)
        let data = unicodeData(dict)
        if kind == "Type3" {
            var matrix: CGPDFArrayRef?
            var identity = CGPDFDictionaryGetArray(dict, "FontMatrix", &matrix) && matrix.map { CGPDFArrayGetCount($0) == 6 } == true
            for (i, expected) in [1.0, 0, 0, 1, 0, 0].enumerated() where identity {
                var number: CGPDFReal = 0
                identity = CGPDFArrayGetNumber(matrix!, i, &number) && number == expected
            }
            if identity, let data { result.map = characterMap(data) }
            return result
        }
        guard ["Type1", "TrueType", "MMType1"].contains(kind) else { return result }
        if let data { result.unicode = unicodeMap(data) }
        var first: CGPDFInteger = 0, widths: CGPDFArrayRef?
        if CGPDFDictionaryGetInteger(dict, "FirstChar", &first), first >= 0, first <= 255,
           CGPDFDictionaryGetArray(dict, "Widths", &widths), let widths, CGPDFArrayGetCount(widths) <= 256 {
            var table: [UInt8: CGFloat] = [:]
            for index in 0..<CGPDFArrayGetCount(widths) where first + index <= 255 {
                var width: CGPDFReal = 0
                guard CGPDFArrayGetNumber(widths, index, &width), width.isFinite, width >= 0 else { table = [:]; break }
                table[UInt8(first + index)] = width / 1000
            }
            if !table.isEmpty { result.widths = table }
        }
        return result
    }

    private final class FontPresence { var found = false }
    /// A Type3 font, or a simple font whose ToUnicode map and Widths can supply word-boundary
    /// evidence. Pages without either skip the operator scan entirely.
    private static func hasSupportedFont(_ page: CGPDFPage) -> Bool {
        var node: CGPDFDictionaryRef? = page.dictionary
        for _ in 0..<64 {
            guard let current = node else { return false }
            var resources: CGPDFDictionaryRef?, fonts: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(current, "Resources", &resources), let resources {
                guard CGPDFDictionaryGetDictionary(resources, "Font", &fonts), let fonts else { return false }
                let presence = FontPresence()
                CGPDFDictionaryApplyFunction(fonts, { _, object, info in
                    var dict: CGPDFDictionaryRef?, subtype: UnsafePointer<CChar>?, stream: CGPDFStreamRef?, widths: CGPDFArrayRef?
                    guard CGPDFObjectGetValue(object, .dictionary, &dict), let dict,
                          CGPDFDictionaryGetName(dict, "Subtype", &subtype), let subtype else { return }
                    let kind = String(cString: subtype)
                    let simple = ["Type1", "TrueType", "MMType1"].contains(kind)
                        && CGPDFDictionaryGetStream(dict, "ToUnicode", &stream)
                        && CGPDFDictionaryGetArray(dict, "Widths", &widths)
                    if kind == "Type3" || simple {
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

    static func read(_ page: CGPDFPage) -> [Evidence] {
        guard page.rotationAngle == 0, hasSupportedFont(page), let table = CGPDFOperatorTableCreate() else { return [] }
        defer { CGPDFOperatorTableRelease(table) }
        CGPDFOperatorTableSetCallback(table, "q") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), !s.inText, s.saved.count < 128 else { s.invalid = true; return }
            s.saved.append((s.matrix, s.font, s.size, s.leading))
        }
        CGPDFOperatorTableSetCallback(table, "Q") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), !s.inText, let saved = s.saved.popLast() else { s.invalid = true; return }
            (s.matrix, s.font, s.size, s.leading) = saved
        }
        CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), !s.inText, let n = Self.numbers(scanner, 6) else { s.invalid = true; return }
            s.matrix = CGAffineTransform(a: n[0], b: n[1], c: n[2], d: n[3], tx: n[4], ty: n[5]).concatenating(s.matrix)
        }
        // TeX output reselects a font at every mathematical symbol, so a page can carry
        // hundreds of selections; each distinct font dictionary is parsed once.
        CGPDFOperatorTableSetCallback(table, "Tf") { scanner, info in
            let s = Self.state(info)
            s.fontSelections += 1
            var name: UnsafePointer<CChar>?, dict: CGPDFDictionaryRef?
            guard s.accept(scanner), s.fontSelections <= 10_000,
                  let n = Self.numbers(scanner, 1), CGPDFScannerPopName(scanner, &name), let name,
                  let object = CGPDFContentStreamGetResource(CGPDFScannerGetContentStream(scanner), "Font", name),
                  CGPDFObjectGetValue(object, .dictionary, &dict), let dict else {
                s.invalid = true; return
            }
            s.size = n[0]
            let id = unsafeBitCast(dict, to: Int.self)
            if let cached = s.fonts[id] { s.font = cached } else {
                guard s.fonts.count < 256 else { s.invalid = true; return }
                s.font = Self.font(dict); s.fonts[id] = s.font
            }
        }
        CGPDFOperatorTableSetCallback(table, "BT") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), !s.inText else { s.invalid = true; return }
            s.inText = true; s.line = .identity; s.positioned = false
        }
        CGPDFOperatorTableSetCallback(table, "ET") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), s.inText else { s.invalid = true; return }
            s.inText = false; s.positioned = false
        }
        CGPDFOperatorTableSetCallback(table, "Tm") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), s.inText, let n = Self.numbers(scanner, 6) else { s.invalid = true; return }
            s.line = CGAffineTransform(a: n[0], b: n[1], c: n[2], d: n[3], tx: n[4], ty: n[5]); s.positioned = true
        }
        CGPDFOperatorTableSetCallback(table, "Td") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), s.inText, let n = Self.numbers(scanner, 2) else { s.invalid = true; return }
            s.line = s.line.translatedBy(x: n[0], y: n[1]); s.positioned = true
        }
        CGPDFOperatorTableSetCallback(table, "TD") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), s.inText, let n = Self.numbers(scanner, 2) else { s.invalid = true; return }
            s.leading = -n[1]; s.line = s.line.translatedBy(x: n[0], y: n[1]); s.positioned = true
        }
        CGPDFOperatorTableSetCallback(table, "T*") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), s.inText else { s.invalid = true; return }
            s.line = s.line.translatedBy(x: 0, y: -s.leading); s.positioned = true
        }
        CGPDFOperatorTableSetCallback(table, "TL") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), let n = Self.numbers(scanner, 1) else { s.invalid = true; return }
            s.leading = n[0]
        }
        // State or placement that this reader does not model disqualifies the whole page.
        for op in ["Tc", "Tw", "Ts", "Tr"] {
            CGPDFOperatorTableSetCallback(table, op) { scanner, info in
                let s = Self.state(info)
                if !s.accept(scanner) || Self.numbers(scanner, 1) != [0] { s.invalid = true }
            }
        }
        CGPDFOperatorTableSetCallback(table, "Tz") { scanner, info in
            let s = Self.state(info)
            if !s.accept(scanner) || Self.numbers(scanner, 1) != [100] { s.invalid = true }
        }
        for op in ["'", "\"", "gs", "BI"] {
            CGPDFOperatorTableSetCallback(table, op) { _, info in Self.state(info).invalid = true }
        }
        // An XObject is opaque: an image carries no text, and a Form's content is not scanned,
        // so its text can neither supply nor contradict evidence (a line mixing Form and page
        // text fails the exact-match requirement). A missing resource disqualifies the page.
        CGPDFOperatorTableSetCallback(table, "Do") { scanner, info in
            let s = Self.state(info)
            var name: UnsafePointer<CChar>?, stream: CGPDFStreamRef?, subtype: UnsafePointer<CChar>?
            guard s.accept(scanner), !s.inText, CGPDFScannerPopName(scanner, &name), let name,
                  let object = CGPDFContentStreamGetResource(CGPDFScannerGetContentStream(scanner), "XObject", name),
                  CGPDFObjectGetValue(object, .stream, &stream), let stream, let dict = CGPDFStreamGetDictionary(stream),
                  CGPDFDictionaryGetName(dict, "Subtype", &subtype), let subtype,
                  ["Image", "Form"].contains(String(cString: subtype)) else {
                s.invalid = true; return
            }
        }
        CGPDFOperatorTableSetCallback(table, "TJ") { scanner, info in Self.state(info).show(scanner, array: true) }
        CGPDFOperatorTableSetCallback(table, "Tj") { scanner, info in Self.state(info).show(scanner, array: false) }
        let s = State(), stream = CGPDFContentStreamCreateWithPage(page)
        defer { CGPDFContentStreamRelease(stream) }
        let scanner = CGPDFScannerCreate(stream, table, Unmanaged.passUnretained(s).toOpaque())
        defer { CGPDFScannerRelease(scanner) }
        guard CGPDFScannerScan(scanner), !s.invalid, s.saved.isEmpty, !s.inText else { return [] }
        return s.evidence
    }

    static func apply(_ evidence: [Evidence], to attributed: NSAttributedString, bounds: CGRect,
                      allBounds: [CGRect]) -> NSAttributedString {
        guard evidence.count <= 10_000, allBounds.count <= 10_000,
              evidence.count * allBounds.count <= 2_000_000 else { return attributed }
        let matches = evidence.filter { bounds.insetBy(dx: -0.75, dy: -0.75).contains($0.origin) }
        // Every show must belong to this line alone; overlapping line rectangles are ambiguous.
        guard !matches.isEmpty, matches.allSatisfy({ match in
            allBounds.filter({ $0.insetBy(dx: -0.75, dy: -0.75).contains(match.origin) }).count == 1
        }) else { return attributed }
        let repaired = NSMutableAttributedString(attributedString: attributed)
        if matches.count == 1, let offsets = matches[0].extraSpaces(in: attributed.string) {
            for offset in offsets.reversed() { repaired.deleteCharacters(in: NSRange(location: offset, length: 1)) }
            return repaired
        }
        guard matches.count >= 2, let offsets = missingSpaces(in: attributed.string, shows: matches) else { return attributed }
        for offset in offsets.reversed() {
            let attributes = repaired.attributes(at: offset - 1, effectiveRange: nil)
            repaired.insert(NSAttributedString(string: " ", attributes: attributes), at: offset)
        }
        return repaired
    }
}
