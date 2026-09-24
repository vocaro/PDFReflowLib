"""Exercise the memory gate with a real child allocation and otherwise valid output.

This is an instrumentation control, not a PDF conversion quality test. The FAA case supplies
that workload separately, without bundling its large source into ordinary tests.
"""
import contextlib
import hashlib
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

import evaluate_real_document as runner


class MemoryGateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / "corpus").mkdir()
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
import json, pathlib, shutil, sys, time
allocation = b"x" * (80 * 1024 * 1024)
shutil.copyfile({str(self.book)!r}, sys.argv[2])
# Every launch records the flags it was given, so a test can read what each attempt carried.
with pathlib.Path(sys.argv[2]).with_name("flags.log").open("a") as flags:
    flags.write(json.dumps(sys.argv[3:]) + "\\n")
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
                     "--max-peak-rss-mib", str(limit), '--execution-context', 'test-child',
                     '--settle-seconds', '0'] + list(extra)
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
        self.assertEqual(code, 0)

    def test_host_memory_pressure_leaves_the_ceiling_unmeasured_rather_than_failed(self):
        with patch.object(runner, "pressure_reader", return_value=lambda: 2):
            code, result = self.invoke(512)
        self.assertEqual(result["peakMemoryPressureLevel"], 2)
        self.assertEqual(result["structuralCheck"], "passed")
        self.assertEqual(result["memoryGate"]["status"], "notMeasured")
        self.assertFalse(result["memoryGate"]["passed"])
        self.assertIn("pressure", result["memoryGate"]["error"])
        self.assertFalse(result["runPassed"])
        self.assertEqual(code, runner.UNMEASURED_MEMORY_EXIT)

    def test_a_peak_over_the_ceiling_fails_even_under_host_memory_pressure(self):
        # Pressure only ever lowers a resident size, so an exceedance measured under it is real.
        with patch.object(runner, "pressure_reader", return_value=lambda: 2):
            code, result = self.invoke(16)
        self.assertEqual(result["memoryGate"]["status"], "exceeded")
        self.assertEqual(result["memoryGate"]["attempts"], 1)
        self.assertEqual(code, 1)

    def test_a_second_attempt_measures_the_ceiling_once_the_host_settles(self):
        level = [2]
        waits = []

        def quieting_settle(read_pressure, seconds):
            waits.append(seconds)
            if len(waits) > 1:  # the unrelated load ends while this run waits for it
                level[0] = 1
            return 0.0

        with patch.object(runner, "pressure_reader", return_value=lambda: level[0]), \
                patch.object(runner, "settle", quieting_settle):
            code, result = self.invoke(512)
        self.assertEqual(code, 0)
        self.assertEqual(len(waits), 2)
        self.assertEqual(result["memoryGate"]["status"], "passed")
        self.assertEqual(result["memoryGate"]["attempts"], 2)
        self.assertEqual([a["peakMemoryPressureLevel"] for a in result["conversionAttempts"]], [2, 1])
        self.assertTrue((self.root / "result/memory-samples-1.json").is_file())
        self.assertTrue((self.root / "result/memory-samples.json").is_file())

    def launched_flags(self):
        """The flags each converter launch of the run received, in launch order."""
        return [json.loads(line) for line in (self.root / "result/flags.log").read_text().splitlines()]

    def test_a_case_without_a_language_converts_at_library_defaults(self):
        self.assertEqual(runner.conversion_flags({"id": "control"}), [])
        code, result = self.invoke(512)
        self.assertEqual(code, 0)
        self.assertEqual(self.launched_flags(), [[]])
        self.assertEqual(result["options"], "library defaults")

    def test_a_reviewed_damaged_script_uses_recognition_and_original_pages(self):
        flags = runner.conversion_flags({"language": "hi-IN", "ocrMode": "always",
                                         "referenceImages": "always"})
        self.assertEqual(flags, ["--language", "hi-IN", "--ocr", "always",
                                 "--reference-images", "always"])

    def test_a_declared_language_reaches_every_conversion_of_the_case(self):
        self.assertEqual(runner.conversion_flags({"id": "x", "language": "zh-Hans"}), ["--language", "zh-Hans"])
        manifest = json.loads((self.root / "corpus/manifest.json").read_text())
        manifest["documents"][0]["language"] = "ar"
        (self.root / "corpus/manifest.json").write_text(json.dumps(manifest))
        level = [2]
        waits = []

        def quieting_settle(read_pressure, seconds):
            waits.append(seconds)
            if len(waits) > 1:  # the host settles, so a second attempt is spent (#293)
                level[0] = 1
            return 0.0

        with patch.object(runner, "pressure_reader", return_value=lambda: level[0]), \
                patch.object(runner, "settle", quieting_settle):
            code, result = self.invoke(512)
        self.assertEqual(code, 0)
        self.assertEqual(result["memoryGate"]["attempts"], 2)
        # The retry is a fresh launch of the same command: the tag is on both.
        self.assertEqual(self.launched_flags(), [["--language", "ar"], ["--language", "ar"]])
        self.assertEqual(result["options"], "library defaults with --language ar")
        self.assertEqual(result["case"]["language"], "ar")

    def test_a_host_that_never_settles_is_not_given_another_conversion(self):
        with patch.object(runner, "pressure_reader", return_value=lambda: 2):
            code, result = self.invoke(512, ["--memory-attempts", "4"])
        self.assertEqual(code, runner.UNMEASURED_MEMORY_EXIT)
        self.assertEqual(result["memoryGate"]["attempts"], 1)
        self.assertNotIn("conversionAttempts", result)
        self.assertFalse((self.root / "result/memory-samples-1.json").exists())

    def test_pressure_before_the_converter_starts_does_not_spoil_its_measurement(self):
        levels = [2]  # a spike the converter's own pages cannot have been compressed by

        def read():
            return levels.pop(0) if levels else 1

        with patch.object(runner, "pressure_reader", return_value=read):
            code, result = self.invoke(512)
        self.assertEqual(code, 0)
        self.assertEqual(result["peakMemoryPressureLevel"], 1)
        self.assertEqual(result["memoryGate"]["status"], "passed")

    def test_the_kernels_footprint_high_water_mark_is_recorded(self):
        # Corroborating evidence for a peak RSS: a high-water mark cannot miss a spike between
        # two samples, and the footprint ledger counts compressed pages. Not gated on.
        code, result = self.invoke(512)
        self.assertEqual(code, 0)
        self.assertGreater(result["converterLifetimeMaxPhysicalFootprintBytes"],
                           result["sampledPeakPhysicalFootprintBytes"] / 2)

    def test_settle_waits_for_normal_pressure_and_gives_up(self):
        levels = [4, 2, 1]
        self.assertIsNotNone(runner.settle(lambda: levels.pop(0), 10))
        self.assertEqual(levels, [])
        self.assertIsNone(runner.settle(lambda: 2, 0))
        self.assertLess(runner.settle(lambda: 1, 0), 1)

    def test_concurrent_evaluations_are_recorded(self):
        code, result = self.invoke(512, ["--concurrent-evaluations", "6"])
        self.assertEqual(code, 0)
        self.assertEqual(result["concurrentEvaluations"], 6)
        self.assertIn(result["peakMemoryPressureLevel"], (1, None))

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
                     "--converter", str(self.converter), "--output", str(self.root / "result"),
                     "--settle-seconds", "0"]
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
                     "--converter", str(self.converter), "--output", str(output), "--timeout", "0.1",
                     "--settle-seconds", "0"]
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

    def test_invalid_attempt_and_settle_values_are_rejected(self):
        for extra in [["--memory-attempts", "0"], ["--settle-seconds", "-1"],
                      ["--settle-seconds", "nan"]]:
            with self.subTest(extra=extra):
                with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
                    self.invoke(512, extra)
                self.assertEqual(error.exception.code, 2)
                self.assertFalse((self.root / "result").exists())


if __name__ == "__main__":
    unittest.main()
