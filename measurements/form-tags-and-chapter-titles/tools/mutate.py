import subprocess, sys, re
W = '/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a85805ea97e861ace'
LR = W + '/Sources/PDFReflowLib/LayoutReconstructor.swift'
MR = W + '/Sources/PDFReflowLib/MarkedTextReader.swift'
MUTATIONS = {
    'all-forms-invalid': (MR, 'if s.textlessForms[identity] != true { s.invalid = true }', 's.invalid = true'),
    'text-shows-ignored': (MR, 'Unmanaged<FormScan>.fromOpaque(info!).takeUnretainedValue().textless = false\n                CGPDFScannerStop(scanner)',
                           'Unmanaged<FormScan>.fromOpaque(info!).takeUnretainedValue().count(scanner)'),
    'nested-forms-not-followed': (MR, '            guard s.textlessForms[identity] == true else { return false }\n', ''),
    'no-book-heading-style': (LR, 'if lines.allSatisfy(inBookHeadingStyle) { return group }', ''),
    'no-titled-group-fallback': (LR, 'let titled = Set(groups.compactMap { group, lines -> Int? in', 'let titled = Set<Int>(); _ = Set(groups.compactMap { group, lines -> Int? in'),
    'no-paragraph-wrap-join': (LR, 'let last = taggedLast, wraps(last, onto: line) {', 'let last = taggedLast, wraps(last, onto: line), false {'),
    'no-spacing-evidence': (LR, '            return spaced.count >= 2\n', '            return spaced.count >= 0\n'),
    'no-unsafe-continuation': (LR, 'if unsafe.contains(where: { groups[$0].map { wraps($0.last!, lines.first!) } ?? false }) {',
                               'if false, unsafe.contains(where: { groups[$0].map { wraps($0.last!, lines.first!) } ?? false }) {'),
    'no-leader-exclusion': (LR, '!upper.text.contains("..."), !lower.text.contains("..."),', ''),
    'no-short-line-guard': (LR, 'guard upper.rect.maxX >= column - body * 0.75, measure.count >= 3 else { return false }', ''),
}
FILTER = 'aFormInvalidates|aChapterTitle|headingEvidenceCounts|aCentredImprint|aParagraphTagOverATitle|twoParagraphTags|paragraphTagsStay|aCaptionContinuation'
names = sys.argv[1:] or list(MUTATIONS)
for name in names:
    path, old, new = MUTATIONS[name]
    original = open(path).read()
    assert original.count(old) == 1, name
    open(path, 'w').write(original.replace(old, new))
    try:
        out = subprocess.run(['swift', 'test', '--filter', FILTER], cwd=W, capture_output=True, text=True).stdout
    finally:
        open(path, 'w').write(original)
    failed = sorted(set(re.findall(r'✘ Test (\w+)\(', out)))
    built = 'error:' not in out
    print(f'{name}: built={built} failing={failed}', flush=True)
