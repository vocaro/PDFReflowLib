#!/usr/bin/env python3
"""usage: groups.py <joined.tsv> [lo] [hi]  histogram of min(adjustment, adjustment + Tc) (0.01 em; adjustment = -number/1000), TJ `adj` and
`kern0` boundaries) per pair group: left class (l lowercase, U uppercase, D digit, P . , ; : ? !,
Q closing ” ’ ), other O), right group (w word start: letter or digit without left overhang; v an
overhanging capital A T V W Y; q opening “ ‘ (; o other). Cells are counts of PDFKit none/space."""
import sys
from collections import Counter, defaultdict

lo = float(sys.argv[2]) if len(sys.argv) > 2 else -0.02
hi = float(sys.argv[3]) if len(sys.argv) > 3 else 0.30


def left(c):
    if c.islower(): return "l"
    if c.isupper(): return "U"
    if c.isdigit(): return "D"
    if c in ".,;:?!": return "P"
    if c in "”’)": return "Q"
    return "O"


def right(c):
    if c in "ATVWY": return "v"
    if c.isalnum(): return "w"
    if c in "“‘(": return "q"
    return "o"


table = defaultdict(Counter)
groups = set()
for row in open(sys.argv[1], encoding="utf-8"):
    f = row.rstrip("\n").split("\t")
    if f[2] not in ("adj", "kern0") or not f[3] or not f[4]:
        continue
    adj = min(float(f[9] or 0), float(f[9] or 0) + float(f[7] or 0))
    if adj < lo or adj > hi:
        continue
    g = left(f[3][0]) + right(f[4][0])
    groups.add(g)
    b = round(adj * 100)
    table[b][(g, f[13])] += 1
order = sorted(groups)
print("adj\t" + "\t".join(order))
for b in sorted(table):
    cells = []
    for g in order:
        n, s = table[b][(g, "none")], table[b][(g, "space")]
        cells.append(f"{n}/{s}" if n or s else ".")
    print(f"{b/100:+.2f}\t" + "\t".join(cells))
