import json, sys
# usage: lines.py fixture.json [y0 y1 x0 x1] -> lines top-down with rect, group, fonts
d = json.load(open(sys.argv[1]))
box = [float(v) for v in sys.argv[2:6]] if len(sys.argv) >= 6 else None
att = {}
for a in d['attributedLines']:
    att.setdefault(a['text'], a)
for m in sorted(d['lines'], key=lambda l: -l['rect'][1]):
    r = m['rect']
    if box and not (box[0] <= r[1] <= box[1] and box[2] <= r[0] <= box[3]):
        continue
    a = att.get(m['text'])
    fonts = sorted(set(x['fontName'] for x in a['runs'])) if a else '?'
    print([round(x, 1) for x in r], m['fontSize'], m.get('structure', {}).get('group'), repr(m['text'][:64]), fonts)
