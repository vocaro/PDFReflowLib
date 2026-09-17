"""Review strips for joins across pages or columns.

usage: sheets.py joined.json survey.jsonl pdf out-prefix [--per 6]
Each row: the foot strip (anchor last line in red) and the head strip (first line in red), 70 pt context.
"""
import json
import os
import subprocess
import sys
from PIL import Image, ImageDraw

joins = [j for j in json.load(open(sys.argv[1])) if j['between'] or j['next_page'] != j['end_page'] or j['end_page'] == 18]
survey = {}
for line in open(sys.argv[2]):
    d = json.loads(line)
    survey[d['page']] = d
pdf, prefix = sys.argv[3], sys.argv[4]
per = int(sys.argv[sys.argv.index('--per') + 1]) if '--per' in sys.argv else 6
os.makedirs(prefix + '-pages', exist_ok=True)
dpi, scale = 90, 90 / 72


def render(n):
    path = f'{prefix}-pages/p{n}.png'
    if not os.path.exists(path):
        subprocess.run(['pdftoppm', '-r', str(dpi), '-png', '-singlefile', '-f', str(n), '-l', str(n), pdf, path[:-4]],
                       check=True)
    return Image.open(path).convert('RGB')


def norm(t):
    return ' '.join(t.split())


def strip(n, text, last):
    lines = survey[n]['lines']
    t = norm(text)
    if last:
        cands = [l for l in lines if l['t'].strip() and t.endswith(norm(l['t']))]
    else:
        cands = [l for l in lines if l['t'].strip() and t.startswith(norm(l['t']).rstrip('-'))]
    img = render(n)
    if not cands:
        return Image.new('RGB', (300, 60), 'yellow')
    a = max(cands, key=lambda l: len(l['t']))
    x, y, w, h = a['r']
    H = img.height
    d = ImageDraw.Draw(img)
    d.rectangle([x * scale, H - (y + h) * scale, (x + w) * scale, H - y * scale], outline='red', width=2)
    box = (max(0, (x - 8) * scale), max(0, H - (y + h + 70) * scale), min(img.width, (x + w + 8) * scale),
           min(H, H - (y - 70) * scale))
    return img.crop(tuple(int(v) for v in box))


rows = []
for j in joins:
    a = strip(j['end_page'], j['end'], True)
    b = strip(j['next_page'], j['next'], False)
    row = Image.new('RGB', (a.width + b.width + 30, max(a.height, b.height) + 16), 'white')
    ImageDraw.Draw(row).text((4, 2), f"p{j['end_page']}->{j['next_page']} [{j['between']}]", fill='blue')
    row.paste(a, (4, 16))
    row.paste(b, (a.width + 24, 16))
    rows.append(row)
for k in range(0, len(rows), per):
    chunk = rows[k:k + per]
    sheet = Image.new('RGB', (max(r.width for r in chunk), sum(r.height + 4 for r in chunk)), 'gray')
    yy = 0
    for r in chunk:
        sheet.paste(r, (0, yy))
        yy += r.height + 4
    out = f'{prefix}-{k // per + 1:02d}.png'
    sheet.save(out)
    print(out, len(chunk))
