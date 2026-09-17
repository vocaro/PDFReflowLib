"""Record desired DGA layout checks, including failures; never turn them into a passing baseline."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from check_corpus_content import read_pages
from compare_conversion_runs import compare


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n')


def satisfies(text, check):
    if check['kind'] == 'text':
        return check['value'] in text
    assert check['kind'] == 'order'
    cursor = 0
    for phrase in check['value']:
        position = text.find(phrase, cursor)
        if position < 0:
            return False
        cursor = position + len(phrase)
    return True


def intersects(a, b):
    return a[0] < b[0] + b[2] and b[0] < a[0] + a[2] and a[1] < b[1] + b[3] and b[1] < a[1] + a[3]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('baseline', 'evaluation', 'source', 'output'):
        parser.add_argument('--' + name, required=True, type=Path)
    parser.add_argument('--check', action='store_true', help='exit 1 if desired layout checks fail')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    expectations = json.loads(Path(__file__).with_name('expectations.json').read_text())
    comparison = compare(args.baseline, args.evaluation, allow_different_converters=True)
    assert comparison['passed'], comparison
    result = json.loads((args.evaluation / 'result.json').read_text())
    assert result['case']['sha256'] == expectations['sourceSHA256']
    epub = args.evaluation / 'dga-2025-2030.epub'
    pages, markers = read_pages(epub)
    assert set(pages) == set(range(1, 11)) and markers == list(range(1, 11))
    old = args.baseline / epub.name
    with zipfile.ZipFile(old) as a, zipfile.ZipFile(epub) as b:
        names = {n for n in a.namelist() if n.endswith('.xhtml')}
        assert names == {n for n in b.namelist() if n.endswith('.xhtml')}
        assert all(a.read(n) == b.read(n) for n in names)
        inventories = {n: hashlib.sha256(b.read(n)).hexdigest() for n in b.namelist()
                       if n.endswith('.xhtml') or n.startswith('EPUB/images/')}
    # Independent rejection controls: missing text and reversed sections cannot pass.
    assert satisfies('alpha beta', {'kind': 'text', 'value': 'alpha beta'})
    assert not satisfies('alpha gamma beta', {'kind': 'text', 'value': 'alpha beta'})
    assert satisfies('alpha beta', {'kind': 'order', 'value': ['alpha', 'beta']})
    assert not satisfies('beta alpha', {'kind': 'order', 'value': ['alpha', 'beta']})
    checks = [dict(check, passed=satisfies(pages[check['page']]['text'], check))
              for check in expectations['checks']]
    geometry = []
    for page in (3, 6):
        raw = json.loads((args.source / f'page{page}-unclustered.json').read_text())
        clustered = json.loads((args.source / f'page{page}.json').read_text())
        assert raw['sourceSHA256'] == clustered['sourceSHA256'] == expectations['sourceSHA256']
        assert raw['lines'] == clustered['lines']
        candidates = [line['text'] for line in raw['lines']
                      if not any(intersects(line['rect'], rect) for rect in raw['graphics'])]
        captured = [line['text'] for line in raw['lines'] if line['text'] in candidates
                    and any(intersects(line['rect'], rect) for rect in clustered['graphics'])]
        geometry.append({'page': page, 'rawRectangleCount': len(raw['graphics']),
                         'clusteredRectangles': clustered['graphics'],
                         'unpaintedCandidateLines': candidates,
                         'candidateLinesInsideClusterHull': captured,
                         'scope': 'Rectangle-overlap diagnostic, not an ownership or safety classifier.'})
    for path in sorted(args.source.glob('page*.json')):
        payload = json.loads(path.read_text())
        assert payload['sourceSHA256'] == expectations['sourceSHA256']
        (args.output / (path.name + '.gz')).write_bytes(gzip.compress(path.read_bytes(), mtime=0))
    for label, directory in [('baseline', args.baseline), ('current', args.evaluation)]:
        destination = args.output / label
        destination.mkdir(exist_ok=True)
        for name in ('result.json', 'conversion-report.json', 'environment-probe.json',
                     'environment-probe.log', 'progress.log', 'memory-samples.json',
                     'epubcheck.log', 'content-assessment.json'):
            path = directory / name
            if path.exists():
                (destination / (name + '.gz')).write_bytes(gzip.compress(path.read_bytes(), mtime=0))
    write(args.output / 'comparison.json', dict(comparison, exactXHTMLEqual=True))
    write(args.output / 'parsed-pages.json', pages)
    write(args.output / 'geometry.json', geometry)
    write(args.output / 'asset-identities.json', inventories)
    audit = {'qualifiedForFullLayout': False, 'allSampleChecksPass': all(c['passed'] for c in checks),
             'passedChecks': sum(c['passed'] for c in checks), 'totalChecks': len(checks),
             'checks': checks, 'scope': expectations['basis'], 'negativeControlsPassed': True}
    write(args.output / 'audit.json', audit)
    source_files = [p for p in (ROOT / 'Sources').rglob('*.swift')]
    source_files += [ROOT / 'tools/capture-layout-fixture.swift', Path(__file__),
                     Path(__file__).with_name('expectations.json'), Path(__file__).with_name('unclustered.patch')]
    write(args.output / 'identity.json', {
        'baseRevision': '2233d5f', 'sourceSHA256': expectations['sourceSHA256'],
        'converterSHA256': result['converterSHA256'], 'outputSHA256': digest(epub),
        'sourceFiles': {str(p.relative_to(ROOT)): digest(p) for p in sorted(source_files)},
        'sourceRenderSHA256': {p.name: digest(p) for p in sorted(args.source.glob('dga-*.png'))},
        'captureArtifacts': {p.name: digest(p) for p in
            (args.source.parent / name for name in ('capture', 'capture-unclustered', 'UnclusteredGraphicsReader.swift'))},
    })
    print(f"Captured {len(checks)} desired checks: {audit['passedChecks']} pass; "
          f"{len(checks) - audit['passedChecks']} fail. Full layout remains unqualified.")
    return 1 if args.check and not audit['allSampleChecksPass'] else 0


if __name__ == '__main__':
    raise SystemExit(main())
