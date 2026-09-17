"""Quantify the per-pixel difference between the premultiplied and opaque rasters."""
import io, sys, zipfile
import numpy as np
from PIL import Image

a, b = zipfile.ZipFile(sys.argv[1]), zipfile.ZipFile(sys.argv[2])
imgs = sorted(n for n in set(a.namelist()) & set(b.namelist())
              if n.lower().endswith(('.png', '.jpg', '.jpeg')))
gmax = 0
hist = np.zeros(256, dtype=np.int64)
changed_imgs = 0
for n in imgs:
    ra = np.asarray(Image.open(io.BytesIO(a.read(n))).convert('RGB')).astype(np.int16)
    rb = np.asarray(Image.open(io.BytesIO(b.read(n))).convert('RGB')).astype(np.int16)
    d = np.abs(ra - rb)
    if d.any():
        changed_imgs += 1
    gmax = max(gmax, int(d.max()))
    hist += np.bincount(d.ravel(), minlength=256)
tot = hist.sum()
print(f'{len(imgs)} images, {changed_imgs} with any changed channel value')
print(f'total channel samples {tot}; maximum absolute difference {gmax} of 255')
for lvl in range(0, min(gmax + 1, 9)):
    print(f'  delta {lvl}: {hist[lvl]} samples  {100*hist[lvl]/tot:.4f}%')
print(f'  delta >= 1: {tot-hist[0]} samples  {100*(tot-hist[0])/tot:.4f}%')
