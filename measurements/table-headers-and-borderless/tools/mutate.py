#!/usr/bin/env python3
"""usage: mutate.py <log-dir>  negative controls for #121: disable one rule at a time, run the table tests, restore.

Each mutation replaces one exact source fragment (the script stops if a fragment is missing), runs
`swift test --filter` over the table suites, records the failing tests, and restores the file."""
import re
import subprocess
import sys
from pathlib import Path

W = Path(__file__).resolve().parents[3]
LOGS = Path(sys.argv[1])
LOGS.mkdir(parents=True, exist_ok=True)
S = 'Sources/PDFReflowLib/'
MUTATIONS = {
    'no-column-band-header': (S + 'ShadedTableDetector.swift',
        'let columnBandHeader = spansTable && !ownBand(first) && ownColumnBands(first)',
        'let columnBandHeader = spansTable && !ownBand(first) && ownColumnBands(first) && false'),
    'no-row-headers': (S + 'ShadedTableDetector.swift', 'result = rowHeaders(result)', '_ = rowHeaders(result)'),
    'no-borderless-split': (S + 'NativeTextReader.swift', 'if let ink = borderlessTableInk {',
                            'if let ink = borderlessTableInk, ink.isEmpty && !ink.isEmpty {'),
    'no-borderless-gutter': (S + 'NativeTextReader.swift', 'guard bottom >= anchor, gutter >= em,', 'guard bottom >= anchor,'),
    'no-borderless-detector': (S + 'LayoutReconstructor.swift',
        'let tables = shaded + BorderlessTableDetector.tables(in: lines.filter { !shadedLines.contains($0) })',
        'let tables = shaded'),
}
FILTER = 'TableHeadersAndBorderlessTests|TableCaptionTests|RuledTablesAndHeaderRulesTests|TintedBoxTests'
for name, (path, old, new) in MUTATIONS.items():
    file = W / path
    original = file.read_text()
    assert original.count(old) == 1, (name, old)
    try:
        file.write_text(original.replace(old, new))
        run = subprocess.run(['swift', 'test', '--filter', FILTER], cwd=W, capture_output=True, text=True)
    finally:
        file.write_text(original)
    output = run.stdout + run.stderr
    (LOGS / f'{name}.log').write_text(output)
    failed = sorted(set(re.findall(r'✘ Test (\w+)\(.*?\) (?:failed|recorded)', output)))
    summary = re.findall(r'✘? ?Test run with .*', output) or re.findall(r'error: .*', output)[:3]
    print(f'{name}: exit {run.returncode}; failing tests {failed}; {summary[-1] if summary else ""}')
