#!/usr/bin/env python3
"""usage: summarize.py <operators.tsv>...

Summarizes `operators` probe rows per book: operator boundaries by gap band and whether PDFKit
spaced them, split by whether the line's shows spell PDFKit's text (a repair is possible only
there), and the lines the rule would change (a boundary it decides is a space, PDFKit has none,
and the line spells). Also lists the characters beside the boundaries it would change.
"""
import collections
import os
import sys

BANDS = [(-99, 0.05, "< 0.05"), (0.05, 0.15, "0.05–0.15"), (0.15, 0.2, "0.15–0.2"), (0.2, 0.3, "0.2–0.3"),
         (0.3, 1.0, "0.3–1"), (1.0, 99, "> 1")]


def band(gap):
    for lo, hi, name in BANDS:
        if lo <= gap < hi:
            return name
    return "?"


print("| Book | Boundaries | Lines spelled | " + " | ".join(f"{b[2]} em: spaced / not" for b in BANDS)
      + " | Would insert | Lines changed |")
print("| --- | ---: | ---: | " + " | ".join("---:" for _ in BANDS) + " | ---: | ---: |")
pairs = collections.Counter()
for path in sys.argv[1:]:
    rows = [line.rstrip("\n").split("\t") for line in open(path, encoding="utf-8") if line.strip()]
    if not rows:
        continue
    table = collections.defaultdict(lambda: [0, 0])
    lines, spelled, changed, inserts = set(), set(), set(), 0
    for page, index, kind, left, right, gap, spaced, spells, decision, text in rows:
        g = float(gap)
        lines.add((page, index))
        if spells == "1":
            spelled.add((page, index))
        table[band(g)][0 if spaced == "1" else 1] += 1
        if decision == "1" and spaced == "0" and spells == "1":
            inserts += 1
            changed.add((page, index))
            pairs[(os.path.basename(path), f"{left}|{right}")] += 1
    name = os.path.basename(path).rsplit(".", 1)[0]
    print(f"| {name} | {len(rows)} | {len(spelled)} of {len(lines)} | "
          + " | ".join(f"{table[b[2]][0]} / {table[b[2]][1]}" for b in BANDS) + f" | {inserts} | {len(changed)} |")
print()
for (book, pair), count in pairs.most_common(40):
    print(f"{book}\t{pair}\t{count}")
