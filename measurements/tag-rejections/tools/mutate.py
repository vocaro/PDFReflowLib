"""mutate.py <filter> : run each mutation of LayoutReconstructor.swift, run the filtered tests, restore."""
import shutil, subprocess, sys
from pathlib import Path

W = Path('/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a90893956cdc3fa18')
F = W / 'Sources/PDFReflowLib/LayoutReconstructor.swift'
B = Path(__file__).resolve().parent / 'backup/LayoutReconstructor.swift'
MUTATIONS = {
    'no-lineCount-decrement': ('            kept[index].structure?.lineCount -= pieces\n', ''),
    'no-preformatted-emission': ('(tag.opensWithSplitMarker && isList(text.text) ? .preformatted(text) : .paragraph(text))', '.paragraph(text)'),
    'no-min-order': ('                tag.order = min(tag.order, markerTag.order)\n', ''),
    'no-opening-check': (' && opening == listLines[0]', ''),
}
original = F.read_text()
assert original == B.read_text(), 'working file differs from backup'
try:
    for name, (old, new) in MUTATIONS.items():
        assert original.count(old) == 1, name
        F.write_text(original.replace(old, new))
        out = subprocess.run(['swift', 'test', '--filter', sys.argv[1]], cwd=W, capture_output=True, text=True).stdout
        failed = sorted({l.split('Test ')[1].split('(')[0] for l in out.splitlines() if l.startswith('✘ Test ') and 'failed after' in l})
        passed = sum(1 for l in out.splitlines() if l.startswith('✔ Test ') and 'passed after' in l)
        print(f'{name}: failed {failed} passed {passed}')
finally:
    F.write_text(original)
print('restored', F.read_text() == B.read_text())
