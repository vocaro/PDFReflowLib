"""usage: sheet.py out.png pdf:page:x0:y0:x1:y1 ...  stack crops (PDF points) vertically at 90 DPI."""
import subprocess
import sys
from PIL import Image, ImageDraw

out = sys.argv[1]
crops = []
for spec in sys.argv[2:]:
    pdf, page, x0, y0, x1, y1 = spec.rsplit(':', 5)
    prefix = out + '.tmp'
    subprocess.run(['pdftoppm', '-f', page, '-l', page, '-r', '90', '-png', '-singlefile', pdf, prefix], check=True)
    im = Image.open(prefix + '.png')
    s = 90 / 72
    H = im.size[1]
    c = im.crop((int(float(x0) * s), int(H - float(y1) * s), int(float(x1) * s), int(H - float(y0) * s)))
    d = ImageDraw.Draw(c)
    d.text((2, 2), f'p{page}', fill=(255, 0, 0))
    crops.append(c)
W = max(c.size[0] for c in crops)
sheet = Image.new('RGB', (W, sum(c.size[1] + 6 for c in crops)), 'white')
y = 0
for c in crops:
    sheet.paste(c, (0, y))
    y += c.size[1] + 6
sheet.save(out)
