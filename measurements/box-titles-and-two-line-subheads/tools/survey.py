"""survey.py <prefix> <dump-label> [pages...]: two-line runs in one bold/italic style over a body line."""
import json, os, re, sys
from collections import Counter
S = '/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad/issue100'
prefix, label = sys.argv[1], sys.argv[2]
dump = {}
page = None
for line in open(f'{S}/dumps/{label}.txt'):
    m = re.match(r'=== page (\d+)', line)
    if m:
        page = int(m.group(1)); continue
    dump.setdefault(page, []).append(line.rstrip('\n'))
files = sorted((int(f[len(prefix) + 1:-5]) for f in os.listdir(f'{S}/fx') if f.startswith(prefix + '-') and f.endswith('.json')))
pages = list(map(int, sys.argv[3:])) or files

def style(runs):
    names = [r['fontName'].lower() for r in runs if r['text'].strip()]
    if not names: return None
    bold = all('bold' in n for n in names)
    italic = not bold and all('italic' in n or 'oblique' in n for n in names)
    return 'bold' if bold else 'italic' if italic else 'plain'

for p in pages:
    d = json.load(open(f'{S}/fx/{prefix}-{p}.json'))
    att = {a['text'].strip(): a for a in d['attributedLines']}
    lines = []
    for l in d['lines']:
        a = att.get(l['text'].strip())
        if not a: continue
        x, y, w, h = l['rect']
        lines.append(dict(text=l['text'], x=x, minY=y, maxY=y + h, w=w, size=l['fontSize'], style=style(a['runs']),
                          fonts=sorted({r['fontName'] for r in a['runs'] if r['text'].strip()}), tag=l.get('structure')))
    weights = Counter()
    for l in lines: weights[round(l['size'])] += len(l['text'])
    if not weights: continue
    body = weights.most_common(1)[0][0]
    def column(l):
        return [o for o in lines if o is not l and o['x'] < l['x'] + l['w'] and o['x'] + o['w'] > l['x']]
    def below(l):
        c = [o for o in column(l) if o['maxY'] <= l['minY'] + body * 0.4]
        return max(c, key=lambda o: o['maxY']) if c else None
    def above(l):
        c = [o for o in column(l) if o['minY'] >= l['maxY'] - body * 0.25]
        return min(c, key=lambda o: o['minY']) if c else None
    for a in lines:
        if a['style'] not in ('bold', 'italic') or not (body * 0.95 <= a['size'] < body * 1.25): continue
        b = below(a)
        if not b or b['style'] != a['style'] or abs(b['size'] - a['size']) > 0.5 or abs(b['x'] - a['x']) > body * 0.5: continue
        if a['minY'] - b['maxY'] >= body * 0.8: continue
        c = below(b)
        if not c or c['style'] != 'plain' or abs(c['size'] - body) > body * 0.1 or b['minY'] - c['maxY'] >= body * 0.8: continue
        up = above(a)
        clear = up is None or up['minY'] - a['maxY'] >= body * 0.8
        edge = abs(c['x'] - a['x']) <= body * 0.5
        out = [o for o in dump.get(p, []) if a['text'][:25] in o]
        print(f"p{p} {a['style']} {a['size']:g}/{body} clear={clear} edge={edge} tag={(a['tag'] or {}).get('headingLevel')} "
              f"| {a['text']!r} / {b['text']!r} / {c['text'][:40]!r}  fonts={a['fonts']}")
        print('      out:', [o[:110] for o in out][:2])
