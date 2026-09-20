#!/usr/bin/env python3
"""What the graphics operation budget costs: the distribution of charged operations over every
cached corpus page, read with the budget lifted, and the time a full scan of the heaviest takes."""
import json
import sys
from pathlib import Path

rows = []
for path in sys.argv[1:]:
    for line in Path(path).read_text().splitlines():
        d = json.loads(line)
        for page in d['pages']:
            rows.append((d['file'], page['page'], page['operations'], page['seconds'],
                         page['unsupported'], page['regions'],
                         page['footprintAfter'] - page['footprintBefore']))

print('pages surveyed', len(rows))
bands = [(0, 10_000), (10_000, 50_000), (50_000, 100_000), (100_000, 150_000), (150_000, 200_000),
         (200_000, 250_000), (250_000, 500_000), (500_000, 1_000_000), (1_000_000, 10**9)]
for low, high in bands:
    band = [r for r in rows if low <= r[2] < high]
    names = ', '.join(f'{r[0].split(".")[0][:20]}:{r[1]}({r[2]:,})' for r in band[:6])
    print(f'{low:>9,}-{high:<10,} {len(band):5d}  {names}')
print('\nheaviest pages, full scan:')
for f, p, ops, sec, uns, reg, foot in sorted(rows, key=lambda r: -r[2])[:14]:
    print(f'  {f:45s} page {p:5d} ops {ops:9,} scan {sec*1000:8.1f} ms regions {reg:5d}'
          f' unsupported {str(uns):5s} footprint {foot/1024:+9.0f} KiB')
print('\nslowest full scans:')
for f, p, ops, sec, uns, reg, foot in sorted(rows, key=lambda r: -r[3])[:10]:
    print(f'  {f:45s} page {p:5d} ops {ops:9,} scan {sec*1000:8.1f} ms regions {reg:5d}'
          f' unsupported {str(uns):5s} footprint {foot/1024:+9.0f} KiB')
print('\nstill unsupported with the budget lifted:', sum(1 for r in rows if r[4]))
for f, p, ops, sec, uns, reg, foot in rows:
    if uns:
        print(f'  {f} page {p} ops {ops:,} regions {reg}')
