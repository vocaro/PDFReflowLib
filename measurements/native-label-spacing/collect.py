"""Accept exactly the two source-reviewed DGA word repairs under compatible capabilities."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
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


def repair(text):
    return text.replace('Protein, Dair y', 'Protein, Dairy').replace('Ve getables', 'Vegetables')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('before', 'after', 'output'):
        parser.add_argument('--' + name, required=True, type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    summary = json.loads((args.after / 'summary.json').read_text())
    assert summary['passed'] and len(summary['results']) == 8
    assert json.loads((args.before / 'summary.json').read_text())['passed']
    records = []
    for result in summary['results']:
        case = result['case']
        before, after = args.before / case, args.after / case
        comparison = compare(before, after, allow_different_converters=True)
        assert comparison['provenanceErrors'] == [], comparison
        assert comparison.get('pageMarkersEqual') is True, comparison
        assert comparison.get('changedImages') == [], comparison
        assert comparison.get('changedReportFields') == [], comparison
        expected_pages = [1] if case == 'dga-2025-2030' else []
        assert comparison.get('changedPages') == expected_pages, comparison
        old, new = before / (case + '.epub'), after / (case + '.epub')
        left, lm = read_pages(old)
        right, rm = read_pages(new)
        assert lm == rm and left.keys() == right.keys()
        for page in left:
            expected = left[page]
            if case == 'dga-2025-2030' and page == 1:
                assert 'Protein, Dair y' in expected['text'] and 'Ve getables' in expected['text']
                expected = json.loads(repair(json.dumps(expected)))
                write(args.output / 'dga-reviewed-page.json', {'before': left[page], 'after': right[page]})
            assert right[page] == expected, (case, page)
        # The standard comparator does not cover all inline markup/navigation. Require exact
        # XHTML bytes here as well, allowing only the same two literal text replacements.
        with zipfile.ZipFile(old) as a, zipfile.ZipFile(new) as b:
            names = {n for n in a.namelist() if n.endswith('.xhtml')}
            assert names == {n for n in b.namelist() if n.endswith('.xhtml')}
            for name in names:
                expected = a.read(name).decode()
                if case == 'dga-2025-2030':
                    expected = repair(expected)
                assert b.read(name).decode() == expected, (case, name)
            image_count = len([n for n in a.namelist() if n.startswith('EPUB/images/') and not n.endswith('/')])
        records.append({'case': case, 'accepted': True, 'strictDriftComparison': comparison,
                        'pageCount': len(left), 'imageCount': image_count,
                        'exactXHTMLWithOnlyReviewedReplacements': True,
                        'beforeEPUBSHA256': digest(old), 'afterEPUBSHA256': digest(new)})
        for label, directory in [('before', before), ('after', after)]:
            output = args.output / label / case
            output.mkdir(parents=True, exist_ok=True)
            for name in ('result.json', 'environment-probe.json', 'environment-probe.log',
                         'conversion-report.json', 'content-assessment.json', 'progress.log',
                         'epubcheck.log', 'memory-samples.json'):
                path = directory / name
                if path.exists():
                    (output / (name + '.gz')).write_bytes(gzip.compress(path.read_bytes(), mtime=0))
    write(args.output / 'comparison-summary.json', {'passed': True, 'cases': records})
    write(args.output / 'corpus-summary.json', summary)
    sources = [p for base in ('Sources', 'Tests', 'tools') for p in (ROOT / base).rglob('*')
               if p.is_file() and p.suffix in ('.swift', '.py', '.json', '.pdf')]
    sources += [ROOT / p for p in ('Package.swift', 'Package.resolved', 'corpus/regressions.json',
                                  'corpus/manifest.json', 'scripts/check-all.sh')]
    write(args.output / 'identity.json', {
        'baseRevision': 'a78aa7d', 'producerSHA256': digest(Path(__file__)),
        'sourceSHA256': {str(p.relative_to(ROOT)): digest(p) for p in sorted(sources)},
        'system': subprocess.check_output(['sw_vers'], text=True),
        'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True),
    })
    print('PASS: exactly two DGA spaces removed; all other XHTML, images, reports and markers unchanged.')


if __name__ == '__main__':
    main()
