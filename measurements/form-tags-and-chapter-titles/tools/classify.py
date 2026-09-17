import re, sys, json
# usage: classify.py base.txt cand.txt pages.json
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
sel = json.load(open(sys.argv[3]))
END = re.compile(r'[.!?:;)\]”"’]\s*$')

def opens(blocks):
    """paragraphs that end without closing punctuation and are followed by a paragraph opening lowercase
    or by any paragraph (possible split), plus line-level paragraphs"""
    n = 0; short = 0
    for i, x in enumerate(blocks):
        if not x.startswith('p: '): continue
        t = x[3:]
        if len(t) < 75 and not END.search(t): short += 1
        if i + 1 < len(blocks) and blocks[i + 1].startswith(('p: ', 'pre: ')) and not END.search(t) \
                and not re.match(r'^(Figure|Table) ', t):
            n += 1
    return n, short

for kind in ('text', 'block'):
    for p in sel[kind]:
        x, y = a.get(p, []), b.get(p, [])
        hx = [s for s in x if re.match(r'h\d:', s)]; hy = [s for s in y if re.match(r'h\d:', s)]
        ox, sx = opens(x); oy, sy = opens(y)
        tags = []
        if sx - sy >= 4: tags.append('INTERLEAVE-REPAIR')
        if hx != hy: tags.append('HEADINGS' + ('(order)' if sorted(hx) == sorted(hy) else '(set)'))
        if oy > ox: tags.append(f'OPEN+{oy - ox}')
        if oy < ox: tags.append(f'open-{ox - oy}')
        print(kind, p, f'blocks {len(x)}->{len(y)} short {sx}->{sy} open {ox}->{oy}', ' '.join(tags))
