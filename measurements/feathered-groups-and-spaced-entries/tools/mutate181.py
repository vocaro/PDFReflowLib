import subprocess, sys, os

# Single-guard mutations of the #181 rules; each must fail at least one test in the filtered suites.
W = '/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a752a17bcd29a7f86'
LAYOUT = os.path.join(W, 'Sources/PDFReflowLib/LayoutReconstructor.swift')
READER = os.path.join(W, 'Sources/PDFReflowLib/GraphicsReader.swift')
FILTER = 'FeatheredGroupsAndSpacedEntriesTests|HangingEntryTests|CropsOverRunningTextTests|ParagraphOpeningTests'

MUTATIONS = [
    ('reader: a feathered box is recorded', READER,
     '|| Self.fills(rect, by: ownBounds)', '|| false'),
    ('reader: paints filling half a box are enough', READER,
     'return shared.width * shared.height >= area * 0.9', 'return shared.width * shared.height >= area * 0.5'),
    ('reader: only an exact fill counts', READER,
     'return shared.width * shared.height >= area * 0.9', 'return shared.width * shared.height >= area * 0.999'),
    ('entries: spaced edges unused', LAYOUT,
     'let edge = hangingEntryEdge(of: line, in: entryEdges + spacedEdges),', 'let edge = hangingEntryEdge(of: line, in: entryEdges),'),
    ('entries: no book wrap', LAYOUT,
     'guard let wrap = found.wrap ?? bookWrap else { return nil }', 'guard let wrap = found.wrap else { return nil }'),
    ('entries: one line is a measure', LAYOUT,
     'let wrap = full.count >= 3 ? full.compactMap', 'let wrap = full.count >= 1 ? full.compactMap'),
    ('entries: any added space', LAYOUT,
     'let spaced = wrap + size * 0.2', 'let spaced = wrap + size * 0'),
    ('entries: two lines make a run', LAYOUT,
     'if count >= 3 { return true }', 'if count >= 2 { return true }'),
    ('entries: uneven leading makes a run', LAYOUT,
     'abs(next.gap - (first ?? next.gap)) <= size * 0.1 {', 'abs(next.gap - (first ?? next.gap)) <= size * 10 {'),
    ('entries: a filled line may open a run', LAYOUT,
     'while !found.fills(last), let next = beneath[last]', 'while let next = beneath[last]'),
    ('entries: bold labels are evidence', LAYOUT,
     '''                && !line.text.contains("....") && abs(line.fontSize - body) <= body * 0.1
                && !LabelStyle(line, body: line.fontSize).bold''',
     '''                && !line.text.contains("....") && abs(line.fontSize - body) <= body * 0.1'''),
    ('entries: any size is evidence', LAYOUT,
     '&& !line.text.contains("....") && abs(line.fontSize - body) <= body * 0.1\n',
     '&& !line.text.contains("....")\n'),
    ('entries: an entry opens at the wrap', LAYOUT,
     'if let spacing = edge.spacing, prev.rect.minY - line.rect.maxY < spacing { return false }', ''),
    ('hanging: no continuation into a wide indent', LAYOUT,
     'if opening.line == prev, prev.readingRect == nil, let edge = hangingEntryEdge(of: prev, in: entryEdges),',
     'if false, opening.line == prev, prev.readingRect == nil, let edge = hangingEntryEdge(of: prev, in: entryEdges),'),
    ('hanging: any edge admits a wide indent', LAYOUT,
     'if opening.line == prev, prev.readingRect == nil, let edge = hangingEntryEdge(of: prev, in: entryEdges),',
     'if opening.line == prev, prev.readingRect == nil, let edge = Optional(HangingEdge(x: prev.rect.minX, size: prev.fontSize, pairs: 1)),'),
    ('hanging: an indent past the edge evidence', LAYOUT,
     'line.rect.minX - edge.x <= edge.size * 2.5,\n               let word', 'line.rect.minX - edge.x <= edge.size * 25,\n               let word'),
    ('hanging: a symbol may open the wrapped line', LAYOUT,
     'line.text.first.map({ $0.isLetter || $0.isNumber || $0 == "(" }) == true,', ''),
    ('hanging: arithmetic may wrap', LAYOUT,
     '![prev.text, line.text].contains(where: { $0.rangeOfCharacter(from: Self.arithmetic) != nil }),', ''),
    ('hanging: an entry line broken short wraps', LAYOUT,
     'prev.rect.maxX + wordWidth + edge.size * 0.5 > right { return true }', 'true { return true }'),
    ('hanging: no shared measure is needed', LAYOUT,
     'if full.filter({ $0 >= right - edge.size }).count >= 3,', 'if full.filter({ $0 >= right - edge.size }).count >= 0,'),
]

only = sys.argv[1:]
results = []
for name, path, old, new in MUTATIONS:
    if only and not any(o in name for o in only): continue
    source = open(path).read()
    if source.count(old) != 1:
        results.append((name, f'ANCHOR x{source.count(old)}')); print(name, 'ANCHOR', source.count(old), flush=True); continue
    open(path, 'w').write(source.replace(old, new))
    try:
        run = subprocess.run(['swift', 'test', '--filter', FILTER], cwd=W, capture_output=True, text=True, timeout=1800)
        out = run.stdout + run.stderr
        failed = sorted({l.split('Test ')[1].split('(')[0] for l in out.splitlines() if l.startswith('✘ Test ') and 'recorded' not in l and 'Test run' not in l})
        build_error = 'error:' in out and 'Test run' not in out
        verdict = 'BUILD ERROR' if build_error else ('killed by ' + ', '.join(failed) if failed else 'SURVIVED')
    finally:
        open(path, 'w').write(source)
    results.append((name, verdict)); print(name, '->', verdict, flush=True)
killed = sum(1 for _, v in results if v.startswith('killed'))
print(f'{killed} of {len(results)} killed')
