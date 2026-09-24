import json
from pathlib import Path
import tempfile
import unittest
import zipfile

from check_corpus_content import ROOT, assess, read_pages, read_spine


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

    def test_original_page_reference_is_distinct_from_a_region_image(self):
        self.contract['pages'][0]['originalPageImage'] = True
        self.assertFalse(self.check()['passed'])
        self.pages[1]['originalPageImage'] = True
        self.assertTrue(self.check()['passed'])
        self.contract['pages'][0]['originalPageImage'] = False
        with self.assertRaises(ValueError):
            self.check()
        path = self.epub('<span epub:type="pagebreak" id="page-1"/>'
                         '<img src="picture.png" alt="Preserved region from page 1"/>'
                         '<img src="picture.png" alt="Original page 1"/>',
                         '<span epub:type="pagebreak" id="page-2"/>')
        pages, _ = read_pages(path)
        self.assertTrue(pages[1]['originalPageImage'])
        self.assertFalse(pages[2]['originalPageImage'])

    def test_source_identity_failed_conversion_and_missing_pages_fail(self):
        for field, value in [('sha256', 'other'), ('bytes', 99), ('pages', 3), ('id', 'other')]:
            result = dict(self.result, case=dict(self.case, **{field: value}))
            self.assertFalse(self.check(result=result)['passed'])
        self.assertFalse(self.check(result=dict(self.result, runPassed=False))['passed'])
        self.assertFalse(self.check(result=dict(self.result, conversionExitCode=1))['passed'])
        # A ceiling host memory pressure left unmeasured is not a verdict on the content, but it
        # excuses nothing else: every other gate still has to have passed (decision 0009).
        unmeasured = dict(self.result, runPassed=False, memoryGate={'status': 'notMeasured'})
        self.assertFalse(self.check(result=unmeasured)['passed'])
        self.assertTrue(self.check(result=dict(unmeasured, gatesPassedApartFromMemory=True))['passed'])
        self.assertFalse(self.check(result=dict(unmeasured, gatesPassedApartFromMemory=False))['passed'])
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

    def test_display_blocks_require_their_semantics_whole_text_and_page(self):
        for kind in ('asides', 'quotations'):
            self.contract['pages'][0][kind] = ['alpha beta']
            self.pages[1][kind] = ['alpha beta']
            self.assertTrue(self.check()['passed'])
            for fragments in ([], ['alpha', 'beta']):
                self.pages[1][kind] = fragments
                self.pages[1]['paragraphs'] = ['alpha beta']
                self.pages[2][kind] = ['alpha beta']
                self.assertFalse(self.check()['passed'])
            for phrase in ('', '  ', 123):
                self.contract['pages'][0][kind] = [phrase]
                with self.assertRaises(ValueError):
                    self.check()
            del self.contract['pages'][0][kind]

    def test_display_parser_keeps_inline_styling_block_boundaries_and_page_ownership(self):
        path = self.epub('<span epub:type="pagebreak" id="page-1"/>'
                         '<aside><p>al<strong>pha</strong> beta</p><p>next</p></aside>'
                         '<blockquote><p>quoted <em>words</em>'
                         '<span epub:type="pagebreak" id="page-2"/> continued</p></blockquote>',
                         '<p>ordinary</p><aside><p>another summary</p></aside>')
        pages, _ = read_pages(path)
        self.assertEqual(pages[1]['asides'], ['alpha beta next'])
        self.assertEqual(pages[2]['asides'], ['another summary'])
        self.assertEqual(pages[1]['quotations'], ['quoted words'])
        self.assertEqual(pages[2]['quotations'], ['continued'])
        self.assertEqual(pages[1]['headings'], [])

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

    def test_preformatted_contract_separates_items_from_paragraphs(self):
        """A `<pre>` item cannot be satisfied by a paragraph, by another item, or by both halves."""
        self.contract['pages'][0]['preformatted'] = ['17) (1, 2)']
        self.pages[1]['preformatted'] = ['17) (1, 2)']
        self.assertTrue(self.check()['passed'])
        for blocks in [[], ['17)', '(1, 2)'], ['18) (1, 2)']]:
            self.pages[1]['preformatted'] = blocks
            self.pages[1]['paragraphs'] = ['17) (1, 2)']
            self.pages[2]['preformatted'] = ['17) (1, 2)']
            self.assertFalse(self.check()['passed'])
        for phrase in ['', '  ', 123]:
            self.contract['pages'][0]['preformatted'] = [phrase]
            with self.assertRaises(ValueError):
                self.check()

    def test_absent_preformatted_targets_detached_stub_without_rejecting_math_text(self):
        self.contract['pages'][0]['absentPreformatted'] = ['23) (2)(−']
        self.pages[1]['text'] += ' 23) (2)(−2/9)'
        self.pages[1]['preformatted'] = []
        self.assertTrue(self.check()['passed'])
        self.pages[1]['preformatted'] = ['23) (2)(−']
        self.assertFalse(self.check()['passed'])
        self.pages[1]['preformatted'] = []
        self.pages[2]['preformatted'] = ['23) (2)(−']
        self.assertTrue(self.check()['passed'])
        for phrase in ['', '  ', 123]:
            self.contract['pages'][0]['absentPreformatted'] = [phrase]
            with self.assertRaises(ValueError):
                self.check()

    def test_preformatted_parser_reads_one_block_at_a_time(self):
        path = self.epub('<span epub:type="pagebreak" id="page-1"/><pre>17) <em>(1, 2)</em></pre>'
                         '<pre>18) (3, 4)</pre><p>prose</p>',
                         '<span epub:type="pagebreak" id="page-2"/><pre>19) (5, 6)</pre>')
        pages, _ = read_pages(path)
        self.assertEqual(pages[1]['preformatted'], ['17) (1, 2)', '18) (3, 4)'])
        self.assertEqual(pages[2]['preformatted'], ['19) (5, 6)'])
        self.assertEqual(pages[1]['paragraphs'], ['prose'])

    def test_list_contract_pins_kind_start_and_consecutive_items(self):
        """A list check names one element's kind, start and items in order (#292)."""
        self.contract['pages'][0]['lists'] = [{'kind': 'ol', 'start': 3, 'items': ['third step', 'fourth step']}]
        whole = {'kind': 'ol', 'start': 3, 'items': ['third step of the procedure', 'fourth step of the procedure']}
        self.pages[1]['lists'] = [whole]
        self.assertTrue(self.check()['passed'])
        # A longer list holding the phrases in consecutive items passes; one held apart does not.
        self.pages[1]['lists'] = [dict(whole, items=['second'] + whole['items'] + ['fifth'])]
        self.assertTrue(self.check()['passed'])
        for shapes in [[], [dict(whole, kind='ul', start=None)], [dict(whole, start=1)],
                       [dict(whole, items=list(reversed(whole['items'])))],
                       [dict(whole, items=whole['items'][:1]), dict(whole, start=4, items=whole['items'][1:])],
                       [dict(whole, items=[whole['items'][0], 'a stranger', whole['items'][1]])]]:
            self.pages[1]['lists'] = shapes
            self.pages[1]['paragraphs'] = whole['items']
            self.pages[2]['lists'] = [whole]
            self.assertFalse(self.check()['passed'], shapes)
        # A bulleted list names no start, and a check without one accepts any start.
        self.contract['pages'][0]['lists'] = [{'kind': 'ul', 'items': ['first', 'second']}]
        self.pages[1]['lists'] = [{'kind': 'ul', 'start': None, 'items': ['first item', 'second item']}]
        self.assertTrue(self.check()['passed'])
        self.contract['pages'][0]['lists'] = [{'kind': 'ol', 'items': ['first', 'second']}]
        self.pages[1]['lists'] = [{'kind': 'ol', 'start': 7, 'items': ['first item', 'second item']}]
        self.assertTrue(self.check()['passed'])
        for invalid in [{'kind': 'ol'}, {'items': ['a']}, {'kind': 'dl', 'items': ['a']}, {'kind': 'ul', 'items': []},
                        {'kind': 'ul', 'items': ['a', '']}, {'kind': 'ul', 'items': 'a'}, {'kind': 'ul', 'items': ['a'], 'start': 1},
                        {'kind': 'ol', 'items': ['a'], 'start': 0}, {'kind': 'ol', 'items': ['a'], 'start': '2'},
                        {'kind': 'ol', 'items': ['a'], 'level': 0}, ['ul', 'a']]:
            self.contract['pages'][0]['lists'] = [invalid]
            with self.assertRaises(ValueError):
                self.check()

    def test_list_parser_reads_lists_on_the_pages_their_items_open_and_refuses_non_items(self):
        path = self.epub('<span epub:type="pagebreak" id="page-1"/><ol start="3"><li>third <em>step</em></li>'
                         '<li><span epub:type="pagebreak" id="page-2"/>fourth step</li></ol><p>prose</p>',
                         '<ul><li>alpha</li><li>beta<span epub:type="pagebreak" id="page-3"/></li></ul><pre>1) 5</pre>')
        pages, markers = read_pages(path)
        self.assertEqual(markers, [1, 2, 3])
        ordered = {'kind': 'ol', 'start': 3, 'items': ['third step', 'fourth step']}
        unordered = {'kind': 'ul', 'start': None, 'items': ['alpha', 'beta']}
        self.assertEqual(pages[1]['lists'], [ordered])
        self.assertEqual(pages[2]['lists'], [ordered, unordered])
        self.assertEqual(pages[3]['lists'], [])
        self.assertIn('fourth step', pages[2]['text'])
        self.assertNotIn('fourth step', pages[1]['text'])
        self.assertEqual(pages[3]['preformatted'], ['1) 5'])
        for body in ['<span epub:type="pagebreak" id="page-1"/><ul><li>a</li><span epub:type="pagebreak" id="page-2"/><li>b</li></ul>',
                     '<span epub:type="pagebreak" id="page-1"/><ul><li>a</li><p>b</p></ul>',
                     '<span epub:type="pagebreak" id="page-1"/><ul>stray<li>a</li></ul>',
                     '<span epub:type="pagebreak" id="page-1"/><ol start="0"><li>a</li><li>b</li></ol>']:
            with self.assertRaises(ValueError):
                read_pages(self.epub(body, '<p>x</p>'))

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

    def test_table_row_must_match_every_cell_of_a_row(self):
        self.contract['pages'][0] = {'page': 1, 'tableRows': [['Chile', '5,250', '5,300']]}
        self.pages[1]['tableRows'] = [['Country', '2023', '2024'], ['Chile', '5,250', '5,300']]
        self.assertTrue(self.check()['passed'])
        # A cell lost changes the row's length; a value read into the wrong column changes the row.
        self.pages[1]['tableRows'] = [['Chile', '5,250']]
        self.assertFalse(self.check()['passed'])
        self.pages[1]['tableRows'] = [['Chile 5,250', '', '5,300']]
        self.assertFalse(self.check()['passed'])
        # A page with no table at all fails the check rather than passing it vacuously.
        self.pages[1].pop('tableRows')
        self.assertFalse(self.check()['passed'])

    def test_table_rows_are_read_from_the_cells_of_each_row(self):
        body = ('<span epub:type="pagebreak" id="page-1"/>'
                '<table><thead><tr><th colspan="2">Mine production</th><th>Reserves</th></tr></thead>'
                '<tbody><tr><td>Chile</td><td>5,250</td><td>190,000</td></tr></tbody></table>')
        pages, _, _ = read_spine(self.spine(body))
        self.assertEqual(pages[1]['tableRows'],
                         [['Mine production', 'Reserves'], ['Chile', '5,250', '190,000']])
        # A cell's text is still part of the page's text, separated from its neighbours.
        self.assertIn('Chile 5,250 190,000', pages[1]['text'])

    def test_invalid_or_empty_contracts_fail(self):
        for pages in [[], [{'page': 1}], [{'page': 3, 'text': ['x']}],
                      [{'page': 1, 'text': ['']}], [{'page': 1, 'text': []}],
                      [{'page': 1, 'absentWarningCodes': []}],
                      [{'page': 1, 'tableRows': [['one']]}],
                      [{'page': 1, 'tableRows': ['not a row']}],
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

    def spine(self, *bodies):
        """An EPUB whose spine holds these bodies in order, for boundary checks."""
        directory = tempfile.TemporaryDirectory(); self.addCleanup(directory.cleanup)
        path = Path(directory.name) / 'book.epub'
        names = [f'part-{index}.xhtml' for index in range(len(bodies))]
        opf = '<package xmlns="http://www.idpf.org/2007/opf"><manifest>'
        opf += ''.join(f'<item id="i{index}" href="{name}"/>' for index, name in enumerate(names))
        opf += '</manifest><spine>' + ''.join(f'<itemref idref="i{index}"/>' for index in range(len(bodies)))
        opf += '</spine></package>'
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr('EPUB/package.opf', opf)
            for name, body in zip(names, bodies):
                archive.writestr('EPUB/' + name, '<html xmlns="http://www.w3.org/1999/xhtml" '
                                 'xmlns:epub="http://www.idpf.org/2007/ops"><body>' + body + '</body></html>')
        return path

    def continuity(self, *bodies, **changes):
        pages, markers, documents = read_spine(self.spine(*bodies))
        return self.check(pages=pages, markers=markers, documents=documents, **changes)

    def test_spine_boundary_continuity_requires_adjacency_order_and_no_duplication(self):
        self.contract = {'sourceSHA256': 'source', 'pages': [{'page': 1, 'text': ['alpha']}], 'spineContinuity': [
            {'sourcePages': [1, 2], 'beforeBoundary': ['alpha', 'ends one document'],
             'afterBoundary': ['opens the next'], 'contiguous': True}]}
        opens = '<span epub:type="pagebreak" id="page-2"/><p>opens the next document</p>'
        ends = '<span epub:type="pagebreak" id="page-1"/><p>alpha ends one document</p>'
        self.assertTrue(self.continuity(ends, opens)['passed'])
        self.assertEqual(self.continuity(ends, opens)['spineBoundariesCrossed'], 1)
        # Where the packer ends a document follows from its byte target, so a join it keeps
        # inside one document is intact text, not a failure; it just crosses no boundary.
        inside = (ends + opens.replace('<span epub:type="pagebreak" id="page-2"/>', '')
                  + '<span epub:type="pagebreak" id="page-2"/><p>tail</p>', '<p>later</p>')
        self.assertTrue(self.continuity(*inside)['passed'])
        self.assertEqual(self.continuity(*inside)['spineBoundariesCrossed'], 0)
        # A join inside one document is still held to the same text: an inserted sentence breaks it.
        self.assertFalse(self.continuity(
            ends + '<p>an inserted sentence</p>' + opens.replace('<span epub:type="pagebreak" id="page-2"/>', '')
            + '<span epub:type="pagebreak" id="page-2"/><p>tail</p>', '<p>later</p>')['passed'])
        # The reverse order, text between the two sides, or text repeated anywhere breaks the join.
        for bodies in [(opens.replace('page-2', 'page-1'), ends.replace('page-1', 'page-2')),
                       (ends, '<span epub:type="pagebreak" id="page-2"/><p>an inserted sentence</p>'
                        '<p>opens the next document</p>'),
                       (ends, opens + '<p>alpha ends one document again</p>'),
                       (ends, '<span epub:type="pagebreak" id="page-2"/><p>only a fragment</p>')]:
            self.assertFalse(self.continuity(*bodies)['passed'], bodies)
        # The documents on both sides must carry the reviewed source pages.
        self.contract['spineContinuity'][0]['sourcePages'] = [2, 2]
        self.assertFalse(self.continuity(ends, opens)['passed'])
        # A boundary two documents away is not the boundary the contract reviewed.
        self.contract['spineContinuity'][0]['sourcePages'] = [1, 2]
        self.assertFalse(self.continuity(ends, '<p>a whole document in between</p>', opens)['passed'])

    def test_spine_boundary_continuity_tolerates_a_gap_only_when_unreviewed(self):
        self.contract = {'sourceSHA256': 'source', 'pages': [{'page': 1, 'text': ['alpha']}], 'spineContinuity': [
            {'sourcePages': [1, 2], 'beforeBoundary': ['alpha'], 'afterBoundary': ['opens the next']}]}
        bodies = ('<span epub:type="pagebreak" id="page-1"/><p>alpha ends one document</p>',
                  '<span epub:type="pagebreak" id="page-2"/><p>a caption first</p><p>opens the next</p>')
        self.assertTrue(self.continuity(*bodies)['passed'])
        self.contract['spineContinuity'][0]['contiguous'] = True
        self.assertFalse(self.continuity(*bodies)['passed'])

    def test_invalid_spine_boundary_contracts_are_not_ignored(self):
        bodies = ('<span epub:type="pagebreak" id="page-1"/><p>alpha ends one document</p>',
                  '<span epub:type="pagebreak" id="page-2"/><p>opens the next</p>')
        for entry in [{'sourcePages': [1, 2], 'beforeBoundary': ['alpha']},
                      {'sourcePages': [1, 2], 'beforeBoundary': ['alpha'], 'afterBoundary': []},
                      {'sourcePages': [1, 2], 'beforeBoundary': ['alpha'], 'afterBoundary': ['  ']},
                      {'sourcePages': [1, 2], 'beforeBoundary': 'alpha', 'afterBoundary': ['x']},
                      {'sourcePages': [], 'beforeBoundary': ['alpha'], 'afterBoundary': ['x']},
                      {'sourcePages': [2, 1], 'beforeBoundary': ['alpha'], 'afterBoundary': ['x']},
                      {'sourcePages': [1, 3], 'beforeBoundary': ['alpha'], 'afterBoundary': ['x']},
                      {'sourcePages': [1, 2], 'beforeBoundary': ['alpha'], 'afterBoundary': ['x'], 'extra': 1},
                      {'sourcePages': [1, 2], 'beforeBoundary': ['alpha'], 'afterBoundary': ['x'], 'contiguous': 'yes'},
                      ['alpha', 'x']]:
            self.contract = {'sourceSHA256': 'source', 'pages': [{'page': 1, 'text': ['alpha']}],
                             'spineContinuity': [entry]}
            with self.assertRaises(ValueError, msg=entry):
                self.continuity(*bodies)

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

    def test_mathml_requires_source_structure_and_an_existing_fallback(self):
        self.contract['pages'][0].pop('minimumImages')
        expectation = {'alttext': 'n^2', 'structure': 'msup(mi(n),mn(2))'}
        self.contract['pages'][0]['math'] = [expectation]
        opening = '<span epub:type="pagebreak" id="page-1"/><p>alpha beta</p>'
        math = ('<math xmlns="http://www.w3.org/1998/Math/MathML" alttext="n^2" altimg="picture.png">'
                '<msup><mi>n</mi><mn>2</mn></msup></math>')
        second = '<span epub:type="pagebreak" id="page-2"/><p>omega</p>'
        self.pages, _ = read_pages(self.epub(opening + math, second))
        self.assertEqual(self.pages[1]['math'], [{**expectation, 'fallback': True}])
        self.assertTrue(self.check()['passed'])
        for changed in [math.replace('msup', 'msub'),
                        math.replace('<mi>n</mi><mn>2</mn>', '<mn>2</mn><mi>n</mi>'),
                        math.replace('alttext="n^2"', 'alttext="n2"'),
                        math.replace('altimg="picture.png"', '')]:
            pages, _ = read_pages(self.epub(opening + changed, second))
            self.assertFalse(self.check(pages=pages)['passed'])
        pages, _ = read_pages(self.epub(opening + math, second, missing_image=True))
        self.assertFalse(self.check(pages=pages)['passed'])
        pages, _ = read_pages(self.epub(opening, second + math))
        self.assertFalse(self.check(pages=pages)['passed'])
        for malformed in [{}, {'alttext': '', 'structure': 'msup(mi(n),mn(2))'},
                          {'alttext': 'n^2', 'structure': 'msup(mi(n),mn(2))', 'fallback': True}]:
            self.contract['pages'][0]['math'] = [malformed]
            with self.assertRaises(ValueError):
                self.check()

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
