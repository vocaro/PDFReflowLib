"""Compare complete tag-enabled conversions with a9d8fd5; recheck source contracts."""
import argparse
import collections
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from check_corpus_content import check_evaluation, read_pages


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n')


def compressed(path, value):
    path.write_bytes(gzip.compress(json.dumps(value, indent=2, ensure_ascii=False).encode(), mtime=0))


def images(path):
    with zipfile.ZipFile(path) as archive:
        return {n: hashlib.sha256(archive.read(n)).hexdigest()
                for n in archive.namelist() if n.startswith('EPUB/images/')}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for field in ('before', 'after', 'logs', 'output'):
        parser.add_argument('--' + field, type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    summary = json.loads((args.after / 'summary.json').read_text())
    assert summary['passed'] and len(summary['results']) == 8 and not summary['notRun']
    cases = {c['id']: c for c in json.loads((ROOT / 'corpus/manifest.json').read_text())['documents']}
    contracts = {c['id']: c for c in json.loads((ROOT / 'corpus/regressions.json').read_text())['cases']}
    compared, changed, baseline, assessments = [], {}, [], []
    for row in summary['results']:
        name = row['case']
        old, new = [directory / name / (name + '.epub') for directory in (args.before, args.after)]
        left, lm = read_pages(old)
        right, rm = read_pages(new)
        assert lm == rm and left.keys() == right.keys()
        assert images(old) == images(new), (name, 'image bytes')
        changes = {}
        for page in left:
            a, b = left[page], right[page]
            assert a['images'] == b['images'], (name, page, 'image ownership')
            assert collections.Counter((s['tag'], s['text']) for s in a['scripts']) == collections.Counter(
                (s['tag'], s['text']) for s in b['scripts']), (name, page, 'script content')
            old_text = a['text']
            if name == 'faa-phak-8083-25c' and page == 325:
                # Source has a line-ending low-/level; logical column order makes it adjacent.
                aw, bw = collections.Counter(old_text.split()), collections.Counter(b['text'].split())
                assert aw - bw == collections.Counter({'low-': 1, 'level': 1})
                assert bw - aw == collections.Counter({'low-level': 1})
            elif name == 'gpo-our-flag-2003' and page == 30:
                assert old_text.count('flag- pole') == 1
                assert old_text.replace('flag- pole', 'flagpole') == b['text']
            elif name == 'faa-phak-8083-25c' and page in (50, 191):
                assert collections.Counter(old_text.split()) == collections.Counter(b['text'].split())
            else:
                assert old_text == b['text'], (name, page, 'unreviewed text/order change')
            if a != b:
                assert name in ('faa-phak-8083-25c', 'fed-explained-2021', 'gpo-our-flag-2003')
                changes[page] = {'before': a, 'after': b}
        changed[name] = changes
        assessment = check_evaluation(cases[name], contracts[name], args.after / name)
        assert assessment['passed'], assessment
        assessments.append(assessment)
        baseline.append(check_evaluation(cases[name], contracts[name], args.before / name))
        folder = args.output / name
        folder.mkdir(exist_ok=True)
        save(folder / 'content-assessment.json', assessment)
        for filename in ('result.json', 'conversion-report.json', 'progress.log', 'memory-samples.json', 'epubcheck.log'):
            (folder / (filename + '.gz')).write_bytes(gzip.compress((args.after / name / filename).read_bytes(), mtime=0))
        measured = json.loads((args.after / name / 'result.json').read_text())
        prior = json.loads((args.before / name / 'result.json').read_text())
        compared.append({'case': name, 'beforeEPUBSHA256': sha(old), 'afterEPUBSHA256': sha(new),
            'imageCount': len(images(new)), 'identicalImageBytesAndPageOrder': True,
            'parsedPages': len(right), 'changedPages': list(changes),
            'seconds': measured['conversionSeconds'], 'peakRSSBytes': measured['converterPeakRSSBytes'],
            'baselinePeakRSSBytes': prior['converterPeakRSSBytes']})
    save(args.output / 'comparison-summary.json', compared)
    compressed(args.output / 'page-comparison.json.gz', changed)
    save(args.output / 'before-content.json', baseline)
    summary['results'] = assessments
    summary['contractRecheck'] = 'Current source contracts rechecked against the completed conversions.'
    save(args.output / 'corpus-summary.json', summary)
    sources = sorted(p for base in ('Sources', 'Tests', 'tools') for p in (ROOT / base).rglob('*')
                     if p.is_file() and p.suffix in ('.swift', '.py', '.json', '.pdf'))
    sources += [ROOT / name for name in ('Package.swift', 'Package.resolved', 'corpus/manifest.json',
        'corpus/regressions.json', 'scripts/check-all.sh', 'measurements/structure-tags/eager-structure-reader.swift')]
    save(args.output / 'identity.json', {'baseRevision': 'a9d8fd5', 'producerSHA256': sha(Path(__file__)),
        'workingTreeSHA256': {str(p.relative_to(ROOT)): sha(p) for p in sources},
        'platform': subprocess.check_output(['sw_vers'], text=True).strip(),
        'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True).strip()})
    for filename in ('final-gate.log', 'final-ios-tests.log', 'test3.log', 'eager-index.log'):
        (args.output / (filename + '.gz')).write_bytes(gzip.compress((args.logs / filename).read_bytes(), mtime=0))
    print('Compared eight complete books; images/scripts retained; all reviewed content contracts pass.')


if __name__ == '__main__':
    main()
