"""Ink-loss check: painted pixels inside a baseline crop that no candidate crop and no text line covers.

usage: inkcheck.py pdf base.jsonl cand.jsonl [--dpi 72] [--threshold 30]
Pages whose crops changed are rendered with pdftoppm; a pixel counts as ink when any channel is below 200.
Text-line rectangles (all native lines) are excluded: text leaving a crop reflows.
"""
import glob
import json
import subprocess
import sys
import tempfile
from PIL import Image

pdf, base_path, cand_path = sys.argv[1:4]
dpi = int(sys.argv[sys.argv.index('--dpi') + 1]) if '--dpi' in sys.argv else 72
threshold = int(sys.argv[sys.argv.index('--threshold') + 1]) if '--threshold' in sys.argv else 30


def load(path):
    return {p['page']: p for p in map(json.loads, open(path))}


base, cand = load(base_path), load(cand_path)
scale = dpi / 72
flagged = []
checked = 0
for n in sorted(base):
    b, c = base[n], cand[n]
    if b['crops'] == c['crops'] or b['unsupported']:
        continue
    checked += 1
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(['pdftoppm', '-f', str(n), '-l', str(n), '-r', str(dpi), '-png', pdf, f'{tmp}/p'], check=True)
        image = Image.open(glob.glob(f'{tmp}/p*.png')[0]).convert('RGB')
    width, height = image.size
    pixels = image.load()

    def box(r, pad=0.0):
        x, y, w, h = r
        return (int((x - pad) * scale), int(height - (y + h + pad) * scale), int((x + w + pad) * scale) + 1,
                int(height - (y - pad) * scale) + 1)

    def inside(px, py, rects):
        return any(x0 <= px < x1 and y0 <= py < y1 for x0, y0, x1, y1 in rects)

    cand_boxes = [box(r) for r in c['crops']]
    text_boxes = [box(l['r'], 1) for l in b['lines']]
    lost = 0
    where = None
    for r in b['crops']:
        x0, y0, x1, y1 = box(r)
        for py in range(max(0, y0), min(height, y1)):
            for px in range(max(0, x0), min(width, x1)):
                if inside(px, py, cand_boxes) or inside(px, py, text_boxes):
                    continue
                red, green, blue = pixels[px, py]
                if min(red, green, blue) < 200:
                    lost += 1
                    if where is None:
                        where = (px / scale, (height - py) / scale)
    if lost > threshold:
        flagged.append((n, lost, where))
print(f'checked {checked} pages; flagged {len(flagged)} (ink pixels > {threshold} at {dpi} dpi outside candidate crops and text)')
for n, lost, where in flagged:
    print(f'  p{n}: {lost} ink pixels, first at page point {tuple(round(v, 1) for v in where)}')
