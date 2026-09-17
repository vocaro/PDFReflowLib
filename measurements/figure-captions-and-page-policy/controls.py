#!/usr/bin/env python3
"""Negative controls for the #27 coverage additions: captions, page policy, strokes and colour.

Each control mutates one passing corpus evaluation — the EPUB markup, one image's pixels or the
conversion report — and requires `tools/check_corpus_content.py` to report the named failure. A
control that stops failing means the contract it belongs to no longer protects anything.

usage: controls.py <evaluation-root> [--json controls.json]

<evaluation-root> holds one directory per case, as `tools/run_corpus_regressions.py --output` writes
them (the case directory itself holds result.json, conversion-report.json and <case>.epub). Cases
whose directory is absent are skipped and named in the output.
"""
import argparse
import io
import json
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
CHECKER = ROOT / 'tools/check_corpus_content.py'


# ---------------------------------------------------------------- mutations

def edit_image(target, transform):
    def edit(name, data):
        if name != target:
            return data
        with Image.open(io.BytesIO(data)) as image:
            result = transform(image.copy())
        buffer = io.BytesIO()
        result.save(buffer, format='PNG')
        return buffer.getvalue()
    return edit


def erase(box):
    def transform(image):
        image.paste(255 if image.mode == 'L' else (255, 255, 255), box)
        return image
    return transform


def grayscale(image):
    return image.convert('L').convert(image.mode)


def swap_channels(image):
    red, green, blue = image.convert('RGB').split()
    return Image.merge('RGB', (blue, red, green)).convert(image.mode)


