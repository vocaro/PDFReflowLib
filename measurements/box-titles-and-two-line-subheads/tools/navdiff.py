"""navdiff.py base.txt cand.txt: headings added/removed/changed level (with page), and whether block text is preserved."""
import re, sys
from collections import Counter

def read(path):
    page = None
    heads, text = [], []
    for line in open(path):
        line = line.rstrip('\n')
        m = re.match(r'=== page (\d+)', line)
        if m:
            page = int(m.group(1)); continue
        m = re.match(r'(h[1-6]|p|pre|li|figcaption|td|th): (.*)', line)
        if not m:
            continue
        if m.group(1).startswith('h'):
            heads.append((page, m.group(1), m.group(2)))
        text.append(m.group(2))
    return heads, text

bh, bt = read(sys.argv[1])
ch, ct = read(sys.argv[2])
bkeys = Counter((p, t) for p, _, t in bh)
ckeys = Counter((p, t) for p, _, t in ch)
added = ckeys - bkeys
removed = bkeys - ckeys
print(f'headings {len(bh)} -> {len(ch)}; added {sum(added.values())}, removed {sum(removed.values())}')
lev_b = {(p, t): l for p, l, t in bh}
for p, l, t in ch:
    if (p, t) in added:
        print(f'  + p{p} {l}: {t}')
for p, l, t in bh:
    if (p, t) in removed:
        print(f'  - p{p} {l}: {t}')
changed = [(p, lev_b[(p, t)], l, t) for p, l, t in ch if (p, t) in lev_b and lev_b[(p, t)] != l]
for c in changed:
    print(f'  ~ p{c[0]} {c[1]}->{c[2]}: {c[3]}')
norm = lambda xs: re.sub(r'\s+', '', ''.join(xs))
print('text preserved (whitespace-insensitive):', norm(bt) == norm(ct))
