"""Source strips for same-page joins: the column-foot line (left) and the column-head line (right).

usage: joinsheet.py joins.json survey.jsonl pdf out-prefix [--per 10]
Renders each page with pdftoppm (100 dpi) into out-prefix-pages/, marks the two anchor lines in red.
"""
import json
import os
import subprocess
import sys
from PIL import Image, ImageDraw

joins = json.load(open(sys.argv[1]))['joins']
survey = {}
for line in open(sys.argv[2]):
    d = json.loads(line)
    survey[d['page']] = d
pdf, prefix = sys.argv[3], sys.argv[4]
per = int(sys.argv[sys.argv.index('--per') + 1]) if '--per' in sys.argv else 10
pages_dir = prefix + '-pages'
os.makedirs(pages_dir, exist_ok=True)
dpi = 100
scale = dpi / 72


def render(n):
    path = f'{pages_dir}/p{n}.png'
    if not os.path.exists(path):
        subprocess.run(['pdftoppm', '-r', str(dpi), '-png', '-singlefile', '-f', str(n), '-l', str(n), pdf,
                        path[:-4]], check=True)
    return Image.open(path).convert('RGB')


def norm(t):
    return ' '.join(t.split())


rows = []
for j in joins:
    n = j['page']
    lines = survey[n]['lines']
    end, nxt = norm(j['end']), norm(j['next'])
    last = max((l for l in lines if l['t'].strip() and end.endswith(norm(l['t']))), key=lambda l: len(l['t']), default=None)
    first = max((l for l in lines if l['t'].strip() and nxt.startswith(norm(l['t']).rstrip('-'))),
                key=lambda l: len(l['t']), default=None)
    img = render(n)
    h = img.height
    draw = ImageDraw.Draw(img)
    crops = []
    for anchor in (last, first):
        if anchor is None:
            crops.append(Image.new('RGB', (400, 120), 'yellow'))
            continue
        x, y, w, hh = anchor['r']
        draw.rectangle([x * scale, h - (y + hh) * scale, (x + w) * scale, h - y * scale], outline='red', width=2)
    for anchor in (last, first):
        if anchor is None:
            continue
        x, y, w, hh = anchor['r']
        box = (max(0, (x - 10) * scale), max(0, h - (y + hh + 45) * scale), min(img.width, (x + w + 10) * scale),
               min(h, h - (y - 45) * scale))
        crops.append(img.crop(tuple(int(v) for v in box)))
    width = sum(c.width for c in crops) + 30
    row = Image.new('RGB', (max(width, 700), max(c.height for c in crops) + 22), 'white')
    ImageDraw.Draw(row).text((4, 2), f'p{n}: …{end[-50:]} ‖ {nxt[:50]}…', fill='blue')
    xoff = 4
    for c in crops:
        row.paste(c, (xoff, 20))
        xoff += c.width + 20
    rows.append(row)

for k in range(0, len(rows), per):
    chunk = rows[k:k + per]
    sheet = Image.new('RGB', (max(r.width for r in chunk), sum(r.height for r in chunk) + 4 * len(chunk)), 'gray')
    y = 0
    for r in chunk:
        sheet.paste(r, (0, y))
        y += r.height + 4
    sheet.save(f'{prefix}-{k // per + 1:02d}.png')
    print(f'{prefix}-{k // per + 1:02d}.png')
