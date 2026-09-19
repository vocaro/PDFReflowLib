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

    /// A Type3 font with the identity font matrix and an uncompressed one-byte `ToUnicode` map.
    private static func font(_ object: CGPDFObjectRef) -> Font? {
        var dict: CGPDFDictionaryRef?
        guard CGPDFObjectGetValue(object, .dictionary, &dict), let dict,
              CGPDFObjects.name(dict, "Subtype") == "Type3",
              CGPDFObjects.matrix(dict, "FontMatrix") == .identity,
              let data = CGPDFObjects.rawData(dict, "ToUnicode"),
              let map = characterMap(data) else { return nil }
        return Font(map: map)
    }

    private static func hasType3Font(_ page: CGPDFPage) -> Bool {
        guard let resources = CGPDFObjects.inheritedResources(of: page) else { return false }
        return CGPDFObjects.fonts(in: resources).contains { CGPDFObjects.name($0, "Subtype") == "Type3" }
    }

    /// Text state and placement this reader does not model disqualifies the whole page.
    private static let scanOptions: ContentStreamWalk.Options = {
        var options = ContentStreamWalk.Options()
        options.operators = ["Tc", "Tw", "Ts", "Tr", "Tz", "gs", "BI", "Do"]
        options.refusesStateChangesInText = true
        options.beginTextPositions = false
        options.selectsFonts = true
        options.maximumShowElements = 4096
        options.moveAndShow = .invalidate
        return options
    }()

    private final class Visitor: ContentStreamVisitor {
        var font: Font?
        var size: CGFloat = 0
        var saved: [(Font?, CGFloat)] = []
        var fontSelections = 0
        var evidence: [Evidence] = []

        func saveState() { saved.append((font, size)) }
        func restoreState() { (font, size) = saved.removeLast() }

        func selectFont(name: String, size: CGFloat, resource: CGPDFObjectRef?, walk: ContentStreamWalk) {
            fontSelections += 1
            guard fontSelections <= 256, let resource else { walk.invalid = true; return }
            self.size = size
            font = NativeSpacingReader.font(resource)
        }

        func show(_ arguments: [ContentStreamWalk.ShowArgument], walk: ContentStreamWalk) {
            guard walk.inText, walk.positioned, evidence.count < 10_000 else { walk.invalid = true; return }
            let transform = walk.textTransform
            guard transform.b == 0, transform.c == 0, transform.a > 0, transform.d > 0,
                  transform.tx.isFinite, transform.ty.isFinite else { walk.invalid = true; return }
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
            var previousWasString = false
            for argument in arguments {
                switch argument {
                case .string(let string):
                    append(string); previousWasString = true
                case .adjustment(let number) where number.isFinite:
                    // Consecutive/initial adjustments and actual word-size gaps are ambiguous.
                    if !previousWasString || number < -10 { valid = false }
                    if number < 0 && number >= -10 { gaps.insert(value.utf16.count) }
                    previousWasString = false
                case .adjustment, .other:
                    valid = false
                }
            }
            if value.hasSuffix("\n") { value.removeLast() }
            if valid, !value.isEmpty, value.utf16.allSatisfy({ (32...126).contains($0) }) {
                item.text = value; item.smallGaps = gaps
            }
            evidence.append(item)
        }

        func handle(_ op: String, scanner: CGPDFScannerRef, walk: ContentStreamWalk) {
            switch op {
            case "Tc", "Tw", "Ts", "Tr":
                if ContentStreamWalk.numbers(scanner, 1) != [0] { walk.invalid = true }
            case "Tz":
                if ContentStreamWalk.numbers(scanner, 1) != [100] { walk.invalid = true }
            case "Do":
                // Only placed images are tolerated; a Form could draw text this reader never sees.
                guard let name = ContentStreamWalk.popName(scanner),
                      let object = CGPDFContentStreamGetResource(CGPDFScannerGetContentStream(scanner), "XObject", name),
                      let stream = CGPDFObjects.stream(of: object), let dict = CGPDFStreamGetDictionary(stream),
                      CGPDFObjects.name(dict, "Subtype") == "Image" else { walk.invalid = true; return }
            default:
                walk.invalid = true
            }
        }
    }

    static func read(_ page: CGPDFPage) -> [Evidence] {
        guard page.rotationAngle == 0, hasType3Font(page) else { return [] }
        let visitor = Visitor()
        guard ContentStreamWalk.scan(page, options: scanOptions, visitor: visitor) else { return [] }
        return visitor.evidence
    }

    static func apply(_ evidence: [Evidence], to attributed: NSAttributedString, bounds: CGRect,
                      allBounds: [CGRect]) -> NSAttributedString {
        guard let match = AnchorMatcher.uniqueAnchor(evidence, at: \.origin, in: bounds, among: allBounds),
              let offsets = match.extraSpaces(in: attributed.string) else { return attributed }
        let repaired = NSMutableAttributedString(attributedString: attributed)
        for offset in offsets.reversed() { repaired.deleteCharacters(in: NSRange(location: offset, length: 1)) }
        return repaired
    }
}
