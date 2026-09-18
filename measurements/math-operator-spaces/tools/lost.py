#!/usr/bin/env python3
"""usage: lost.py <base.epub> <cand.epub> <page>[,<page>...]

For each page, the text the baseline reflowed that the candidate does not (moved into an image or
dropped), and the text the candidate reflows that the baseline did not (taken out of an image),
compared with all whitespace removed so the respacing itself does not count."""
import difflib
import re
import sys

sys.path.insert(0, __file__.rsplit("/", 4)[0] + "/tools")
from check_corpus_content import read_pages  # noqa: E402

base, _ = read_pages(sys.argv[1])
cand, _ = read_pages(sys.argv[2])
for number in (int(n) for n in sys.argv[3].split(",")):
    x = re.sub(r"\s+", "", base.get(number, {}).get("text", ""))
    y = re.sub(r"\s+", "", cand.get(number, {}).get("text", ""))
    matcher = difflib.SequenceMatcher(None, x, y, autojunk=False)
    lost = [x[i1:i2] for op, i1, i2, j1, j2 in matcher.get_opcodes() if op in ("delete", "replace") and i2 - i1 > 0]
    gained = [y[j1:j2] for op, i1, i2, j1, j2 in matcher.get_opcodes() if op in ("insert", "replace") and j2 - j1 > 0]
    print(f"page {number}: images {len(base.get(number, {}).get('images', []))}->{len(cand.get(number, {}).get('images', []))}")
    print("   lost  :", [s[:120] for s in lost])
    print("   gained:", [s[:120] for s in gained])