def half_scale(image):
    return image.resize((image.width // 2, image.height // 2))


def substitute(pattern, replacement):
    def edit(name, text):
        return re.sub(pattern, replacement, text, count=1)
    return edit


def add_warning(page, code):
    def edit(report):
        report.setdefault('warnings', []).append({'page': page, 'code': code, 'message': 'stub'})
    return edit


def drop_warning(page, code):
    def edit(report):
        report['warnings'] = [w for w in report['warnings']
                              if not (w.get('page') == page and w.get('code') == code)]
    return edit


# ---------------------------------------------------------------- harness

def rewrite(source, destination, edit_xhtml=None, edit_report=None, edit_images=None):
    shutil.copytree(source, destination)
    epub = next(destination.glob('*.epub'))
    for chooses, edit in ((lambda n: n.endswith('.xhtml'), edit_xhtml),
                          (lambda n: n.startswith('EPUB/images/'), edit_images)):
        if not edit:
            continue
        with zipfile.ZipFile(epub) as archive:
            entries = [(info, archive.read(info.filename)) for info in archive.infolist()]
        with zipfile.ZipFile(epub, 'w') as archive:
            for info, data in entries:
                if chooses(info.filename):
                    data = (edit(info.filename, data.decode()).encode() if edit is edit_xhtml
                            else edit(info.filename, data))
                archive.writestr(info, data)
    if edit_report:
        path = destination / 'conversion-report.json'
        report = json.loads(path.read_text())
        edit_report(report)
        path.write_text(json.dumps(report))


def assess(case, directory):
    result = subprocess.run([sys.executable, str(CHECKER), '--case', case,
                             '--evaluation', str(directory)],
                            capture_output=True, text=True, cwd=ROOT)
    return json.loads(result.stdout)


CONTROLS = [
    # (case, name, expected failure, mutation)
    ('ntrs-20200002975-gwl-2020', 'GWL page 14: a stray line pushed between Figure A1 and its caption',
     'does not stand after an image',
     dict(edit_xhtml=substitute(r'(<figcaption>Preserved region from page 14</figcaption></figure>\n)',
                                r'\1<p>stray line</p>\n'))),
    ('ntrs-20200002975-gwl-2020', 'GWL page 14: the figure removed, its caption text kept',
     'does not stand after an image',
     dict(edit_xhtml=substitute(r'<figure><img src="images/image-24\.png" alt="Preserved region from page 14"/>'
                                r'<figcaption>Preserved region from page 14</figcaption></figure>', ''))),
    ('ntrs-20200002975-gwl-2020', 'GWL page 14: the caption text removed, its figure kept',
     'no block holds the caption',
     dict(edit_xhtml=substitute(r'<strong>Figure A1\. Peak bending moment due to lift, research model, '
                                r'segregated by azimuth angle regions</strong>', 'stray line'))),
    ('ntrs-20190030725-dasc-2019', 'DASC page 7: the TABLE I caption pushed below its table',
     'does not stand before an image',
     dict(edit_xhtml=substitute(r'(<p>TABLE I: A 6-flight example\.</p>\n)', r'\1<p>stray line</p>\n'))),
    ('faa-phak-8083-25c', 'FAA page 262: Figure 11-5 caption pushed away from its figure',
     'does not stand after an image',
     dict(edit_xhtml=substitute(r'(<p><strong>Figure 11-5\.</strong>)', r'<p>stray line</p>\1'))),
    ('nbs-jres-geltman-1977', 'NBS page 2: FIGURE 1 crop removed, its caption kept',
     'does not stand after an image',
     dict(edit_xhtml=substitute(r'<figure><img src="images/image-5\.png"[^>]*/>'
                                r'<figcaption>[^<]*</figcaption></figure>', ''))),
    ('ntrs-20210020887-techport-thm-2021', 'TechPort page 3: a source-page image appears',
     'unexpected source-page reference image',
     dict(edit_xhtml=substitute(r'(<span epub:type="pagebreak" role="doc-pagebreak" id="page-3"[^/]*/>)',
                                r'\1<figure><img src="images/image-19.png" alt="Original page 3"/></figure>'))),
    ('usda-ars-agresearch-2012-11', 'USDA page 22: a source-page image appears on the index page',
     'unexpected source-page reference image',
     dict(edit_xhtml=substitute(r'(<span epub:type="pagebreak" role="doc-pagebreak" id="page-22"[^/]*/>)',
                                r'\1<figure><img src="images/image-43.png" alt="Original page 22"/></figure>'))),
    ('ntrs-20190030725-dasc-2019', 'DASC page 5: the page reports fresh recognition',
     'unexpected quality warning ocrUsed', dict(edit_report=add_warning(5, 'ocrUsed'))),
    ('ntrs-20200002975-gwl-2020', 'GWL page 9: the page falls back to a whole-page image',
     'unexpected quality warning pageImageFallback',
     dict(edit_report=add_warning(9, 'pageImageFallback'))),
    ('ntrs-20180003024-earthdata-slides-2018', 'Slides 12: the deck text layer is called implausible',
     'unexpected quality warning implausibleTextLayer',
     dict(edit_report=add_warning(12, 'implausibleTextLayer'))),
    ('uscourts-pro-se-1-2016', 'Pro Se 1 page 2: the form reports a damaged encoding',
     'unexpected quality warning damagedTextEncoding',
     dict(edit_report=add_warning(2, 'damagedTextEncoding'))),
    ('ntrs-20210020887-techport-thm-2021', 'TechPort page 2: the lost-interaction warning disappears',
     'Page 2: missing quality warning', dict(edit_report=drop_warning(2, 'annotationsNotConverted'))),
    ('usda-ars-agresearch-2012-11', 'USDA page 23: the preserved-region disclosure disappears',
     'Page 23: missing quality warning', dict(edit_report=drop_warning(23, 'imageRegion'))),
    ('ntrs-20210020887-techport-thm-2021', 'TechPort page 5: one gallery image dropped',
     'Page 5: missing preserved images',
     dict(edit_xhtml=substitute(r'<figure><img src="images/image-35\.png"[^>]*/>'
                                r'<figcaption>[^<]*</figcaption></figure>', ''))),
    ('usgs-mcs2025-copper', "USGS page 2: Chile's production figures erased from the table crop",
     'no image shows every stroke',
     dict(edit_images=edit_image('EPUB/images/image-3.png', erase((330, 130, 1254, 160))))),
    ('usgs-mcs2025-copper', 'USGS page 2: the spanning column headers erased',
     'no image shows every stroke',
     dict(edit_images=edit_image('EPUB/images/image-3.png', erase((330, 0, 1254, 45))))),
    ('gpo-our-flag-2003', "Our Flag page 27: the 125 ft row's flag size erased",
     'no image shows every stroke',
     dict(edit_images=edit_image('EPUB/images/image-48.png', erase((280, 240, 415, 268))))),
    ('cdc-zombie-pandemic-2011', 'CDC page 13: the comic page converted to grayscale',
     'no image keeps the appearance',
     dict(edit_images=edit_image('EPUB/images/image-13.png', grayscale))),
    ('cdc-zombie-pandemic-2011', "CDC page 13: the comic page's colour channels swapped",
     'no image keeps the appearance',
     dict(edit_images=edit_image('EPUB/images/image-13.png', swap_channels))),
    ('cdc-zombie-pandemic-2011', 'CDC page 13: the comic page rasterized at half scale',
     'no image keeps the appearance',
     dict(edit_images=edit_image('EPUB/images/image-13.png', half_scale))),
    ('gpo-our-flag-2003', 'Our Flag page 10: the 50-star paragraph split at the page marker',
     'does not continue onto page 11',
     dict(edit_xhtml=substitute(r'(With the 50-star flag came )'
                                r'(<span epub:type="pagebreak" role="doc-pagebreak" id="page-11"[^/]*/>)',
                                r'\1</p>\2<p>'))),
    ('nbs-jres-geltman-1977', 'NBS page 6: the conclusion paragraph split at the page marker',
     'does not continue onto page 7',
     dict(edit_xhtml=substitute(r'(<span epub:type="pagebreak" role="doc-pagebreak" id="page-7"[^/]*/>)',
                                r'</p>\1<p>'))),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('evaluations', type=Path)
    parser.add_argument('--json', type=Path)
    arguments = parser.parse_args()
    records, skipped, failures = [], [], 0
    for case, name, expected, mutation in CONTROLS:
        source = arguments.evaluations / case
        if not source.is_dir():
            skipped.append(f'{case}: no evaluation in {arguments.evaluations}')
            continue
        with tempfile.TemporaryDirectory() as workspace:
            target = Path(workspace) / 'evaluation'
            rewrite(source, target, **mutation)
            assessment = assess(case, target)
        matching = [e for e in assessment['errors'] if expected in e]
        failures += not matching
        records.append({'case': case, 'control': name, 'expected': expected,
                        'failedAsRequired': bool(matching),
                        'error': matching[0] if matching else None,
                        'otherErrors': [] if matching else assessment['errors'][:3]})
        print(('FAILS as required: ' if matching else 'DID NOT FAIL: ') + name)
        if matching:
            print('    ' + matching[0])
    for note in skipped:
        print('SKIPPED ' + note)
    summary = {'controls': records, 'skipped': skipped,
               'failedAsRequired': sum(r['failedAsRequired'] for r in records),
               'total': len(records)}
    if arguments.json:
        arguments.json.write_text(json.dumps(summary, indent=2) + '\n')
    print(f"\n{summary['failedAsRequired']}/{summary['total']} controls failed as required")
    return 1 if failures or skipped else 0


if __name__ == '__main__':
    sys.exit(main())
