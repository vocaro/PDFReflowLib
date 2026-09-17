#!/usr/bin/env python3
"""usage: histogram.py <bounds.tsv> [kind] [column]  prints a 0.01 em histogram of a shows.py column
(default: gapEm of `adj` boundaries), split by the pair's character classes."""
import sys
from collections import Counter

kind = sys.argv[2] if len(sys.argv) > 2 else "adj"
column = sys.argv[3] if len(sys.argv) > 3 else "gapEm"
names = "page showIndex kind left right font size tcEm twEm adjEm gapEm spaceGlyphEm context".split()
index = names.index(column)


def cls(c):
    if c.isalpha(): return "L"
    if c.isdigit(): return "D"
    return "P"


bins = Counter(); pairs = Counter(); total = 0
for line in open(sys.argv[1], encoding="utf-8"):
    f = line.rstrip("\n").split("\t")
    if len(f) < 13 or f[2] != kind or not f[index]:
        continue
    v = float(f[index]); total += 1
    b = round(v * 100) / 100
    bins[b] += 1
    pairs[(b, cls(f[3][:1] or " ") + cls(f[4][:1] or " "))] += 1
print("boundaries", total)
for b in sorted(bins):
    detail = " ".join(f"{k}={n}" for (x, k), n in sorted(pairs.items()) if x == b)
    print(f"{b:+.2f}\t{bins[b]}\t{'#' * min(80, max(1, bins[b] // 50))}\t{detail}")
