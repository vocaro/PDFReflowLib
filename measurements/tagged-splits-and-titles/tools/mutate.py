import subprocess, sys, re
# Disables one part at a time, runs the #89/#90 tests, restores the source. Run from the worktree root.
LR = 'Sources/PDFReflowLib/LayoutReconstructor.swift'
FD = 'Sources/PDFReflowLib/FurnitureDetector.swift'
M = {
    'untagged-to-tagged join': (LR, 'if tag.headingLevel == 0, !tag.opensWithSplitMarker, !taggedTitles.contains(tag.group), tagged == nil,',
                                'if false, tag.headingLevel == 0, !tag.opensWithSplitMarker, !taggedTitles.contains(tag.group), tagged == nil,'),
    'tagged-to-untagged join': (LR, 'if let current = tagged, current.0.headingLevel == 0, !current.0.opensWithSplitMarker,\n               !taggedTitles.contains(current.0.group),',
                                'if false, let current = tagged, current.0.headingLevel == 0, !current.0.opensWithSplitMarker,\n               !taggedTitles.contains(current.0.group),'),
    'justified-column evidence': (LR, 'return edge.count >= 6 && justified.count * 2 > edge.count', 'return false && justified.isEmpty'),
    'justified majority (any column)': (LR, 'return edge.count >= 6 && justified.count * 2 > edge.count', 'return edge.count >= 6 && !justified.isEmpty'),
    'justified column needs space somewhere': (LR, 'justified.count * 2 > edge.count && spacedAtAll', 'justified.count * 2 > edge.count || spacedAtAll && false'),
    'prose density': (LR, '[upper, lower].allSatisfy({ $0.rect.width <= CGFloat($0.text.count) * size * 0.7 })', 'true'),
    'bold book-style titles': (LR, 'if lines.allSatisfy({ inBookHeadingStyle($0) && wholly($0, .bold) && $0.fontSize >= reflowBody * 0.95 }) {',
                               'if false, lines.allSatisfy({ inBookHeadingStyle($0) && wholly($0, .bold) && $0.fontSize >= reflowBody * 0.95 }) {'),
    'italic titles': (LR, 'return lines.count == 1 && setsItalicTitle(untagged(lines[0])) ? group : nil', 'return nil'),
    'leader in group': (LR, 'guard !lines.contains(where: { $0.text.contains("....") ||', 'guard !lines.contains(where: { $0.text.contains("\\u{0}") ||'),
    'leader beneath': (LR, 'if let beneath, free.contains(where: { other in', 'if let beneath, beneath.text.isEmpty, free.contains(where: { other in'),
    'leader in wrapped entry beneath': (LR, '(other == beneath || other.structure != nil && other.structure?.group == beneath.structure?.group)', '(other == beneath)'),
    'title density': (LR, '|| $0.rect.width > CGFloat($0.text.count) * $0.fontSize * 0.7 }),', '|| false }),'),
    'centred title': (LR, 'guard readsAsTitle(lines), !free.contains(where: { other in', 'guard readsAsTitle(lines), !free.isEmpty || free.contains(where: { other in'),
    'list beneath italic title': (LR, 'abs(below.fontSize - reflowBody) <= reflowBody * 0.1, !isList(below.text),', 'abs(below.fontSize - reflowBody) <= reflowBody * 0.1,'),
    'italic title case': (LR, 'titleCase(line.text) else { return false }', 'true else { return false }'),
    'lettered bare folio group': (FD, '|| Int(folioParts[0]) != nil || isPartLetter(folioParts[0]))', '|| Int(folioParts[0]) != nil)'),
    'lettered folio reading': (FD, 'if parts.count == 2, isPartLetter(parts[0]), let value', 'if false, parts.count == 2, isPartLetter(parts[0]), let value'),
    'lettered folio heading floor': (LR, '"^(?:(?:[0-9]+-|[A-Za-z]-)?[0-9]+|', '"^(?:(?:[0-9]+-)?[0-9]+|'),
}
names = sys.argv[1:] or list(M)
for name in names:
    path, old, new = M[name]
    source = open(path).read()
    assert source.count(old) == 1, name
    open(path, 'w').write(source.replace(old, new))
    try:
        out = subprocess.run(['swift', 'test', '--filter', 'TaggedSplitsAndTitlesTests|TaggedFormAndTitleTests'], capture_output=True, text=True).stdout
    finally:
        open(path, 'w').write(source)
    failed = sorted(set(re.findall(r'✘ Test (\w+)\(\) failed', out)))
    build = 'error:' in out
    print(f'{name}: {"BUILD ERROR" if build else (", ".join(failed) or "NO TEST FAILS")}', flush=True)
