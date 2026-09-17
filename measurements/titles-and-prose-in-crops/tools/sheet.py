"""Before/after sheets of the preserved images on changed pages.

usage: sheet.py base.epub cand.epub cmp.json out-prefix [--per 8] [--width 900] [--pages 1,2]
Each row: page number, base images (left, red label) | candidate images (right, green label), with pixel sizes.
"""
import io
import json
import sys
import zipfile
from PIL import Image, ImageDraw

sys.path.insert(0, '/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a9acaee9e89cd74f3/tools')
from check_corpus_content import read_pages  # noqa: E402

base_path, cand_path, cmp_path, prefix = sys.argv[1:5]
per = int(sys.argv[sys.argv.index('--per') + 1]) if '--per' in sys.argv else 8
width = int(sys.argv[sys.argv.index('--width') + 1]) if '--width' in sys.argv else 900
base, _ = read_pages(base_path, max_uncompressed_bytes=4 << 30, max_entries=100000)
cand, _ = read_pages(cand_path, max_uncompressed_bytes=4 << 30, max_entries=100000)
if '--pages' in sys.argv:
    pages = [int(p) for p in sys.argv[sys.argv.index('--pages') + 1].split(',')]
else:
    pages = json.load(open(cmp_path))['changedPages']
bz, cz = zipfile.ZipFile(base_path), zipfile.ZipFile(cand_path)
row_h = 260
half = width // 2


def strip(z, names, w):
    images = [Image.open(io.BytesIO(z.read(n))).convert('RGB') for n in names]
    canvas = Image.new('RGB', (w, row_h), 'white')
    if not images:
        return canvas, []
    slot = w // len(images)
    sizes = []
    for i, im in enumerate(images):
        sizes.append(im.size)
        scale = min((slot - 6) / im.width, (row_h - 20) / im.height, 1.0)
        thumb = im.resize((max(1, int(im.width * scale)), max(1, int(im.height * scale))))
        canvas.paste(thumb, (i * slot + 3, 18))
        ImageDraw.Draw(canvas).rectangle([i * slot + 2, 17, i * slot + 4 + thumb.width, 19 + thumb.height], outline=(150, 150, 150))
    return canvas, sizes


pages = [p for p in pages if p in base or p in cand]
for sheet_index in range(0, len(pages), per):
    chunk = pages[sheet_index:sheet_index + per]
    sheet = Image.new('RGB', (width + 10, row_h * len(chunk)), 'white')
    draw = ImageDraw.Draw(sheet)
    for r, page in enumerate(chunk):
        b_im, b_sizes = strip(bz, base.get(page, {}).get('images', []), half)
        c_im, c_sizes = strip(cz, cand.get(page, {}).get('images', []), half)
        sheet.paste(b_im, (0, r * row_h))
        sheet.paste(c_im, (half + 10, r * row_h))
        draw.line([(half + 5, r * row_h), (half + 5, (r + 1) * row_h)], fill=(0, 0, 0), width=2)
        draw.line([(0, r * row_h), (width + 10, r * row_h)], fill=(0, 0, 0), width=1)
        draw.text((4, r * row_h + 3), f'p{page} base {b_sizes}', fill=(200, 0, 0))
        draw.text((half + 14, r * row_h + 3), f'cand {c_sizes}', fill=(0, 140, 0))
    out = f'{prefix}-{sheet_index // per + 1:02d}.png'
    sheet.save(out)
    print(out, chunk)
