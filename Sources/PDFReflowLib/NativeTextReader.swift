import Foundation
import PDFKit
import CoreText
#if os(macOS)
import AppKit
private typealias PlatformFont = NSFont
#else
import UIKit
private typealias PlatformFont = UIFont
#endif

enum NativeTextReader {
    // PDFKit attributed extraction can raise an NSFont exception when separate documents
    // are read concurrently (#21). Serialize this synchronous page step across converter
    // instances; never hold the lock across async progress, OCR, graphics or EPUB writing.
    // Host code using PDFKit independently does not participate in this library-local lock.
    private static let extractionLock = NSLock()

    static func withExtractionLock<T>(_ operation: () throws -> T) throws -> T {
        try Task.checkCancellation()
        // Keep the uncontended path immediate. A queued conversion checks cancellation
        // between timed waits instead of waiting for another document's page to finish.
        // This does not interrupt a PDFKit call already executing inside the gate.
        if !extractionLock.try() {
            while !extractionLock.lock(before: Date(timeIntervalSinceNow: 0.05)) {
                try Task.checkCancellation()
            }
        }
        defer { extractionLock.unlock() }
        try Task.checkCancellation()
        return try operation()
    }

    /// What line repair found on a page drawn in index-named glyphs (#143).
    final class IndexGlyphReport {
        /// Lines rewritten through established characters, and lines with index-glyph shows left
        /// as PDFKit read them.
        var repairedLines = 0
        var unrepairedLines = 0
        /// Each line's text as PDFKit reported it, before any repair.
        var nativeText: [String] = []
        init() {}
    }

    /// `borderlessTableInk`, when given (the page's painted rectangles), also splits the rows of
    /// a borderless table whose cells PDFKit merges into one line; see `splitBorderlessTables`, and
    /// the rows of a list PDFKit merges where it reads the others apart (`splitAtRowEdges`); a page
    /// the pipeline reads as native typography passes it, and invisible text over a scan does not.
    /// `glyphDecodings` are the characters the document established for index-glyph fonts
    /// (`GlyphIndexDecoder`); lines drawn in them are repaired, and `report` counts the outcome.
    /// `removingOverprints` drops a line that only overprints another (`withoutOverprints`, #165);
    /// only `tools/capture-layout-fixture.swift` turns it off, to record PDFKit's lines as they come.
    static func lines(on page: PDFPage, limit: Int, includeStyle: Bool = true,
                      columnJoints: [ColumnJoint] = [], borderlessTableInk: [CGRect]? = nil,
                      blanks: [FormBlank] = [],
                      glyphDecodings: [String: [UInt8: String]] = [:], report: IndexGlyphReport? = nil,
                      removingOverprints: Bool = true) throws -> [TextLine] {
        try withExtractionLock {
            // The page's text shows and their fonts' weights, for bold PDFKit cannot name (#125).
            let weights = includeStyle && page.numberOfCharacters <= limit
                ? page.pageRef.map { FontWeightReader.read($0, decodings: glyphDecodings) } ?? [] : []
            // Symbol fonts' private-use characters, read from the page's font resources the first time
            // a line holds one (#155).
            let privateUse = PrivateUseCharacters(page: page)
            // The page's text shows, for word boundaries PDFKit drops (#119, #128) and for
            // detached content it joins into one line (#14).
            let spacing = includeStyle && page.numberOfCharacters <= limit
                ? page.pageRef.map { NativeSpacingReader.read($0, decodings: glyphDecodings) } ?? [] : []
            var lines = try extractLines(on: page, limit: limit, includeStyle: includeStyle, weights: weights,
                                         spacing: spacing, report: report, privateUse: privateUse)
            // Overprints go before any split. Dropping them changes what the page holds, while
            // every split below only divides a line the page already has, and each of those asks
            // which line a show or a rectangle belongs to: `splitDetachedShows` takes a cut only
            // where each show origin falls inside exactly one line rectangle, which two identical
            // rectangles can never satisfy, so an overprinted line left standing would refuse its
            // own split and any other line its rectangle covers (#165, #14).
            if removingOverprints { lines = withoutOverprints(lines) }
            lines = try splitDetachedShows(lines, shows: spacing, on: page, includeStyle: includeStyle,
                                           weights: weights, privateUse: privateUse)
            if !blanks.isEmpty {
                lines = try splitAtBlanks(lines, blanks: blanks, on: page, includeStyle: includeStyle, weights: weights,
                                          privateUse: privateUse)
            }
            if !columnJoints.isEmpty {
                lines = try splitAtColumnJoints(lines, joints: columnJoints, on: page, includeStyle: includeStyle, weights: weights,
                                                privateUse: privateUse)
            }
            if let ink = borderlessTableInk {
                lines = try splitBorderlessTables(lines, ink: ink, on: page, includeStyle: includeStyle, weights: weights,
                                                  privateUse: privateUse)
                lines = try splitColumnGrids(lines, on: page, includeStyle: includeStyle, weights: weights,
                                             privateUse: privateUse)
                lines = try splitAtRowEdges(lines, on: page, includeStyle: includeStyle, weights: weights,
                                            privateUse: privateUse)
            }
            // Last, because every step above matches line text to the page's own characters and
            // shows, where a ligature is one character (`NativeSpacingReader` reads the glyph `ff`
            // as U+FB00, `GlyphIndexDecoder` index 27 too). From here on it is letters (#189).
            for index in lines.indices { lines[index].spellOutLigatures() }
            return lines
        }
    }

    /// Drops a line that only overprints another: the same text, in the same size, drawn on the
    /// same rectangle to within a twentieth of a point (#165).
    ///
    /// A source can stack two text boxes with the same words in the same place. The Earthdata
    /// deck, exported from Google Slides, keeps each build step's boxes on the finished slide, so
    /// slides 13–21 draw `Cumulus` once alone and once above `Data` / `Archive`, and slides 19 and
    /// 20 draw `End-User` / `Interpretation` twice over. Nothing distinguishes the two drawings on
    /// the rendered page — the second lands glyph for glyph on the first — but PDFKit returns a
    /// line for each, and reflow read them as separate paragraphs (`Cumulus`, then `Cumulus Data
    /// Archive`). The second draws no ink the first has not drawn, so it carries no text of its
    /// own. Fake bold set by drawing a line twice offsets the copy by a fraction of an em, well
    /// past this tolerance, and keeps both lines; a word genuinely repeated on a page stands
    /// somewhere else, so its rectangle differs.
    static func withoutOverprints(_ lines: [TextLine]) -> [TextLine] {
        guard lines.count > 1 else { return lines }
        var kept: [TextLine] = []
        kept.reserveCapacity(lines.count)
        for line in lines {
            let overprints = kept.contains { other in
                other.text == line.text && other.fontSize == line.fontSize
                    && abs(other.rect.minX - line.rect.minX) <= 0.05 && abs(other.rect.minY - line.rect.minY) <= 0.05
                    && abs(other.rect.width - line.rect.width) <= 0.05 && abs(other.rect.height - line.rect.height) <= 0.05
            }
            if !overprints { kept.append(line) }
        }
        return kept
    }

    /// The joints a line crosses inside a ruled grid: its middle lies within the joint's rows
    /// and it reaches more than one em past the joint on both sides.
    static func crossedJoints(_ line: TextLine, _ joints: [ColumnJoint]) -> [CGFloat] {
        let em = max(4, line.fontSize)
        return joints.filter { joint in
            line.rect.midY > joint.minY && line.rect.midY < joint.maxY
                && line.rect.minX < joint.x - em && line.rect.maxX > joint.x + em
        }.map(\.x)
    }

    /// A page's decodable private-use characters (`PrivateUseDecoder`), read once and only for a
    /// page whose text holds one.
    final class PrivateUseCharacters {
        private let page: PDFPage
        private var characters: [UInt32: String]?
        init(page: PDFPage) { self.page = page }

        func decode(_ text: String) -> String {
            guard PrivateUseDecoder.containsPrivateUse(text) else { return text }
            return PrivateUseDecoder.decode(text, read())
        }

        func decode(_ attributed: NSAttributedString) -> NSAttributedString {
            guard PrivateUseDecoder.containsPrivateUse(attributed.string) else { return attributed }
            return PrivateUseDecoder.decode(attributed, read())
        }

        private func read() -> [UInt32: String] {
            if let characters { return characters }
            let read = page.pageRef.map(PrivateUseDecoder.characters(on:)) ?? [:]
            characters = read
            return read
        }
    }

