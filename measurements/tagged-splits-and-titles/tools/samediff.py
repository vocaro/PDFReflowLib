import difflib, sys
# usage: samediff.py base1 cand1 base2 cand2 -- are the changed block lines of pair 1 and pair 2 the same?
def changes(a, b):
    x, y = open(a).read().splitlines(), open(b).read().splitlines()
    return [l for l in difflib.unified_diff(x, y, lineterm='', n=0) if l[:1] in '+-' and not l.startswith(('+++', '---'))]
one, two = changes(sys.argv[1], sys.argv[2]), changes(sys.argv[3], sys.argv[4])
print('pair 1 changed lines', len(one), 'pair 2 changed lines', len(two), 'identical change sets:', one == two)
for l in [l for l in one if l not in two][:10]: print('only 1:', l[:160])
for l in [l for l in two if l not in one][:10]: print('only 2:', l[:160])
