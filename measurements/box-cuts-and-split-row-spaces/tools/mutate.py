#!/usr/bin/env python3
# Negative controls: each mutation restores one pre-#177 behaviour (or removes one guard), runs the
# whole Swift suite, and lists the failing tests. Sources are restored after every run.
import subprocess, re, sys
W = '/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a8f4ce138eaeafac2'
L = f'{W}/Sources/PDFReflowLib/LayoutReconstructor.swift'
N = f'{W}/Sources/PDFReflowLib/NativeSpacingReader.swift'
MUTATIONS = [
    ('no-box-stepping', L, 'for steppingOverBoxes in [false, true] {', 'for steppingOverBoxes in [false] {'),
    ('no-inset', L, 'abs(first.rect.maxX - last.rect.maxX) <= body * 2 else { return false }',
     'abs(first.rect.maxX - last.rect.maxX) <= body * 2, Bool(\"false\")! else { return false }'),
    ('no-past-box', L, 'guard !boxes.isEmpty, !left.text.hasSuffix("-"), blocks[index].page == page.number,',
     'guard Bool(\"false\")!, !boxes.isEmpty, !left.text.hasSuffix("-"), blocks[index].page == page.number,'),
    ('no-word-break-inset', L, '                    || nextLineAroundInset(last, first, page: page, body: body, insets: insets)\n', ''),
    ('no-box-beneath', L, '$0.maxY <= last.rect.minY + 1 && $0.minX < last.rect.maxX && $0.maxX > last.rect.minX', '$0 == $0'),
    ('no-next-page-box', L, '!steppingOverBoxes || !clusters(page.tints, distance: 4)', 'true || !clusters(page.tints, distance: 4)'),
    ('no-row-pieces', N, 'guard allTexts.count == allBounds.count, bounds.height > 0,',
     'guard Bool(\"false\")!, allTexts.count == allBounds.count, bounds.height > 0,'),
    ('no-row-span', N, '(show.end ?? -.infinity) > allBounds[right].minX + height', 'Bool("false")!'),
    ('no-soft-hyphen', N, 'guard let last = shows.max(by: { $0.origin.x < $1.origin.x }), let unicode = last.unicode,',
     'guard Bool(\"false\")!, let last = shows.max(by: { $0.origin.x < $1.origin.x }), let unicode = last.unicode,'),
    ('strict-spells', N, 'if source[i] == extracted[j] || whitespace(source[i]) && whitespace(extracted[j]) { i += 1; j += 1 }',
     'if source[i] == extracted[j] { i += 1; j += 1 }'),
]
only = set(sys.argv[1:])
for name, path, old, new in MUTATIONS:
    if only and name not in only:
        continue
    original = open(path).read()
    assert original.count(old) == 1, name
    open(path, 'w').write(original.replace(old, new))
    try:
        run = subprocess.run(['swift', 'test'], cwd=W, capture_output=True, text=True)
        out = run.stdout + run.stderr
        failed = sorted(set(re.findall(r'✘ Test (\w+)\(\) failed', out)))
        errors = [l for l in out.splitlines() if 'error:' in l][:3]
        print(name, 'FAILED:', failed if failed else 'none', errors if errors and not failed else '', flush=True)
    finally:
        open(path, 'w').write(original)
