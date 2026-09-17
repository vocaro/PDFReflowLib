#!/usr/bin/env python3
"""usage: outcomes.py <joined.tsv> [kind] [step]  per gap bin (em of the left glyph's size): how often
PDFKit's product line has a space (`space`), has none (`none`) or the boundary was not located."""
import sys
from collections import Counter, defaultdict

kind = sys.argv[2] if len(sys.argv) > 2 else "adj"
step = float(sys.argv[3]) if len(sys.argv) > 3 else 0.01
table = defaultdict(Counter)
for row in open(sys.argv[1], encoding="utf-8"):
    f = row.rstrip("\n").split("\t")
    if f[2] != kind:
        continue
    b = round(round(float(f[10]) / step) * step, 3)
    table[b][f[13]] += 1
print("gapEm\tspace\tnone\tunfound")
for b in sorted(table):
    c = table[b]
    print(f"{b:+.2f}\t{c['space']}\t{c['none']}\t{c['unfound']}")
