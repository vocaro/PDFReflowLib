#!/usr/bin/env python3
"""Per-page differences between two EPUBs: words, image count and pixel sizes, tables.

usage: pagediff.py <baseline.epub> <candidate.epub>

A page whose only change is losing thin images (height at most MAX_RULE_HEIGHT pixels) with its
text and tables unchanged is summarised as a rule-only change; every other change is listed.
"""
import collections
import io
import struct
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from check_corpus_content import read_pages  # noqa: E402

MAX_RULE_HEIGHT = 16


def png_size(data):
    if data[:8] == b'\x89PNG\r\n\x1a\n':
        return struct.unpack('>II', data[16:24])
    return None


def sizes(path, pages):
    with zipfile.ZipFile(path) as archive:
        names = set(archive.namelist())
        result = {}
        for number, page in pages.items():
            dims = []
            for asset in page['images']:
                name = asset if asset in names else 'EPUB/' + asset.split('EPUB/')[-1]
                data = archive.read(name) if name in names else b''
                dims.append(png_size(data))
            result[number] = dims
        return result


def main():
    base_path, cand_path = sys.argv[1], sys.argv[2]
    base, _ = read_pages(base_path)
    cand, _ = read_pages(cand_path)
    base_sizes, cand_sizes = sizes(base_path, base), sizes(cand_path, cand)
    totals = collections.Counter()
    rule_only = []
    for number in sorted(set(base) | set(cand)):
        b, c = base.get(number), cand.get(number)
        bw = collections.Counter((b or {}).get('text', '').split())
        cw = collections.Counter((c or {}).get('text', '').split())
        bi, ci = base_sizes.get(number, []), cand_sizes.get(number, [])
        bt, ct = (b or {}).get('tables', []), (c or {}).get('tables', [])
        totals['baseImages'] += len(bi)
        totals['candImages'] += len(ci)
        totals['baseTables'] += len(bt)
        totals['candTables'] += len(ct)
        totals['baseThin'] += sum(1 for s in bi if s and s[1] <= MAX_RULE_HEIGHT)
        totals['candThin'] += sum(1 for s in ci if s and s[1] <= MAX_RULE_HEIGHT)
        if bw == cw and bt == ct and bi == ci and (b or {}).get('text') == (c or {}).get('text'):
            continue
        lost = collections.Counter(bi) - collections.Counter(ci)
        gained = collections.Counter(ci) - collections.Counter(bi)
        if (b or {}).get('text') == (c or {}).get('text') and bt == ct and not gained \
                and all(s and s[1] <= MAX_RULE_HEIGHT for s in lost.elements()):
            rule_only.append((number, sorted(lost.elements())))
            continue
        print(f'page {number}: words {sum(bw.values())} -> {sum(cw.values())} '
              f'(+{sum((cw - bw).values())} -{sum((bw - cw).values())}); images {bi} -> {ci}; tables {len(bt)} -> {len(ct)}; '
              f'same text order: {(b or {}).get("text") == (c or {}).get("text")}')
        if cw - bw:
            print('   gained words:', ' '.join(list((cw - bw).elements())[:60]))
        if bw - cw:
            print('   lost words:', ' '.join(list((bw - cw).elements())[:60]))
    print(f'rule-only pages ({len(rule_only)}):', ' '.join(str(n) for n, _ in rule_only))
    print('lost thin image sizes on rule-only pages:', dict(collections.Counter(s for _, l in rule_only for s in l)))
    print('totals:', dict(totals))


if __name__ == '__main__':
    main()
