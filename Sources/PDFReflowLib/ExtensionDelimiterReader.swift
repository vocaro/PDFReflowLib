import Foundation
import CoreGraphics
#if os(macOS)
import AppKit
private typealias PlatformFont = NSFont
#else
import UIKit
private typealias PlatformFont = UIFont
#endif

/// The sized delimiters a TeX math extension font draws without stating a character for them
/// (#305).
///
/// TeX draws a `\big(` or the parentheses `\left(`/`\right)` choose around a tall group from its
/// extension font (CMEX10, and the fonts that follow its layout, such as txexs), which names each
/// glyph for its shape and size: `parenleftbig`, `parenrightBig`, `bracketleftbigg`. No glyph list
/// gives those names a character, and the font's `ToUnicode` map, where it has one, covers only the
/// pieces a display builds its tallest brackets from, so PDFKit reads nothing at all where they
/// stand. Wallace page 178 prints `(a²)³` and its text layer spells `a2 3`: the reader cannot tell
/// it from a²³.
///
/// This reader establishes the character from the name the font's own resources give its code: a
/// `Differences` array, or the built-in encoding of an embedded Type 1 program whose descriptor's
/// `CharSet` lists a sized delimiter. Only the sized delimiters are read (parentheses, square
/// brackets, braces, floor and ceiling brackets, angle brackets and the two slashes, in TeX's four
/// sizes); a radical, an extensible piece or a big operator is not a character a line of text can
/// hold, and a code the font's map states is PDFKit's to read. It never invents a character: a
/// delimiter enters a line only where the page's own shows around it place it there
/// (`placements`, `apply`), and anything it cannot place leaves the line as PDFKit read it.
enum ExtensionDelimiterReader {
    /// Which side of what it encloses a delimiter stands on: an opening delimiter belongs with what
    /// follows it, a closing one with what precedes it.
    enum Side: Equatable, Sendable { case opening, closing, neither }

    /// A glyph an extension font names as a sized delimiter: its character, its side, and how far
    /// below its origin it reaches, in em.
    struct Glyph: Equatable, Sendable {
        var character: String
        var side: Side
        var depth: CGFloat
    }

    /// One delimiter as the page draws it, in page space.
    struct Delimiter: Equatable, Sendable {
        var character: String
        var side: Side
        var origin: CGPoint
        /// Where its advance ends.
        var end: CGFloat
        /// Its font size in page space.
        var size: CGFloat
        /// How far below its origin it reaches, in em.
        var depth: CGFloat
        /// The origin of the show that drew it, which `NativeSpacingReader` records as one show of
        /// no known text; and whether that show drew nothing but delimiters this reader states.
        var show: CGPoint
        var alone: Bool

        /// TeX's extension delimiters hang from their origin: each rises 0.04 em above it.
        static let height: CGFloat = 0.04
        var top: CGFloat { origin.y + Self.height * size }
        var bottom: CGFloat { origin.y - depth * size }
    }

    // MARK: - Glyph names

    private static let shapes: [String: (character: String, side: Side)] = [
        "parenleft": ("(", .opening), "parenright": (")", .closing),
        "bracketleft": ("[", .opening), "bracketright": ("]", .closing),
        "braceleft": ("{", .opening), "braceright": ("}", .closing),
        "floorleft": ("\u{230A}", .opening), "floorright": ("\u{230B}", .closing),
        "ceilingleft": ("\u{2308}", .opening), "ceilingright": ("\u{2309}", .closing),
        "angbracketleft": ("\u{27E8}", .opening), "angbracketright": ("\u{27E9}", .closing),
        "slash": ("/", .neither), "backslash": ("\\", .neither),
    ]

    /// TeX's four delimiter sizes and the depth CMEX10 gives each below its origin, in em; every one
    /// rises `Delimiter.height` above it.
    private static let sizes: [(suffix: String, depth: CGFloat)] = [
        ("big", 1.16), ("Big", 1.76), ("bigg", 2.36), ("Bigg", 2.96),
    ]

    /// The sized delimiter a glyph name states, or nil for any other name: `parenleftbig` is `(`,
    /// but `parenlefttp` (an extensible piece), `radicalbig` and `summationtext` are none.
    static func glyph(named name: String) -> Glyph? {
        for (suffix, depth) in sizes where name.hasSuffix(suffix) {
            guard let shape = shapes[String(name.dropLast(suffix.count))] else { continue }
            return Glyph(character: shape.character, side: shape.side, depth: depth)
        }
        return nil
    }

