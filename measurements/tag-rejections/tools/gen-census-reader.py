"""gen_census.py: derive census/CensusReader.swift from the worktree's MarkedTextReader.swift, recording
the first page-invalidating operator (callback@line) and each rejected group's reasons."""
import re
from pathlib import Path
here = Path(__file__).resolve().parent
src = Path('/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a90893956cdc3fa18/Sources/PDFReflowLib/MarkedTextReader.swift').read_text().split('\n')
out, ctx = [], 'top'
for i, line in enumerate(src, 1):
    m = re.search(r'SetCallback\(table, "(.+?)"\)', line) or re.search(r'SetCallback\(table, op\)', line) or re.search(r'func (\w+)\(', line)
    if m: ctx = (m.group(1) if m.groups() else 'op').replace('\\"', 'quote').replace('"', 'quote')
    if 'invalid = true' in line and 'var invalid' not in line:
        tag = f'{ctx}@L{i}'
        line = line.replace('s.invalid = true', f's.fail("{tag}")').replace('invalid = true', f'fail("{tag}")')
    out.append(line)
s = '\n'.join(out)
def rep(a, b):
    global s
    assert s.count(a) == 1, a
    s = s.replace(a, b)
rep('enum MarkedTextReader {', 'enum CensusReader {\n    nonisolated(unsafe) static var pageReason: String? = nil\n    nonisolated(unsafe) static var groupReasons: [Int: Set<String>] = [:]')
rep('        var invalid = false\n', '        var invalid = false\n        func fail(_ why: String) { if !invalid { CensusReader.pageReason = why }; invalid = true }\n')
rep('guard CGPDFScannerScan(scanner), !s.invalid, s.marks.isEmpty, s.saved.isEmpty, !s.inText else { return false }',
    '''let scanned = CGPDFScannerScan(scanner)
        guard scanned, !s.invalid, s.marks.isEmpty, s.saved.isEmpty, !s.inText else {
            if CensusReader.pageReason == nil { CensusReader.pageReason = !scanned ? "scanFailed" : !s.marks.isEmpty ? "unbalancedMarks" : !s.saved.isEmpty ? "unbalancedQ" : "unclosedBT" }
            return false
        }''')
rep('lines.count * s.anchors.count <= 2_000_000 else { return false }', 'lines.count * s.anchors.count <= 2_000_000 else { CensusReader.pageReason = "limits"; return false }')
rep('var rejected = Set(s.unknownOrigins.compactMap { tags[$0]?.group })',
    'var rejected = Set(s.unknownOrigins.compactMap { tags[$0]?.group })\n        for id in s.unknownOrigins { if let g = tags[id]?.group { CensusReader.groupReasons[g, default: []].insert("unknownOrigin") } }')
rep('if let tag { rejected.insert(tag.group) }', 'if let tag { rejected.insert(tag.group); CensusReader.groupReasons[tag.group, default: []].insert(candidates.isEmpty ? "noLineAtOrigin" : "ambiguousOrigin") }')
rep('for (id, tag) in tags where !found.contains(id) { rejected.insert(tag.group) }', 'for (id, tag) in tags where !found.contains(id) { rejected.insert(tag.group); CensusReader.groupReasons[tag.group, default: []].insert("mcidNotShownOnPage") }')
rep('if groups.count != 1 || values.contains(where: { $0 == nil }) { rejected.formUnion(groups) }',
    'if groups.count != 1 || values.contains(where: { $0 == nil }) { rejected.formUnion(groups); for g in groups { CensusReader.groupReasons[g, default: []].insert(groups.count != 1 ? "lineSharedByGroups" : "lineSharedWithUntaggedOrAmbiguousShow") } }')
(here / 'CensusReader.swift').write_text(s)
print('ok')
