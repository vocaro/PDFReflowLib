"""compare.py <before> <after> [detail.txt]: diff two digests."""
import collections, difflib, gzip, json, sys
from pathlib import Path

S = Path(__file__).resolve().parent / 'out'
def load(n):
    with gzip.open(S / f'{n}.digest.json.gz', 'rt') as h:
        return json.load(h)
a, b = load(sys.argv[1]), load(sys.argv[2])
print('epub identical:', a['epubSHA256'] == b['epubSHA256'])
print('warnings', len(a['warnings']), '->', len(b['warnings']))
def short(m):
    return {'Caption, list': 'unsafe', 'Tagged groups': 'run', 'Some tagged text': 'reader',
            'Some PDF structure': 'tree'}.get(next((k for k in ('Caption, list', 'Tagged groups', 'Some tagged text', 'Some PDF structure') if m.startswith(k)), ''), m[:20])
def fall(d):
    r = collections.defaultdict(set)
    for c, p, m in d['warnings']:
        if c == 'structureFallback':
            r[short(m)].add(p)
    return r
fa, fb = fall(a), fall(b)
for k in sorted(set(fa) | set(fb)):
    print(f'structureFallback[{k}]', len(fa[k]), '->', len(fb[k]), 'gained', sorted(fb[k] - fa[k]), 'lost', sorted(fa[k] - fb[k]))
ca = collections.Counter(c for c, _, _ in a['warnings']); cb = collections.Counter(c for c, _, _ in b['warnings'])
for k in sorted(set(ca) | set(cb)):
    if ca[k] != cb[k]:
        print('code', k, ca[k], '->', cb[k])
print('nav', len(a['nav']), '->', len(b['nav']), 'identical' if a['nav'] == b['nav'] else 'DIFFERS')
if a['nav'] != b['nav']:
    for line in difflib.unified_diff([f'{d} {t}' for d, t, _ in a['nav']], [f'{d} {t}' for d, t, _ in b['nav']], lineterm='', n=0):
        print('  nav', line)
print('images identical:', a['images'] == b['images'], len(a['images']), len(b['images']))
text = [p for p in a['pages'] if a['pages'][p]['text'] != b['pages'].get(p, {}).get('text')]
blocks = [p for p in a['pages'] if any(a['pages'][p][k] != b['pages'].get(p, {}).get(k) for k in ('headings', 'paragraphs', 'listItems'))]
wa = sorted(sum((a['pages'][p]['text'].split() for p in a['pages']), []))
wb = sorted(sum((b['pages'][p]['text'].split() for p in b['pages']), []))
print('word multiset identical:', wa == wb, len(wa), len(wb))
print('text-changed pages', len(text), sorted(map(int, text)))
print('block-changed pages', len(blocks), sorted(map(int, blocks)))
if len(sys.argv) > 3:
    with open(sys.argv[3], 'w') as h:
        for p in sorted(set(text) | set(blocks), key=int):
            h.write(f'===== page {p}\n')
            for k in ('headings', 'paragraphs', 'listItems'):
                old, new = a['pages'][p][k], b['pages'][p][k]
                if old != new:
                    for line in difflib.unified_diff(old, new, lineterm='', n=0):
                        if not line.startswith(('---', '+++', '@@')):
                            h.write(f'  {k[:4]} {line}\n')
            if a['pages'][p]['text'] != b['pages'][p]['text']:
                sa, sb = a['pages'][p]['text'].split(), b['pages'][p]['text'].split()
                for op, i1, i2, j1, j2 in difflib.SequenceMatcher(None, sa, sb, autojunk=False).get_opcodes():
                    if op != 'equal':
                        h.write(f'  text {op}: {" ".join(sa[i1:i2])[:300]!r} -> {" ".join(sb[j1:j2])[:300]!r}\n')
