"""Rejected prototype (#18): comic panels from a page raster by recursive gutter cuts.

Measurement only; nothing in the library uses it. Input is a directory of `pdftoppm -r 80 -jpeg`
renders named p-NN.jpg. Output: one TSV row per page with the panel rectangles (render pixels,
top-left origin, in cut order) and, with --draw DIR, overlay images.

Ink is a pixel at least CONTRAST darker than its RADIUS box mean, so inked borders count and smooth
shading (the page vignette) does not. Inside a region, rows are tried before columns. A gutter is a
run of at least MIN_GUTTER lines with at most LIGHT_MAX ink, flanked within SEARCH lines on both
sides by a line with at least BORDER_MIN ink, and passing through the region's outer border lines
(at most 25% ink in its first and last 8 perpendicular lines), so a light band inside one panel
(a window frame) is not a gutter. Pieces narrower than MIN_PANEL are dropped. All thresholds were
fitted by hand to this one book's 80-DPI renders.
"""
import argparse, os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

RADIUS, CONTRAST = 8, 45
LIGHT_MAX, BORDER_MIN = 0.08, 0.40
MIN_GUTTER, SEARCH, MIN_PANEL = 5, 10, 60


def ink(path):
    img = Image.open(path).convert('L')
    a = np.asarray(img).astype(np.int16)
    mean = np.asarray(img.filter(ImageFilter.BoxBlur(RADIUS))).astype(np.int16)
    return (mean - a) > CONTRAST


def cuts(dark, axis):
    share = dark.mean(axis=1 - axis)
    n, light, found, i = share.shape[0], share <= LIGHT_MAX, [], 0
    while i < n:
        if not light[i]:
            i += 1
            continue
        j = i
        while j < n and light[j]:
            j += 1
        if j - i >= MIN_GUTTER and i > 0 and j < n:
            before, after = share[max(0, i - SEARCH):i], share[j:j + SEARCH]
            ends = (dark[:8, i:j], dark[-8:, i:j]) if axis == 1 else (dark[i:j, :8], dark[i:j, -8:])
            if before.max() >= BORDER_MIN and after.max() >= BORDER_MIN and all(e.mean() <= 0.25 for e in ends):
                found.append((i, j))
        i = j
    return found


def panels(dark, x0=0, y0=0):
    h, w = dark.shape
    if min(h, w) < MIN_PANEL:
        return []
    for axis in (0, 1):
        found = cuts(dark, axis)
        if not found:
            continue
        pieces, start, out = [], 0, []
        for a, b in found:
            pieces.append((start, a))
            start = b
        pieces.append((start, dark.shape[axis]))
        for a, b in pieces:
            if b - a >= MIN_PANEL:
                sub = dark[a:b, :] if axis == 0 else dark[:, a:b]
                out += panels(sub, x0 + (a if axis else 0), y0 + (0 if axis else a))
        return out
    return [(x0, y0, x0 + w, y0 + h)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('renders')
    parser.add_argument('--pages', type=int, nargs='+', default=list(range(1, 43)))
    parser.add_argument('--draw')
    args = parser.parse_args()
    print('page\tpanels\trectangles')
    for page in args.pages:
        path = os.path.join(args.renders, f'p-{page:02d}.jpg')
        found = panels(ink(path))
        print(f'{page}\t{len(found)}\t' + ' '.join(f'{x1},{y1},{x2},{y2}' for x1, y1, x2, y2 in found))
        if args.draw:
            pic = Image.open(path).convert('RGB')
            draw = ImageDraw.Draw(pic)
            for k, (x1, y1, x2, y2) in enumerate(found):
                draw.rectangle([x1 + 3, y1 + 3, x2 - 3, y2 - 3], outline=(255, 0, 0), width=5)
                draw.rectangle([x1 + 8, y1 + 8, x1 + 30, y1 + 26], fill=(255, 255, 0))
                draw.text((x1 + 12, y1 + 10), str(k + 1), fill=(0, 0, 0))
            os.makedirs(args.draw, exist_ok=True)
            pic.save(os.path.join(args.draw, f'p-{page:02d}.jpg'), quality=70)


if __name__ == '__main__':
    main()
