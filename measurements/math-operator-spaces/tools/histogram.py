#!/usr/bin/env python3
"""usage: histogram.py <gaps.tsv> [label]

Histograms of `gaps.py` boundaries by class, in em:

- operator: one side a binary or relation operator (OPERATORS), the other an operand (a letter, digit,
  mathematical letter, or a bracket that opens or closes toward it);
- text words: two letters, or sentence punctuation then a letter, both in a text font (not a math font);
- math letters: two letters where either glyph is in a math-italic font (CMMI, or a mathematical
  alphanumeric), the juxtaposed variables whose kerns gave #119 its spurious insertions;
- after ligature: a ligature glyph then a letter.
"""
import collections
import sys

OPERATORS = set("+−=<>×÷±∓≤≥≠≈≡⋅∗")
BINS = [-1, 0.02, 0.05, 0.066, 0.1, 0.12, 0.14, 0.15, 0.16, 0.17, 0.18, 0.2, 0.25, 0.3, 0.4, 0.6, 1.0, 99]


def math_letter(c):
    return 0x1D400 <= ord(c) <= 0x1D7FF or 0x2100 <= ord(c) <= 0x214F


def math_font(name):
    n = name.upper()
    return any(k in n for k in ("CMMI", "CMSY", "CMEX", "MATH", "LMMATH", "SYMBOL", "MSBM", "MSAM", "RSFS", "EUFM"))


def operand(c, side):
    return c.isalnum() or math_letter(c) or (c in "([" if side == "right" else c in ")]")


def label(bins, g):
    for lo, hi in zip(bins, bins[1:]):
        if lo <= g < hi:
            return f"[{lo:g},{hi:g})"
    return "?"


def main(path, name):
    classes = collections.defaultdict(collections.Counter)
    for line in open(path, encoding="utf-8"):
        f = line.rstrip("\n").split("\t")
        if len(f) < 12 or f[2] not in ("in", "cross"):
            continue
        left, right, lf, rf, gap = f[3][-1:], f[4][:1], f[5], f[6], float(f[10])
        if not left or not right:
            continue
        if left in OPERATORS and operand(right, "right") or right in OPERATORS and operand(left, "left"):
            classes["operator"][label(BINS, gap)] += 1
        elif left in "ﬀﬁﬂﬃﬄ" and right.isalpha():
            classes["after ligature"][label(BINS, gap)] += 1
        elif (left.isalpha() or math_letter(left)) and (right.isalpha() or math_letter(right)):
            if math_letter(left) or math_letter(right) or "CMMI" in lf.upper() or "CMMI" in rf.upper():
                classes["math letters"][label(BINS, gap)] += 1
            elif not math_font(lf) and not math_font(rf):
                classes["text words"][label(BINS, gap)] += 1
        elif left in ".,;:?!" and right.isalpha() and not math_font(rf):
            classes["text words"][label(BINS, gap)] += 1
    keys = [label(BINS, (lo + hi) / 2 if hi < 99 else 5) for lo, hi in zip(BINS, BINS[1:])]
    print(f"## {name}")
    print("| gap (em) | " + " | ".join(classes) + " |")
    print("| --- | " + " | ".join("---:" for _ in classes) + " |")
    for k in keys:
        print(f"| {k} | " + " | ".join(str(classes[c][k]) for c in classes) + " |")
    print("| total | " + " | ".join(str(sum(classes[c].values())) for c in classes) + " |")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else sys.argv[1])
