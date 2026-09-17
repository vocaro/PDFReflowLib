#!/usr/bin/env python3
"""usage: cost.py <base-binary> <cand-binary> <pdf> <runs> <work-dir>

Converts <pdf> alternately with the two binaries (base, cand, base, cand, ...), each run under
`/usr/bin/time -l`, and prints wall seconds and peak RSS (MiB) per run with the medians. Each
EPUB is deleted as soon as its run ends. Library defaults; the output byte budget is unlimited so
NOAA excerpts are not stopped by the default ceiling (the same for both binaries).
"""
import os
import re
import statistics
import subprocess
import sys
import time

base, cand, pdf, runs, work = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5]
results = {'base': [], 'cand': []}
for index in range(runs):
    for label, binary in (('base', base), ('cand', cand)):
        out = os.path.join(work, f'{label}-{index}.epub')
        start = time.monotonic()
        proc = subprocess.run(['/usr/bin/time', '-l', binary, pdf, out, '--maximum-output-bytes', 'unlimited',
                               '--package-identifier', 'urn:uuid:00000000-0000-0000-0000-000000000125',
                               '--modification-date', '2026-01-01T00:00:00Z'],
                              stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
        wall = time.monotonic() - start
        rss = int(re.search(r'(\d+)\s+maximum resident set size', proc.stderr).group(1)) / 2**20
        size = os.path.getsize(out) if os.path.exists(out) else 0
        if os.path.exists(out):
            os.remove(out)
        results[label].append((wall, rss))
        print(f'{label} run {index + 1}: rc={proc.returncode} wall={wall:.2f}s peakRSS={rss:.0f}MiB epub={size}', flush=True)
for label, values in results.items():
    print(f'{label} median: wall={statistics.median(v[0] for v in values):.2f}s '
          f'peakRSS={statistics.median(v[1] for v in values):.0f}MiB')
b = statistics.median(v[0] for v in results['base'])
c = statistics.median(v[0] for v in results['cand'])
print(f'wall change: {100 * (c - b) / b:+.1f}%')
