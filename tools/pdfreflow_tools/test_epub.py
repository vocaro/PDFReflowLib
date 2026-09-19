"""Archive admission happens before any entry is read; package and marker parsing are exact."""
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import warnings
import xml.etree.ElementTree as ET
import zipfile

from pdfreflow_tools import epub


class AdmissionTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.path = Path(directory.name) / 'book.epub'
        with zipfile.ZipFile(self.path, 'w') as archive:
            archive.writestr('mimetype', 'application/epub+zip')
            archive.writestr('EPUB/package.opf', '<package/>')
            archive.writestr('EPUB/chapter.xhtml', '<html/>')
        with zipfile.ZipFile(self.path) as archive:
            self.entries = len(archive.infolist())
            self.expanded = sum(entry.file_size for entry in archive.infolist())

    def test_limits_are_validated_before_the_archive_opens(self):
        for name in ['max_entries', 'max_uncompressed_bytes']:
            for value in [None, True, 0, -1, 1.0, '10', float('nan'), [], sys.maxsize + 1]:
                with self.subTest(name=name, value=value), patch.object(zipfile, 'ZipFile') as opened:
                    with self.assertRaisesRegex(ValueError, name + ' must be an integer from 1 to'):
                        with epub.open_archive(self.path, **{name: value}):
                            pass
                    opened.assert_not_called()

    def test_exact_ceilings_admit_and_one_below_rejects_before_any_read(self):
        with epub.open_archive(self.path, max_entries=self.entries, max_uncompressed_bytes=self.expanded) as archive:
            self.assertEqual(archive.read('mimetype'), epub.MIMETYPE)
        for limits in [dict(max_entries=self.entries - 1), dict(max_uncompressed_bytes=self.expanded - 1)]:
            with self.subTest(limits=limits), patch.object(zipfile.ZipFile, 'read') as read:
                with self.assertRaisesRegex(ValueError, 'EPUB exceeds inspection bounds'):
                    with epub.open_archive(self.path, **limits):
                        pass
                read.assert_not_called()

    def test_duplicate_entries_are_rejected(self):
        with warnings.catch_warnings():
            warnings.simplefilter('ignore', UserWarning)
            with zipfile.ZipFile(self.path, 'a') as archive:
                archive.writestr('EPUB/chapter.xhtml', '<html>again</html>')
        with self.assertRaisesRegex(ValueError, 'Duplicate archive entries'):
            with epub.open_archive(self.path):
                pass


class PackageTests(unittest.TestCase):
    OPF = ('<package xmlns="http://www.idpf.org/2007/opf" version="3.0"><manifest>'
           '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'
           '<item id="b" href="text/b.xhtml" media-type="application/xhtml+xml"/>'
           '<item id="a" href="a.xhtml" media-type="application/xhtml+xml"/>'
           '</manifest><spine><itemref idref="b"/><itemref idref="a"/></spine></package>')

    def test_spine_names_resolve_beside_the_package_in_reading_order(self):
        package = epub.parse_package(ET.fromstring(self.OPF))
        self.assertEqual(package.version, '3.0')
        self.assertEqual(package.spine, ['EPUB/text/b.xhtml', 'EPUB/a.xhtml'])
        self.assertEqual(package.items['nav']['properties'], 'nav')
        self.assertEqual(epub.parse_package(ET.fromstring(self.OPF), 'OPS/content.opf').spine,
                         ['OPS/text/b.xhtml', 'OPS/a.xhtml'])

    def test_package_is_read_from_the_archive(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'book.epub'
            with zipfile.ZipFile(path, 'w') as archive:
                archive.writestr(epub.PACKAGE, self.OPF)
            with zipfile.ZipFile(path) as archive:
                self.assertEqual(epub.read_package(archive).spine, ['EPUB/text/b.xhtml', 'EPUB/a.xhtml'])

    def test_unknown_spine_reference_and_missing_href_are_errors(self):
        with self.assertRaises(KeyError):
            epub.parse_package(ET.fromstring(self.OPF.replace('idref="a"', 'idref="missing"')))
        with self.assertRaises(KeyError):
            epub.parse_package(ET.fromstring(self.OPF.replace(' href="a.xhtml"', '')))


class PageBoundaryTests(unittest.TestCase):
    def element(self, markup):
        return ET.fromstring('<body xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">'
                             + markup + '</body>')[0]

    def test_markers_name_their_source_page(self):
        self.assertEqual(epub.page_boundary(self.element('<span epub:type="pagebreak" id="page-12"/>')), 12)
        self.assertTrue(epub.is_page_boundary(self.element('<span epub:type="pagebreak noteref" id="page-1"/>')))

    def test_other_elements_are_not_boundaries(self):
        for markup in ['<p id="page-1">text</p>', '<span epub:type="noteref" id="page-1"/>', '<span/>']:
            with self.subTest(markup=markup):
                self.assertIsNone(epub.page_boundary(self.element(markup)))

    def test_invalid_anchors_are_rejected(self):
        for anchor in ['', 'page-0', 'page-01', 'p-1', 'page-1x', 'PAGE-1']:
            with self.subTest(anchor=anchor), self.assertRaisesRegex(ValueError, 'Invalid page boundary'):
                epub.page_boundary(self.element(f'<span epub:type="pagebreak" id="{anchor}"/>'))


if __name__ == '__main__':
    unittest.main()
