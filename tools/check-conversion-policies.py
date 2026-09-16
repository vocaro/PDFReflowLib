#!/usr/bin/env python3
"""Exercise the public CLI's policy controls with real small PDFs and optional EPUBCheck."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import zipfile

import view_epub

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('epub_checks', ROOT / 'tools/check-epubs.py')
checks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checks)

HEADER = 'PDF REFLOW TEST BOOK'  # Repeated at the top of all three prose.pdf pages.
PINNED = ['--package-identifier', 'urn:pdfreflow:headers-keep', '--modification-date', '2026-01-01T00:00:00Z']


def spine_markup(path):
    with zipfile.ZipFile(path) as book:
        return ''.join(book.read(n).decode('utf-8') for n in book.namelist() if n.endswith('.xhtml'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--converter', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--epubcheck', type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    converter = str(args.converter.resolve(strict=True))
    fixtures = ROOT / 'Tests/PDFReflowLibTests/fixtures'
    cases = [
        ('page-jpeg', 'graphics', ['--reference-images', 'always', '--full-page-image-encoding', 'jpeg:0.9',
                                  '--maximum-output-bytes', 'unlimited', '--maximum-epub-bytes', '1048576'], 4),
        ('region-jpeg', 'graphics', ['--reference-images', 'never', '--region-image-encoding', 'jpeg:0.95'], 3),
        ('fallback-smallest', 'scanned', ['--no-ocr', '--reference-images', 'never',
                                        '--full-page-image-encoding', 'smallest:0.9'], 1),
        ('text-only', 'prose', ['--reference-images', 'never', '--maximum-epub-bytes', 'unlimited'], 0),
        ('ocr-selective-native', 'prose', ['--ocr', 'image-backed'], 0),
        ('ocr-never', 'scanned', ['--ocr', 'never'], 1),
        ('ocr-always', 'columns', ['--ocr', 'always'], 1),
        ('ocr-automatic', 'scanned', ['--ocr', 'automatic'], 1),
        ('headers-default', 'prose', [], 0),
        ('headers-remove', 'prose', ['--repeated-headers-and-footers', 'remove'], 0),
        ('headers-keep', 'prose', ['--repeated-headers-and-footers', 'keep'], 0),
        ('headers-keep-pinned-a', 'prose', ['--repeated-headers-and-footers', 'keep', *PINNED], 0),
        ('headers-keep-pinned-b', 'prose', ['--repeated-headers-and-footers', 'keep', *PINNED], 0),
    ]
    results = []
    for name, fixture, flags, image_count in cases:
        output = args.output / (name + '.epub')
        command = [converter, str(fixtures / (fixture + '.pdf')), str(output), *flags]
        run = subprocess.run(command, capture_output=True, text=True, timeout=120, check=True)
        report = json.loads(run.stdout)
        (args.output / (name + '-report.json')).write_text(run.stdout)
        (args.output / (name + '-progress.log')).write_text(run.stderr)
        assert report['imageCount'] == image_count
        if name == 'ocr-selective-native' or name == 'ocr-never':
            assert report['recognizedPageCount'] == 0
        if name == 'ocr-always' or name == 'ocr-automatic':
            assert report['recognizedPageCount'] == 1
        assert run.stderr.splitlines()[-1] == '100% completed'
        text = checks.check(output)
        if fixture == 'graphics': assert 'Text after the table' in text
        if name.startswith('headers-'):
            removed = [w['page'] for w in report['warnings'] if w['code'] == 'furnitureRemoved']
            count = spine_markup(output).count(HEADER)
            if name.startswith('headers-keep'):
                assert count == 3 and removed == [], (name, count, removed)
            else:
                assert count == 0 and removed == [1, 2, 3], (name, count, removed)
        with zipfile.ZipFile(output) as book:
            images = [n for n in book.namelist() if n.startswith('EPUB/images/')]
            if name == 'page-jpeg':
                assert sum(n.endswith('.jpg') for n in images) == 1
                assert sum(n.endswith('.png') for n in images) == 3
            if name == 'region-jpeg': assert all(n.endswith('.jpg') for n in images)
        view_epub.prepare(output, args.output / (name + '-reader'))
        if args.epubcheck:
            with (args.output / (name + '-epubcheck.log')).open('w') as log:
                subprocess.run([str(args.epubcheck.resolve()), str(output)], stdout=log, stderr=subprocess.STDOUT,
                               check=True, timeout=120)
        results.append({'name': name, 'command': command, 'imageCount': image_count, 'passed': True})
        print('PASS ' + name, flush=True)
    failures = [
        ['--reference-images', 'invalid'], ['--region-image-encoding', 'jpeg:nan'],
        ['--full-page-image-encoding', 'smallest:1.1'], ['--full-page-image-encoding', 'jpeg:-0.1'],
        ['--maximum-output-bytes', '0'], ['--maximum-epub-bytes', '-1'], ['--maximum-epub-bytes'],
        ['--unknown', 'x'], ['--maximum-epub-bytes', '1'], ['--maximum-output-bytes', '1'],
        ['--ocr', 'invalid'], ['--ocr'],
        ['--repeated-headers-and-footers', 'drop'], ['--repeated-headers-and-footers', 'KEEP'],
        ['--repeated-headers-and-footers'],
        ['--raster-dpi', '71'], ['--raster-dpi', '601'], ['--raster-dpi', 'nan'], ['--raster-dpi'],
        ['--maximum-raster-pixels', '0'], ['--maximum-raster-pixels', '48000001'], ['--maximum-raster-pixels', '1.5'],
    ]
    for flags in failures:
        output = args.output / 'must-not-exist.epub'
        run = subprocess.run([converter, str(fixtures / 'prose.pdf'), str(output), *flags],
                             capture_output=True, text=True, timeout=60)
        assert run.returncode != 0 and not output.exists(), flags
        assert '100% completed' not in run.stderr, flags
        if flags[0] == '--repeated-headers-and-footers' and len(flags) == 2:
            assert run.returncode == 1, flags
            assert run.stderr.strip() == ('Invalid conversion options: unknown repeated header/footer policy: '
                                          f'{flags[1]} (expected remove or keep)'), run.stderr
        assert not list(args.output.glob('.pdfreflow-*')), flags
        results.append({'flags': flags, 'exitCode': run.returncode, 'diagnostic': run.stderr, 'passed': True})
    digests = [hashlib.sha256((args.output / f'headers-keep-pinned-{run}.epub').read_bytes()).hexdigest()
               for run in 'ab']
    assert digests[0] == digests[1], digests
    results.append({'name': 'headers-keep-reproducible', 'sha256': digests[0], 'passed': True})
    (args.output / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    print(f'PASS {len(cases)} policy conversions and {len(failures)} rejection/cleanup cases', flush=True)


if __name__ == '__main__':
    main()
