#!/usr/bin/env python3
"""usage: mutate.py <log-dir>  negative controls for #124: disable one rule at a time, run the table tests, restore.

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
    'section-rows-data-cells': (S + 'ShadedTableDetector.swift',
        'span: columns.count, header: true)], header: false))',
        'span: columns.count, header: false)], header: false))'),
    'no-label-column-groups': (S + 'ShadedTableDetector.swift',
        'guard !groups.isEmpty else { return rowHeaders(rows, columns: nil) }',
        'guard !groups.isEmpty, false else { return rowHeaders(rows, columns: nil) }'),
    'one-tbody': (S + 'EPUBTextEncoder.swift',
        'if groups.isEmpty || isSection(item) && !groups[groups.count - 1].isEmpty { groups.append([]) }',
        'if groups.isEmpty { groups.append([]) }'),
    'section-row-scope': (S + 'EPUBTextEncoder.swift',
        'attribute += isSection(row) ? " scope=\\"rowgroup\\"" : " scope=\\"row\\""',
        'attribute += " scope=\\"row\\""'),
}
FILTER = 'TableLeftoversTests|TableHeadersAndBorderlessTests|TableCaptionTests|RuledTablesAndHeaderRulesTests|TintedBoxTests'
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
