#!/usr/bin/env python3
"""Audit two claims in #28's abandoned-branch study using its retained Git objects."""
import gzip
import hashlib
import json
import subprocess

REVISION = 'dc81a78087ace4215841cd1d8059924dddd279e8'


def read(path):
    return subprocess.check_output(['git', 'show', REVISION + ':' + path])


def main():
    sweep_path = 'measurements/raster-qualification/sweep/results.json.gz'
    books_path = 'measurements/raster-qualification/books/summary.json'
    sweep = read(sweep_path); books = read(books_path)
    rows = json.loads(gzip.decompress(sweep))['images']
    png = {(x['target'], x['requestedDPI']): x for x in rows if x['kind'] == 'region' and x['encoding'] == 'png'}
    examples = []
    for row in rows:
        if 'phraseCoverage' not in row: continue
        base = png[row['target'], row['requestedDPI']]['phraseCoverage']['found']
        delta = row['phraseCoverage']['found'] - base
        if abs(delta) > 1:
            examples.append({'target': row['target'], 'dpi': row['requestedDPI'], 'encoding': row['encoding'],
                             'pngPhrases': base, 'encodedPhrases': row['phraseCoverage']['found'], 'delta': delta})
    result = {'revision': REVISION, 'sources': {sweep_path: hashlib.sha256(sweep).hexdigest(),
                                               books_path: hashlib.sha256(books).hexdigest()},
              'maximumAbsolutePhraseDelta': max(abs(x['delta']) for x in examples),
              'counterexamplesToAtMostOneClaim': examples,
              'bookSettings': sorted({row['setting'] for row in json.loads(books)['runs']})}
    print(json.dumps(result, indent=2))


if __name__ == '__main__': main()
