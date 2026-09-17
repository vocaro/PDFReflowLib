#!/usr/bin/env python3
"""usage: add-contract.py <base-text.tsv> <cand-text.tsv> <case-id> <page> <spaced phrase> <fused phrase> [...]  (repository root)

Adds `text` (the spaced phrase) and `absentText` (the fused phrase) checks to a page of corpus/regressions.json,
only when the candidate EPUB text (epubtext.py dump) contains the spaced phrase and not the fused one, and the
baseline contains the fused phrase and not the spaced one. Arguments after the case id repeat in threes."""
import json
import sys

base = open(sys.argv[1], encoding="utf-8").read()
cand = open(sys.argv[2], encoding="utf-8").read()
case_id, rest = sys.argv[3], sys.argv[4:]
path = "corpus/regressions.json"
data = json.load(open(path, encoding="utf-8"))
cases = data["cases"] if isinstance(data, dict) else data
case = next(c for c in cases if c["id"] == case_id)
for i in range(0, len(rest), 3):
    page, spaced, fused = int(rest[i]), rest[i + 1], rest[i + 2]
    ok = spaced in cand and fused not in cand and fused in base and spaced not in base
    print(f"{case_id} page {page}: {spaced!r} / {fused!r} -> {'added' if ok else 'REFUSED'}")
    if not ok:
        continue
    entry = next((p for p in case["pages"] if p["page"] == page), None)
    if entry is None:
        entry = {"page": page}
        case["pages"].append(entry)
    for key, value in (("text", spaced), ("absentText", fused)):
        if value not in entry.setdefault(key, []):
            entry[key].append(value)
with open(path, "w", encoding="utf-8") as out:
    json.dump(data, out, indent=2, ensure_ascii=False)
    out.write("\n")
