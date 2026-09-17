p = '/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad/issue117/probe/src/LayoutReconstructor.swift'
s = open(p).read()
marks = [
    ('            if let y = headingBand(elements, gutter: x, bodySize: bodySize) {', 'headingBand'),
    ('            if let y = stackedBlocks(elements, gutter: x, bodySize: bodySize) {', 'stackedBlocks'),
    ('            let columns = ordered(elements.filter { $0.rect.maxX < x }, bodySize: bodySize, depth: depth + 1)', 'columns'),
    ('            let width = horizontalBands(elements).first { abs($0.y - y) < 0.01 }?.width ?? .greatestFiniteMagnitude', 'vgap'),
    ('        if let parts = headingRow(elements, bodySize: bodySize) {', 'headingRow?'),
    ('        if let x = bulletColumns(elements, bodySize: bodySize) {', 'bulletColumns?'),
    ('        // A floated box reads after the lines beside it and before the lines below it.', 'SORT'),
]
for anchor, label in marks:
    assert s.count(anchor) == 1, anchor
    s = s.replace(anchor, f'        debugOrder("{label}", elements, depth)\n' + anchor)
s = s.replace('    static func ordered(_ elements: [Element], bodySize: CGFloat, depth: Int = 0) -> [Element] {',
'''    static func debugOrder(_ label: String, _ elements: [Element], _ depth: Int) {
        guard ProcessInfo.processInfo.environment["ORDER_DEBUG"] != nil else { return }
        let texts = elements.prefix(4).map { $0.line.map { String($0.text.prefix(18)) } ?? "IMG" }
        print(String(repeating: "  ", count: depth) + label + " n=\\(elements.count) " + texts.joined(separator: " | "))
    }
    static func ordered(_ elements: [Element], bodySize: CGFloat, depth: Int = 0) -> [Element] {''')
open(p, 'w').write(s)
