import sys, re, difflib

# usage: dumpdiff.py <blocks-dump> page [page ...]: unified diff of each page's blocks, base vs cand.
text = open(sys.argv[1], encoding='utf-8').read()
base, cand = text.split('######## cand\n')
base = base.split('######## base\n', 1)[1]
def pages(s):
    out = {}
    for chunk in s.split('==== page ')[1:]:
        number, _, rest = chunk.partition('\n')
        out[int(number)] = rest.splitlines()
    return out
b, c = pages(base), pages(cand)
want = [int(x) for x in sys.argv[2:]] or sorted(set(b) | set(c))
for p in want:
    diff = list(difflib.unified_diff(b.get(p, []), c.get(p, []), lineterm='', n=0))
    if diff:
        print(f'==== page {p}')
        for line in diff[2:]:
            if not line.startswith('@@'): print(line[:200])
