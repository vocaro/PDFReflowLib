"""Compare two EPUBs asset by asset: decoded RGB pixels, alpha, and every XHTML document."""
import hashlib, io, sys, zipfile
import numpy as np
from PIL import Image

a, b = zipfile.ZipFile(sys.argv[1]), zipfile.ZipFile(sys.argv[2])
an = {n for n in a.namelist()}
bn = {n for n in b.namelist()}
print('names only in A:', sorted(an - bn)[:5], 'only in B:', sorted(bn - an)[:5])

xh = sorted(n for n in an & bn if n.endswith(('.xhtml', '.opf', '.ncx', '.css')))
diff = [n for n in xh if a.read(n) != b.read(n)]
print(f'markup/package/nav files: {len(xh)} compared, {len(diff)} differ', diff[:5])

imgs = sorted(n for n in an & bn if n.lower().endswith(('.png', '.jpg', '.jpeg')))
same_pixels = alpha_opaque_a = mode_a_rgba = mode_b_rgb = 0
bad = []
for n in imgs:
    ia = Image.open(io.BytesIO(a.read(n)))
    ib = Image.open(io.BytesIO(b.read(n)))
    mode_a_rgba += ia.mode == 'RGBA'
    mode_b_rgb += ib.mode == 'RGB'
    if ia.mode == 'RGBA':
        alpha_opaque_a += bool((np.asarray(ia)[..., 3] == 255).all())
    ra = np.asarray(ia.convert('RGB'))
    rb = np.asarray(ib.convert('RGB'))
    if ra.shape == rb.shape and np.array_equal(ra, rb):
        same_pixels += 1
    else:
        bad.append((n, ra.shape, rb.shape,
                    int(np.abs(ra.astype(int) - rb.astype(int)).max()) if ra.shape == rb.shape else None))
print(f'images: {len(imgs)} compared')
print(f'  A written RGBA: {mode_a_rgba};  A alpha all-opaque: {alpha_opaque_a};  B written RGB: {mode_b_rgb}')
print(f'  identical decoded RGB pixels: {same_pixels}/{len(imgs)}')
for n, sa, sb, mx in bad[:10]:
    print('   DIFF', n, sa, sb, 'max channel delta', mx)
bytes_a = sum(i.file_size for i in a.infolist())
bytes_b = sum(i.file_size for i in b.infolist())
print(f'entry bytes {bytes_a} -> {bytes_b}  ({100*(bytes_a-bytes_b)/bytes_a:.1f}% smaller)')
