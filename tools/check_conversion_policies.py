#!/usr/bin/env python3
"""Exercise the public CLI's policy controls with real small PDFs and optional EPUBCheck."""
import argparse
import json
from pathlib import Path
import zipfile

import check_epubs as checks
from pdfreflow_tools.converter import convert, pinned_packaging, run_epubcheck
from pdfreflow_tools.corpus import FIXTURES, digest
import view_epub

HEADER = 'PDF REFLOW TEST BOOK'  # Repeated at the top of all three prose.pdf pages.
PINNED = pinned_packaging('urn:pdfreflow:headers-keep')


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
    fixtures = FIXTURES
    cases = [
        ('page-jpeg', 'graphics', ['--reference-images', 'always', '--full-page-image-encoding', 'jpeg:0.9',
                                  '--region-image-encoding', 'png',
                                  '--maximum-output-bytes', 'unlimited', '--maximum-epub-bytes', '1048576'], 4),
        # The automatic default (#193), named explicitly and left implicit, must write the same images.
        ('automatic-default', 'graphics', ['--reference-images', 'always'], 4),
        ('automatic-named', 'graphics', ['--reference-images', 'always', '--full-page-image-encoding', 'automatic',
                                         '--region-image-encoding', 'automatic:0.9'], 4),
        ('region-jpeg', 'graphics', ['--reference-images', 'never', '--region-image-encoding', 'jpeg:0.95'], 3),
        ('fallback-smallest', 'scanned', ['--no-ocr', '--reference-images', 'never',
                                        '--full-page-image-encoding', 'smallest:0.9'], 1),
        ('text-only', 'prose', ['--reference-images', 'never', '--maximum-epub-bytes', 'unlimited'], 0),
        ('ocr-selective-native', 'prose', ['--ocr', 'image-backed'], 0),
        ('ocr-never', 'scanned', ['--ocr', 'never'], 1),
        ('ocr-keep-image-backed', 'scanned', ['--ocr', 'keep-image-backed'], 1),
        ('ocr-always', 'columns', ['--ocr', 'always'], 1),
        ('ocr-automatic', 'scanned', ['--ocr', 'automatic'], 1),
        # Language correction is an opt-in whose report must say it was used (#108); off,
        # explicitly or by default, the report says what it always has.
        ('ocr-language-correction', 'scanned', ['--ocr-language-correction', 'on'], 1),
        ('ocr-language-correction-off', 'scanned', ['--ocr-language-correction', 'off'], 1),
        ('headers-default', 'prose', [], 0),
        ('headers-remove', 'prose', ['--repeated-headers-and-footers', 'remove'], 0),
        ('headers-keep', 'prose', ['--repeated-headers-and-footers', 'keep'], 0),
        ('headers-keep-pinned-a', 'prose', ['--repeated-headers-and-footers', 'keep', *PINNED], 0),
        ('headers-keep-pinned-b', 'prose', ['--repeated-headers-and-footers', 'keep', *PINNED], 0),
    ]
    results = []
    automatic_default = None
    for name, fixture, flags, image_count in cases:
        output = args.output / (name + '.epub')
        run = convert(converter, fixtures / (fixture + '.pdf'), output, *flags, timeout=120)
        report = run.report
        (args.output / (name + '-report.json')).write_text(run.stdout)
        (args.output / (name + '-progress.log')).write_text(run.stderr)
        assert report['imageCount'] == image_count
        if name == 'ocr-selective-native' or name == 'ocr-never':
            assert report['recognizedPageCount'] == 0
        if name in ('ocr-always', 'ocr-automatic', 'ocr-keep-image-backed',
                    'ocr-language-correction', 'ocr-language-correction-off'):
            assert report['recognizedPageCount'] == 1
        if name.startswith('ocr-'):
            recognized = [w['message'] for w in report['warnings'] if w['code'] == 'ocrUsed']
            corrected = [m for m in recognized if 'language correction on' in m]
            if name == 'ocr-language-correction':
                assert recognized and corrected == recognized, (name, recognized)
            else:
                assert corrected == [], (name, corrected)
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
            if name.startswith('automatic-'):
                written = {n: book.read(n) for n in images}
                if name == 'automatic-named':
                    assert written == automatic_default, 'named automatic differs from the default'
                else:
                    automatic_default = written
        view_epub.prepare(output, args.output / (name + '-reader'))
        if args.epubcheck:
            run_epubcheck(args.epubcheck.resolve(), output, args.output / (name + '-epubcheck.log'),
                          check=True, timeout=120)
        results.append({'name': name, 'command': run.command, 'imageCount': image_count, 'passed': True})
        print('PASS ' + name, flush=True)
    # A declared language reaches the package document (#108).
    tagged = args.output / 'language.epub'
    convert(converter, fixtures / 'prose.pdf', tagged, '--language', 'zh-Hans', timeout=60)
    with zipfile.ZipFile(tagged) as archive:
        package = next(n for n in archive.namelist() if n.endswith('.opf'))
        text = archive.read(package).decode('utf-8')
    assert '<dc:language>zh-Hans</dc:language>' in text, 'declared language missing from the package'
    print('PASS language-tag', flush=True)
    # A locked document converts with its password and with no other (#252). The password is
    # read from a file, so it never reaches the argument list or the process table.
    password_file = args.output / 'password.txt'
    password_file.write_text('reflow')
    wrong_file = args.output / 'wrong-password.txt'
    wrong_file.write_text('not the password')
    unlocked = args.output / 'unlocked.epub'
    convert(converter, fixtures / 'encrypted.pdf', unlocked, '--password-file', str(password_file), timeout=60)
    assert 'A locked page reflows once its password unlocks it.' in checks.check(unlocked)
    # The same password on standard input, which is the form that leaves no file behind.
    piped = args.output / 'unlocked-stdin.epub'
    convert(converter, fixtures / 'encrypted.pdf', piped, '--password-file', '-', timeout=60, input='reflow\n')
    assert 'A locked page reflows once its password unlocks it.' in checks.check(piped)
    for flags, expected in ((['--password-file', str(wrong_file)], 'The PDF is password-protected.'),
                            ([], 'The PDF is password-protected.'),
                            (['--password-file', str(args.output / 'absent.txt')], 'cannot read the password file'),
                            (['--password-file', str(args.output / 'empty.txt')], 'states no password')):
        (args.output / 'empty.txt').write_text('')
        output = args.output / 'must-not-exist.epub'
        run = convert(converter, fixtures / 'encrypted.pdf', output, *flags, timeout=60, check=False)
        assert run.returncode == 1 and not output.exists(), flags
        assert expected in run.stderr, (flags, run.stderr)
        # Whatever the CLI says about a failure, it does not say the password.
        assert 'not the password' not in run.stderr, run.stderr
    print('PASS locked-document', flush=True)
    failures = [
        ['--reference-images', 'invalid'], ['--region-image-encoding', 'jpeg:nan'],
        ['--full-page-image-encoding', 'smallest:1.1'], ['--full-page-image-encoding', 'jpeg:-0.1'],
        ['--region-image-encoding', 'automatic:1.1'], ['--full-page-image-encoding', 'automatic:'],
        ['--full-page-image-encoding', 'lossless'],
        ['--maximum-output-bytes', '0'], ['--maximum-epub-bytes', '-1'], ['--maximum-epub-bytes'],
        ['--unknown', 'x'], ['--maximum-epub-bytes', '1'], ['--maximum-output-bytes', '1'],
        ['--ocr', 'invalid'], ['--ocr'],
        # The correction opt-in takes on or off and nothing else (#108).
        ['--ocr-language-correction', 'yes'], ['--ocr-language-correction', 'ON'],
        ['--ocr-language-correction', ''], ['--ocr-language-correction'],
        ['--repeated-headers-and-footers', 'drop'], ['--repeated-headers-and-footers', 'KEEP'],
        ['--repeated-headers-and-footers'],
        # A language tag decides dc:language and the rules that only hold for a declared
        # language, so a malformed one fails rather than converting as something else (#108).
        ['--language', ''], ['--language', 'en_US'], ['--language', 'zh--Hans'],
        ['--language', 'en-'], ['--language', '1en'], ['--language'],
    ]
    for flags in failures:
        output = args.output / 'must-not-exist.epub'
        run = convert(converter, fixtures / 'prose.pdf', output, *flags, timeout=60, check=False)
        assert run.returncode != 0 and not output.exists(), flags
        assert '100% completed' not in run.stderr, flags
        if flags[0] == '--repeated-headers-and-footers' and len(flags) == 2:
            assert run.returncode == 1, flags
            assert run.stderr.strip() == ('Invalid conversion options: unknown repeated header/footer policy: '
                                          f'{flags[1]} (expected remove or keep)'), run.stderr
        if flags[0] == '--ocr-language-correction' and len(flags) == 2:
            assert run.returncode == 1, flags
            assert run.stderr.strip() == ('Invalid conversion options: unknown OCR language-correction setting: '
                                          f'{flags[1]} (expected on or off)'), run.stderr
        assert not list(args.output.glob('.pdfreflow-*')), flags
        results.append({'flags': flags, 'exitCode': run.returncode, 'diagnostic': run.stderr, 'passed': True})
    digests = [digest(args.output / f'headers-keep-pinned-{run}.epub') for run in 'ab']
    assert digests[0] == digests[1], digests
    results.append({'name': 'headers-keep-reproducible', 'sha256': digests[0], 'passed': True})
    (args.output / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    print(f'PASS {len(cases)} policy conversions and {len(failures)} rejection/cleanup cases', flush=True)


if __name__ == '__main__':
    main()
