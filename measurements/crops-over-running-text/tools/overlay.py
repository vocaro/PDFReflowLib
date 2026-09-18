import re, subprocess, sys, os
from PIL import Image, ImageDraw

# usage: overlay.py <pdf> <survey.txt> <out.png> <page> [page...]
# Renders each page at 50 dpi and draws its crops (from the survey) as red rectangles.
pdf, survey, out = sys.argv[1], sys.argv[2], sys.argv[3]
pages = [int(p) for p in sys.argv[4:]]
DPI = 50
crops = {}
current = None
for line in open(survey, encoding='utf-8', errors='replace'):
    m = re.match(r'^(\d+)\t', line)
    if m:
        current = int(m.group(1)); crops[current] = []
    else:
        r = re.match(r'^  \[([-\d.]+) ([-\d.]+) ([-\d.]+) ([-\d.]+)\]', line)
        if r and current is not None:
            crops[current].append([float(x) for x in r.groups()])
images = []
for p in pages:
    subprocess.run(['pdftoppm', '-r', str(DPI), '-png', '-f', str(p), '-l', str(p), pdf, '/tmp/ov'], check=True)
    name = [f for f in os.listdir('/tmp') if f.startswith('ov-') and f.endswith('.png')]
    path = '/tmp/' + sorted(name)[-1]
    im = Image.open(path).convert('RGB')
    draw = ImageDraw.Draw(im)
    height = im.height
    for (x0, y0, x1, y1) in crops.get(p, []):
        box = [x0 * DPI / 72, height - y1 * DPI / 72, x1 * DPI / 72, height - y0 * DPI / 72]
        draw.rectangle(box, outline=(255, 0, 0), width=2)
    draw.text((4, 4), str(p), fill=(255, 0, 0))
    images.append(im)
    os.remove(path)
w = sum(i.width for i in images); h = max(i.height for i in images)
sheet = Image.new('RGB', (w, h), 'white')
x = 0
for i in images:
    sheet.paste(i, (x, 0)); x += i.width
sheet.save(out)
print(out, sheet.size)
