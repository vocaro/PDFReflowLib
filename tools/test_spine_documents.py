import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('epub_contracts', Path(__file__).with_name('check-epubs.py'))
contracts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(contracts)


def document(body):
    return ('<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">'
            '<head><title>test</title></head><body>' + body + '</body></html>').encode()


class NoteLinkPairingTests(unittest.TestCase):
    """Note references and return links must resolve to each other through their actual hrefs."""

    @staticmethod
    def documents(first, second):
        import xml.etree.ElementTree as ET
        return {'EPUB/chapter-1.xhtml': ET.fromstring(document(first)), 'EPUB/chapter-2.xhtml': ET.fromstring(document(second))}

    reference = ('<p>Body<sup><a epub:type="noteref" role="doc-noteref" id="noteref-c1-4" href="chapter-2.xhtml#note-c1-4">4</a></sup>'
                 ' again<sup><a epub:type="noteref" role="doc-noteref" href="chapter-2.xhtml#note-c1-4">4</a></sup></p>')
    note = ('<p id="note-c1-4" epub:type="endnote"><a href="chapter-1.xhtml#noteref-c1-4" role="doc-backlink" epub:type="backlink">4.</a>'
            ' Note.</p>')

    def test_paired_links_across_files_pass(self):
        contracts.check_note_links(self.documents(self.reference, self.note))
        same = self.reference.replace('chapter-2.xhtml#', '#') + self.note.replace('chapter-1.xhtml#', '#')
        contracts.check_note_links(self.documents(same, '<p>x</p>'))

    def test_missing_note_wrong_return_link_and_stray_backlink_fail(self):
        cases = [
            ('note reference without a note', self.reference, '<p id="note-c1-5">5. Other.</p>'),
            ('exactly one return link', self.reference, '<p id="note-c1-4">4. No return.</p>'),
            ('return link misses its reference', self.reference, self.note.replace('#noteref-c1-4', '#page-1') + '<p id="page-1">x</p>'),
            ('another note', self.reference + '<p id="note-c1-9"><a href="#noteref-c1-4" role="doc-backlink" epub:type="backlink">9.</a></p>'
             '<sup><a epub:type="noteref" role="doc-noteref" id="noteref-c1-9" href="#note-c1-9">9</a></sup>',
             self.note.replace('chapter-1.xhtml#noteref-c1-4', 'chapter-1.xhtml#noteref-c1-9')),
            ('return link without a reference', '<p>x</p>', '<p><a href="#nowhere" role="doc-backlink" epub:type="backlink">↩</a></p>'),
            ('noteref without epub:type', self.reference.replace('epub:type="noteref" ', ''), self.note),
            ('backlink without epub:type', self.reference, self.note.replace(' epub:type="backlink"', '')),
        ]
        for message, first, second in cases:
            with self.assertRaisesRegex(AssertionError, message):
                contracts.check_note_links(self.documents(first, second))


