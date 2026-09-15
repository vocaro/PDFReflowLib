"""Retain #21 cancellation receipts and compare corpus output with the previous gate."""
import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path
import tarfile
import zipfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--gate', type=Path, required=True)
    parser.add_argument('--logs', type=Path, required=True)
    args = parser.parse_args()
    output = Path(__file__).resolve().parent
    summary = json.loads((args.gate / 'corpus/summary.json').read_text())
    assert summary['passed'] and len(summary['results']) == 8 and not summary['notRun']
    previous = json.loads((ROOT / 'measurements/pdfkit-concurrency/corpus-comparison.json').read_text())
    rows = []
    for book in previous:
        name = book['case']
        with zipfile.ZipFile(args.gate / 'corpus' / name / (name + '.epub')) as epub:
            expected = {entry['entry']: entry['sha256'] for entry in book['unchangedEntries']}
            assert set(epub.namelist()) == set(expected) | {'EPUB/package.opf'}, name
            for entry, checksum in expected.items():
                assert hashlib.sha256(epub.read(entry)).hexdigest() == checksum, (name, entry)
        rows.append({'case': name, 'identicalEntries': len(expected), 'identicalImages': book['images'],
                     'pages': book['pages']})
    sources = ['Sources/PDFReflowLib/NativeTextReader.swift',
               'Tests/PDFReflowLibTests/ExtractionCancellationTests.swift',
               'measurements/extraction-cancellation/collect.py']
    record = {'baseline': '58da4de7c1481dba7455cc9df88eaf813fe9ee3c',
              'sourceSHA256': {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in sources},
              'comparison': rows,
              'comparisonExclusion': 'EPUB/package.opf has dynamic identifier/timestamp; not compared here.',
              'corpus': summary}
    (output / 'results.json').write_text(json.dumps(record, indent=2) + '\n')
    with tarfile.open(output / 'receipts.tar.gz', 'w:gz') as archive:
        for path in sorted(args.gate.rglob('*')):
            if path.is_file() and path.suffix in {'.json', '.log'}:
                data = path.read_bytes()
                info = tarfile.TarInfo(str(path.relative_to(args.gate)))
                info.size, info.mtime = len(data), 0
                archive.addfile(info, io.BytesIO(data))
    for name in ['before', 'after', 'full-gate', 'ios']:
        path = args.logs / ('pdfreflow-cancellation-' + name + '.log')
        (output / (name + '.log.gz')).write_bytes(gzip.compress(path.read_bytes(), mtime=0))
    print(f'Compared {len(rows)} books, {sum(r["pages"] for r in rows)} pages, '
          f'{sum(r["identicalImages"] for r in rows)} identical images.')


if __name__ == '__main__':
    main()
