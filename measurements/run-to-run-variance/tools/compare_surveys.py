#!/usr/bin/env python3
"""usage: compare_surveys.py dirA dirB : per case, keys whose hash differs between the two surveys
(each survey's run 0 is used)."""
import sys
from pathlib import Path

a, b = Path(sys.argv[1]), Path(sys.argv[2])
cases = sorted({p.name.rsplit('-', 1)[0] for p in a.glob('*-0.txt')} & {p.name.rsplit('-', 1)[0] for p in b.glob('*-0.txt')})
for case in cases:
    da = dict(l.split('\t', 1) for l in (a / f'{case}-0.txt').read_text().splitlines() if '\t' in l)
    db = dict(l.split('\t', 1) for l in (b / f'{case}-0.txt').read_text().splitlines() if '\t' in l)
    diff = [k for k in sorted(set(da) | set(db)) if da.get(k) != db.get(k)]
    print(case, 'identical' if not diff else f'{len(diff)} differ: {diff[:10]}')
