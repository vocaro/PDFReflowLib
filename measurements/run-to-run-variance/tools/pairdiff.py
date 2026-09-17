#!/usr/bin/env python3
"""usage: pairdiff.py runA runB : compare two evaluation directories' EPUBs with the repeat check's
normalized comparison (OCR pages exempt)."""
import importlib.util, json, sys
from pathlib import Path

W = Path('/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a1f4f642d57375727')
sys.path.insert(0, str(W / 'tools'))
spec = importlib.util.spec_from_file_location('repeat', W / 'tools/check_reproducibility.py')
repeat = importlib.util.module_from_spec(spec)
spec.loader.exec_module(repeat)

a, b = Path(sys.argv[1]), Path(sys.argv[2])
ea, eb = next(a.glob('*.epub')), next(b.glob('*.epub'))
ra = json.loads((a / 'conversion-report.json').read_text())
rb = json.loads((b / 'conversion-report.json').read_text())
result = repeat.compare_runs(ea, eb, ra, rb)
result.pop('differingEntries', None)
print(json.dumps(result, indent=1)[:4000])
