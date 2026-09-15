import hashlib
import io
from pathlib import Path
import tempfile
import unittest

from fetch_corpus import fetch_case


class FetchCorpusTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.cache = Path(self.directory.name)
        self.content = b'%PDF-1.7\nsmall test document\n'
        self.case = {'id': 'example', 'filename': 'example.pdf', 'bytes': len(self.content),
                     'sha256': hashlib.sha256(self.content).hexdigest(),
                     'downloadURL': 'https://publisher.example/book.pdf'}

    def response(self, content):
        return lambda request, timeout: io.BytesIO(content)

    def test_download_then_cache_hit_needs_no_network(self):
        self.assertEqual(fetch_case(self.case, self.cache, opener=self.response(self.content))['status'], 'downloaded')
        def offline(*args, **kwargs):
            raise AssertionError('cache hit must not access the network')
        self.assertEqual(fetch_case(self.case, self.cache, opener=offline)['status'], 'cached')
        self.assertEqual((self.cache / 'example.pdf').read_bytes(), self.content)

    def test_same_size_cache_corruption_is_repaired(self):
        (self.cache / 'example.pdf').write_bytes(b'x' * len(self.content))
        self.assertEqual(fetch_case(self.case, self.cache, opener=self.response(self.content))['status'], 'downloaded')
        self.assertEqual((self.cache / 'example.pdf').read_bytes(), self.content)

    def test_bad_download_never_replaces_existing_cache(self):
        target = self.cache / 'example.pdf'
        target.write_bytes(self.content)
        for content in [b'x' * len(self.content), self.content[:-1], self.content + b'x']:
            with self.subTest(content=content):
                with self.assertRaises(ValueError):
                    fetch_case(self.case, self.cache, refresh=True, opener=self.response(content))
                self.assertEqual(target.read_bytes(), self.content)
                self.assertEqual(list(self.cache.glob('*.partial')), [])

    def test_failed_new_download_publishes_nothing(self):
        with self.assertRaises(ValueError):
            fetch_case(self.case, self.cache, opener=self.response(b'<html>error</html>'))
        self.assertEqual(list(self.cache.iterdir()), [])

    def test_network_failure_preserves_cache_and_cleans_partial(self):
        target = self.cache / 'example.pdf'
        target.write_bytes(self.content)
        def disconnected(*args, **kwargs):
            raise OSError('connection interrupted')
        with self.assertRaises(OSError):
            fetch_case(self.case, self.cache, refresh=True, opener=disconnected)
        self.assertEqual(list(self.cache.iterdir()), [target])
        self.assertEqual(target.read_bytes(), self.content)

    def test_missing_url_allows_verified_owner_seed_but_not_download(self):
        self.case.pop('downloadURL')
        with self.assertRaisesRegex(ValueError, 'no direct downloadURL'):
            fetch_case(self.case, self.cache)
        (self.cache / 'example.pdf').write_bytes(self.content)
        self.assertEqual(fetch_case(self.case, self.cache)['status'], 'cached')

    def test_rejects_unsafe_manifest_paths_and_schemes(self):
        for field, value in [('filename', '../escape.pdf'), ('filename', 'a\\b.pdf'),
                             ('downloadURL', 'file:///etc/passwd'), ('downloadURL', 'https://user:pass@example.com/a.pdf')]:
            with self.subTest(field=field, value=value):
                case = dict(self.case, **{field: value})
                with self.assertRaises(ValueError):
                    fetch_case(case, self.cache, opener=self.response(self.content))

    def test_rejects_symlink_cache_entry(self):
        original = self.cache / 'original.pdf'
        original.write_bytes(self.content)
        (self.cache / 'example.pdf').symlink_to(original)
        with self.assertRaisesRegex(ValueError, 'symlink'):
            fetch_case(self.case, self.cache, opener=self.response(self.content))
        self.assertEqual(original.read_bytes(), self.content)


if __name__ == '__main__':
    unittest.main()
