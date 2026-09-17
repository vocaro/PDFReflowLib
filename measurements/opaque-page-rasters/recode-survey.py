"""Measure lossless re-encodings of the page rasters the library writes.

For a sample of assets: is the alpha channel constant? is the image grayscale?
What do PNG-RGB, PNG-gray, PNG-palette and JPEG cost against the written RGBA PNG?
"""
import io, json, random, sys, zipfile
import numpy as np
from PIL import Image

epub, index, kind, n = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
z = zipfile.ZipFile(epub)
imgs = json.load(open(index))
sel = [s for s, v in imgs.items() if v[1] == kind]
random.seed(11)
sel = sorted(random.sample(sel, min(n, len(sel))))

tot = {k: 0 for k in ('orig', 'rgb', 'gray', 'pal', 'jpeg90', 'jpeg95', 'smallest90')}
opaque = grayish = 0
rows = []
for s in sel:
    d = z.read('EPUB/images/' + s)
    im = Image.open(io.BytesIO(d))
    a = np.asarray(im)
    has_alpha = im.mode == 'RGBA'
    op = bool(has_alpha and (a[..., 3] == 255).all())
    rgb = im.convert('RGB')
    r = np.asarray(rgb)
    gy = bool((r[..., 0] == r[..., 1]).all() and (r[..., 1] == r[..., 2]).all())
    opaque += op
    grayish += gy

    def size(img, fmt, **kw):
        b = io.BytesIO()
        img.save(b, fmt, **kw)
        return b.tell()

    e = {}
    e['orig'] = len(d)
    e['rgb'] = size(rgb, 'PNG', optimize=False, compress_level=6)
    e['gray'] = size(rgb.convert('L'), 'PNG', compress_level=6)
    e['pal'] = size(rgb.convert('P', palette=Image.ADAPTIVE, colors=256), 'PNG', compress_level=6)
    e['jpeg90'] = size(rgb, 'JPEG', quality=90)
    e['jpeg95'] = size(rgb, 'JPEG', quality=95)
    e['smallest90'] = min(e['rgb'], e['jpeg90'])
    for k in tot:
        tot[k] += e[k]
    rows.append((s, op, gy, e))

print(f'{kind}: sampled {len(sel)} of {len([1 for v in imgs.values() if v[1]==kind])}')
print(f'  fully opaque alpha: {opaque}/{len(sel)};  R==G==B: {grayish}/{len(sel)}')
base = tot['orig']
for k in ('orig', 'rgb', 'gray', 'pal', 'jpeg90', 'jpeg95', 'smallest90'):
    print(f'  {k:11s} {tot[k]/1048576:9.2f} MiB   {100*tot[k]/base:6.1f}% of written')
