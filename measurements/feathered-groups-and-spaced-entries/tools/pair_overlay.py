import re, subprocess, sys, os
from PIL import Image, ImageDraw

# usage: pair_overlay.py <pdf> <base-survey> <cand-survey> <out.png> <page> [page...]
# Two rows: base crops (red) above candidate crops (blue) for each page, at 50 dpi.
pdf, base, cand, out = sys.argv[1:5]
pages = [int(p) for p in sys.argv[5:]]
DPI = 50
S = '/private/tmp/claude-501/i181'

def load(survey):
    crops, current = {}, None
    for line in open(survey, encoding='utf-8', errors='replace'):
        m = re.match(r'^(\d+)\t', line)
        if m:
            current = int(m.group(1)); crops[current] = []
        else:
            r = re.match(r'^  \[([-\d.]+) ([-\d.]+) ([-\d.]+) ([-\d.]+)\]', line)
            if r and current is not None:
                crops[current].append([float(x) for x in r.groups()])
    return crops

surveys = [(load(base), (255, 0, 0)), (load(cand), (0, 0, 255))]
rows = []
for crops, colour in surveys:
    images = []
    for p in pages:
        subprocess.run(['pdftoppm', '-r', str(DPI), '-png', '-f', str(p), '-l', str(p), pdf, f'{S}/render'], check=True)
        name = sorted(f for f in os.listdir(S) if f.startswith('render-') and f.endswith('.png'))[-1]
        im = Image.open(f'{S}/{name}').convert('RGB')
        os.remove(f'{S}/{name}')
        draw = ImageDraw.Draw(im)
        for (x0, y0, x1, y1) in crops.get(p, []):
            draw.rectangle([x0 * DPI / 72, im.height - y1 * DPI / 72, x1 * DPI / 72, im.height - y0 * DPI / 72],
                           outline=colour, width=3)
        draw.text((4, 4), str(p), fill=colour)
        images.append(im)
    rows.append(images)
w = max(sum(i.width for i in r) for r in rows); h = sum(max(i.height for i in r) for r in rows)
sheet = Image.new('RGB', (w, h), 'white')
y = 0
for r in rows:
    x = 0
    for i in r:
        sheet.paste(i, (x, y)); x += i.width
    y += max(i.height for i in r)
sheet.save(out)
print(out, sheet.size)
