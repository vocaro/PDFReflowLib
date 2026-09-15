"""Collect complete corpus receipts and compare heading suppression with a retained baseline."""
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

REVIEWED_CHANGES = {13, 46, 54, 75, 77, 103, 109}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def packed(source, target):
    target.write_bytes(gzip.compress(source.read_bytes(), mtime=0))


def image_hashes(path):
    with zipfile.ZipFile(path) as archive:
        return {name: hashlib.sha256(archive.read(name)).hexdigest()
                for name in archive.namelist() if name.startswith('EPUB/images/')}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('before', 'after', 'logs', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    summary = json.loads((args.after / 'summary.json').read_text())
    assert summary['passed'] and len(summary['results']) == 8
    rows, reviewed = [], {}
    for case in summary['results']:
        name = case['case']
        before, after = args.before / name, args.after / name
        old_book, new_book = before / (name + '.epub'), after / (name + '.epub')
        left, left_markers = read_pages(old_book)
        right, right_markers = read_pages(new_book)
        assert left_markers == right_markers
        old_images, new_images = image_hashes(old_book), image_hashes(new_book)
        assert collections.Counter(old_images.values()) == collections.Counter(new_images.values())
        changed, removed = [], 0
        for number, old_page in left.items():
            new_page = right[number]
            assert [old_images[n] for n in old_page['images']] == [new_images[n] for n in new_page['images']]
            if old_page == new_page:
                continue
            assert name == 'fed-explained-2021' and number in REVIEWED_CHANGES, (name, number)
            # Joining body lines may repair line-ending hyphens; other characters must survive.
            canonical = lambda value: ''.join(value.split()).replace('-', '')
            assert canonical(old_page['text']) == canonical(new_page['text'])
            lost = collections.Counter(old_page['headings']) - collections.Counter(new_page['headings'])
            assert not (collections.Counter(new_page['headings']) - collections.Counter(old_page['headings']))
            fixture = json.loads((ROOT / f'Tests/PDFReflowLibTests/fixtures/fed-{number}-layout.json').read_text())
            source_body = {line['text'] for line in fixture['lines'] if line['fontSize'] == 10}
            assert set(lost) <= source_body, (number, set(lost) - source_body)
            changed.append(number)
            removed += sum(lost.values())
            reviewed[str(number)] = {'before': old_page, 'after': new_page}
        rows.append({'case': name, 'beforeEPUBSHA256': sha(old_book), 'afterEPUBSHA256': sha(new_book),
                     'changedPages': changed, 'removedBodyHeadings': removed,
                     'beforeHeadings': sum(len(p['headings']) for p in left.values()),
                     'afterHeadings': sum(len(p['headings']) for p in right.values()),
                     'identicalImageBytesAndPageOrder': True, 'imageCount': len(new_images)})
        dest = args.output / name
        dest.mkdir(exist_ok=True)
        for filename in ('result.json', 'conversion-report.json', 'content-assessment.json',
                         'progress.log', 'memory-samples.json', 'epubcheck.log'):
            packed(after / filename, dest / (filename + '.gz'))
    write_json(args.output / 'comparison-summary.json', rows)
    write_json(args.output / 'reviewed-pages.json', reviewed)
    write_json(args.output / 'corpus-summary.json', summary)
    files = sorted(p for base in ('Sources', 'Tests', 'tools') for p in (ROOT / base).rglob('*')
                   if p.is_file() and p.suffix in ('.swift', '.py', '.json', '.pdf'))
    files += [ROOT / name for name in ('Package.swift', 'Package.resolved', 'corpus/manifest.json',
                                       'corpus/regressions.json', 'scripts/check-all.sh')]
    write_json(args.output / 'identity.json', {
        'baseRevision': '9be59c9', 'producerSHA256': sha(Path(__file__)),
        'workingTreeSHA256': {str(p.relative_to(ROOT)): sha(p) for p in files},
        'platform': subprocess.check_output(['sw_vers'], text=True).strip(),
        'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True).strip(),
        'baseline': 'Retained full default corpus run from measurements/local-header-regressions/record.md',
    })
    for filename in ('before-tests.log', 'before-content.json', 'intermediate-heading-failure.log',
                     'intermediate-content.json', 'release-gate.log', 'release-ios-tests.log'):
        packed(args.logs / filename, args.output / (filename + '.gz'))
    print(json.dumps(rows, indent=2))


if __name__ == '__main__':
    main()
