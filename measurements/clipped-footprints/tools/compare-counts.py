#!/usr/bin/env python3
"""Whole-book and per-page before/after comparison of reflowed words and images."""
import json
import sys
from pathlib import Path

before = json.loads(Path(sys.argv[1]).read_text())
after = json.loads(Path(sys.argv[2]).read_text())
detail = len(sys.argv) > 3 and sys.argv[3] == '--detail'
only = sys.argv[4] if len(sys.argv) > 4 else None

total_lost = 0
print(f"{'case':<40} {'words':>19} {'images':>13} {'no-text pages':>15}")
for case in sorted(before):
    if only and case != only:
        continue
    b, a = before[case]['pages'], after[case]['pages']
    assert set(b) == set(a), (case, set(b) ^ set(a))
    bw, aw = sum(x[0] for x in b.values()), sum(x[0] for x in a.values())
    bi, ai = sum(x[1] for x in b.values()), sum(x[1] for x in a.values())
    be, ae = sum(1 for x in b.values() if x[0] == 0), sum(1 for x in a.values() if x[0] == 0)
    lost = sorted((int(p) for p in b if a[p][0] < b[p][0]))
    total_lost += len(lost)
    flag = '' if not lost else f'  LOSES WORDS on {len(lost)} pages: {lost[:20]}'
    changed = '' if (bw, bi) == (aw, ai) else ''
    print(f'{case:<40} {bw:8d} -> {aw:8d} {bi:5d} -> {ai:5d} {be:6d} -> {ae:6d}{flag}{changed}')
    if detail:
        for p in sorted(b, key=int):
            if b[p] != a[p]:
                print(f'    page {p:>5}: {b[p][0]:6d},{b[p][1]:3d} -> {a[p][0]:6d},{a[p][1]:3d}')
print('pages losing words:', total_lost)
