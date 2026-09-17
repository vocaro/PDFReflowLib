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
        /// UTF-16 offsets in `unicode` where a TJ adjustment between two glyphs of this show sets
        /// a word space without a space glyph (`sameFontWordSpace`), #119.
        var wordSpaces: Set<Int> = []
        /// UTF-16 offsets in `unicode` where sentence punctuation meets a capital or an opening
        /// quote with no measurable gap (`sentenceSpace`), #128.
        var sentenceSpaces: Set<Int> = []
        /// Sentence-space candidates whose word before or after reaches the edge of the show, with
        /// their gaps in em; `missingSpaces` decides them with the neighbouring shows on the line.
        var sentenceCandidates: [Int: CGFloat] = [:]
        /// Whether the show sets nonzero character or word spacing, the producer condition of #119.
        var spaced = false

        /// The characters of the show's last word (after its last space character, word space or
        /// sentence space), and whether that word begins the show.
        var lastWord: (word: [Unicode.Scalar], startsShow: Bool)? {
            guard let unicode else { return nil }
            return NativeSpacingReader.word(in: Array(unicode.unicodeScalars), offsets: NativeSpacingReader.offsets(unicode),
                                            before: unicode.unicodeScalars.count, breaks: wordSpaces.union(sentenceSpaces))
        }

        /// The show's first word, with a trailing space where a space, word space or sentence space
        /// ends it.
        var firstWord: [Unicode.Scalar] {
            guard let unicode else { return [] }
            return NativeSpacingReader.word(in: Array(unicode.unicodeScalars), offsets: NativeSpacingReader.offsets(unicode),
                                            from: 0, breaks: wordSpaces.union(sentenceSpaces))
        }

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
    ///
    /// Two same-font boundaries are also restored (#119, the 9/11 report): a word space that a
    /// TJ adjustment sets between two glyphs of one show (`Evidence.wordSpaces`), and a note
    /// reference, a raised show of digits in a smaller size, followed by a capital at a word gap.
    static func missingSpaces(in native: String, shows: [Evidence]) -> [Int]? {
        var source: [UInt16] = [], boundaries: Set<Int> = []
        var previous: Evidence?
        // The line's characters with their UTF-16 offsets in `source`, the sentence-space candidates
        // at show edges, and the show transitions that separate words (#128).
        var scalars: [Unicode.Scalar] = [], scalarOffsets: [Int] = [], candidates: [(Int, CGFloat)] = [], separated: Set<Int> = []
        func word(_ character: Character?) -> Bool { character.map { $0.isLetter || $0.isNumber } ?? false }
        // Punctuation that closes a word or a formula (Wallace's `6)|when`, `Second:|m`, #120): it
        // follows a character of its own show, or its one-character show follows the one before
        // without a word gap (a space, or 0.15 em on one baseline; a subscript's shift is no gap).
        var previousStart = 0, wordGaps: Set<Int> = []
        func closesWord(_ show: Evidence, start: Int) -> Bool {
            guard let characters = show.unicode.map(Array.init), let last = characters.last, ")],;:".contains(last) else { return false }
            if characters.count >= 2 { return !characters[characters.count - 2].isWhitespace }
            return start > 0 && !wordGaps.contains(start)
        }
        for show in shows.sorted(by: { $0.origin.x < $1.origin.x }) {
            guard let unicode = show.unicode, !unicode.isEmpty, source.count + unicode.utf16.count <= 8192 else { return nil }
            if let previous {
                let size = max(previous.size, show.size)
                if abs(previous.origin.y - show.origin.y) > size * 0.1 || previous.end.map({ show.origin.x - $0 >= size * 0.1 }) != false {
                    separated.insert(source.count)
                }
                if previous.unicode?.last?.isWhitespace == true
                    || abs(previous.origin.y - show.origin.y) <= size * 0.1 && previous.end.map({ show.origin.x - $0 >= size * 0.15 }) == true {
                    wordGaps.insert(source.count)
                }
            }
            scalars += unicode.unicodeScalars
            scalarOffsets += offsets(unicode).dropLast().map { source.count + $0 }
            candidates += show.sentenceCandidates.map { (source.count + $0.key, $0.value) }
            if let previous, let end = previous.end, previous.font != show.font,
               abs(previous.origin.y - show.origin.y) <= max(previous.size, show.size) * 0.1,
               show.origin.x - end >= max(previous.size, show.size) * 0.15,
               word(previous.unicode?.last) || closesWord(previous, start: previousStart) && unicode.first?.isLetter == true,
               word(unicode.first) {
                boundaries.insert(source.count)
            }
            if let previous, let end = previous.end, noteReference(previous, before: show, end: end) {
                boundaries.insert(source.count)
            }
            // A sentence boundary split across two shows on one baseline (9/11's semibold speaker
            // labels, `FAA:|Yes.`), in a producer that justifies with character or word spacing (#128).
            if let previous, let end = previous.end, previous.spaced || show.spaced,
               previous.size > 0, show.size > 0, min(previous.size, show.size) >= max(previous.size, show.size) * 0.8,
               abs(previous.origin.y - show.origin.y) <= max(previous.size, show.size) * 0.1,
               let (word, startsShow) = previous.lastWord,
               sentenceSpace(word: word, startsShow: startsShow, following: show.firstWord,
                             gap: (show.origin.x - end) / max(previous.size, show.size)) {
                boundaries.insert(source.count)
            }
            for offset in show.wordSpaces.union(show.sentenceSpaces) where offset > 0 && offset < unicode.utf16.count {
                boundaries.insert(source.count + offset)
            }
            previousStart = source.count
            source += unicode.utf16
            previous = show
        }
        if !candidates.isEmpty {
            let index = Dictionary(scalarOffsets.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
            let lineOffsets = scalarOffsets + [source.count]
            for (offset, gap) in candidates.sorted(by: { $0.0 < $1.0 }) {
                guard let k = index[offset] else { continue }
                let breaks = boundaries.union(separated)
                let (before, startsLine) = NativeSpacingReader.word(in: scalars, offsets: lineOffsets, before: k, breaks: breaks)
                let after = NativeSpacingReader.word(in: scalars, offsets: lineOffsets, from: k, breaks: breaks)
                if sentenceSpace(word: before, startsShow: startsLine, following: after, gap: gap) { boundaries.insert(offset) }
            }
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
        // A space glyph that ends the source line draws nothing; PDFKit trims it (9/11, #119).
        while i < source.count, j == extracted.count, whitespace(source[i]) { i += 1 }
        return i == source.count && j == extracted.count && !inserted.isEmpty ? inserted : nil
    }

    /// Word-space gaps measured on the 9/11 report's TJ arrays (#119), as min(adjustment,
    /// adjustment + Tc) in em between two glyphs of one show with no space glyph. Before a
    /// letter, a digit or `(`, kerns end at 0.059 em and word spaces begin at 0.075 em. After a
    /// lowercase letter or punctuation, a capital that overhangs to the left (A T V W Y) or an
    /// opening quote takes the space's kern into the gap: kerns, abbreviations and initials
    /// (`N.Y.`, `W. W.`) lie at or below 0.001 em and word spaces begin at 0.003 em. Between
    /// capitals the narrow mode is kerning (Replay Clocks' Libertine small caps, `WI|TH`,
    /// +0.037 em), so it takes the letter threshold.
    static let wordSpaceGap: CGFloat = 0.066
    static let overhangWordSpaceGap: CGFloat = 0.005
    /// Character spacing of at least this many em between the two glyphs of a show is a column
    /// gap (#120: FAA's chart tables set 0.59–1.58 em; its letter-spacing stays at or below 0.2 em).
    static let characterSpacingColumnGap: CGFloat = 0.5

    /// Whether a same-font gap of `gap` em between `left` and `right` (after `before`, the
    /// character preceding `left`) is a word space. The left side ends a word (a letter, a digit,
    /// sentence punctuation or a closing quote or parenthesis) and the right side starts one (a
    /// letter, a digit, an opening quote or parenthesis). A period or colon between digits (`3.5`, `8:46`)
    /// is never a boundary, nor is a mathematical letter (TeX math italic sets kerns and italic
    /// corrections, Replay Clocks' `ℎ𝑙𝑐.𝑓`), and gaps above one em are not word spaces.
    ///
    /// A chained initial, a capital and a period before a capital that `after` (the character
    /// following `right`) makes an initial too (`C.|A.`), takes the letter threshold like two
    /// capitals: NOAA's Lora kerns `.|A` by +0.027 em inside initials it sets closed (`B.A. Muhling`)
    /// on lines with word spacing of -0.002 em (#120, reached once shows that continue the cursor
    /// were read).
    static func sameFontWordSpace(before: Unicode.Scalar?, left: Unicode.Scalar, right: Unicode.Scalar, gap: CGFloat,
                                  after: Unicode.Scalar? = nil) -> Bool {
        func mathematical(_ scalar: Unicode.Scalar) -> Bool {
            (0x1D400...0x1D7FF).contains(scalar.value) || (0x2100...0x214F).contains(scalar.value)
        }
        let letters = CharacterSet.letters, digits = CharacterSet.decimalDigits
        let closing = ".,;:?!\u{201D}\u{2019})".unicodeScalars.contains(left)
        let leftWord = letters.contains(left) || digits.contains(left) || closing
        let overhang = "ATVWY\u{201C}\u{2018}".unicodeScalars.contains(right)
        let rightWord = overhang || letters.contains(right) || digits.contains(right) || right == "("
        guard leftWord, rightWord, !mathematical(left), !mathematical(right), gap.isFinite, gap <= 1 else { return false }
        if ".:".unicodeScalars.contains(left), let before, digits.contains(before), digits.contains(right) { return false }
        let chained = left == "." && before.map(CharacterSet.uppercaseLetters.contains) == true && after == "."
        let narrow = overhang && (closing || CharacterSet.lowercaseLetters.contains(left)) && !chained
        return gap >= (narrow ? overhangWordSpaceGap : wordSpaceGap)
    }

    /// A note reference set as its own show (9/11: a 7.2-point digit raised 2.25 points before
    /// 10.25-point text): one to four digits at most 0.8 of the next show's size, raised by 0.15
    /// to 0.6 of it, followed on the text's baseline by a capital or an opening quote at a word
    /// gap in em of the reference's size.
    static func noteReference(_ note: Evidence, before show: Evidence, end: CGFloat) -> Bool {
        guard let digits = note.unicode, (1...4).contains(digits.unicodeScalars.count),
              digits.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) }),
              let first = show.unicode?.unicodeScalars.first,
              CharacterSet.uppercaseLetters.contains(first) || first == "\u{201C}",
              note.size > 0, show.size > 0, note.size <= show.size * 0.8 else { return false }
        let raise = note.origin.y - show.origin.y, gap = (show.origin.x - end) / note.size
        return raise >= show.size * 0.15 && raise <= show.size * 0.6 && gap >= wordSpaceGap && gap <= 1
    }

    /// The UTF-16 offset of each Unicode scalar of `string`, plus the string's length.
    static func offsets(_ string: String) -> [Int] {
        var result: [Int] = [], offset = 0
        for scalar in string.unicodeScalars { result.append(offset); offset += scalar.utf16.count }
        return result + [offset]
    }

    /// The word that ends before scalar `index`: the scalars back to a whitespace character or
    /// to a scalar whose UTF-16 offset is a break, and whether it reaches the start.
    static func word(in scalars: [Unicode.Scalar], offsets: [Int], before index: Int,
                     breaks: Set<Int>) -> (word: [Unicode.Scalar], startsShow: Bool) {
        var start = index
        while start > 0, !scalars[start - 1].properties.isWhitespace, !breaks.contains(offsets[start]) { start -= 1 }
        return (Array(scalars[start..<index]), start == 0 && !breaks.contains(offsets[0]))
    }

    /// The word that starts at scalar `index`, up to a whitespace character or a break, with a
    /// space appended where one of those ends it (none where the show ends).
    static func word(in scalars: [Unicode.Scalar], offsets: [Int], from index: Int, breaks: Set<Int>) -> [Unicode.Scalar] {
        var end = index
        while end < scalars.count, !scalars[end].properties.isWhitespace, end == index || !breaks.contains(offsets[end]) { end += 1 }
        return Array(scalars[index..<end]) + (end < scalars.count ? [" "] : [])
    }

    /// Sentence spaces that a kern before an overhanging capital absorbs entirely (#128). 9/11 sets
    /// 331 sentence boundaries such as `casualties.The` at -0.13 to +0.005 em, where abbreviations
    /// and initials also lie, so no gap separates them. Measured on the book's own boundaries after a
    /// period before a capital, a word followed by a capitalized word or an acronym is spaced in 5,646
    /// of 5,977 (`U.S.|Army` 157 of 157, an initial `H.|Kean` 230 of 236); the only form set closed is
    /// a capital that continues an abbreviation, a capital followed by a period (`U.|S.`, `D.|C.`,
    /// `N.|Y.`: 781 of 791). So a boundary is a sentence space when:
    /// - `word`, the characters before it back to a space, ends with `. , ; : ? !`, optionally
    ///   followed by closing quotes, parentheses or brackets (`Jews.”|The`);
    /// - the punctuation follows a letter or digit, or a closing parenthesis, bracket or quote
    ///   (`(OMB).|They`); an apostrophe after a letter (`O’|Neill`, `QAEDA’|S`) and an ellipsis are not;
    /// - `following`, the word after it (with a trailing space where a space or word space ends it),
    ///   starts with a capital not followed by a period, or with an opening quote before a letter or
    ///   digit;
    /// - an initial (a capital and at most one more letter) is not followed by a capitalized
    ///   abbreviation of at most four letters that ends with a period, which is set closed (Our Flag's
    ///   title page `H.Doc. 108-97`);
    /// - the word holds no address characters (`/ @ = \`, `www`: `print.php3?|ReportID`) and no
    ///   mathematical letters;
    /// - a period does not end a number that begins the show (list and note numbers, `10.|August 2001`,
    ///   `21.|While`);
    /// - the gap is between -0.15 and 1 em.
    static func sentenceSpace(word: [Unicode.Scalar], startsShow: Bool, following: [Unicode.Scalar], gap: CGFloat) -> Bool {
        func mathematical(_ scalar: Unicode.Scalar) -> Bool {
            (0x1D400...0x1D7FF).contains(scalar.value) || (0x2100...0x214F).contains(scalar.value)
        }
        let alphanumerics = CharacterSet.alphanumerics, letters = CharacterSet.letters
        guard gap.isFinite, gap >= -0.15, gap <= 1, following.count > 1 else { return false }
        let right = following[0], next = following[1]
        guard !mathematical(right), !mathematical(next) else { return false }
        if right == "\u{201C}" || right == "\u{2018}" {
            guard alphanumerics.contains(next) else { return false }
        } else {
            guard CharacterSet.uppercaseLetters.contains(right), next != "." else { return false }
        }
        let closers = "\u{201D}\u{2019})]".unicodeScalars
        var end = word.count
        while end > 0, closers.contains(word[end - 1]) { end -= 1 }
        guard end > 1, ".,;:?!".unicodeScalars.contains(word[end - 1]) else { return false }
        let body = word[..<(end - 1)], last = body[body.endIndex - 1]
        guard !body.contains(where: { "/@=\\".unicodeScalars.contains($0) || mathematical($0) }),
              !String(String.UnicodeScalarView(body)).lowercased().contains("www") else { return false }
        if closers.contains(last) { return !body.dropLast().allSatisfy { closers.contains($0) } }
        guard alphanumerics.contains(last) else { return false }
        guard word[end - 1] == "." else { return true }
        if startsShow, body.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) { return false }
        let initial = Array(body.reversed().prefix { letters.contains($0) }.reversed())
        let abbreviation = following.last == " " ? Array(following.dropLast()) : following
        return !((1...2).contains(initial.count) && CharacterSet.uppercaseLetters.contains(initial[0])
                 && (3...5).contains(abbreviation.count) && abbreviation.last == "."
                 && abbreviation.dropLast().allSatisfy { letters.contains($0) })
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

    /// A simple font's ToUnicode map (Type1, TrueType, MMType1). A simple font's codes are one
    /// byte whatever its map declares, and Adobe PDF Library writes one-byte entries under a
    /// two-byte `<0000> <FFFF>` codespace (FAA, DGA, Fed), so that codespace is read as one byte.
    /// Any entry that is not one byte, and any other codespace, still fails the parse (#91, #104).
    static func simpleFontUnicodeMap(_ data: Data) -> [UInt8: String]? {
        guard data.count <= 65_536, let text = String(data: data, encoding: .isoLatin1),
              let normalized = text.replacingOccurrences(
                of: #"begincodespacerange\s*<0000>\s*<[fF]{4}>\s*endcodespacerange"#,
                with: "begincodespacerange <00> <FF> endcodespacerange", options: .regularExpression
              ).data(using: .isoLatin1) else { return nil }
        return unicodeMap(normalized)
    }

    /// One `Differences` array element: a code that starts a run, or the next code's glyph name.
    enum EncodingDifference: Equatable {
        case code(Int)
        case name(String)
    }

    /// Adobe Glyph List names a `Differences` array may assign: printable ASCII, and the quotes,
    /// dashes and ligatures TeX text fonts encode there. Any other name leaves its code undecoded.
    static let differenceGlyphs: [String: String] = {
        var table: [String: String] = [
            "space": " ", "exclam": "!", "quotedbl": "\"", "numbersign": "#", "dollar": "$", "percent": "%",
            "ampersand": "&", "quotesingle": "'", "parenleft": "(", "parenright": ")", "asterisk": "*",
            "plus": "+", "comma": ",", "hyphen": "-", "period": ".", "slash": "/", "colon": ":",
            "semicolon": ";", "less": "<", "equal": "=", "greater": ">", "question": "?", "at": "@",
            "bracketleft": "[", "backslash": "\\", "bracketright": "]", "asciicircum": "^",
            "underscore": "_", "grave": "`", "braceleft": "{", "bar": "|", "braceright": "}",
            "asciitilde": "~", "quoteleft": "\u{2018}", "quoteright": "\u{2019}",
            "quotedblleft": "\u{201C}", "quotedblright": "\u{201D}", "endash": "\u{2013}",
            "emdash": "\u{2014}", "ff": "\u{FB00}", "fi": "\u{FB01}", "fl": "\u{FB02}",
            "ffi": "\u{FB03}", "ffl": "\u{FB04}",
        ]
        for (index, name) in ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"].enumerated() {
            table[name] = String(index)
        }
        for scalar in UInt8(ascii: "A")...UInt8(ascii: "Z") {
            let upper = String(UnicodeScalar(scalar))
            table[upper] = upper
            table[upper.lowercased()] = upper.lowercased()
        }
        return table
    }()

    /// The codes of a Type1 font without a ToUnicode map, read through `WinAnsiEncoding` (#110).
    /// Ghostscript's TeX output (Wallace) writes no ToUnicode for its Computer Modern fonts, only
    /// this encoding, by name or as the `BaseEncoding` of a `Differences` dictionary. A Type1
    /// font draws the glyph its encoding names, so codes 32–126 read as the ASCII characters
    /// WinAnsi names, and a `Differences` entry gives its code the character of its glyph name
    /// (`differenceGlyphs`). An unknown name removes its code, so no line that draws it can be
    /// matched. More than 256 entries, a name before any code, or a code outside 0–255 fails.
    static func winAnsiUnicodeMap(differences: [EncodingDifference]) -> [UInt8: String]? {
        guard differences.count <= 256 else { return nil }
        var result: [UInt8: String] = [:]
        for code in UInt8(32)...126 { result[code] = String(UnicodeScalar(code)) }
        var next: Int?
        for entry in differences {
            switch entry {
            case .code(let code):
                guard (0...255).contains(code) else { return nil }
                next = code
            case .name(let name):
                guard let code = next, code <= 255 else { return nil }
                result[UInt8(code)] = differenceGlyphs[name]
                next = code + 1
            }
        }
        return result
    }

    static func encodingUnicodeMap(_ dict: CGPDFDictionaryRef) -> [UInt8: String]? {
        var name: UnsafePointer<CChar>?, encoding: CGPDFDictionaryRef?
        if CGPDFDictionaryGetName(dict, "Encoding", &name), let name {
            return String(cString: name) == "WinAnsiEncoding" ? winAnsiUnicodeMap(differences: []) : nil
        }
        var base: UnsafePointer<CChar>?, array: CGPDFArrayRef?
        guard CGPDFDictionaryGetDictionary(dict, "Encoding", &encoding), let encoding,
              CGPDFDictionaryGetName(encoding, "BaseEncoding", &base), let base,
              String(cString: base) == "WinAnsiEncoding" else { return nil }
        guard CGPDFDictionaryGetArray(encoding, "Differences", &array), let array else {
            return winAnsiUnicodeMap(differences: [])
        }
        let count = CGPDFArrayGetCount(array)
        guard count <= 256 else { return nil }
        var differences: [EncodingDifference] = []
        for index in 0..<count {
            var code: CGPDFInteger = 0, glyph: UnsafePointer<CChar>?
            if CGPDFArrayGetInteger(array, index, &code) {
                differences.append(.code(code))
            } else if CGPDFArrayGetName(array, index, &glyph), let glyph {
                differences.append(.name(String(cString: glyph)))
            } else { return nil }
        }
        return winAnsiUnicodeMap(differences: differences)
    }

    private struct Font {
        var id: Int
        /// The Type3 identity-matrix bfchar map that authorizes space removal.
        var map: [UInt8: String]?
        /// Any supported one-byte ToUnicode map, or a Type1 font's WinAnsi encoding without one,
        /// for word-boundary evidence.
        var unicode: [UInt8: String]?
        /// Simple-font glyph advances in text space per unit of font size.
        var widths: [UInt8: CGFloat]?
    }
    private final class State {
        var matrix = CGAffineTransform.identity
        /// The text line matrix (Tlm), which `Td`, `TD` and `T*` move, and the text matrix (Tm),
        /// which a show advances (#120).
        var line = CGAffineTransform.identity
        var text = CGAffineTransform.identity
        var font: Font?
        var size: CGFloat = 0
        var leading: CGFloat = 0
        /// Character and word spacing (`Tc`, `Tw`) in unscaled text space units (#119).
        var characterSpacing: CGFloat = 0
        var wordSpacing: CGFloat = 0
        var saved: [(CGAffineTransform, Font?, CGFloat, CGFloat, CGFloat, CGFloat)] = []
        var inText = false
        var positioned = false
        var invalid = false
        var operations = 0
        var fontSelections = 0
        var fonts: [Int: Font?] = [:]
        var evidence: [Evidence] = []
        var decodings: [String: [UInt8: String]] = [:]

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
            // A show that continues the text cursor needs the previous show's complete advance.
            guard positioned else { invalid = true; return }
            positioned = false
            let transform = text.concatenating(matrix)
            guard transform.tx.isFinite, transform.ty.isFinite, transform.a.isFinite else { invalid = true; return }
            // Rotated or mirrored text (a margin stamp) supplies no word-boundary evidence and
            // does not disqualify the page's upright text.
            guard transform.b == 0, transform.c == 0, transform.a > 0, transform.d > 0 else { return }
            var item = Evidence(origin: CGPoint(x: transform.tx, y: transform.ty), size: size * transform.a, font: font?.id ?? 0)
            // Type3 space removal models no character or word spacing.
            var value = "", gaps: Set<Int> = [], valid = font?.map != nil && size > 0 && characterSpacing == 0 && wordSpacing == 0
            var unicode = "", advance: CGFloat = 0, trailingSpacing: CGFloat = 0, glyphStarts: Set<Int> = []
            var decodable = font?.unicode != nil && size > 0, measurable = font?.widths != nil && size > 0
            let spacing = (characterSpacing, wordSpacing)
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
                        glyphStarts.insert(unicode.utf16.count)
                        unicode += decoded
                    } else { decodable = false }
                    // A simple font's code 32 is the space that word spacing widens.
                    trailingSpacing = spacing.0 + (code == 32 ? spacing.1 : 0)
                    if measurable, let width = font.widths?[code] { advance += width * size + trailingSpacing } else { measurable = false }
                }
            }
            /// Adjusted boundaries between strings: the UTF-16 offset, the gap in em, the index of
            /// the non-empty string after it and the code count of the one before it.
            var boundaries: [(offset: Int, gap: CGFloat, string: Int, before: Int)] = []
            var trailingAdjustment: CGFloat = 0
            if let values {
                var previousWasString = false
                // An adjustment moves the glyphs after it. A trailing one moves none of this show's
                // glyphs, so it cannot shorten the measured end (#110: Ghostscript ends each TeX math
                // show with one, `[(5)178.4]TJ`); it moves only a show that continues the cursor.
                var pending: CGFloat = 0
                defer { trailingAdjustment = pending }
                // Adjustment units since the last glyph, the number of non-empty strings so far,
                // and the code count of the last one.
                var sinceGlyph: CGFloat = 0, strings = 0, lastCount = 0
                // Where adjustments offset a character spacing of a tenth of an em or more (by at
                // least half of it), two glyphs of one string stand the character spacing apart: the
                // Census report's Distiller sets `Journal of Official Statistics` at Tc 0.38 em with
                // +349 to +378 between letters, and each word gap as two glyphs of one string (#143).
                let characterSpacing = size > 0 ? spacing.0 / size : 0
                var compensated = false
                for i in 0..<CGPDFArrayGetCount(values) where characterSpacing >= 0.1 && !compensated {
                    var number: CGPDFReal = 0
                    if CGPDFArrayGetNumber(values, i, &number), number / 1000 >= characterSpacing / 2 { compensated = true }
                }
                for i in 0..<CGPDFArrayGetCount(values) {
                    var string: CGPDFStringRef?
                    var number: CGPDFReal = 0
                    if CGPDFArrayGetString(values, i, &string), let string {
                        advance -= pending; pending = 0
                        let offset = unicode.utf16.count, count = CGPDFStringGetLength(string)
                        if count > 0, strings > 0, sinceGlyph != 0 || compensated, size > 0 {
                            // The glyphs' own gap in em: the adjustment, less any negative character
                            // spacing that cancels it (9/11's `9:34` sets +31 against Tc -0.031 em).
                            // Where adjustments offset a large character spacing (`compensated`), the gap is
                            // their sum: the Census report's Distiller sets Tc 0.46 em with +446 between
                            // letters and -13 at a word (#143).
                            let adjustment = -sinceGlyph / 1000
                            let gap = compensated ? adjustment + characterSpacing : min(adjustment, adjustment + characterSpacing)
                            boundaries.append((offset, gap, strings, lastCount))
                        }
                        append(string); previousWasString = true
                        if compensated, count > 1 {
                            for start in glyphStarts.sorted() where start > offset {
                                // A quad after a section number (`2 Data Files`, 1.1 em) is still one word gap.
                                boundaries.append((start, min(1, characterSpacing), strings, count))
                            }
                        }
                        if count > 0 { strings += 1; lastCount = count; sinceGlyph = 0 }
                    } else if CGPDFArrayGetNumber(values, i, &number), number.isFinite {
                        sinceGlyph += number
                        // Consecutive/initial adjustments and actual word-size gaps are ambiguous.
                        if !previousWasString || number < -10 { valid = false }
                        if number < 0 && number >= -10 { gaps.insert(value.utf16.count) }
                        previousWasString = false
                        pending += number / 1000 * size
                    } else { valid = false; decodable = false; measurable = false }
                }
            } else if let single {
                append(single)
            }
            if value.hasSuffix("\n") { value.removeLast() }
            if valid, !value.isEmpty, value.utf16.allSatisfy({ (32...126).contains($0) }) {
                item.text = value; item.smallGaps = gaps
            }
            if decodable, !unicode.isEmpty {
                item.unicode = unicode
            }
            // Word spaces inside a show are read only where the producer justifies with character or
            // word spacing and folds a kerned space into an adjustment (9/11's Distiller output: 99.9%
            // of its dropped spaces). Without that state, TeX and InDesign write word spaces as space
            // glyphs or full adjustments that PDFKit keeps, and narrow gaps are kerns: NOAA's Lora
            // `E.|A.` at +0.027 em, Wallace's juxtaposed CMMI variables `x|y`.
            if decodable, !unicode.isEmpty, spacing.0 != 0 || spacing.1 != 0 {
                let scalars = unicode.utf16
                func scalar(before offset: Int) -> (Unicode.Scalar, Int)? {
                    guard offset > 0 else { return nil }
                    let index = String.Index(utf16Offset: offset, in: unicode)
                    guard let previous = unicode.unicodeScalars.index(index, offsetBy: -1, limitedBy: unicode.unicodeScalars.startIndex) else { return nil }
                    return (unicode.unicodeScalars[previous], previous.utf16Offset(in: unicode))
                }
                let words = boundaries.map { boundary -> Bool in
                    guard boundary.offset > 0, boundary.offset < scalars.count,
                          let (left, leftOffset) = scalar(before: boundary.offset) else { return false }
                    let rightIndex = String.Index(utf16Offset: boundary.offset, in: unicode)
                    let right = unicode.unicodeScalars[rightIndex]
                    let afterIndex = unicode.unicodeScalars.index(after: rightIndex)
                    return NativeSpacingReader.sameFontWordSpace(before: scalar(before: leftOffset)?.0, left: left, right: right, gap: boundary.gap,
                                                                 after: afterIndex < unicode.unicodeScalars.endIndex ? unicode.unicodeScalars[afterIndex] : nil)
                }
                // Letter-spaced type (`C H A P`) adjusts every glyph alike: a boundary beside a
                // one-glyph string whose other side is also a word gap is not a word space.
                for (k, boundary) in boundaries.enumerated() where words[k] {
                    let spaced = boundaries.indices.contains { n in
                        words[n] && (boundaries[n].string == boundary.string - 1 && boundary.before == 1
                            || boundaries[n].string == boundary.string + 1 && boundaries[n].before == 1)
                    }
                    if !spaced { item.wordSpaces.insert(boundary.offset) }
                }
                // A column gap set as character spacing (#120, FAA page 458's chart table:
                // `(68)Tj 1.465 Tc -1.465 Tw (52)Tj` draws `1,685 2,599`). FAA's letter-spacing ends at
                // 0.2 em; its column gaps start at 0.6 em. Only a two-glyph show is read, so
                // letter-spaced type cannot split.
                let characterGap = spacing.0 / size
                if boundaries.isEmpty, glyphStarts.count == 2, characterGap >= NativeSpacingReader.characterSpacingColumnGap,
                   characterGap <= 10, let offset = glyphStarts.max(), offset > 0, offset < unicode.utf16.count,
                   let (left, _) = scalar(before: offset) {
                    let right = unicode.unicodeScalars[String.Index(utf16Offset: offset, in: unicode)]
                    // The characters follow the in-show word-space classes; the gap itself is above them.
                    if NativeSpacingReader.sameFontWordSpace(before: nil, left: left, right: right, gap: 1) {
                        item.wordSpaces.insert(offset)
                    }
                }
                // Sentence spaces with no measurable gap (#128): at every glyph boundary between
                // sentence punctuation and a capital or opening quote that is not already a word
                // space. A boundary without an adjustment has the character spacing as its gap.
                item.spaced = true
                let characters = Array(unicode.unicodeScalars), offsets = NativeSpacingReader.offsets(unicode)
                let gaps = Dictionary(boundaries.map { ($0.offset, $0.gap) }, uniquingKeysWith: { first, _ in first })
                let lefts = ".,;:?!\u{201D}\u{2019})]".unicodeScalars
                for k in characters.indices.dropFirst() where lefts.contains(characters[k - 1]) {
                    let offset = offsets[k]
                    guard glyphStarts.contains(offset), !item.wordSpaces.contains(offset) else { continue }
                    let breaks = item.wordSpaces.union(item.sentenceSpaces)
                    let (word, startsShow) = NativeSpacingReader.word(in: characters, offsets: offsets, before: k, breaks: breaks)
                    let following = NativeSpacingReader.word(in: characters, offsets: offsets, from: k, breaks: breaks)
                    let gap = gaps[offset] ?? min(0, spacing.0 / size)
                    if NativeSpacingReader.sentenceSpace(word: word, startsShow: startsShow, following: following, gap: gap) {
                        item.sentenceSpaces.insert(offset)
                    } else if startsShow || following.last != " " {
                        // The word or the capital's word continues into another show (an italic
                        // title, `Encyclopedia|.Six`; a show split inside a word, `June,T|enet`).
                        item.sentenceCandidates[offset] = gap
                    }
                }
            }
            // A glyph's ink ends at its width; the spacing after the last one moves no glyph.
            if measurable, advance.isFinite, advance >= 0 { item.end = transform.tx + (advance - trailingSpacing) * transform.a }
            evidence.append(item)
            // The next show may continue from this one's full advance, spacing and adjustments
            // included (Replay Clocks page 10's reference list, `[([8])]TJ 0 g 0 G [-571(D)…]TJ`, #120).
            let full = advance - trailingAdjustment
            if measurable, full.isFinite, abs(full) <= 100_000 {
                text = text.translatedBy(x: full, y: 0); positioned = true
            }
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
    private static func font(_ dict: CGPDFDictionaryRef, decodings: [String: [UInt8: String]]) -> Font? {
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
        if let data {
            result.unicode = simpleFontUnicodeMap(data)
        } else if !decodings.isEmpty, let index = FontWeightReader.indexGlyphFont(dict), let decoded = decodings[index.key] {
            // Index-named glyphs read through the characters the document established (#143).
            result.unicode = decoded
        } else if kind != "TrueType" {
            result.unicode = encodingUnicodeMap(dict)
        }
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

    private final class FontPresence {
        var found = false
        var decoded: Set<String> = []
    }
    /// A Type3 font, or a simple font whose ToUnicode map and Widths can supply word-boundary
    /// evidence. Pages without either skip the operator scan entirely.
    private static func hasSupportedFont(_ page: CGPDFPage, decoded: Set<String>) -> Bool {
        var node: CGPDFDictionaryRef? = page.dictionary
        for _ in 0..<64 {
            guard let current = node else { return false }
            var resources: CGPDFDictionaryRef?, fonts: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(current, "Resources", &resources), let resources {
                guard CGPDFDictionaryGetDictionary(resources, "Font", &fonts), let fonts else { return false }
                let presence = FontPresence()
                presence.decoded = decoded
                CGPDFDictionaryApplyFunction(fonts, { _, object, info in
                    let presence = Unmanaged<FontPresence>.fromOpaque(info!).takeUnretainedValue()
                    var dict: CGPDFDictionaryRef?, subtype: UnsafePointer<CChar>?, stream: CGPDFStreamRef?, widths: CGPDFArrayRef?
                    guard CGPDFObjectGetValue(object, .dictionary, &dict), let dict,
                          CGPDFDictionaryGetName(dict, "Subtype", &subtype), let subtype else { return }
                    let kind = String(cString: subtype)
                    let simple = ["Type1", "TrueType", "MMType1"].contains(kind)
                        && CGPDFDictionaryGetArray(dict, "Widths", &widths)
                        && (CGPDFDictionaryGetStream(dict, "ToUnicode", &stream)
                            || kind != "TrueType" && NativeSpacingReader.encodingUnicodeMap(dict) != nil
                            || !presence.decoded.isEmpty && FontWeightReader.indexGlyphFont(dict).map { presence.decoded.contains($0.key) } == true)
                    if kind == "Type3" || simple {
                        presence.found = true
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

    /// `decodings` are the characters the document established for index-glyph fonts (#143).
    static func read(_ page: CGPDFPage, decodings: [String: [UInt8: String]] = [:]) -> [Evidence] {
        guard page.rotationAngle == 0, hasSupportedFont(page, decoded: Set(decodings.keys)),
              let table = CGPDFOperatorTableCreate() else { return [] }
        defer { CGPDFOperatorTableRelease(table) }
        CGPDFOperatorTableSetCallback(table, "q") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), !s.inText, s.saved.count < 128 else { s.invalid = true; return }
            s.saved.append((s.matrix, s.font, s.size, s.leading, s.characterSpacing, s.wordSpacing))
        }
        CGPDFOperatorTableSetCallback(table, "Q") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), !s.inText, let saved = s.saved.popLast() else { s.invalid = true; return }
            (s.matrix, s.font, s.size, s.leading, s.characterSpacing, s.wordSpacing) = saved
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
                s.font = Self.font(dict, decodings: s.decodings); s.fonts[id] = s.font
            }
        }
        CGPDFOperatorTableSetCallback(table, "BT") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), !s.inText else { s.invalid = true; return }
            s.inText = true; s.line = .identity; s.text = .identity; s.positioned = false
        }
        CGPDFOperatorTableSetCallback(table, "ET") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), s.inText else { s.invalid = true; return }
            s.inText = false; s.positioned = false
        }
        CGPDFOperatorTableSetCallback(table, "Tm") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), s.inText, let n = Self.numbers(scanner, 6) else { s.invalid = true; return }
            s.line = CGAffineTransform(a: n[0], b: n[1], c: n[2], d: n[3], tx: n[4], ty: n[5]); s.text = s.line; s.positioned = true
        }
        CGPDFOperatorTableSetCallback(table, "Td") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), s.inText, let n = Self.numbers(scanner, 2) else { s.invalid = true; return }
            s.line = s.line.translatedBy(x: n[0], y: n[1]); s.text = s.line; s.positioned = true
        }
        CGPDFOperatorTableSetCallback(table, "TD") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), s.inText, let n = Self.numbers(scanner, 2) else { s.invalid = true; return }
            s.leading = -n[1]; s.line = s.line.translatedBy(x: n[0], y: n[1]); s.text = s.line; s.positioned = true
        }
        CGPDFOperatorTableSetCallback(table, "T*") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), s.inText else { s.invalid = true; return }
            s.line = s.line.translatedBy(x: 0, y: -s.leading); s.text = s.line; s.positioned = true
        }
        CGPDFOperatorTableSetCallback(table, "TL") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), let n = Self.numbers(scanner, 1) else { s.invalid = true; return }
            s.leading = n[0]
        }
        // Character and word spacing move glyphs along the baseline and are measured (#119: every
        // 9/11 page justifies with them). A value beyond one em per glyph is not typesetting.
        CGPDFOperatorTableSetCallback(table, "Tc") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), let n = Self.numbers(scanner, 1), abs(n[0]) <= 1000 else { s.invalid = true; return }
            s.characterSpacing = n[0]
        }
        CGPDFOperatorTableSetCallback(table, "Tw") { scanner, info in
            let s = Self.state(info)
            guard s.accept(scanner), let n = Self.numbers(scanner, 1), abs(n[0]) <= 1000 else { s.invalid = true; return }
            s.wordSpacing = n[0]
        }
        // State or placement that this reader does not model disqualifies the whole page.
        for op in ["Ts", "Tr"] {
            CGPDFOperatorTableSetCallback(table, op) { scanner, info in
                let s = Self.state(info)
                if !s.accept(scanner) || Self.numbers(scanner, 1) != [0] { s.invalid = true }
            }
        }
        CGPDFOperatorTableSetCallback(table, "Tz") { scanner, info in
            let s = Self.state(info)
            if !s.accept(scanner) || Self.numbers(scanner, 1) != [100] { s.invalid = true }
        }
        // A graphics state parameter dictionary moves no text unless it selects a font; one that
        // does, or a missing resource, is unmodeled (#110: every Wallace page sets `/OPM` by `gs`).
        CGPDFOperatorTableSetCallback(table, "gs") { scanner, info in
            let s = Self.state(info)
            var name: UnsafePointer<CChar>?, dict: CGPDFDictionaryRef?, font: CGPDFObjectRef?
            guard s.accept(scanner), CGPDFScannerPopName(scanner, &name), let name,
                  let object = CGPDFContentStreamGetResource(CGPDFScannerGetContentStream(scanner), "ExtGState", name),
                  CGPDFObjectGetValue(object, .dictionary, &dict), let dict,
                  !CGPDFDictionaryGetObject(dict, "Font", &font) else {
                s.invalid = true; return
            }
        }
        for op in ["'", "\"", "BI"] {
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
        s.decodings = decodings
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
        // One show can carry word spaces of its own (#119); a font change needs two.
        guard let offsets = missingSpaces(in: attributed.string, shows: matches) else { return attributed }
        for offset in offsets.reversed() {
            let attributes = repaired.attributes(at: offset - 1, effectiveRange: nil)
            repaired.insert(NSAttributedString(string: " ", attributes: attributes), at: offset)
        }
        return repaired
    }
}
