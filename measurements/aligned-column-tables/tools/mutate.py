#!/usr/bin/env python3
"""usage: mutate.py <log-dir>  negative controls for #150: disable one part of the rule at a time, run the
table tests, restore.

Each mutation replaces one exact source fragment (the script stops if a fragment is missing), runs
`swift test --filter` over the table and index-glyph suites, records the failing tests, and restores the file."""
import re
import subprocess
import sys
from pathlib import Path

W = Path(__file__).resolve().parents[3]
LOGS = Path(sys.argv[1])
LOGS.mkdir(parents=True, exist_ok=True)
S = 'Sources/PDFReflowLib/'
G = S + 'ColumnGrid.swift'
MUTATIONS = {
    'no numeric column': (G, 'guard numeric.contains(true), !bands', 'guard true, !bands'),
    'no header': (G, 'return rows.isEmpty ? nil : rows', 'return rows'),
    'numeric columns need no heading': (G, 'guard cells.count >= 2, numeric.allSatisfy({ heading($0) != nil }),',
                                        'guard cells.count >= 2, true,'),
    'a body row may head the body': (G, 'heading(0) == nil || !numeric.allSatisfy({ heading($0)?.allSatisfy { isNumber($0.text) } == true })',
                                     'true'),
    'columns need not be flush': (G, 'guard left || right else { return nil }', 'guard true else { return nil }'),
    'continuation continues any cells': (G, 'guard present.filter({ open[$0] }).count <= 1 else { return nil }',
                                         'guard present.filter({ open[$0] }).count <= 99 else { return nil }'),
    'marker columns allowed': (G, '!bands.indices.contains(where: { band in cells(band).allSatisfy(opensWithMarker) })', 'true'),
    'leaders allowed': (G, 'return text.contains(". . .") || text.contains("....")', 'return false'),
    'no fifteen-em cell': (G, 'guard bands.count >= 2, bands.allSatisfy({ $0.maxX - $0.minX <= em * widestCell }) else { return nil }',
                           'guard bands.count >= 2 else { return nil }'),
    'no number stacks a word space apart': (G, 'if perRow.allSatisfy({ $0.count >= 2 }), lasts.allSatisfy', 'if false, perRow.allSatisfy({ $0.count >= 2 }), lasts.allSatisfy'),
    'no in-cell gap test': (G, 'for gap in wide.indices where wide[gap] && bands[gap + 1].minX - bands[gap].maxX < inCell * 2 { return nil }', ''),
    'headings continue at a quarter em': (G, 'let tight = em * 0.1', 'let tight = em * flush'),
    'no centred header division': (G, 'result += parts.count >= 2 && centred ? parts : [segment]', 'result += [segment]'),
    'layout window takes prose columns': (G, 'func cells(_ band: Int) -> Bool { bands[band].widest <= em * widestCell }',
                                          'func cells(_ band: Int) -> Bool { true }'),
    'grids may continue past their edge': (G, '|| continued.count * 2 < last - start + 1 else { start += 1; continue }',
                                           '|| true else { start += 1; continue }'),
    'page columns count as continuing': (G, 'guard near.contains(where: { $0.rect.minY > top + 1.5 || $0.rect.minY < bottom - 1.5 })',
                                         'guard false'),
    'tagged paragraphs anywhere': (S + 'BorderlessTableDetector.swift',
                                   'guard lines.allSatisfy({ line in line.structure.map { !groups.contains($0.group) } ?? true',
                                   'guard true || lines.allSatisfy({ line in line.structure.map { !groups.contains($0.group) } ?? true'),
    'heading-tagged lines are cells': (S + 'BorderlessTableDetector.swift',
                                       'let usable = lines.filter { ($0.structure?.headingLevel ?? 0) == 0 && !$0.monospaced',
                                       'let usable = lines.filter { !$0.monospaced'),
    'cells re-selected, not sliced': (S + 'NativeTextReader.swift',
                                      'if line.text.split(whereSeparator: \\.isWhitespace).count == measured,',
                                      'if false, line.text.split(whereSeparator: \\.isWhitespace).count == measured,'),
    'no split': (S + 'NativeTextReader.swift',
                 'lines = try splitColumnGrids(lines, on: page, includeStyle: includeStyle, weights: weights,\n                                             privateUse: privateUse)',
                 '_ = 0'),
    'guard ignores read tables': (S + 'PDFReflowLibPipeline.swift',
                                  'guard holdsNumericGrid(lines) else { return false }', 'return holdsNumericGrid(lines)'),
}
FILTER = ('AlignedColumnTablesTests|TableHeadersAndBorderlessTests|TableLeftoversTests|TableCaptionTests'
          '|RuledTablesAndHeaderRulesTests|TintedBoxTests|GlyphIndexDecodingTests')
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
    (LOGS / f'{name.replace(" ", "-")}.log').write_text(output)
    failed = sorted(set(re.findall(r'✘ Test (\w+)\(.*?\) (?:failed|recorded)', output)))
    summary = re.findall(r'✘? ?Test run with .*', output) or re.findall(r'error: .*', output)[:3]
    print(f'{name}: exit {run.returncode}; failing tests {failed}; {summary[-1] if summary else ""}', flush=True)
