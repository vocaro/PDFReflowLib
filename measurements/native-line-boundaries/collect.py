"""Verify the two reviewed native spacing changes against complete retained corpus output."""
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
from check_corpus_content import read_pages


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def images(path):
    with zipfile.ZipFile(path) as archive:
        return {n: hashlib.sha256(archive.read(n)).hexdigest()
                for n in archive.namelist() if n.startswith('EPUB/images/')}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('before', 'after', 'logs', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    summary = json.loads((args.after / 'summary.json').read_text())
    assert summary['passed'] and len(summary['results']) == 8
    rows = []
    for result in summary['results']:
        name = result['case']
        before, after = args.before / name, args.after / name
        old, new = before / (name + '.epub'), after / (name + '.epub')
        left, lm = read_pages(old)
        right, rm = read_pages(new)
        assert lm == rm
        a, b = images(old), images(new)
        assert collections.Counter(a.values()) == collections.Counter(b.values())
        changed = []
        for number in left:
            assert [a[n] for n in left[number]['images']] == [b[n] for n in right[number]['images']]
            if left[number] == right[number]:
                continue
            replacements = {('dga-2025-2030', 1): ('GuidelinesFor Americans', 'Guidelines For Americans'),
                            ('gpo-our-flag-2003', 31): ('Burial Flagfor a Veteran', 'Burial Flag for a Veteran')}
            assert (name, number) in replacements, (name, number)
            original, corrected = replacements[name, number]
            assert original in left[number]['text']
            expected = json.loads(json.dumps(left[number]).replace(original, corrected))
            assert right[number] == expected
            changed.append(number)
            write_json(args.output / (name + '-reviewed-title.json'), {'before': left[number], 'after': right[number]})
        rows.append({'case': name, 'changedPages': changed, 'beforeEPUBSHA256': sha(old),
                     'afterEPUBSHA256': sha(new), 'imageCount': len(b),
                     'identicalImageBytesAndPageOrder': True, 'parsedPageCount': len(left)})
        folder = args.output / name
        folder.mkdir(exist_ok=True)
        for filename in ('result.json', 'conversion-report.json', 'content-assessment.json',
                         'progress.log', 'memory-samples.json', 'epubcheck.log'):
            (folder / (filename + '.gz')).write_bytes(gzip.compress((after / filename).read_bytes(), mtime=0))
    write_json(args.output / 'comparison-summary.json', rows)
    write_json(args.output / 'corpus-summary.json', summary)
    sources = sorted(p for base in ('Sources', 'Tests', 'tools') for p in (ROOT / base).rglob('*')
                     if p.is_file() and p.suffix in ('.swift', '.py', '.json', '.pdf'))
    sources += [ROOT / name for name in ('Package.swift', 'Package.resolved', 'corpus/manifest.json',
                                         'corpus/regressions.json', 'scripts/check-all.sh')]
    write_json(args.output / 'identity.json', {
        'baseRevision': 'ff334ce', 'producerSHA256': sha(Path(__file__)),
        'workingTreeSHA256': {str(p.relative_to(ROOT)): sha(p) for p in sources},
        'platform': subprocess.check_output(['sw_vers'], text=True).strip(),
        'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True).strip(),
        'baseline': 'Retained complete default-policy corpus from measurements/spine-packing/record.md',
    })
    for filename in ('before-tests.log', 'before-content.json', 'before-flag-content.json', 'release-gate.log', 'release-ios-tests.log'):
        (args.output / (filename + '.gz')).write_bytes(gzip.compress((args.logs / filename).read_bytes(), mtime=0))
    print(json.dumps(rows, indent=2))


if __name__ == '__main__':
    main()
