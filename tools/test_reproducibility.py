import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import check_reproducibility as repro

PAGES = {1: '<h2 id="heading-1-0">Opening</h2><p>First page prose.</p>',
         2: '<p>Recognized comic dialogue.</p>',
         3: '<p>Third page prose.</p><figure><img src="images/image-1.png" alt=""/></figure>'}


def pinned(name):
    return zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))


def write_epub(path, pages=PAGES, packing=((1, 2, 3),), image=b'pixels', comment=b''):
    """A minimal converter-shaped EPUB: spine documents holding page-marked segments."""
    files = [f'chapter-{index + 1}.xhtml' for index in range(len(packing))]
    where = {page: files[index] for index, group in enumerate(packing) for page in group}
    with zipfile.ZipFile(path, 'w') as archive:
        archive.writestr(pinned('mimetype'), 'application/epub+zip')
        archive.writestr(pinned('EPUB/package.opf'),
            '<package xmlns="http://www.idpf.org/2007/opf" version="3.0"><manifest>'
            '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'
            + ''.join(f'<item id="c{i}" href="{name}" media-type="application/xhtml+xml"/>' for i, name in enumerate(files))
            + '<item id="img0" href="images/image-1.png" media-type="image/png"/></manifest><spine>'
            + ''.join(f'<itemref idref="c{i}"/>' for i in range(len(files))) + '</spine></package>')
        headings = [(page, text) for page, markup in pages.items()
                    for text in [markup.split('>', 1)[1].split('<', 1)[0]] if markup.startswith('<h2')]
        archive.writestr(pinned('EPUB/nav.xhtml'),
            '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>'
            '<nav epub:type="toc"><ol>'
            + ''.join(f'<li><a href="{where[page]}#heading-{page}-0">{text}</a></li>' for page, text in headings)
            + '</ol></nav><nav epub:type="page-list"><ol>'
            + ''.join(f'<li><a href="{where[page]}#page-{page}">{page}</a></li>' for page in pages)
            + '</ol></nav></body></html>')
        for index, group in enumerate(packing):
            archive.writestr(pinned('EPUB/' + files[index]),
                '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head>'
                '<title>book</title></head><body>'
                + ''.join(f'<span epub:type="pagebreak" role="doc-pagebreak" id="page-{page}" aria-label="{page}"/>'
                          + pages[page] for page in group) + '</body></html>')
        archive.writestr(pinned('EPUB/images/image-1.png'), image)
        archive.comment = comment


def report(ocr=(2,), extra=()):
    return {'pageCount': 3, 'imageCount': 1, 'recognizedPageCount': len(ocr), 'reflowedPageCount': 3,
            'outputURL': 'file:///anywhere',
            'warnings': [{'code': 'ocrUsed', 'page': page, 'message': 'OCR'} for page in ocr] + list(extra)}


class ComparisonTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.left = self.root / 'left.epub'
        write_epub(self.left)

    def candidate(self, name='right.epub', **kwargs):
        path = self.root / name
        write_epub(path, **kwargs)
        return path

    def compare(self, right, left_report=None, right_report=None):
        return repro.compare_runs(self.left, right, left_report or report(), right_report or report())

    def test_identical_epubs_and_reports_pass_without_normalization(self):
        right_report = report()
        right_report['outputURL'] = 'file:///elsewhere'
        result = self.compare(self.candidate(), right_report=right_report)
        self.assertTrue(result['passed'], result)
        self.assertTrue(result['byteIdentical'])
        self.assertNotIn('changedPages', result)

    def test_changed_non_ocr_page_fails_and_names_the_page(self):
        pages = PAGES | {3: PAGES[3].replace('Third', 'Changed')}
        result = self.compare(self.candidate(pages=pages))
        self.assertFalse(result['passed'])
        self.assertEqual(result['nonOCRChangedPages'], [3])
        self.assertIn('page markup differs on non-OCR pages [3]', result['failures'])
        self.assertEqual(result['differingEntries'], ['EPUB/chapter-1.xhtml'])

    def test_changed_markup_alone_fails_even_with_identical_text(self):
        pages = PAGES | {1: PAGES[1].replace('<h2 id="heading-1-0">Opening</h2>', '<p>Opening</p>')}
        result = self.compare(self.candidate(pages=pages))
        self.assertFalse(result['passed'])
        self.assertEqual(result['nonOCRChangedPages'], [1])

    def test_changed_ocr_page_passes_under_normalization_and_is_reported(self):
        pages = PAGES | {2: '<p>An INOD gseg id</p><p>Another line</p>'}
        result = self.compare(self.candidate(pages=pages),
                              right_report=report(extra=[{'code': 'uncertainHyphen', 'page': 2, 'message': 'x'}]))
        self.assertTrue(result['passed'], result)
        self.assertFalse(result['byteIdentical'])
        self.assertEqual(result['ocrChangedPages'], [2])
        self.assertEqual(result['nonOCRChangedPages'], [])
        self.assertIn('page markup differs on OCR pages [2]', result['allowedDifferences'])
        self.assertIn('report warnings differ on OCR pages', result['allowedDifferences'])

    def test_ocr_page_exemption_requires_the_page_to_be_ocr_in_both_runs(self):
        pages = PAGES | {2: '<p>Different</p>'}
        result = self.compare(self.candidate(pages=pages), right_report=report(ocr=()))
        self.assertFalse(result['passed'])
        self.assertTrue(any('OCR page sets differ' in f for f in result['failures']))
        self.assertEqual(result['nonOCRChangedPages'], [2])

    def test_ocr_text_that_moves_spine_packing_passes_but_is_reported(self):
        pages = PAGES | {2: '<p>' + 'longer recognized text ' * 50 + '</p>'}
        result = self.compare(self.candidate(pages=pages, packing=((1, 2), (3,))))
        self.assertTrue(result['passed'], result)
        self.assertEqual(result['ocrChangedPages'], [2])
        self.assertTrue(any('spine packing differs' in note for note in result['allowedDifferences']))

    def test_spine_packing_change_without_ocr_pages_fails(self):
        result = repro.compare_runs(self.left, self.candidate(packing=((1, 2), (3,))), report(ocr=()), report(ocr=()))
        self.assertFalse(result['passed'])
        self.assertIn('spine packing differs without OCR pages', result['failures'])
        self.assertEqual(result['changedPages'], [])

    def test_image_bytes_differ_fails_and_names_referencing_page(self):
        result = self.compare(self.candidate(image=b'other pixels'))
        self.assertFalse(result['passed'])
        self.assertEqual(result['failures'], ['entry EPUB/images/image-1.png differs (referenced on pages [3])'])

    def test_zip_metadata_only_difference_fails_despite_equal_entries(self):
        result = self.compare(self.candidate(comment=b'another archive comment'))
        self.assertFalse(result['byteIdentical'])
        self.assertFalse(result['passed'])
        self.assertEqual(result['differingEntries'], [])
        self.assertEqual(result['failures'], ['ZIP archive comment differs'])

    def test_navigation_text_change_outside_ocr_pages_fails(self):
        right = self.candidate()
        with zipfile.ZipFile(right) as archive:
            entries = {info.filename: archive.read(info.filename) for info in archive.infolist()}
        entries['EPUB/nav.xhtml'] = entries['EPUB/nav.xhtml'].replace(b'>Opening<', b'>Renamed<')
        tampered = self.root / 'nav.epub'
        with zipfile.ZipFile(tampered, 'w') as archive:
            for name, data in entries.items():
                archive.writestr(pinned(name), data)
        result = self.compare(tampered)
        self.assertFalse(result['passed'])
        self.assertIn('navigation entries differ outside OCR pages (pages [1])', result['failures'])

    def test_report_differences_outside_ocr_pages_fail(self):
        extra = [{'code': 'structureFallback', 'page': 3, 'message': 'x'}]
        result = self.compare(self.candidate(), right_report=report(extra=extra))
        self.assertFalse(result['passed'])
        self.assertIn('report warnings differ outside OCR pages (pages [3])', result['failures'])
        counts = report()
        counts['imageCount'] = 2
        result = self.compare(self.candidate('counts.epub'), right_report=counts)
        self.assertEqual(result['failures'], ['report field imageCount: 1 vs 2'])


