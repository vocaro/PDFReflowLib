"""Compare complete corpus semantics and serialized spine packing against a retained baseline."""
import argparse
import collections
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from check_corpus_content import read_pages
spec = importlib.util.spec_from_file_location('epub_contracts', ROOT / 'tools/check-epubs.py')
contracts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(contracts)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def image_hashes(path):
    with zipfile.ZipFile(path) as archive:
        return {name: hashlib.sha256(archive.read(name)).hexdigest()
                for name in archive.namelist() if name.startswith('EPUB/images/')}


def spine_sizes(path):
    sizes, violations, atomic = [], [], 0
    with zipfile.ZipFile(path) as archive:
        for name in archive.namelist():
            if not name.startswith('EPUB/chapter-') or not name.endswith('.xhtml'):
                continue
            data = archive.read(name)
            size = len(data.split(b'<body>', 1)[1].split(b'</body>', 1)[0])
            sizes.append(size)
            try:
                atomic += contracts.check_spine_document(data)['oversizedAtomicBlock']
            except AssertionError as error:
                violations.append({'document': name, 'bodyBytes': size, 'reason': str(error)})
    return {'documents': len(sizes), 'maximumBodyBytes': max(sizes),
            'oversizedAtomicBlocks': atomic, 'violations': violations}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('before', 'after', 'logs', 'output'):
        parser.add_argument('--' + name, required=True, type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    summary = json.loads((args.after / 'summary.json').read_text())
    assert summary['passed'] and len(summary['results']) == 8
    rows = []
    for result in summary['results']:
        name = result['case']
        before, after = args.before / name, args.after / name
        old, new = before / (name + '.epub'), after / (name + '.epub')
        left, left_markers = read_pages(old)
        right, right_markers = read_pages(new)
        assert left_markers == right_markers
        old_images, new_images = image_hashes(old), image_hashes(new)
        assert collections.Counter(old_images.values()) == collections.Counter(new_images.values())
        for number in left:
            assert [old_images[n] for n in left[number]['images']] == [new_images[n] for n in right[number]['images']]
            assert left[number] == right[number], (name, number)
        old_sizes, new_sizes = spine_sizes(old), spine_sizes(new)
        assert not new_sizes['violations'], (name, new_sizes)
        contracts.check(new)  # Independently resolve all page and heading navigation targets.
        rows.append({'case': name, 'beforeEPUBSHA256': sha(old), 'afterEPUBSHA256': sha(new),
                     'identicalParsedPages': True, 'identicalImageBytesAndPageOrder': True,
                     'imageCount': len(new_images), 'before': old_sizes, 'after': new_sizes})
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
        'baseRevision': '294d0cd', 'producerSHA256': sha(Path(__file__)),
        'workingTreeSHA256': {str(p.relative_to(ROOT)): sha(p) for p in sources},
        'platform': subprocess.check_output(['sw_vers'], text=True).strip(),
        'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True).strip(),
        'baseline': 'Retained complete default-policy corpus from measurements/heading-body-regressions/record.md',
    })
    for filename in ('before-tests.log', 'progress-handoff-failure.log', 'release-gate.log', 'release-ios-tests.log'):
        (args.output / (filename + '.gz')).write_bytes(gzip.compress((args.logs / filename).read_bytes(), mtime=0))
    print(json.dumps(rows, indent=2))


if __name__ == '__main__':
    main()
