#!/usr/bin/env python3
"""usage: fine.py <joined.tsv> <leftRegex> <rightRegex> <lo> <hi> <step>
Histogram of min(adjustment, adjustment + Tc) in em (`adj` and `kern0`) for matching glyph pairs at a fine step."""
import re
import sys
from collections import Counter

path, left, right = sys.argv[1], re.compile(sys.argv[2]), re.compile(sys.argv[3])
lo, hi, step = float(sys.argv[4]), float(sys.argv[5]), float(sys.argv[6])
bins = Counter()
for row in open(path, encoding="utf-8"):
    f = row.rstrip("\n").split("\t")
    if f[2] not in ("adj", "kern0") or not left.fullmatch(f[3]) or not right.fullmatch(f[4]):
        continue
    value = min(float(f[9] or 0), float(f[9] or 0) + float(f[7] or 0))
    if lo <= value < hi:
        bins[round(value / step)] += 1
for b in sorted(bins):
    print(f"{b * step:+.3f}\t{bins[b]}")
