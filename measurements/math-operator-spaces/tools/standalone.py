#!/usr/bin/env python3
"""usage: standalone.py <lines.tsv>...

Counts product lines holding a whitespace-separated token made only of mathematical operators (the
reader's `mathOperators`): the lines whose `wordShare` token count depends on whether such a token
counts, and of those the lines where it decides `isWordy` (at least two words of three or more
letters, and words of two or more letters at least 40% of the tokens)."""
import os
import sys

OPERATORS = set("+−×÷±∓∗⋅=≠<>≤≥≈≡")
EDGES = "\"'“”‘’()[]{}.,;:!?"


def share(tokens, minimum):
    return sum(1 for t in tokens if len(t.strip(EDGES)) >= minimum and t.strip(EDGES).isalpha())


def wordy(tokens):
    return share(tokens, 3) >= 2 and share(tokens, 2) * 5 >= len(tokens) * 2


print("| Lines file | Lines | with a standalone operator | isWordy differs when it is not counted |")
print("| --- | ---: | ---: | ---: |")
for path in sys.argv[1:]:
    n = holding = flips = 0
    for line in open(path, encoding="utf-8"):
        f = line.rstrip("\n").split("\t")
        if len(f) < 3:
            continue
        n += 1
        tokens = f[2].split()
        if any(t and all(c in OPERATORS for c in t) for t in tokens):
            holding += 1
            kept = [t for t in tokens if not all(c in OPERATORS for c in t)]
            if wordy(tokens) != wordy(kept):
                flips += 1
    print(f"| {os.path.basename(path)} | {n} | {holding} | {flips} |")
