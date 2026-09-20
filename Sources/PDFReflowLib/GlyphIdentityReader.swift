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
        /// Set only on a show drawn in an index-glyph font (#143, #226), glyph by glyph: this
        /// show's line is rebuilt from these rather than through `candidateRange`'s single
        /// substitution, since such a font's every character is wrong, not one of them.
        var indexGlyphs: [IndexGlyph]?
    }

    /// One glyph of an index-glyph font: what PDFKit reports for its name, what the document's
    /// own words establish it draws, and whether a word-sized gap stands before it inside its
    /// show. `drawn` is U+FFFD where nothing in the document states the character.
    struct IndexGlyph: Equatable {
        var reported: String
        var drawn: String
        var startsWord: Bool
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

    /// A font's evidence, or nil for a font this reader has nothing to check (not a dingbat
    /// family and not a non-symbolic Type1/MMType1 font, or its `ToUnicode` map cannot be fully
    /// read). The case check is gated on the descriptor's `Flags`: bit 6 (Nonsymbolic, 32) set and
    /// bit 3 (Symbolic, 4) clear, matching a plain text font whose encoding names ordinary letters.
    private static func fontInfo(_ dict: CGPDFDictionaryRef) -> FontInfo? {
        guard let subtype = CGPDFObjects.name(dict, "Subtype") else { return nil }
        let wide = subtype == "Type0"
        var names: [String] = []
        if let base = CGPDFObjects.name(dict, "BaseFont") { names.append(base) }
        var descriptorOwner = dict
        if wide {
            var descendants: CGPDFArrayRef?, first: CGPDFDictionaryRef?
            guard let encoding = CGPDFObjects.name(dict, "Encoding"), encoding == "Identity-H" || encoding == "Identity-V",
                  CGPDFDictionaryGetArray(dict, "DescendantFonts", &descendants), let descendants,
                  CGPDFArrayGetCount(descendants) >= 1, CGPDFArrayGetDictionary(descendants, 0, &first), let first
            else { return nil }
            descriptorOwner = first
        }
        var descriptor: CGPDFDictionaryRef?
        _ = CGPDFDictionaryGetDictionary(descriptorOwner, "FontDescriptor", &descriptor)
        var flags: Int?
        if let descriptor {
            if let fontName = CGPDFObjects.name(descriptor, "FontName") { names.append(fontName) }
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
        guard let data = CGPDFObjects.rawData(dict, "ToUnicode"),
              let map = bfCharMap(data, codeDigits: wide ? 4 : 2) else { return nil }
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

    private static let scanOptions: ContentStreamWalk.Options = {
        var options = ContentStreamWalk.Options()
        options.maximumOperations = 200_000
        options.maximumSavedStates = 256
        // A stray positioning operator or text object boundary is tolerated: this reader records
        // shows, it does not validate the stream.
        options.strictTextObjects = false
        options.selectsFonts = true
        options.maximumShowElements = 4096
        return options
    }()

    private final class Visitor: ContentStreamVisitor {
        var font: FontInfo?
        var size: CGFloat = 0
        var saved: [(FontInfo?, CGFloat)] = []
        var lastOrigin: CGPoint?
        var fonts: [Int: FontInfo?] = [:]
        var shows: [Show] = []

        func saveState() { saved.append((font, size)) }
        func restoreState() { (font, size) = saved.removeLast() }
        func beginText(_ walk: ContentStreamWalk) { lastOrigin = nil }
        func endText(_ walk: ContentStreamWalk) { lastOrigin = nil }

        func selectFont(name: String, size: CGFloat, resource: CGPDFObjectRef?, walk: ContentStreamWalk) {
            self.size = size
            var dict: CGPDFDictionaryRef?
            guard let resource, CGPDFObjectGetValue(resource, .dictionary, &dict), let dict else { font = nil; return }
            let id = unsafeBitCast(dict, to: Int.self)
            if let cached = fonts[id] { font = cached }
            else {
                guard fonts.count < 1024 else { walk.invalid = true; return }
                let info = GlyphIdentityReader.fontInfo(dict)
                fonts[id] = info
                font = info
            }
        }

        // Numeric TJ adjustments carry no text; this reader tracks no advance or spacing, only
        // each show's decoded content and origin.
        func show(_ arguments: [ContentStreamWalk.ShowArgument], walk: ContentStreamWalk) {
            guard walk.inText, shows.count < 10_000 else { walk.invalid = true; return }
            let transform = walk.textTransform
            guard transform.tx.isFinite, transform.ty.isFinite, transform.a.isFinite, transform.d.isFinite else { return }
            // Rotated or mirrored text supplies no evidence for upright lines.
            guard transform.b == 0, transform.c == 0, transform.a > 0, transform.d > 0 else { lastOrigin = nil; return }
            let origin: CGPoint
            if walk.positioned { origin = CGPoint(x: transform.tx, y: transform.ty) }
            else if let last = lastOrigin { origin = last }
            else { return }
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
            for case .string(let string) in arguments { append(string) }
            guard ok, !reported.isEmpty, drawn != reported else { return }
            shows.append(Show(origin: origin, reported: reported, drawn: drawn, indexGlyphs: nil))
        }
    }

    /// Whether any font resource on `page` is a dingbat family or a non-symbolic Type1/MMType1
    /// font: the only fonts this reader can ever flag. Skips the full content-stream scan on the
    /// vast majority of pages, which have neither.
    private static func hasCandidateFont(_ page: CGPDFPage) -> Bool {
        guard let resources = CGPDFObjects.inheritedResources(of: page) else { return false }
        return CGPDFObjects.fonts(in: resources).contains { fontInfo($0) != nil }
    }

    /// The page's shows whose drawn text differs from what their font's `ToUnicode` map reports,
    /// or none when the page has no candidate font, its content stream cannot be scanned, or it is
    /// rotated (this reader's transform math assumes an upright page, matching
    /// `NativeSpacingReader`). This reader follows no Form XObjects: both motivating fixes (the
    /// magazine's back-cover bullet and its page-15 photo credit) draw directly on their own
    /// page's content stream.
    static func read(_ page: CGPDFPage) -> [Show] {
        guard page.rotationAngle == 0 else { return [] }
        var shows: [Show] = []
        if hasCandidateFont(page) {
            let visitor = Visitor()
            if ContentStreamWalk.scan(page, options: scanOptions, visitor: visitor) { shows = visitor.shows }
        }
        return shows + indexGlyphShows(page)
    }

    // MARK: - Index-glyph fonts (#143, #226)

    /// The character PDFKit reports for a glyph named by index. Measured with a synthetic Type 1
    /// font over the whole range while landing #143: a one-letter prefix (`G`, `g`, `C`, `c`,
    /// `a`) reads as the character whose code point is the index, for an index in 33–126 or
    /// 161–255, and as nothing anywhere else; a longer prefix (`glyph12`, `cid7`) reads as
    /// nothing. Where this prediction is wrong the line simply fails to align and is left exactly
    /// as PDFKit read it, so a future PDFKit loses the repair rather than corrupting a line.
    static func reportedCharacter(index: Int, shortPrefix: Bool) -> String {
        guard shortPrefix, (33...126).contains(index) || (161...255).contains(index),
              let scalar = UnicodeScalar(UInt32(index)) else { return "" }
        return String(scalar)
    }

    /// One show per index-glyph run on `page`, with each glyph's reported and drawn characters.
    /// Nothing at all when the page holds no index-glyph font or when the document established no
    /// font's characters: a book whose index-glyph fonts stay undecoded (the Warren Commission's
    /// synthetic fonts, the CDC comic) keeps #38's path untouched.
    private static func indexGlyphShows(_ page: CGPDFPage) -> [Show] {
        guard TextEncodingCheck.hasUnmappedFont(page) else { return [] }
        let table = GlyphIndexDecoder.table(for: page)
        guard !table.isEmpty, let scanned = GlyphIndexDecoder.scan(page) else { return [] }
        return scanned.shows.compactMap { show in
            guard let font = scanned.fonts[show.fontKey] else { return nil }
            let characters = table[show.fontKey]
            var glyphs: [IndexGlyph] = []
            var reported = "", drawn = ""
            for (position, glyph) in show.glyphs.enumerated() {
                // An ordinary glyph name states its own character and PDFKit reads it; an
                // index name reads as its index, or as nothing where PDFKit maps none.
                let read = glyph.index.map {
                    reportedCharacter(index: $0, shortPrefix: font.shortPrefixedCodes.contains(glyph.code))
                } ?? font.names[glyph.code] ?? ""
                let stated = characters?[glyph.code] ?? GlyphIndexDecoder.unknownCharacter
                // A show's first glyph never opens a word here: PDFKit knows the advance between
                // two shows and sets that space itself. Only a gap inside one show, which its
                // character spacing hides, is this reader's to restore.
                glyphs.append(IndexGlyph(reported: read, drawn: stated,
                                         startsWord: position > 0 && glyph.startsWord))
                reported += read
                drawn += stated
            }
            guard !glyphs.isEmpty else { return nil }
            return Show(origin: show.origin, reported: reported, drawn: drawn, indexGlyphs: glyphs)
        }
    }

    /// The index-glyph shows of one PDFKit line: those whose origin lies in its rectangle and in
    /// no other line's, in the order they are drawn across the line.
    static func indexGlyphs(of shows: [Show], in bounds: CGRect, among allBounds: [CGRect]) -> [IndexGlyph] {
        let candidates = shows.filter { $0.indexGlyphs != nil }
        guard !candidates.isEmpty, candidates.count <= AnchorMatcher.maximumAnchors,
              allBounds.count <= AnchorMatcher.maximumAnchors else { return [] }
        // An origin inside more than one line's rectangle is ambiguous evidence and rewrites
        // nothing, as everywhere else in this reader. Where PDFKit reports one drawn row as
        // several overlapping lines (#149 item 3) that leaves the row as PDFKit read it, and
        // `GlyphIndexDecoder.unreadGlyphs` is what tells the page so.
        return candidates
            .filter { show in
                AnchorMatcher.contains(bounds, show.origin)
                    && allBounds.filter({ AnchorMatcher.contains($0, show.origin) }).count == 1
            }
            .sorted { $0.origin.x < $1.origin.x }
            .flatMap { $0.indexGlyphs ?? [] }
    }

    /// Rewrites a line drawn in index-glyph fonts from its own glyphs, or nil when the glyphs do
    /// not spell what PDFKit read. Every non-blank character of the line must be the reported
    /// character of the next glyph in drawing order, and every glyph must be placed: a glyph
    /// PDFKit reports as nothing (a ligature) is inserted where it is drawn, and a word-sized gap
    /// inside a show that PDFKit's spacing hid opens a word. Anything else — a character no glyph
    /// explains, a glyph left over, a line the shows do not cover — leaves the line as PDFKit
    /// read it, as #143's rule did.
    static func repairIndexGlyphs(_ glyphs: [IndexGlyph], in attributed: NSAttributedString) -> NSAttributedString? {
        guard let repair = rebuildIndexGlyphs(glyphs, in: attributed, carryingSurplus: false),
              repair.rewritten else { return nil }
        return repair.text
    }

    /// A line rebuilt from the glyphs offered to it: its text, how many of them it took in
    /// drawing order, and whether any character actually changed (a line the decoder reads
    /// exactly as PDFKit did is left alone, attributes and all).
    struct IndexGlyphRepair {
        var text: NSAttributedString
        var consumed: Int
        var rewritten: Bool
    }

    /// `repairIndexGlyphs`'s alignment, with the option of leaving a tail of the glyphs for the
    /// next line of the same printed row (#237).
    ///
    /// `carryingSurplus` lets the alignment stop at the end of the line with glyphs left over —
    /// **but only where the next of them opens a word.** TeX sets a whole printed row as one
    /// `TJ` show and PDFKit splits it into a line per printed column, so the cut always falls at
    /// the horizontal gap between two columns, which is a word gap by construction. A glyph that
    /// continues the word the line ends with was never the next line's to take, so the repair
    /// declines instead, exactly as it does for a glyph the line has no room for.
    static func rebuildIndexGlyphs(_ glyphs: [IndexGlyph], in attributed: NSAttributedString,
                                   carryingSurplus: Bool) -> IndexGlyphRepair? {
        guard !glyphs.isEmpty, attributed.length <= 4_096, glyphs.count <= 4_096 else { return nil }
        let line = attributed.string as NSString

        /// One step of the alignment: a glyph placed, or a character of the line kept.
        enum Step { case glyph(Int), keep(Int) }

        func isBlank(_ index: Int) -> Bool {
            guard let scalar = UnicodeScalar(UInt32(line.character(at: index))) else { return false }
            return CharacterSet.whitespacesAndNewlines.contains(scalar) || line.character(at: index) == 0xFFFC
        }
        func matches(_ text: String, at index: Int) -> Bool {
            let expected = text as NSString
            guard !text.isEmpty, index + expected.length <= line.length else { return false }
            return line.substring(with: NSRange(location: index, length: expected.length)) == text
        }

        // The alignment is deterministic except at a glyph the document states no character for:
        // PDFKit may report it as one character or as nothing, and which of the two it did is not
        // knowable in advance, so both are tried and only an alignment that consumes the whole
        // line and every glyph stands. A ligature the line does not spell is likewise placed
        // before or after an adjoining space, whichever its own word gap says.
        var steps: [Step] = []
        var failed = Set<Int>()
        var budget = 20_000
        var consumed = glyphs.count
        func align(_ cursor: Int, _ position: Int) -> Bool {
            if cursor == line.length {
                if position == glyphs.count { consumed = position; return true }
                // The rest of the row is the next line's, and the cut falls at the gap between
                // two printed columns. Checked before the options below so that a ligature
                // opening a word joins the word it opens rather than the line that ends here.
                if carryingSurplus, glyphs[position].startsWord { consumed = position; return true }
            }
            let state = cursor * (glyphs.count + 1) + position
            if failed.contains(state) { return false }
            budget -= 1
            guard budget > 0 else { return false }
            var options: [(Step, Int, Int)] = []
            if position < glyphs.count {
                let glyph = glyphs[position]
                let blankHere = cursor < line.length && isBlank(cursor)
                if glyph.reported.isEmpty || glyph.drawn == GlyphIndexDecoder.unknownCharacter {
                    // Placed where it is drawn, after an adjoining space when it opens a word.
                    let zeroWidth = (Step.glyph(position), cursor, position + 1)
                    if blankHere, glyph.startsWord { options.append((.keep(cursor), cursor + 1, position)) }
                    options.append(zeroWidth)
                }
                if matches(glyph.reported, at: cursor) {
                    options.append((.glyph(position), cursor + (glyph.reported as NSString).length, position + 1))
                }
                if glyph.drawn == GlyphIndexDecoder.unknownCharacter, cursor < line.length, !blankHere {
                    options.append((.glyph(position), cursor + 1, position + 1))
                }
            }
            if cursor < line.length, isBlank(cursor) { options.append((.keep(cursor), cursor + 1, position)) }
            for (step, nextCursor, nextPosition) in options {
                steps.append(step)
                if align(nextCursor, nextPosition) { return true }
                steps.removeLast()
            }
            failed.insert(state)
            return false
        }
        guard align(0, 0) else { return nil }

        func attributes(at index: Int) -> [NSAttributedString.Key: Any] {
            guard attributed.length > 0 else { return [:] }
            return attributed.attributes(at: min(index, attributed.length - 1), effectiveRange: nil)
        }
        let result = NSMutableAttributedString()
        var replaced = false
        var cursor = 0
        for step in steps {
            switch step {
            case .keep(let index):
                result.append(attributed.attributedSubstring(from: NSRange(location: index, length: 1)))
                cursor = index + 1
            case .glyph(let index):
                let glyph = glyphs[index]
                if glyph.startsWord, let last = result.string.last, !last.isWhitespace {
                    result.append(NSAttributedString(string: " ", attributes: attributes(at: cursor)))
                }
                result.append(NSAttributedString(string: glyph.drawn, attributes: attributes(at: cursor)))
                replaced = replaced || glyph.drawn != glyph.reported
            }
        }
        return IndexGlyphRepair(text: result, consumed: consumed, rewritten: replaced)
    }

    /// Glyphs a show drew past the last character of the line its origin fell in, held for the
    /// next line of the same printed row (#237).
    struct IndexGlyphCarry {
        var glyphs: [IndexGlyph]
        /// The rectangles of the lines the row has covered so far, unioned: what the next line
        /// must continue.
        var row: CGRect
    }

    /// Whether `bounds` is the next printed column of the row `row` covers: a line begun at or
    /// after the row's right edge whose own middle lies inside the row's band of baselines.
    /// Both halves matter. Without the first, a carried glyph could land on the line below,
    /// which is a gap in the row's reading, not its continuation; without the second, it could
    /// land on a line of another row further down the page.
    static func continuesRow(_ row: CGRect, _ bounds: CGRect) -> Bool {
        guard row.isFinite, !row.isNull, bounds.isFinite, !bounds.isNull else { return false }
        return bounds.minX >= row.maxX - AnchorMatcher.tolerance
            && bounds.midY > row.minY && bounds.midY < row.maxY
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
    ///
    /// `carry` holds the glyphs an earlier line of the same printed row could not take (#237).
    /// They are offered to this line before its own, and whatever this line leaves is held for
    /// the next; a line that does not continue the row drops them, and
    /// `GlyphIndexDecoder.unreadGlyphs` then counts them against the page exactly as it counts a
    /// row no line could be found for at all.
    static func apply(_ shows: [Show], to attributed: NSAttributedString, bounds: CGRect,
                      allBounds: [CGRect], carry: inout IndexGlyphCarry?) -> NSAttributedString {
        // A line drawn in index-glyph fonts is rebuilt whole: every one of its characters is
        // wrong, so there is no single unambiguous occurrence to substitute.
        var indexGlyphs = indexGlyphs(of: shows, in: bounds, among: allBounds)
        var row = bounds
        if let pending = carry {
            carry = nil
            if continuesRow(pending.row, bounds) {
                indexGlyphs = pending.glyphs + indexGlyphs
                row = pending.row.union(bounds)
            }
        }
        if !indexGlyphs.isEmpty {
            // A line the glyphs spell on their own is rebuilt exactly as before; only one that
            // they cannot is allowed to leave a tail for the line beside it.
            guard let repair = rebuildIndexGlyphs(indexGlyphs, in: attributed, carryingSurplus: false)
                ?? rebuildIndexGlyphs(indexGlyphs, in: attributed, carryingSurplus: true)
            else { return attributed }
            if repair.consumed < indexGlyphs.count {
                carry = IndexGlyphCarry(glyphs: Array(indexGlyphs[repair.consumed...]), row: row)
            }
            return repair.rewritten ? repair.text : attributed
        }
        guard let match = AnchorMatcher.uniqueAnchor(shows.filter { $0.indexGlyphs == nil },
                                                     at: \.origin, in: bounds, among: allBounds),
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

    /// `apply` for a line read on its own, with no row running through it: nothing is carried in,
    /// and glyphs this line cannot take are dropped rather than offered on.
    static func apply(_ shows: [Show], to attributed: NSAttributedString, bounds: CGRect,
                      allBounds: [CGRect]) -> NSAttributedString {
        var carry: IndexGlyphCarry?
        return apply(shows, to: attributed, bounds: bounds, allBounds: allBounds, carry: &carry)
    }
}
