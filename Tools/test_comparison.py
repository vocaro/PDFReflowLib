"""Deterministic comparison controls. No Poppler or Apple frameworks needed."""
import io
import json
from pathlib import Path
import stat
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import compare_pdf as comparison
from serve_comparison import ReviewHandler

CHAPTER = '''<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>Test &amp; book</title><link rel="stylesheet" href="style.css"/></head>
<body><span id="page-1" epub:type="pagebreak"/><p><strong>con<span id="page-2" epub:type="pagebreak"/>version</strong> &lt;safe&gt;</p>
<img src="images/a.png"/></body></html>'''


class ComparisonTests(unittest.TestCase):
    def test_page_ranges_are_sorted_unique_and_bounded(self):
        self.assertEqual(comparison.select_pages("3,1-3,5", 5), [1, 2, 3, 5])
        self.assertEqual(comparison.select_pages("all", 3), [1, 2, 3])
        for spec in ["0", "3-2", "6", "1,", "-1", "2-999999999", "", "1.5"]:
            with self.subTest(spec=spec), self.assertRaises(ValueError):
                comparison.select_pages(spec, 5)

    def test_inline_page_marker_and_styles_survive_browser_serialization(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / "book.epub"
            with zipfile.ZipFile(archive, "w") as book:
                book.writestr("EPUB/chapter-1.xhtml", CHAPTER)
                book.writestr("EPUB/images/a.png", b"image bytes")
            pages = comparison.unpack_epub(archive, root / "epub")
            self.assertEqual(pages, {1: "epub/EPUB/chapter-1.html#page-1",
                                     2: "epub/EPUB/chapter-1.html#page-2"})
            original = root / "epub/EPUB/chapter-1.xhtml"
            self.assertEqual(original.read_text(), CHAPTER)
            preview = original.with_suffix(".html").read_text()
            self.assertIn('<strong>con<span id="page-2" epub:type="pagebreak"></span>version</strong>', preview)
            self.assertIn('&lt;safe&gt;', preview)
            self.assertIn('href="style.css"', preview)
            self.assertIn('src="images/a.png"', preview)
            self.assertEqual((root / "epub/EPUB/images/a.png").read_bytes(), b"image bytes")

    def test_unsafe_archive_paths_and_symlinks_rejected_before_extraction(self):
        names = ["../escaped", "/absolute", "a/../../escaped", "a\\escaped", "./a", "a//b", "a:b"]
        symlink = zipfile.ZipInfo("link")
        symlink.external_attr = (stat.S_IFLNK | 0o777) << 16
        for name in [*names, symlink]:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                with zipfile.ZipFile(root / "bad.epub", "w") as archive:
                    archive.writestr(name, "data")
                with self.assertRaises(ValueError):
                    comparison.unpack_epub(root / "bad.epub", root / "unpacked")
                self.assertFalse((root / "unpacked").exists())

    def test_archive_size_and_case_collisions_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with zipfile.ZipFile(root / "bad.epub", "w") as archive:
                archive.writestr("A", "1")
                archive.writestr("a", "2")
            for limit in [1, 100]:
                with self.assertRaises(ValueError):
                    comparison.unpack_epub(root / "bad.epub", root / "unpacked", limit)

    def test_missing_and_duplicate_source_markers_fail(self):
        for chapter in [CHAPTER.replace('epub:type="pagebreak"', ''), CHAPTER.replace('id="page-2"', 'id="page-1"')]:
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                with zipfile.ZipFile(root / "bad.epub", "w") as archive:
                    archive.writestr("chapter.xhtml", chapter)
                with self.assertRaises(ValueError):
                    comparison.unpack_epub(root / "bad.epub", root / "unpacked")

    def test_child_failure_keeps_diagnostics_and_timeout_reaps_child(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaises(RuntimeError):
                comparison.run([sys.executable, "-c", "import sys; print('diagnostic', file=sys.stderr); sys.exit(7)"],
                               root / "out", root / "err", 10)
            self.assertIn("diagnostic", (root / "err").read_text())
            with self.assertRaises(TimeoutError):
                comparison.run([sys.executable, "-c", "import time; time.sleep(60)"],
                               root / "out", root / "err", 0.1)

    def test_failed_bundle_is_recorded_and_existing_output_is_protected(self):
        from argparse import Namespace
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "input.pdf"
            source.write_bytes(b"test")
            args = Namespace(converter=sys.executable, pdftohtml=sys.executable, pdftoppm=sys.executable,
                             pdf=source, output=root / "review", no_ocr=False, timeout=10)
            with patch.object(comparison.platform, "platform", return_value="test"), \
                    patch.object(comparison.subprocess, "run", side_effect=RuntimeError("version probe failed")):
                with self.assertRaises(RuntimeError):
                    comparison.build(args)
            manifest = json.loads((args.output / "comparison.json").read_text())
            self.assertEqual(manifest["status"], "failed")
            self.assertEqual((args.output / "input.pdf").read_bytes(), b"test")
            with self.assertRaises(FileExistsError):
                comparison.build(args)


class ServingTests(unittest.TestCase):
    def test_headers_block_document_scripts_and_paths_cannot_escape_bundle(self):
        # Exercise the actual HTTP handler without requiring a listening socket in restricted tests.
        class Connection:
            def __init__(self, request):
                self.input = io.BytesIO(request)
                self.output = io.BytesIO()
            def makefile(self, *args, **kwargs):
                return self.input
            def sendall(self, data):
                self.output.write(data)

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "index.html").write_text("shell")
            (root / "page.html").write_text("preview")
            (root / "escape").symlink_to(root.parent)
            for path, expected in [("/", 200), ("/page.html", 200),
                                   ("/%2e%2e/private", 403), ("/escape/anything", 403)]:
                with self.subTest(path=path):
                    connection = Connection(f"GET {path} HTTP/1.0\r\n\r\n".encode())
                    with patch.object(ReviewHandler, "log_message"):
                        ReviewHandler(connection, ("127.0.0.1", 0), None, directory=str(root))
                    response = connection.output.getvalue().decode()
                    self.assertIn(f"HTTP/1.0 {expected}", response)
                    self.assertIn("script-src 'self'" if path == "/" else "script-src 'none'", response)
                    self.assertIn("X-Content-Type-Options: nosniff", response)


if __name__ == "__main__":
    unittest.main()
