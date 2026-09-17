import re, subprocess, sys
# Removes one guard at a time, runs the #103/#105 tests, and reports which tests fail.
root = '/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a7b53bf84cf30faac'
LR = root + '/Sources/PDFReflowLib/LayoutReconstructor.swift'
FD = root + '/Sources/PDFReflowLib/FurnitureDetector.swift'
mutations = [
    ('heading type', LR, 'return line.fontSize >= bodySize * 1.25 && !isList(line.text)', 'return !isList(line.text)'),
    ('not a list line', LR, 'return line.fontSize >= bodySize * 1.25 && !isList(line.text)', 'return line.fontSize >= bodySize * 1.25'),
    ('trailing: wide band', LR, '.last(where: { $0.width > bodySize * 1.1 })', '.last'),
    ('trailing: rule off', LR, 'let y = trailingHeading(elements, cut: y, bodySize: bodySize) ?? y', 'let y = y'),
    ('row: figure required', LR, 'guard row.contains(where: { $0.line == nil && $0.box == nil }) else { continue }', ''),
    ('row: clean row', LR, 'above.count + row.count + below.count == elements.count', 'true'),
    ('row: content below', LR, 'guard !above.isEmpty, !below.isEmpty,', 'guard !above.isEmpty,'),
    ('row: rule off', LR, 'if let parts = headingRow(elements, bodySize: bodySize) {', 'if false, let parts = headingRow(elements, bodySize: bodySize) {'),
    ('roman: bare folio flag', FD, 'let isFolio = romanFolio != nil\n                ||', 'let isFolio = false\n                ||'),
    ('roman: offset key', FD, 'ledger.groups[edge + "roman-#(offset=\\(offset))", default: []]', 'ledger.groups[edge + "roman-#", default: []]'),
    ('roman: two letters', FD, 'let romanFolio = words.count == 1 ? romanValue(words[0]) : nil', 'let romanFolio = words.count == 1 && words[0].count >= 2 ? romanValue(words[0]) : nil'),
]
only = sys.argv[1:]
for name, path, old, new in mutations:
    if only and name not in only:
        continue
    source = open(path).read()
    assert source.count(old) == 1, name
    open(path, 'w').write(source.replace(old, new))
    try:
        out = subprocess.run(['swift', 'test', '--filter', 'DGABulletsAndContentsFolioTests|ListContinuation|ColumnCut|FurnitureTests'],
                             cwd=root, capture_output=True, text=True).stdout
    finally:
        open(path, 'w').write(source)
    failed = sorted(set(re.findall(r'✘ Test (\w+)\(', out)))
    summary = re.findall(r'Test run with .*', out)
    print(f'{name}: failing {failed or "NONE"} | {summary[-1] if summary else "no summary (build error?)"}', flush=True)
