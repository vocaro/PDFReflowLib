// Prototype survey for #150/#137: blocks of baselines a clear vertical channel divides into
// aligned columns.
//
// usage: grid <pdf> [first last]
// env: CHANNEL (ems, default 0.6), ROWS (default 3), CELL (max column width in ems, default 15),
//      ALIGN (ems, default 0.25), SHOWROWS (default 4), NUMERIC (require a numeric column),
//      MARKERS (reject a column whose cells open with an enumeration marker)
import Foundation
import PDFKit
import AppKit

struct Word { var text: String; var minX: CGFloat; var maxX: CGFloat }
struct Segment { var words: [Word]
    var minX: CGFloat { words[0].minX }
    var maxX: CGFloat { words[words.count - 1].maxX }
    var text: String { words.map(\.text).joined(separator: " ") }
}
struct Row { var y: CGFloat; var em: CGFloat; var segments: [Segment]; var mono: Bool }

let arguments = CommandLine.arguments
guard arguments.count >= 2, let document = PDFDocument(url: URL(fileURLWithPath: arguments[1])) else {
    fatalError("usage: grid <pdf> [first last]")
}
let env = ProcessInfo.processInfo.environment
let channelEm = CGFloat(env["CHANNEL"].flatMap(Double.init) ?? 0.6)
let minimumRows = Int(env["ROWS"] ?? "3")!
let cellEm = CGFloat(env["CELL"].flatMap(Double.init) ?? 15)
let alignEm = CGFloat(env["ALIGN"].flatMap(Double.init) ?? 0.25)
let showRows = Int(env["SHOWROWS"] ?? "4")!
let requireNumeric = env["NUMERIC"] != nil
let rejectMarkers = env["NOMARKERS"] == nil
let requireHeader = env["HEADER"] != nil
let first = arguments.count >= 4 ? Int(arguments[2])! : 1
let last = arguments.count >= 4 ? Int(arguments[3])! : document.pageCount

