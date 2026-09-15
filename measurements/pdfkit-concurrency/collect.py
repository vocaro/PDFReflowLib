"""Preserve concurrency campaigns and verify unchanged complete-corpus EPUB content."""
import argparse
from collections import Counter
import gzip
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tarfile
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[2]
BASE = 'd40fe2f437af9777211a84d8d88b1e154cc95969'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def add(archive, name, data):
    item = tarfile.TarInfo(name)
    item.size = len(data)
    item.mtime = 0
    archive.addfile(item, io.BytesIO(data))


def package_semantics(data):
    root = ET.fromstring(data)
    for element in root.iter():
        if element.tag == '{http://purl.org/dc/elements/1.1/}identifier':
            element.text = 'CONVERSION-IDENTIFIER'
        if element.get('property') == 'dcterms:modified':
            element.text = 'CONVERSION-TIMESTAMP'
    return ET.tostring(root)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ('scratch', 'before', 'after', 'output'):
        parser.add_argument('--' + key, type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    campaigns = ['release', 'native-before', 'native-after', 'sdk-only', 'native-debug']
    sources = {}
    campaign_rows = []
    with tarfile.open(args.output / 'campaigns.tar.gz', 'w:gz') as archive:
        for campaign in campaigns:
            folder = args.scratch / campaign
            meta = json.loads((folder / 'identity.json').read_text())
            assert digest((folder / 'probe').read_bytes()) == meta['binary']['sha256']
            results = json.loads((folder / 'results.json').read_text())
            for result in results:
                for log, identity in result['logs'].items():
                    data = (folder / result['case'] / log).read_bytes()
                    assert len(data) == identity['bytes'] and digest(data) == identity['sha256']
            for path, identity in meta['sources'].items():
                wanted = identity['sha256']
                if wanted in sources:
                    continue
                candidates = [(ROOT / path).read_bytes()]
                if path == 'tools/check_pdfkit_concurrency.py':
                    candidates += [p.read_bytes() for p in args.scratch.glob('runner-*.py')]
                historical = subprocess.run(['git', 'show', f'{BASE}:{path}'], cwd=ROOT, capture_output=True)
                if historical.returncode == 0:
                    candidates.append(historical.stdout)
                source = next((b for b in candidates if digest(b) == wanted), None)
                assert source is not None, (campaign, path, 'missing producer version')
                sources[wanted] = path
                add(archive, f'producers/{wanted}/{Path(path).name}', source)
            for path in sorted(folder.rglob('*')):
                if path.is_file() and path.name != 'probe':
                    add(archive, f'{campaign}/{path.relative_to(folder)}', path.read_bytes())
            counts = Counter((r['mode'], r['workers'], r['status']) for r in results)
            campaign_rows.append({'campaign': campaign, 'settings': meta['settings'],
                'outcomes': [{'mode': k[0], 'workers': k[1], 'status': k[2], 'processes': v} for k, v in sorted(counts.items())],
                'verifiedCompletedIterations': sum(r['result']['completed'] for r in results if r['status'] == 'passed'),
                'failures': [r['case'] for r in results if r['status'] != 'passed']})
    save(args.output / 'campaign-summary.json', campaign_rows)
    summary = json.loads((args.after / 'summary.json').read_text())
    assert summary['passed'] and len(summary['results']) == 8 and not summary['notRun']
    comparison = []
    with tarfile.open(args.output / 'corpus-receipts.tar.gz', 'w:gz') as receipts:
        for row in summary['results']:
            name = row['case']
            folders = [base / name for base in (args.before, args.after)]
            epubs = [folder / f'{name}.epub' for folder in folders]
            with zipfile.ZipFile(epubs[0]) as left, zipfile.ZipFile(epubs[1]) as right:
                assert sorted(left.namelist()) == sorted(right.namelist()), (name, 'entry names')
                unchanged = []
                for entry in left.namelist():
                    a, b = left.read(entry), right.read(entry)
                    if entry == 'EPUB/package.opf':
                        assert package_semantics(a) == package_semantics(b), (name, entry)
                    else:
                        assert a == b, (name, entry)
                        unchanged.append({'entry': entry, 'sha256': digest(a)})
                image_count = sum(n.startswith('EPUB/images/') and not n.endswith('/') for n in left.namelist())
            old, new = [json.loads((folder / 'result.json').read_text()) for folder in folders]
            reports = [json.loads((folder / 'conversion-report.json').read_text()) for folder in folders]
            for report in reports:
                report.pop('outputURL', None)
            assert reports[0] == reports[1], (name, 'conversion report')
            comparison.append({'case': name, 'pages': old['case']['pages'], 'images': image_count,
                'contentChecks': row['contentChecks'], 'beforeSeconds': old['conversionSeconds'],
                'afterSeconds': new['conversionSeconds'], 'beforeRSSBytes': old['converterPeakRSSBytes'],
                'afterRSSBytes': new['converterPeakRSSBytes'], 'unchangedEntries': unchanged})
            for label, folder in zip(['before', 'after'], folders):
                for file in ['result.json', 'conversion-report.json', 'content-assessment.json', 'progress.log', 'epubcheck.log']:
                    add(receipts, f'{label}/{name}/{file}', (folder / file).read_bytes())
    save(args.output / 'corpus-comparison.json', comparison)
    for file in ['full-gate.log', 'ios-tests.log']:
        path = args.scratch / file
        if path.exists():
            (args.output / (file + '.gz')).write_bytes(gzip.compress(path.read_bytes(), mtime=0))
    paths = ['Sources/PDFReflowLib/NativeTextReader.swift', 'Tests/PDFReflowLibTests/ConversionTests.swift',
             'scripts/check-all.sh', 'tools/check_pdfkit_concurrency.py', 'tools/probe-pdfkit-concurrency.swift',
             'tools/test_pdfkit_concurrency.py', 'measurements/pdfkit-concurrency/collect.py',
             'corpus/manifest.json', 'corpus/regressions.json']
    save(args.output / 'identity.json', {'baseline': BASE, 'implementationSHA256': {p: digest((ROOT / p).read_bytes()) for p in paths},
        'campaignArchiveSHA256': digest((args.output / 'campaigns.tar.gz').read_bytes()),
        'corpusReceiptArchiveSHA256': digest((args.output / 'corpus-receipts.tar.gz').read_bytes())})
    print(f'Compared {len(comparison)} complete books, {sum(r["pages"] for r in comparison)} pages, '
          f'{sum(r["images"] for r in comparison)} identical images.')


if __name__ == '__main__':
    main()
