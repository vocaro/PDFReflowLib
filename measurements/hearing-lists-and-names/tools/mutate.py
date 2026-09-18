#!/usr/bin/env python3
"""usage: mutate.py  apply each #161 negative-control mutation to LayoutReconstructor.swift in turn, run
HearingListsAndNamesTests plus the neighbouring hanging-entry, label, transcript and reading-order
suites, and restore the file.

Run from the repository root. Prints the failing tests for each mutation."""
import re, subprocess, sys
from pathlib import Path

SOURCE = Path('Sources/PDFReflowLib/LayoutReconstructor.swift')
FILTER = ('HearingListsAndNamesTests|HangingEntryTests|BoxTitlesAndTwoLineSubheadsTests|FontWeightDetectionTests'
          '|FAAHeadingLeftoversTests|ListContinuationTests|FallbackBlocksAndLigaturesTests')
MUTATIONS = {
    'no entries after a wide entry': ('return (edge.pairs >= 2 || edge.titled) && edge.hangsOnly && !justified',
                                      'return false'),
    'one wrapped entry enough': ('return (edge.pairs >= 2 || edge.titled) && edge.hangsOnly && !justified',
                                 'return (edge.pairs >= 1 || edge.titled) && edge.hangsOnly && !justified'),
    'flush run-ons ignored': ('edge.hangsOnly = !runsOnFlush(edge.x, edge.size)', 'edge.hangsOnly = true'),
    'justified measure ignored': ('&& edge.hangsOnly && !justified', '&& edge.hangsOnly'),
    'no titled edges': ('        if !titles.isEmpty {\n', '        if false {\n'),
    'one title enough': ('guard heads.filter({ sameEdge($0.x, $0.size) }).count >= 2,',
                         'guard heads.filter({ sameEdge($0.x, $0.size) }).count >= 1,'),
    'titled edge beside a measure': ('measures[Int(head.size.rounded())] == nil, !runsOnFlush(head.x, head.size) else { continue }',
                                     '!runsOnFlush(head.x, head.size) else { continue }'),
    'no wide titles': ('prose > 0, line.rect.width <= prose || wideTitle else { continue }',
                       'prose > 0, line.rect.width <= prose else { continue }'),
    'no named entries': ('        if let entries = namedEntries(elements) { return entries }\n', ''),
    'names as wide as descriptions': ('guard widestName <= widestDescription * 0.6 else { return nil }',
                                      'guard widestName <= widestDescription * 2 else { return nil }'),
    'codes as names': ('guard names.allSatisfy({ elements[$0].line!.text.filter(\\.isLetter).count >= 2 }) else { return nil }', ''),
    'stray lines admitted': ('            } else {\n                return nil\n            }\n        }\n        let widestName',
                             '            }\n        }\n        let widestName'),
}
original = SOURCE.read_text()
try:
    for name, (old, new) in MUTATIONS.items():
        assert original.count(old) == 1, name
        SOURCE.write_text(original.replace(old, new))
        run = subprocess.run(['swift', 'test', '--filter', FILTER], capture_output=True, text=True)
        failing = sorted(set(re.findall(r'✘ Test (\w+)\(', run.stdout + run.stderr)))
        if run.returncode != 0 and not failing:
            failing = ['BUILD OR RUN FAILURE']
        print(f'{name}: {", ".join(failing) or "NO FAILURES"}')
        sys.stdout.flush()
finally:
    SOURCE.write_text(original)
