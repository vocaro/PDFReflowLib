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

    def invoke(self, limit, extra=()):
        output = self.root / "result"
        arguments = ["runner", "--case", "control", "--pdf", str(self.pdf),
                     "--converter", str(self.converter), "--output", str(output),
                     "--max-peak-rss-mib", str(limit), '--execution-context', 'test-child'] + list(extra)
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
        self.assertEqual(result['executionContext'], 'test-child')
        self.assertTrue(result['systemBuild'])
        self.assertTrue(result["memoryGate"]["passed"])
        self.assertTrue(result["runPassed"])
        self.assertEqual(result["converterSHA256AfterConversion"], result["converterSHA256"])
        self.assertEqual(code, 0)

    def test_converter_rebuilt_during_conversion_fails_the_evaluation(self):
        self.converter.write_text(self.converter.read_text().replace(
            "time.sleep(0.2)", "time.sleep(0.2)\nopen(sys.argv[0], 'a').write('# rebuilt\\n')"))
        code, result = self.invoke(512)
        self.assertEqual(result["conversionExitCode"], 0)
        self.assertNotEqual(result["converterSHA256AfterConversion"], result["converterSHA256"])
        self.assertEqual(result["converterIdentityError"], "converter binary changed during conversion")
        self.assertFalse(result["runPassed"])
        self.assertEqual(code, 1)

    def test_converter_options_are_forwarded_after_the_paths_and_recorded(self):
        recorded = self.root / "argv.json"
        self.converter.write_text(self.converter.read_text().replace(
            "import json, shutil, sys, time",
            f"import json, shutil, sys, time\nopen({str(recorded)!r}, 'w').write(json.dumps(sys.argv[1:]))"))
        code, result = self.invoke(512, ['--converter-option=--raster-dpi=240', '--converter-option=--ocr=never'])
        self.assertEqual(code, 0)
        self.assertEqual(result['options'], '--raster-dpi 240 --ocr never')
        argv = json.loads(recorded.read_text())
        self.assertEqual(argv[2:], ['--raster-dpi', '240', '--ocr', 'never'])
        self.assertEqual(argv[0], str(self.pdf.resolve()))
        shutil.rmtree(self.root / "result")
        _, result = self.invoke(512)
        self.assertEqual(result['options'], 'library defaults')

    def test_malformed_converter_options_are_rejected_before_conversion(self):
        for option in ['raster-dpi=240', '--raster-dpi', '--raster-dpi=', '=240']:
            with self.subTest(option=option), self.assertRaises(SystemExit) as caught:
                with contextlib.redirect_stderr(io.StringIO()):
                    self.invoke(512, ['--converter-option=' + option])
            self.assertEqual(caught.exception.code, 2)
            self.assertFalse((self.root / "result").exists())

    def test_previous_child_peak_does_not_contaminate_this_run(self):
        subprocess.run([sys.executable, "-c", "allocation = b'x' * (200 * 1024 * 1024)"], check=True)
        code, result = self.invoke(160)
        self.assertEqual(code, 0)
        self.assertLess(result["converterPeakRSSBytes"], 160 * 1024 * 1024)

    def test_probe_is_executed_with_source_and_launch_context(self):
        probe = self.make_probe()
        code, result = self.invoke(512, ['--environment-probe', str(probe)])
        self.assertEqual(code, 0)
        self.assertTrue(result['environmentProbeCheck']['passed'])
        self.assertEqual(result['environmentProbe']['runID'], result['runID'])
        self.assertEqual(result['environmentProbeCapture']['executableSHA256'], runner.digest(probe))
        self.assertEqual(result['outputSHA256'], runner.digest(self.root / 'result/control.epub'))

    def make_probe(self, tail=''):
        probe = self.root / 'probe'
        probe.write_text(f'''#!{sys.executable}
import hashlib, json, pathlib, sys, time
assert sys.argv[1:4] == [{str(self.pdf.resolve())!r}, '1', 'test-child']
payload = {{'schemaVersion': 1, 'runID': sys.argv[4], 'page': 1, 'system': 'test system',
    'sourceSHA256': hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest(),
    'probeSHA256': hashlib.sha256(pathlib.Path(sys.argv[0]).read_bytes()).hexdigest(),
    'packedPixelSHA256': 'a' * 64, 'width': 10, 'height': 10, 'bitsPerPixel': 32, 'rasterDPI': 180,
    'metalDevice': 'test device', 'colorSpaceName': 'DeviceRGB', 'colorSpaceICC_SHA256': 'unavailable',
    'ocr': {{'status': 'succeeded', 'lines': ['Control']}}}}
{tail}
pathlib.Path(sys.argv[5]).write_text(json.dumps(payload))
''')
        probe.chmod(0o700)
        return probe

    def test_failed_capability_probe_fails_otherwise_passing_evaluation(self):
        probe = self.make_probe("payload['ocr'] = {'status': 'failed'}")
        code, result = self.invoke(512, ['--environment-probe', str(probe)])
        self.assertEqual(result['conversionExitCode'], 0)
        self.assertFalse(result['runPassed'])
        self.assertEqual(code, 1)

    def test_probe_failure_modes_retain_failed_receipts(self):
        for name, tail in [('exit', 'sys.exit(7)'), ('missing', 'sys.exit(0)'),
                           ('invalid-json', "pathlib.Path(sys.argv[5]).write_text('{'); sys.exit(0)"),
                           ('malformed', "payload = ['not an object']"),
                           ('stale', "payload['runID'] = 'previous-run'"),
                           ('wrong-source', "payload['sourceSHA256'] = 'b' * 64"),
                           ('wrong-binary', "payload['probeSHA256'] = 'b' * 64")]:
            with self.subTest(name=name):
                probe = self.make_probe(tail)
                code, result = self.invoke(512, ['--environment-probe', str(probe)])
                self.assertEqual(code, 1)
                self.assertEqual(result['conversionExitCode'], 0)
                self.assertFalse(result['environmentProbeCheck']['passed'])
                shutil.rmtree(self.root / 'result')

    def test_probe_launch_failure_retains_receipt(self):
        probe = self.make_probe()
        probe.chmod(0o600)
        code, result = self.invoke(512, ['--environment-probe', str(probe)])
        self.assertEqual(code, 1)
        self.assertEqual(result['conversionExitCode'], 0)
        self.assertTrue(result['environmentProbeCapture']['error'])

    def test_probe_timeout_retains_failure_and_reaps_probe(self):
        probe = self.make_probe('time.sleep(30)')
        code, result = self.invoke(512, ['--environment-probe', str(probe), '--timeout', '0.1'])
        self.assertEqual(code, 1)
        self.assertIn('timed out', result['environmentProbeCapture']['error'])

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
