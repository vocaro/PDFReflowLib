"""gen-census-reader.py <MarkedTextReader.swift> <CensusReader.swift>: an instrumented copy of the reader
(baseline d63bbbc or the #91 candidate) that records the first page-invalidating operator (callback@line),
each rejected group's reasons, a sample per rejected anchor (bytes, nearest line) and, where the reader
ignores space-only shows, where each ignored show would have been placed."""
import re, sys
from pathlib import Path
src = Path(sys.argv[1]).read_text().split('\n')
out, ctx = [], 'top'
for i, line in enumerate(src, 1):
    m = re.search(r'SetCallback\(table, "(.+?)"\)', line) or re.search(r'SetCallback\(table, op\)', line) or re.search(r'func (\w+)\(', line)
    if m: ctx = (m.group(1) if m.groups() else 'op').replace('\\"', 'quote').replace('"', 'quote')
    if 'invalid = true' in line and 'var invalid' not in line:
        tag = f'{ctx}@L{i}'
        line = line.replace('s.invalid = true', f's.fail("{tag}")').replace('invalid = true', f'fail("{tag}")')
    out.append(line)
s = '\n'.join(out)
candidate = 'blankIdentifiers' in s
def rep(a, b, count=1):
    global s
    assert s.count(a) == count, (a, s.count(a))
    s = s.replace(a, b)
rep('enum MarkedTextReader {', '''enum CensusReader {
    nonisolated(unsafe) static var pageReason: String? = nil
    nonisolated(unsafe) static var groupReasons: [Int: Set<String>] = [:]
    nonisolated(unsafe) static var anchorBytes: [[UInt8]] = []
    nonisolated(unsafe) static var samples: [String] = []
    nonisolated(unsafe) static var blankPoints: [(CGPoint, Int?)] = []
    nonisolated(unsafe) static var blankUnknown = 0
    nonisolated(unsafe) static var blankStats: [String: Int] = [:]''')
rep('        var invalid = false\n', '        var invalid = false\n        func fail(_ why: String) { if !invalid { CensusReader.pageReason = why }; invalid = true }\n')
rep('            if array {\n                var values: CGPDFArrayRef?', '            var values: CGPDFArrayRef?\n            var value: CGPDFStringRef?\n            if array {')
rep('                var value: CGPDFStringRef?\n', '')
grab = '''            var sampleBytes: [UInt8] = []
            func grab(_ string: CGPDFStringRef) { if let p = CGPDFStringGetBytePtr(string) { sampleBytes += UnsafeBufferPointer(start: p, count: CGPDFStringGetLength(string)) } }
            if array, let values { for i in 0..<CGPDFArrayGetCount(values) { var st: CGPDFStringRef?; if CGPDFArrayGetString(values, i, &st), let st { grab(st) } } } else if !array, let value { grab(value) }
'''
if candidate:
    rep('            // Invisible text is inherited', grab + '            // Invisible text is inherited')
    rep('                if let id = marks.last?.id { blankIdentifiers.insert(id) }\n',
        '                if let id = marks.last?.id { blankIdentifiers.insert(id) }\n'
        '                if known { CensusReader.blankPoints.append((CGPoint(x: 0, y: rise).applying(lineMatrix).applying(matrix), marks.last?.id)) } else { CensusReader.blankUnknown += 1 }\n')
else:
    rep('            guard known else { unknownOrigin(); return }', grab + '            guard known else { unknownOrigin(); return }')
rep('anchors.append(Anchor(point: point, id: marks.last?.id))', 'anchors.append(Anchor(point: point, id: marks.last?.id)); CensusReader.anchorBytes.append(sampleBytes)')
rep('guard CGPDFScannerScan(scanner), !s.invalid, s.marks.isEmpty, s.saved.isEmpty, !s.inText else { return false }',
    '''let scanned = CGPDFScannerScan(scanner)
        guard scanned, !s.invalid, s.marks.isEmpty, s.saved.isEmpty, !s.inText else {
            if CensusReader.pageReason == nil { CensusReader.pageReason = !scanned ? "scanFailed" : !s.marks.isEmpty ? "unbalancedMarks" : !s.saved.isEmpty ? "unbalancedQ" : "unclosedBT" }
            return false
        }''')
