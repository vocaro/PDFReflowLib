"""Verify bounded drop-cap changes against complete retained corpus output."""
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
from check_corpus_content import read_pages, normalized


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
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
    assert summary['passed'] and len(summary['results']) == 8 and not summary['notRun']
    changed_flag_pages = [5, 7, 8, 9, 10, 13, 16, 26, 27, 28, 29, 30, 31, 46, 47, 49, 50, 53]
    rows = []
    reviewed = {}
    for result in summary['results']:
        name = result['case']
        old = args.before / name / (name + '.epub')
        new = args.after / name / (name + '.epub')
        left, lm = read_pages(old)
        right, rm = read_pages(new)
        assert lm == rm
        a, b = images(old), images(new)
        assert a == b, name
        changes = []
        for number in left:
            before, after = left[number], right[number]
            assert before['images'] == after['images']
            if before == after:
                continue
            assert name == 'gpo-our-flag-2003' and number in changed_flag_pages
            # Each former opening heading becomes prose, and all genuine headings remain.
            removed = [h for h in before['headings'] if h not in after['headings']]
            assert len(removed) == (2 if number == 27 else 1)
            assert [h for h in before['headings'] if h not in removed] == after['headings']
            old_rest, new_rest = before['text'], after['text']
            for heading in removed:
                assert any(heading in paragraph for paragraph in after['paragraphs'])
                assert old_rest.count(heading) == new_rest.count(heading) == 1
                old_rest = old_rest.replace(heading, '', 1)
                new_rest = new_rest.replace(heading, '', 1)
            # All remaining prose keeps its exact order. The newly adjacent source lines on
            # page 9 allow the existing vocabulary-based some-/times repair, visually reviewed.
            old_rest, new_rest = normalized(old_rest), normalized(new_rest)
            if number == 9:
                assert old_rest.count('some- times') == 1
                old_rest = old_rest.replace('some- times', 'sometimes', 1)
            assert old_rest == new_rest, (number, 'unrelated prose changed')
            # Only the spurious initial-letter subscripts disappear. Genuine fractions on
            # page 30 and every other script retain their full text and surrounding context.
            old_scripts = collections.Counter(json.dumps(s, sort_keys=True) for s in before['scripts'])
            new_scripts = collections.Counter(json.dumps(s, sort_keys=True) for s in after['scripts'])
            assert not new_scripts - old_scripts
            lost = [json.loads(s) for s, count in (old_scripts - new_scripts).items() for _ in range(count)]
            assert collections.Counter((s['tag'], s['text']) for s in lost) == collections.Counter(
                ('sub', heading[0]) for heading in removed)
            changes.append({'page': number, 'openingHeadingsConvertedToParagraphs': removed,
                            'removedInitialScripts': lost, 'remainingProseOrderUnchanged': True})
            reviewed[str(number)] = {'before': before, 'after': after}
        assert [c['page'] for c in changes] == (changed_flag_pages if name == 'gpo-our-flag-2003' else [])
        rows.append({'case': name, 'beforeEPUBSHA256': sha(old), 'afterEPUBSHA256': sha(new),
                     'imageCount': len(b), 'identicalImageBytesAndPageOrder': True,
                     'parsedPageCount': len(left), 'changes': changes})
        folder = args.output / name
        folder.mkdir(exist_ok=True)
        for filename in ('result.json', 'conversion-report.json', 'content-assessment.json',
                         'progress.log', 'memory-samples.json', 'epubcheck.log'):
            (folder / (filename + '.gz')).write_bytes(gzip.compress(
                (args.after / name / filename).read_bytes(), mtime=0))
    save(args.output / 'comparison-summary.json', rows)
    (args.output / 'flag-page-comparison.json.gz').write_bytes(gzip.compress(
        json.dumps(reviewed, ensure_ascii=False, indent=2).encode(), mtime=0))
    save(args.output / 'corpus-summary.json', summary)
    sources = sorted(p for base in ('Sources', 'Tests', 'tools') for p in (ROOT / base).rglob('*')
                     if p.is_file() and p.suffix in ('.swift', '.py', '.json', '.pdf'))
    sources += [ROOT / name for name in ('Package.swift', 'Package.resolved', 'corpus/manifest.json',
                                         'corpus/regressions.json', 'scripts/check-all.sh')]
    save(args.output / 'identity.json', {'baseRevision': 'bd62936', 'producerSHA256': sha(Path(__file__)),
         'workingTreeSHA256': {str(p.relative_to(ROOT)): sha(p) for p in sources},
         'platform': subprocess.check_output(['sw_vers'], text=True).strip(),
         'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True).strip()})
    for filename in ('before-tests.log', 'before-content.json', 'final-gate.log', 'final-ios-tests.log'):
        (args.output / (filename + '.gz')).write_bytes(gzip.compress((args.logs / filename).read_bytes(), mtime=0))
    print('Verified eight complete books, bounded opening changes and identical images.')


if __name__ == '__main__':
    main()
