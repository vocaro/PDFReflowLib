import json, sys
d = json.load(open(sys.argv[1]))
tags = {}
for l in d['lines']:
    tags[(l['text'], tuple(round(x, 1) for x in l['rect']))] = (l.get('structure'), l['fontSize'])
print('page', d['page'], 'paints', len(d.get('paints') or []), 'frames', sum(1 for p in d.get('paints') or [] if p['frame']))
for p in d.get('paints') or []:
    if p['frame']:
        print('  frame', [round(x, 1) for x in p['rect']])
for l in sorted(d['attributedLines'], key=lambda l: -(l['rect'][1] if l.get('rect') else 0)):
    r = [round(x, 1) for x in l.get('rect') or []]
    runs = ' | '.join(f"{x['fontName']}@{x['fontSize']:g}:{x['text'][:25]!r}" for x in l['runs'])
    t = tags.get((l['text'], tuple(r)))
    print(r, l['text'][:70], '::', runs[:150], '::', t)
