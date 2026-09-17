"""Missing-text survey: native text-layer lines absent from the EPUB text, classified by cause.

usage: analyze.py <survey.jsonl> <book.epub> [--list CAUSE] [--pages a,b,c] [--json out.json]
"""
import argparse
import collections
import json
import re
import sys

sys.path.insert(0, '/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a9acaee9e89cd74f3/tools')
from check_corpus_content import read_pages  # noqa: E402


def key(text):
    return re.sub(r'[^a-z0-9]', '', text.lower())


def intersects(a, b):
    return a[0] < b[0] + b[2] and b[0] < a[0] + a[2] and a[1] < b[1] + b[3] and b[1] < a[1] + a[3]


def thin(r):
    return r[3] <= 6 and r[2] >= max(12, r[3] * 3)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('survey')
    parser.add_argument('epub')
    parser.add_argument('--list', action='append', default=[])
    parser.add_argument('--json')
    args = parser.parse_args()
    pages, _ = read_pages(args.epub, max_uncompressed_bytes=4 << 30, max_entries=100000)
    text = {n: key(p['text']) for n, p in pages.items()}
    counts = collections.Counter()
    words = collections.Counter()
    by_page = collections.defaultdict(collections.Counter)
    records = []
    for raw in open(args.survey):
        page = json.loads(raw)
        n = page['page']
        haystack = ''.join(text.get(m, '') for m in (n - 1, n, n + 1))
        height = None
        crops = page['crops']
        for line in page['lines']:
            k = key(line['t'])
            if len(k) < 6:
                continue
            if k in haystack:
                continue
            r = line['r']
            if page['unsupported']:
                cause = 'page-image-fallback'
            elif line['h']:
                cause = 'hidden'
            elif line['c']:
                crop = crops[line['c'][0]]
                figure = any(intersects(g, crop) and not thin(g) for g in page['graphics'])
                cause = 'figure-crop' if figure else 'formula-or-table-crop'
            elif n not in pages:
                cause = 'page-not-in-epub'
            else:
                # Page-space y: furniture sits in the top or bottom 54 pt.
                cause = 'furniture-band' if r[1] < 54 or r[1] + r[3] > 792 - 54 else 'other'
            count = len(line['t'].split())
            counts[cause] += 1
            words[cause] += count
            by_page[cause][n] += 1
            records.append({'page': n, 'cause': cause, 'text': line['t'], 'rect': r, 'size': line['s'],
                            'crop': crops[line['c'][0]] if line['c'] else None})
    for cause in sorted(counts):
        print(f'{cause:24} lines {counts[cause]:5} words {words[cause]:6} pages {len(by_page[cause]):4}')
    for cause in args.list:
        print(f'\n== {cause}: pages', dict(sorted(by_page[cause].items())))
        for rec in records:
            if rec['cause'] == cause:
                print(f"  p{rec['page']:3} {rec['rect']} s{rec['size']:.1f} {rec['text'][:90]!r}")
    if args.json:
        json.dump(records, open(args.json, 'w'), indent=1)


main()
