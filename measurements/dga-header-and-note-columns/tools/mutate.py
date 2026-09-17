"""Single-guard mutations of #141's rules; each must fail at least one test.
usage: mutate.py first last   (indices into MUTANTS, inclusive)"""
import subprocess, sys, time

W = '/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a0ba3a7886d1b0e32'
TD = W + '/Sources/PDFReflowLib/TintDetector.swift'
LR = W + '/Sources/PDFReflowLib/LayoutReconstructor.swift'
MUTANTS = [
    ('edge: reads', TD, 'held.allSatisfy(reads) else { return hull }', 'true else { return hull }'),
    
    ('edge: backdrop filled', TD, 'let filled = paints.filter(\\.filled).map(\\.rect)', 'let filled = paints.map(\\.rect)'),
    ('edge: work limit', TD, 'hulls.count * (images.count + lines.count + filled.count) <= seedClusterWorkLimit else', 'true else'),
    ('edge: every line on a backdrop', TD, 'guard held.allSatisfy({ line in backdrops.contains { $0.contains(CGPoint(x: line.rect.midX, y: line.rect.midY)) } }),', 'guard true,'),
    ('edge: backdrop width', TD, 'union(backdrops).width >= hull.width * 0.9 else', 'true else'),
    ('edge: bottom edge', TD, 'if strip.minY <= hull.minY + 1 {', 'if true {'),
    ('edge: top edge', TD, '} else if strip.maxY >= hull.maxY - 1 {', '} else if true {'),
    ('edge: rest height', TD, 'guard high - low >= hull.height / 3, coverage', 'guard true, coverage'),
    ('edge: image coverage', TD, 'coverage(of: rest, by: art) >= 0.9 else { return hull }', 'true else { return hull }'),
    ('edge: images part of rest', TD, 'return union(art.map { $0.intersection(rest) }.filter { !$0.isNull })', 'return rest'),
    ('notes: small type', LR, 'let line = sorted[end].line, line.fontSize <= bodySize * 0.9 {', 'let line = sorted[end].line, line.fontSize > 0 {'),
    ('notes: three markers', LR, 'guard markers.count >= 3 else { return sorted }', 'guard markers.count >= 2 else { return sorted }'),
    ('notes: line left of every edge', LR, 'guard let column = edges.lastIndex(where: { element.rect.minX >= $0 - bodySize * 0.5 }) else { return sorted }', 'let column = edges.lastIndex(where: { element.rect.minX >= $0 - bodySize * 0.5 }) ?? 0'),
    ('notes: disjoint columns', LR, 'guard zip(extents, extents.dropFirst()).allSatisfy({ $0.maxX < $1.minX }) else { return sorted }', ''),
    ('notes: consecutive numbers', LR, 'guard zip(numbers, numbers.dropFirst()).allSatisfy({ $1 == $0 + 1 }) else { return sorted }', ''),
    ('notes: raised marker', LR, 'guard case let .text(value, style)? = text.elements.first, style.contains(.superscript),', 'guard case let .text(value, style)? = text.elements.first, style.rawValue >= 0,'),
    ('notes: column gap', LR, 'where edges.last.map({ x - $0 > bodySize * 1.5 }) ?? true', 'where true'),
    ('paragraph: note opens paragraph', LR, 'let nextNote = raisedNoteNumber(line) != nil && raisedNoteNumber(paragraph) != nil', 'let nextNote = raisedNoteNumber(line) != nil'),
    ('paragraph: break at note', LR, 'let nextNote = raisedNoteNumber(line) != nil && raisedNoteNumber(paragraph) != nil', 'let nextNote = false'),
    ('ordering: rule applied', LR, 'return noteColumnsInNumberOrder(sortedByRows(elements, bodySize: bodySize), bodySize: bodySize)', 'return sortedByRows(elements, bodySize: bodySize)'),
    ('compose: edge bands applied', TD, 'let graphics = withoutEdgeBands(result.graphics, paints: paints, lines: lines)', 'let graphics = result.graphics'),
]

first, last = int(sys.argv[1]), int(sys.argv[2])
for name, path, old, new in MUTANTS[first:last + 1]:
    original = open(path).read()
    assert original.count(old) == 1, name
    open(path, 'w').write(original.replace(old, new))
    try:
        start = time.time()
        build = subprocess.run(['swift', 'build', '--build-tests'], cwd=W, capture_output=True, text=True)
        if build.returncode != 0:
            print(f'{name}: BUILD FAILED', build.stdout[-600:], flush=True)
            continue
        test = subprocess.run(['swift', 'test', '--skip-build', '--filter', 'EdgeBandsAndNoteColumnsTests|IllustratedPageTests'],
                              cwd=W, capture_output=True, text=True)
        failing = sorted({l.split('Test ')[1].split('(')[0] for l in (test.stdout + test.stderr).splitlines()
                          if l.startswith('✘ Test ') and not l.startswith('✘ Test run')})
        verdict = 'KILLED' if test.returncode != 0 else 'SURVIVED'
        print(f'{name}: {verdict} {failing} ({time.time() - start:.0f}s)', flush=True)
    finally:
        open(path, 'w').write(original)
