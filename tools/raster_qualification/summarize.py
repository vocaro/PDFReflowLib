#!/usr/bin/env python3
"""Independently inspect retained device EPUBs and report drift against each book's 180-DPI run.

Raw corpus failures stay failures. A separate diagnostic rescales images to the reference DPI;
this is not a replacement gate, and it cannot prove fine-detail legibility.
"""
from collections import Counter
import argparse
import hashlib
import io
import json
from pathlib import Path
import subprocess
import sys
import zipfile

from PIL import Image
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from check_corpus_content import assess, read_spine
from pdfreflow_tools.corpus import manifest_cases, regression_contracts


def write(path, data):
    path.write_text(json.dumps(data, indent=2) + '\n')


def inspect(path, max_uncompressed_bytes=512 * 1024 * 1024):
    pages, markers, documents = read_spine(path, max_uncompressed_bytes=max_uncompressed_bytes)
    images = []
    with zipfile.ZipFile(path) as archive:
        for info in archive.infolist():
            if not info.filename.startswith('EPUB/images/') or info.is_dir(): continue
            data = archive.read(info)
            with Image.open(io.BytesIO(data)) as image:
                image.load()
                images.append({'name': info.filename, 'bytes': len(data), 'size': list(image.size),
                               'format': image.format, 'sha256': hashlib.sha256(data).hexdigest()})
    return pages, markers, documents, images


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--epubcheck', default='/opt/homebrew/bin/epubcheck')
    parser.add_argument('--max-uncompressed-bytes', type=int, default=512 * 1024 * 1024)
    args = parser.parse_args()
    if args.max_uncompressed_bytes <= 0:
        parser.error('inspection byte limit must be positive')
    cases = {case['id']: case for case in manifest_cases(ROOT)}
    contracts = {case['id']: case for case in regression_contracts(ROOT)['cases']}
    rows = []
    baselines = {}
    directories = sorted(args.directory.glob('*/metrics.json'), key=lambda p: ('-180-' not in str(p), str(p)))
    for metrics_path in directories:
        directory = metrics_path.parent
        metrics = json.loads(metrics_path.read_text())
        name = metrics['case']; dpi = metrics['rasterDPI']
        if metrics['status'] != 'completed':
            rows.append({'metrics': metrics}); continue
        if not (directory / 'content.json').exists():
            continue  # The device runner has not finished copying/checking this output yet.
        report = json.loads((directory / 'conversion-report.json').read_text())
        path = directory / (name + '.epub')
        pages, markers, documents, images = inspect(path, args.max_uncompressed_bytes)
        base = baselines.setdefault(name, (dpi, pages, markers, images))
        changed = [n for n in sorted(pages.keys() | base[1].keys()) if pages.get(n, {}).get('text') != base[1].get(n, {}).get('text')]
        row = {'metrics': metrics, 'images': len(images), 'imageBytes': sum(i['bytes'] for i in images),
               'largestImagePixels': max((i['size'][0] * i['size'][1] for i in images), default=0),
               'encodings': dict(Counter(i['format'] for i in images)), 'baselineDPI': base[0],
               'changedTextPages': changed, 'pageMarkersEqual': markers == base[2],
               'warningCounts': dict(Counter(w['code'] for w in report['warnings'])),
               'pageCount': report['pageCount'], 'reflowedPages': report['reflowedPageCount'],
               'recognizedPages': report['recognizedPageCount'],
               'ocrPages': sorted({w['page'] for w in report['warnings'] if w['code'] == 'ocrUsed'}),
               'textDrift': {str(n): {'baseline': base[1].get(n, {}).get('text'), 'candidate': pages.get(n, {}).get('text')} for n in changed},
               'rawContent': json.loads((directory / 'content.json').read_text())}
        if name in cases and dpi != 180:
            with zipfile.ZipFile(path) as archive:
                def normalized(asset):
                    data = archive.read(asset)
                    with Image.open(io.BytesIO(data)) as image:
                        # All selected ordinary book pages are below the 12 Mpx ceiling through 300 DPI.
                        image = image.resize((max(1, round(image.width * 180 / dpi)), max(1, round(image.height * 180 / dpi))), Image.Resampling.LANCZOS)
                        buffer = io.BytesIO(); image.save(buffer, format='PNG'); return buffer.getvalue()
                receipt = json.loads((directory / 'result.json').read_text())
                row['normalizedImageDiagnostic'] = assess(cases[name], contracts[name], receipt, report, pages, markers,
                                                          documents=documents, image_data=normalized)
        with (directory / 'epubcheck.log').open('w') as log:
            result = subprocess.run([args.epubcheck, str(path)], stdout=log, stderr=subprocess.STDOUT, timeout=300)
        row['epubcheckExitCode'] = result.returncode
        write(directory / 'image-identities.json', images)
        rows.append(row)
        write(args.directory / 'comparison.json', rows)
        print(name, dpi, 'RSS MiB', round(metrics['peakRSSBytes']/1048576,1), 'footprint MiB', round(metrics['sampledPeakFootprintBytes']/1048576,1), 'changed text pages', len(changed), 'EPUBCheck', result.returncode, flush=True)

    write(args.directory / 'comparison.json', rows)


if __name__ == '__main__':
    main()
