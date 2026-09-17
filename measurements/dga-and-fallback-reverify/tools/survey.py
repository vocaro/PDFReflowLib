#!/usr/bin/env python3
"""Operation counts per page for every cached corpus PDF, with the budget lifted."""
import glob, os, re, subprocess, sys
here = os.path.dirname(os.path.abspath(__file__))
env = dict(os.environ, BUDGET='100000000')
env.pop('CLIP', None)
files = sys.argv[1:] or sorted(glob.glob('/Users/trevorharmon/Development/PDFReflowLib/corpus/cache/*.pdf'))
for f in files:
    out = subprocess.run([os.path.join(here, 'diag'), f], capture_output=True, text=True, env=env).stdout
    rows = []
    for line in out.splitlines():
        m = re.match(r'page (\d+) unsupported=(\w+) .*ops=(\d+) seconds=([\d.]+) paints=(\d+)', line)
        if m: rows.append((int(m[1]), m[2] == 'true', int(m[3]), float(m[4]), int(m[5]), line))
    top = sorted(rows, key=lambda r: -r[2])[:3]
    print(f'== {os.path.basename(f)} pages={len(rows)} over100k={sum(r[2] > 100_000 for r in rows)} '
          f'unsupportedLifted={sum(r[1] for r in rows)} maxOps={top[0][2] if top else 0}', flush=True)
    for r in rows:
        if r[2] > 100_000 or r[1]:
            print(f'   page {r[0]} ops={r[2]} seconds={r[3]} paints={r[4]} unsupportedLifted={r[1]}')
