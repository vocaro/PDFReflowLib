"""Exercise the memory gate with a real child allocation and otherwise valid output.

This is an instrumentation control, not a PDF conversion quality test. The FAA case supplies
that workload separately, without bundling its large source into ordinary tests.
"""
import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

TOOLS = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("real_document_runner", TOOLS / "evaluate-real-document.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class MemoryGateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / "corpus").mkdir()
        (self.root / "tools").mkdir()
        shutil.copyfile(TOOLS / "check-epubs.py", self.root / "tools/check-epubs.py")
        self.pdf = self.root / "control.pdf"
        self.pdf.write_bytes(b"instrumentation control input")
        case = {"id": "control", "bytes": self.pdf.stat().st_size,
                "sha256": hashlib.sha256(self.pdf.read_bytes()).hexdigest(), "pages": 1}
        (self.root / "corpus/manifest.json").write_text(json.dumps({"documents": [case]}))
        self.book = self.root / "control.epub"
        with zipfile.ZipFile(self.book, "w") as archive:
            archive.writestr("mimetype", "application/epub+zip")
            archive.writestr("EPUB/package.opf", '''<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
              <manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
              <item id="c" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest>
              <spine><itemref idref="c"/></spine></package>''')
            archive.writestr("EPUB/chapter.xhtml", '<html xmlns="http://www.w3.org/1999/xhtml"><body><p>Control</p></body></html>')
            archive.writestr("EPUB/nav.xhtml", '<html xmlns="http://www.w3.org/1999/xhtml"><body><a href="chapter.xhtml">Control</a></body></html>')
        self.converter = self.root / "converter"
        self.converter.write_text(f'''#!{sys.executable}
import json, shutil, sys, time
allocation = b"x" * (80 * 1024 * 1024)
shutil.copyfile({str(self.book)!r}, sys.argv[2])
time.sleep(0.2)
print("0% opening", file=sys.stderr)
print("100% completed", file=sys.stderr)
print(json.dumps({{"pageCount": 1, "reflowedPageCount": 1, "recognizedPageCount": 0, "imageCount": 0, "warnings": []}}))
''')
        self.converter.chmod(0o700)
        self.root_patch = patch.object(runner, "ROOT", self.root)
        self.root_patch.start()

    def tearDown(self):
        self.root_patch.stop()
        self.temp.cleanup()

    def invoke(self, limit):
        output = self.root / "result"
        arguments = ["runner", "--case", "control", "--pdf", str(self.pdf),
                     "--converter", str(self.converter), "--output", str(output),
                     "--max-peak-rss-mib", str(limit)]
        with patch.object(sys, "argv", arguments), contextlib.redirect_stdout(io.StringIO()):
            code = runner.main()
        return code, json.loads((output / "result.json").read_text())

    def test_actual_peak_above_limit_fails_an_otherwise_successful_conversion(self):
        code, result = self.invoke(16)
        self.assertEqual(result["conversionExitCode"], 0)
        self.assertEqual(result["structuralCheck"], "passed")
        self.assertGreaterEqual(result["converterPeakRSSBytes"], 80 * 1024 * 1024)
        self.assertFalse(result["memoryGate"]["passed"])
        self.assertFalse(result["runPassed"])
        self.assertEqual(code, 1)

    def test_peak_below_limit_passes(self):
        code, result = self.invoke(512)
        self.assertTrue(result["memoryGate"]["passed"])
        self.assertTrue(result["runPassed"])
        self.assertEqual(code, 0)

    def test_previous_child_peak_does_not_contaminate_this_run(self):
        subprocess.run([sys.executable, "-c", "allocation = b'x' * (200 * 1024 * 1024)"], check=True)
        code, result = self.invoke(160)
        self.assertEqual(code, 0)
        self.assertLess(result["converterPeakRSSBytes"], 160 * 1024 * 1024)

    def test_manifest_ceiling_is_enforced_without_override(self):
        manifest = self.root / "corpus/manifest.json"
        data = json.loads(manifest.read_text())
        data["documents"][0]["memoryBudget"] = {"maxPeakRSSMiB": 16}
        manifest.write_text(json.dumps(data))
        arguments = ["runner", "--case", "control", "--pdf", str(self.pdf),
                     "--converter", str(self.converter), "--output", str(self.root / "result")]
        with patch.object(sys, "argv", arguments), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(runner.main(), 1)
        result = json.loads((self.root / "result/result.json").read_text())
        self.assertFalse(result["memoryGate"]["passed"])

    def test_regressing_progress_fails_even_when_conversion_and_memory_pass(self):
        text = self.converter.read_text().replace('print("100% completed", file=sys.stderr)',
            'print("60% writing", file=sys.stderr)\nprint("40% writing", file=sys.stderr)\nprint("100% completed", file=sys.stderr)')
        self.converter.write_text(text)
        code, result = self.invoke(512)
        self.assertTrue(result["memoryGate"]["passed"])
        self.assertEqual(result["structuralCheck"], "passed")
        self.assertFalse(result["progressCheck"]["passed"])
        self.assertEqual(code, 1)

    def test_timeout_kills_and_records_the_child(self):
        self.converter.write_text(f"#!{sys.executable}\nimport time\ntime.sleep(30)\n")
        output = self.root / "result"
        arguments = ["runner", "--case", "control", "--pdf", str(self.pdf),
                     "--converter", str(self.converter), "--output", str(output), "--timeout", "0.1"]
        with patch.object(sys, "argv", arguments), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(runner.main(), 1)
        result = json.loads((output / "result.json").read_text())
        self.assertTrue(result["timedOut"])
        self.assertEqual(result["conversionExitCode"], -9)
        self.assertFalse(result["runPassed"])

    def test_changed_input_is_rejected_before_conversion(self):
        self.pdf.write_bytes(b"changed")
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
            self.invoke(512)
        self.assertEqual(error.exception.code, 2)
        self.assertFalse((self.root / "result").exists())

    def test_nonfinite_budget_is_rejected(self):
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
            self.invoke(float("nan"))
        self.assertEqual(error.exception.code, 2)
        self.assertFalse((self.root / "result").exists())


if __name__ == "__main__":
    unittest.main()
