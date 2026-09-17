import json
import sys

cands = json.load(open(sys.argv[1]))
trace = [l for l in open(sys.argv[2]) if l.startswith('TRACE')]
pick = {19, 24, 122, 145, 169, 251, 281, 286, 109, 136}
for c in cands:
    if not (c['opening'] == 'lower' or (c['end_page'] in pick and c['words'] > 5)):
        continue
    if c['words'] < 3:
        continue
    tail = c['end'][-40:]
    hits = [l.strip() for l in trace if tail[-25:] in l]
    print(f"p{c['end_page']}->{c['next_page']} [{c['between']}] …{c['end'][-35:]!r} ‖ {c['next'][:25]!r}")
    for h in hits or ['   (no trace)']:
        print('    ', h[:330])
