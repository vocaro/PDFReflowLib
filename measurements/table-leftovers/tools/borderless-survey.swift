import Foundation
import PDFKit

// Survey of borderless table candidates (#124): runs of baselines whose text PDFKit's glyph
// geometry splits at a gap of at least two ems, sharing a gutter from row to row. A row is every
// PDFKit line on one baseline; its pieces are the runs of glyphs separated by such gaps, whether
// PDFKit returned them as one line (merged) or as several. Prints one record per run of at least
// three split rows whose gutters overlap, with the rows PDFKit merged counted separately.
//
// usage: borderless-survey <pdf> [first-page last-page]

struct Piece { var text: String; var minX: CGFloat; var maxX: CGFloat }
struct Row { var y: CGFloat; var em: CGFloat; var pieces: [Piece]; var merged: Bool; var minX: CGFloat; var maxX: CGFloat }

let arguments = CommandLine.arguments
guard arguments.count >= 2, let document = PDFDocument(url: URL(fileURLWithPath: arguments[1])) else {
    fatalError("usage: borderless-survey <pdf> [first last]")
}
let first = arguments.count >= 4 ? Int(arguments[2])! : 1
let last = arguments.count >= 4 ? Int(arguments[3])! : document.pageCount

for number in first...last {
    guard let page = document.page(at: number - 1),
          let all = page.selection(for: page.bounds(for: .cropBox)) else { continue }
    var rows: [Row] = []
    // Every character as PDFKit selects it alone: its text and bounds come from one selection.
    var pageGlyphs: [(Character, CGRect)] = []
    for offset in 0..<page.numberOfCharacters {
        guard let selection = page.selection(for: NSRange(location: offset, length: 1)),
              let character = selection.string?.first, !character.isWhitespace else { continue }
        let box = selection.bounds(for: page)
        // A synthesized line break selects the glyph before it again.
        guard box.width > 0, box.height > 0, pageGlyphs.last?.1 != box else { continue }
        pageGlyphs.append((character, box))
    }
    for line in all.selectionsByLine() {
        guard let string = line.string, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
        let bounds = line.bounds(for: page)
        guard bounds.width > 0, bounds.height > 0 else { continue }
        var em = bounds.height
        if let attributed = line.attributedString, attributed.length > 0,
           let font = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont { em = font.pointSize }
        em = max(4, em)
        // Glyphs inside this line: characters whose own one-character selection lies on it.
        let glyphs = pageGlyphs.filter { bounds.insetBy(dx: -0.5, dy: -0.5).contains(CGPoint(x: $0.1.midX, y: $0.1.midY)) }
        let sortedGlyphs = glyphs.sorted { $0.1.minX < $1.1.minX }
        var pieces: [Piece] = []
        for (character, box) in sortedGlyphs {
            if let lastPiece = pieces.last, box.minX - lastPiece.maxX < em * 2 {
                let gapWord = box.minX - lastPiece.maxX > em * 0.2 ? " " : ""
                pieces[pieces.count - 1].text += gapWord + String(character)
                pieces[pieces.count - 1].maxX = max(lastPiece.maxX, box.maxX)
            } else {
                pieces.append(Piece(text: String(character), minX: box.minX, maxX: box.maxX))
            }
        }
        guard !pieces.isEmpty else { continue }
        let y = bounds.minY
        if let index = rows.firstIndex(where: { abs($0.y - y) <= 1.5 }) {
            rows[index].pieces += pieces
            rows[index].pieces.sort { $0.minX < $1.minX }
            rows[index].merged = rows[index].merged || pieces.count > 1
            rows[index].minX = min(rows[index].minX, bounds.minX); rows[index].maxX = max(rows[index].maxX, bounds.maxX)
        } else {
            rows.append(Row(y: y, em: em, pieces: pieces, merged: pieces.count > 1, minX: bounds.minX, maxX: bounds.maxX))
        }
    }
    rows.sort { $0.y > $1.y }
    if ProcessInfo.processInfo.environment["SURVEY_DEBUG"] != nil { for r in rows { print("  y \(Int(r.y)) em \(r.em) " + r.pieces.map { "\($0.text)[\(Int($0.minX))-\(Int($0.maxX))]" }.joined(separator: " | ")) } }
    // Gutters of a row: the gaps between its consecutive pieces.
    func gutters(_ row: Row) -> [(CGFloat, CGFloat)] {
        zip(row.pieces, row.pieces.dropFirst()).map { ($0.maxX, $1.minX) }
    }
    func overlaps(_ a: [(CGFloat, CGFloat)], _ b: [(CGFloat, CGFloat)]) -> Bool {
        a.contains { x in b.contains { y in min(x.1, y.1) - max(x.0, y.0) > 0 } }
    }
    var index = 0
    while index < rows.count {
        guard rows[index].pieces.count >= 2 else { index += 1; continue }
        var run = [index]
        var next = index + 1
        // Continue through split rows sharing a gutter with the last split row; single-piece rows
        // (a cell's second line) may sit between them, within three ems.
        while next < rows.count, rows[run.last!].y - rows[next].y <= rows[index].em * 3 {
            if rows[next].pieces.count >= 2 {
                guard overlaps(gutters(rows[run.last!]), gutters(rows[next])) else { break }
                run.append(next)
            } else if let lastSplit = run.last, rows[lastSplit].y - rows[next].y > rows[index].em * 3 { break }
            next += 1
        }
        if run.count >= 3 {
            let merged = run.filter { rows[$0].merged }.count
            let columns = run.map { rows[$0].pieces.count }.max()!
            let widest = run.flatMap { rows[$0].pieces.map { ($0.maxX - $0.minX) / rows[index].em } }.max()!
            print("page \(number)\trows \(run.count)\tmerged \(merged)\tcolumns \(columns)\twidestPieceEm \(Int(widest))\ty \(Int(rows[run[0]].y))")
            for row in run.prefix(4) {
                print("    " + rows[row].pieces.map { $0.text }.joined(separator: " | "))
            }
        }
        index = max(next, index + 1)
    }
}
