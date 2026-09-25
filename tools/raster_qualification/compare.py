#!/usr/bin/env python3
"""Compare completed RasterHost runs at identical settings; differences do not prove accuracy."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from check_corpus_content import read_spine


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def images(path):
    with zipfile.ZipFile(path) as archive:
        return Counter(hashlib.sha256(archive.read(name)).hexdigest()
                       for name in archive.namelist() if name.startswith('EPUB/images/') and not name.endswith('/'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('baseline', type=Path)
    parser.add_argument('candidate', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--max-uncompressed-bytes', type=int, default=512 * 1024 * 1024)
    args = parser.parse_args()
    records = []; skipped = []
    for file in sorted(args.candidate.glob('*/metrics.json')):
        candidate = file.parent; baseline = args.baseline / candidate.name
        if not (baseline / 'metrics.json').exists():
            skipped.append({'run': candidate.name, 'reason': 'no matching baseline'}); continue
        a = json.loads((baseline / 'metrics.json').read_text()); b = json.loads(file.read_text())
        if a['status'] != 'completed' or b['status'] != 'completed':
            skipped.append({'run': candidate.name, 'reason': 'incomplete conversion'}); continue
        for key in ('case', 'rasterDPI', 'maximumRasterPixels', 'sourceSHA256', 'ocr', 'referenceImages'):
            if a[key] != b[key]: raise ValueError('incompatible setting: ' + key)
        if a.get('maximumOutputBytes', 512*1024*1024) != b.get('maximumOutputBytes', 512*1024*1024):
            raise ValueError('incompatible output budget')
        paths = [directory / (a['case'] + '.epub') for directory in (baseline, candidate)]
        pa, ma, _ = read_spine(paths[0], max_uncompressed_bytes=args.max_uncompressed_bytes)
        pb, mb, _ = read_spine(paths[1], max_uncompressed_bytes=args.max_uncompressed_bytes)
        changed = [n for n in sorted(pa.keys() | pb.keys()) if pa.get(n, {}).get('text') != pb.get(n, {}).get('text')]
        reports = [json.loads((directory / 'conversion-report.json').read_text()) for directory in (baseline, candidate)]
        for report in reports: report.pop('outputURL', None)
        ia, ib = images(paths[0]), images(paths[1])
        records.append({'run': candidate.name, 'baselineSHA256': digest(paths[0]), 'candidateSHA256': digest(paths[1]),
                        'changedTextPages': changed, 'pageMarkersEqual': ma == mb,
                        'reportsEqualExceptOutputURL': reports[0] == reports[1],
                        'encodedImagesEqualIgnoringNames': ia == ib,
                        'unmatchedBaselineImages': sum((ia-ib).values()),
                        'unmatchedCandidateImages': sum((ib-ia).values())})
    result = {'baseline': str(args.baseline), 'candidate': str(args.candidate),
              'scope': 'Observed same-setting differences, not accuracy or attribution to hardware.',
              'comparisons': records, 'skipped': skipped}
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(f'{len(records)} comparisons; {len(skipped)} skipped')


if __name__ == '__main__':
    main()
