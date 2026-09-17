#!/usr/bin/env python3
"""usage: summarize.py : census/summary.txt from census/<book>-<label>.tsv and .repairs.tsv"""
import collections, csv, pathlib, re

census = pathlib.Path(__file__).resolve().parent.parent / 'census'
books = ['faa', 'dga', 'fed', 'our-flag', '911', 'wallace', 'loper', 'usgs', 'replay']
out = []
out.append('Maps (identical in every label; one binary reports both parses)')
out.append('book | pages with measured simple fonts | pages with a rejected map | pages with an Adobe one-byte map '
           '| pages still rejected (strict, one-byte) | font-page uses rejected: strict -> one-byte | remaining rejection classes')
for book in books:
    rows = list(csv.DictReader(open(census / f'{book}-base.tsv'), delimiter='\t'))
    uses = sum(int(r['simpleFonts']) for r in rows)
    strict = sum(int(r['strictRejected']) for r in rows)
    onebyte = sum(int(r['oneByteAccepted']) for r in rows)
    classes = collections.Counter()
    for r in rows:
        if r['otherRejected'] != '-':
            for part in r['otherRejected'].split(','):
                key, value = part.rsplit('=', 1)
                classes[re.sub(r'twoByteEntry\((<[0-9A-Fa-f]{4}>).*\)', r'twoByteEntry(\1 …)', key)] += int(value)
    out.append(f"{book} | {len(rows)} of which styled {sum(r['styled'] == 'true' for r in rows)} | "
               f"{sum(int(r['strictRejected']) > 0 for r in rows)} | {sum(int(r['oneByteAccepted']) > 0 for r in rows)} | "
               f"{sum(int(r['strictRejected']) > 0 for r in rows)} -> {sum(r['otherRejected'] != '-' for r in rows)} | "
               f"{strict} of {uses} -> {strict - onebyte} | {dict(classes) or '-'}")
out.append('')
out.append('Evidence and repairs per label (base: 36c6265 reader; cand: this tree; gs: this tree with a textless ExtGState accepted)')
out.append('book | label | shows | decoded | pages with decoded shows | first disqualifying check (pages) | repaired lines | inserted spaces')
for book in books:
    for label in ['base', 'cand', 'gs']:
        rows = list(csv.DictReader(open(census / f'{book}-{label}.tsv'), delimiter='\t'))
        reasons = collections.Counter(re.sub(r'@\d+$', '', r['invalid']) for r in rows)
        repairs = [line.rstrip('\n').split('\t') for line in open(census / f'{book}-{label}.repairs.tsv')]
        inserted = sum(len(after) - len(before) for _, before, after, *_ in repairs)
        out.append(f"{book} | {label} | {sum(int(r['shows']) for r in rows)} | {sum(int(r['decoded']) for r in rows)} | "
                   f"{sum(int(r['decoded']) > 0 for r in rows)} | {dict(reasons.most_common())} | {len(repairs)} | {inserted}")
text = '\n'.join(out) + '\n'
(census / 'summary.txt').write_text(text)
print(text)
