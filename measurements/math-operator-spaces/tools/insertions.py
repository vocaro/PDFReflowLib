#!/usr/bin/env python3
"""usage: insertions.py <base-lines.tsv> <cand-lines.tsv> [--rows]

Diffs product lines (`survey-lines` column 3) between a baseline and a candidate, page by page.
A changed line is classified as `spaces only` when the candidate equals the baseline apart from
inserted spaces; each inserted space is reported with the characters on either side. Pages whose
line counts differ are listed separately with both line lists. With `--rows`, one TSV row per
inserted space: page, line, left|right, candidate line.
"""
import collections
import sys


def load(path):
    pages = collections.defaultdict(list)
    for line in open(path, encoding="utf-8"):
        f = line.rstrip("\n").split("\t")
        if len(f) >= 3:
            pages[f[0]].append(f[2])
    return pages


def inserted(base, cand):
    """Offsets in `cand` of spaces that `base` lacks, or None unless cand = base + spaces."""
    i = j = 0
    out = []
    while i < len(base) and j < len(cand):
        if base[i] == cand[j]:
            i += 1; j += 1
        elif cand[j] == " ":
            out.append(j); j += 1
        else:
            return None
    while j < len(cand) and cand[j] == " ":
        out.append(j); j += 1
    return out if i == len(base) and j == len(cand) else None


base, cand = load(sys.argv[1]), load(sys.argv[2])
rows = "--rows" in sys.argv
pairs = collections.Counter()
changed = spaces = other = 0
lines = sum(len(v) for v in cand.values())
recount = []
for page in sorted(set(base) | set(cand), key=int):
    b, c = base.get(page, []), cand.get(page, [])
    if len(b) != len(c):
        recount.append((page, b, c)); continue
    for k, (x, y) in enumerate(zip(b, c)):
        if x == y:
            continue
        changed += 1
        offsets = inserted(x, y)
        if offsets is None:
            other += 1
            if rows:
                print(f"{page}\t{k}\tOTHER\t{x}\t{y}")
            continue
        for o in offsets:
            spaces += 1
            pair = f"{y[o - 1] if o else '^'}|{y[o + 1] if o + 1 < len(y) else '$'}"
            pairs[pair] += 1
            if rows:
                print(f"{page}\t{k}\t{pair}\t{y}")
if not rows:
    print(f"lines {lines}, changed {changed}, spaces-only {changed - other}, other {other}, inserted spaces {spaces}")
    print("pages whose line count changed:", [(p, len(b), len(c)) for p, b, c in recount])
    for p, b, c in recount:
        sb, sc = set(b), set(c)
        print(f"  page {p} base-only: {[x for x in b if x not in sc]}")
        print(f"  page {p} cand-only: {[x for x in c if x not in sb]}")
    print("by pair:", pairs.most_common(30))
