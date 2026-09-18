#!/usr/bin/env python3
"""usage: classes.py <lines.tsv>...

Counts, in `survey-lines` product text, every mathematical operator between two non-space
characters' reach (operands or operators, the space beside it allowed) by how PDFKit's text spaces it:
`after only` (`5+ 3`, the #188 report), `before only` (`9 +4`), `both` (`5 + 3`) and `neither`
(`5+3`). Reports occurrences and the lines holding at least one.
"""
import collections
import os
import sys

OPERATORS = set("+−×÷±∓∗⋅=≠<>≤≥≈≡")

print("| Lines file | Lines | after only | before only | both | neither | lines with an asymmetric operator |")
print("| --- | ---: | ---: | ---: | ---: | ---: | ---: |")
for path in sys.argv[1:]:
    counts, lines, asym, n = collections.Counter(), collections.defaultdict(set), set(), 0
    for line in open(path, encoding="utf-8"):
        f = line.rstrip("\n").split("\t")
        if len(f) < 3:
            continue
        n += 1
        text = f[2]
        for k, ch in enumerate(text):
            if ch not in OPERATORS or k == 0 or k == len(text) - 1:
                continue
            before, after = text[k - 1] == " ", text[k + 1] == " "
            left = text[k - 2] if before and k >= 2 else text[k - 1]
            right = text[k + 2] if after and k + 2 < len(text) else text[k + 1]
            if left == " " or right == " ":
                continue
            kind = "both" if before and after else "before only" if before else "after only" if after else "neither"
            counts[kind] += 1
            lines[kind].add((f[0], f[1]))
            if kind in ("before only", "after only"):
                asym.add((f[0], f[1]))
    name = os.path.relpath(path)
    print(f"| {name} | {n} | " + " | ".join(f"{counts[k]} ({len(lines[k])})" for k in ("after only", "before only", "both", "neither"))
          + f" | {len(asym)} |")
