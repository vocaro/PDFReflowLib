import CoreGraphics
import Foundation

/// Some composers emit inserted break hyphens through a separate resource of the same font.
/// A font switch alone says nothing: this reader requires a complete page census, repeated
/// lexically confirmed breaks, and ordinary hard hyphens actually drawn by the neighboring
/// body font. Unknown or contradictory uses leave the original source characters untouched.
enum DiscretionaryHyphenReader {
    struct Show {
        var font: Int
        var family: String?
        var text: String?
        var origin: CGPoint?
        var size: CGFloat
        var object: Int
    }

    private struct Font {
        var id: Int
        var family: String?
        var bytes = 1
        var map: [UInt32: String]?
    }

    /// A one-byte ToUnicode map written as scalar ranges. Keep this separate from the glyph
    /// identity reader, whose case correction deliberately refuses ranged maps. An explicit
    /// U+00AD in this map is source evidence even when PDFKit omits that character from a line.
    static func scalarRangeMap(_ data: Data) -> [UInt32: String]? {
        guard data.count <= 65_536, let input = String(data: data, encoding: .ascii),
              !input.contains("usecmap"),
              input.range(of: #"1\s+begincodespacerange\s*<00>\s*<ff>\s*endcodespacerange"#,
                          options: .regularExpression) != nil else { return nil }
        let text = input.replacingOccurrences(of: "%[^\\r\\n]*", with: "", options: .regularExpression)
        let blocks = try! NSRegularExpression(pattern: #"(\d+)\s+beginbfrange\s*([\s\S]*?)\s*endbfrange"#)
        let entries = try! NSRegularExpression(pattern: #"<([0-9a-fA-F]{2})>\s*<([0-9a-fA-F]{2})>\s*<([0-9a-fA-F]{4})>"#)
        let ns = text as NSString
        let matches = blocks.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty, matches.count <= 256,
              matches.count == text.components(separatedBy: "beginbfrange").count - 1,
              !text.contains("beginbfchar") else { return nil }
        var map: [UInt32: String] = [:]
        for block in matches {
            let body = ns.substring(with: block.range(at: 2)), bodyNS = body as NSString
            let pairs = entries.matches(in: body, range: NSRange(location: 0, length: bodyNS.length))
            guard Int(ns.substring(with: block.range(at: 1))) == pairs.count,
                  entries.stringByReplacingMatches(in: body, range: NSRange(location: 0, length: bodyNS.length),
                                                   withTemplate: "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            for pair in pairs {
                guard let first = UInt32(bodyNS.substring(with: pair.range(at: 1)), radix: 16),
                      let last = UInt32(bodyNS.substring(with: pair.range(at: 2)), radix: 16),
                      let base = UInt32(bodyNS.substring(with: pair.range(at: 3)), radix: 16),
                      first <= last, last <= 255, base + last - first <= 0xFFFF else { return nil }
                for code in first...last {
                    let scalar = base + code - first
                    guard !(0xD800...0xDFFF).contains(scalar), let value = UnicodeScalar(scalar),
                          map.updateValue(String(value), forKey: code) == nil else { return nil }
                }
            }
        }
        return map.isEmpty ? nil : map
    }

    private static func font(_ dict: CGPDFDictionaryRef) -> Font {
        let name = CGPDFObjects.name(dict, "BaseFont")
        let family = name.map { value -> String in
            let parts = value.split(separator: "+", maxSplits: 1)
            return parts.count == 2 && parts[0].count == 6 && parts[0].allSatisfy(\.isUppercase)
                ? String(parts[1]) : value
        }
        var font = Font(id: unsafeBitCast(dict, to: Int.self), family: family)
        guard let subtype = CGPDFObjects.name(dict, "Subtype"),
              ["Type0", "TrueType", "Type1"].contains(subtype),
              subtype != "Type0" || CGPDFObjects.name(dict, "Encoding") == "Identity-H",
              let data = CGPDFObjects.rawData(dict, "ToUnicode") else { return font }
        font.bytes = subtype == "Type0" ? 2 : 1
        font.map = GlyphIdentityReader.bfCharMap(data, codeDigits: font.bytes * 2, allowSequences: true)
            ?? (font.bytes == 1 ? scalarRangeMap(data) : nil)
        return font
    }

    private final class Visitor: ContentStreamVisitor {
        var current: Font?
        var size: CGFloat = 0
        var saved: [(Font?, CGFloat)] = []
        var fonts: [Int: Font] = [:]
        var shows: [Show] = []
        var object = 0
        var decodedCharacters = 0
        var resources: CGPDFDictionaryRef?
        var lastOrigin: CGPoint?

        func saveState() { saved.append((current, size)) }
        func restoreState() { (current, size) = saved.removeLast() }
        func beginText(_ walk: ContentStreamWalk) { object += 1; lastOrigin = nil }
        func endText(_ walk: ContentStreamWalk) { lastOrigin = nil }
        func selectFont(name: String, size: CGFloat, resource: CGPDFObjectRef?, walk: ContentStreamWalk) {
            self.size = size
            guard let resource, let dict = CGPDFObjects.dictionary(of: resource) else { current = nil; return }
            let id = unsafeBitCast(dict, to: Int.self)
            guard fonts.count < 1024 else { walk.invalid = true; return }
            let found = fonts[id] ?? DiscretionaryHyphenReader.font(dict)
            fonts[id] = found
            current = found
        }
        func show(_ arguments: [ContentStreamWalk.ShowArgument], walk: ContentStreamWalk) {
            guard shows.count < 10_000 else { walk.invalid = true; return }
            let transform = walk.textTransform
            let upright = [transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty].allSatisfy(\.isFinite) && transform.b == 0 && transform.c == 0 && transform.a > 0 && transform.d > 0
            let origin = upright ? (walk.positioned ? CGPoint(x: transform.tx, y: transform.ty) : lastOrigin) : nil
            lastOrigin = origin
            var text: String? = current?.map == nil ? nil : ""
            var units = 0
            for argument in arguments {
                switch argument {
                case .adjustment: break
                case .other: text = nil
                case .string(let string):
                    guard let font = current, let map = font.map, text != nil,
                          let bytes = CGPDFStringGetBytePtr(string) else { text = nil; continue }
                    let count = CGPDFStringGetLength(string)
                    guard count <= 8192, count % font.bytes == 0 else { text = nil; continue }
                    for i in stride(from: 0, to: count, by: font.bytes) {
                        let code = font.bytes == 2 ? UInt32(bytes[i]) << 8 | UInt32(bytes[i + 1]) : UInt32(bytes[i])
                        guard let value = map[code] else { text = nil; break }
                        units += value.utf16.count
                        guard units <= 8192 else { text = nil; break }
                        text?.append(value)
                    }
                }
            }
            decodedCharacters += text?.utf16.count ?? 0
            guard decodedCharacters <= 2_000_000 else { walk.invalid = true; return }
            shows.append(Show(font: current?.id ?? -1, family: current?.family, text: text,
                              origin: origin, size: size * transform.d, object: object))
        }
        func handle(_ op: String, scanner: CGPDFScannerRef, walk: ContentStreamWalk) {
            if op == "Do" {
                guard !walk.inText, let name = ContentStreamWalk.popName(scanner),
                      let resource = CGPDFContentStreamGetResource(CGPDFScannerGetContentStream(scanner), "XObject", name),
                      let stream = CGPDFObjects.stream(of: resource), let dict = CGPDFStreamGetDictionary(stream)
                else { walk.invalid = true; return }
                if CGPDFObjects.name(dict, "Subtype") == "Image" { return }
                guard CGPDFObjects.name(dict, "Subtype") == "Form",
                      let own = CGPDFObjects.dictionary(dict, "Resources") ?? resources else { walk.invalid = true; return }
                let outer = (current, size, saved, resources, lastOrigin)
                saved = []; resources = own; lastOrigin = nil
                _ = walk.descend(into: stream, dictionary: dict, resources: own, scanner: scanner)
                (current, size, saved, resources, lastOrigin) = outer
                return
            }
            if op == "gs" {
                guard let name = ContentStreamWalk.popName(scanner),
                      let resource = CGPDFContentStreamGetResource(CGPDFScannerGetContentStream(scanner), "ExtGState", name),
                      let dict = CGPDFObjects.dictionary(of: resource), CGPDFObjects.object(dict, "Font") == nil
                else { walk.invalid = true; return }
                return
            }
            // Rise, rendering mode and horizontal scaling change source/native ownership.
            guard let value = ContentStreamWalk.numbers(scanner, 1)?.first,
                  value == (op == "Tz" ? 100 : 0) else { walk.invalid = true; return }
        }
    }

    static func read(_ page: CGPDFPage) -> [Show] {
        guard page.rotationAngle == 0 else { return [] }
        let visitor = Visitor()
        visitor.resources = CGPDFObjects.inheritedResources(of: page)
        var options = ContentStreamWalk.Options()
        options.selectsFonts = true
        options.maximumOperations = 200_000
        options.maximumSavedStates = 256
        options.maximumShowElements = 4096
        options.maximumFormDepth = 8
        options.moveAndShow = .show
        options.operators = ["Do", "Ts", "Tr", "Tz", "gs"]
        guard ContentStreamWalk.scan(page, options: options, visitor: visitor) else { return [] }
        return visitor.shows
    }

    /// Native line indices and exact joined words corroborated by the font census. This is
    /// evidence for join-time evaluation, not an unconditional rewrite: the exact continuation
    /// and source-attested compound spellings still decide whether it applies.
    /// This never searches for a particular word, font name or publication.
    static func lines(shows: [Show], texts: [String], bounds: [CGRect]) -> [Int: String] {
        guard texts.count == bounds.count, shows.count <= 10_000,
              shows.count * bounds.count <= AnchorMatcher.maximumComparisons else { return [:] }
        let fonts = Dictionary(grouping: shows.indices, by: { shows[$0].font })
        var result: [Int: String] = [:]
        func owner(_ point: CGPoint) -> Int? {
            let hits = bounds.indices.filter { AnchorMatcher.contains(bounds[$0], point) }
            return hits.count == 1 ? hits[0] : nil
        }
        func normalized(_ text: String) -> String { text.precomposedStringWithCompatibilityMapping.trimmingCharacters(in: .whitespacesAndNewlines) }
        // A composer that simply uses a fallback font for every line-final hyphen has not
        // distinguished hard from discretionary breaks. Require an independently drawn hard
        // compound at a native wrap in the body resource, also printed whole on this page.
        let pattern = try! NSRegularExpression(pattern: #"\p{L}+(?:-\p{L}+)+"#)
        var compounds: [Int: Set<String>] = [:]
        for show in shows {
            if Task.isCancelled { return [:] }
            guard let text = show.text else { continue }
            let value = normalized(text).lowercased() as NSString
            for match in pattern.matches(in: value as String, range: NSRange(location: 0, length: value.length)) {
                compounds[show.font, default: []].insert(value.substring(with: match.range))
            }
        }
        var wrappedCompoundFonts = Set<Int>()
        for index in shows.indices.dropLast() {
            if Task.isCancelled { return [:] }
            let left = shows[index], right = shows[index + 1]
            guard let a = left.text.map(normalized), a.hasSuffix("-"),
                  let b = right.text.map(normalized), b.first?.isLowercase == true,
                  left.font == right.font, left.object == right.object,
                  let start = left.origin, let end = right.origin, left.size > 0,
                  start.y - end.y >= left.size * 0.8, start.y - end.y <= left.size * 1.8,
                  let line = owner(start), let next = owner(end), line != next,
                  normalized(texts[line]).hasSuffix(a), normalized(texts[next]).hasPrefix(b),
                  abs(bounds[line].minX - bounds[next].minX) <= left.size else { continue }
            let prefix = String(a.dropLast().reversed().prefix(while: \.isLetter).reversed()).lowercased()
            let suffix = String(b.prefix(while: \.isLetter)).lowercased()
            if compounds[left.font]?.contains(prefix + "-" + suffix) == true { wrappedCompoundFonts.insert(left.font) }
        }
        for (_, indices) in fonts where indices.count >= 4 {
            if Task.isCancelled { return [:] }
            guard indices.allSatisfy({ shows[$0].text == "-" }) else { continue }
            var selected: [Int: String] = [:]
            var vouched = Set<String>(), valid = true
            for index in indices {
                guard index > 0, index + 1 < shows.count else { valid = false; break }
                let hyphen = shows[index], before = shows[index - 1], after = shows[index + 1]
                guard let family = hyphen.family, before.family == family, after.family == family,
                      before.font == after.font, before.font != hyphen.font,
                      before.object == hyphen.object, after.object == hyphen.object,
                      let left = before.text, let right = after.text,
                      let point = hyphen.origin, let start = before.origin, let end = after.origin,
                      hyphen.size > 0, abs(before.size - hyphen.size) < 0.1,
                      abs(after.size - hyphen.size) < 0.1,
                      abs(point.y - start.y) < 0.5,
                      start.x <= point.x,
                      point.y - end.y >= hyphen.size * 0.8, point.y - end.y <= hyphen.size * 1.8,
                      let line = owner(point), let previous = owner(start), previous == line,
                      let next = owner(end), next != line,
                      abs(bounds[next].minX - bounds[line].minX) <= hyphen.size,
                      let l = normalized(left).last, l.isLetter,
                      normalized(right).first?.isLowercase == true,
                      normalized(texts[line]).trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(normalized(left) + "-"),
                      normalized(texts[next]).hasPrefix(normalized(right)),
                      wrappedCompoundFonts.contains(before.font)
                else { valid = false; break }
                let prefix = String(normalized(left).reversed().prefix(while: \.isLetter).reversed()).lowercased()
                let suffix = String(normalized(right).prefix(while: \.isLetter)).lowercased()
                guard prefix.count >= 2, suffix.count >= 2 else { valid = false; break }
                if EnglishText.vouchesForHyphenJoin(prefix: prefix, suffix: suffix) {
                    vouched.insert(prefix + suffix)
                }
                selected[line] = prefix + suffix
            }
            if valid, vouched.count >= 3, selected.count == indices.count { result.merge(selected) { first, _ in first } }
        }
        return result
    }

    /// Source shows whose font maps a final byte to U+00AD, but whose PDFKit line omits it.
    /// The next source show and the two unique native line owners must state the same split.
    static func explicitSoftHyphenLines(shows: [Show], texts: [String], bounds: [CGRect]) -> Set<Int> {
        guard texts.count == bounds.count, shows.count * bounds.count <= AnchorMatcher.maximumComparisons
        else { return [] }
        func lastWord(_ text: String) -> String {
            String(text.reversed().drop(while: { $0 == "\u{FFFD}" || $0.isWhitespace })
                .prefix(while: \.isLetter).reversed())
        }
        var result = Set<Int>()
        for index in shows.indices.dropLast() {
            if Task.isCancelled { return [] }
            let mark = shows[index], next = shows[index + 1]
            guard mark.text?.last == "\u{00AD}", mark.font == next.font,
                  mark.object == next.object, let start = mark.origin, let end = next.origin,
                  mark.size > 0, abs(mark.size - next.size) < 0.1,
                  start.y - end.y >= mark.size * 0.8,
                  start.y - end.y <= mark.size * 1.8
            else { continue }
            let before = lastWord(String(mark.text!.dropLast()))
            let prefix: String
            if !before.isEmpty { prefix = before }
            else if index > 0, shows[index - 1].font == mark.font,
                    shows[index - 1].object == mark.object,
                    let previous = shows[index - 1].origin,
                    abs(previous.y - start.y) < 0.5 {
                prefix = lastWord(shows[index - 1].text ?? "")
            } else { continue }
            let suffix = String((next.text ?? "").prefix(while: \.isLetter))
            guard prefix.count >= 2, suffix.count >= 2 else { continue }
            // A drop cap can enlarge a preceding line's rectangle across this baseline. The
            // exact source word halves must identify one adjacent pair of native selections.
            let candidates = bounds.indices.dropLast().filter { line in
                AnchorMatcher.contains(bounds[line], start)
                    && AnchorMatcher.contains(bounds[line + 1], end)
                    && texts[line].trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(prefix)
                    && texts[line + 1].trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(suffix)
                    && !texts[line].hasSuffix("-") && !texts[line].hasSuffix("\u{00AD}")
                    && abs(bounds[line].minX - bounds[line + 1].minX) <= mark.size * 6
                    && (before.isEmpty ? index > 0 && shows[index - 1].origin.map {
                        AnchorMatcher.contains(bounds[line], $0)
                    } == true : true)
            }
            if candidates.count == 1 { result.insert(candidates[0]) }
        }
        return result
    }

    static func restoreSoftHyphen(to attributed: NSAttributedString) -> NSAttributedString {
        let value = attributed.string as NSString
        var end = value.length
        while end > 0, let scalar = UnicodeScalar(UInt32(value.character(at: end - 1))),
              CharacterSet.whitespacesAndNewlines.contains(scalar) { end -= 1 }
        guard end > 0, value.character(at: end - 1) != 45,
              value.character(at: end - 1) != 0xAD else {
            return attributed
        }
        let result = NSMutableAttributedString(attributedString: attributed)
        let attributes = attributed.attributes(at: end - 1, effectiveRange: nil)
        result.insert(NSAttributedString(string: "\u{00AD}", attributes: attributes), at: end)
        return result
    }

    static let attribute = NSAttributedString.Key("PDFReflowSourceDiscretionaryWord")

    static func apply(to attributed: NSAttributedString, word: String) -> NSAttributedString {
        let text = attributed.string as NSString
        var end = text.length
        while end > 0, let scalar = UnicodeScalar(UInt32(text.character(at: end - 1))),
              CharacterSet.whitespacesAndNewlines.contains(scalar) { end -= 1 }
        guard end > 0, text.character(at: end - 1) == 45 else { return attributed }
        let result = NSMutableAttributedString(attributedString: attributed)
        result.addAttribute(attribute, value: word, range: NSRange(location: end - 1, length: 1))
        return result
    }
}
