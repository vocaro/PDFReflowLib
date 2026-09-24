import CoreGraphics
import Foundation

/// Reads a preserved equation crop as mathematics where the page's own glyphs and painted bars
/// prove its structure (#190), so it can be written as MathML instead of a picture.
///
/// The evidence is the content stream, not PDFKit's lines: PDFKit joins an exercise's label, a
/// fraction's numerator and the operator beside it into one line (`59) 3`, `5 + 5`), while every
/// glyph has a show with a baseline, a size and an advance (`NativeSpacingReader`), and every
/// fraction bar is a painted rule (`GraphicsReader`, padded two points). Three structures are
/// proven and nothing else:
///
/// - a **bar fraction**: a thin rule with one row of glyphs just above it and one just below,
///   each centred on the bar, the wider spanning it, the bar on the maths axis of its row, and
///   no other glyph or rule touching the stack (so a stacked or nested fraction is refused);
/// - a **superscript**: a glyph smaller than the row's type, raised by a fifth to three quarters
///   of it, set straight after its base (a number, a variable, a bracketed group);
/// - a **row** of numbers, maths italic variables, operators and brackets on one baseline, with no
///   gap wider than three quarters of an em, balanced brackets, and operators that each stand
///   between operands (a sign may open an operand).
///
/// A crop may hold several rows (a column of exercises) and a row several exercises; a printed
/// label (`52)`) opens each. Every row of the crop must read, every glyph and rule in the crop
/// must be used, and the characters must be exactly those of the page's text lines in the crop;
/// anything else (a word, an upright letter, a subscript, a radical, an undecodable glyph, a rule
/// that is not a fraction bar, a gap that aligns rather than spaces) leaves the crop a picture.
enum MathRecognizer {
    /// One glyph as the page draws it: its character, its advance along the baseline, its
    /// baseline and its size in page space.
    struct Glyph: Equatable {
        var text: String
        var minX: CGFloat
        var maxX: CGFloat
        var baseline: CGFloat
        var size: CGFloat
        var mathItalic = false

        /// The glyph's type box: a descender's quarter em below the baseline to three quarters above.
        var box: CGRect { CGRect(x: minX, y: baseline - size * 0.25, width: max(0, maxX - minX), height: size) }
        var center: CGPoint { CGPoint(x: (minX + maxX) / 2, y: baseline + size * 0.25) }
    }

    /// A page's glyphs, and the origins of shows that could not be read glyph by glyph.
    struct PageGlyphs: Equatable {
        var glyphs: [Glyph] = []
        var opaque: [CGPoint] = []
    }

    /// One printed row of a crop, read: its label, its expression and the region the expression
    /// occupies (for the fallback image).
    struct Row: Equatable {
        var label: String?
        var node: MathExpression.Node
        var rect: CGRect
    }

