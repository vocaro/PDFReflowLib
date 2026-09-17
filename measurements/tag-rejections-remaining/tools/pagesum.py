"""pagesum.py <w-dir> <book>: compare <book>-base and <book>-cand dumps from one.sh: images, navigation,
structureFallback pages, pages whose block boundaries only changed, pages whose text order changed, word multiset."""
import collections, json, re, sys
from pathlib import Path
w, book = Path(sys.argv[1]), sys.argv[2]
print('images identical', (w / f'{book}-base.img').read_text() == (w / f'{book}-cand.img').read_text())
print('navigation identical', (w / f'{book}-base.nav').read_text() == (w / f'{book}-cand.nav').read_text(),
      len((w / f'{book}-base.nav').read_text().splitlines()), len((w / f'{book}-cand.nav').read_text().splitlines()))
fallback = {}
for label in ('base', 'cand'):
    warnings = json.load(open(w / f'{book}-{label}.json'))['warnings']
    codes = collections.Counter(x['code'] for x in warnings)
    fallback[label] = {x['page'] for x in warnings if x['code'] == 'structureFallback'}
    print(label, 'warnings', len(warnings), 'structureFallback pages', len(fallback[label]))
print('fallback removed', sorted(fallback['base'] - fallback['cand']), 'added', sorted(fallback['cand'] - fallback['base']))

def pages(path):
    d = collections.defaultdict(list); cur = 0
    for line in open(path):
        m = re.match(r'=== page (\d+)( \(inside\))?$', line.strip())
        if m: cur = int(m.group(1)); continue
        d[cur].append(re.sub(r'\[\[p\d+\]\]', '', line.rstrip('\n')))
    return d
a, b = pages(w / f'{book}-base.txt'), pages(w / f'{book}-cand.txt')
flat = lambda p: ' '.join(re.sub(r'^\w+: ', '', x) for x in p).split()
blockonly, text = [], []
for p in sorted(set(a) | set(b)):
    if a[p] == b[p]: continue
    (blockonly if flat(a[p]) == flat(b[p]) else text).append(p)
print('block-only pages', len(blockonly), blockonly)
print('text-order pages', len(text), text)
wa = collections.Counter(x for p in a for x in flat(a[p])); wb = collections.Counter(x for p in b for x in flat(b[p]))
print('word multiset identical', wa == wb, (wa - wb).most_common(5), (wb - wa).most_common(5))
