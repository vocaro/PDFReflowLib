import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('epub_contracts', Path(__file__).with_name('check-epubs.py'))
contracts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(contracts)


def document(body):
    return ('<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">'
            '<head><title>test</title></head><body>' + body + '</body></html>').encode()


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