    /// The page's glyphs from its content stream. Only the TeX font families qualified by the
    /// Wallace source checks are read; an unknown face remains opaque. A show in a bold font is opaque: Wallace page 15 sets the
    /// factor it multiplies in bold (`3·5 / 3·6`, the `2` of `4·2 / 9·2`), emphasis MathML written
    /// from the glyphs would drop, so its crop stays a picture.
    static func glyphs(on page: CGPDFPage) -> PageGlyphs {
        var mathItalicFonts: Set<Int> = [], readableFonts: Set<Int> = []
        if let resources = CGPDFObjects.inheritedResources(of: page) {
            for font in CGPDFObjects.fonts(in: resources) {
                guard let base = CGPDFObjects.name(font, "BaseFont") else { continue }
                let name = String(base.split(separator: "+").last ?? Substring(base)).lowercased()
                let id = unsafeBitCast(font, to: Int.self)
                if name.range(of: #"^cmmi[0-9]+$"#, options: .regularExpression) != nil {
                    mathItalicFonts.insert(id)
                    readableFonts.insert(id)
                } else if name.range(of: #"^cm(r|sy|ex|ss|tt)[0-9]+$"#, options: .regularExpression) != nil
                    || name.range(of: #"^europeancomputermodern-romanregular[0-9]+pt$"#, options: .regularExpression) != nil {
                    readableFonts.insert(id)
                }
            }
        }
        var result = PageGlyphs()
        for show in NativeSpacingReader.read(page, recordingGlyphs: true) {
            guard let glyphs = show.glyphs, readableFonts.contains(show.font) else {
                // A show of spaces only draws nothing a reader would miss.
                if show.unicode?.allSatisfy(\.isWhitespace) != true { result.opaque.append(show.origin) }
                continue
            }
            for glyph in glyphs {
                result.glyphs.append(Glyph(text: glyph.text, minX: glyph.minX, maxX: glyph.maxX, baseline: show.origin.y,
                                           size: show.size, mathItalic: mathItalicFonts.contains(show.font)))
            }
        }
        return result
    }

    /// The crop's rows, or nil unless every glyph, rule and line in it reads as proven mathematics.
    /// `body` is the page's body type size, which tells a displayed fraction from an inline one.
    static func rows(in crop: CGRect, page: PageGlyphs, graphics: [CGRect], lines: [TextLine], body: CGFloat) -> [Row]? {
        guard !page.opaque.contains(where: crop.contains) else { return nil }
        var glyphs: [Glyph] = []
        for glyph in page.glyphs where glyph.box.intersects(crop.insetBy(dx: 1, dy: 1)) {
            // A glyph the crop cuts belongs to text outside it.
            guard crop.contains(glyph.center) else { return nil }
            if !glyph.text.allSatisfy(\.isWhitespace) { glyphs.append(glyph) }
        }
        guard !glyphs.isEmpty, explains(glyphs, lines: lines, crop: crop) else { return nil }
        // Every painted mark in the crop must be a fraction bar: a thin rule, as padded by GraphicsReader.
        let bars = graphics.filter { $0.intersects(crop) }
        guard bars.allSatisfy({ crop.insetBy(dx: -1, dy: -1).contains($0) && $0.height <= 5 && $0.width >= 6 }) else { return nil }
        var claimed = Set<Int>()
        var items: [Item] = []
        for bar in bars {
            guard let fraction = fraction(bar, glyphs: glyphs, bars: bars, body: body),
                  claimed.isDisjoint(with: fraction.members) else { return nil }
            claimed.formUnion(fraction.members)
            items.append(.init(box: fraction.box, fraction: fraction))
        }
        items += glyphs.indices.filter { !claimed.contains($0) }.map { Item(box: glyphs[$0].box, glyph: glyphs[$0]) }
        var rows: [Row] = []
        for band in bands(items) {
            guard let read = read(band) else { return nil }
            rows += read.map { Row(label: $0.label, node: $0.node, rect: $0.rect.intersection(crop)) }
        }
        return rows.isEmpty ? nil : rows
    }

    // MARK: - Evidence

    /// Whether the crop's glyphs are exactly the characters of the text lines it holds, so text the
    /// content stream does not show (a form's, an image's) cannot be dropped.
    static func explains(_ glyphs: [Glyph], lines: [TextLine], crop: CGRect) -> Bool {
        var expected: [Character: Int] = [:]
        for line in lines where line.rect.intersects(crop.insetBy(dx: 1, dy: 1)) {
            guard crop.contains(CGPoint(x: line.rect.midX, y: line.rect.midY)) else { return false }
            for character in line.text where !character.isWhitespace { expected[normalized(character), default: 0] += 1 }
        }
        var found: [Character: Int] = [:]
        for glyph in glyphs {
            for character in glyph.text.precomposedStringWithCompatibilityMapping where !character.isWhitespace {
                found[normalized(character), default: 0] += 1
            }
        }
        return !expected.isEmpty && expected == found
    }

    /// PDFKit and a font's map can name one symbol by two characters.
    private static func normalized(_ character: Character) -> Character {
        switch character {
        case "-": "\u{2212}"
        case "\u{00B7}": "\u{22C5}"
        default: character
        }
    }

    // MARK: - Fractions

    struct Fraction {
        var bar: CGRect
        var node: MathExpression.Node
        var box: CGRect
        var members: Set<Int>
        /// The rule's height in page space.
        var axis: CGFloat { bar.midY }
    }

    struct Item {
        var box: CGRect
        var glyph: Glyph?
        var fraction: Fraction?
        init(box: CGRect, glyph: Glyph) { self.box = box; self.glyph = glyph }
        init(box: CGRect, fraction: Fraction) { self.box = box; self.fraction = fraction }
    }

    /// The fraction a bar draws, or nil unless one row of glyphs sits just above it and one just
    /// below, each centred on it, and nothing else touches the stack.
    static func fraction(_ bar: CGRect, glyphs: [Glyph], bars: [CGRect], body: CGFloat) -> Fraction? {
        // GraphicsReader pads a painted path by two points on every side.
        let y = bar.midY, left = bar.minX + 2, right = bar.maxX - 2, width = right - left
        guard width >= 2 else { return nil }
        let spanned = glyphs.indices.filter { glyphs[$0].minX >= left - 0.75 && glyphs[$0].maxX <= right + 0.75 }
        let above = spanned.filter { glyphs[$0].baseline > y && glyphs[$0].baseline - y <= glyphs[$0].size * 1.8 }
        let below = spanned.filter { glyphs[$0].baseline < y && y - glyphs[$0].baseline <= glyphs[$0].size * 1.8 }
        guard !above.isEmpty, !below.isEmpty,
              let numerator = term(above.map { glyphs[$0] }), let denominator = term(below.map { glyphs[$0] }) else { return nil }
        // The numerator's baseline stands just over the bar; the denominator hangs below it, its
        // top clear of the bar.
        let raise = (numerator.baseline - y) / numerator.size, drop = (y - denominator.baseline) / denominator.size
        guard (0.15...1.0).contains(raise), (0.6...1.4).contains(drop) else { return nil }
        // Each term is centred on the bar and the wider one spans it.
        for extent in [numerator.extent, denominator.extent] {
            guard abs((extent.lowerBound + extent.upperBound) / 2 - (left + right) / 2) <= max(0.75, width * 0.1) else { return nil }
        }
        let wider = max(numerator.extent.upperBound - numerator.extent.lowerBound,
                        denominator.extent.upperBound - denominator.extent.lowerBound)
        guard wider >= width - 3, wider >= width * 0.5, wider <= width + 1 else { return nil }
        let members = Set(above + below)
        let box = members.reduce(CGRect(x: left, y: y, width: width, height: 0)) { $0.union(glyphs[$1].box) }
        // Nothing else may touch the stack: a glyph beside a term, a second bar (a stacked or
        // nested fraction).
        let inner = box.insetBy(dx: 0.5, dy: 0.5)
        guard !glyphs.indices.contains(where: { !members.contains($0) && glyphs[$0].box.intersects(inner) }),
              !bars.contains(where: { $0 != bar && $0.insetBy(dx: 2, dy: 2).intersects(inner) }) else { return nil }
        let display = min(numerator.size, denominator.size) >= body * 0.9
        return Fraction(bar: bar, node: .fraction(numerator.node, denominator.node, display: display), box: box, members: members)
    }

    /// A fraction's numerator or denominator: one row with no bar and no label.
    private static func term(_ glyphs: [Glyph]) -> (node: MathExpression.Node, baseline: CGFloat, size: CGFloat,
                                                     extent: ClosedRange<CGFloat>)? {
        let items = glyphs.map { Item(box: $0.box, glyph: $0) }
        guard let parsed = expression(items.sorted { $0.box.minX < $1.box.minX }), let baseline = parsed.baseline,
              let minX = glyphs.map(\.minX).min(), let maxX = glyphs.map(\.maxX).max() else { return nil }
        return (parsed.node, baseline, parsed.size, minX...maxX)
    }

    // MARK: - Rows

    /// Items grouped into printed rows: runs of overlapping vertical extents, top to bottom.
    static func bands(_ items: [Item]) -> [[Item]] {
        var bands: [(minY: CGFloat, items: [Item])] = []
        for item in items.sorted(by: { $0.box.maxY > $1.box.maxY }) {
            if let last = bands.last, item.box.maxY > last.minY {
                bands[bands.count - 1].items.append(item)
                bands[bands.count - 1].minY = min(last.minY, item.box.minY)
            } else {
                bands.append((item.box.minY, [item]))
            }
        }
        return bands.map(\.items)
    }

    /// A printed row: exercises, each opened by its label, read left to right.
    private static func read(_ band: [Item]) -> [(label: String?, node: MathExpression.Node, rect: CGRect)]? {
        let items = band.sorted { $0.box.minX < $1.box.minX }
        var segments: [(label: String?, items: [Item])] = []
        var index = 0
        while index < items.count {
            // A label opens the row, or stands an em clear of the exercise before it.
            let clear = index == 0 || items[index].box.minX - items[index - 1].box.maxX >= (items[index].glyph?.size ?? 0)
            if clear, let (label, count) = label(items, at: index) {
                segments.append((label, []))
                index += count
                continue
            }
            if segments.isEmpty { segments.append((nil, [])) }
            segments[segments.count - 1].items.append(items[index])
            index += 1
        }
        var result: [(label: String?, node: MathExpression.Node, rect: CGRect)] = []
        for segment in segments {
            guard let parsed = expression(segment.items) else { return nil }
            let rect = segment.items.reduce(CGRect.null) { $0.union($1.box) }.insetBy(dx: -2, dy: -2)
            result.append((segment.label, parsed.node, rect))
        }
        return result
    }

    /// A printed exercise label at `index`: one to three digits and a closing bracket on one
    /// baseline in upright type, set apart from what follows by at least a quarter em.
    private static func label(_ items: [Item], at index: Int) -> (String, Int)? {
        var text = "", count = 0
        while index + count < items.count, let glyph = items[index + count].glyph, glyph.text.count == 1,
              glyph.text.first!.isASCII, glyph.text.first!.isNumber, !glyph.mathItalic, count < 3 {
            text += glyph.text
            count += 1
        }
        guard count > 0, index + count < items.count - 1, let bracket = items[index + count].glyph, bracket.text == ")",
              let first = items[index].glyph, abs(bracket.baseline - first.baseline) <= first.size * 0.05,
              abs(bracket.size - first.size) <= first.size * 0.05 else { return nil }
        let next = items[index + count + 1]
        guard next.box.minX - bracket.maxX >= first.size * 0.25 else { return nil }
        return (text + ")", count + 1)
    }

    // MARK: - Expressions

    private enum Token {
        case node(MathExpression.Node)
        case open
        case close
        case symbol(String)
    }

    private static let operators: [Character: String] = [
        "+": "+", "\u{2212}": "\u{2212}", "-": "\u{2212}", "\u{00D7}": "\u{00D7}", "\u{00F7}": "\u{00F7}",
        "\u{22C5}": "\u{22C5}", "\u{00B7}": "\u{22C5}", "=": "=", "<": "<", ">": ">", "\u{2264}": "\u{2264}",
        "\u{2265}": "\u{2265}", "\u{00B1}": "\u{00B1}",
    ]
    /// Operators that may stand before an operand with nothing on their left: a sign.
    private static let signs: Set<String> = ["+", "\u{2212}", "\u{00B1}"]

    /// One exercise's expression, or nil unless it reads as a proven row. `baseline` and `size` are
    /// the row's type (nil for a row of fractions alone).
    private static func expression(_ items: [Item]) -> (node: MathExpression.Node, baseline: CGFloat?, size: CGFloat)? {
        guard !items.isEmpty else { return nil }
        let glyphs = items.compactMap(\.glyph)
        let size = glyphs.map(\.size).max() ?? 0
        let bases = glyphs.filter { $0.size >= size * 0.9 }
        let baseline = bases.map(\.baseline).sorted().dropFirst(bases.count / 2).first
        if let baseline {
            guard bases.allSatisfy({ abs($0.baseline - baseline) <= size * 0.1 }) else { return nil }
        }
        // Every list of tokens under construction; brackets open a new one.
        var stack: [[MathExpression.Node]] = [[]]
        var previousMaxX: CGFloat?
        // Whether the last token ended an operand. Operands side by side multiply, and a product is
        // set close (`2(x+1)`, `(8)(1/2)`): a space between them is an unprinted label or a
        // column, not notation (Wallace page 16 prints exercise `33` without its bracket).
        var endsOperand = false
        func opensOperand(at minX: CGFloat) -> Bool {
            guard endsOperand, let previousMaxX else { return true }
            return minX - previousMaxX <= max(size, 6) * 0.2
        }
        // The number still growing, its last glyph's end.
        var number: (text: String, maxX: CGFloat)?
        func flushNumber() {
            if let value = number { stack[stack.count - 1].append(.number(value.text)); number = nil }
        }
        var index = 0
        while index < items.count {
            let item = items[index]
            // Ordinary maths spacing is under half an em; a wider gap aligns columns.
            if let previousMaxX, item.box.minX - previousMaxX > max(size, 1) * 0.75 { return nil }
            if let fraction = item.fraction {
                if let baseline {
                    let axis = (fraction.axis - baseline) / size
                    guard (0.1...0.5).contains(axis) else { return nil }
                }
                guard opensOperand(at: item.box.minX) else { return nil }
                flushNumber()
                stack[stack.count - 1].append(fraction.node)
                endsOperand = true
                previousMaxX = item.box.maxX
                index += 1
                continue
            }
            guard let glyph = item.glyph, let character = glyph.text.first, glyph.text.count == 1 else { return nil }
            if let baseline, glyph.size < size * 0.9 {
                // A superscript: smaller type, raised, straight after its base.
                let raise = (glyph.baseline - baseline) / size
                guard glyph.size <= size * 0.85, (0.2...0.75).contains(raise), let baseEnd = previousMaxX,
                      glyph.minX - baseEnd <= size * 0.3, glyph.minX - baseEnd >= -size * 0.1 else { return nil }
                var script = [glyph]
                while index + 1 < items.count, let next = items[index + 1].glyph, next.size < size * 0.9,
                      abs(next.baseline - glyph.baseline) <= glyph.size * 0.1, abs(next.size - glyph.size) <= glyph.size * 0.05,
                      next.minX - script.last!.maxX <= glyph.size * 0.3 {
                    script.append(next)
                    index += 1
                }
                guard let exponent = flat(script) else { return nil }
                flushNumber()
                guard let base = stack[stack.count - 1].popLast() else { return nil }
                switch base {
                case .number, .identifier, .fraction: break
                case let .row(nodes) where nodes.first == .operator("("): break
                default: return nil
                }
                stack[stack.count - 1].append(.superscript(base, exponent))
                endsOperand = true
                previousMaxX = script.last!.maxX
                index += 1
                continue
            }
            if character.isASCII, character.isNumber || character == "." {
                // A number is contiguous digits; a decimal point stands between digits.
                if let value = number, glyph.minX - value.maxX <= size * 0.15 {
                    number = (value.text + String(character), glyph.maxX)
                } else {
                    guard opensOperand(at: glyph.minX) else { return nil }
                    flushNumber()
                    number = (String(character), glyph.maxX)
                }
            } else if character.isASCII, character.isLetter {
                guard glyph.mathItalic, opensOperand(at: glyph.minX) else { return nil }
                flushNumber()
                stack[stack.count - 1].append(.identifier(String(character)))
            } else if character == "(" {
                guard opensOperand(at: glyph.minX) else { return nil }
                flushNumber()
                stack.append([.operator("(")])
            } else if character == ")" {
                flushNumber()
                guard stack.count > 1 else { return nil }
                let group = stack.removeLast() + [.operator(")")]
                stack[stack.count - 1].append(.row(group))
            } else if let symbol = operators[character] {
                flushNumber()
                stack[stack.count - 1].append(.operator(symbol))
            } else {
                return nil
            }
            endsOperand = !(operators[character] != nil || character == "(")
            previousMaxX = glyph.maxX
            index += 1
        }
        flushNumber()
        guard stack.count == 1, valid(stack[0]) else { return nil }
        let nodes = stack[0]
        return (nodes.count == 1 ? nodes[0] : .row(nodes), baseline, size)
    }

    /// An exponent: numbers, variables and a leading sign on one baseline.
    private static func flat(_ glyphs: [Glyph]) -> MathExpression.Node? {
        var nodes: [MathExpression.Node] = []
        var number = ""
        for glyph in glyphs {
            guard let character = glyph.text.first, glyph.text.count == 1 else { return nil }
            if character.isASCII, character.isNumber {
                number.append(character)
                continue
            }
            if !number.isEmpty { nodes.append(.number(number)); number = "" }
            if character.isASCII, character.isLetter, glyph.mathItalic {
                nodes.append(.identifier(String(character)))
            } else if let symbol = operators[character], signs.contains(symbol), nodes.isEmpty {
                nodes.append(.operator(symbol))
            } else {
                return nil
            }
        }
        if !number.isEmpty { nodes.append(.number(number)) }
        guard valid(nodes) else { return nil }
        return nodes.count == 1 ? nodes[0] : .row(nodes)
    }

    /// Whether a list of nodes reads as operands joined by operators: each operator stands between
    /// operands, except a sign, which may open an operand; two numbers never stand side by side,
    /// and a number never follows a variable (`x 2` is no product a book prints). A number may
    /// precede a fraction (a mixed number, `3 1/2`). Bracketed groups are read inside too.
    static func valid(_ node: MathExpression.Node) -> Bool {
        if case let .row(nodes) = node { return valid(nodes) }
        return valid([node])
    }

    static func valid(_ nodes: [MathExpression.Node]) -> Bool {
        var content = nodes
        if case .operator("(")? = nodes.first, case .operator(")")? = nodes.last {
            content = Array(nodes.dropFirst().dropLast())
        }
        guard !content.isEmpty else { return false }
        var expectsOperand = true
        var previous: MathExpression.Node?
        for (index, node) in content.enumerated() {
            switch node {
            case let .operator(symbol):
                guard symbol != "(", symbol != ")" else { return false }
                if expectsOperand, !(signs.contains(symbol) && index + 1 < content.count) { return false }
                expectsOperand = true
            case let .row(inner):
                guard valid(inner) else { return false }
                expectsOperand = false
            case let .number(value):
                guard value.range(of: #"^[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil else { return false }
                if !expectsOperand, let previous {
                    switch previous {
                    case .number, .identifier, .superscript: return false
                    default: break
                    }
                }
                expectsOperand = false
            case let .fraction(numerator, denominator, _):
                guard valid(numerator), valid(denominator) else { return false }
                expectsOperand = false
            case let .superscript(base, script):
                guard valid(base), valid(script) else { return false }
                expectsOperand = false
            default:
                expectsOperand = false
            }
            previous = node
        }
        return !expectsOperand
    }
}
