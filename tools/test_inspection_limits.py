import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import warnings
import xml.etree.ElementTree as ET
import zipfile

from check_corpus_content import (ROOT, DEFAULT_MAX_ENTRIES, DEFAULT_MAX_UNCOMPRESSED_BYTES,
                                  check_evaluation, read_pages)


class InspectionLimitTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.path = self.directory / 'fixture.epub'

    def make_epub(self, *, pages=2, chapters=2, images=1, padding_mib=0, body=None):
        with zipfile.ZipFile(self.path, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=1) as archive:
            manifest = ''.join(f'<item id="c{i}" href="c{i}.xhtml"/>' for i in range(chapters))
            spine = ''.join(f'<itemref idref="c{i}"/>' for i in range(chapters))
            archive.writestr('EPUB/package.opf',
                             f'<package xmlns="http://www.idpf.org/2007/opf"><manifest>{manifest}</manifest>'
                             f'<spine>{spine}</spine></package>')
            for chapter in range(chapters):
                content = []
                for page in range(chapter * pages // chapters + 1, (chapter + 1) * pages // chapters + 1):
                    content.append(f'<span epub:type="pagebreak" id="page-{page}"/><p>source {page}</p>')
                    for image in range((page - 1) * images // pages, page * images // pages):
                        content.append(f'<img src="image-{image}.png"/>')
                archive.writestr(f'EPUB/c{chapter}.xhtml',
                                 '<html xmlns="http://www.w3.org/1999/xhtml" '
                                 'xmlns:epub="http://www.idpf.org/2007/ops"><body>'
                                 + (body if body is not None else ''.join(content)) + '</body></html>')
            # Only image presence is inspected: pixels/conformance are outside this fixture's scope.
            for image in range(images):
                archive.writestr(f'EPUB/image-{image}.png', b'fixture')
            if padding_mib:
                with archive.open('EPUB/padding.bin', 'w') as stream:
                    chunk = bytes(1024 * 1024)
                    for _ in range(padding_mib):
                        stream.write(chunk)
        with zipfile.ZipFile(self.path) as archive:
            return len(archive.infolist()), sum(entry.file_size for entry in archive.infolist())

    def test_exact_bounds_and_each_one_below_reject_before_xml_read(self):
        entries, expanded = self.make_epub()
        original = read_pages(self.path)
        self.assertEqual(read_pages(self.path, max_entries=entries, max_uncompressed_bytes=expanded), original)
        self.assertEqual(read_pages(self.path, max_entries=sys.maxsize,
                                    max_uncompressed_bytes=sys.maxsize), original)
        for limits in [dict(max_entries=entries - 1), dict(max_uncompressed_bytes=expanded - 1)]:
            with self.subTest(limits=limits), patch.object(zipfile.ZipFile, 'read') as read:
                with self.assertRaisesRegex(ValueError, 'EPUB exceeds inspection bounds'):
                    read_pages(self.path, **limits)
                read.assert_not_called()

    def test_invalid_api_limits_fail_before_opening_archive(self):
        for name in ['max_entries', 'max_uncompressed_bytes']:
            for value in [None, True, False, 0, -1, 1.0, '10000', float('nan'),
                          float('inf'), [], {}, sys.maxsize + 1]:
                with self.subTest(name=name, value=value), patch.object(zipfile, 'ZipFile') as archive:
                    with self.assertRaisesRegex(ValueError, name + ' must be an integer'):
                        read_pages(self.path, **{name: value})
                    archive.assert_not_called()

    def test_noaa_scale_needs_both_explicit_limits(self):
        entries, expanded = self.make_epub(pages=1834, chapters=81, images=11245, padding_mib=513)
        self.assertGreater(entries, DEFAULT_MAX_ENTRIES)
        self.assertGreater(expanded, DEFAULT_MAX_UNCOMPRESSED_BYTES)
        for limits in [{}, dict(max_entries=20000), dict(max_uncompressed_bytes=4 * 1024**3)]:
            with self.subTest(limits=limits), self.assertRaisesRegex(ValueError, 'inspection bounds'):
                read_pages(self.path, **limits)
        pages, markers = read_pages(self.path, max_entries=20000, max_uncompressed_bytes=4 * 1024**3)
        self.assertEqual(markers, list(range(1, 1835)))
        for page, content in pages.items():
            self.assertEqual(content['text'], f'source {page}')
            self.assertEqual(content['images'], [f'EPUB/image-{i}.png' for i in
                                                range((page - 1) * 11245 // 1834, page * 11245 // 1834)])
        self.evaluation(pages=1834)
        self.assertEqual(self.cli().returncode, 1)
        result = self.cli('--max-entries', '20000', '--max-uncompressed-bytes', str(4 * 1024**3))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(json.loads(result.stdout)['passed'])

    def test_default_entry_bound_independently_rejects(self):
        entries, expanded = self.make_epub(images=10000)
        self.assertLess(expanded, DEFAULT_MAX_UNCOMPRESSED_BYTES)
        with self.assertRaisesRegex(ValueError, 'inspection bounds'):
            read_pages(self.path)
        self.assertEqual(len(read_pages(self.path, max_entries=entries)[0][2]['images']), 5000)

    def test_raised_limits_keep_structural_rejections(self):
        limits = dict(max_entries=20000, max_uncompressed_bytes=4 * 1024**3)
        for body, message in [('<span epub:type="pagebreak" id="bad"/>', 'Invalid page boundary'),
                              ('<span epub:type="pagebreak" id="page-1"/>', 'Duplicate page boundary'),
                              ('<span epub:type="pagebreak" id="page-1"/><img src="missing.png"/>',
                               'Missing image asset')]:
            self.make_epub(body=body)
            with self.subTest(body=body), self.assertRaisesRegex(ValueError, message):
                read_pages(self.path, **limits)
        self.make_epub(body='<broken>')
        with self.assertRaises(ET.ParseError):
            read_pages(self.path, **limits)
        self.make_epub()
        with warnings.catch_warnings():
            warnings.simplefilter('ignore', UserWarning)
            with zipfile.ZipFile(self.path, 'a') as archive:
                archive.writestr('EPUB/image-0.png', b'duplicate')
        with self.assertRaisesRegex(ValueError, 'Duplicate archive entries'):
            read_pages(self.path, **limits)

    def evaluation(self, *, pages=2):
        case = dict(id='fixture', sha256='synthetic-source', bytes=100, pages=pages)
        contract = dict(id='fixture', sourceSHA256=case['sha256'], pages=[
            dict(page=1, text=['source 1']), dict(page=2, text=['source 2'], minimumImages=1)])
        (self.directory / 'result.json').write_text(json.dumps(dict(case=case, runPassed=True, conversionExitCode=0)))
        (self.directory / 'conversion-report.json').write_text(json.dumps(dict(pageCount=pages)))
        corpus = self.directory / 'corpus'
        corpus.mkdir()
        (corpus / 'manifest.json').write_text(json.dumps(dict(documents=[case])))
        (corpus / 'regressions.json').write_text(json.dumps(dict(cases=[contract])))
        # The copied script resolves its repository root from its own location, so the fake
        # corpus above is what its command line reads; its package comes along for the same reason.
        tools = self.directory / 'tools'
        tools.mkdir()
        shutil.copytree(ROOT / 'tools/pdfreflow_tools', tools / 'pdfreflow_tools',
                        ignore=shutil.ignore_patterns('__pycache__', 'test_*'))
        self.script = tools / 'check_corpus_content.py'
        shutil.copyfile(ROOT / 'tools/check_corpus_content.py', self.script)
        return case, contract

    def cli(self, *flags):
        return subprocess.run([sys.executable, str(self.script), '--case', 'fixture',
                               '--evaluation', str(self.directory), *flags],
                              text=True, capture_output=True, timeout=30)

    def test_evaluation_and_cli_forward_limits_and_keep_content_checks(self):
        entries, expanded = self.make_epub(images=10000)
        case, contract = self.evaluation()
        with self.assertRaisesRegex(ValueError, 'inspection bounds'):
            check_evaluation(case, contract, self.directory)
        limits = dict(max_entries=entries, max_uncompressed_bytes=expanded)
        self.assertTrue(check_evaluation(case, contract, self.directory, **limits)['passed'])
        self.assertEqual(self.cli().returncode, 1)
        flags = ['--max-entries', str(entries), '--max-uncompressed-bytes', str(expanded)]
        success = self.cli(*flags)
        self.assertEqual(success.returncode, 0, success.stderr)
        self.assertTrue(json.loads(success.stdout)['passed'])
        for restricted in [['--max-entries', str(entries - 1), '--max-uncompressed-bytes', str(expanded)],
                           ['--max-entries', str(entries), '--max-uncompressed-bytes', str(expanded - 1)]]:
            result = self.cli(*restricted)
            self.assertEqual(result.returncode, 1)
            self.assertIn('EPUB exceeds inspection bounds', json.loads(result.stdout)['errors'])
        contract['pages'][0]['text'] = ['missing source']
        (self.directory / 'corpus/regressions.json').write_text(json.dumps(dict(cases=[contract])))
        failed = self.cli(*flags)
        self.assertEqual(failed.returncode, 1)
        self.assertIn('missing text', json.loads(failed.stdout)['errors'][0])

    def test_cli_rejects_invalid_limits_with_usage_error(self):
        self.evaluation()
        for flag in ['--max-entries', '--max-uncompressed-bytes']:
            for value in ['0', '-1', '1.5', 'nan', 'inf', 'true', 'unlimited', '', str(sys.maxsize + 1)]:
                with self.subTest(flag=flag, value=value):
                    result = self.cli(flag, value)
                    self.assertEqual(result.returncode, 2)
                    self.assertIn(flag, result.stderr)
                    self.assertNotIn('Traceback', result.stderr)
                    self.assertEqual(result.stdout, '')

    def test_cli_and_api_defaults_still_pass_small_evaluation(self):
        self.make_epub()
        case, contract = self.evaluation()
        self.assertTrue(check_evaluation(case, contract, self.directory)['passed'])
        result = self.cli()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(json.loads(result.stdout)['passed'])
