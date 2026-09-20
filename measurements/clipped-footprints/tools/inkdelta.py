#!/usr/bin/env python3
"""Ink left outside the crops and the text, before and after, page by page.

A clip read too tightly leaves real artwork uncovered. This renders each page whose crops changed
and counts the dark pixels outside crops and line boxes under the old crops and under the new
ones, so only an increase is attributable to the change.
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

DPI = 72
CACHE = Path(__file__).resolve().parents[3] / 'corpus/cache'


def load(path):
    rows = {}
    for line in Path(path).read_text().splitlines():
        d = json.loads(line)
        rows[(d['file'], d['page'])] = d
    return rows


def outside(pixels, bounds, rects):
    height, width = pixels.shape
    bx, by, bw, bh = bounds
    allowed = np.zeros_like(pixels, dtype=bool)
    for x, y, w, h in rects:
        left = int((x - bx)) - 1
        right = int((x - bx + w)) + 1
        top = int((by + bh - (y + h))) - 1
        bottom = int((by + bh - y)) + 1
        allowed[max(0, top):min(height, bottom), max(0, left):min(width, right)] = True
    ink = pixels < 200
    return int((ink & ~allowed).sum()), int(ink.sum())


def main():
    old, new = load(sys.argv[1]), load(sys.argv[2])
    changed = sorted(k for k in new if k in old and old[k]['crops'] != new[k]['crops'])
    print('pages whose crops changed:', len(changed))
    rows = []
    with tempfile.TemporaryDirectory() as directory:
        for file, page in changed:
            a, b = old[(file, page)], new[(file, page)]
            if b['requiresPageImage'] and a['requiresPageImage']:
                continue
            prefix = Path(directory) / 'p'
            subprocess.run(['pdftoppm', '-f', str(page), '-l', str(page), '-r', str(DPI), '-gray',
                            '-png', str(CACHE / file), str(prefix)], check=True, capture_output=True)
            files = sorted(Path(directory).glob('p-*.png'))
            pixels = np.asarray(Image.open(files[0]).convert('L'))
            before, total = outside(pixels, a['bounds'], a['crops'] + a['lines'])
            after, _ = outside(pixels, b['bounds'], b['crops'] + b['lines'])
            rows.append((after - before, before, after, total, file, page))
            for path in files:
                path.unlink()
    rows.sort(reverse=True)
    worse = [r for r in rows if r[0] > 0]
    print('pages that leave more ink uncovered than before:', len(worse))
    for delta, before, after, total, file, page in rows[:20]:
        print(f'  {file:30s} page {page:5d} outside {before:7d} -> {after:7d} of {total:8d}'
              f' ink pixels (delta {delta:+d})')
    print('total ink pixels newly outside:', sum(r[0] for r in worse))


main()