let numberPattern = try! NSRegularExpression(pattern: #"^[-−–+$(]?[\d][\d.,:/%′'’)]*$"#)
func isNumber(_ text: String) -> Bool {
    numberPattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
}
let markerPattern = try! NSRegularExpression(pattern: #"^(\(?\d{1,3}[).]|\(?[a-zA-Z][).]|[•●○◦▪■□–—-])$"#)
func isMarker(_ text: String) -> Bool {
    markerPattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
}

struct Block { var rows: [[[Word]]]; var columns: [(CGFloat, CGFloat)] }

// The table the rows (each a list of words inside the window) read as, or nil.
func reads(_ rows: [[Word]], em: CGFloat) -> Block? {
    var spans = rows.flatMap { $0.map { ($0.minX, $0.maxX) } }.sorted { $0.0 < $1.0 }
    guard !spans.isEmpty else { return nil }
    var merged: [(CGFloat, CGFloat)] = []
    for span in spans {
        if let lastSpan = merged.last, span.0 <= lastSpan.1 { merged[merged.count - 1].1 = max(lastSpan.1, span.1) }
        else { merged.append(span) }
    }
    spans = merged
    var columns: [(CGFloat, CGFloat)] = []
    var open = spans[0]
    for span in spans.dropFirst() {
        if span.0 - open.1 >= em * channelEm { columns.append(open); open = span }
        else { open.1 = max(open.1, span.1) }
    }
    columns.append(open)
    guard columns.count >= 2, columns.allSatisfy({ $0.1 - $0.0 <= em * cellEm }) else { return nil }
    func column(_ word: Word) -> Int {
        columns.firstIndex { word.minX >= $0.0 - 0.5 && word.maxX <= $0.1 + 0.5 }!
    }
    // A channel is at least twice the widest gap inside a cell.
    var inCell: CGFloat = 0
    for row in rows {
        for (left, right) in zip(row, row.dropFirst()) where column(left) == column(right) {
            inCell = max(inCell, right.minX - left.maxX)
        }
    }
    guard zip(columns, columns.dropFirst()).allSatisfy({ $1.0 - $0.1 >= inCell * 2 }) else { return nil }
    // A baseline with first-column text opens a row; one without continues the open row: it
    // continues at most one cell that already holds text, and may fill cells the row left empty.
    // Every row then fills every column.
    var grid: [[[Word]]] = []
    for row in rows {
        var cells = [[Word]](repeating: [], count: columns.count)
        for word in row { cells[column(word)].append(word) }
        if !cells[0].isEmpty { grid.append(cells) }
        else if !grid.isEmpty {
            let continued = cells.indices.filter { !cells[$0].isEmpty && !grid[grid.count - 1][$0].isEmpty }
            guard continued.count <= 1 else { return nil }
            for index in cells.indices { grid[grid.count - 1][index] += cells[index] }
        } else { return nil }
    }
    guard grid.count >= minimumRows, grid.allSatisfy({ $0.allSatisfy { !$0.isEmpty } }) else { return nil }
    // Every column is flush left or flush right down the rows.
    for index in columns.indices {
        let lefts = rows.compactMap { row in row.filter { column($0) == index }.map(\.minX).min() }
        let rights = rows.compactMap { row in row.filter { column($0) == index }.map(\.maxX).max() }
        let flushLeft = lefts.max()! - lefts.min()! <= em * alignEm
        let flushRight = rights.max()! - rights.min()! <= em * alignEm
        guard flushLeft || flushRight else { return nil }
    }
    if requireNumeric {
        guard columns.indices.contains(where: { index in
            grid.allSatisfy { cells in cells[index].count == 1 && isNumber(cells[index][0].text) }
        }) else { return nil }
    }
    if rejectMarkers {
        guard !columns.indices.contains(where: { index in
            grid.allSatisfy { cells in cells[index].first.map { isMarker($0.text) } ?? false }
        }) else { return nil }
    }
    return Block(rows: grid, columns: columns)
}

var hits = 0
for number in first...last {
    guard let page = document.page(at: number - 1),
          let all = page.selection(for: page.bounds(for: .cropBox)) else { continue }
    var glyphs: [(Character, CGRect)] = []
    for offset in 0..<page.numberOfCharacters {
        guard let selection = page.selection(for: NSRange(location: offset, length: 1)),
              let character = selection.string?.first, !character.isWhitespace else { continue }
        let box = selection.bounds(for: page)
        guard box.width > 0, box.height > 0, glyphs.last?.1 != box else { continue }
        glyphs.append((character, box))
    }
    var rows: [Row] = []
    for line in all.selectionsByLine() {
        guard let string = line.string, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
        let bounds = line.bounds(for: page)
        guard bounds.width > 0, bounds.height > 0 else { continue }
        var em = bounds.height, mono = false
        if let attributed = line.attributedString, attributed.length > 0,
           let font = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont {
            em = font.pointSize
            let name = font.fontName.lowercased()
            mono = name.contains("mono") || name.contains("courier")
        }
        em = max(4, em)
        let inside = glyphs.filter { bounds.insetBy(dx: -0.5, dy: -0.5).contains(CGPoint(x: $0.1.midX, y: $0.1.midY)) }
            .sorted { $0.1.minX < $1.1.minX }
        var words: [Word] = []
        for (character, box) in inside {
            if let lastWord = words.last, box.minX - lastWord.maxX < em * 0.25 {
                words[words.count - 1].text += String(character)
                words[words.count - 1].maxX = max(lastWord.maxX, box.maxX)
            } else { words.append(Word(text: String(character), minX: box.minX, maxX: box.maxX)) }
        }
        guard !words.isEmpty else { continue }
        var segments: [Segment] = []
        for word in words {
            if let lastSegment = segments.last, word.minX - lastSegment.maxX < em * channelEm {
                segments[segments.count - 1].words.append(word)
            } else { segments.append(Segment(words: [word])) }
        }
        if let index = rows.firstIndex(where: { abs($0.y - bounds.minY) <= 1.5 }) {
            rows[index].segments += segments
            rows[index].segments.sort { $0.minX < $1.minX }
            rows[index].mono = rows[index].mono || mono
        } else { rows.append(Row(y: bounds.minY, em: em, segments: segments, mono: mono)) }
    }
    rows.sort { $0.y > $1.y }
    var used: [(y: CGFloat, minX: CGFloat, maxX: CGFloat)] = []
    for (seedIndex, seed) in rows.enumerated() where !seed.mono {
        let em = seed.em
        // Groups of consecutive short segments in the seed row.
        var groups: [[Segment]] = []
        for segment in seed.segments {
            if segment.maxX - segment.minX <= em * cellEm, let lastGroup = groups.last, !lastGroup.isEmpty,
               groups[groups.count - 1].last!.maxX <= segment.minX {
                groups[groups.count - 1].append(segment)
            } else if segment.maxX - segment.minX <= em * cellEm { groups.append([segment]) }
            else { groups.append([]) }
        }
        for group in groups where group.count >= 2 {
            guard !used.contains(where: { abs($0.y - seed.y) <= 1.5 && $0.minX < group.last!.maxX && $0.maxX > group[0].minX }) else { continue }
            var window = (group[0].minX - em * 0.5, group.last!.maxX + em * 0.5)
            var picked: [[Word]] = [group.flatMap(\.words)]
            var best: (Block, CGFloat, (CGFloat, CGFloat))? = nil
            var previousY = seed.y
            for next in rows[(seedIndex + 1)...] {
                if previousY - next.y > em * 1.8 { break }
                let inside = next.segments.filter { $0.maxX > window.0 && $0.minX < window.1 }
                if inside.isEmpty { continue }
                guard !next.mono, abs(next.em - em) <= em * 0.15 else { break }
                picked.append(inside.flatMap(\.words))
                previousY = next.y
                window = (min(window.0, inside[0].minX - em * 0.5), max(window.1, inside.last!.maxX + em * 0.5))
                if let block = reads(picked, em: em) { best = (block, next.y, window) }
            }
            guard let (block, lastY, finalWindow) = best else { continue }
            for row in rows[seedIndex...] where row.y >= lastY - 1.5 {
                used.append((row.y, finalWindow.0, finalWindow.1))
            }
            var headerText = ""
            if requireHeader {
                // The row directly above the seed, inside the window: two or more segments in
                // distinct columns, not all numbers.
                guard seedIndex > 0 else { continue }
                var above: Row? = nil
                for candidate in rows[..<seedIndex].reversed() {
                    if candidate.y - seed.y > em * 1.8 { break }
                    if candidate.segments.contains(where: { $0.maxX > finalWindow.0 && $0.minX < finalWindow.1 }) { above = candidate; break }
                }
                guard let header = above, abs(header.em - em) <= em * 0.3 else { print("  (no header row above page \(number) y \(Int(seed.y)))"); continue }
                let inside = header.segments.filter { $0.maxX > finalWindow.0 && $0.minX < finalWindow.1 }
                guard inside.allSatisfy({ $0.minX >= finalWindow.0 - em && $0.maxX <= finalWindow.1 + em }) else { continue }
                let cols = Set(inside.flatMap { seg in seg.words.compactMap { word in
                    block.columns.indices.max { a, b in
                        min(block.columns[a].1, word.maxX) - max(block.columns[a].0, word.minX) < min(block.columns[b].1, word.maxX) - max(block.columns[b].0, word.minX) }
                } })
                guard cols.count >= 2, !inside.allSatisfy({ $0.words.allSatisfy { isNumber($0.text) } }) else { continue }
                headerText = inside.map(\.text).joined(separator: " | ")
            }
            hits += 1
            let widest = block.columns.map { ($0.1 - $0.0) / em }.max()!
            print("page \(number)\theader [\(headerText)]\trows \(block.rows.count)\tcolumns \(block.columns.count)\tem \(String(format: "%.1f", em))\twidestCellEm \(String(format: "%.1f", widest))\ty \(Int(seed.y))\tx \(Int(block.columns[0].0))")
            for cells in block.rows.prefix(showRows) {
                print("    " + cells.map { $0.map(\.text).joined(separator: " ") }.joined(separator: " | "))
            }
        }
    }
}
print("hits \(hits)")
