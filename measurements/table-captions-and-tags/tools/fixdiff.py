import json, sys
old = json.load(open(sys.argv[1])); new = json.load(open(sys.argv[2]))
print('keys old-only', set(old) - set(new), 'new-only', set(new) - set(old))
for key in sorted(set(old) & set(new)):
    if old[key] != new[key] and key not in ('lines', 'paints', 'attributedLines', 'graphics'):
        print('DIFF', key, str(old[key])[:200], '->', str(new[key])[:200])
def r(v): return [round(x, 2) for x in v]
for key in ('graphics',):
    a = [r(x) for x in old.get(key, [])]; b = [r(x) for x in new.get(key, [])]
    print(key, len(a), len(b), 'removed', [x for x in a if x not in b], 'added', [x for x in b if x not in a])
a = [(r(p['rect']), p['frame']) for p in old.get('paints', [])]; b = [(r(p['rect']), p['frame']) for p in new.get('paints', [])]
print('paints', len(a), len(b)); print('  removed', [x for x in a if x not in b]); print('  added', [x for x in b if x not in a])
ol = old['lines']; nl = new['lines']
print('lines', len(ol), len(nl))
ot = [(l['text'], r(l['rect']), l['fontSize']) for l in ol]; nt = [(l['text'], r(l['rect']), l['fontSize']) for l in nl]
print('  text/rect removed', [x for x in ot if x not in nt]); print('  text/rect added', [x for x in nt if x not in ot])
os_ = [l.get('structure') for l in ol]; ns = [l.get('structure') for l in nl]
if ot == nt:
    changed = [(ol[i]['text'][:40], os_[i], ns[i]) for i in range(len(ol)) if os_[i] != ns[i]]
    print('  structure changed on', len(changed), 'lines; tagged old', sum(1 for s in os_ if s), 'new', sum(1 for s in ns if s))
    for c in changed[:8]: print('   ', c)
for k in ('attributedLines',):
    if old.get(k) != new.get(k): print(k, 'differ', len(old.get(k, [])), len(new.get(k, [])))
