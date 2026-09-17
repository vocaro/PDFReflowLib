p = '/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad/me/base7c4/Sources/PDFReflowLib/LayoutReconstructor.swift'
s = open(p).read()
for old, new in [('let last = taggedLast, wraps(last, onto: line) {', 'let last = taggedLast, wraps(last, onto: line), false {'),
                 ('if unsafe.contains(where: { groups[$0].map { wraps($0.last!, lines.first!) } ?? false }) {',
                  'if false, unsafe.contains(where: { groups[$0].map { wraps($0.last!, lines.first!) } ?? false }) {')]:
    assert s.count(old) == 1
    s = s.replace(old, new)
open(p, 'w').write(s)
print('mutated')
