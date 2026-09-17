#!/usr/bin/env python3
"""usage: pick.py <joined.tsv> <leftRegex> <rightRegex> <lo> <hi> [limit] [kinds]
Rows whose left/right glyphs match and whose min(adjustment, adjustment + Tc) in em lies in [lo, hi) (gapEm for `show`)."""
import re
import sys

path, left, right, lo, hi = sys.argv[1], re.compile(sys.argv[2]), re.compile(sys.argv[3]), float(sys.argv[4]), float(sys.argv[5])
limit = int(sys.argv[6]) if len(sys.argv) > 6 else 12
kinds = (sys.argv[7] if len(sys.argv) > 7 else "adj,kern0").split(",")
shown = 0
for row in open(path, encoding="utf-8"):
    f = row.rstrip("\n").split("\t")
    if f[2] not in kinds or not left.fullmatch(f[3]) or not right.fullmatch(f[4]):
        continue
    value = min(float(f[9] or 0), float(f[9] or 0) + float(f[7] or 0)) if f[2] != "show" else float(f[10])
    if lo <= value < hi:
        print(f"{f[0]}\t{value:+.4f}\ttc={f[7]}\t{f[5]}\t{f[12]}\t{f[13] if len(f) > 13 else ''}")
        shown += 1
        if shown >= limit:
            break
