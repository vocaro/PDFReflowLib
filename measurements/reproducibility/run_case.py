#!/usr/bin/env python3
"""Evidence driver for the #68 record: one repeat check per invocation, outputs discarded.

usage: run_case.py <scratch-dir> <case> <concurrent|sequential> [--converter PATH] [--tag TAG]

Refuses to start with less than 5 GiB free, runs tools/check_reproducibility.py, copies the
case result.json to results/<case>-<mode>[-TAG].json with warning tallies, prints a one-line
summary, and deletes the scratch output (including EPUBs kept on failure after copying their
hashes; rerun with --keep to inspect a failure).
"""
import argparse
from collections import Counter
import json
from pathlib import Path
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('scratch', type=Path)
    parser.add_argument('case')
    parser.add_argument('mode', choices=['concurrent', 'sequential'])
    parser.add_argument('--converter', type=Path, default=ROOT / '.build/release/pdf-reflow')
    parser.add_argument('--tag', default='')
    parser.add_argument('--keep', action='store_true')
    args = parser.parse_args()
    free = shutil.disk_usage(args.scratch.parent if not args.scratch.exists() else args.scratch).free
    if free < 5 * 1024 ** 3:
        sys.exit(f'only {free / 1024 ** 3:.1f} GiB free; stopping')
    name = f'{args.case}-{args.mode}' + (f'-{args.tag}' if args.tag else '')
    output = args.scratch / name
    code = subprocess.run([sys.executable, ROOT / 'tools/check_reproducibility.py', '--converter', args.converter,
                           '--output', output, '--case', args.case, '--mode', args.mode]).returncode
    record = json.loads((output / args.case / 'result.json').read_text())
    tallies = []
    for index in (1, 2):
        report = output / args.case / f'run-{index}.json'
        warnings = json.loads(report.read_text()).get('warnings', []) if report.stat().st_size else []
        counts = Counter(w['code'] for w in warnings)
        tallies.append({'warnings': len(warnings), 'byCode': dict(sorted(counts.items())),
                        'structureFallbackPages': len({w['page'] for w in warnings if w['code'] == 'structureFallback'})})
    record['warningTallies'] = tallies
    record['freeBytesBefore'] = free
    (HERE / 'results').mkdir(exist_ok=True)
    (HERE / 'results' / (name + '.json')).write_text(json.dumps(record, indent=2) + '\n')
    print(f"{name}: exit {code} passed {record['passed']} byteIdentical {record.get('byteIdentical')} "
          f"wall {record['wallSeconds']}s runs {[r['seconds'] for r in record['runs']]} "
          f"sha {record.get('epubSHA256', ['-'])[0][:16]} ocrPages {record.get('ocrPages')} "
          f"structureFallback {[t['structureFallbackPages'] for t in tallies]} "
          f"allowed {record.get('allowedDifferences')} errors {record['errors']}", flush=True)
    if not args.keep:
        shutil.rmtree(output)
    return code


if __name__ == '__main__':
    raise SystemExit(main())