class CommandTests(unittest.TestCase):
    """End-to-end through stub converters, including the binary-identity refusal."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / 'book.pdf'
        self.source.write_bytes(b'%PDF-1.7 control')
        self.converter = self.root / 'converter'

    def stub(self, body=''):
        self.converter.write_text(f'''#!{sys.executable}
import json, random, sys
sys.path.insert(0, {str(Path(__file__).parent)!r})
from test_reproducibility import PAGES, write_epub, report
assert sys.argv[3:] == {repro.PINNED!r}, sys.argv
pages = dict(PAGES)
{body}
write_epub(sys.argv[2], pages=pages)
print(json.dumps(report()))
''')
        self.converter.chmod(0o700)

    def run_main(self, *extra):
        output = self.root / 'out'
        argv = ['check', '--converter', str(self.converter), '--output', str(output), '--pdf', str(self.source), *extra]
        with patch.object(sys, 'argv', argv), contextlib.redirect_stdout(io.StringIO()):
            code = repro.main()
        return code, json.loads((output / 'summary.json').read_text()), output / 'book'

    def test_deterministic_converter_passes_in_both_modes_and_discards_outputs(self):
        self.stub()
        for mode in ('concurrent', 'sequential'):
            with self.subTest(mode=mode):
                code, summary, directory = self.run_main('--mode', mode)
                self.assertEqual(code, 0, summary)
                [record] = summary['results']
                self.assertTrue(record['byteIdentical'])
                self.assertEqual(record['mode'], mode)
                self.assertEqual(record['converterSHA256'], repro.digest(self.converter))
                cache = record['visionModelCache']
                self.assertEqual(cache['before']['executableName'], 'converter')
                self.assertFalse(cache['changed'])
                self.assertFalse(list(directory.glob('*.epub')))
                self.assertTrue((directory / 'run-2.json').exists())
                (self.root / 'out' / 'summary.json').unlink()
                for path in sorted((self.root / 'out').rglob('*'), reverse=True):
                    path.unlink() if path.is_file() else path.rmdir()
                (self.root / 'out').rmdir()

    def test_nondeterministic_non_ocr_page_fails_and_keeps_outputs(self):
        self.stub("pages[3] = '<p>' + str(random.random()) + '</p>'")
        code, summary, directory = self.run_main()
        self.assertEqual(code, 1)
        [record] = summary['results']
        self.assertEqual(record['nonOCRChangedPages'], [3])
        self.assertEqual(len(list(directory.glob('*.epub'))), 2)

    def test_nondeterministic_ocr_page_passes_and_is_reported(self):
        self.stub("pages[2] = '<p>' + str(random.random()) + '</p>'")
        code, summary, _ = self.run_main('--mode', 'sequential')
        self.assertEqual(code, 0, summary)
        self.assertEqual(summary['results'][0]['ocrChangedPages'], [2])

    def test_converter_replaced_during_the_check_is_refused(self):
        self.stub("open(sys.argv[0], 'a').write('# rebuilt\\n')")
        for mode in ('sequential', 'concurrent'):
            with self.subTest(mode=mode):
                output = self.root / ('out-' + mode)
                argv = ['check', '--converter', str(self.converter), '--output', str(output),
                        '--pdf', str(self.source), '--mode', mode]
                with patch.object(sys, 'argv', argv), contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(repro.main(), 1)
                [record] = json.loads((output / 'summary.json').read_text())['results']
                self.assertIn('converter binary changed during the check; refusing to compare two builds',
                              record['errors'])
                self.assertNotIn('byteIdentical', record)

    def test_failed_conversion_is_a_failure(self):
        self.stub("sys.exit(3)")
        code, summary, _ = self.run_main()
        self.assertEqual(code, 1)
        self.assertEqual(summary['results'][0]['errors'], ['conversion failed; see run logs'])

    def test_sources_are_required_and_labels_distinct(self):
        self.stub()
        for extra in [(), ('--pdf', str(self.source))]:
            argv = ['check', '--converter', str(self.converter), '--output', str(self.root / 'x')]
            argv += [] if not extra else ['--pdf', str(self.source), *extra]
            with patch.object(sys, 'argv', argv), contextlib.redirect_stderr(io.StringIO()), \
                    self.assertRaises(SystemExit):
                repro.main()


if __name__ == '__main__':
    unittest.main()