    private static func squeezed(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The characters of a line between two x positions as a line of their own, measured with
    /// PDFKit's rectangle selections; nil when the span holds no visible text.
    private static func piece(of rect: CGRect, from minX: CGFloat, to maxX: CGFloat,
                              on page: PDFPage, includeStyle: Bool, weights: [FontWeightReader.Show],
                              privateUse: PrivateUseCharacters) -> TextLine? {
        func selection(from minX: CGFloat, to maxX: CGFloat) -> PDFSelection? {
            guard maxX > minX else { return nil }
            return page.selection(for: CGRect(x: minX, y: rect.minY, width: maxX - minX, height: rect.height))
        }
        func visible(_ selection: PDFSelection?) -> String {
            squeezed(selection?.string?.replacingOccurrences(of: "\u{FFFC}", with: " ") ?? "")
        }
        // A space glyph stretches across the gap; shrink both edges of the selection until
        // it holds the piece's own characters only.
        let target = visible(selection(from: minX, to: maxX))
        guard !target.isEmpty else { return nil }
        var low = minX, high = maxX
        for _ in 0..<14 {
            let middle = (low + high) / 2
            if visible(selection(from: minX, to: middle)) == target { high = middle } else { low = middle }
        }
        var left = minX
        low = minX
        var top = high
        for _ in 0..<14 {
            let middle = (low + top) / 2
            if visible(selection(from: middle, to: high)) == target { left = middle; low = middle } else { top = middle }
        }
        guard let chosen = selection(from: left, to: high), visible(chosen) == target,
              let raw = chosen.string?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let bounds = chosen.bounds(for: page)
        guard bounds.isFinite, !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return nil }
        var semantic = raw
        let attributed = includeStyle ? chosen.attributedString.map { original -> NSAttributedString in
            var text = original
            // Index-named glyphs are repaired in each piece as in its whole line (#143).
            var carry: FontWeightReader.IndexGlyphCarry?
            if weights.contains(where: { $0.indexFont != nil }),
               case let repair = FontWeightReader.repairIndexGlyphs(weights, in: original, bounds: bounds, allBounds: [bounds], carry: &carry),
               repair.outcome == .repaired, carry == nil, original.string.trimmingCharacters(in: .whitespacesAndNewlines) == raw {
                text = repair.text
                semantic = repair.text.string.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let styled = FontWeightReader.apply(weights, to: text, bounds: bounds, allBounds: [bounds])
            let drawn = redrawn(styled, semantic: semantic, bounds: bounds, allBounds: [bounds], weights: weights)
            semantic = drawn.semantic
            return privateUse.decode(drawn.attributed ?? styled)
        } : nil
        return textLine(semantic: privateUse.decode(semantic.replacingOccurrences(of: "\u{FFFC}", with: " ")),
                        bounds: bounds, attributed: attributed)
    }

    /// A line with the glyphs its fonts' maps misreport rewritten as drawn (`FontWeightReader.redrawGlyphs`,
    /// #186), and its semantic text to match. The line is left as it was unless its attributed text is
    /// its semantic text, so the two never disagree.
    private static func redrawn(_ attributed: NSAttributedString?, semantic: String, bounds: CGRect, allBounds: [CGRect],
                                weights: [FontWeightReader.Show]) -> (attributed: NSAttributedString?, semantic: String) {
        guard let attributed, weights.contains(where: { $0.redraws != nil }) else { return (attributed, semantic) }
        let drawn = FontWeightReader.redrawGlyphs(weights, in: attributed, bounds: bounds, allBounds: allBounds)
        func plain(_ text: String) -> String {
            text.replacingOccurrences(of: "\u{FFFC}", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard drawn.string != attributed.string, plain(attributed.string) == plain(semantic) else { return (attributed, semantic) }
        return (drawn, drawn.string.replacingOccurrences(of: "\u{FFFC}", with: " "))
    }

    /// A line cut in two at `x`: both pieces exist, spell the line apart from the whitespace at
    /// the cut, stand on their own sides of `x` and at least `gap` apart.
    private static func cut(_ line: TextLine, at x: CGFloat, gap: CGFloat, on page: PDFPage,
                            includeStyle: Bool, weights: [FontWeightReader.Show],
                            privateUse: PrivateUseCharacters) -> (left: TextLine, right: TextLine)? {
        let rect = line.rect
        guard let left = piece(of: rect, from: rect.minX, to: x, on: page, includeStyle: includeStyle, weights: weights,
                               privateUse: privateUse),
              let right = piece(of: rect, from: x, to: rect.maxX, on: page, includeStyle: includeStyle, weights: weights,
                                privateUse: privateUse),
              squeezed(left.text + " " + right.text) == squeezed(line.text),
              right.rect.minX - left.rect.maxX >= gap,
              left.rect.maxX <= x + 1, right.rect.minX >= x - 1 else { return nil }
        return (left, right)
    }

    /// PDFKit returns a ruled table's cells on one baseline as one line ("Tool Definition In
    /// practice", Fed page 46). A line crossing a column joint of the rule grid is split there
    /// when the joint falls in whitespace between the glyphs on either side and those glyphs
    /// stand at least one em apart, measured with PDFKit's own rectangle selections; prose
    /// crossing the joint (a caption, a title) has only word spaces and stays whole. The pieces
    /// must spell the line exactly, apart from the whitespace at the cut, or the line is kept
    /// (#65).
    private static func splitAtColumnJoints(_ lines: [TextLine], joints: [ColumnJoint],
                                            on page: PDFPage, includeStyle: Bool, weights: [FontWeightReader.Show],
                                            privateUse: PrivateUseCharacters) throws -> [TextLine] {
        var result: [TextLine] = []
        for line in lines {
            try Task.checkCancellation()
            let crossed = crossedJoints(line, joints)
            guard !crossed.isEmpty, !line.monospaced else { result.append(line); continue }
            let rect = line.rect
            let em = max(4, line.fontSize)
            // A cut is real when the joint falls between words and the glyphs on either side of
            // it stand at least one em apart.
            let cuts = crossed.filter {
                cut(line, at: $0, gap: em, on: page, includeStyle: includeStyle, weights: weights, privateUse: privateUse) != nil
            }
            let edges = [rect.minX] + cuts + [rect.maxX]
            var pieces: [TextLine] = []
            for (start, end) in zip(edges, edges.dropFirst()) {
                guard let next = piece(of: rect, from: start, to: end, on: page, includeStyle: includeStyle, weights: weights,
                                       privateUse: privateUse) else { pieces = []; break }
                pieces.append(next)
            }
            guard pieces.count >= 2, squeezed(pieces.map(\.text).joined(separator: " ")) == squeezed(line.text) else {
                result.append(line); continue
            }
            result += pieces
        }
        return result
    }

    /// PDFKit reads some rows of a form across the ruled blank set in them as one line, the gap
    /// collapsed: the US Courts form's `State of (name) ____.` comes back as `State of (name).`, and
    /// four more such rows on pages 3 and 4 likewise (#152). Where a one-line field's blank
    /// (`FormBlank.sharesRow`) lies wholly inside a line's extent, the line is cut at the blank's
    /// middle, as a ruled grid's joint cuts a table row (`splitAtColumnJoints`), and the pieces must
    /// spell the line (PDFKit may have closed the gap without a space, so spaces are not compared).
    ///
    /// PDFKit's geometry cannot show that the blank is empty: it stretches the boxes of the two
    /// characters beside a collapsed gap across it, so `(name)` ends at the blank's middle and the
    /// period after it begins there. What it can show is what stands over the blank: a selection
    /// of the blank's interior, an em in from each end, holds only those two stretched boxes — a
    /// bracket, a period, a comma, a space — and no letter or digit, where a value printed on the
    /// rule would. The pieces then stand on their own sides of the rule.
    /// The reconstruction sets the blank back between them (`LayoutReconstructor.joiningBlankRows`).
    private static func splitAtBlanks(_ lines: [TextLine], blanks: [FormBlank], on page: PDFPage,
                                      includeStyle: Bool, weights: [FontWeightReader.Show],
                                      privateUse: PrivateUseCharacters) throws -> [TextLine] {
        func letters(_ text: String) -> String { String(text.filter { !$0.isWhitespace }) }
        var result: [TextLine] = []
        for line in lines {
            try Task.checkCancellation()
            let em = max(4, line.fontSize)
            // The rules as drawn, without `GraphicsReader`'s two points of padding.
            let crossed = blanks.filter { $0.sharesRow(with: line.rect) }.map { $0.rule.insetBy(dx: 2, dy: 0) }
                .filter { $0.width > 0 && line.rect.minX < $0.minX && line.rect.maxX > $0.maxX }
                .sorted { $0.minX < $1.minX }
            guard !crossed.isEmpty, !line.monospaced, line.readingDirection == nil else { result.append(line); continue }
            let empty = crossed.allSatisfy { rule in
                guard rule.width > em * 3 else { return false }
                let interior = CGRect(x: rule.minX + em, y: line.rect.minY, width: rule.width - em * 2, height: line.rect.height)
                let over = page.selection(for: interior)?.string ?? ""
                return !over.contains { $0.isLetter || $0.isNumber }
            }
            let edges = [line.rect.minX] + crossed.map(\.midX) + [line.rect.maxX]
            var pieces: [TextLine] = []
            for (start, end) in zip(edges, edges.dropFirst()) where empty {
                guard let next = piece(of: line.rect, from: start, to: end, on: page, includeStyle: includeStyle,
                                       weights: weights, privateUse: privateUse) else { pieces = []; break }
                pieces.append(next)
            }
            guard pieces.count == crossed.count + 1, letters(pieces.map(\.text).joined()) == letters(line.text) else {
                result.append(line); continue
            }
            // Each piece keeps to its side of the rules beside it.
            for index in pieces.indices {
                var rect = pieces[index].rect
                if index > 0 { rect = CGRect(x: max(rect.minX, crossed[index - 1].maxX), y: rect.minY,
                                             width: rect.maxX - max(rect.minX, crossed[index - 1].maxX), height: rect.height) }
                if index < crossed.count { rect.size.width = min(rect.maxX, crossed[index].minX) - rect.minX }
                guard rect.width > 0 else { pieces = []; break }
                pieces[index].rect = rect
            }
            guard !pieces.isEmpty else { result.append(line); continue }
            result += pieces
        }
        return result
    }

    /// Empty space that separates content standing on two sides of a page from a word space, a
    /// column gap or a table's cells (#14). Measured on the corpus's own merged lines: every gap
    /// a column, a cell or a graph label leaves reaches at most 11.5 ems and 19.4% of the page's
    /// width (Wallace's answer columns and coordinate labels, the FAA's beacon table, the Census
    /// report's figures), while content set against the opposite side of a page begins at 17.8 ems
    /// and 35.7% (Wallace's two-graph exercise row, Our Flag's signature block, the *Dietary
    /// Guidelines* cover's labels and footer). Nothing at all lies between.
    static let detachedShowGap: CGFloat = 8
    static let detachedShowPageShare: CGFloat = 0.25

    /// Detached content PDFKit returns as one line (#14, the *Dietary Guidelines* cover, whose
    /// `& Healthy Fats` labels the left of the food pyramid and `& Fruits` its right on the same
    /// baseline). PDFKit joins the two with a space glyph 343 pt wide and reports character
    /// positions that no longer follow the text, so a cut cannot be found by walking characters.
    /// The text-show positions in the content stream can still say where each piece begins.
    ///
    /// A cut is proposed at a show whose origin stands `detachedShowGap` ems and
    /// `detachedShowPageShare` of the page beyond the previous show's origin — a necessary
    /// condition for that much empty page, since neither show's ink begins before its origin, and
    /// cheap enough to leave ordinary prose untouched. PDFKit's own rectangle selections then
    /// measure the pieces, which must spell the line exactly apart from the whitespace at the
    /// cuts, stand on their own sides of them, and leave every neighbouring pair that same
    /// distance apart with more empty page between them than their own ink. Word spaces, prose
    /// rows and a table's columns leave far less. Any failure keeps the whole line, so a line
    /// that mixes a real gap with a doubtful one is never taken apart.
    private static func splitDetachedShows(_ lines: [TextLine], shows: [NativeSpacingReader.Evidence],
                                           on page: PDFPage, includeStyle: Bool, weights: [FontWeightReader.Show],
                                           privateUse: PrivateUseCharacters) throws -> [TextLine] {
        guard !shows.isEmpty, lines.count <= 10_000, shows.count * lines.count <= 2_000_000 else { return lines }
        let allBounds = lines.map(\.rect)
        let share = page.bounds(for: .cropBox).width * detachedShowPageShare
        var result: [TextLine] = []
        for line in lines {
            try Task.checkCancellation()
            let rect = line.rect
            guard !line.monospaced, rect.width > share else { result.append(line); continue }
            let least = max(max(4, line.fontSize) * detachedShowGap, share)
            // Every show placed on this line, and on no other: overlapping line rectangles
            // cannot say which line a show belongs to.
            let matches = shows.filter { rect.insetBy(dx: -0.75, dy: -0.75).contains($0.origin) }
            guard matches.count >= 2, matches.allSatisfy({ match in
                allBounds.filter { $0.insetBy(dx: -0.75, dy: -0.75).contains(match.origin) }.count == 1
            }) else { result.append(line); continue }
            let ordered = matches.sorted { $0.origin.x < $1.origin.x }
            let cuts = zip(ordered, ordered.dropFirst()).compactMap { left, right -> CGFloat? in
                right.origin.x - left.origin.x > least ? right.origin.x - 0.5 : nil
            }
            guard !cuts.isEmpty else { result.append(line); continue }
            let edges = [rect.minX] + cuts + [rect.maxX]
            var pieces: [TextLine] = []
            for (start, end) in zip(edges, edges.dropFirst()) {
                guard let next = piece(of: rect, from: start, to: end, on: page, includeStyle: includeStyle,
                                       weights: weights, privateUse: privateUse) else { pieces = []; break }
                pieces.append(next)
            }
            guard pieces.count == cuts.count + 1,
                  squeezed(pieces.map(\.text).joined(separator: " ")) == squeezed(line.text),
                  zip(pieces, cuts).allSatisfy({ $0.rect.maxX <= $1 + 1 }),
                  zip(pieces.dropFirst(), cuts).allSatisfy({ $0.rect.minX >= $1 - 1 }),
                  zip(pieces, pieces.dropFirst()).allSatisfy({ left, right in
                      let gap = right.rect.minX - left.rect.maxX
                      return gap >= least && gap >= left.rect.width + right.rect.width
                  }) else { result.append(line); continue }
            result += pieces
        }
        return result
    }

    /// Letters, all capitals: a borderless table's column headings (`CATEGORY`, `LIMIT LOAD FACTOR`).
    static func isCapitalHeading(_ text: String) -> Bool {
        let letters = text.filter(\.isLetter)
        return letters.count >= 2 && letters.allSatisfy(\.isUppercase)
    }

    /// A borderless two-column table whose rows PDFKit merges (#121, FAA page 131's `CATEGORY` /
    /// `LIMIT LOAD FACTOR` table: `Normal1 3.8 to –1.52` is one line, but `Utility (mild
    /// acrobatics,` and `4.4 to –1.76` are two). Where PDFKit keeps one row's cells apart, their
    /// gap (two to ten ems, both pieces at most fifteen ems wide, nothing between them) is the
    /// column gap. The table is the run of rows through that pair, each row's baseline within
    /// 1.8 ems of the next, among the lines overlapping the pair's width widened by an em
    /// (so a neighbouring page column is not part of it): every line in the run is the same size
    /// and not monospaced, lies on one side of the gap's middle, or is cut inside the gap where
    /// PDFKit's selections show glyphs at least two ems apart on either side. The run's first row
    /// is its heading, in capitals on both sides; at least three rows (the heading among them) hold
    /// text on both sides, every row's left text ends at least an em before any row's right text
    /// begins, and nothing painted lies within the run. Only then are its crossing lines split. A
    /// prose line crossing the gap has word spaces there, so it ends the run; a run without a
    /// capital heading, with cells too close to share a gutter, or near a drawn rule, is left
    /// exactly as PDFKit read it.
    private static func splitBorderlessTables(_ lines: [TextLine], ink: [CGRect], on page: PDFPage,
                                              includeStyle: Bool, weights: [FontWeightReader.Show],
                                              privateUse: PrivateUseCharacters) throws -> [TextLine] {
        func sameRow(_ a: TextLine, _ b: TextLine) -> Bool { abs(a.rect.minY - b.rect.minY) <= 1.5 }
        var result = lines
        for left in lines where !left.monospaced {
            let em = max(4, left.fontSize)
            guard left.rect.width <= em * 15 else { continue }
            for right in lines where right != left && !right.monospaced && sameRow(left, right) {
                let gap = right.rect.minX - left.rect.maxX
                guard right.rect.width <= em * 15, gap >= em * 2, gap <= em * 10,
                      abs(right.fontSize - left.fontSize) <= em * 0.15,
                      result.contains(left), result.contains(right),
                      !lines.contains(where: { $0 != left && $0 != right && sameRow($0, left)
                          && $0.rect.maxX > left.rect.maxX && $0.rect.minX < right.rect.minX }) else { continue }
                try Task.checkCancellation()
                let lower = left.rect.maxX, upper = right.rect.minX
                let window = (left.rect.minX - em, right.rect.maxX + em)
                var rows: [[TextLine]] = []
                for line in result.filter({ $0.rect.maxX > window.0 && $0.rect.minX < window.1 })
                    .sorted(by: { $0.rect.minY > $1.rect.minY }) {
                    if let last = rows.last?.first, sameRow(last, line) { rows[rows.count - 1].append(line) } else { rows.append([line]) }
                }
                guard let anchor = rows.firstIndex(where: { $0.contains(left) }) else { continue }
                func step(_ upperRow: Int) -> Bool { rows[upperRow][0].rect.minY - rows[upperRow + 1][0].rect.minY <= em * 1.8 }
                // Before measuring any glyphs: the rows chained to the pair must start with a
                // capital heading.
                var top = anchor
                while top > 0, step(top - 1) { top -= 1 }
                guard let heading = rows[top...anchor].firstIndex(where: { row in
                    row.allSatisfy { isCapitalHeading($0.text) }
                }) else { continue }
                // Each row read against the gap: its lines by side of the gap's middle, crossing
                // lines cut.
                let middle = (lower + upper) / 2
                func read(_ row: [TextLine]) -> (left: [TextLine], right: [TextLine], cuts: [(TextLine, [TextLine])])? {
                    var lefts: [TextLine] = [], rights: [TextLine] = [], cuts: [(TextLine, [TextLine])] = []
                    for line in row {
                        guard !line.monospaced, abs(line.fontSize - left.fontSize) <= em * 0.15 else { return nil }
                        if line.rect.maxX <= middle { lefts.append(line); continue }
                        if line.rect.minX >= middle { rights.append(line); continue }
                        let positions = [lower + em * 0.5, middle, upper - em * 0.5]
                        guard let pieces = positions.lazy.compactMap({
                            cut(line, at: $0, gap: em * 2, on: page, includeStyle: includeStyle, weights: weights, privateUse: privateUse)
                        }).first else { return nil }
                        lefts.append(pieces.left); rights.append(pieces.right)
                        cuts.append((line, [pieces.left, pieces.right]))
                    }
                    return (lefts, rights, cuts)
                }
                guard let head = read(rows[heading]), !head.left.isEmpty, !head.right.isEmpty,
                      (head.left + head.right).allSatisfy({ isCapitalHeading($0.text) }) else { continue }
                var readRows = [head]
                var bottom = heading
                while bottom + 1 < rows.count, step(bottom), let next = read(rows[bottom + 1]) {
                    readRows.append(next)
                    bottom += 1
                }
                // Every row's left text ends at least an em before any row's right text begins.
                let gutter = (readRows.flatMap(\.right).map(\.rect.minX).min() ?? 0) - (readRows.flatMap(\.left).map(\.rect.maxX).max() ?? 0)
                guard bottom >= anchor, gutter >= em, readRows.filter({ !$0.left.isEmpty && !$0.right.isEmpty }).count >= 3,
                      !ink.contains(where: { $0.intersects(union(rows[heading...bottom].flatMap { $0.map(\.rect) })) }) else { continue }
                for (line, pieces) in readRows.flatMap(\.cuts) {
                    guard let index = result.firstIndex(of: line) else { continue }
                    result.replaceSubrange(index...index, with: pieces)
                }
            }
        }
        return result
    }

    /// A line's glyphs, each measured with PDFKit's one-character selection, joined into words at
    /// gaps under a quarter em. Each word spans the line's height, so words group into the line's
    /// baseline. Where the line's text has as many words, they take its words: index-glyph repair
    /// (#143) rewrote the characters PDFKit reports for them.
    private static func glyphWords(_ line: TextLine, on page: PDFPage) -> [ColumnGrid.Piece]? {
        guard let selection = page.selection(for: line.rect) else { return nil }
        let em = max(4, line.fontSize)
        let area = line.rect.insetBy(dx: -0.5, dy: -0.5)
        var glyphs: [(character: Character, box: CGRect)] = []
        for index in 0..<selection.numberOfTextRanges(on: page) {
            let range = selection.range(at: index, on: page)
            guard range.location != NSNotFound, range.length > 0, range.length <= 2_000 else { continue }
            for offset in range.location..<(range.location + range.length) {
                guard let one = page.selection(for: NSRange(location: offset, length: 1)),
                      let character = one.string?.first, !character.isWhitespace else { continue }
                let box = one.bounds(for: page)
                // A synthesized line break selects the glyph before it again.
                guard box.isFinite, !box.isNull, box.width > 0, box.height > 0,
                      area.contains(CGPoint(x: box.midX, y: box.midY)), glyphs.last?.box != box else { continue }
                glyphs.append((character, box))
            }
        }
        guard !glyphs.isEmpty else { return nil }
        var words: [(text: String, minX: CGFloat, maxX: CGFloat)] = []
        for glyph in glyphs.sorted(by: { $0.box.minX < $1.box.minX }) {
            if let last = words.last, glyph.box.minX - last.maxX < em * 0.25 {
                words[words.count - 1].text.append(glyph.character)
                words[words.count - 1].maxX = max(last.maxX, glyph.box.maxX)
            } else { words.append((String(glyph.character), glyph.box.minX, glyph.box.maxX)) }
        }
        let tokens = line.text.split(whereSeparator: \.isWhitespace).map(String.init)
        return words.enumerated().map { index, word in
            ColumnGrid.Piece(rect: CGRect(x: word.minX, y: line.rect.minY, width: word.maxX - word.minX, height: line.rect.height),
                             text: tokens.count == words.count ? tokens[index] : word.text, size: line.fontSize, id: index)
        }
    }

    /// A line cut into the cells its word groups make (`parts`, left to right). When the line's
    /// text has one word for each of its `measured` glyph words, each cell takes its words' share
    /// of the line's own text, styles and repairs included (PDFKit's selections inside a Census row
    /// would report the index glyphs undecoded, #143); otherwise PDFKit's rectangle selections
    /// measure each cell between the midpoints of the gaps. The cells must spell the line exactly,
    /// apart from the whitespace between them.
    private static func cells(of line: TextLine, parts: [[ColumnGrid.Piece]], measured: Int, on page: PDFPage,
                              includeStyle: Bool, weights: [FontWeightReader.Show],
                              privateUse: PrivateUseCharacters) -> [TextLine]? {
        let cuts = zip(parts, parts.dropFirst()).map { ($0.last!.rect.maxX + $1.first!.rect.minX) / 2 }
        let edges = [line.rect.minX] + cuts + [line.rect.maxX]
        var pieces: [TextLine] = []
        if line.text.split(whereSeparator: \.isWhitespace).count == measured,
           let slices = slices(line.content, tokenCounts: parts.map(\.count)) {
            for (part, slice) in zip(parts, slices) {
                var cell = line
                cell.replaceContent(slice)
                cell.rect = CGRect(x: part[0].rect.minX, y: line.rect.minY,
                                   width: part[part.count - 1].rect.maxX - part[0].rect.minX, height: line.rect.height)
                cell.readingRect = nil
                cell.trailingSpace = pieces.count < parts.count - 1 || line.trailingSpace
                pieces.append(cell)
            }
        } else {
            for (start, end) in zip(edges, edges.dropFirst()) {
                guard let next = piece(of: line.rect, from: start, to: end, on: page, includeStyle: includeStyle,
                                       weights: weights, privateUse: privateUse),
                      next.rect.minX >= start - 1, next.rect.maxX <= end + 1 else { return nil }
                pieces.append(next)
            }
        }
        guard pieces.count == parts.count,
              squeezed(pieces.map(\.text).joined(separator: " ")) == squeezed(line.text) else { return nil }
        return pieces
    }

    /// Styled text divided at its whitespace into parts of `tokenCounts` words each, trimmed; nil
    /// when the text holds anything but plain runs or a different number of words.
    static func slices(_ text: InlineText, tokenCounts: [Int]) -> [InlineText]? {
        guard !tokenCounts.isEmpty, tokenCounts.allSatisfy({ $0 > 0 }) else { return nil }
        var parts = [InlineText](repeating: InlineText(), count: tokenCounts.count)
        var part = 0, words = 0, inWord = false
        for element in text.elements {
            guard case let .text(value, style) = element else { return nil }
            for character in value {
                if character.isWhitespace {
                    inWord = false
                } else if !inWord {
                    inWord = true
                    if words == tokenCounts[part] {
                        part += 1; words = 0
                        guard part < tokenCounts.count else { return nil }
                    }
                    words += 1
                }
                if case let .text(last, lastStyle)? = parts[part].elements.last, lastStyle == style {
                    parts[part].elements[parts[part].elements.count - 1] = .text(last + String(character), style)
                } else { parts[part].elements.append(.text(String(character), style)) }
            }
        }
        guard part == tokenCounts.count - 1, words == tokenCounts[part] else { return nil }
        return parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// Borderless tables of aligned columns under a header whose rows PDFKit merges (#150, #137;
    /// Census's `rnkswp05 0.8861 0.9620`, FAA page 410's `T 12,000' and below 25`). Candidate
    /// regions come from the lines: at least three of them ending in a number at one right edge
    /// (`ColumnGrid.regions`), so ordinary pages measure nothing. The lines of each region are
    /// measured glyph by glyph into words, and `ColumnGrid` reads their grid; each line whose words
    /// fall into more than one cell is cut between them (`cells(of:)`). The cuts are kept only when
    /// every line of the grid cuts and the cut lines read as the same grid in layout, so a table
    /// either reaches layout whole or not at all.
    private static func splitColumnGrids(_ lines: [TextLine], on page: PDFPage, includeStyle: Bool,
                                         weights: [FontWeightReader.Show], privateUse: PrivateUseCharacters) throws -> [TextLine] {
        let pieces = lines.enumerated().filter { !$0.element.monospaced }.map {
            ColumnGrid.Piece(rect: $0.element.rect, text: $0.element.text, size: $0.element.fontSize, id: $0.offset)
        }
        let regions = ColumnGrid.regions(in: pieces, capped: false)
        guard !regions.isEmpty else { return lines }
        var replacements: [Int: [TextLine]] = [:]
        for region in regions {
            try Task.checkCancellation()
            // Each region line as words, identified by the line and the word's place in it.
            var words: [ColumnGrid.Piece] = []
            var owners: [(line: Int, word: Int)] = []
            for piece in region.rows.flatMap({ $0 }) where replacements[piece.id] == nil {
                let measured = glyphWords(lines[piece.id], on: page)
                    ?? [ColumnGrid.Piece(rect: piece.rect, text: piece.text, size: piece.size)]
                for (index, var word) in measured.enumerated() {
                    word.id = owners.count
                    owners.append((piece.id, index))
                    words.append(word)
                }
            }
            let rows = ColumnGrid.baselines(words)
            for grid in ColumnGrid.grids(in: rows, beside: region.beside) {
                // Each line's words in order, with their places in the grid.
                var placed: [Int: [(word: ColumnGrid.Piece, placement: ColumnGrid.Placement)]] = [:]
                for (baseline, placements) in grid.placements.enumerated() {
                    for (index, placement) in placements.enumerated() {
                        guard let placement else { continue }
                        let word = rows[baseline][index]
                        placed[owners[word.id].line, default: []].append((word, placement))
                    }
                }
                var cut: [Int: [TextLine]] = [:]
                var complete = true
                for (index, entries) in placed {
                    let ordered = entries.sorted { $0.word.rect.minX < $1.word.rect.minX }
                    var parts: [[ColumnGrid.Piece]] = []
                    var places: [ColumnGrid.Placement] = []
                    for entry in ordered {
                        if places.last == entry.placement { parts[parts.count - 1].append(entry.word) }
                        else { parts.append([entry.word]); places.append(entry.placement) }
                    }
                    // A cell's words are contiguous in its line.
                    guard Set(places.map { "\($0.row):\($0.columns)" }).count == places.count else { complete = false; break }
                    guard parts.count >= 2 else { continue }
                    let line = lines[index]
                    let measured = owners.filter { $0.line == index }.count
                    guard let pieces = cells(of: line, parts: parts, measured: measured, on: page, includeStyle: includeStyle,
                                             weights: weights, privateUse: privateUse) else { complete = false; break }
                    cut[index] = pieces
                }
                guard complete, !cut.isEmpty else { continue }
                // Layout must read the same table from the cut lines.
                let gridLines = Set(placed.keys)
                let after = gridLines.sorted().flatMap { cut[$0] ?? [lines[$0]] }
                let cells = after.map { ColumnGrid.Piece(rect: $0.rect, text: $0.text, size: $0.fontSize) }
                let reread = ColumnGrid.regions(in: cells, capped: true).flatMap { ColumnGrid.grids(in: $0.rows, beside: $0.beside) }
                guard reread.contains(where: { $0.rows == grid.rows && $0.columns == grid.columns
                    && $0.placements.flatMap { $0 }.compactMap { $0 }.count == cells.count }) else { continue }
                replacements.merge(cut) { first, _ in first }
            }
        }
        guard !replacements.isEmpty else { return lines }
        return lines.indices.flatMap { replacements[$0] ?? [lines[$0]] }
    }

    /// An Arabic page number (optionally prefixed by its chapter's number or its part's letter,
    /// `5-17` or `C-2`) or a Roman numeral.
    static func isFolio(_ text: String) -> Bool {
        !text.isEmpty && text.range(of: "^(?:(?:[0-9]+-|[A-Za-z]-)?[0-9]+|m{0,3}(?:cm|cd|d?c{0,3})(?:xc|xl|l?x{0,3})(?:ix|iv|v?i{0,3}))$",
            options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Two edges a page's rows share (#199): at least four rows set a line of one size at `left`
    /// and, on its baseline, the next line of that size at `x`, at least two ems past its end.
    /// `rows` counts them.
    struct RowEdge: Equatable {
        var left: CGFloat
        var x: CGFloat
        var size: CGFloat
        var rows: Int
    }

    /// The edges on which a page's rows set two columns that PDFKit read apart: the Table of Names'
    /// names at 44.7 and descriptions at 152.7 (9/11 pages 449–456). Each line is paired with the
    /// nearest line before it on its baseline (within 1.5 points), in its size (within 5%); pairs
    /// whose two left edges each fall within a point of another's are one edge. A line beside a
    /// neighbouring column's line is paired with that line, whose edge is the other column's.
    static func rowEdges(_ lines: [TextLine]) -> [RowEdge] {
        let usable = lines.filter { !$0.monospaced && $0.readingDirection == nil && $0.fontSize > 0 }
        guard usable.count >= 5, usable.count <= 10_000 else { return [] }
        func sameSize(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) <= max(a, b) * 0.05 }
        let rows = usable.sorted { $0.rect.minY < $1.rect.minY }
        var pairs: [(left: CGFloat, x: CGFloat, size: CGFloat)] = []
        var low = 0
        for line in rows {
            while rows[low].rect.minY < line.rect.minY - 1.5 { low += 1 }
            var nearest: TextLine?
            var index = low
            while index < rows.count, rows[index].rect.minY <= line.rect.minY + 1.5 {
                let other = rows[index]
                if other != line, sameSize(other.fontSize, line.fontSize), other.rect.maxX <= line.rect.minX,
                   other.rect.maxX > nearest?.rect.maxX ?? -.infinity { nearest = other }
                index += 1
            }
            if let nearest, nearest.rect.maxX <= line.rect.minX - max(4, line.fontSize) * 2 {
                pairs.append((nearest.rect.minX, line.rect.minX, line.fontSize))
            }
        }
        pairs.sort { ($0.x, $0.left) < ($1.x, $1.left) }
        var edges: [RowEdge] = []
        for (start, first) in pairs.enumerated() {
            guard !edges.contains(where: { sameSize($0.size, first.size) && first.x - $0.x <= 1
                && abs(first.left - $0.left) <= 1 }) else { continue }
            let group = pairs[start...].prefix { $0.x - first.x <= 1 }
                .filter { sameSize($0.size, first.size) && abs($0.left - first.left) <= 1 }
            if group.count >= 4 { edges.append(RowEdge(left: first.left, x: first.x, size: first.size, rows: group.count)) }
        }
        return edges
    }

    /// Rows PDFKit reads as one line where it reads the page's other rows apart (#199): the Table of
    /// Names sets each name at the page's edge and its description on the same baseline 108 points
    /// in, and PDFKit returns most rows as two lines, but `John Ashcroft Attorney General, 2001–`
    /// (page 449) and `Janet Reno Attorney General, 1993–2001` (page 451) as one, which then reads
    /// as a name without a description and runs into the next name. A line that starts on a row
    /// edge's left edge (`rowEdges`), in its size, and crosses its second is cut there when the
    /// glyphs on either side stand at least two ems apart and the right piece begins on the second
    /// edge, within a point, as its neighbours' second columns do; the pieces must spell the line
    /// apart from the whitespace at the cut (`cut`). A page number is no second column: a contents
    /// entry keeps the folio it ends in (NOAA's `Future Land-Use Options 6-17`, the CIA report's
    /// `for Each Segregation 26`), which reconstruction reads with it. The edge must hold more rows
    /// PDFKit read apart than lines crossing it, so a list PDFKit mostly merges (the report's flight
    /// timelines, page 51) is left as read. A prose line crossing the edge has only word spaces
    /// there and stays whole.
    private static func splitAtRowEdges(_ lines: [TextLine], on page: PDFPage, includeStyle: Bool,
                                        weights: [FontWeightReader.Show], privateUse: PrivateUseCharacters) throws -> [TextLine] {
        let edges = rowEdges(lines)
        guard !edges.isEmpty else { return lines }
        func crosses(_ line: TextLine, _ edge: RowEdge) -> Bool {
            let em = max(4, line.fontSize)
            return !line.monospaced && line.readingDirection == nil
                && abs(edge.size - line.fontSize) <= max(edge.size, line.fontSize) * 0.05
                && abs(line.rect.minX - edge.left) <= 1 && edge.x - edge.left >= em * 2 && line.rect.maxX > edge.x + em
        }
        let kept = edges.filter { edge in lines.filter { crosses($0, edge) }.count < edge.rows }
        guard !kept.isEmpty else { return lines }
        var result: [TextLine] = []
        for line in lines {
            try Task.checkCancellation()
            let em = max(4, line.fontSize)
            var halves: (left: TextLine, right: TextLine)?
            for x in kept.filter({ crosses(line, $0) }).map(\.x).sorted() {
                if let pieces = cut(line, at: x - 0.5, gap: em * 2, on: page, includeStyle: includeStyle, weights: weights,
                                    privateUse: privateUse),
                   abs(pieces.right.rect.minX - x) <= 1, !isFolio(pieces.right.text) { halves = pieces; break }
            }
            guard let halves else { result.append(line); continue }
            result += [halves.left, halves.right]
        }
        return result
    }

    private static func extractLines(on page: PDFPage, limit: Int, includeStyle: Bool, weights: [FontWeightReader.Show],
                                     spacing: [NativeSpacingReader.Evidence], report: IndexGlyphReport?,
                                     privateUse: PrivateUseCharacters) throws -> [TextLine] {
        guard page.numberOfCharacters <= limit else {
            throw ConversionError.resourceLimit("too many characters")
        }
        guard let selection = page.selection(for: page.bounds(for: .cropBox)) else { return [] }
        let selections = selection.selectionsByLine()
        let boundsByLine = selections.map { $0.bounds(for: page) }
        // PDFKit's text of every line, beside its rectangle: a line the shows it holds do not spell
        // may be one piece of a row PDFKit split (`NativeSpacingReader.rowPieceSpaces`, #177).
        let textsByLine = selections.map(\.string)
        var result: [TextLine] = []
        var carry: FontWeightReader.IndexGlyphCarry?
        let indexGlyphs = weights.contains { $0.indexFont != nil }
        if let report, indexGlyphs {
            report.unrepairedLines += FontWeightReader.unplacedIndexShows(weights, allBounds: boundsByLine)
        }
        defer { if carry != nil { report?.unrepairedLines += 1 } }
        // Spacing and style evidence applied to a line's (repaired) characters.
        func finish(_ attributed: NSAttributedString?, semantic: String, exact: Bool, bounds: CGRect,
                    allBounds: [CGRect], allTexts: [String?] = []) -> TextLine {
            let repaired = attributed.map {
                exact ? NativeSpacingReader.apply(spacing, to: $0, bounds: bounds, allBounds: allBounds, allTexts: allTexts) : $0
            }
            let corrected = repaired?.string != attributed?.string
                ? repaired?.string.replacingOccurrences(of: "\u{FFFC}", with: " ") : nil
            let weighted = repaired.map {
                FontWeightReader.apply(weights, to: $0, bounds: bounds, allBounds: allBounds)
            }
            // Glyphs a map misreports are redrawn after spacing and style evidence, which compare
            // PDFKit's characters with those maps (#186).
            let (drawn, text) = redrawn(weighted, semantic: corrected ?? semantic, bounds: bounds,
                                        allBounds: allBounds, weights: weights)
            // Private-use characters are decoded last: spacing and style evidence compare PDFKit's
            // characters with the shows' own maps, which hold the same private-use values (#155).
            return textLine(semantic: privateUse.decode(text),
                            bounds: bounds, attributed: drawn.map(privateUse.decode))
        }
        // A repaired line whose last show PDFKit continues on the next line of its row (the carry),
        // held with its PDFKit characters until that line is read (`joinsSplitShow`).
        var held: (attributed: NSAttributedString, bounds: CGRect, output: Int)?
        for (index, line) in selections.enumerated() {
            try Task.checkCancellation()
            guard let raw = textsByLine[index] else { continue }
            // U+FFFC names an attachment, not a word. Retain a boundary between adjacent
            // words; the graphics reader preserves the object's visible content separately.
            var semantic = raw.replacingOccurrences(of: "\u{FFFC}", with: " ")
            guard !semantic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let bounds = line.bounds(for: page)
            guard bounds.isFinite, !bounds.isNull, bounds.width > 0, bounds.height > 0 else { continue }
            report?.nativeText.append(raw)
            // Object-only selections were discarded before requesting attributed text,
            // which can make PDFKit decode large image attachments.
            var attributed = includeStyle ? line.attributedString : nil
            // Index-named glyphs PDFKit reports as other characters are rewritten first (#143), so
            // spacing and style evidence read the characters the page draws.
            let exact = attributed?.string == raw
            let unrepaired = attributed, previous = held
            held = nil
            var continued = false
            if let original = attributed, indexGlyphs {
                let handed = carry != nil
                let repair = FontWeightReader.repairIndexGlyphs(weights, in: original, bounds: bounds,
                                                                allBounds: boundsByLine, carry: &carry)
                if repair.abandoned { report?.unrepairedLines += 1 }
                if repair.outcome == .repaired, exact {
                    attributed = repair.text
                    semantic = repair.text.string.replacingOccurrences(of: "\u{FFFC}", with: " ")
                    report?.repairedLines += 1
                    continued = handed && !repair.abandoned && carry == nil
                    if carry != nil { held = (original, bounds, result.count) }
                } else if repair.outcome != .none {
                    report?.unrepairedLines += 1
                }
            }
            result.append(finish(attributed, semantic: semantic, exact: exact, bounds: bounds, allBounds: boundsByLine,
                                 allTexts: textsByLine))
            if continued, let previous, previous.output == result.count - 2, let original = unrepaired,
               let joined = joinsSplitShow(previous.attributed, previous.bounds, original, bounds,
                                           continuation: semantic, weights: weights, allBounds: boundsByLine) {
                result.replaceSubrange((result.count - 2)..., with: [
                    finish(joined.text, semantic: joined.text.string.replacingOccurrences(of: "\u{FFFC}", with: " "),
                           exact: true, bounds: joined.bounds, allBounds: boundsByLine),
                ])
            }
        }
        return result
    }

    /// Two PDFKit lines of one row that a single index-glyph show spans (#149). PDFKit reads Census
    /// page 17's reference number `[2]` as a line of its own and the entry's first line as another,
    /// although one show sets both; #143's repair already carries the show's remaining glyphs from
    /// the number's line to the entry's. When that continuation reads as words, the two are one
    /// typeset line and are read as one: their PDFKit characters joined (with a space where neither
    /// sets one), over the union of their rectangles, which holds every show of the row, so repair,
    /// spacing and style evidence see the whole show at once. Each show still lies in one piece's
    /// rectangle alone, so ownership among the page's lines is unchanged. Returns nil unless the
    /// joined line repairs completely with nothing carried on. A row whose continuation is figures
    /// (page 12's `rnkswp05` and its rates) stays in its pieces: those are a table's cells.
    static func joinsSplitShow(_ left: NSAttributedString, _ leftBounds: CGRect, _ right: NSAttributedString,
                               _ rightBounds: CGRect, continuation: String, weights: [FontWeightReader.Show],
                               allBounds: [CGRect]) -> (text: NSAttributedString, bounds: CGRect)? {
        guard left.length > 0, right.length > 0, continuesInWords(continuation) else { return nil }
        let joined = NSMutableAttributedString(attributedString: left)
        if left.string.last?.isWhitespace == false, right.string.first?.isWhitespace == false {
            joined.append(NSAttributedString(string: " ", attributes: left.attributes(at: left.length - 1, effectiveRange: nil)))
        }
        joined.append(right)
        let union = leftBounds.union(rightBounds)
        var carry: FontWeightReader.IndexGlyphCarry?
        let repair = FontWeightReader.repairIndexGlyphs(weights, in: joined, bounds: union, allBounds: allBounds, carry: &carry)
        guard repair.outcome == .repaired, carry == nil, !repair.abandoned else { return nil }
        return (repair.text, union)
    }

    /// Text that continues a line in words rather than figures: at least three words of three or
    /// more letters, and letters making up at least half of its visible characters.
    static func continuesInWords(_ text: String) -> Bool {
        let visible = text.filter { !$0.isWhitespace }
        let letters = visible.filter(\.isLetter).count
        let words = text.split(whereSeparator: \.isWhitespace).filter { $0.filter(\.isLetter).count >= 3 }.count
        return words >= 3 && letters * 2 >= visible.count
    }

    static func textLine(semantic: String, bounds: CGRect, attributed: NSAttributedString?) -> TextLine {
        let font = (attributed?.length ?? 0) > 0
            ? attributed?.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont : nil
        let name = font?.fontName.lowercased() ?? ""
        let mono = name.contains("courier") || name.contains("mono")
        let proposedSize = font?.pointSize ?? bounds.height
        let size = proposedSize.isFinite && proposedSize > 0 && proposedSize <= 100_000
            ? proposedSize : min(100_000, bounds.height)
        let text = semantic.trimmingCharacters(in: mono ? .newlines : .whitespacesAndNewlines)
        var styled: InlineText?
        if let attributed, attributed.string.replacingOccurrences(of: "\u{FFFC}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines) == text {
            styled = inlineText(from: attributed)
        }
        // Keep each selection's own text with its geometry. PDFKit's characterBounds offsets
        // need not agree with string offsets at synthesized newlines on current OS builds.
        var result = TextLine(content: styled ?? InlineText(text), rect: bounds,
            fontSize: size, monospaced: mono)
        // The space PDFKit reported at the line's end, which `text` no longer carries: evidence
        // that this piece was cut inside a line rather than at a line break (#180).
        result.trailingSpace = !mono && semantic.last?.isWhitespace == true && !text.isEmpty
        if !mono, styled != nil, let attributed, let bodySize = dropCapBodySize(in: attributed),
           bounds.height >= bodySize * 2, bounds.width >= bodySize * 8 {
            result.fontSize = bodySize
            result.readingRect = CGRect(x: bounds.minX, y: bounds.maxY - bodySize,
                width: bounds.width, height: bodySize)
        } else if !mono, styled != nil, let attributed, let titleSize = displayNumeralTitleSize(in: attributed) {
            // The line's typography is the title's; the numeral is its ornament (#55).
            result.fontSize = titleSize
        } else if !mono, styled != nil, let attributed, let itemSize = bulletItemBodySize(in: attributed) {
            // The line's typography is the item's; the bullet is its ornament (#180).
            result.fontSize = itemSize
        }
        return result
    }

    /// A list item measured from the bullet glyph that opens it rather than from its own text
    /// (#180). PDFKit reports one size a line, taken from its first run, and a source is free to
    /// draw the bullet from a smaller font than the item: TeX's `\labelitemi` is a 6.97-point
    /// glyph before 9.96-point text, so the IEEEtran paper's `• Controllability: …` reports 6.97
    /// and every size test the item's own type would pass — `continuesListItem`'s above all — sees
    /// a line a third smaller than the lines that wrap under it.
    ///
    /// The evidence is a first run of nothing but bullets and whitespace (the marker; the same
    /// reading `isBulletRun` takes for scripts) before a larger, non-blank run, with substantial
    /// text after the marker: three words of two or more letters, and fifteen letters in all, so
    /// that a short label opening a list (`• Units of measurement:`) is an item while the pair of
    /// scan marks a scanned book's text layer reads as `✓ 5 1/J.tJ RtJ.tJ` is not. The
    /// size is the first text run's, not the whole line's, because an item's text carries scripts
    /// as any other prose line does. A bullet drawn *larger* than its text is left alone: it
    /// overstates the line rather than hiding it, which is a different defect.
    static func bulletItemBodySize(in attributed: NSAttributedString) -> CGFloat? {
        guard attributed.length > 0 else { return nil }
        var markerRange = NSRange()
        let marker = attributed.attributes(at: 0, effectiveRange: &markerRange)
        let glyphs = (attributed.string as NSString).substring(with: markerRange)
        guard glyphs.contains(where: bulletCharacters.contains),
              glyphs.allSatisfy({ $0.isWhitespace || bulletCharacters.contains($0) }),
              markerRange.length < attributed.length,
              let cap = marker[.font] as? PlatformFont, cap.pointSize.isFinite, cap.pointSize > 0 else { return nil }
        let rest = NSRange(location: markerRange.length, length: attributed.length - markerRange.length)
        let itemText = (attributed.string as NSString).substring(with: rest)
        guard itemText.filter(\.isLetter).count >= 15,
              itemText.split(whereSeparator: \.isWhitespace).filter({ $0.filter(\.isLetter).count >= 2 }).count >= 3,
              !itemText.contains("\n"), !itemText.contains("\r") else { return nil }
        var size: CGFloat?
        attributed.enumerateAttributes(in: rest) { attributes, range, stop in
            guard size == nil else { stop.pointee = true; return }
            let text = (attributed.string as NSString).substring(with: range)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            guard let font = attributes[.font] as? PlatformFont, font.pointSize.isFinite,
                  font.pointSize > 0, font.pointSize <= 100_000 else { stop.pointee = true; return }
            size = font.pointSize
            stop.pointee = true
        }
        guard let body = size, body > cap.pointSize + 0.05,
              !cap.fontName.lowercased().contains("courier"),
              !cap.fontName.lowercased().contains("mono") else { return nil }
        return body
    }

    /// A chapter opener's display numeral fused by PDFKit with the title beside it (The Fed
    /// Explained's 70-point `1` before the 24-point `Overview of the Federal`): a run of one to
    /// three digits at least twice the size of the title run that follows on the line. The
    /// title's size is the line's size for heading evidence; the numeral's own size would rank
    /// the line above its second line and above every other title (#55).
    static func displayNumeralTitleSize(in attributed: NSAttributedString) -> CGFloat? {
        guard attributed.length > 0 else { return nil }
        var initialRange = NSRange()
        let initial = attributed.attributes(at: 0, effectiveRange: &initialRange)
        let numeral = (attributed.string as NSString).substring(with: initialRange)
            .trimmingCharacters(in: .whitespaces)
        guard (1...3).contains(numeral.count), numeral.allSatisfy(\.isNumber),
              initialRange.length < attributed.length, let cap = initial[.font] as? PlatformFont else { return nil }
        let rest = NSRange(location: initialRange.length, length: attributed.length - initialRange.length)
        let title = (attributed.string as NSString).substring(with: rest)
        guard title.filter(\.isLetter).count >= 2, !title.contains("\n"), !title.contains("\r"),
              let font = attributed.attributes(at: rest.location, effectiveRange: nil)[.font] as? PlatformFont else { return nil }
        let size = font.pointSize
        guard size.isFinite, size > 0, cap.pointSize.isFinite, cap.pointSize <= 100_000,
              cap.pointSize >= size * 2 else { return nil }
        var consistent = true
        attributed.enumerateAttributes(in: rest) { attributes, _, _ in
            guard let font = attributes[.font] as? PlatformFont, font.pointSize.isFinite,
                  abs(font.pointSize - size) <= size * 0.1 else { consistent = false; return }
        }
        return consistent ? size : nil
    }

    /// A lowered, oversized single initial followed by a substantial normal-baseline body run.
    /// This is typography evidence, not a claim that the PDF has logical structure tags.
    private static func dropCapBodySize(in attributed: NSAttributedString) -> CGFloat? {
        guard attributed.length > 0 else { return nil }
        var initialRange = NSRange()
        let initial = attributed.attributes(at: 0, effectiveRange: &initialRange)
        let first = (attributed.string as NSString).substring(with: initialRange)
            .trimmingCharacters(in: .whitespaces)
        guard first.count == 1, first.first?.isUppercase == true,
              initialRange.length < attributed.length,
              let cap = initial[.font] as? PlatformFont,
              !cap.fontName.lowercased().contains("courier"),
              !cap.fontName.lowercased().contains("mono") else { return nil }
        let rest = NSRange(location: initialRange.length, length: attributed.length - initialRange.length)
        let bodyText = (attributed.string as NSString).substring(with: rest)
        guard bodyText.first?.isLowercase == true, bodyText.filter(\.isLetter).count >= 20,
              !bodyText.contains("\n"), !bodyText.contains("\r") else { return nil }
        let body = attributed.attributes(at: rest.location, effectiveRange: nil)
        guard let font = body[.font] as? PlatformFont else { return nil }
        let size = font.pointSize
        let offset = baselineOffset(initial)
        guard size.isFinite, size > 0, cap.pointSize.isFinite, cap.pointSize <= 100_000,
              cap.pointSize >= size * 2, cap.pointSize <= size * 8,
              offset.isFinite, offset <= -size, offset >= -cap.pointSize else { return nil }
        var consistent = true
        attributed.enumerateAttributes(in: rest) { attributes, _, _ in
            guard let font = attributes[.font] as? PlatformFont,
                  font.pointSize.isFinite, abs(font.pointSize - size) <= size * 0.1,
                  baselineOffset(attributes).isFinite,
                  abs(baselineOffset(attributes)) < size * 0.12 else {
                consistent = false; return
            }
        }
        return consistent ? size : nil
    }

    private static func baselineOffset(_ attributes: [NSAttributedString.Key: Any]) -> Double {
        (attributes[NSAttributedString.Key(kCTBaselineOffsetAttributeName as String)] as? NSNumber
            ?? attributes[.baselineOffset] as? NSNumber)?.doubleValue ?? 0
    }

    private struct StyledRun {
        var text: String
        var style: TextStyle
        var offset: Double
        var size: Double
        var hasFont: Bool
        var first: Bool
        /// Drawn in a bold font resource PDFKit does not name bold (#125).
        var resourceBold = false
        /// Drawn in an italic text font resource PDFKit does not name italic (#133).
        var resourceItalic = false
        /// The run's pieces with their maths italic flag (#142). A maths italic resource marks
        /// part of what PDFKit reports as one run (Wallace's `8x`: `8` in CMR, `x` in CMMI), and
        /// `enumerateAttributes` splits a run wherever any attribute changes. A split run would
        /// measure differently — every baseline and script rule reads a run's neighbours — so the
        /// pieces are joined back into the run PDFKit reported, measured as one, and written apart
        /// only at the end. `text` is their concatenation.
        var parts: [(text: String, mathItalic: Bool)] = []
        /// Drawn, in whole or in part, in a maths italic font resource.
        var resourceMathItalic: Bool { parts.contains { $0.mathItalic } }
    }

    static func inlineText(from attributed: NSAttributedString) -> InlineText {
        let hasDropCap = dropCapBodySize(in: attributed) != nil
        var styled: [StyledRun] = []
        // The previous attributed run's attributes without the maths italic mark.
        var attributesWithoutSlope: NSDictionary?
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, range, _ in
            let font = attributes[.font] as? PlatformFont
            let name = font?.fontName.lowercased() ?? ""
            let run = (attributed.string as NSString).substring(with: range)
                .replacingOccurrences(of: "\u{FFFC}", with: " ")
            var style: TextStyle = []
            if name.contains("italic") || name.contains("oblique") { style.insert(.italic) }
            if name.contains("bold") { style.insert(.bold) }
            // PDFKit supplies Core Text baseline offsets even when font size/name do not
            // change. Preserve that evidence instead of guessing from character offsets.
            let offset = (attributes[NSAttributedString.Key(kCTBaselineOffsetAttributeName as String)] as? NSNumber
                ?? attributes[.baselineOffset] as? NSNumber)?.doubleValue ?? 0
            let mathItalic = attributes[FontWeightReader.mathItalicAttribute] != nil
            var piece = StyledRun(text: run, style: style, offset: offset, size: Double(font?.pointSize ?? 12),
                                  hasFont: font != nil, first: range.location == 0,
                                  resourceBold: attributes[FontWeightReader.boldAttribute] != nil,
                                  resourceItalic: attributes[FontWeightReader.italicAttribute] != nil)
            piece.parts = [(text: run, mathItalic: mathItalic)]
            // Rejoin a run the maths italic mark alone split, so the line measures as PDFKit read
            // it. `enumerateAttributes` returns maximal ranges, so two neighbours whose attributes
            // are equal but for that mark are one run of PDFKit's.
            var rest = attributes
            rest[FontWeightReader.mathItalicAttribute] = nil
            if var previous = styled.last, let last = attributesWithoutSlope, last.isEqual(to: rest) {
                previous.text += run
                previous.parts += piece.parts
                styled[styled.count - 1] = previous
            } else {
                styled.append(piece)
            }
            attributesWithoutSlope = rest as NSDictionary
        }
        remeasureQuotedMarker(&styled)
        let baselines = shiftedBaselines(styled)
        var runs: [InlineText.Element] = []
        for (index, run) in styled.enumerated() {
            var style = run.style
            let measured = run.hasFont && run.size.isFinite && run.size > 0 && run.offset.isFinite
            let previous = index > 0 ? styled[index - 1] : nil
            let next = index + 1 < styled.count ? styled[index + 1] : nil
            // A run at least twice the size of every run beside it is display type (a chapter
            // opener's numeral, a drop cap), never a script of the smaller text (#55).
            let neighbours = [previous, next].compactMap { $0 }.filter(\.hasFont).map(\.size)
            let display = measured && !neighbours.isEmpty && neighbours.allSatisfy { run.size >= $0 * 2 }
            if let previous, measured, previous.hasFont, previous.size.isFinite, previous.size > 0, previous.offset.isFinite,
               let last = previous.text.last, let first = run.text.first,
               !last.isWhitespace, !first.isWhitespace, last != "-", last != "\u{00ad}" {
                // PDFKit can concatenate separate visual lines without a space while retaining
                // their full-line baseline offsets. Require matching font sizes and a jump beyond
                // the inline-script range; opposite superscripts/subscripts alone are not evidence.
                let lines = abs(run.size - previous.size) <= max(0.5, max(run.size, previous.size) * 0.1)
                    && abs(run.offset - previous.offset) > max(run.size, previous.size) * 0.75
                    && (abs(run.offset) > run.size * 0.75 || abs(previous.offset) > previous.size * 0.75)
                // A display numeral set on its own baseline before a title (`1` then `Overview`)
                // is a separate word; a raised or lowered script marker beside its base is not.
                let numeral = previous.text.allSatisfy(\.isNumber) && previous.size >= run.size * 2
                    && abs(previous.offset - run.offset) > run.size * 0.75 && first.isLetter
                if lines || numeral { runs.append(.text(" ", [])) }
            }
            let tolerance = max(0.5, run.size * 0.12)
            // Some PDFKit selections combine several OCR lines, represented as baseline
            // shifts of a full line height. Those are layout offsets, not inline scripts.
            // A run is measured from the baseline of the base it is set beside, where that base is itself
            // shifted in the selection (#144); a base on a shifted baseline is no script.
            let offset = run.offset - (baselines.reference[index] ?? 0)
            if !(hasDropCap && run.first), !display, !baselines.base[index], !isBulletRun(index, in: styled),
               !isSeparatorBullet(index, in: styled),
               hasScriptBase(run, index: index, in: styled), offset.isFinite, abs(offset) <= run.size * 0.75 {
                if offset > tolerance { style.insert(.superscript) }
                else if offset < -tolerance { style.insert(.subscript) }
            }
            // PDFKit names a font only when the system has one by that name; the page's own font
            // resources state the weight and slope of the rest (#125, #133). A display initial or
            // numeral (Our Flag's drop caps in a bold, italic-flagged script face) is ornament, not
            // emphasis; a display-size title beside a small marker keeps its style.
            let ornament = display && run.text.filter(\.isLetter).count <= 1
            // A list marker without a letter or digit opening the line in a style the text after it
            // does not share (DGA's bold `+` bullets) marks the item, not an emphasis.
            let opening = styled[..<index].allSatisfy { $0.text.allSatisfy(\.isWhitespace) }
            let following = styled[(index + 1)...].first { !$0.text.allSatisfy(\.isWhitespace) }
            let marker = opening && !run.text.contains { $0.isLetter || $0.isNumber } && following != nil
            if run.resourceBold, !ornament, !(marker && following?.resourceBold == false) { style.insert(.bold) }
            if run.resourceItalic, !ornament, !(marker && following?.resourceItalic == false) { style.insert(.italic) }
            // Maths italic is a variable's slope, so it is neither ornament nor a list marker's
            // emphasis; it follows the same exemptions as the emphasis styles beside it (#142).
            // Only now, with the run measured whole, are its pieces written apart.
            let slope = run.resourceMathItalic && !ornament && !(marker && following?.resourceMathItalic == false)
            guard slope else { runs.append(.text(run.text, style)); continue }
            for part in run.parts where !part.text.isEmpty {
                runs.append(.text(part.text, part.mathItalic ? style.union(.mathItalic) : style))
            }
        }
        return InlineText(elements: runs).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Scripts set beside a base that is itself off the selection's baseline (#144). PDFKit measures
    /// every run of a selection from one baseline, so Wallace page 255's denominator `6a²b`, set
    /// 7.8 points below the comment `First identify LCD` beside it, reads `6a` (−7.80) and `b` (−7.80)
    /// as subscripts and its exponent (−4.32) as one too.
    ///
    /// A run followed, with no space between, by a clearly smaller run (at most its size / 1.1) shifted
    /// to the same side of the selection's baseline and against the run is that run's base, and is no
    /// script; the smaller run is measured from the base's offset. A run of the base's size that follows
    /// such a script with no space between, on the base's baseline, resumes the base and is measured from
    /// it. Where the base stands on the selection's baseline (`x²`, `H₂O`, a note marker) the offsets are
    /// the ones the selection states, so nothing changes; the Fed's regulation letter (`F ` beside its
    /// 8-point name, #138) is set apart by a space and the name is on the selection's baseline. A base
    /// that is itself clearly smaller than the run it follows with no space between is a script too: the
    /// DASC paper's nested indices (`STA` with `n` raised and `i` raised again, #163) keep the offsets
    /// the selection states.
    private static func shiftedBaselines(_ runs: [StyledRun]) -> (reference: [Double?], base: [Bool]) {
        var reference = [Double?](repeating: nil, count: runs.count)
        var base = [Bool](repeating: false, count: runs.count)
        func measured(_ run: StyledRun) -> Bool {
            run.hasFont && run.size.isFinite && run.size > 0 && run.offset.isFinite
                && !run.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        func touching(_ left: StyledRun, _ right: StyledRun) -> Bool {
            left.text.last?.isWhitespace == false && right.text.first?.isWhitespace == false
        }
        func shifted(_ run: StyledRun, from offset: Double) -> Bool {
            abs(run.offset - offset) > max(0.5, run.size * 0.12)
        }
        for index in runs.indices.dropLast() {
            let carrier = runs[index], script = runs[index + 1]
            guard measured(carrier), measured(script), touching(carrier, script), script.size <= carrier.size / 1.1,
                  shifted(carrier, from: 0), shifted(script, from: 0), (carrier.offset > 0) == (script.offset > 0),
                  shifted(script, from: carrier.offset),
                  abs(script.offset - carrier.offset) <= carrier.size * 0.75 else { continue }
            if index > 0, case let before = runs[index - 1], measured(before), touching(before, carrier),
               carrier.size <= before.size / 1.1 { continue }
            base[index] = true
            reference[index + 1] = carrier.offset
            if index + 2 < runs.count, case let resumed = runs[index + 2], measured(resumed), touching(script, resumed),
               resumed.size >= carrier.size / 1.1, resumed.size <= carrier.size * 1.1, !shifted(resumed, from: carrier.offset) {
                reference[index + 2] = carrier.offset
            }
        }
        return (reference, base)
    }

    /// Filled list bullets. Open marks (`◦`, `○`, `□`) are left out: Wallace sets its degree signs as a
    /// raised `◦` (`29◦`), and a raised degree sign is a superscript.
    static let bulletCharacters: Set<Character> = ["\u{2022}", "\u{2023}", "\u{2043}", "\u{25AA}", "\u{25CF}", "\u{25A0}",
                                                   "\u{25C6}", "\u{2756}", "\u{2751}", "\u{27A2}", "\u{27A4}", "\u{25BA}",
                                                   "\u{2714}", "\u{2713}"]

    /// A line's opening bullet and the whitespace after it (#144): the run holds bullets and
    /// whitespace only, and so does everything before it, which holds a bullet if the run does not.
    /// A bullet opens an item and is no script, however it is raised: the Supreme Court's Symbol
    /// bullets (pages 86–87) are 7.98-point glyphs raised 1.02 points beside 10.98-point text, just
    /// past the script tolerance, with the space after them raised alike.
    private static func isBulletRun(_ index: Int, in runs: [StyledRun]) -> Bool {
        func bulletsAndSpace(_ text: String) -> Bool { text.allSatisfy { $0.isWhitespace || bulletCharacters.contains($0) } }
        guard bulletsAndSpace(runs[index].text), runs[...index].allSatisfy({ bulletsAndSpace($0.text) }) else { return false }
        return runs[...index].contains { $0.text.contains(where: bulletCharacters.contains) }
    }

    /// A bullet standing apart between two words (#186): the run holds bullets and whitespace only, and
    /// whitespace separates it from the text on either side, or it ends the line. A script is set against
    /// its base; a bullet set a word space from both neighbours separates them, however it is raised
    /// (*Agricultural Research*'s back cover sets `ars.usda.gov/ar ● Follow us`, a 6-point Monotype Sorts
    /// bullet raised one point between 11-point addresses). A bullet touching a word stays measured.
    private static func isSeparatorBullet(_ index: Int, in runs: [StyledRun]) -> Bool {
        let text = runs[index].text
        guard text.contains(where: bulletCharacters.contains),
              text.allSatisfy({ $0.isWhitespace || bulletCharacters.contains($0) }) else { return false }
        let before = runs[..<index].last { !$0.text.isEmpty }?.text.last
        let after = runs[(index + 1)...].first { !$0.text.isEmpty }?.text.first
        return (text.first?.isWhitespace == true || before.map(\.isWhitespace) ?? true)
            && (text.last?.isWhitespace == true || after.map(\.isWhitespace) ?? true)
            && (before != nil || after != nil)
    }

    /// A script is set smaller than, or as large as, the text it is raised or lowered from, so a
    /// shifted run needs another visible run in its selection at least nearly its own size (#138).
    /// The Fed's regulation letters (pages 82/83: a 12-point `F` beside its 8-point name, or `KK`
    /// alone in its selection) sit 2.74 points lower only because PDFKit measures both from a common
    /// baseline; they are cell labels, not subscripts.
    private static func hasScriptBase(_ run: StyledRun, index: Int, in runs: [StyledRun]) -> Bool {
        runs.indices.contains { other in
            other != index && runs[other].hasFont && runs[other].size.isFinite
                && runs[other].size >= run.size / 1.1
                && !runs[other].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// PDFKit can split a row at a closing quote kerned back over the period before it and then
    /// measure the split piece's baseline on the note marker it holds (#11): 9/11 page 362's
    /// `to routine.` and `”12`, where the 10.25-point quote reads 3.44 points below the 5.125-point
    /// `12`, so the marker read as base text and the quote as a subscript. The piece is re-measured
    /// from its full-size text only when it holds nothing else: closing punctuation, uniformly
    /// lowered by 0.2–0.5 of its size, each followed by a one- to three-digit run at 0.4–0.7 of that
    /// size at offset zero, ending the piece or before a space. An exponent after a letter or digit
    /// (`x2`, `32`) is never re-measured.
    private static func remeasureQuotedMarker(_ runs: inout [StyledRun]) {
        let visible = runs.indices.filter { !runs[$0].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard visible.count >= 2, visible.allSatisfy({ runs[$0].hasFont && runs[$0].size.isFinite && runs[$0].offset.isFinite }),
              let base = visible.map({ runs[$0].size }).max(), base > 0 else { return }
        let tolerance = max(0.5, base * 0.12)
        let closing = Set("\u{201D}\u{2019}\"')].,;:")
        let full = visible.filter { abs(runs[$0].size - base) <= base * 0.1 }
        let markers = visible.filter { runs[$0].size <= base * 0.7 }
        guard full.count + markers.count == visible.count, !markers.isEmpty,
              let lowest = full.map({ runs[$0].offset }).min(), let highest = full.map({ runs[$0].offset }).max(),
              highest - lowest <= tolerance, -highest >= base * 0.2, -lowest <= base * 0.5,
              full.allSatisfy({ runs[$0].text.trimmingCharacters(in: .whitespaces).allSatisfy(closing.contains) }) else { return }
        for marker in markers {
            let run = runs[marker]
            let digits = run.text.trimmingCharacters(in: .whitespaces)
            guard (1...3).contains(digits.count), digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber),
                  run.size >= base * 0.4, abs(run.offset) <= tolerance,
                  let position = visible.firstIndex(of: marker), position > 0,
                  full.contains(visible[position - 1]), marker == visible[position - 1] + 1,
                  runs[marker - 1].text.last?.isWhitespace == false else { return }
            if marker + 1 < runs.count, run.text.last?.isWhitespace != true,
               runs[marker + 1].text.first?.isWhitespace != true { return }
        }
        let shift = -(highest + lowest) / 2
        for index in runs.indices { runs[index].offset += shift }
    }
}
