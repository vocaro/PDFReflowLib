#!/usr/bin/env python3
"""usage: operators.py <pdf> <first> <last>  pages that use each operator NativeSpacingReader treats as
unmodeled or conditional: nonzero Tc/Tw, Ts/Tr nonzero, Tz not 100, ' and ", BI, Do, and shows
whose text cursor was not repositioned since the previous show."""
import sys
from collections import Counter

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from shows import mutool, tokens  # noqa: E402

pdf, first, last = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
pages = Counter()
for page in range(first, last + 1):
    seen, operands, positioned = set(), [], False
    data = mutool("show", "-b", pdf, f"pages/{page}/Contents")
    depth = 0
    for kind, value in tokens(data):
        if kind == "[":
            depth += 1; continue
        if kind == "]":
            depth -= 1; continue
        if kind != "op":
            if depth == 0: operands.append(value)
            continue
        if depth:
            continue
        op = value
        if op in ("Tc", "Tw", "Ts", "Tr") and operands and operands[-1] != 0: seen.add(f"{op}!=0")
        if op == "Tz" and operands and operands[-1] != 100: seen.add("Tz!=100")
        if op in ("'", '"', "BI", "Do", "gs"): seen.add(op)
        if op in ("Tm", "Td", "TD", "T*", "BT"): positioned = op != "BT"
        if op in ("Tj", "TJ"):
            if not positioned: seen.add("unpositioned")
            positioned = False
        operands = []
    for s in seen:
        pages[s] += 1
    pages["pages"] += 1
for k, v in sorted(pages.items()):
    print(k, v)
