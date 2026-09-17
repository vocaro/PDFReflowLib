import sys, re, collections
# usage: navdiff.py base.txt cand.txt  -- headings (level, text) per source page, added/removed/level-changed
def heads(path):
    out = collections.Counter()
    page = 0
    for l in open(path):
        l = l.rstrip('\n')
        m = re.match(r'=== page (\d+)', l)
        if m:
            if '(inside)' not in l: page = int(m.group(1))
            continue
        m = re.match(r'h(\d): (.*)', l)
        if m: out[(page, m.group(2))] = int(m.group(1))
    return out
a, b = heads(sys.argv[1]), heads(sys.argv[2])
added = sorted(k for k in b if k not in a)
removed = sorted(k for k in a if k not in b)
relevel = sorted(k for k in a if k in b and a[k] != b[k])
print(f'headings {len(a)} -> {len(b)}; added {len(added)}, removed {len(removed)}, level changed {len(relevel)}')
for k in removed: print('-', k[0], f'h{a[k]}', k[1])
for k in relevel: print('~', k[0], f'h{a[k]}->h{b[k]}', k[1])
for k in added: print('+', k[0], f'h{b[k]}', k[1])
