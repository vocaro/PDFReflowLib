import re, sys, json
from collections import Counter

def pages(f):
    d = {}; cur = 0; d[0] = []
    for l in open(f):
        l = l.rstrip('\n')
        m = re.match(r'=== page (\d+)$', l)
        if m:
            cur = int(m.group(1)); d.setdefault(cur, []); continue
        if l.startswith('=== page'): continue
        d[cur].append(re.sub(r'\[\[p\d+\]\]', '', l))
    return d

def words(blocks):
    return Counter(w for b in blocks for w in re.sub(r'^\w+: ', '', b).replace('-', ' ').split())

a, b = pages(sys.argv[1]), pages(sys.argv[2])
wa = Counter(); wb = Counter()
text, block, same = [], [], 0
for p in sorted(set(a) | set(b)):
    x, y = a.get(p, []), b.get(p, []); wa += words(x); wb += words(y)
    if x == y: same += 1; continue
    tx = ' '.join(re.sub(r'^\w+: ', '', s) for s in x if s != 'img')
    ty = ' '.join(re.sub(r'^\w+: ', '', s) for s in y if s != 'img')
    (block if re.sub(r'\s+', ' ', tx) == re.sub(r'\s+', ' ', ty) else text).append(p)
print('identical pages', same)
print('text-changed pages', len(text), text)
print('block-only pages', len(block), block)
print('document word multiset equal:', wa == wb, 'lost', dict((wa - wb).most_common(8)), 'gained', dict((wb - wa).most_common(8)))
if len(sys.argv) > 3:
    json.dump({'text': text, 'block': block}, open(sys.argv[3], 'w'))
