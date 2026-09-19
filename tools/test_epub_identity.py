import json
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
import epub_identity as identity  # noqa: E402

PACKAGE = (b'<?xml version="1.0"?><package><metadata><dc:identifier id="book-id">urn:uuid:%s</dc:identifier>'
           b'<meta property="dcterms:modified">%s</meta></metadata></package>')


def write_epub(path, identifier=b'a', modified=b'2026-01-01T00:00:00Z', chapter=b'<p>text</p>',
               image=b'\x89PNG', entries=None):
    with zipfile.ZipFile(path, 'w') as archive:
        archive.writestr('mimetype', 'application/epub+zip')
        archive.writestr('EPUB/package.opf', PACKAGE % (identifier, modified))
        archive.writestr('EPUB/chapter-1.xhtml', chapter)
        archive.writestr('EPUB/images/image-1.png', image)
        for name, data in (entries or {}).items():
            archive.writestr(name, data)


class IdentityTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.root = Path(self.dir.name)
        self.baseline = self.root / 'baseline.epub'
        write_epub(self.baseline)

    def tearDown(self):
        self.dir.cleanup()

    def test_identifier_and_timestamp_are_the_only_permitted_variation(self):
        candidate = self.root / 'same.epub'
        write_epub(candidate, identifier=b'b', modified=b'2027-02-02T00:00:00Z')
        self.assertEqual(identity.compare_epubs(self.baseline, candidate), [])

    def test_changed_markup_byte_is_reported(self):
        candidate = self.root / 'markup.epub'
        write_epub(candidate, chapter=b'<p>Text</p>')
        self.assertEqual(len(identity.compare_epubs(self.baseline, candidate)), 1)
        self.assertIn('chapter-1.xhtml', identity.compare_epubs(self.baseline, candidate)[0])

    def test_changed_image_bytes_are_reported(self):
        candidate = self.root / 'image.epub'
        write_epub(candidate, image=b'\x89PNG\x00')
        self.assertTrue(any('image-1.png' in line for line in identity.compare_epubs(self.baseline, candidate)))

    def test_missing_extra_and_reordered_entries_are_reported(self):
        candidate = self.root / 'extra.epub'
        write_epub(candidate, entries={'EPUB/chapter-2.xhtml': b'<p>more</p>'})
        self.assertTrue(any(line.startswith('extra in candidate') for line in identity.compare_epubs(self.baseline, candidate)))
        self.assertTrue(any(line.startswith('missing in candidate') for line in identity.compare_epubs(candidate, self.baseline)))
        reordered = self.root / 'reordered.epub'
        with zipfile.ZipFile(self.baseline) as source, zipfile.ZipFile(reordered, 'w') as target:
            for name in reversed(source.namelist()):
                target.writestr(name, source.read(name))
        self.assertEqual(identity.compare_epubs(self.baseline, reordered), ['entry order differs'])

    def test_package_without_exactly_one_identifier_is_rejected(self):
        candidate = self.root / 'broken.epub'
        with zipfile.ZipFile(candidate, 'w') as archive:
            archive.writestr('mimetype', 'application/epub+zip')
            archive.writestr('EPUB/package.opf', b'<package/>')
            archive.writestr('EPUB/chapter-1.xhtml', b'<p>text</p>')
            archive.writestr('EPUBimages/image-1.png', b'')
        with self.assertRaises(ValueError):
            identity.compare_epubs(self.baseline, candidate)

    def test_reports_match_except_output_path(self):
        first = self.root / 'a.json'
        second = self.root / 'b.json'
        report = {'outputURL': 'file:///a', 'pageCount': 3, 'warnings': [{'code': 'ocrUsed', 'page': 1}]}
        first.write_text(json.dumps(report))
        report['outputURL'] = 'file:///b'
        second.write_text(json.dumps(report))
        self.assertEqual(identity.compare_reports(first, second), [])
        report['warnings'] = []
        second.write_text(json.dumps(report))
        self.assertEqual(identity.compare_reports(first, second), ['report warnings differs'])


if __name__ == '__main__':
    unittest.main()