    // MARK: - Font evidence

    /// The names a Type 1 program's built-in encoding gives its codes (`dup 16 /parenleftBig put`),
    /// read from the program's clear-text part; empty for a program that uses `StandardEncoding`.
    static func builtInEncoding(_ program: String) -> [UInt8: String] {
        guard let start = program.range(of: "/Encoding") else { return [:] }
        let text = program[start.upperBound...]
        let end = text.range(of: "readonly def")?.lowerBound ?? text.range(of: "currentfile eexec")?.lowerBound
            ?? text.endIndex
        let body = String(text[..<end])
        let entries = try! NSRegularExpression(pattern: #"dup\s+(\d{1,3})\s*/([A-Za-z0-9._]{1,64})\s+put"#)
        var result: [UInt8: String] = [:]
        for match in entries.matches(in: body, range: NSRange(body.startIndex..., in: body)).prefix(256) {
            guard let codeRange = Range(match.range(at: 1), in: body), let nameRange = Range(match.range(at: 2), in: body),
                  let code = UInt8(body[codeRange]) else { continue }
            result[code] = String(body[nameRange])
        }
        return result
    }

    /// The built-in encoding of the font's embedded Type 1 program (`FontFile`), read only where the
    /// descriptor's `CharSet` lists a sized delimiter: a program is decompressed for no other font.
    private static func builtInNames(_ font: CGPDFDictionaryRef) -> [UInt8: String] {
        guard let descriptor = CGPDFObjects.dictionary(font, "FontDescriptor"),
              let charSet = CGPDFObjects.text(descriptor, "CharSet"), charSet.utf16.count <= 65_536,
              charSet.split(separator: "/").contains(where: { glyph(named: String($0)) != nil }),
              let stream = CGPDFObjects.stream(descriptor, "FontFile"),
              let dictionary = CGPDFStreamGetDictionary(stream) else { return [:] }
        var format = CGPDFDataFormat.raw
        guard let data = CGPDFStreamCopyData(stream, &format) as Data?, format == .raw else { return [:] }
        let clear = CGPDFObjects.integer(dictionary, "Length1").map { max(0, $0) } ?? data.count
        return builtInEncoding(String(decoding: data.prefix(min(clear, data.count, 262_144)), as: UTF8.self))
    }

    /// The names a simple font's own resources give its codes: its `Differences` array, over the
    /// built-in encoding of its embedded program where no base encoding replaces it. A standard
    /// encoding names no sized delimiter, so a font that names one has nothing to read.
    static func glyphNames(_ font: CGPDFDictionaryRef) -> [UInt8: String] {
        if CGPDFObjects.name(font, "Encoding") != nil { return [:] }
        let encoding = CGPDFObjects.dictionary(font, "Encoding")
        var names = encoding.flatMap { CGPDFObjects.name($0, "BaseEncoding") } == nil ? builtInNames(font) : [:]
        guard let encoding, let differences = CGPDFObjects.array(encoding, "Differences") else { return names }
        let count = CGPDFArrayGetCount(differences)
        guard count <= 4096 else { return [:] }
        var next: Int?
        for index in 0..<count {
            var code: CGPDFInteger = 0, name: UnsafePointer<CChar>?
            if CGPDFArrayGetInteger(differences, index, &code) {
                guard (0...255).contains(code) else { return [:] }
                next = code
            } else if CGPDFArrayGetName(differences, index, &name), let name, let code = next, code <= 255 {
                names[UInt8(code)] = String(cString: name)
                next = code + 1
            } else { return [:] }
        }
        return names
    }

    /// A simple font's glyph advances in em, by code.
    private static func widths(_ font: CGPDFDictionaryRef) -> [UInt8: CGFloat]? {
        guard let first = CGPDFObjects.integer(font, "FirstChar"), (0...255).contains(first),
              let array = CGPDFObjects.array(font, "Widths"), CGPDFArrayGetCount(array) <= 256 else { return nil }
        var table: [UInt8: CGFloat] = [:]
        for index in 0..<CGPDFArrayGetCount(array) where first + index <= 255 {
            var width: CGPDFReal = 0
            guard CGPDFArrayGetNumber(array, index, &width), width.isFinite, width >= 0 else { return nil }
            table[UInt8(first + index)] = width / 1000
        }
        return table
    }

    /// What the page walk needs of one font: the delimiters it draws without stating a character,
    /// by code, and its advances.
    fileprivate struct Font {
        var delimiters: [UInt8: Glyph] = [:]
        var widths: [UInt8: CGFloat]?
    }

    /// The codes a simple font names as sized delimiters and states no character for. A code its
    /// `ToUnicode` map states is left to PDFKit, and a map this cannot read states nothing it can
    /// trust, so such a font supplies none. So does a code with no advance to place it by.
    static func unstatedDelimiters(_ font: CGPDFDictionaryRef) -> [UInt8: Glyph] {
        guard let subtype = CGPDFObjects.name(font, "Subtype"), subtype == "Type1" || subtype == "MMType1" else { return [:] }
        var delimiters = glyphNames(font).compactMapValues(glyph(named:))
        guard !delimiters.isEmpty, let widths = widths(font) else { return [:] }
        if CGPDFObjects.stream(font, "ToUnicode") != nil {
            guard let data = CGPDFObjects.rawData(font, "ToUnicode"),
                  let map = NativeSpacingReader.simpleFontUnicodeMap(data) else { return [:] }
            for code in map.keys { delimiters.removeValue(forKey: code) }
        }
        return delimiters.filter { widths[$0.key] != nil }
    }

    fileprivate static func font(_ dict: CGPDFDictionaryRef) -> Font {
        Font(delimiters: unstatedDelimiters(dict), widths: widths(dict))
    }

    // MARK: - Page scan

    private static let scanOptions: ContentStreamWalk.Options = {
        var options = ContentStreamWalk.Options()
        options.operators = ["Tc", "Tw", "Tz", "Ts"]
        options.maximumOperations = 200_000
        options.maximumSavedStates = 256
        options.strictTextObjects = false
        options.selectsFonts = true
        options.maximumShowElements = 4096
        options.moveAndShow = .invalidate
        return options
    }()

    private final class Visitor: ContentStreamVisitor {
        struct State {
            var font: Font?
            var size: CGFloat = 0
            var characterSpacing: CGFloat = 0
            var wordSpacing: CGFloat = 0
            var scaling: CGFloat = 100
            var rise: CGFloat = 0
        }
        var state = State()
        var saved: [State] = []
        var fonts: [Int: Font] = [:]
        /// The text matrix, which a show advances; the walk keeps only the line matrix.
        var text = CGAffineTransform.identity
        var continuing = false
        var delimiters: [Delimiter] = []

        func saveState() { saved.append(state) }
        func restoreState() { if let previous = saved.popLast() { state = previous } }
        func beginText(_ walk: ContentStreamWalk) { text = .identity; continuing = false }
        func endText(_ walk: ContentStreamWalk) { continuing = false }

        func selectFont(name: String, size: CGFloat, resource: CGPDFObjectRef?, walk: ContentStreamWalk) {
            state.size = size
            guard let resource, let dict = CGPDFObjects.dictionary(of: resource) else { state.font = nil; return }
            let id = unsafeBitCast(dict, to: Int.self)
            if let cached = fonts[id] { state.font = cached; return }
            guard fonts.count < 256 else { walk.invalid = true; return }
            let font = ExtensionDelimiterReader.font(dict)
            fonts[id] = font
            state.font = font
        }

        func show(_ arguments: [ContentStreamWalk.ShowArgument], walk: ContentStreamWalk) {
            guard walk.inText else { return }
            // A show that continues the cursor starts where the previous one's advance ended; one
            // whose start is unknown places nothing, and neither does the show after it.
            if walk.positioned { text = walk.lineMatrix } else if !continuing { return }
            continuing = false
            guard let font = state.font, let widths = font.widths, state.size > 0, state.scaling == 100 else { return }
            let transform = text.concatenating(walk.matrix)
            guard transform.tx.isFinite, transform.ty.isFinite, transform.a.isFinite, transform.d.isFinite,
                  transform.b == 0, transform.c == 0, transform.a > 0, transform.d > 0 else { return }
            var advance: CGFloat = 0, found: [Delimiter] = [], others = 0
            for argument in arguments {
                switch argument {
                case .string(let string):
                    let count = CGPDFStringGetLength(string)
                    guard count <= 4096, let bytes = CGPDFStringGetBytePtr(string) else { return }
                    for index in 0..<count {
                        let code = bytes[index]
                        guard let width = widths[code] else { return }
                        if let glyph = font.delimiters[code] {
                            let origin = CGPoint(x: advance, y: state.rise).applying(transform)
                            found.append(Delimiter(character: glyph.character, side: glyph.side, origin: origin,
                                                   end: origin.x + width * state.size * transform.a,
                                                   size: state.size * transform.a, depth: glyph.depth,
                                                   show: CGPoint(x: transform.tx, y: transform.ty), alone: false))
                        } else {
                            others += 1
                        }
                        advance += width * state.size + state.characterSpacing + (code == 32 ? state.wordSpacing : 0)
                    }
                case .adjustment(let number):
                    advance -= number / 1000 * state.size
                case .other:
                    return
                }
            }
            guard advance.isFinite, abs(advance) <= 100_000 else { return }
            for var delimiter in found where delimiters.count < 10_000 {
                delimiter.alone = others == 0
                delimiters.append(delimiter)
            }
            text = text.translatedBy(x: advance, y: 0)
            continuing = true
        }

        func handle(_ op: String, scanner: CGPDFScannerRef, walk: ContentStreamWalk) {
            guard let value = ContentStreamWalk.numbers(scanner, 1)?.first, abs(value) <= 100_000 else {
                walk.invalid = true; return
            }
            switch op {
            case "Tc": state.characterSpacing = value
            case "Tw": state.wordSpacing = value
            case "Tz": state.scaling = value
            case "Ts": state.rise = value
            default: walk.invalid = true
            }
        }
    }

    /// Every sized delimiter the page draws and no map states, in drawing order; none when the
    /// page has no font that names one, is rotated, or cannot be scanned. Form XObjects are not
    /// followed: TeX draws its text on the page.
    static func read(_ page: CGPDFPage) -> [Delimiter] {
        guard page.rotationAngle == 0, let resources = CGPDFObjects.inheritedResources(of: page),
              CGPDFObjects.fonts(in: resources).contains(where: { !unstatedDelimiters($0).isEmpty }) else { return [] }
        let visitor = Visitor()
        guard ContentStreamWalk.scan(page, options: scanOptions, visitor: visitor) else { return [] }
        return visitor.delimiters
    }

    // MARK: - Placement

    /// Delimiters drawn side by side, with the shows beside them on their row.
    struct Placement {
        var delimiters: [Delimiter]
        /// The nearest show before the delimiters and the nearest after, each within an em, whose
        /// baseline lies within the delimiters' height; whitespace-only shows are not anchors.
        var left: NativeSpacingReader.Evidence?
        var right: NativeSpacingReader.Evidence?
        /// Whether a show of spaces stands between the delimiters and the anchor on that side.
        var spacedLeft = false
        var spacedRight = false
        /// The baseline of the row the delimiters enclose (`enclosedBase`).
        var baseline: CGFloat
        /// The height the delimiters span, which holds the baseline of every show on their row.
        var low: CGFloat
        var high: CGFloat
    }

    private static func sameShow(_ show: NativeSpacingReader.Evidence, _ point: CGPoint) -> Bool {
        abs(show.origin.x - point.x) <= 0.01 && abs(show.origin.y - point.y) <= 0.01
    }

    private static func blank(_ text: String?) -> Bool { text.map { $0.allSatisfy(\.isWhitespace) } ?? false }

    /// The glyph of the enclosed row a run of delimiters stands beside, or nil where it encloses
    /// no row.
    ///
    /// TeX centres a delimiter on the maths axis, a quarter em above the baseline of the row it
    /// encloses, so the row's baseline is known from the delimiter alone. Walking inward from it,
    /// show by show with no gap wider than an em, the first glyph set in the delimiter's own size
    /// must stand on that baseline; smaller glyphs before it are scripts and are passed over, as the
    /// ² of `(a²)³` is on the way from `)` to `a`. A tall parenthesis around a fraction encloses no
    /// row: its first glyph at its own size is a displayed numerator or denominator, off the
    /// baseline, and an inline fraction's are all smaller, so the walk reaches another delimiter,
    /// a larger glyph or a gap first. Such a delimiter stays out of the text, where the fraction
    /// beside it is not a line of text either.
    private static func enclosedBase(_ run: [Delimiter], leftward: Bool, row: [NativeSpacingReader.Evidence],
                                     others: [Delimiter]) -> NativeSpacingReader.Evidence? {
        guard let first = run.first, let last = run.last else { return nil }
        let size = first.size, baseline = (first.top + first.bottom) / 2 - size * 0.25
        let low = run.map(\.bottom).min()!, high = run.map(\.top).max()!
        let side = row.filter { show in
            !blank(show.unicode) && show.origin.y >= low - AnchorMatcher.tolerance
                && show.origin.y <= high + AnchorMatcher.tolerance && (leftward
                ? (show.end ?? show.origin.x) <= first.origin.x + AnchorMatcher.tolerance
                : show.origin.x >= last.end - AnchorMatcher.tolerance)
        }.sorted { leftward ? ($0.end ?? $0.origin.x) > ($1.end ?? $1.origin.x) : $0.origin.x < $1.origin.x }
        var edge = leftward ? first.origin.x : last.end
        for show in side {
            let near = leftward ? show.end ?? show.origin.x : show.origin.x
            guard (leftward ? edge - near : near - edge) <= size else { return nil }
            // Another delimiter on the way closes the group this one opens, or opens the one it closes.
            if others.contains(where: { other in
                other.bottom < high && other.top > low
                    && (leftward ? other.origin.x < edge && other.end > near : other.end > edge && other.origin.x < near)
            }) { return nil }
            // A glyph of no known character could be anything, and a radical sign hangs from its
            // vinculum, so its origin says nothing about the baseline.
            guard let text = show.unicode, !text.contains("√") else { return nil }
            if abs(show.size - size) <= size * 0.1 {
                return abs(show.origin.y - baseline) <= size * 0.2 ? show : nil
            }
            guard show.size < size * 0.9 else { return nil }
            edge = leftward ? min(edge, show.origin.x) : max(edge, show.end ?? show.origin.x)
        }
        return nil
    }

    /// A PDFKit line's text with its whitespace taken out, and where each remaining UTF-16 unit
    /// stands in the line. U+FFFC, an attachment, is whitespace here, as it is to the line.
    private static func stripped(_ text: String) -> (units: [UInt16], positions: [Int]) {
        var units: [UInt16] = [], positions: [Int] = []
        for (index, unit) in text.utf16.enumerated() where !isBlank(unit) {
            units.append(unit)
            positions.append(index)
        }
        return (units, positions)
    }

    private static func isBlank(_ unit: UInt16) -> Bool {
        unit == 0xFFFC || UnicodeScalar(unit).map { CharacterSet.whitespacesAndNewlines.contains($0) } == true
    }

    /// Where a run goes in one PDFKit line, as an index into the line's stripped text, or nil.
    ///
    /// The shows whose origin the line's rectangle holds and whose baseline is on the run's row,
    /// taken left to right, spell that stretch of the line apart from PDFKit's spaces, and the run
    /// stands between two of them: after the show before it, before the show after it. The text of
    /// the shows on either side of it, one show more on each side at a time, must be found in the
    /// line exactly once, at its start or end where the shows reach it with nothing undecoded
    /// between, and the run goes between the two. A show whose text is unknown stops the context on
    /// its side. A line that holds the anchors' origins without spelling their text around the cut,
    /// as a line whose rectangle a tall glyph stretched over its neighbour's does not, is not the
    /// run's line.
    private static func cut(_ placement: Placement, shows: [NativeSpacingReader.Evidence], delimiters: [Delimiter],
                            bounds: CGRect, text: [UInt16]) -> Int? {
        let tokens = shows.filter { show in
            AnchorMatcher.contains(bounds, show.origin) && !blank(show.unicode)
                && show.origin.y >= placement.low && show.origin.y <= placement.high
                && !delimiters.contains { sameShow(show, $0.show) }
        }.sorted { $0.origin.x < $1.origin.x }
        guard tokens.count <= 4096 else { return nil }
        let index: Int
        if let right = placement.right, let found = tokens.firstIndex(where: { sameShow($0, right.origin) }) {
            if let left = placement.left, tokens.contains(where: { sameShow($0, left.origin) }) {
                guard found > 0, sameShow(tokens[found - 1], left.origin) else { return nil }
            }
            index = found
        } else if let left = placement.left, let found = tokens.firstIndex(where: { sameShow($0, left.origin) }) {
            index = found + 1
        } else { return nil }
        let texts = tokens.map(\.unicode)
        func strip(_ slice: ArraySlice<String?>) -> [UInt16] {
            slice.compactMap { $0 }.flatMap { Array($0.utf16) }.filter { !isBlank($0) }
        }
        let before = texts[..<index].reversed().prefix { $0 != nil }.count
        let after = texts[index...].prefix { $0 != nil }.count
        let reachesStart = before == index, reachesEnd = after == texts.count - index
        guard before + after > 0 else { return nil }
        for width in 1...max(before, after) {
            let leftCount = min(width, before), rightCount = min(width, after)
            let leading = strip(texts[(index - leftCount)..<index])
            let pattern = leading + strip(texts[index..<(index + rightCount)])
            guard !pattern.isEmpty, pattern.count <= text.count else { return nil }
            let anchoredStart = reachesStart && leftCount == before
            let anchoredEnd = reachesEnd && rightCount == after
            var matches: [Int] = []
            for start in 0...(text.count - pattern.count) {
                if anchoredStart, start != 0 { break }
                if anchoredEnd, start + pattern.count != text.count { continue }
                if text[start..<(start + pattern.count)].elementsEqual(pattern) { matches.append(start) }
                if matches.count > 1 { break }
            }
            if matches.count == 1 { return matches[0] + leading.count }
            if matches.isEmpty || (leftCount == before && rightCount == after) { return nil }
        }
        return nil
    }

    /// Which line each run of delimiters belongs to, keyed by the line's index in `lines`, whose
    /// text PDFKit read as `texts`.
    ///
    /// Delimiters drawn within half an em of one another on overlapping heights are one run. A run
    /// must stand beside the row it encloses (`enclosedBase`): an opening run the row after it, a
    /// closing run the row before it, a slash both. Its anchors are the page's shows nearest it on
    /// either side (`Placement`). Its line is the one line whose rectangle holds an anchor's origin
    /// and whose text places the run (`cut`). PDFKit stretches a line's rectangle over whatever
    /// tall glyph it attaches to the line, a delimiter's included, so rectangles overlap around a
    /// run and a rectangle alone does not say which line a show is in; the text does. A run two
    /// lines could hold, or none, is left out. So is a delimiter drawn in one show with glyphs this
    /// reader does not state: that show's text is unknown.
    static func placements(_ delimiters: [Delimiter], shows: [NativeSpacingReader.Evidence],
                           lines: [CGRect], texts: [String]) -> [Int: [Placement]] {
        guard !delimiters.isEmpty, delimiters.count <= 1000, !shows.isEmpty, lines.count == texts.count,
              shows.count <= AnchorMatcher.maximumAnchors, lines.count <= AnchorMatcher.maximumAnchors,
              shows.count * lines.count <= AnchorMatcher.maximumComparisons,
              shows.count * delimiters.count <= AnchorMatcher.maximumComparisons else { return [:] }
        let row = shows.filter { show in !delimiters.contains { sameShow(show, $0.show) } }
        var runs: [[Delimiter]] = []
        for delimiter in delimiters.filter(\.alone).sorted(by: { $0.origin.x < $1.origin.x }) {
            if let index = runs.lastIndex(where: { run in
                guard let last = run.last else { return false }
                let gap = delimiter.origin.x - last.end
                return gap >= -AnchorMatcher.tolerance && gap <= last.size * 0.5
                    && delimiter.bottom < last.top && last.bottom < delimiter.top
                    && !row.contains { $0.origin.x > last.origin.x && $0.origin.x < delimiter.origin.x
                        && $0.origin.y >= max(last.bottom, delimiter.bottom) && $0.origin.y <= min(last.top, delimiter.top) }
            }) {
                runs[index].append(delimiter)
            } else {
                runs.append([delimiter])
            }
        }
        var result: [Int: [Placement]] = [:]
        for run in runs {
            guard let first = run.first, let last = run.last else { continue }
            let sides = Set(run.map(\.side))
            let others = delimiters.filter { delimiter in !run.contains(delimiter) }
            let closes = sides.contains(.closing) || sides.contains(.neither)
            let opens = sides.contains(.opening) || sides.contains(.neither)
            let fromLeft = closes ? enclosedBase(run, leftward: true, row: row, others: others) : nil
            let fromRight = opens ? enclosedBase(run, leftward: false, row: row, others: others) : nil
            guard !closes || fromLeft != nil, !opens || fromRight != nil,
                  let base = fromLeft ?? fromRight else { continue }
            let low = run.map(\.bottom).min()! - AnchorMatcher.tolerance
            let high = run.map(\.top).max()! + AnchorMatcher.tolerance
            let beside = row.filter { $0.origin.y >= low && $0.origin.y <= high }
            let before = beside.filter { show in
                let edge = show.end ?? show.origin.x
                return edge <= first.origin.x + AnchorMatcher.tolerance && first.origin.x - edge <= first.size
            }.sorted { ($0.end ?? $0.origin.x) > ($1.end ?? $1.origin.x) }
            let after = beside.filter { show in
                show.origin.x >= last.end - AnchorMatcher.tolerance && show.origin.x - last.end <= last.size
            }.sorted { $0.origin.x < $1.origin.x }
            var placement = Placement(delimiters: run, baseline: base.origin.y, low: low, high: high)
            placement.left = before.first { !blank($0.unicode) }
            placement.right = after.first { !blank($0.unicode) }
            placement.spacedLeft = before.first.map { blank($0.unicode) } ?? false
            placement.spacedRight = after.first.map { blank($0.unicode) } ?? false
            let anchors = [placement.left, placement.right].compactMap { $0?.origin }
            let placed = lines.indices.filter { line in
                anchors.contains { AnchorMatcher.contains(lines[line], $0) }
                    && cut(placement, shows: row, delimiters: delimiters, bounds: lines[line],
                           text: stripped(texts[line]).units) != nil
            }
            guard placed.count == 1 else { continue }
            result[placed[0], default: []].append(placement)
        }
        return result
    }

    /// Carries how far a restored delimiter reaches above and below its row's baseline, in points,
    /// from the delimiter's character to `NativeTextReader.inlineText`, which reads a script set
    /// against the delimiter by it (`script(after:)`).
    static let reachAttribute = NSAttributedString.Key("PDFReflowDelimiterReach")

    final class Reach: NSObject {
        let above: Double
        let below: Double
        let size: Double
        init(above: Double, below: Double, size: Double) {
            self.above = above
            self.below = below
            self.size = size
        }
    }

    /// The script level of a run drawn straight after a restored tall delimiter, which its own size
    /// would not make a script: TeX raises a group's exponent from the top of the delimiter that
    /// closes it, not from the baseline, so `(a²)³` sets its ³ higher than three quarters of the
    /// ³'s own size (Wallace page 178: 7.44 points on 7.97). A run smaller than the delimiter,
    /// raised from the delimiter's baseline by more than `tolerance` and no higher than the
    /// delimiter's top, is its superscript; lowered no further than its foot, its subscript.
    static func script(after reach: Reach, at delimiterOffset: Double, offset: Double, size: Double,
                       tolerance: Double) -> TextStyle {
        guard size <= reach.size * 0.9 else { return [] }
        let shift = offset - delimiterOffset
        if shift > tolerance, shift <= reach.above + tolerance { return .superscript }
        if shift < -tolerance, -shift <= reach.below + tolerance { return .subscript }
        return []
    }

    /// The gap, in em, beside a delimiter that is a word space where PDFKit set none: the gap a
    /// font change must show before it separates two words (`NativeSpacingReader`).
    static let wordGap: CGFloat = 0.15

    /// Inserts `placements` into one PDFKit line (`attributed`, with `bounds`), or returns it as
    /// read. Each run goes where `cut` places it in the line as it now reads.
    ///
    /// PDFKit sets a space in the gap the delimiter's width leaves, whether or not the page spaces
    /// a word there, so that space is placed rather than kept. Nothing stands between a delimiter
    /// and what it encloses, and nothing between a closing delimiter and the script raised or
    /// lowered after it. On its outer side a delimiter keeps PDFKit's space, and takes one PDFKit
    /// did not set where the page draws a space or leaves a word gap there (`wordGap`): an advance
    /// understates the gap beside a delimiter, whose ink is narrower than its advance, so a narrow
    /// measure is no evidence that a space PDFKit set is not a word space. A slash, which encloses
    /// nothing, is spaced by that gap alone. The delimiter takes the attributes of the nearest
    /// character set in its own size, so it stands on that text's baseline, and carries its reach
    /// above and below it (`Reach`).
    static func apply(_ placements: [Placement], shows: [NativeSpacingReader.Evidence], delimiters: [Delimiter],
                      to attributed: NSAttributedString, bounds: CGRect) -> NSAttributedString {
        guard !placements.isEmpty, attributed.length > 0, attributed.length <= 4096 else { return attributed }
        let row = shows.filter { show in !delimiters.contains { sameShow(show, $0.show) } }
        let (text, positions) = stripped(attributed.string)
        struct Edit { var range: NSRange; var replacement: NSAttributedString }
        var edits: [Edit] = []
        for placement in placements {
            guard let first = placement.delimiters.first, let last = placement.delimiters.last,
                  let cut = cut(placement, shows: row, delimiters: delimiters, bounds: bounds, text: text) else { continue }
            // The whitespace PDFKit set between the characters on either side of the cut.
            let lower = cut > 0 ? positions[cut - 1] + 1 : positions[cut]
            let upper = cut < positions.count ? positions[cut] : lower
            let hasSpace = upper > lower
            // The attributes of the nearest character set in the delimiters' own size.
            var base: [NSAttributedString.Key: Any]?
            search: for distance in 0..<text.count {
                for candidate in [cut - 1 - distance, cut + distance] where text.indices.contains(candidate) {
                    let attributes = attributed.attributes(at: positions[candidate], effectiveRange: nil)
                    if let font = attributes[.font] as? PlatformFont, abs(font.pointSize - first.size) <= first.size * 0.1 {
                        base = attributes
                        break search
                    }
                }
            }
            guard let base else { continue }
            func wide(_ gap: CGFloat?, _ size: CGFloat) -> Bool { gap.map { $0 >= size * wordGap } ?? false }
            // A script set straight after a closing delimiter is the group's own (`script(after:)`).
            let scripted = placement.right.map { right in
                right.size <= last.size * 0.9 && abs(right.origin.y - placement.baseline) > max(0.5, right.size * 0.12)
            } ?? false
            let spaceBefore = cut > 0 && first.side != .closing && (placement.spacedLeft
                || wide(placement.left.flatMap { $0.end }.map { first.origin.x - $0 }, first.size)
                || first.side == .opening && hasSpace)
            let spaceAfter = cut < text.count && last.side != .opening && !scripted && (placement.spacedRight
                || wide(placement.right.map { $0.origin.x - last.end }, last.size)
                || last.side == .closing && hasSpace)
            let replacement = NSMutableAttributedString()
            func space(at location: Int) {
                let at = min(max(0, location), attributed.length - 1)
                replacement.append(NSAttributedString(string: " ", attributes: attributed.attributes(at: at, effectiveRange: nil)))
            }
            if spaceBefore { space(at: hasSpace ? lower : lower - 1) }
            for (offset, delimiter) in placement.delimiters.enumerated() {
                if offset > 0, delimiter.origin.x - placement.delimiters[offset - 1].end >= delimiter.size * wordGap {
                    space(at: lower)
                }
                var attributes = base
                attributes[reachAttribute] = Reach(above: Double(delimiter.top - placement.baseline),
                                                   below: Double(placement.baseline - delimiter.bottom),
                                                   size: Double(delimiter.size))
                replacement.append(NSAttributedString(string: delimiter.character, attributes: attributes))
            }
            if spaceAfter { space(at: hasSpace ? upper - 1 : upper) }
            edits.append(Edit(range: NSRange(location: lower, length: upper - lower), replacement: replacement))
        }
        // Two runs placed in one gap are two readings of it: neither is applied.
        let contested = Set(Dictionary(grouping: edits, by: \.range.location).filter { $0.value.count > 1 }.keys)
        let applied = edits.filter { !contested.contains($0.range.location) }
        guard !applied.isEmpty else { return attributed }
        let result = NSMutableAttributedString(attributedString: attributed)
        // Every edit is an offset in the line as PDFKit read it, so they are applied from the right.
        for edit in applied.sorted(by: { $0.range.location > $1.range.location }) {
            result.replaceCharacters(in: edit.range, with: edit.replacement)
        }
        return result
    }
}
