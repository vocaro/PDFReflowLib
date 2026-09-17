#!/usr/bin/env python3
"""usage: notes.py <joined.tsv> [rows]  `show` boundaries from a smaller show (at most 0.8 of the next
show's size) to the next show: a gap histogram (0.01 em of the smaller size) by PDFKit outcome and by
whether the small show ends with a space glyph, then up to `rows` rows without one."""
import sys
from collections import Counter

limit = int(sys.argv[2]) if len(sys.argv) > 2 else 30
bins, rows = Counter(), []
for row in open(sys.argv[1], encoding="utf-8"):
    f = row.rstrip("\n").split("\t")
    if f[2] != "show" or ">" not in f[6]:
        continue
    a, b = (float(x) for x in f[6].split(">"))
    if a > b * 0.8:
        continue
    spaced = f[3] == " "
    gap = float(f[10])
    bins[(round(gap * 100), "space-glyph" if spaced else "no-glyph", f[13])] += 1
    if not spaced:
        rows.append(f"{f[0]}\t{gap:+.4f}\t{f[6]}\t{f[12]}\t{f[13]}")
for key in sorted(bins):
    print(f"{key[0] / 100:+.2f}\t{key[1]}\t{key[2]}\t{bins[key]}")
print("\n".join(rows[:limit]))
