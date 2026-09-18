#!/usr/bin/env python3
"""usage: pagediff.py <base.epub> <cand.epub> [--show N]

Per source page (the content checker's page reader): text that differs, and whether it differs once
all whitespace is removed; the number of images; headings; paragraph and list-item block counts.
Prints counts and every page whose change is more than whitespace, with the first differing text.
"""
import re
import sys

sys.path.insert(0, __file__.rsplit("/", 4)[0] + "/tools")
from check_corpus_content import read_pages  # noqa: E402


def squeeze(text):
    return re.sub(r"\s+", "", text)


base, _ = read_pages(sys.argv[1])
cand, _ = read_pages(sys.argv[2])
show = int(sys.argv[sys.argv.index("--show") + 1]) if "--show" in sys.argv else 0
whitespace, other = [], []
for number in sorted(set(base) | set(cand)):
    a, b = base.get(number, {}), cand.get(number, {})
    notes = []
    if len(a.get("images", [])) != len(b.get("images", [])):
        notes.append(f"images {len(a.get('images', []))}->{len(b.get('images', []))}")
    if a.get("headings") != b.get("headings"):
        notes.append(f"headings {a.get('headings')} -> {b.get('headings')}")
    for key in ("paragraphs", "listItems", "preformattedLines"):
        if len(a.get(key, [])) != len(b.get(key, [])):
            notes.append(f"{key} {len(a.get(key, []))}->{len(b.get(key, []))}")
    if squeeze(a.get("text", "")) != squeeze(b.get("text", "")):
        x, y = squeeze(a.get("text", "")), squeeze(b.get("text", ""))
        k = next((i for i, (p, q) in enumerate(zip(x, y)) if p != q), min(len(x), len(y)))
        notes.append(f"text differs at {k}: base …{x[max(0, k - 40):k + 60]}… cand …{y[max(0, k - 40):k + 60]}…")
    if notes:
        other.append((number, notes))
    elif a.get("text") != b.get("text"):
        whitespace.append(number)
print(f"pages {len(cand)}; whitespace-only text changes {len(whitespace)}; other changes {len(other)}")
for number, notes in other:
    print(f"page {number}:")
    for n in notes:
        print("   ", n[:400])
if show:
    for number in whitespace[:show]:
        print("ws page", number)