rep('lines.count * s.anchors.count <= 2_000_000 else { return false }', 'lines.count * s.anchors.count <= 2_000_000 else { CensusReader.pageReason = "limits"; return false }')
rep('var rejected = Set(s.unknownOrigins.compactMap { tags[$0]?.group })',
    '''var rejected = Set(s.unknownOrigins.compactMap { tags[$0]?.group })
        for id in s.unknownOrigins { if let g = tags[id]?.group { CensusReader.groupReasons[g, default: []].insert("unknownOrigin") } }
        if CensusReader.blankUnknown > 0 { CensusReader.blankStats["unknownOrigin"] = CensusReader.blankUnknown }
        for (point, id) in CensusReader.blankPoints {
            let n = lines.indices.filter { lines[$0].rect.insetBy(dx: -0.75, dy: -0.75).contains(point) }.count
            let key = (n == 0 ? "noLine" : n == 1 ? "inLine" : "ambiguous") + (id.flatMap { tags[$0] } != nil ? "Tagged" : id != nil ? "Untracked" : "Unmarked")
            CensusReader.blankStats[key, default: 0] += 1
        }''')
rep('for anchor in s.anchors {', 'for (anchorIndex, anchor) in s.anchors.enumerated() {')
rep('if let tag { rejected.insert(tag.group) }', '''if let tag { rejected.insert(tag.group); CensusReader.groupReasons[tag.group, default: []].insert(candidates.isEmpty ? "noLineAtOrigin" : "ambiguousOrigin")
                    let bytes = CensusReader.anchorBytes[anchorIndex]
                    let ascii = String(bytes.prefix(24).map { (32...126).contains($0) ? Character(UnicodeScalar($0)) : "." })
                    let hex = bytes.prefix(8).map { String(format: "%02x", $0) }.joined()
                    let nearest = lines.min { a, b in
                        hypot(a.rect.midX - anchor.point.x, a.rect.midY - anchor.point.y) < hypot(b.rect.midX - anchor.point.x, b.rect.midY - anchor.point.y) }
                    let near = nearest.map { String(format: "(%.1f,%.1f %.1fx%.1f) %@", $0.rect.minX, $0.rect.minY, $0.rect.width, $0.rect.height, String($0.text.prefix(30))) } ?? "-"
                    CensusReader.samples.append("\\(candidates.isEmpty ? "noLine" : "ambiguous(\\(candidates.count))")\\t\\(String(format: "%.1f,%.1f", anchor.point.x, anchor.point.y))\\tlen\\(bytes.count)\\t\\(hex)\\t\\(ascii)\\tnearest \\(near)")
                }''')
rep('for (id, tag) in tags where !found.contains(id) { rejected.insert(tag.group) }', '''for (id, tag) in tags where !found.contains(id) { rejected.insert(tag.group); CensusReader.groupReasons[tag.group, default: []].insert(
            s.unknownOrigins.contains(id) ? "mcidShownOnlyFromUnknownOrigin" : s.identifiers.contains(id) ? "mcidMarkedWithoutPlaceableText" : "mcidAbsentFromContentStream") }''')
rep('if groups.count != 1 || values.contains(where: { $0 == nil }) { rejected.formUnion(groups) }',
    'if groups.count != 1 || values.contains(where: { $0 == nil }) { rejected.formUnion(groups); for g in groups { CensusReader.groupReasons[g, default: []].insert(groups.count != 1 ? "lineSharedByGroups" : "lineSharedWithUntaggedOrAmbiguousShow") } }')
rep('Self.state(', 'Self.state(', s.count('Self.state('))
Path(sys.argv[2]).write_text(s)
print('ok', 'candidate' if candidate else 'baseline')
