"""Compare two surveys: crops changed per page, lines released from and captured into crops.

usage: diff.py base.jsonl cand.jsonl [--verbose]
"""
import json
import sys


def load(path):
    return {p['page']: p for p in map(json.loads, open(path))}


base, cand = load(sys.argv[1]), load(sys.argv[2])
verbose = '--verbose' in sys.argv
changed = released_total = captured_total = 0
rw = cw = 0
for n in sorted(base):
    b, c = base[n], cand[n]
    if b['crops'] == c['crops']:
        continue
    changed += 1
    released = [l for l, m in zip(b['lines'], c['lines']) if l['c'] and not m['c'] and not l['h']]
    captured = [m for l, m in zip(b['lines'], c['lines']) if m['c'] and not l['c'] and not m['h']]
    released_total += len(released)
    captured_total += len(captured)
    rw += sum(len(l['t'].split()) for l in released)
    cw += sum(len(l['t'].split()) for l in captured)
    print(f"p{n}: crops {len(b['crops'])}->{len(c['crops'])} released {len(released)} captured {len(captured)}")
    if verbose:
        print('   base', b['crops'])
        print('   cand', c['crops'])
        for l in released:
            print('   - ', l['r'], l['t'][:80])
        for l in captured:
            print('   + ', l['r'], l['t'][:80])
print(f'pages changed {changed}; lines released {released_total} ({rw} words); captured {captured_total} ({cw} words)')
