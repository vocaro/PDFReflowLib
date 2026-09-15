"""Compare the rejected #18 OCR-heading prototype across complete corpus conversions.

Run with prototype.patch applied to reproduce the recorded implementation hashes.
"""
import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path
import sys
import tarfile
import zipfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from check_corpus_content import read_pages


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--before', type=Path, required=True)
    parser.add_argument('--gate', type=Path, required=True)
    args = parser.parse_args()
    output = Path(__file__).resolve().parent
    summary = json.loads((args.gate / 'corpus/summary.json').read_text())
    assert summary['passed'] and len(summary['results']) == 8 and not summary['notRun']
    rows = []
    for item in summary['results']:
        name = item['case']
        before = args.before / name / (name + '.epub')
        after = args.gate / 'corpus' / name / (name + '.epub')
        left, lm = read_pages(before)
        right, rm = read_pages(after)
        assert lm == rm
        with zipfile.ZipFile(before) as old, zipfile.ZipFile(after) as new:
            images = [n for n in old.namelist() if n.startswith('EPUB/images/')]
            assert images == [n for n in new.namelist() if n.startswith('EPUB/images/')]
            assert all(old.read(n) == new.read(n) for n in images), name
        report = json.loads((args.gate / 'corpus' / name / 'conversion-report.json').read_text())
        recognized = {w['page'] for w in report['warnings'] if w['code'] == 'ocrUsed'}
        changed = []
        for page in left:
            if left[page] == right[page]:
                continue
            assert page in recognized, (name, page, 'native page changed')
            for key in ('text', 'images', 'scripts'):
                assert left[page][key] == right[page][key], (name, page, key)
            assert not right[page]['headings'], (name, page)
            changed.append({'page': page, 'beforeHeadings': left[page]['headings'],
                            'afterParagraphs': right[page]['paragraphs']})
        rows.append({'case': name, 'pages': len(left), 'identicalImages': len(images),
                     'beforeEPUBSHA256': sha(before), 'afterEPUBSHA256': sha(after),
                     'changedOCRPages': changed})
    sources = ['Sources/PDFReflowLib/LayoutReconstructor.swift', 'Sources/PDFReflowLib/OCRReader.swift',
               'Tests/PDFReflowLibTests/OCRHeadingTests.swift', 'Tests/PDFReflowLibTests/SourceLayoutFixture.swift',
               'Tests/PDFReflowLibTests/fixtures/cdc-13-ocr-layout.json', 'corpus/regressions.json',
               'tools/capture-ocr-layout-fixture.swift', 'measurements/ocr-headings/collect.py']
    result = {'baseline': '6992fb3', 'status': 'Rejected: demotes the genuine CDC page-15 title. No runtime fix retained.',
              'sourceSHA256': {p: sha(ROOT / p) for p in sources},
              'comparison': rows, 'corpus': summary,
              'scope': 'Every page has identical text, inline scripts and images; heading/paragraph changes are restricted to fresh OCR pages. Navigation remains covered by the gate.'}
    (output / 'results.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    with tarfile.open(output / 'receipts.tar.gz', 'w:gz') as archive:
        for path in sorted(args.gate.rglob('*')):
            if path.is_file() and path.suffix in {'.json', '.log'}:
                data = path.read_bytes()
                info = tarfile.TarInfo(str(path.relative_to(args.gate)))
                info.size, info.mtime = len(data), 0
                archive.addfile(info, io.BytesIO(data))
    for name in ('before-tests', 'after-tests', 'full-gate', 'ios'):
        path = Path('/tmp/ocr-headings-' + name + '.log')
        (output / (name + '.log.gz')).write_bytes(gzip.compress(path.read_bytes(), mtime=0))
    print(json.dumps(rows, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
