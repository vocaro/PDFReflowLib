"""Identity checks fail closed and name their mismatch; loaders read the root they are given."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from pdfreflow_tools import corpus


class IdentityTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.content = b'%PDF-1.7\npinned source\n'
        self.path = self.root / 'source.pdf'
        self.path.write_bytes(self.content)
        self.case = {'id': 'sample', 'filename': 'source.pdf', 'bytes': len(self.content),
                     'sha256': hashlib.sha256(self.content).hexdigest()}

    def test_identity_reports_bytes_and_sha256(self):
        self.assertEqual(corpus.identity(self.path), {'bytes': self.case['bytes'], 'sha256': self.case['sha256']})
        self.assertEqual(corpus.digest(self.path), self.case['sha256'])

    def test_matching_identity_compares_size_before_hashing(self):
        self.assertTrue(corpus.matches_identity(self.path, self.case))
        self.path.write_bytes(b'x' * len(self.content))
        self.assertFalse(corpus.matches_identity(self.path, self.case))
        self.path.write_bytes(self.content + b'!')
        with patch.object(corpus, 'digest') as digest:
            self.assertFalse(corpus.matches_identity(self.path, self.case))
            digest.assert_not_called()

    def test_verification_names_the_mismatch(self):
        self.assertEqual(corpus.verify_source(self.path, self.case), self.path)
        self.path.write_bytes(self.content[:-1])
        with self.assertRaisesRegex(ValueError, '^sample source byte count mismatch$'):
            corpus.verify_source(self.path, self.case)
        self.path.write_bytes(b'x' * len(self.content))
        with self.assertRaisesRegex(ValueError, '^sample source checksum mismatch$'):
            corpus.verify_source(self.path, self.case)
        with self.assertRaisesRegex(ValueError, '^FAA source checksum mismatch$'):
            corpus.verify_source(self.path, self.case, 'FAA')

    def test_missing_file_is_an_error_not_a_mismatch(self):
        for check in [corpus.matches_identity, corpus.verify_source, corpus.identity]:
            with self.subTest(check=check.__name__), self.assertRaises(FileNotFoundError):
                check(self.root / 'absent.pdf', self.case) if check is not corpus.identity else check(self.root / 'absent.pdf')


class ManifestTests(unittest.TestCase):
    def test_root_is_the_package_repository(self):
        self.assertTrue((corpus.ROOT / 'Package.swift').is_file())
        self.assertTrue((corpus.ROOT / 'corpus/manifest.json').is_file())
        self.assertTrue((corpus.FIXTURES / 'manifest.json').is_file())
        self.assertTrue(corpus.manifest_cases())
        self.assertTrue(corpus.regression_contracts()['cases'])

    def test_loaders_read_the_given_root(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'corpus').mkdir()
            cases = [{'id': 'first', 'filename': 'first.pdf'}, {'id': 'second', 'filename': 'second.pdf'}]
            (root / 'corpus/manifest.json').write_text(json.dumps({'documents': cases}))
            (root / 'corpus/regressions.json').write_text(json.dumps({'cases': [{'id': 'second'}]}))
            self.assertEqual(corpus.manifest_cases(root), cases)
            self.assertEqual(corpus.regression_contracts(root), {'cases': [{'id': 'second'}]})
            self.assertEqual(corpus.find_case(cases, 'second'), cases[1])
            self.assertIsNone(corpus.find_case(cases, 'third'))
            self.assertEqual(corpus.cached_source(cases[0], root), root / 'corpus/cache/first.pdf')


if __name__ == '__main__':
    unittest.main()
