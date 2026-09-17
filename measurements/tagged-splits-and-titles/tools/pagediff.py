import re, sys, difflib
# usage: pagediff.py base.txt cand.txt  -- per-page unified block diff of two block dumps
# (measurements/form-tags-and-chapter-titles/tools/block-dump.py output), every changed page.
def pages(f):
    d = {0: []}; cur = 0
    for l in open(f):
        l = l.rstrip('\n')
        m = re.match(r'=== page (\d+)$', l)
        if m: cur = int(m.group(1)); d.setdefault(cur, []); continue
        if l.startswith('=== page'): continue
        d[cur].append(re.sub(r'\[\[p\d+\]\]', '', l))
    return d
a, b = pages(sys.argv[1]), pages(sys.argv[2])
for p in sorted(set(a) | set(b)):
    if a.get(p, []) == b.get(p, []): continue
    print(f'######## page {p}')
    for line in difflib.unified_diff(a.get(p, []), b.get(p, []), lineterm='', n=0):
        if line.startswith(('---', '+++')): continue
        print(line)
