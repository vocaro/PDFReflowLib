#!/usr/bin/env python3
"""usage: fixturediff.py <old-layout.json> <new-layout.json>  lines, paints and graphics that differ."""
import json
import sys

old, new = (json.load(open(path)) for path in sys.argv[1:3])


def lines(fixture):
    return [(l['text'], tuple(round(v, 2) for v in l['rect']), l['fontSize'], json.dumps(l.get('structure'), sort_keys=True))
            for l in fixture['lines']]


a, b = lines(old), lines(new)
print('lines', len(a), '->', len(b))
for line in a:
    if line not in b:
        print('-', line[:3])
for line in b:
    if line not in a:
        print('+', line[:3])
for key in ('paints', 'graphics', 'attributedLines', 'bounds', 'sourceSHA256'):
    print(key, 'same' if old.get(key) == new.get(key) else 'DIFFERENT')
