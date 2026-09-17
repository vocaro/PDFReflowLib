#!/usr/bin/env python3
"""Pages the #93 rule fails, per book, as each threshold moves (reads scores.tsv from score-pages).

The ink columns hold every surveyed page's measurement, so a variant may test more pages than the
converter renders. Usage: sensitivity.py [scores.tsv]
"""
import csv
import sys
from collections import defaultdict
from pathlib import Path

DEFAULT = dict(share=0.5, numeric=0.2, judged=20, fraction=0.75, rows=7, cap=32)
VARIANTS = [
    ('rule', {}),
    ('English share < 0.4', dict(share=0.4)),
    ('English share < 0.6', dict(share=0.6)),
    ('English share < 0.7', dict(share=0.7)),
    ('numeric share < 0.3', dict(numeric=0.3)),
    ('no numeric guard', dict(numeric=9)),
    ('judged words >= 10', dict(judged=10)),
    ('uncovered >= 0.6', dict(fraction=0.6)),
    ('uncovered >= 0.3', dict(fraction=0.3)),
    ('uncovered rows >= 5', dict(rows=5)),
    ('words test only', dict(fraction=9)),
    ('ink test only', dict(share=-1)),
]


def fails(row, p):
    tokens, numeric = int(row['tokens']), int(row['numericTokens'])
    english, damaged = int(row['english']), int(row['damaged'])
    judged = english + damaged
    if judged >= p['judged'] and numeric < tokens * p['numeric'] and english < judged * p['share']:
        return 'words'
    fraction = float(row['uncoveredFraction'] or 0)
    rows = int(row['uncoveredRows'])
    if english < p['cap'] and rows >= p['rows'] and fraction >= p['fraction'] and english < rows:
        return 'ink'
    return None


def main():
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).with_name('scores.tsv')
    rows = list(csv.DictReader(path.open(), delimiter='\t'))
    books = sorted({r['book'] for r in rows})
    print('| Variant | ' + ' | '.join(books) + ' |')
    print('| --- |' + ' --- |' * len(books))
    for name, change in VARIANTS:
        p = dict(DEFAULT, **change)
        flagged = defaultdict(list)
        for r in rows:
            if fails(r, p):
                flagged[r['book']].append(int(r['page']))
        cells = []
        for b in books:
            pages = flagged[b]
            cells.append(str(len(pages)) if b == 'cdc' or len(pages) > 12 or not pages
                         else f"{len(pages)} ({', '.join(map(str, pages))})")
        print(f'| {name} | ' + ' | '.join(cells) + ' |')


if __name__ == '__main__':
    main()
