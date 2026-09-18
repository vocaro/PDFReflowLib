import json, sys
# usage: lines.py fixture.json [minY maxY]: lines sorted top-down with geometry
f = json.load(open(sys.argv[1]))
lo, hi = (float(sys.argv[2]), float(sys.argv[3])) if len(sys.argv) > 3 else (-1e9, 1e9)
print('bounds', f['bounds'])
for p in f['paints']:
    r = p['rect']
    print('  paint', [round(v, 1) for v in r], {k: v for k, v in p.items() if k != 'rect' and v})
for l in sorted(f['lines'], key=lambda l: (-(l['rect'][1] + l['rect'][3]), l['rect'][0])):
    x, y, w, h = l['rect']
    if not lo <= y <= hi: continue
    s = l.get('structure')
    print(f"{x:7.1f} {y:7.1f} {x+w:7.1f} {y+h:7.1f} sz{l['fontSize']:5.1f} {'S' + str(s['group']) if s else ''} | {l['text'][:110]}")
