"""The developer reader's independent vendor and publication admission controls."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import view_epub


class EPUBReaderTests(unittest.TestCase):
    def test_vendored_engine_matches_pin_and_rejects_changed_bytes(self):
        view_epub.verify_assets()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "lib").mkdir()
            (root / "lib/view.js").write_text("changed")
            (root / "assets.json").write_text(json.dumps({"files": {"lib/view.js": {"bytes": 1, "sha256": "bad"}}}))
            with patch.object(view_epub, "ASSETS", root), self.assertRaises(ValueError):
                view_epub.verify_assets()

    def test_active_markup_external_resources_and_css_are_rejected(self):
        unsafe = [
            '<script>alert(1)</script>', '<img src="https://example.com/tracker.png"/>',
            '<link rel="preconnect" href="https://example.com"/>', '<p onclick="alert(1)">x</p>',
            '<meta http-equiv="refresh" content="0;url=https://example.com"/>',
            '<iframe src="a.xhtml"/>', '<img src="//example.com/a.png"/>',
            '<img src="%68ttps://example.com/a.png"/>',
            '<item href="a.png" media-type="application/xhtml+xml"/>',
        ]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "mimetype").write_text("application/epub+zip")
            for payload in unsafe:
                with self.subTest(payload=payload):
                    (root / "chapter.xhtml").write_text(f'<html><head/><body>{payload}</body></html>')
                    with self.assertRaises(ValueError):
                        view_epub.validate_resources(root)
            (root / "chapter.xhtml").unlink()
            for css in ['@import "https://example.com/style.css";', 'body {background:url(https://example.com)}', r'@\69mport "remote";']:
                (root / "style.css").write_text(css)
                with self.assertRaises(ValueError):
                    view_epub.validate_resources(root)

    def test_jpeg_resources_require_matching_inert_media_types(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "mimetype").write_text("application/epub+zip")
            for suffix in ["jpg", "jpeg"]:
                path = root / ("image." + suffix)
                path.write_bytes(b"\xff\xd8\xff\xd9")
                package = root / "package.opf"
                package.write_text(f'<package><item href="{path.name}" media-type="image/jpeg"/></package>')
                self.assertIn(path.name, view_epub.validate_resources(root))
                for media in ["image/png", "image/svg+xml", "application/javascript"]:
                    package.write_text(f'<package><item href="{path.name}" media-type="{media}"/></package>')
                    with self.assertRaises(ValueError): view_epub.validate_resources(root)
                path.unlink()

    def test_configured_reader_limit_checks_both_zip_and_expanded_size(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "book.epub"
            chapter = '<html xmlns:epub="http://www.idpf.org/2007/ops"><head/><body><span id="page-1" epub:type="pagebreak"/>' + "x" * 10000 + '</body></html>'
            with zipfile.ZipFile(source, "w", compression=zipfile.ZIP_DEFLATED) as book:
                book.writestr("mimetype", "application/epub+zip")
                book.writestr("EPUB/chapter-1.xhtml", chapter)
            self.assertLess(source.stat().st_size, 1000)
            for limit in [0, 1, 1000]:
                with self.assertRaises(ValueError):
                    view_epub.prepare(source, root / str(limit), maximum_bytes=limit)
            manifest = view_epub.prepare(source, root / "accepted", maximum_bytes=20000)
            self.assertIn("EPUB/chapter-1.xhtml", manifest["resources"])

    def test_preparation_keeps_original_xhtml_and_page_navigation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source.epub"
            chapter = '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Book</title></head><body><p>joined<span id="page-1" epub:type="pagebreak"/>word</p></body></html>'
            with zipfile.ZipFile(source, "w") as book:
                book.writestr("mimetype", "application/epub+zip")
                book.writestr("EPUB/chapter-1.xhtml", chapter)
            manifest = view_epub.prepare(source, root / "reader")
            self.assertEqual(manifest["pages"][1], "EPUB/chapter-1.xhtml#page-1")
            self.assertEqual((root / "reader/epub/EPUB/chapter-1.xhtml").read_text(), chapter)
            self.assertEqual((root / "reader/book.epub").read_bytes(), source.read_bytes())
            self.assertNotIn("EPUB/chapter-1.html", manifest["resources"])
            with self.assertRaises(FileExistsError):
                view_epub.prepare(source, root / "reader")

    def test_mathml_preview_preserves_browser_math_and_rejects_unsafe_fallbacks(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source.epub"
            chapter = ('<html xmlns="http://www.w3.org/1999/xhtml" '
                       'xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Math</title></head>'
                       '<body><span id="page-1" epub:type="pagebreak"/>'
                       '<p><math xmlns="http://www.w3.org/1998/Math/MathML" alttext="sqrt 4" '
                       'altimg="images/image-1.png"><msqrt><mn>4</mn></msqrt></math></p></body></html>')

            def write_book(markup):
                with zipfile.ZipFile(source, "w") as book:
                    book.writestr("mimetype", "application/epub+zip")
                    book.writestr("EPUB/chapter-1.xhtml", markup)
                    book.writestr("EPUB/images/image-1.png", b"\x89PNG\r\n\x1a\n")

            write_book(chapter)
            view_epub.prepare(source, root / "reader")
            original = (root / "reader/epub/EPUB/chapter-1.xhtml").read_text()
            preview = (root / "reader/epub/EPUB/chapter-1.html").read_text()
            self.assertEqual(original, chapter)
            self.assertIn('<math alttext="sqrt 4" altimg="images/image-1.png"><msqrt><mn>4</mn></msqrt></math>', preview)
            self.assertNotIn("ns0:", preview)
            for payload in [
                chapter.replace('images/image-1.png', 'https://example.com/image.png'),
                chapter.replace('images/image-1.png', '../image-1.png'),
                chapter.replace('<msqrt>', '<annotation-xml>').replace('</msqrt>', '</annotation-xml>'),
            ]:
                with self.subTest(payload=payload):
                    write_book(payload)
                    with self.assertRaises(ValueError):
                        view_epub.prepare(source, root / f"rejected-{len(list(root.glob('rejected-*')))}")


if __name__ == "__main__":
    unittest.main()
