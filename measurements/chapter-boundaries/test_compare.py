import tempfile
from pathlib import Path
import unittest
import zipfile
from compare import compare


def book(path, split=False, text='body', image=b'pixels', broken_link=False):
    marker = '<span epub:type="pagebreak" id="page-{}"/>'
    bodies = [marker.format(1) + '<p>' + text + '</p><figure><img src="images/a.png"/></figure>',
              marker.format(2) + '<h2 id="two">Chapter 2</h2>']
    if not split:
        bodies = [''.join(bodies)]
    def xhtml(body):
        return ('<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">'
                '<head><title>test</title></head><body>' + body + '</body></html>')
    with zipfile.ZipFile(path, 'w') as archive:
        manifest, spine = [], []
        for n, body in enumerate(bodies, 1):
            archive.writestr(f'EPUB/chapter-{n}.xhtml', xhtml(body))
            manifest.append(f'<item id="c{n}" href="chapter-{n}.xhtml"/>')
            spine.append(f'<itemref idref="c{n}"/>')
        archive.writestr('EPUB/package.opf', '<package xmlns="http://www.idpf.org/2007/opf"><manifest>'
                        + ''.join(manifest) + '</manifest><spine>' + ''.join(spine) + '</spine></package>')
        archive.writestr('EPUB/images/a.png', image)
        chapter = 9 if broken_link else (2 if split else 1)
        archive.writestr('EPUB/nav.xhtml', xhtml(f'<nav><a href="chapter-{chapter}.xhtml#two">Chapter 2</a></nav>'))


class ComparisonTests(unittest.TestCase):
    def test_repackaging_preserves_all_content(self):
        with tempfile.TemporaryDirectory() as d:
            before, after = Path(d) / 'before.epub', Path(d) / 'after.epub'
            book(before)
            book(after, split=True)
            result = compare(before, after, [2])
            self.assertEqual(result['baselineMissingChapterStarts'], [2])
            self.assertEqual(result['afterSpineCount'], 2)

    def test_original_packing_fails_chapter_contract(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / 'old.epub'
            book(path)
            with self.assertRaisesRegex(AssertionError, 'not a spine start'):
                compare(path, path, [2])

    def test_content_image_and_link_damage_fail(self):
        with tempfile.TemporaryDirectory() as d:
            before, after = Path(d) / 'before.epub', Path(d) / 'after.epub'
            book(before)
            for change in [{'text': 'lost text'}, {'image': b'changed pixels'}, {'broken_link': True}]:
                book(after, split=True, **change)
                with self.assertRaises(AssertionError):
                    compare(before, after, [2])


if __name__ == '__main__':
    unittest.main()
