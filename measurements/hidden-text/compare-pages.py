import sys
sys.path.insert(0, "/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-ac792da2d7b1d9d97/tools")
import compare_conversion_runs as c
from pathlib import Path
# usage: pages.py baseline.epub candidate.epub
# Pages whose records differ, split into those that differ only by the book-wide paragraph
# ordinal (paragraphIDs keys shift when an earlier page loses paragraphs) and real changes.
a, b = Path(sys.argv[1]), Path(sys.argv[2])
lp, _ = c.read_pages(a)
rp, _ = c.read_pages(b)
changed = sorted(p for p in lp.keys() | rp.keys() if lp.get(p) != rp.get(p))
ordinal_only, real = [], []
for p in changed:
    l, r = lp.get(p) or {}, rp.get(p) or {}
    keys = {k for k in l.keys() | r.keys() if l.get(k) != r.get(k)}
    if keys == {"paragraphIDs"} and list(l["paragraphIDs"].values()) == list(r["paragraphIDs"].values()):
        ordinal_only.append(p)
    else:
        real.append((p, sorted(keys)))
print("changed", len(changed), "ordinal-only", len(ordinal_only))
print("real changes", real)
for p, keys in real:
    l, r = lp.get(p) or {}, rp.get(p) or {}
    lt, rt = l.get("paragraphs", []), r.get("paragraphs", [])
    print(f"page {p}: removed paragraphs", [x for x in lt if x not in rt][:10], "added", [x for x in rt if x not in lt][:10])
    lh, rh = l.get("headings", []), r.get("headings", [])
    if lh != rh:
        print(f"page {p}: headings", lh, "=>", rh)
