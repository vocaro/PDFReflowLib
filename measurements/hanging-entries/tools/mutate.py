#!/usr/bin/env python3
"""usage: mutate.py  apply each #134 negative-control mutation to LayoutReconstructor.swift in turn, run
HangingEntryTests plus the neighbouring label and transcript suites, and restore the file.

Run from the repository root. Prints the failing tests for each mutation."""
import re, subprocess, sys
from pathlib import Path

SOURCE = Path('Sources/PDFReflowLib/LayoutReconstructor.swift')
FILTER = 'HangingEntryTests|BoxTitlesAndTwoLineSubheadsTests|FontWeightDetectionTests|FAAHeadingLeftoversTests'
MUTATIONS = {
    'no entry splits': ('        func opensHangingEntry(_ line: TextLine, after prev: TextLine, first: TextLine?) -> Bool {\n',
                        '        func opensHangingEntry(_ line: TextLine, after prev: TextLine, first: TextLine?) -> Bool {\n            if true { return false }\n'),
    'continuation after any first line': ('if hangs(prev) { return prev != first && (opensOnEdge || hangs(first)) }',
                                           'if hangs(prev) { return true }'),
    'no titles over entries': ('return style.bold ? paragraph || entries', 'return style.bold ? paragraph'),
    'no hanging titles': ('let hanging = hangingEntryEdge(of: line, in: entryEdges) != nil', 'let hanging = false && hangingEntryEdge(of: line, in: entryEdges) != nil'),
    'openings ignored': ('pairs.append((upper.rect.minX, size, !ends))', 'pairs.append((upper.rect.minX, size, true))'),
}
original = SOURCE.read_text()
try:
    for name, (old, new) in MUTATIONS.items():
        assert original.count(old) == 1, name
        SOURCE.write_text(original.replace(old, new))
        run = subprocess.run(['swift', 'test', '--filter', FILTER], capture_output=True, text=True)
        failing = sorted(set(re.findall(r'✘ Test (\w+)\(', run.stdout + run.stderr)))
        print(f'{name}: {", ".join(failing) or "NO FAILURES"}')
        sys.stdout.flush()
finally:
    SOURCE.write_text(original)
