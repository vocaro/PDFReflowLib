"""Converter and EPUBCheck runs report exactly what the child process did."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from pdfreflow_tools import converter


class ConverterTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.source = self.root / 'input.pdf'
        self.source.write_bytes(b'%PDF')

    def stub(self, name, body):
        path = self.root / name
        path.write_text(f'#!{sys.executable}\nimport sys\n{body}\n')
        path.chmod(0o700)
        return path

    def test_successful_conversion_returns_the_parsed_report_and_progress(self):
        stub = self.stub('converter', 'print("0% opening", file=sys.stderr)\n'
                         'print("100% completed", file=sys.stderr)\n'
                         'print(\'{"pageCount": 1, "flags": \' + repr(sys.argv[3:]).replace("\'", \'"\') + "}")')
        run = converter.convert(stub, self.source, self.root / 'out.epub', '--no-ocr', timeout=30)
        self.assertEqual(run.command, [str(stub), str(self.source), str(self.root / 'out.epub'), '--no-ocr'])
        self.assertEqual(run.returncode, 0)
        self.assertEqual(run.report, {'pageCount': 1, 'flags': ['--no-ocr']})
        self.assertEqual(json.loads(run.stdout), run.report)
        self.assertEqual(run.stderr.splitlines(), ['0% opening', '100% completed'])

    def test_failed_conversion_raises_unless_the_caller_reads_the_exit_code(self):
        stub = self.stub('converter', 'print("Invalid conversion options", file=sys.stderr)\nsys.exit(1)')
        with self.assertRaises(subprocess.CalledProcessError):
            converter.convert(stub, self.source, self.root / 'out.epub')
        run = converter.convert(stub, self.source, self.root / 'out.epub', check=False)
        self.assertEqual(run.returncode, 1)
        self.assertIsNone(run.report)
        self.assertEqual(run.stderr.strip(), 'Invalid conversion options')

    def test_pinned_packaging_fixes_identifier_and_date(self):
        self.assertEqual(converter.pinned_packaging('urn:pdfreflow:test'),
                         ['--package-identifier', 'urn:pdfreflow:test',
                          '--modification-date', converter.PINNED_MODIFICATION_DATE])

    def test_epubcheck_output_is_logged_and_its_exit_code_returned(self):
        stub = self.stub('epubcheck', 'print("Validating " + sys.argv[1], flush=True)\n'
                         'print("ERROR(RSC-005)", file=sys.stderr)\nsys.exit(3)')
        log = self.root / 'epubcheck.log'
        self.assertEqual(converter.run_epubcheck(stub, self.root / 'book.epub', log), 3)
        self.assertEqual(log.read_text().splitlines(), [f'Validating {self.root / "book.epub"}', 'ERROR(RSC-005)'])
        with self.assertRaises(subprocess.CalledProcessError):
            converter.run_epubcheck(stub, self.root / 'book.epub', log, check=True)


if __name__ == '__main__':
    unittest.main()
