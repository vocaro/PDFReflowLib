#!/usr/bin/env python3
"""usage: risk.py <insertions.tsv>  counts inserted spaces per guard-relevant class and prints each
class's rows to <insertions>-<class>.tsv: `initial` (a single capital and a period before the space,
`W. Bush`, `U.S. Army`), `digits` (a comma between digits, `11, 2001`), `ellipsis` (after `. .`),
`quote` (before an opening quote), `lowercase` (after a lowercase letter), and `other`."""
import re
import sys
from collections import defaultdict

groups = defaultdict(list)
for row in open(sys.argv[1], encoding="utf-8"):
    f = row.rstrip("\n").split("\t")
    if len(f) < 8 or f[3] == "other":
        continue
    left_word, _, right_word = f[6].partition(" ")
    if re.search(r"(^|[^A-Za-z])[A-Z]\.$", left_word):
        key = "initial"
    elif f[4] == "," and left_word[-2:-1].isdigit() and right_word[:1].isdigit():
        key = "digits"
    elif left_word.endswith(".") and (f[7].find(". . .") >= 0 or left_word.endswith("..")):
        key = "ellipsis"
    elif f[5] in "“‘":
        key = "quote"
    elif f[4].islower():
        key = "lowercase"
    else:
        key = "other"
    groups[key].append(row)
base = sys.argv[1].rsplit(".", 1)[0]
for key, rows in sorted(groups.items()):
    print(key, len(rows))
    with open(f"{base}-{key}.tsv", "w", encoding="utf-8") as out:
        out.writelines(rows)
