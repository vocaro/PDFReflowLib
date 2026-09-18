import sys, re
# usage: classify.py base.epub cand.epub: pages whose blocks only split/join (same text), and the rest in detail
exec(open(sys.argv[0].replace('classify.py', 'pagediff.py')).read().split('a, b = pages')[0])
import difflib
a, b = pages(sys.argv[1]), pages(sys.argv[2])
def text(blocks): return re.sub(r'\s+', '', ''.join(x.split(': ', 1)[1] if ': ' in x else x for x in blocks))
splits, joins, other = [], [], []
for n in sorted(set(a) | set(b)):
    if a.get(n) == b.get(n): continue
    A, B = a.get(n, []), b.get(n, [])
    if text(A) == text(B) and [x.split(':')[0] for x in A if 'img' in x] == [x.split(':')[0] for x in B if 'img' in x]:
        (splits if len(B) > len(A) else joins).append(n)
    else:
        other.append(n)
print('splits only', len(splits), splits)
print('joins only', len(joins), joins)
print('other', len(other), other)
for n in other:
    print(f'==== page {n}')
    for line in difflib.unified_diff(a.get(n, []), b.get(n, []), lineterm='', n=0):
        if line.startswith(('---', '+++', '@@')): continue
        print('  ' + line[:220])
