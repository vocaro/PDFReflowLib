#!/usr/bin/env python3
"""usage: insertions.py <base-lines.tsv> <cand-lines.tsv> [book]

Compares product lines (survey-lines column 3) and writes one TSV row per inserted space: book, page,
line, class, the two characters around it, the word pair, and the candidate line. A line that changes
in any other way than by inserted spaces is reported as `other`. Classes: `note` (a digit before a
capital or opening quote, the reference's own boundary), `punct` (after . , ; : ? ! or a closing
quote or parenthesis), `capital` (a letter before a capital), `word` (anything else). Prints counts
per class to stderr."""
import sys
from collections import Counter

book = sys.argv[3] if len(sys.argv) > 3 else ""
base = [l.rstrip("\n").split("\t") for l in open(sys.argv[1], encoding="utf-8")]
cand = [l.rstrip("\n").split("\t") for l in open(sys.argv[2], encoding="utf-8")]
counts = Counter()
if len(base) != len(cand):
    print(f"#line counts differ {len(base)} {len(cand)}", file=sys.stderr)


def classify(left, right):
    if left.isdigit() and (right.isupper() or right in "“‘"):
        return "note"
    if left in ".,;:?!”’)":
        return "punct"
    if left.isalpha() and (right.isupper() or right in "“‘"):
        return "capital"
    return "word"


for a, b in zip(base, cand):
    if a[:3] == b[:3]:
        continue
    before, after = a[2], b[2]
    i = j = 0
    spots = []
    while i < len(before) and j < len(after):
        if before[i] == after[j]:
            i += 1; j += 1
        elif after[j] == " ":
            spots.append(j); j += 1
        else:
            break
    if i != len(before) or j != len(after) or not spots:
        counts["other"] += 1
        print(f"{book}\t{a[0]}\t{a[1]}\tother\t\t\t{before}\t{after}")
        continue
    for s in spots:
        left, right = after[s - 1], after[s + 1] if s + 1 < len(after) else ""
        cls = classify(left, right)
        counts[cls] += 1
        start = after.rfind(" ", 0, s - 1) + 1
        end = after.find(" ", s + 1)
        pair = after[start:end if end >= 0 else len(after)]
        print(f"{book}\t{a[0]}\t{a[1]}\t{cls}\t{left}\t{right}\t{pair}\t{after}")
print(dict(counts), "lines changed", sum(1 for a, b in zip(base, cand) if a[:3] != b[:3]), file=sys.stderr)
