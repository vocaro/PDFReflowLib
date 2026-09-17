#!/usr/bin/env python3
"""usage: classes.py <fused.tsv> [rows-class]  counts fused.py candidates by the #119 classes, from the
characters at the first split: `note` (digits after sentence punctuation, then a capital: `went.8They`),
`punct` (punctuation or a closing quote before the split), `capital` (a letter before a capital or an
opening quote), `smallcaps` (a letter before a lowercase letter: letter-spaced small caps, `Tue sday`),
`other`. With rows-class, prints that class's rows."""
import re
import sys
from collections import Counter

counts, show = Counter(), sys.argv[2] if len(sys.argv) > 2 else None
for row in list(open(sys.argv[1], encoding="utf-8"))[1:]:
    f = row.rstrip("\n").split("\t")
    pieces = f[3].split(" + ")
    left, right = pieces[0], pieces[1] if len(pieces) > 1 else ""
    a, b = left[-1:], right[:1]
    if re.search(r"[.”’?!]\d{1,4}$", left) and (b.isupper() or b == "“"):
        key = "note"
    elif a in ".,;:?!”’)":
        key = "punct"
    elif a.isalpha() and (b.isupper() or b in "“‘"):
        key = "capital"
    elif a.isalpha() and b.islower():
        key = "smallcaps"
    else:
        key = "other"
    counts[key] += 1
    if show == key:
        print("\t".join(f[:4]))
print(dict(sorted(counts.items())), "total", sum(counts.values()), file=sys.stderr)
