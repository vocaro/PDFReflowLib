import json, sys, re
S = '/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad/issue100'
dump = open(f'{S}/dumps/{sys.argv[1]}.txt').read().split('\n')
pages = {}
cur = None
for l in dump:
    m = re.match(r'=== page (\d+)', l)
    if m:
        cur = int(m.group(1)); continue
    pages.setdefault(cur, []).append(l)
import os
plist = list(map(int, sys.argv[2:])) or sorted(int(f[4:-5]) for f in os.listdir(f'{S}/fx') if f.startswith('fed-') and f.endswith('.json'))
for p in plist:
    d = json.load(open(f'{S}/fx/fed-{p}.json'))
    frames = [f['rect'] for f in d.get('paints') or [] if f['frame']]
    for fr in frames:
        x, y, w, h = fr
        inside = [l for l in d['lines'] if x <= l['rect'][0] + l['rect'][2] / 2 <= x + w and y <= l['rect'][1] + l['rect'][3] / 2 <= y + h]
        inside.sort(key=lambda l: -l['rect'][1])
        if len(inside) < 2:
            continue
        a, b = inside[0], inside[1]
        pitch = [inside[i]['rect'][1] - inside[i + 1]['rect'][1] for i in range(1, min(4, len(inside) - 1))]
        out = [o for o in pages.get(p, []) if o[3:30].strip() and a['text'][:20] in o]
        print(f"p{p} frame w={w:.0f} n={len(inside)} title={a['text'][:55]!r} fs={a['fontSize']:.1f} h={a['rect'][3]:.2f} | next fs={b['fontSize']:.1f} h={b['rect'][3]:.2f} pitch1={a['rect'][1]-b['rect'][1]:.1f} pitch={[round(v,1) for v in pitch]} tag={a.get('structure',{}) and a['structure'].get('headingLevel')} dx={b['rect'][0]-a['rect'][0]:.1f}")
        print('     out:', [o[:90] for o in out][:2])
