import json
from pathlib import Path
import tempfile
import unittest
import zipfile

from check_corpus_content import ROOT, assess, read_pages


class CorpusContentTests(unittest.TestCase):
    def setUp(self):
        self.case = {'id': 'fixture', 'sha256': 'source', 'bytes': 100, 'pages': 2}
        self.contract = {'sourceSHA256': 'source', 'pages': [
            {'page': 1, 'text': ['alpha beta'], 'orderedText': ['alpha', 'beta'], 'minimumImages': 1},
            {'page': 2, 'text': ['omega'], 'warningCodesAnyOf': ['unverifiedTextLayer']}]}
        self.result = {'case': self.case, 'runPassed': True, 'conversionExitCode': 0}
        self.report = {'pageCount': 2, 'warnings': [{'page': 2, 'code': 'unverifiedTextLayer'}]}
        self.pages = {1: {'text': 'alpha beta', 'images': ['picture.png']},
                      2: {'text': 'omega', 'images': []}}

    def check(self, **changes):
        values = dict(case=self.case, contract=self.contract, result=self.result,
                      report=self.report, pages=self.pages, markers=[1, 2])
        values.update(changes)
        return assess(**values)

    def test_positive_control_and_lost_text(self):
        self.assertTrue(self.check()['passed'])
        self.pages[1]['text'] = 'alpha'
        self.assertFalse(self.check()['passed'])

    def test_text_on_wrong_page_does_not_pass(self):
        self.pages[1]['text'], self.pages[2]['text'] = 'omega', 'alpha beta'
        self.assertFalse(self.check()['passed'])

    def test_reversed_order_and_repeated_phrase_fail(self):
        self.contract['pages'][0]['text'] = []
        self.pages[1]['text'] = 'beta alpha'
        self.assertFalse(self.check()['passed'])
        self.contract['pages'][0]['orderedText'] = ['alpha', 'alpha']
        self.assertFalse(self.check()['passed'])

    def test_images_and_quality_warnings_are_required(self):
        self.pages[1]['images'] = []
        self.assertFalse(self.check()['passed'])
        self.pages[1]['images'] = ['picture.png']
        self.report['warnings'][0]['code'] = 'imageRegion'
        self.assertFalse(self.check()['passed'])
        self.report['warnings'][0] = {'page': 1, 'code': 'unverifiedTextLayer'}
        self.assertFalse(self.check()['passed'])

    def test_source_identity_failed_conversion_and_missing_pages_fail(self):
        for field, value in [('sha256', 'other'), ('bytes', 99), ('pages', 3), ('id', 'other')]:
            result = dict(self.result, case=dict(self.case, **{field: value}))
            self.assertFalse(self.check(result=result)['passed'])
        self.assertFalse(self.check(result=dict(self.result, runPassed=False))['passed'])
        self.assertFalse(self.check(result=dict(self.result, conversionExitCode=1))['passed'])
        for markers in [[1], [2, 1], [1, 1, 2]]:
            self.assertFalse(self.check(markers=markers)['passed'])
        self.pages[2]['text'] += '\ufffc'
        self.assertFalse(self.check()['passed'])

    def test_invalid_or_empty_contracts_fail(self):
        for pages in [[], [{'page': 1}], [{'page': 3, 'text': ['x']}],
                      [{'page': 1, 'text': ['']}], [{'page': 1, 'text': []}],
                      [{'page': 1, 'minimumImages': 0}]]:
            with self.assertRaises(ValueError):
                self.check(contract={'sourceSHA256': 'source', 'pages': pages})

    def test_manifest_contracts_have_pinned_sources_and_useful_checks(self):
        cases = {c['id']: c for c in json.loads((ROOT / 'corpus/manifest.json').read_text())['documents']}
        definitions = json.loads((ROOT / 'corpus/regressions.json').read_text())
        ids = [c['id'] for c in definitions['cases']]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertTrue(ids)
        for contract in definitions['cases']:
            case = cases[contract['id']]
            self.assertEqual(case['sha256'], contract['sourceSHA256'])
            self.assertTrue(contract['basis'])
            result = assess(case, contract, {}, {}, {}, [])
            self.assertGreater(result['contentChecks'], 0)
            self.assertFalse(result['passed'])
        excluded = [c['id'] for c in definitions['excludedFullConversions']]
        self.assertFalse(set(ids) & set(excluded))
        self.assertEqual(set(ids) | set(excluded), set(cases))

    def epub(self, first, second, *, reverse=False, missing_image=False):
        directory = tempfile.TemporaryDirectory(); self.addCleanup(directory.cleanup)
        path = Path(directory.name) / 'book.epub'
        opf = '<package xmlns="http://www.idpf.org/2007/opf"><manifest><item id="a" href="z.xhtml"/><item id="b" href="a.xhtml"/></manifest><spine>'
        opf += ''.join(f'<itemref idref="{i}"/>' for i in (['b', 'a'] if reverse else ['a', 'b']))
        opf += '</spine></package>'
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr('EPUB/package.opf', opf)
            for name, body in [('z.xhtml', first), ('a.xhtml', second)]:
                archive.writestr('EPUB/' + name, '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body>' + body + '</body></html>')
            if not missing_image:
                archive.writestr('EPUB/picture.png', b'test asset; this test checks presence only')
        return path

    def test_spine_order_inline_styling_and_continuation_across_files(self):
        path = self.epub('<span epub:type="pagebreak" id="page-1"/><p>al<strong>pha</strong> beta</p>',
                         '<p>continued</p><span epub:type="pagebreak" id="page-2"/><p>omega</p>')
        pages, markers = read_pages(path)
        self.assertEqual(markers, [1, 2])
        self.assertEqual(pages[1]['text'], 'alpha beta continued')
        self.assertEqual(pages[2]['text'], 'omega')

    def test_inline_page_boundary_splits_text_at_its_true_position(self):
        path = self.epub('<span epub:type="pagebreak" id="page-1"/><p>conver<span epub:type="pagebreak" id="page-2"/>sion</p>', '<p>later</p>')
        pages, markers = read_pages(path)
        self.assertEqual(markers, [1, 2])
        self.assertEqual(pages[1]['text'], 'conver')
        self.assertEqual(pages[2]['text'], 'sion later')

    def test_captions_do_not_satisfy_text_and_missing_assets_fail(self):
        body = '<span epub:type="pagebreak" id="page-1"/><figure><img src="picture.png"/><figcaption>alpha beta</figcaption></figure>'
        pages, _ = read_pages(self.epub(body, ''))
        self.assertEqual(pages[1]['text'], '')
        self.assertEqual(pages[1]['images'], ['EPUB/picture.png'])
        with self.assertRaises(ValueError):
            read_pages(self.epub(body, '', missing_image=True))

    def test_duplicate_anchors_are_rejected(self):
        marker = '<span epub:type="pagebreak" id="page-1"/>'
        with self.assertRaises(ValueError):
            read_pages(self.epub(marker, marker))
