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
    /// evidence for join-time evaluation, not an unconditional rewrite: independently valid
    /// halves and source-attested compounds still keep their literal hyphens.
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
                if LayoutReconstructor.lexiconVouches(prefix: prefix, suffix: suffix, usesEnglishLexicon: true) {
                    vouched.insert(prefix + suffix)
                }
                selected[line] = prefix + suffix
            }
            if valid, vouched.count >= 3, selected.count == indices.count { result.merge(selected) { first, _ in first } }
        }
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
