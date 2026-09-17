#!/usr/bin/env python3
"""Controls for the OCR normalization on real converter output.

usage: ocr_control.py <scratch-dir> <case> <ocr-page> <plain-page>

Converts the case once with the pinned options, then compares the EPUB with rewritten copies
of itself (ZIP metadata preserved) via check_reproducibility.compare_runs:
  ocr-text     every paragraph on <ocr-page> replaced, as Vision variance would   -> pass, reported
  plain-text   one paragraph on <plain-page> changed                             -> fail, page named
  ocr-image    an image referenced on <ocr-page> changed                          -> fail, entry named
  nav-heading  the first navigation heading entry outside OCR pages renamed      -> fail
Writes results/ocr-control-<case>.json and deletes the scratch output.
"""
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import zipfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import check_reproducibility as repro  # noqa: E402


def rewrite(source, target, change):
    with zipfile.ZipFile(source) as original, zipfile.ZipFile(target, 'w') as copy:
        for info in original.infolist():
            copy.writestr(info, change(info.filename, original.read(info.filename)))


def segment_span(text, page):
    start = text.index(f'id="page-{page}"')
    following = re.search(r'id="page-\d+"', text[start + 1:])
    return start, start + 1 + following.start() if following else len(text)


def main():
    scratch, case, ocr_page, plain_page = Path(sys.argv[1]), sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
    manifest = {c['id']: c for c in json.loads((ROOT / 'corpus/manifest.json').read_text())['documents']}
    work = scratch / f'ocr-control-{case}'
    work.mkdir(parents=True)
    epub, report_path = work / 'base.epub', work / 'base.json'
    with report_path.open('w') as out:
        subprocess.run([ROOT / '.build/release/pdf-reflow', ROOT / 'corpus/cache' / manifest[case]['filename'],
                        epub, *repro.PINNED], stdout=out, stderr=subprocess.DEVNULL, check=True)
    report = json.loads(report_path.read_text())
    package = repro.Package(epub)
    assert ocr_page in repro.ocr_pages(report) and plain_page not in repro.ocr_pages(report)
    owner = {page: name for name in package.spine
             for page in map(int, re.findall(r'id="page-(\d+)"', package.entries[name].decode()))}

    def paragraphs(page, replace):
        def change(name, data):
            if name != owner[page]:
                return data
            text = data.decode()
            start, end = segment_span(text, page)
            return (text[:start] + replace(text[start:end]) + text[end:]).encode()
        return change

    image = re.search(r'src="(images/[^"]+)"', package.segments[ocr_page]).group(1)
    headings = [m for m in re.finditer(r'<a href="([^"#]*)#(heading-[^"]+)">([^<]+)</a>',
                                       package.entries[package.nav].decode())
                if package.id_pages.get(m.group(2)) not in repro.ocr_pages(report)]
    controls = {
        'ocr-text': paragraphs(ocr_page, lambda s: re.sub(r'<p>.*?</p>', '<p>An INOD gseg id</p>', s)),
        'plain-text': paragraphs(plain_page, lambda s: re.sub(r'<p>', '<p>CHANGED ', s, count=1)),
        'ocr-image': lambda name, data: data + b'\0' if name == 'EPUB/' + image else data,
        'nav-heading': lambda name, data: (data.replace(f'>{headings[0].group(3)}</a>'.encode(), b'>Renamed</a>', 1)
                                           if name == package.nav else data),
    }
    results = {'case': case, 'ocrPage': ocr_page, 'plainPage': plain_page, 'image': image,
               'baseSHA256': repro.digest(epub), 'ocrPages': sorted(repro.ocr_pages(report)), 'controls': {}}
    for name, change in controls.items():
        mutated = work / f'{name}.epub'
        rewrite(epub, mutated, change)
        outcome = repro.compare_runs(epub, mutated, report, report)
        results['controls'][name] = {key: outcome.get(key) for key in
                                     ('passed', 'byteIdentical', 'differingEntries', 'nonOCRChangedPages',
                                      'ocrChangedPages', 'failures', 'allowedDifferences')}
        print(name, 'passed' if outcome['passed'] else 'failed', outcome['failures'], outcome['allowedDifferences'])
        mutated.unlink()
    (HERE / 'results').mkdir(exist_ok=True)
    (HERE / 'results' / f'ocr-control-{case}.json').write_text(json.dumps(results, indent=2) + '\n')
    shutil.rmtree(work)


if __name__ == '__main__':
    main()
