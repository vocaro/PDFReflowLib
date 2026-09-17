import re, sys
# usage: splits.py base.txt cand.txt : paragraph boundaries one side has inside a paragraph and the other splits
def blocks(f):
    out = []; page = 0
    for l in open(f):
        l = l.rstrip('\n')
        m = re.match(r'=== page (\d+)', l)
        if m: page = int(m.group(1)); continue
        m = re.match(r'(p|pre|li|figcaption|h\d): (.*)', l)
        if m: out.append((page, m.group(1), re.sub(r'\s*\[\[p\d+\]\]\s*', ' ', m.group(2)).strip()))
    return out

def norm(s): return re.sub(r'\s+', ' ', s)

def boundaries_split(x, y, label):
    body = '\n'.join(norm(t) for _, _, t in x)
    found = []
    for (p1, k1, t1), (p2, k2, t2) in zip(y, y[1:]):
        if k1 not in ('p', 'pre') or k2 not in ('p', 'pre'): continue
        seam = norm(t1[-25:] + ' ' + t2[:25])
        if len(t1) > 3 and len(t2) > 3 and seam in body:
            found.append((p2, t1[-45:], t2[:45]))
    print(f'{label}: {len(found)}')
    for f in found: print('  ', f)

a, b = blocks(sys.argv[1]), blocks(sys.argv[2])
boundaries_split(a, b, 'paragraphs the candidate splits that the baseline joins')
boundaries_split(b, a, 'paragraphs the baseline splits that the candidate joins')
