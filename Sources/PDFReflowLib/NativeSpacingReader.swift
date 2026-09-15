import Foundation
import CoreGraphics

/// Removes only PDFKit spaces contradicted by a supported Type3 text-show operation.
/// This is deliberately a small evidence reader, not a replacement text extractor.
enum NativeSpacingReader {
    struct Evidence {
        var origin: CGPoint
        var text: String?
        // UTF-16 boundaries with a positive gap of at most 0.01 em in the source TJ array.
        var smallGaps: Set<Int> = []

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

    private struct Font { var map: [UInt8: String] }
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
        var evidence: [Evidence] = []

        func accept(_ scanner: CGPDFScannerRef) -> Bool {
            operations += 1
            if operations > 100_000 || Task.isCancelled { invalid = true }
            if invalid { CGPDFScannerStop(scanner) }
            return !invalid
        }
        func show(_ scanner: CGPDFScannerRef, array: Bool) {
            guard accept(scanner), inText, positioned, evidence.count < 10_000 else { invalid = true; return }
            positioned = false
            let transform = line.concatenating(matrix)
            guard transform.b == 0, transform.c == 0, transform.a > 0, transform.d > 0,
                  transform.tx.isFinite, transform.ty.isFinite else { invalid = true; return }
            var item = Evidence(origin: CGPoint(x: transform.tx, y: transform.ty))
            var value = "", gaps: Set<Int> = [], valid = font != nil && size > 0
            func append(_ string: CGPDFStringRef) {
                let count = CGPDFStringGetLength(string)
                guard count <= 4096, value.utf16.count + count <= 4096,
                      let bytes = CGPDFStringGetBytePtr(string), let font else { valid = false; return }
                for index in 0..<count {
                    guard let decoded = font.map[bytes[index]] else { valid = false; return }
                    value += decoded
                }
            }
            if array {
                var values: CGPDFArrayRef?
                guard CGPDFScannerPopArray(scanner, &values), let values,
                      CGPDFArrayGetCount(values) <= 4096 else { invalid = true; return }
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
                    } else { valid = false }
                }
            } else {
                var string: CGPDFStringRef?
                guard CGPDFScannerPopString(scanner, &string), let string else { invalid = true; return }
                append(string)
            }
            if value.hasSuffix("\n") { value.removeLast() }
            if valid, !value.isEmpty, value.utf16.allSatisfy({ (32...126).contains($0) }) {
                item.text = value; item.smallGaps = gaps
            }
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
    private static func font(_ object: CGPDFObjectRef) -> Font? {
        var dict: CGPDFDictionaryRef?, subtype: UnsafePointer<CChar>?, matrix: CGPDFArrayRef?, stream: CGPDFStreamRef?
        guard CGPDFObjectGetValue(object, .dictionary, &dict), let dict,
              CGPDFDictionaryGetName(dict, "Subtype", &subtype), let subtype, String(cString: subtype) == "Type3",
              CGPDFDictionaryGetArray(dict, "FontMatrix", &matrix), let matrix, CGPDFArrayGetCount(matrix) == 6,
              CGPDFDictionaryGetStream(dict, "ToUnicode", &stream), let stream else { return nil }
        for (i, expected) in [1.0, 0, 0, 1, 0, 0].enumerated() {
            var number: CGPDFReal = 0
            guard CGPDFArrayGetNumber(matrix, i, &number), number == expected else { return nil }
        }
        var format = CGPDFDataFormat.raw
        guard let data = CGPDFStreamCopyData(stream, &format), format == .raw,
              let map = characterMap(data as Data) else { return nil }
        return Font(map: map)
    }

    private final class FontPresence { var found = false }
    private static func hasType3Font(_ page: CGPDFPage) -> Bool {
        var node: CGPDFDictionaryRef? = page.dictionary
        for _ in 0..<64 {
            guard let current = node else { return false }
            var resources: CGPDFDictionaryRef?, fonts: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(current, "Resources", &resources), let resources {
                guard CGPDFDictionaryGetDictionary(resources, "Font", &fonts), let fonts else { return false }
                let presence = FontPresence()
                CGPDFDictionaryApplyFunction(fonts, { _, object, info in
                    var dict: CGPDFDictionaryRef?, subtype: UnsafePointer<CChar>?
                    if CGPDFObjectGetValue(object, .dictionary, &dict), let dict,
                       CGPDFDictionaryGetName(dict, "Subtype", &subtype), let subtype,
                       String(cString: subtype) == "Type3" {
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
        guard page.rotationAngle == 0, hasType3Font(page), let table = CGPDFOperatorTableCreate() else { return [] }
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
        CGPDFOperatorTableSetCallback(table, "Tf") { scanner, info in
            let s = Self.state(info)
            s.fontSelections += 1
            var name: UnsafePointer<CChar>?
            guard s.accept(scanner), s.fontSelections <= 256,
                  let n = Self.numbers(scanner, 1), CGPDFScannerPopName(scanner, &name), let name,
                  let object = CGPDFContentStreamGetResource(CGPDFScannerGetContentStream(scanner), "Font", name) else {
                s.invalid = true; return
            }
            s.size = n[0]; s.font = Self.font(object)
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
        CGPDFOperatorTableSetCallback(table, "Do") { scanner, info in
            let s = Self.state(info)
            var name: UnsafePointer<CChar>?, stream: CGPDFStreamRef?, subtype: UnsafePointer<CChar>?
            guard s.accept(scanner), CGPDFScannerPopName(scanner, &name), let name,
                  let object = CGPDFContentStreamGetResource(CGPDFScannerGetContentStream(scanner), "XObject", name),
                  CGPDFObjectGetValue(object, .stream, &stream), let stream, let dict = CGPDFStreamGetDictionary(stream),
                  CGPDFDictionaryGetName(dict, "Subtype", &subtype), let subtype, String(cString: subtype) == "Image" else {
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
        guard matches.count == 1, let match = matches.first,
              allBounds.filter({ $0.insetBy(dx: -0.75, dy: -0.75).contains(match.origin) }).count == 1,
              let offsets = match.extraSpaces(in: attributed.string) else { return attributed }
        let repaired = NSMutableAttributedString(attributedString: attributed)
        for offset in offsets.reversed() { repaired.deleteCharacters(in: NSRange(location: offset, length: 1)) }
        return repaired
    }
}
