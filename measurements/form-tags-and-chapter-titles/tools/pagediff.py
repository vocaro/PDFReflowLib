import re, sys, difflib
# usage: pagediff.py base.txt cand.txt width page...
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
w = int(sys.argv[3])
for p in map(int, sys.argv[4:]):
    print(f'######## page {p}')
    for line in difflib.unified_diff(a.get(p, []), b.get(p, []), lineterm='', n=0):
        if line.startswith(('---', '+++')): continue
        print(line[:w])
