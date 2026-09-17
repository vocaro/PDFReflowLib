#!/usr/bin/env python3
"""usage: summarize.py survey.json...  one block per tagged table: shape, spans, consistency, cells."""
import json, sys
for path in sys.argv[1:]:
    tables = json.load(open(path))
    print(f'## {path.rsplit("/", 1)[-1]}: {len(tables)} tagged tables')
    for t in tables:
        cells = [c for row in t['rows'] for c in row]
        spans = sorted({c['attrs'].get('ColSpan', 1) for c in cells if 'attrs' in c})
        print(f"pages {t['pages']} parent {t['parent']}: {len(t['rows'])} TR, {len(cells)} cells "
              f"({sum(c['role'] == 'TH' for c in cells)} TH), colspans {spans}, empty cells {sum(not c['lines'] for c in cells)}, "
              f"unknown-origin MCIDs {sum(c['unknownOrigin'] for c in cells)}, unplaced shows {sum(c['unplaced'] for c in cells)}, "
              f"lines shared between cells {len(t['sharedLines'])}")
        at = next(i for i, s in enumerate(t['parentChildren']) if s.startswith('*TABLE*'))
        if at > 0:
            print(f"   preceding sibling: {t['parentChildren'][at - 1][:140]}")
        for shared in t['sharedLines']:
            print(f"   shared: {shared}")
        for row in t['rows']:
            print('   TR ' + ' || '.join(f"{c['role']}{c.get('attrs', {}).get('ColSpan', '')}{c.get('bbox', '')} {' / '.join(c['lines'])[:48]}" for c in row))