class SpineDocumentTests(unittest.TestCase):
    def test_exact_target_and_markup_accounting(self):
        body = '<p>' + 'a' * 59_993 + '</p>'
        self.assertEqual(contracts.check_spine_document(document(body)),
                         {'bodyBytes': 60_000, 'oversizedAtomicBlock': False})
        with self.assertRaisesRegex(AssertionError, 'multiple blocks'):
            contracts.check_spine_document(document(body + '<p>x</p>'))

    def test_utf8_and_escaping_count_as_serialized_bytes(self):
        body = '<p>' + '😸&amp;' * 4_000 + '</p>'
        result = contracts.check_spine_document(document(body))
        self.assertEqual(result['bodyBytes'], len(body.encode()))
        with self.assertRaisesRegex(AssertionError, 'multiple blocks'):
            contracts.check_spine_document(document(body * 2))

    def test_one_oversized_styled_block_and_its_source_marker_are_allowed(self):
        marker = '<span epub:type="pagebreak" id="page-1"/>'
        body = marker + '<p><strong>' + 'x' * 60_001 + '</strong></p>'
        self.assertTrue(contracts.check_spine_document(document(body))['oversizedAtomicBlock'])
        with self.assertRaisesRegex(AssertionError, 'unrelated page markers'):
            contracts.check_spine_document(document(marker + body))

    def test_oversize_cannot_hide_unwrapped_text_or_unexpected_elements(self):
        for body in ['x' * 60_001 + '<p>y</p>', '<p>y</p>' + 'x' * 60_001,
                     '<div>' + 'x' * 60_001 + '</div>']:
            with self.assertRaises(AssertionError):
                contracts.check_spine_document(document(body))

    def test_short_headings_may_precede_one_oversized_block(self):
        marker = '<span epub:type="pagebreak" id="page-1"/>'
        block = '<p>' + 'x' * 60_001 + '</p>'
        for body in [marker + '<h2 id="a">Section</h2>' + block, '<h1 id="a">Part</h1><h2 id="b">Section</h2>' + block]:
            self.assertTrue(contracts.check_spine_document(document(body))['oversizedAtomicBlock'])
        for body in ['<h2 id="a">' + 'h' * 6_000 + '</h2>' + block,
                     '<h2 id="a">Section</h2><p>other</p>' + block,
                     block + '<h2 id="a">Trailing</h2>']:
            with self.assertRaisesRegex(AssertionError, 'multiple blocks'):
                contracts.check_spine_document(document(body))

    def test_trailing_heading_size_ignores_markers_and_stops_at_content(self):
        run = '<h2 id="a">A</h2>\n<span epub:type="pagebreak" id="page-2"/><h3 id="b">B</h3>'
        self.assertEqual(contracts.trailing_heading_bytes(('<p>text</p>\n' + run + '\n').encode()), len(run))
        self.assertEqual(contracts.trailing_heading_bytes(b'<h2 id="a">A</h2>\n<p>text</p>\n'), 0)
        self.assertEqual(contracts.trailing_heading_bytes(b'<p>text</p><span epub:type="pagebreak" id="page-2"/>'), 0)
        # An earlier heading must not extend the run across intervening paragraphs.
        spread = b'<h2 id="x">Early</h2>\n<p>' + b'p' * 7_000 + b'</p>\n<h2 id="y">Late</h2>\n'
        self.assertEqual(contracts.trailing_heading_bytes(spread), len(b'<h2 id="y">Late</h2>'))


class SpineContinuityTests(unittest.TestCase):
    def epub(self, bodies):
        import tempfile, zipfile
        directory = tempfile.TemporaryDirectory(); self.addCleanup(directory.cleanup)
        path = Path(directory.name) / 'book.epub'
        items = ''.join(f'<item id="c{i}" href="chapter-{i}.xhtml" media-type="application/xhtml+xml"/>' for i in range(len(bodies)))
        spine = ''.join(f'<itemref idref="c{i}"/>' for i in range(len(bodies)))
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr(zipfile.ZipInfo('mimetype'), 'application/epub+zip')
            archive.writestr('EPUB/package.opf', '<package xmlns="http://www.idpf.org/2007/opf" version="3.0"><manifest>'
                             '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>' + items +
                             '</manifest><spine>' + spine + '</spine></package>')
            archive.writestr('EPUB/nav.xhtml', document('<p>nav</p>'))
            for i, body in enumerate(bodies):
                archive.writestr(f'EPUB/chapter-{i}.xhtml', document(body))
        return path

    def test_heading_must_not_end_a_document_before_its_content(self):
        with self.assertRaisesRegex(AssertionError, 'separated from its content'):
            contracts.check(self.epub(['<h2 id="z">Intro</h2><p>one</p><h2 id="a">Section</h2>', '<p>two</p>']))
        with self.assertRaisesRegex(AssertionError, 'separated from its content'):
            contracts.check(self.epub(['<p>one</p><h2 id="a">A</h2><span epub:type="pagebreak" id="page-2"/>', '<p>two</p>']))
        self.assertIn('Section two', contracts.check(self.epub(['<p>one</p>', '<h2 id="a">Section</h2><p>two</p>'])))
        # The final document and long heading runs are not separated content.
        contracts.check(self.epub(['<p>one</p>', '<p>two</p><h2 id="a">Appendix</h2>']))
        contracts.check(self.epub(['<p>one</p><h2 id="a">' + 'h' * 6_000 + '</h2>', '<p>two</p>']))

