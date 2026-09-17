import os, sys
from PIL import Image, ImageDraw
D = os.path.dirname(os.path.abspath(__file__))
tsv = sys.argv[1]
colors = {'E': (255, 0, 0), 'P': (170, 170, 255), 'N': (255, 170, 0), 'G': (0, 180, 0), 'C': (160, 0, 200)}
rows = [l.rstrip('\n').split('\t') for l in open(tsv)]
for p in sorted({int(r[0]) for r in rows if len(r) >= 6}):
    im = Image.open(f'{D}/p-{p}.png').convert('RGB')
    d = ImageDraw.Draw(im)
    s = 100 / 72
    for r in rows:
        if len(r) < 6 or int(r[0]) != p: continue
        x0, y0, x1, y1 = map(float, r[2:6])
        w = {'C': 3, 'G': 2, 'E': 1}.get(r[1], 1)
        pad = {'C': 3, 'G': 1}.get(r[1], 0)
        d.rectangle([x0 * s - pad, y0 * s - pad, x1 * s + pad, y1 * s + pad], outline=colors[r[1]], width=w)
    im.save(f'{D}/r-{p}.png')
