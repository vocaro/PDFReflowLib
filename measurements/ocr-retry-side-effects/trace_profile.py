#!/usr/bin/env python3
"""Resident and footprint profile of an evaluation's memory samples, by stage and page range (#129).

usage: trace_profile.py <evaluation dir>... [--bucket 20]

For each run: the maximum sampled resident size and physical footprint in MiB, and where each
occurs, then per page bucket of the recognition pass (`recognizing`/`extracting` samples) the
maximum of each, then the reconstruction pass maximum. Samples are 100 ms apart, so short spikes
are missed (the receipt's wait4 peak is authoritative for the peak itself).
"""
import json
import re
import sys
from pathlib import Path

MIB = 1 << 20


def main():
    args = sys.argv[1:]
    bucket = 20
    if '--bucket' in args:
        i = args.index('--bucket'); bucket = int(args[i + 1]); del args[i:i + 2]
    runs = []
    for directory in args:
        samples = json.loads((Path(directory) / 'memory-samples.json').read_text())
        receipt = json.loads((Path(directory) / 'result.json').read_text())
        rows = {}
        recon = [0, 0]
        top_r = max(samples, key=lambda s: s['residentBytes'])
        top_f = max(samples, key=lambda s: s['physicalFootprintBytes'])
        for s in samples:
            m = re.search(r'(recognizing|extracting|reconstructing|packaging|writing)\D*page (\d+)', s['progress'])
            if not m:
                continue
            r, f = s['residentBytes'] / MIB, s['physicalFootprintBytes'] / MIB
            if m.group(1) in ('recognizing', 'extracting'):
                key = (int(m.group(2)) - 1) // bucket
                row = rows.setdefault(key, [0, 0])
                row[0] = max(row[0], r); row[1] = max(row[1], f)
            else:
                recon[0] = max(recon[0], r); recon[1] = max(recon[1], f)
        runs.append((directory, receipt, rows, recon, top_r, top_f))
    for directory, receipt, rows, recon, top_r, top_f in runs:
        print(Path(directory).name, f"wait4 peak {receipt['converterPeakRSSBytes'] / MIB:.0f} MiB,",
              f"{receipt['conversionSeconds']:.0f} s; sampled max resident {top_r['residentBytes'] / MIB:.0f}",
              f"({top_r['progress']}), footprint {top_f['physicalFootprintBytes'] / MIB:.0f} ({top_f['progress']})")
    keys = sorted({k for run in runs for k in run[2]})
    print('pages     ' + ''.join(f'{Path(r[0]).name[-14:]:>22}' for r in runs) + '   (resident/footprint MiB)')
    for k in keys:
        cells = ''.join(f"{('%.0f/%.0f' % tuple(r[2][k])) if k in r[2] else '-':>22}" for r in runs)
        print(f'{k * bucket + 1:4}-{(k + 1) * bucket:<4} ' + cells)
    print('reconstr. ' + ''.join(f"{'%.0f/%.0f' % tuple(r[3]):>22}" for r in runs))


if __name__ == '__main__':
    main()
