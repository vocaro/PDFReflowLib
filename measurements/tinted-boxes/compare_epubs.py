#!/usr/bin/env python3
"""Per-page comparison of two EPUBs from the same source: text, headings, tables and images.

Images are compared by pixel size and byte hash (names differ between runs). Prints the pages
whose text changed (with word counts), pages whose image set changed, and totals.
"""
import hashlib
from pathlib import Path
import struct
import sys
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools'))
import check_corpus_content as ccc


def png_size(data):
    if data[:8] == b'\x89PNG\r\n\x1a\n':
        return struct.unpack('>II', data[16:24])
    return (len(data), 0)


def load(path):
    pages, _ = ccc.read_pages(path, max_entries=20000, max_uncompressed_bytes=4 * 1024 ** 3)
    with zipfile.ZipFile(path) as archive:
        images = {}
        for n, page in pages.items():
            entries = []
            for name in page['images']:
                data = archive.read(name)
                entries.append((png_size(data), hashlib.sha256(data).hexdigest()[:12]))
            images[n] = sorted(entries)
    return pages, images


def main():
    left, right = sys.argv[1], sys.argv[2]
    verbose = '--verbose' in sys.argv
    lp, li = load(left)
    rp, ri = load(right)
    text_changed, image_changed = [], []
    gained = lost = 0
    for n in sorted(set(lp) | set(rp)):
        lt = lp.get(n, {}).get('text', '')
        rt = rp.get(n, {}).get('text', '')
        lw, rw = len(lt.split()), len(rt.split())
        if lt != rt:
            text_changed.append((n, lw, rw, len(lp.get(n, {}).get('tables', [])), len(rp.get(n, {}).get('tables', []))))
            gained += max(0, rw - lw)
            lost += max(0, lw - rw)
        if li.get(n) != ri.get(n):
            image_changed.append((n, [s for s, _ in li.get(n, [])], [s for s, _ in ri.get(n, [])]))
    print(f'pages: {len(lp)} vs {len(rp)}; text changed on {len(text_changed)} pages (+{gained} / -{lost} words); '
          f'image set changed on {len(image_changed)} pages; images {sum(len(v) for v in li.values())} -> {sum(len(v) for v in ri.values())}; '
          f'tables {sum(len(p.get("tables", [])) for p in lp.values())} -> {sum(len(p.get("tables", [])) for p in rp.values())}')
    if verbose:
        for n, lw, rw, lt, rt in text_changed:
            print(f'  text page {n}: {lw} -> {rw} words, tables {lt} -> {rt}')
        for n, l, r in image_changed:
            print(f'  images page {n}: {l} -> {r}')


if __name__ == '__main__':
    main()
