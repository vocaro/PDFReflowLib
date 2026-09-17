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
    /// shape code: `cmbx12`, `cmb10`, `cmmib10`, `cmbsy10`, `cmssbx10`, `cmbxti10`, `dcbx10`, `ecbx1200`.
    static func isTeXBold(_ lower: String) -> Bool {
        lower.range(of: #"^(cm|dc|ec|tc)(ss)?(bx|b|mib|bsy)(sl|ti|sc)?[0-9]+$"#, options: .regularExpression) != nil
    }

    static func nameWeight(_ baseFont: String) -> NameWeight {
        let name = strippedName(baseFont)
        let lower = name.lowercased()
        if isTeXBold(lower) { return .bold }
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

    struct FontInfo {
        var baseFont: String?
        var subtype: String
        var fontWeight: CGFloat?
        var stemV: CGFloat?
        var flags: Int?
        var hasToUnicode: Bool
        /// Nil for a Type3 font with no descriptor: its glyphs are procedures with no weight.
        var weight: Weight?
        var unicode: [UInt8: String]?
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

    static func fontInfo(_ dict: CGPDFDictionaryRef) -> FontInfo {
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
        var info = FontInfo(baseFont: baseFont, subtype: subtype, fontWeight: fontWeight,
                            stemV: descriptor.flatMap { number($0, "StemV") }, flags: flags, hasToUnicode: hasMap)
        if subtype != "Type3" || hasDescriptor || baseFont != nil {
            info.weight = weight(baseFont: baseFont, fontWeight: fontWeight, flags: flags)
        }
        if ["Type1", "TrueType", "MMType1"].contains(subtype), hasMap, let stream {
            var format = CGPDFDataFormat.raw
            if let data = CGPDFStreamCopyData(stream, &format), format == .raw {
                info.unicode = NativeSpacingReader.simpleFontUnicodeMap(data as Data)
            }
        }
        return info
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
    }

    private final class State {
        var matrix = CGAffineTransform.identity
        var line = CGAffineTransform.identity
        var font: Int?
        var size: CGFloat = 0
        var leading: CGFloat = 0
        var saved: [(CGAffineTransform, Int?, CGFloat, CGFloat)] = []
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

    private static func show(_ s: State, _ strings: [CGPDFStringRef]) {
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
        var text: String? = info?.unicode == nil ? nil : ""
        for string in strings {
            let count = CGPDFStringGetLength(string)
            guard let bytes = CGPDFStringGetBytePtr(string), count <= 4096 else { text = nil; break }
            for index in 0..<count {
                guard let decoded = info?.unicode?[bytes[index]], (text?.utf16.count ?? 0) < 8192 else { text = nil; break }
                text? += decoded
            }
        }
        s.shows.append(Show(origin: origin, size: s.size * transform.d, font: s.font ?? 0,
                            weight: info?.weight, text: text, placed: placed))
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
                s.fonts[id] = Self.fontInfo(dict)
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
            Self.show(s, [string])
        }
        CGPDFOperatorTableSetCallback(table, "'") { scanner, info in
            let s = Self.state(info)
            var string: CGPDFStringRef?
            guard s.accept(scanner), CGPDFScannerPopString(scanner, &string), let string else { s.invalid = true; return }
            s.line = s.line.translatedBy(x: 0, y: -s.leading); s.positioned = true
            Self.show(s, [string])
        }
        CGPDFOperatorTableSetCallback(table, "\"") { scanner, info in
            let s = Self.state(info)
            var string: CGPDFStringRef?
            guard s.accept(scanner), CGPDFScannerPopString(scanner, &string), let string,
                  Self.numbers(scanner, 2) != nil else { s.invalid = true; return }
            s.line = s.line.translatedBy(x: 0, y: -s.leading); s.positioned = true
            Self.show(s, [string])
        }
        CGPDFOperatorTableSetCallback(table, "TJ") { scanner, info in
            let s = Self.state(info)
            var array: CGPDFArrayRef?
            guard s.accept(scanner), CGPDFScannerPopArray(scanner, &array), let array,
                  CGPDFArrayGetCount(array) <= 8192 else { s.invalid = true; return }
            var strings: [CGPDFStringRef] = []
            for index in 0..<CGPDFArrayGetCount(array) {
                var string: CGPDFStringRef?
                if CGPDFArrayGetString(array, index, &string), let string { strings.append(string) }
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
            let saved = (s.matrix, s.font, s.size, s.leading, s.saved.count)
            s.matrix = matrix.concatenating(s.matrix)
            s.formDepth += 1
            Self.scan(content, s)
            s.formDepth -= 1
            s.inText = false
            s.saved.removeLast(max(0, s.saved.count - saved.4))
            (s.matrix, s.font, s.size, s.leading) = (saved.0, saved.1, saved.2, saved.3)
        }
        return table
    }

    /// The page's text shows, or none when the content stream cannot be scanned or no show is
    /// drawn in a bold font (then no line can gain bold).
    static func read(_ page: CGPDFPage) -> [Show] {
        let shows = read(page, fonts: nil)
        return shows.contains(where: { $0.weight == .bold }) ? shows : []
    }

    /// The page's shows and, when `fonts` is given, every font resource it selected (survey).
    static func read(_ page: CGPDFPage, fonts: ((Int, FontInfo) -> Void)?) -> [Show] {
        guard let table = makeTable() else { return [] }
        defer { CGPDFOperatorTableRelease(table) }
        let s = State()
        s.table = table
        let content = CGPDFContentStreamCreateWithPage(page)
        defer { CGPDFContentStreamRelease(content) }
        scan(content, s)
        if let fonts { for (id, info) in s.fonts { fonts(id, info) } }
        guard !s.invalid else { return [] }
        return s.shows
    }

    // MARK: - Lines

    /// Marks the characters of `attributed` (a PDFKit line with `bounds`) drawn in bold font
    /// resources with `boldAttribute`. The line's shows are those whose origin lies in its bounds
    /// and in no other line's. They explain the line when the leftmost starts within half an em of
    /// the line's left edge (so no show begun on another line draws its first glyphs) and, where
    /// every show decodes, their text spells the line apart from whitespace. Then a line whose
    /// shows are all one bold font weight is bold throughout; a line mixing weights is marked
    /// character by character from the decoded shows in reading order, and left unmarked when
    /// they do not decode or do not spell it. A regular line is returned unchanged.
    static func apply(_ shows: [Show], to attributed: NSAttributedString, bounds: CGRect,
                      allBounds: [CGRect]) -> NSAttributedString {
        guard attributed.length > 0, !shows.isEmpty, shows.count <= 50_000, allBounds.count <= 10_000,
              shows.count * max(1, allBounds.count) <= 4_000_000 else { return attributed }
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
            guard others.count == owners.count - 1 else { return attributed }
            if others.allSatisfy({ bounds.height < $0.height * 0.75 }) {
                matches.append(show); chosen = true
            } else if others.contains(where: { $0.height < bounds.height * 0.75 }) {
                chosen = true
            } else { return attributed }
        }
        guard !matches.isEmpty,
              matches.contains(where: { $0.weight == .bold }),
              !chosen || matches.allSatisfy({ $0.text != nil }),
              let left = matches.map(\.origin.x).min(),
              left - bounds.minX <= max(2, (matches.map(\.size).max() ?? 0) * 0.5) else { return attributed }
        func letters(_ text: String) -> [Unicode.Scalar] {
            text.precomposedStringWithCompatibilityMapping.unicodeScalars.filter {
                !CharacterSet.whitespacesAndNewlines.contains($0) && $0 != "\u{FFFC}" && $0 != "\u{00AD}"
            }
        }
        let decoded = matches.allSatisfy { $0.text != nil }
        let target = letters(attributed.string)
        var weights: [Weight]?
        if decoded {
            // Reading order: by origin, a show drawn straight after another keeping stream order.
            var sequence: [(Unicode.Scalar, Weight?)] = []
            for show in matches.enumerated().sorted(by: { ($0.element.origin.x, $0.offset) < ($1.element.origin.x, $1.offset) }) {
                sequence += letters(show.element.text ?? "").map { ($0, show.element.weight) }
            }
            guard sequence.map(\.0) == target else { return attributed }
            guard sequence.allSatisfy({ $0.1 != nil }) else { return attributed }
            weights = sequence.map { $0.1! }
        } else {
            guard matches.allSatisfy({ $0.weight == .bold }) else { return attributed }
        }
        let result = NSMutableAttributedString(attributedString: attributed)
        guard let weights else {
            result.addAttribute(boldAttribute, value: true, range: NSRange(location: 0, length: result.length))
            return result
        }
        // Walk the attributed string's characters against the weighted letters.
        let string = attributed.string as NSString
        var index = 0, position = 0
        while position < string.length {
            let range = string.rangeOfComposedCharacterSequence(at: position)
            let count = letters(string.substring(with: range)).count
            if count > 0 {
                guard index + count <= weights.count else { return attributed }
                if weights[index..<(index + count)].allSatisfy({ $0 == .bold }) {
                    result.addAttribute(boldAttribute, value: true, range: range)
                }
                index += count
            }
            position = range.location + range.length
        }
        guard index == weights.count else { return attributed }
        // Whitespace draws no weight, so it follows PDFKit's run: a space inside a run whose other
        // characters are all bold is bold (`Figure 2-8. ` stays one bold run), and one inside a
        // wholly regular run or a run of spaces alone is not. In a run PDFKit merged across fonts
        // a space takes the weight of the character before it (after it at the start).
        var positions: [(range: NSRange, blank: Bool, bold: Bool)] = []
        position = 0
        while position < string.length {
            let range = string.rangeOfComposedCharacterSequence(at: position)
            positions.append((range, letters(string.substring(with: range)).isEmpty,
                              result.attribute(boldAttribute, at: range.location, effectiveRange: nil) != nil))
            position = range.location + range.length
        }
        var previous: Bool?
        var runs: [Int: Bool?] = [:]  // run start: all bold, all regular, or nil (mixed or blank)
        for (offset, entry) in positions.enumerated() {
            guard entry.blank else { previous = entry.bold; continue }
            var run = NSRange()
            _ = attributed.attributes(at: entry.range.location, effectiveRange: &run)
            if runs[run.location] == nil {
                let neighbours = positions.filter { !$0.blank && NSIntersectionRange($0.range, run).length > 0 }
                runs[run.location] = neighbours.isEmpty ? false
                    : neighbours.allSatisfy(\.bold) ? true : neighbours.contains(where: \.bold) ? .some(nil) : false
            }
            let bold = (runs[run.location] ?? nil)
                ?? previous ?? positions[(offset + 1)...].first(where: { !$0.blank })?.bold ?? false
            if bold { result.addAttribute(boldAttribute, value: true, range: entry.range) }
        }
        return result
    }
}
