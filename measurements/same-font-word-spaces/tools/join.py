#!/usr/bin/env python3
"""usage: join.py <bounds.tsv> <lines.tsv> [kinds]

For each shows.py boundary (default kinds adj,space,show), finds its context (the non-space
characters on both sides, at least 4 each, trimmed to the show) as a unique substring of one page's
product lines with whitespace removed, and reports whether that line has whitespace at the boundary.
Adds a column `native`: `space`, `none` (dropped) or `unfound`, and the matched line.
"""
import re
import sys
from collections import defaultdict

kinds = set((sys.argv[3] if len(sys.argv) > 3 else "adj,space,show").split(","))
pages = defaultdict(list)
for row in open(sys.argv[2], encoding="utf-8"):
    f = row.rstrip("\n").split("\t")
    if len(f) >= 3:
        pages[int(f[0])].append(f[2].replace("\\n", " "))


def squeeze(text):
    kept, index = [], []
    for k, c in enumerate(text):
        if not c.isspace():
            kept.append(c); index.append(k)
    return "".join(kept), index


cache = {}
for row in open(sys.argv[1], encoding="utf-8"):
    f = row.rstrip("\n").split("\t")
    if len(f) < 13 or f[2] not in kinds:
        continue
    page = int(f[0])
    if page not in cache:
        cache[page] = [(line, *squeeze(line)) for line in pages.get(page, [])]
    left, _, right = f[12].partition("|")
    left = re.sub(r"\s", "", left.split("  ")[-1])
    right = re.sub(r"\s", "", right)
    result, found = "unfound", ""
    if len(left) >= 4 and len(right) >= 4:
        hits = []
        for line, squeezed, index in cache[page]:
            start = squeezed.find(left + right)
            while start >= 0:
                hits.append((line, index, start + len(left)))
                start = squeezed.find(left + right, start + 1)
        if len(hits) == 1:
            line, index, cut = hits[0]
            gap = line[index[cut - 1] + 1:index[cut]]
            result = "space" if gap else "none"
            found = line
    print("\t".join(f[:13] + [result, found]))
