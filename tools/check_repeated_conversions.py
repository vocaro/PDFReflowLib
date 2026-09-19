#!/usr/bin/env python3
"""Bound PDFKit's attributed-text leak across repeated conversions in one process (#4).

Converts one checksum-verified corpus source several times in one process through the public
API (`measurements/pdfkit-repeated-conversions/measure.sh`), with pinned packaging, and counts
`leaks` after every round. Fails when a round's EPUB differs from the first round's, or when the
leaked objects added per conversion exceed the per-page ceiling. PDFKit leaks every attributed
string it returns (FB24783799); the library requests one per page, so the count grows with pages,
not lines. Byte totals are reported, not gated: they are the page text itself and vary by a few
percent from run to run. macOS only; the Simulator has no `leaks`.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
MEASURE = ROOT / 'measurements/pdfkit-repeated-conversions/measure.sh'


def evaluate(lines, pages, maximum_objects_per_page):
    """Checks the harness output; returns a summary or raises ValueError."""
    records = [json.loads(line) for line in lines if line.startswith('{')]
    conversions = [r for r in records if 'input' in r]
    counts = []
    for record in records:
        if 'leaks' in record:
            match = re.search(r'(\d+) leaks? for (\d+) total leaked bytes', record['leaks'])
            if match is None:
                raise ValueError(f'Unreadable leaks summary: {record["leaks"]!r}')
            counts.append((int(match[1]), int(match[2])))
    if len(conversions) < 2 or len(counts) != len(conversions):
        raise ValueError('Expected one leaks count after each of at least two conversions')
    if len({r['sha256'] for r in conversions}) != 1:
        raise ValueError('Repeated conversions in one process produced different EPUBs')
    rounds = len(counts) - 1
    objects = (counts[-1][0] - counts[0][0]) / rounds
    leaked_bytes = (counts[-1][1] - counts[0][1]) / rounds
    summary = {'conversions': len(conversions), 'pages': pages,
               'leakedObjectsPerConversion': objects, 'leakedBytesPerConversion': leaked_bytes,
               'ceilingObjectsPerConversion': maximum_objects_per_page * pages}
    if objects > maximum_objects_per_page * pages:
        raise ValueError(f'{objects:.0f} leaked objects per conversion exceed '
                         f'{maximum_objects_per_page} per page ({summary["ceilingObjectsPerConversion"]})')
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--case', default='fed-explained-2021')
    parser.add_argument('--rounds', type=int, default=3)
    parser.add_argument('--maximum-leaked-objects-per-page', type=int, default=30)
    args = parser.parse_args()
    if args.rounds < 2:
        parser.error('at least two rounds are needed to measure growth')
    case = next((c for c in json.loads((ROOT / 'corpus/manifest.json').read_text())['documents']
                 if c['id'] == args.case), None)
    if case is None:
        parser.error(f'unknown case {args.case}')
    source = ROOT / 'corpus/cache' / case['filename']
    if source.stat().st_size != case['bytes']:
        raise ValueError(f'{args.case} source byte count mismatch')
    with source.open('rb') as stream:
        if hashlib.file_digest(stream, 'sha256').hexdigest() != case['sha256']:
            raise ValueError(f'{args.case} source checksum mismatch')
    environment = dict(os.environ, LEAKS='1')
    environment.pop('SIMULATOR', None)
    result = subprocess.run(['sh', str(MEASURE), str(args.rounds), str(source)],
                            env=environment, capture_output=True, text=True, check=True)
    summary = evaluate(result.stdout.splitlines(), case['pages'], args.maximum_leaked_objects_per_page)
    print(json.dumps(summary, sort_keys=True))
    print(f'PASS repeated-conversion leak gate for {args.case} (macOS; not an iOS device budget)')


if __name__ == '__main__':
    main()
