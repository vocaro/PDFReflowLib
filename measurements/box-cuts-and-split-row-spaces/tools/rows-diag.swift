import Foundation
import PDFKit
import AppKit
setvbuf(stdout, nil, _IONBF, 0)
func run() {
    let doc = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1]))!
    FileHandle.standardError.write("step 5\n".data(using: .utf8)!)
    let n = Int(CommandLine.arguments[2])!
    FileHandle.standardError.write("step 6\n".data(using: .utf8)!)
    let needle = CommandLine.arguments[3]
    FileHandle.standardError.write("step 7\n".data(using: .utf8)!)
    let page = doc.page(at: n - 1)!, ref = page.pageRef!
    FileHandle.standardError.write("step 8\n".data(using: .utf8)!)
    let selection = page.selection(for: page.bounds(for: .cropBox))!
    FileHandle.standardError.write("step 9\n".data(using: .utf8)!)
    let evidence = NativeSpacingReader.read(ref)
    FileHandle.standardError.write("step 10\n".data(using: .utf8)!)
    print("evidence count", evidence.count)
    FileHandle.standardError.write("step 11\n".data(using: .utf8)!)
    let lines = selection.selectionsByLine()
    FileHandle.standardError.write("step 12\n".data(using: .utf8)!)
    let bounds = lines.map { $0.bounds(for: page) }
    FileHandle.standardError.write("step 13\n".data(using: .utf8)!)
    for (i, line) in lines.enumerated() {
        guard let s = line.string, s.contains(needle) else { continue }
        let b = bounds[i]
        print("LINE \(i) \(b) \(s.debugDescription)")
        for (j, other) in bounds.enumerated() where j != i && other.insetBy(dx: -0.75, dy: -0.75).intersects(b.insetBy(dx: -0.75, dy: -0.75)) {
            print("  overlaps line \(j) \(other) \(lines[j].string?.debugDescription ?? "")")
        }
        let near = evidence.filter { abs($0.origin.y - b.minY) < 20 && $0.origin.x > b.minX - 50 && $0.origin.x < b.maxX + 50 }
        for e in near.sorted(by: { $0.origin.y != $1.origin.y ? $0.origin.y > $1.origin.y : $0.origin.x < $1.origin.x }) {
            let owners = bounds.enumerated().filter { $0.element.insetBy(dx: -0.75, dy: -0.75).contains(e.origin) }.map(\.offset)
            print("   show o=\(e.origin) end=\(e.end.map { "\($0)" } ?? "nil") size=\(e.size) spaced=\(e.spaced) owners=\(owners) ws=\(e.wordSpaces.sorted()) ss=\(e.sentenceSpaces.sorted()) cand=\(e.sentenceCandidates) \((e.unicode ?? "nil").debugDescription)")
        }
        if let a = line.attributedString {
            let r = NativeSpacingReader.apply(evidence, to: a, bounds: b, allBounds: bounds, allTexts: lines.map(\.string))
            print("  applied: \(r.string.debugDescription)")
        }
    }
    
}
run()