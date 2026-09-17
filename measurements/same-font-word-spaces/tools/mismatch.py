#!/usr/bin/env python3
"""usage: mismatch.py <refusals.tsv>  for `spelling` refusals, the first code unit where the source (shows
joined, `¦` removed) and PDFKit's line disagree under missingSpaces's rule, counted by the pair."""
import sys
from collections import Counter

pairs, examples = Counter(), {}
for row in open(sys.argv[1], encoding="utf-8"):
    f = row.rstrip("\n").split("\t")
    if len(f) < 4 or f[1] != "spelling":
        continue
    native = f[2].replace("\\n", "\n").replace("\\t", "\t")
    source = f[3].replace("¦", "").replace("\\n", "\n").replace("\\t", "\t")
    i = j = 0
    while i < len(source) and j < len(native):
        if source[i] == native[j]:
            i += 1; j += 1
        elif native[j].isspace():
            j += 1
        else:
            break
    if i < len(source) and j < len(native):
        key = f"src U+{ord(source[i]):04X} {source[i]!r} vs native U+{ord(native[j]):04X} {native[j]!r}"
    elif i < len(source):
        key = f"source longer: {source[i:i+12]!r}"
    elif j < len(native):
        key = f"native longer: {native[j:j+12]!r}"
    else:
        key = "matches"
    pairs[key] += 1
    examples.setdefault(key, f"{f[0]}: {native[max(0, j-20):j+20]!r}")
for key, count in pairs.most_common(40):
    print(count, key, "|", examples[key])
