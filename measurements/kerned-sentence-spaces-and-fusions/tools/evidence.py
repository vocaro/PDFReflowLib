import sys, re
from collections import Counter, defaultdict
# For boundaries after `.` before a capital: how the source sets them, by left segment and what follows the capital.
tab = defaultdict(Counter); examples = defaultdict(list)
for l in open(sys.argv[1], encoding='utf-8'):
    f = l.rstrip('\n').split('\t')
    kind = f[2]
    if kind not in ('adj', 'kern0', 'space'): continue
    if f[3] != '.' or not f[4].isupper(): continue
    L, R = f[12].split('|', 1)
    nxt = R[1:2]
    m = re.search(r'([A-Za-z0-9]*)\.$', L)
    seg = m.group(1) if m else ''
    before = L[:len(L) - len(seg) - 1][-1:] if m else ''
    segc = 'empty' if not seg else ('digits' if seg.isdigit() else ('1' if len(seg) == 1 else ('2' if len(seg) == 2 else '3+')))
    if before == '.': segc += '/internal.'
    nx = 'period' if nxt == '.' else ('lower' if nxt.islower() else ('upper' if nxt.isupper() else 'other'))
    if kind == 'space': how = 'spaceglyph'
    else:
        tc = float(f[7]); adj = float(f[9]); gap = min(adj, adj + tc)
        how = 'measured' if gap >= 0.005 else 'closed'
    key = (segc, nx)
    tab[key][how] += 1
    if len(examples[(key, how)]) < 8: examples[(key, how)].append(f[12])
for key in sorted(tab):
    print(key, dict(tab[key]))
    for how in ('spaceglyph', 'measured', 'closed'):
        if examples[(key, how)]: print('   ', how, ' ; '.join(examples[(key, how)][:6]))
