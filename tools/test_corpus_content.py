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

    def test_image_maximum_counts_images_on_its_page(self):
        self.contract['pages'][1]['maximumImages'] = 0
        self.assertTrue(self.check()['passed'])
        self.pages[2]['images'] = ['rule.png']
        result = self.check()
        self.assertFalse(result['passed'])
        self.assertIn('Page 2: 1 images, at most 0 expected', result['errors'])
        self.contract['pages'][1]['maximumImages'] = 1
        self.assertTrue(self.check()['passed'])
        for invalid in (-1, True, 1.0, '0'):
            self.contract['pages'][1]['maximumImages'] = invalid
            with self.assertRaises(ValueError):
                self.check()

    def test_page_reference_expectation_distinguishes_references_from_other_images(self):
        self.contract['pages'][0]['pageReference'] = False
        self.assertTrue(self.check()['passed'])
        self.pages[1]['pageReferences'] = ['page-1.png']
        result = self.check()
        self.assertFalse(result['passed'])
        self.assertIn('Page 1: unexpected source-page reference image', result['errors'])
        self.contract['pages'][0]['pageReference'] = True
        self.assertTrue(self.check()['passed'])
        del self.pages[1]['pageReferences']
        result = self.check()
        self.assertFalse(result['passed'])
        self.assertIn('Page 1: missing source-page reference image', result['errors'])
        for invalid in (0, 1, 'false', None):
            self.contract['pages'][0]['pageReference'] = invalid
            with self.assertRaises(ValueError):
                self.check()

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

    def test_presentation_form_ligatures_fail_on_any_page(self):
        # #189: every Latin ligature U+FB00-U+FB06 fails, on a page with or without expectations.
        self.assertTrue(self.check()['passed'])
        for ligature in '\ufb00\ufb01\ufb02\ufb03\ufb04\ufb05\ufb06':
            pages = {1: dict(self.pages[1]), 2: dict(self.pages[2], text='omega di' + ligature + 'erent')}
            result = self.check(pages=pages)
            self.assertFalse(result['passed'])
            self.assertIn('Presentation-form ligature', ' '.join(result['errors']))
        # Controls: the spelled-out letters, the neighbouring code points and other compatibility forms pass.
        for text in ('omega different', 'omega \ufaff \ufb07 \ufb13', 'omega x\u00b2 \u00bd \uff46 \u0133'):
            self.assertTrue(self.check(pages={1: self.pages[1], 2: dict(self.pages[2], text=text)})['passed'], text)

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

    def test_heading_level_contract_rejects_flattened_and_re_ranked_headings(self):
        self.contract['pages'][0]['headingLevels'] = [{'heading': 'alpha beta', 'level': 2}]
        self.pages[1]['headings'] = ['alpha beta']
        self.pages[1]['headingLevels'] = [(2, 'alpha beta')]
        self.assertTrue(self.check()['passed'])
        # The same heading one tier deeper fails, naming the level it was written at.
        self.pages[1]['headingLevels'] = [(3, 'alpha beta')]
        result = self.check()
        self.assertFalse(result['passed'])
        self.assertIn("Page 1: heading 'alpha beta' at level [3] not 2", result['errors'])
        # A heading flattened to a paragraph fails as a missing heading.
        self.pages[1]['headingLevels'] = []
        result = self.check()
        self.assertFalse(result['passed'])
        self.assertIn("Page 1: missing heading 'alpha beta'", result['errors'])
        # The same text as a heading on another page cannot satisfy this page.
        self.pages[2]['headingLevels'] = [(2, 'alpha beta')]
        self.assertFalse(self.check()['passed'])
        # Two headings holding the phrase must agree on the level.
        self.pages[1]['headingLevels'] = [(2, 'alpha beta'), (4, 'alpha beta gamma')]
        self.assertFalse(self.check()['passed'])
        for invalid in ([], {'heading': 'alpha beta'}, {'level': 2}, 'alpha beta',
                        {'heading': '', 'level': 2}, {'heading': 'alpha beta', 'level': 0},
                        {'heading': 'alpha beta', 'level': 7}, {'heading': 'alpha beta', 'level': True},
                        {'heading': 'alpha beta', 'level': '2'},
                        {'heading': 'alpha beta', 'level': 2, 'page': 1}):
            self.contract['pages'][0]['headingLevels'] = [invalid]
            with self.assertRaises(ValueError):
                self.check()

    def test_heading_parser_records_each_heading_level(self):
        path = self.epub('<span epub:type="pagebreak" id="page-1"/><h2>alpha</h2><h5>beta</h5>',
                         '<span epub:type="pagebreak" id="page-2"/><h3>gamma</h3><p>prose</p>')
        pages, _ = read_pages(path)
        self.assertEqual(pages[1]['headingLevels'], [(2, 'alpha'), (5, 'beta')])
        self.assertEqual(pages[2]['headingLevels'], [(3, 'gamma')])

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

    def test_paragraph_continuation_past_a_page_holding_only_figures(self):
        # #118: page 2 holds only a figure; both page markers sit at the text boundary.
        self.contract['pages'] = [{'page': 1, 'continuedParagraphs': [
            {'end': 'the sentence', 'next': 'continues here', 'nextPage': 3}]}]
        joined = self.epub('<span epub:type="pagebreak" id="page-1"/><p>starts the sentence'
                           '<span epub:type="pagebreak" id="page-2"/><span epub:type="pagebreak" id="page-3"/>'
                           ' continues here</p>', '<p>later</p>')
        # Page 2 carries text of its own: the paragraph skipped it.
        texted = self.epub('<span epub:type="pagebreak" id="page-1"/><p>starts the sentence'
                           '<span epub:type="pagebreak" id="page-2"/> a body line of page two'
                           '<span epub:type="pagebreak" id="page-3"/> continues here</p>', '<p>later</p>')
        split = self.epub('<span epub:type="pagebreak" id="page-1"/><p>starts the sentence</p>'
                          '<span epub:type="pagebreak" id="page-2"/><span epub:type="pagebreak" id="page-3"/>'
                          '<p>continues here</p>', '<p>later</p>')
        self.case['pages'] = self.report['pageCount'] = 3
        for path, passes in [(joined, True), (texted, False), (split, False)]:
            pages, markers = read_pages(path)
            result = self.check(pages=pages, markers=markers)
            self.assertEqual(result['passed'], passes, (path, result['errors']))
        # A page between that the reader never saw cannot be vouched for as empty.
        pages, markers = read_pages(joined)
        del pages[2]
        result = self.check(pages=pages, markers=markers)
        self.assertEqual(result['errors'], ["Page 1: paragraph does not continue onto page 3 "
                                            "{'end': 'the sentence', 'next': 'continues here', 'nextPage': 3}"])
        # Without nextPage the same output does not continue onto page 2.
        self.contract['pages'][0]['continuedParagraphs'] = [{'end': 'the sentence', 'next': 'continues here'}]
        pages, markers = read_pages(joined)
        self.assertFalse(self.check(pages=pages, markers=markers)['passed'])
        for invalid in [2, 1, 0, '3', True, 3.0]:
            self.contract['pages'][0]['continuedParagraphs'] = [
                {'end': 'the sentence', 'next': 'continues here', 'nextPage': invalid}]
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

    def test_pull_quote_contract_requires_a_pull_quote_aside_on_the_page(self):
        self.contract['pages'][0]['pullQuotes'] = ['alpha beta']
        self.pages[1]['pullQuotes'] = ['alpha beta']
        self.assertTrue(self.check()['passed'])
        self.pages[1]['pullQuotes'] = []
        self.pages[1]['paragraphs'] = ['alpha beta']  # The same words as prose cannot pass.
        self.pages[1]['headings'] = ['alpha beta']  # Nor as a heading.
        self.assertFalse(self.check()['passed'])
        self.pages[2]['pullQuotes'] = ['alpha beta']  # Nor on the wrong page.
        self.assertFalse(self.check()['passed'])
        for phrase in ['', '  ', 123]:
            self.contract['pages'][0]['pullQuotes'] = [phrase]
            with self.assertRaises(ValueError):
                self.check()

    def test_pull_quote_parser_reads_the_aside_and_its_paragraph(self):
        path = self.epub('<span epub:type="pagebreak" id="page-1"/><p>body one</p>'
                         '<aside class="pullquote" role="doc-pullquote"><p>“quoted words.”—A Speaker</p></aside>'
                         '<p>body two</p>', '<span epub:type="pagebreak" id="page-2"/><p>page two</p>')
        pages, _ = read_pages(path)
        self.assertEqual(pages[1]['pullQuotes'], ['“quoted words.”—A Speaker'])
        self.assertEqual(pages[1]['paragraphs'], ['body one', '“quoted words.”—A Speaker', 'body two'])
        self.assertEqual(pages[1]['headings'], [])

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

    def note_link_pages(self, first=None, second=None):
        first = first if first is not None else (
            '<span epub:type="pagebreak" id="page-1"/><p>Scheduled at 7:45.'
            '<sup><a epub:type="noteref" role="doc-noteref" id="noteref-c1-4" href="a.xhtml#note-c1-4">4</a></sup> In another'
            ' terminal<sup><a epub:type="noteref" role="doc-noteref" href="a.xhtml#note-c1-4">4</a></sup> plain<sup>9</sup></p>')
        second = second if second is not None else (
            '<span epub:type="pagebreak" id="page-2"/><p id="note-c1-4" epub:type="endnote">'
            '<a href="z.xhtml#noteref-c1-4" role="doc-backlink" epub:type="backlink">4.</a> Flight 11 pushed'
            '<span epub:type="pagebreak" id="page-3"/> back.</p><p id="note-c2-4">4. Other chapter.</p>')
        return read_pages(self.epub(first, second))

    def note_link_check(self, link, pages, markers):
        self.case['pages'] = 3
        self.report['pageCount'] = 3
        self.contract['pages'] = [{'page': 1, 'noteLinks': [link]}]
        return self.check(pages=pages, markers=markers)

    def test_note_link_parser_follows_hrefs_and_accumulates_note_text_across_pages(self):
        pages, markers = self.note_link_pages()
        self.assertEqual(markers, [1, 2, 3])
        self.assertEqual([(r['text'], r['id']) for r in pages[1]['noterefs']], [('4', 'noteref-c1-4'), ('4', None)])
        self.assertTrue(pages[1]['noterefs'][0]['before'].endswith('Scheduled at 7:45.'))
        self.assertTrue(pages[1]['noterefs'][1]['before'].endswith('In another terminal'))
        note = pages[2]['anchors']['EPUB/a.xhtml#note-c1-4']
        self.assertEqual((note['page'], note['text'], note['backlink']), (2, '4. Flight 11 pushed back.', 'z.xhtml#noteref-c1-4'))
        self.assertEqual(pages[1]['text'], 'Scheduled at 7:45.4 In another terminal4 plain9')

    def test_note_links_resolve_marker_note_page_and_return_link(self):
        pages, markers = self.note_link_pages()
        link = {'marker': '4', 'before': 'at 7:45.', 'note': 'Flight 11 pushed back', 'notePage': 2}
        self.assertTrue(self.note_link_check(link, pages, markers)['passed'])
        # A repeated reference links to the same note; the return link goes to the first reference.
        self.assertTrue(self.note_link_check(dict(link, before='In another terminal'), pages, markers)['passed'])
        self.assertTrue(self.note_link_check({'marker': '4', 'before': 'at 7:45.', 'note': 'Flight 11'}, pages, markers)['passed'])
        for change, message in [(dict(before='at 7:46.'), 'missing linked marker'),
                                (dict(marker='9', before='plain'), 'missing linked marker'),
                                (dict(note='Other chapter'), 'wrong note'),
                                (dict(notePage=3), 'not 3')]:
            result = self.note_link_check(dict(link, **change), pages, markers)
            self.assertFalse(result['passed'])
            self.assertIn(message, result['errors'][0])

    def test_note_links_reject_missing_targets_and_absent_or_misdirected_return_links(self):
        link = {'marker': '4', 'before': 'at 7:45.', 'note': 'Flight 11 pushed back', 'notePage': 2}
        broken = ('<span epub:type="pagebreak" id="page-1"/><p>Scheduled at 7:45.'
                  '<sup><a epub:type="noteref" role="doc-noteref" id="noteref-c1-4" href="a.xhtml#note-c1-7">4</a></sup></p>')
        pages, markers = self.note_link_pages(first=broken)
        result = self.note_link_check(link, pages, markers)
        self.assertFalse(result['passed'])
        self.assertIn('missing note', result['errors'][0])
        second = ('<span epub:type="pagebreak" id="page-2"/><p id="note-c1-4" epub:type="endnote">4. Flight 11 pushed back.</p>'
                  '<span epub:type="pagebreak" id="page-3"/>')
        result = self.note_link_check(link, *self.note_link_pages(second=second))
        self.assertFalse(result['passed'])
        self.assertIn('return link', result['errors'][0])
        misdirected = second.replace('endnote">4.', 'endnote"><a href="z.xhtml#noteref-c1-9" role="doc-backlink" epub:type="backlink">4.</a>')
        result = self.note_link_check(link, *self.note_link_pages(second=misdirected))
        self.assertFalse(result['passed'])
        self.assertIn('return link', result['errors'][0])
        for invalid in [{'marker': '4', 'before': 'x'}, {'marker': '', 'before': 'x', 'note': 'y'},
                        {'marker': '4', 'before': 'x', 'note': 'y', 'notePage': 0},
                        {'marker': '4', 'before': 'x', 'note': 'y', 'extra': 1}, 'text']:
            with self.assertRaises(ValueError):
                self.note_link_check(invalid, *self.note_link_pages())

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

    def test_paragraph_distinction_rejects_a_lead_in_merged_into_the_paragraph_above(self):
        self.contract['pages'] = [{'page': 1, 'distinctParagraphs': [
            {'first': 'tons of copper.', 'second': 'Substitutes: Aluminum'}]}]
        split = self.epub('<span epub:type="pagebreak" id="page-1"/><p>resources contained tons of copper.</p>'
                          '<p><strong>Substitutes:</strong> Aluminum substitutes for copper.</p>'
                          '<span epub:type="pagebreak" id="page-2"/>', '<p>x</p>')
        merged = self.epub('<span epub:type="pagebreak" id="page-1"/><p>resources contained tons of copper. '
                           '<strong>Substitutes:</strong> Aluminum substitutes for copper.</p>'
                           '<span epub:type="pagebreak" id="page-2"/>', '<p>x</p>')
        for path, passes in [(split, True), (merged, False)]:
            pages, markers = read_pages(path)
            self.assertEqual(self.check(pages=pages, markers=markers)['passed'], passes)
        # Both passages must exist, so a misspelled expectation cannot pass vacuously.
        pages, markers = read_pages(split)
        for missing in [{'first': 'nowhere', 'second': 'Substitutes: Aluminum'},
                        {'first': 'tons of copper.', 'second': 'nowhere'}]:
            self.contract['pages'][0]['distinctParagraphs'] = [missing]
            self.assertFalse(self.check(pages=pages, markers=markers)['passed'])
        for invalid in [{'first': 'x'}, {'first': '', 'second': 'y'}, {'first': 'x', 'second': 1}, ['x', 'y']]:
            self.contract['pages'][0]['distinctParagraphs'] = [invalid]
            with self.assertRaises(ValueError):
                self.check(pages=pages, markers=markers)

    def test_preformatted_lines_need_one_block_with_each_line_whole_and_in_order(self):
        self.contract['pages'] = [{'page': 1, 'preformattedLines': [
            ['TAF', 'FM1500 16015G25KT P6SM SCT040 BKN250', 'FM120400 1408KT P6SM']]}]
        def book(body):
            return self.epub('<span epub:type="pagebreak" id="page-1"/>' + body + '<span epub:type="pagebreak" id="page-2"/>', '<p>x</p>')
        kept = book('<pre>TAF\nKPIR 111130Z\nFM1500 16015G25KT P6SM SCT040 BKN250\nFM120400 1408KT P6SM</pre>')
        merged = book('<pre>TAF KPIR 111130Z FM1500 16015G25KT P6SM SCT040 BKN250 FM120400 1408KT P6SM</pre>')
        split = book('<pre>TAF\nFM1500 16015G25KT P6SM SCT040 BKN250</pre><pre>FM120400 1408KT P6SM</pre>')
        paragraphs = book('<p>TAF</p><p>FM1500 16015G25KT P6SM SCT040 BKN250</p><p>FM120400 1408KT P6SM</p>')
        reordered = book('<pre>TAF\nFM120400 1408KT P6SM\nFM1500 16015G25KT P6SM SCT040 BKN250</pre>')
        for path, passes in [(kept, True), (merged, False), (split, False), (paragraphs, False), (reordered, False)]:
            pages, markers = read_pages(path)
            self.assertEqual(self.check(pages=pages, markers=markers)['passed'], passes, str(path))
        pages, markers = read_pages(kept)
        # A line must be whole: a prefix of a longer line does not match.
        self.contract['pages'][0]['preformattedLines'] = [['TAF', 'FM1500 16015G25KT']]
        self.assertFalse(self.check(pages=pages, markers=markers)['passed'])
        for invalid in [['TAF'], ['TAF', ''], ['TAF', 1], 'TAF']:
            self.contract['pages'][0]['preformattedLines'] = [invalid]
            with self.assertRaises(ValueError):
                self.check(pages=pages, markers=markers)

    def test_math_expression_pins_markup_alternative_text_and_label(self):
        # A crop written as MathML (#190): the expression's own markup is the evidence, so a wrong
        # token, a term moved across the bar, a lost exponent or a wrong label fails, and the
        # expression's tokens never count as page text.
        math = ('<p class="math">52) <math xmlns="http://www.w3.org/1998/Math/MathML" alttext="{alt}" '
                'altimg="picture.png">{body}</math></p>')
        def book(body, alt='27/3', label=None):
            markup = math.format(alt=alt, body=body)
            if label is not None:
                markup = markup.replace('52)', label)
            return self.epub('<span epub:type="pagebreak" id="page-1"/>' + markup
                             + '<span epub:type="pagebreak" id="page-2"/>', '<p>x</p>')
        fraction = '<mfrac><mn>27</mn><mn>3</mn></mfrac>'
        self.contract['pages'] = [{'page': 1, 'mathExpressions': [
            {'mathml': fraction, 'alttext': '27/3', 'label': '52)'}]}]
        cases = [
            (book(fraction), True),
            (book('<mfrac><mn>27</mn><mn>8</mn></mfrac>'), False),
            (book('<mfrac><mn>3</mn><mn>27</mn></mfrac>'), False),
            (book('<mn>27</mn><mn>3</mn>'), False),
            (book(fraction, alt='27 3'), False),
            (book(fraction, label='53)'), False),
        ]
        for path, passes in cases:
            pages, markers = read_pages(path)
            self.assertEqual(self.check(pages=pages, markers=markers)['passed'], passes, str(path))
        pages, _ = read_pages(cases[0][0])
        self.assertEqual(pages[1]['text'], '52)')
        self.assertEqual(pages[1]['math'][0]['fallback'], 'EPUB/picture.png')
        # A lost exponent changes the markup.
        self.contract['pages'] = [{'page': 1, 'mathExpressions': [
            {'mathml': '<msup><mi>x</mi><mn>2</mn></msup>'}]}]
        pages, markers = read_pages(book('<msup><mi>x</mi><mn>2</mn></msup>', alt='x^2'))
        self.assertTrue(self.check(pages=pages, markers=markers)['passed'])
        pages, markers = read_pages(book('<mi>x</mi><mn>2</mn>', alt='x^2'))
        self.assertFalse(self.check(pages=pages, markers=markers)['passed'])
        for invalid in [{}, {'mathml': ''}, {'mathml': 'x', 'other': 'y'}, 'x']:
            self.contract['pages'] = [{'page': 1, 'mathExpressions': [invalid]}]
            with self.assertRaises(ValueError):
                self.check(pages=pages, markers=markers)
        # The fallback image must exist.
        with self.assertRaises(ValueError):
            read_pages(self.epub('<span epub:type="pagebreak" id="page-1"/>' + math.format(alt='x', body='<mi>x</mi>')
                                 + '<span epub:type="pagebreak" id="page-2"/>', '<p>x</p>', missing_image=True))

    def test_list_items_and_preformatted_blocks_read_their_own_elements(self):
        # A list item is an <li>; a list-shaped line the converter keeps preformatted is a <pre>.
        # Neither check is satisfied by the other element, nor by a paragraph (#194).
        def book(body):
            return self.epub('<span epub:type="pagebreak" id="page-1"/>' + body + '<span epub:type="pagebreak" id="page-2"/>', '<p>x</p>')
        self.contract['pages'] = [{'page': 1, 'listItems': ['Alternator switch'],
                                   'preformattedBlocks': ['1) 1− 3']}]
        kept = book('<ul><li>Alternator switch</li></ul><pre>1) 1− 3</pre>')
        swapped = book('<pre>• Alternator switch</pre><ol><li>1− 3</li></ol>')
        prose = book('<p>Alternator switch</p><p>1) 1− 3</p>')
        for path, passes in [(kept, True), (swapped, False), (prose, False)]:
            pages, markers = read_pages(path)
            self.assertEqual(self.check(pages=pages, markers=markers)['passed'], passes, str(path))
        pages, markers = read_pages(kept)
        for key in ('listItems', 'preformattedBlocks'):
            for invalid in ['', 1]:
                self.contract['pages'] = [{'page': 1, key: [invalid]}]
                with self.assertRaises(ValueError):
                    self.check(pages=pages, markers=markers)

    def test_list_expectation_pins_kind_start_depth_and_consecutive_items(self):
        self.contract['pages'] = [{'page': 1, 'lists': [
            {'kind': 'ol', 'start': 3, 'items': ['Third step', 'Fourth step']},
            {'kind': 'ul', 'level': 1, 'items': ['A detail', 'Another detail']}]}]
        def book(body):
            return self.epub('<span epub:type="pagebreak" id="page-1"/>' + body + '<span epub:type="pagebreak" id="page-2"/>', '<p>x</p>')
        kept = book('<ol start="3"><li>Third step</li><li>Fourth step<ul><li>A detail</li><li>Another detail</li></ul></li></ol>')
        renumbered = book('<ol><li>Third step</li><li>Fourth step<ul><li>A detail</li><li>Another detail</li></ul></li></ol>')
        split = book('<ol start="3"><li>Third step</li></ol><ol start="4"><li>Fourth step<ul><li>A detail</li><li>Another detail</li></ul></li></ol>')
        flattened = book('<ol start="3"><li>Third step</li><li>Fourth step</li></ol><ul><li>A detail</li><li>Another detail</li></ul>')
        bulleted = book('<ul><li>Third step</li><li>Fourth step<ul><li>A detail</li><li>Another detail</li></ul></li></ul>')
        reordered = book('<ol start="3"><li>Fourth step<ul><li>A detail</li><li>Another detail</li></ul></li><li>Third step</li></ol>')
        for path, passes in [(kept, True), (renumbered, False), (split, False), (flattened, False),
                             (bulleted, False), (reordered, False)]:
            pages, markers = read_pages(path)
            self.assertEqual(self.check(pages=pages, markers=markers)['passed'], passes, str(path))
        pages, markers = read_pages(kept)
        # A nested list's words stay apart from its item's own text.
        self.assertIn('Fourth step A detail Another detail', pages[1]['text'])
        self.assertEqual(pages[1]['listItems'], ['Third step', 'Fourth step', 'A detail', 'Another detail'])
        for invalid in [{'kind': 'dl', 'items': ['x']}, {'kind': 'ol', 'items': []}, {'kind': 'ol', 'items': ['']},
                        {'kind': 'ul', 'start': 2, 'items': ['x']}, {'kind': 'ol', 'start': '3', 'items': ['x']},
                        {'kind': 'ol', 'items': ['x'], 'extra': 1}, ['x']]:
            self.contract['pages'] = [{'page': 1, 'lists': [invalid]}]
            with self.assertRaises(ValueError):
                self.check(pages=pages, markers=markers)

    def test_page_marker_opening_a_list_item_starts_the_page_and_a_list_holds_only_items(self):
        # The converter puts a page marker inside the item it precedes (#194); the item, and the
        # list's place in the page sequence, belong to the new page.
        self.contract['pages'] = [{'page': 2, 'listItems': ['Fifth step'],
                                   'lists': [{'kind': 'ol', 'start': 4, 'items': ['Fourth step', 'Fifth step']}]}]
        path = self.epub('<span epub:type="pagebreak" id="page-1"/><ol start="4"><li>Fourth step</li>'
                         '<li><span epub:type="pagebreak" id="page-2"/>Fifth step</li></ol>', '<p>x</p>')
        pages, markers = read_pages(path)
        self.assertEqual(markers, [1, 2])
        self.assertEqual(pages[1]['listItems'], ['Fourth step'])
        self.assertEqual(pages[2]['listItems'], ['Fifth step'])
        self.assertEqual(pages[1]['blocks'], [('text', 'Fourth step')])
        self.assertEqual(pages[2]['blocks'], [('text', 'Fifth step'), ('text', 'x')])
        self.assertTrue(self.check(pages=pages, markers=markers)['passed'])
        # Negative controls: a marker, or a block, directly inside the list is refused.
        for body in ['<ol><li>Fourth step</li><span epub:type="pagebreak" id="page-2"/><li>Fifth step</li></ol>',
                     '<ul><li>a</li><p>b</p></ul>', '<ol start="0"><li>a</li></ol>']:
            with self.assertRaises(ValueError):
                read_pages(self.epub('<span epub:type="pagebreak" id="page-1"/>' + body, '<p>x</p>'))

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
        # A phrase holding a presentation-form ligature could never be found (#189).
        self.assertNotRegex(json.dumps(definitions, ensure_ascii=False), '[ﬀ-ﬆ]')
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

    def test_page_reference_is_read_from_title_and_alternative_text(self):
        """#187: the reference carries its provenance in `title`; a fallback shares the title only."""
        def references(image):
            pages, _ = read_pages(self.epub('<span epub:type="pagebreak" id="page-1"/>' + image, ''))
            return pages[1].get('pageReferences', [])
        self.assertEqual(references('<img src="picture.png" alt="The printed page, for comparison" title="Source page 1"/>'),
                         ['EPUB/picture.png'])
        # EPUBs from before #187 name it in `alt`, so baselines still compare.
        self.assertEqual(references('<img src="picture.png" alt="Original page 1"/>'), ['EPUB/picture.png'])
        for image in ['<img src="picture.png" alt="Whole page kept as an image" title="Source page 1"/>',
                      '<img src="picture.png" alt="The printed page, for comparison" title="Source page 2"/>',
                      '<img src="picture.png" alt="The printed page, for comparison"/>',
                      '<img src="picture.png" alt="Illustration" title="Preserved region from page 1"/>']:
            self.assertEqual(references(image), [], image)

    def test_image_alternatives_require_the_text_and_no_provenance_beside_it(self):
        pages, _ = read_pages(self.epub(
            '<span epub:type="pagebreak" id="page-1"/><p>alpha beta</p>'
            '<figure><img src="picture.png" alt="Figure  3. The  rake" title="Preserved region from page 1"/></figure>', ''))
        self.assertEqual(pages[1]['alternatives'], ['Figure 3. The rake'])
        self.contract['pages'][0]['imageAlternatives'] = ['Figure 3. The rake']
        self.pages[1]['alternatives'] = ['Figure 3. The rake', 'Mathematical expression']
        self.assertTrue(self.check()['passed'])
        self.contract['pages'][0]['imageAlternatives'] = ['Figure 3. The rake', 'Mathematical expression']
        self.assertTrue(self.check()['passed'])
        # A kind the page does not carry fails.
        self.contract['pages'][0]['imageAlternatives'] = ['Table kept as an image']
        result = self.check()
        self.assertFalse(result['passed'])
        self.assertIn("Page 1: no image carries the alternative text 'Table kept as an image'", result['errors'])
        # Provenance or nothing in any image's alternative text fails the page, as before #187.
        self.contract['pages'][0]['imageAlternatives'] = ['Figure 3. The rake']
        for bad in ['Preserved region from page 1', 'Original page 1', '']:
            self.pages[1]['alternatives'] = ['Figure 3. The rake', bad]
            self.assertFalse(self.check()['passed'], bad)
        for invalid in ([], 'Illustration', [''], [3]):
            self.contract['pages'][0]['imageAlternatives'] = invalid
            with self.assertRaises(ValueError):
                self.check()

    def test_captions_do_not_satisfy_text_and_missing_assets_fail(self):
        body = '<span epub:type="pagebreak" id="page-1"/><figure><img src="picture.png"/><figcaption>alpha beta</figcaption></figure>'
        pages, _ = read_pages(self.epub(body, ''))
        self.assertEqual(pages[1]['text'], '')
        self.assertEqual(pages[1]['images'], ['EPUB/picture.png'])
        with self.assertRaises(ValueError):
            read_pages(self.epub(body, '', missing_image=True))

    def test_block_sequence_records_images_and_outermost_blocks_only(self):
        body = ('<span epub:type="pagebreak" id="page-1"/><h2>title</h2>'
                '<figure><img src="picture.png"/><figcaption>generic caption</figcaption></figure>'
                '<p>Figure 1. the rake</p>'
                '<table><tr><td>cell one</td><td>cell two</td></tr></table>')
        pages, _ = read_pages(self.epub(body, ''))
        # The figure's own generic caption never enters, and a table's cells do not become
        # blocks of their own beside it.
        self.assertEqual(pages[1]['blocks'],
                         [('text', 'title'), ('image', 'EPUB/picture.png'),
                          ('text', 'Figure 1. the rake'), ('text', 'cell one cell two')])

    def test_block_sequence_keeps_only_what_a_split_block_holds_on_its_own_page(self):
        path = self.epub('<span epub:type="pagebreak" id="page-1"/><p>opens here'
                         '<span epub:type="pagebreak" id="page-2"/>and closes there</p>', '<p>later</p>')
        pages, _ = read_pages(path)
        self.assertEqual(pages[1]['blocks'], [('text', 'opens here')])
        self.assertEqual(pages[2]['blocks'], [('text', 'later')])

    def test_captioned_image_requires_the_caption_beside_its_figure(self):
        self.contract['pages'] = [{'page': 1, 'captionedImages': [
            {'caption': 'Figure 3. Illustration of instrumentation rake'}]}]
        marker = '<span epub:type="pagebreak" id="page-1"/>'
        rest = '<span epub:type="pagebreak" id="page-2"/><p>omega</p>'
        figure = '<figure><img src="picture.png"/><figcaption>Preserved region from page 1</figcaption></figure>'
        caption = '<p>Figure 3. Illustration of instrumentation rake with instrument locations</p>'
        prose = '<p>Target Profile Determination</p>'
        for body, passes in [(marker + figure + caption, True),
                             # The caption drifted away from its figure.
                             (marker + figure + prose + caption, False),
                             # The figure is gone, although the caption text survives.
                             (marker + prose + caption, False),
                             # The caption reads before the figure, not after it.
                             (marker + caption + figure, False)]:
            pages, markers = read_pages(self.epub(body, rest))
            result = self.check(pages=pages, markers=markers)
            self.assertEqual(result['passed'], passes, result['errors'])
        # A caption the page does not hold at all is reported as missing, not as misplaced.
        pages, markers = read_pages(self.epub(marker + figure + prose, rest))
        result = self.check(pages=pages, markers=markers)
        self.assertIn("Page 1: no block holds the caption 'Figure 3. Illustration of "
                      "instrumentation rake'", result['errors'])
        # A table caption set above its table is the same assertion the other way round.
        self.contract['pages'][0]['captionedImages'] = [
            {'caption': 'TABLE I: A 6-flight example.', 'position': 'before'}]
        table = '<p>TABLE I: A 6-flight example.</p>'
        for body, passes in [(marker + table + figure, True), (marker + figure + table, False),
                             (marker + table + prose + figure, False)]:
            pages, markers = read_pages(self.epub(body, rest))
            result = self.check(pages=pages, markers=markers)
            self.assertEqual(result['passed'], passes, result['errors'])
        # The same caption on another page cannot satisfy this one.
        self.contract['pages'][0]['captionedImages'] = [{'caption': 'TABLE I: A 6-flight example.'}]
        pages, markers = read_pages(self.epub(marker, '<span epub:type="pagebreak" id="page-2"/>'
                                              + figure + table))
        self.assertFalse(self.check(pages=pages, markers=markers)['passed'])
        for invalid in [{}, {'position': 'after'}, {'caption': ''}, {'caption': 3},
                        {'caption': 'x', 'position': 'beside'}, {'caption': 'x', 'page': 1}, 'x']:
            self.contract['pages'][0]['captionedImages'] = [invalid]
            with self.assertRaises(ValueError):
                self.check()

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

    def test_absent_script_rejects_the_script_with_its_tag_text_and_context(self):
        body = ('<span epub:type="pagebreak" id="page-1"/><p>alpha beta</p><p><sup>• </sup>Under the Medicare program</p>'
                '<p>citizen of <em>(foreign nation) </em><sub>.</sub></p><img src="picture.png"/>')
        second = '<span epub:type="pagebreak" id="page-2"/><p>omega</p>'
        pages, _ = read_pages(self.epub(body, second))
        for expectation in [{'tag': 'sup', 'text': '•'},
                            {'tag': 'sub', 'text': '.', 'before': '(foreign nation)'},
                            {'tag': 'sup', 'text': '•', 'after': 'Under the Medicare'}]:
            self.contract['pages'][0]['absentScripts'] = [expectation]
            self.assertFalse(self.check(pages=pages)['passed'], expectation)
        # Controls: the plain text passes; another tag, text or context does not match.
        plain = body.replace('<sup>• </sup>', '• ').replace('<sub>.</sub>', '.')
        clean, _ = read_pages(self.epub(plain, second))
        for expectation in [{'tag': 'sup', 'text': '•'}, {'tag': 'sub', 'text': '.', 'before': '(foreign nation)'}]:
            self.contract['pages'][0]['absentScripts'] = [expectation]
            self.assertTrue(self.check(pages=clean)['passed'], expectation)
        for expectation in [{'tag': 'sub', 'text': '•'}, {'tag': 'sup', 'text': '.'},
                            {'tag': 'sub', 'text': '.', 'before': '(domestic nation)'},
                            {'tag': 'sup', 'text': '•', 'after': 'Under the Medicaid'}]:
            self.contract['pages'][0]['absentScripts'] = [expectation]
            self.assertTrue(self.check(pages=pages)['passed'], expectation)
        for invalid in [{}, {'tag': 'span', 'text': '.'}, {'tag': 'sub', 'text': ''},
                        {'tag': 'sub', 'text': '.', 'before': ''}, {'tag': 'sub', 'text': '.', 'page': 2}]:
            self.contract['pages'][0]['absentScripts'] = [invalid]
            with self.assertRaises(ValueError):
                self.check(pages=pages)

    def test_invalid_script_contract_is_not_ignored(self):
        for script in [{}, {'tag': 'span', 'text': '2', 'before': 'a', 'after': 'b'},
                       {'tag': 'sup', 'text': '', 'before': 'a', 'after': 'b'}]:
            self.contract['pages'][0]['scripts'] = [script]
            with self.assertRaises(ValueError):
                self.check()
