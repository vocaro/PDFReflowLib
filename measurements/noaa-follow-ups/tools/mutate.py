import os, subprocess
# Single-guard mutations of #200's rules; each must fail at least one test.
W = '/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a1cbbc24d84b92807'
os.chdir(W)
L = 'Sources/PDFReflowLib/LayoutReconstructor.swift'
mutants = [
    ('verse guard (#147 path)', L, 'guard wraps.short * 3 <= wraps.wrapped else { return false }', ''),
    ('verse guard (hanging path)', L, 'if wraps.wrapped >= 2, wraps.short * 3 <= wraps.wrapped, wraps.full(prev, line) { return true }',
     'if wraps.wrapped >= 2, wraps.full(prev, line) { return true }'),
    ('two wrapped entries, not three sharing a measure', L, 'if wraps.wrapped >= 2, wraps.short', 'if wraps.wrapped >= 3, wraps.short'),
    ('run openings', L, 'if edge.spacing != nil, edge.openings.contains(line.rect) { return true }', ''),
    ('lone widest line fills', L, 'let fills = { (line: Int) in full.count >= 3 && edge[line].rect.maxX >= measure - size }',
     'let fills = { (line: Int) in edge[line].rect.maxX >= measure - size }'),
    ('book spacing pairs', L, 'if spacedPairs.contains(where: { $0.upper == prev.rect && $0.lower == line.rect }) { return true }', ''),
    ('entry size', L, 'guard entrySize else { return false }', ''),
    ('bold caption', L, '|| opensBoldCaption(line, after: prev)\n', '\n'),
    ('bold caption bold label', L, 'style.contains(.bold), isCaption(value', 'isCaption(value'),
    ('subheader column', 'Sources/PDFReflowLib/TableRegionDetector.swift', 'baseline(row) - baseline(next) <= leading else { continue }',
     'true else { continue }'),
    ('backdrop behind a picture', 'Sources/PDFReflowLib/TintDetector.swift', 'if coverage(of: rest, by: others) >= 0.5 { removed.insert(index) }',
     'if false { removed.insert(index) }'),
    ('caption broken at a hyphen', L, '!(block.page == previousPage.number && isCaption(text) && text.last.map({ "-\\u{00AD}".contains($0) }) == true)', 'true'),
    ('backdrop threshold', 'Sources/PDFReflowLib/TintDetector.swift', 'coverage(of: rest, by: others) >= 0.5', 'coverage(of: rest, by: others) >= 0.15'),
]
filt = 'NOAAFollowUps|RuleAdjacentProse|FeatheredGroups|HangingEntry|ParagraphOpening|CropsOverRunningText|PageBackdrop'
for name, path, old, new in mutants:
    src = open(path).read()
    assert src.count(old) == 1, name
    open(path, 'w').write(src.replace(old, new))
    try:
        r = subprocess.run(['swift', 'test', '--filter', filt], capture_output=True, text=True)
        out = r.stdout + r.stderr
        failed = sorted({l.split('Test ')[1].split('(')[0] for l in out.splitlines() if l.startswith('✘ Test ') and 'recorded' in l})
        built = 'error:' not in out
        print(f'{name}: {"KILLED " + ", ".join(failed) if failed else ("SURVIVED" if built else "BUILD ERROR")}', flush=True)
    finally:
        open(path, 'w').write(src)
