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

    def test_furniture_absence_and_real_heading_semantics(self):
        self.contract['pages'][0].update(absentText=['RUNNING HEADER'], headings=['alpha beta'])
        self.pages[1]['headings'] = ['alpha beta']
        self.assertTrue(self.check()['passed'])
        self.pages[1]['text'] += ' RUNNING HEADER'
        self.assertFalse(self.check()['passed'])
        self.pages[1]['text'] = 'alpha beta'
        self.pages[1]['headings'] = []  # Same text in ordinary prose cannot pass.
        self.assertFalse(self.check()['passed'])
        self.pages[2]['headings'] = ['alpha beta']  # Wrong page cannot pass either.
        self.assertFalse(self.check()['passed'])
        for key in ['absentText', 'headings']:
            for phrase in ['', '  ', 123]:
                self.contract['pages'][0][key] = [phrase]
                with self.assertRaises(ValueError):
                    self.check()
                self.contract['pages'][0].pop(key)

    def test_heading_parser_preserves_styling_and_page_ownership(self):
        path = self.epub('<span epub:type="pagebreak" id="page-1"/><h2>al<strong>pha</strong> beta</h2>'
                         '<p>ordinary prose</p><h3>first<span epub:type="pagebreak" id="page-2"/>second</h3>',
                         '<h6>another heading</h6><p>prose</p><figure><figcaption>caption</figcaption></figure>')
        pages, _ = read_pages(path)
        self.assertEqual(pages[1]['headings'], ['alpha beta', 'first'])
        self.assertEqual(pages[2]['headings'], ['second', 'another heading'])
        self.assertNotIn('caption', pages[2]['text'])
        self.assertIn('another heading prose', pages[2]['text'])

    def test_paragraph_contract_requires_semantics_continuity_and_page(self):
        self.contract['pages'][0]['paragraphs'] = ['alpha beta']
        self.pages[1]['paragraphs'] = ['alpha beta']
        self.assertTrue(self.check()['passed'])
        for fragments in [[], ['alpha', 'beta']]:
            self.pages[1]['paragraphs'] = fragments
            self.pages[1]['headings'] = ['alpha beta']
            self.pages[2]['paragraphs'] = ['alpha beta']
            self.assertFalse(self.check()['passed'])
        for phrase in ['', '  ', 123]:
            self.contract['pages'][0]['paragraphs'] = [phrase]
            with self.assertRaises(ValueError):
                self.check()

    def test_paragraph_continuation_requires_one_element_across_the_page_marker(self):
        self.contract['pages'] = [{'page': 1, 'continuedParagraphs': [{'end': 'the sentence', 'next': 'continues here'}]}]
        # Separate chapter files cannot hold one paragraph, so these are also cross-file controls.
        joined = self.epub('<span epub:type="pagebreak" id="page-1"/><p>before</p><p>starts the sentence'
                           '<span epub:type="pagebreak" id="page-2"/> continues here</p>', '<p>later</p>')
        split = self.epub('<span epub:type="pagebreak" id="page-1"/><p>starts the sentence</p>',
                          '<span epub:type="pagebreak" id="page-2"/><p>continues here</p>')
        other = self.epub('<span epub:type="pagebreak" id="page-1"/><p>starts the sentence'
                          '<span epub:type="pagebreak" id="page-2"/></p><p>continues here</p>', '<p>x</p>')
        for path, passes in [(joined, True), (split, False), (other, False)]:
            pages, markers = read_pages(path)
            result = self.check(pages=pages, markers=markers)
            self.assertEqual(result['passed'], passes, result['errors'])
        # Phrases must sit on the correct side of the marker.
        swapped = self.epub('<span epub:type="pagebreak" id="page-1"/><p>continues here'
                            '<span epub:type="pagebreak" id="page-2"/> starts the sentence</p>', '<p>omega</p>')
        pages, markers = read_pages(swapped)
        self.assertFalse(self.check(pages=pages, markers=markers)['passed'])
        for invalid in [{'end': 'x'}, {'end': '', 'next': 'y'}, {'end': 'x', 'next': 1}, ['x', 'y'],
                        {'end': 'x', 'next': 'y', 'extra': 'z'}]:
            self.contract['pages'][0]['continuedParagraphs'] = [invalid]
            with self.assertRaises(ValueError):
                self.check()

    def test_note_contract_requires_a_footnote_block_on_the_page(self):
        self.contract['pages'][0]['notes'] = ['alpha beta']
        self.pages[1]['notes'] = ['alpha beta']
        self.assertTrue(self.check()['passed'])
        self.pages[1]['notes'] = []
        self.pages[1]['paragraphs'] = ['alpha beta']  # Same text in ordinary prose cannot pass.
        self.assertFalse(self.check()['passed'])
        self.pages[2]['notes'] = ['alpha beta']  # Wrong page cannot pass either.
        self.assertFalse(self.check()['passed'])
        self.pages[1]['notes'] = ['alpha', 'beta']  # Split across two notes cannot pass.
        self.assertFalse(self.check()['passed'])
        for phrase in ['', '  ', 123]:
            self.contract['pages'][0]['notes'] = [phrase]
            with self.assertRaises(ValueError):
                self.check()

    def test_note_parser_keeps_note_text_on_its_pages_and_in_its_paragraph(self):
        path = self.epub('<span epub:type="pagebreak" id="page-1"/><p>body one</p>'
                         '<div class="footnote" role="doc-footnote"><p><sup>1</sup> note one'
                         '<span epub:type="pagebreak" id="page-2"/> continues</p></div><p>body two</p>',
                         '<div role="doc-footnote"><p>note two</p></div><p>plain</p>')
        pages, _ = read_pages(path)
        self.assertEqual(pages[1]['notes'], ['1 note one'])
        self.assertEqual(pages[2]['notes'], ['continues', 'note two'])
        self.assertEqual(pages[1]['paragraphs'], ['body one', '1 note one'])
        self.assertEqual(pages[2]['paragraphs'], ['continues', 'body two', 'note two', 'plain'])
        self.assertIn('body one 1 note one', pages[1]['text'])
        # The continued note is one paragraph element across the page marker.
        self.contract['pages'] = [{'page': 1, 'continuedParagraphs': [{'end': 'note one', 'next': 'continues'}]}]
        self.assertTrue(self.check(pages=pages, markers=[1, 2])['passed'])

    def test_paragraph_separation_rejects_a_folio_that_absorbed_the_continuation(self):
        self.contract['pages'] = [{'page': 1, 'separateParagraphs': [{'end': '108', 'next': 'set a bomb'}]}]
        split = self.epub('<span epub:type="pagebreak" id="page-1"/><p>the terrorists who'
                          '<span epub:type="pagebreak" id="page-2"/> set a bomb</p>', '<p>108</p>')
        absorbed = self.epub('<span epub:type="pagebreak" id="page-1"/><p>the terrorists who</p><p>108'
                             '<span epub:type="pagebreak" id="page-2"/> set a bomb</p>', '<p>x</p>')
        for path, passes in [(split, False), (absorbed, False)]:
            pages, markers = read_pages(path)
            self.assertEqual(self.check(pages=pages, markers=markers)['passed'], passes)
        # The split output above fails only because the folio moved after the marker; on its own page it passes.
        kept = self.epub('<span epub:type="pagebreak" id="page-1"/><p>108</p><p>the terrorists who'
                         '<span epub:type="pagebreak" id="page-2"/> set a bomb</p>', '<p>x</p>')
        pages, markers = read_pages(kept)
        self.assertTrue(self.check(pages=pages, markers=markers)['passed'])
        # Both phrases must exist, so a misspelled expectation cannot pass vacuously.
        for missing in [{'end': 'nowhere', 'next': 'set a bomb'}, {'end': '108', 'next': 'nowhere'}]:
            self.contract['pages'][0]['separateParagraphs'] = [missing]
            self.assertFalse(self.check(pages=pages, markers=markers)['passed'])
        for invalid in [{'end': 'x'}, {'end': '', 'next': 'y'}, {'end': 'x', 'next': 1}, ['x', 'y']]:
            self.contract['pages'][0]['separateParagraphs'] = [invalid]
            with self.assertRaises(ValueError):
                self.check(pages=pages, markers=markers)

    def test_paragraph_parser_keeps_inline_styles_and_cross_page_ownership(self):
        path = self.epub('<span epub:type="pagebreak" id="page-1"/><h2>title</h2>'
                         '<p>al<strong>pha</strong> beta<span epub:type="pagebreak" id="page-2"/> gamma</p>',
                         '<pre>code</pre><figure><figcaption><p>caption</p></figcaption></figure><p>delta</p>')
        pages, _ = read_pages(path)
        self.assertEqual(pages[1]['paragraphs'], ['alpha beta'])
        self.assertEqual(pages[2]['paragraphs'], ['gamma', 'delta'])

    def test_absent_warning_codes_reject_the_named_warning_only_on_that_page(self):
        self.contract['pages'][0]['absentWarningCodes'] = ['damagedTextEncoding', 'ocrUsed']
        self.assertTrue(self.check()['passed'])
        self.report['warnings'].append({'page': 1, 'code': 'imageRegion'})
        self.assertTrue(self.check()['passed'])
        self.report['warnings'].append({'page': 2, 'code': 'damagedTextEncoding'})
        self.assertTrue(self.check()['passed'])
        self.report['warnings'].append({'page': 1, 'code': 'damagedTextEncoding'})
        result = self.check()
        self.assertFalse(result['passed'])
        self.assertIn('Page 1: unexpected quality warning damagedTextEncoding', result['errors'])

    def test_invalid_or_empty_contracts_fail(self):
        for pages in [[], [{'page': 1}], [{'page': 3, 'text': ['x']}],
                      [{'page': 1, 'text': ['']}], [{'page': 1, 'text': []}],
                      [{'page': 1, 'absentWarningCodes': []}],
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

    def test_table_cells_are_separate_words_and_the_grid_is_parsed(self):
        path = self.epub('<span epub:type="pagebreak" id="page-1"/><table><thead><tr><th>Entity</th><th>Overview</th></tr></thead>'
                         '<tbody><tr><td colspan="2">Group</td></tr><tr><td>Board</td><td>Promotes stability</td></tr></tbody></table>',
                         '<p>later</p>')
        pages, _ = read_pages(path)
        self.assertEqual(pages[1]['text'], 'Entity Overview Group Board Promotes stability later')
        self.assertEqual(pages[1]['tables'][0]['cells'], [['Entity', 'Overview'], ['Group', 'Group'], ['Board', 'Promotes stability']])
        self.assertEqual(pages[1]['tables'][0]['headerRows'], 1)

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

    def test_script_must_have_correct_style_page_and_context(self):
        expectation = {'tag': 'sup', 'text': '2', 'before': 'quadratic is ax', 'after': '+ bx + c = 0.'}
        self.contract['pages'][0]['scripts'] = [expectation]
        body = '<span epub:type="pagebreak" id="page-1"/><p>alpha beta quadratic is ax<sup><em>2</em> </sup>+ bx + c = 0.</p><img src="picture.png"/>'
        second = '<span epub:type="pagebreak" id="page-2"/><p>omega</p>'
        self.pages, _ = read_pages(self.epub(body, second))
        self.assertTrue(self.check()['passed'])
        for broken in [body.replace('<sup>', '<sub>').replace('</sup>', '</sub>'),
                       body.replace('<sup>', '').replace('</sup>', ''),
                       body.replace('is ax', 'is bx'), body.replace('+ bx', '+ cx')]:
            pages, _ = read_pages(self.epub(broken, second))
            self.assertFalse(self.check(pages=pages)['passed'])
        self.pages[2]['scripts'] = self.pages[1]['scripts']
        self.pages[1]['scripts'] = []
        self.assertFalse(self.check()['passed'])

    def test_preformatted_scripts_are_checked_with_context_and_cannot_be_flattened(self):
        self.contract['pages'][0]['scripts'] = [
            {'tag': 'sup', 'text': '2', 'before': '80) (7a', 'after': '+7a)'},
            {'tag': 'sub', 'text': '2', 'before': 'H', 'after': 'O'},
        ]
        body = ('<span epub:type="pagebreak" id="page-1"/><p>alpha beta</p>'
                '<pre>80) (7a<sup><em>2</em></sup> +7a)\n    H<sub>2</sub>O</pre>'
                '<img src="picture.png"/>')
        pages, _ = read_pages(self.epub(body, ''))
        self.pages[1] = pages[1]
        self.assertTrue(self.check()['passed'])
        for old, new in [('<sup><em>2</em></sup>', '2'), ('<sub>2</sub>', '2'),
                         ('80) (7a', '81) (7a')]:
            pages, _ = read_pages(self.epub(body.replace(old, new), ''))
            self.pages[1] = pages[1]
            self.assertFalse(self.check()['passed'])

    def test_caption_or_literal_markup_cannot_supply_a_script(self):
        for content in ['<figcaption>ax<sup>2</sup>+ b</figcaption>',
                        '<p>ax&lt;sup&gt;2&lt;/sup&gt;+ b</p>']:
            pages, _ = read_pages(self.epub('<span epub:type="pagebreak" id="page-1"/>' + content, ''))
            self.assertEqual(pages[1]['scripts'], [])

    def test_script_crossing_page_boundary_keeps_context_on_its_own_page(self):
        body = '<span epub:type="pagebreak" id="page-1"/><p>x<sup>2<span epub:type="pagebreak" id="page-2"/>3</sup>y</p>'
        pages, _ = read_pages(self.epub(body, ''))
        self.assertEqual(pages[1]['scripts'], [{'tag': 'sup', 'text': '2', 'before': 'x', 'after': ''}])
        self.assertEqual(pages[2]['scripts'], [{'tag': 'sup', 'text': '3', 'before': '', 'after': 'y'}])

    def test_invalid_script_contract_is_not_ignored(self):
        for script in [{}, {'tag': 'span', 'text': '2', 'before': 'a', 'after': 'b'},
                       {'tag': 'sup', 'text': '', 'before': 'a', 'after': 'b'}]:
            self.contract['pages'][0]['scripts'] = [script]
            with self.assertRaises(ValueError):
                self.check()
