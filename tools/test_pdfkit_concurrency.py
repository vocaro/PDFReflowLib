import json
from pathlib import Path
import signal
import sys
import tempfile
import unittest

from check_pdfkit_concurrency import classify, fixture, run_case


def receipt_text():
    common = {'mode': 'native', 'workers': 8, 'iterations': 2}
    return '\n'.join(json.dumps(r) for r in [dict(common, event='started'),
        dict(common, event='completed', completed=16, failures=[], peakRSSBytes=1024)])


class ConcurrencyHarnessTests(unittest.TestCase):
    def test_requires_full_positive_control(self):
        self.assertEqual(classify(0, False, receipt_text(), 'native', 8, 2)[0], 'passed')
        records = [json.loads(r) for r in receipt_text().splitlines()]
        for changed in [dict(records[1], completed=15), dict(records[1], failures=['wrong font']),
                        dict(records[1], peakRSSBytes=0), dict(records[1], mode='plain')]:
            with self.subTest(changed=changed):
                self.assertEqual(classify(0, False, json.dumps(records[0]) + '\n' + json.dumps(changed),
                                          'native', 8, 2)[0], 'invalid-receipt')

    def test_empty_truncated_and_corrupt_results_fail_closed(self):
        for text in ['', '{}', 'null\nnull', '{}\n{}', '[]\n[]', receipt_text().splitlines()[0],
                     receipt_text() + '\n{}', 'not json']:
            with self.subTest(text=text):
                self.assertEqual(classify(0, False, text, 'native', 8, 2)[0], 'invalid-receipt')

    def test_crash_and_timeout_cannot_be_overridden_by_success_text(self):
        for code, timeout, expected in [(-6, False, 'signal'), (1, False, 'failed'), (0, True, 'timeout')]:
            self.assertEqual(classify(code, timeout, receipt_text(), 'native', 8, 2)[0], expected)

    def test_failure_diagnostics_survive_process_exit(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'failure'
            result = run_case([sys.executable, '-c', 'import sys; print("evidence", file=sys.stderr); sys.exit(3)'],
                              path, 5, 'native', 8, 2)
            self.assertEqual(result['status'], 'failed')
            self.assertEqual(result['returncode'], 3)
            self.assertEqual((path / 'stderr.log').read_text().strip(), 'evidence')
            self.assertEqual(json.loads((path / 'receipt.json').read_text()), result)
            with self.assertRaises(FileExistsError):
                run_case([sys.executable, '-c', ''], path, 5, 'native', 8, 2)

    def test_signal_is_reported_without_retry(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = run_case([sys.executable, '-c', 'import os, signal; os.kill(os.getpid(), signal.SIGTERM)'],
                              Path(tmp) / 'signal', 5, 'native', 8, 2)
            self.assertEqual(result['status'], 'signal')
            self.assertEqual(result['returncode'], -signal.SIGTERM)

    def test_timeout_kills_and_reaps_probe(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = run_case([sys.executable, '-c', 'import time; time.sleep(30)'],
                              Path(tmp) / 'timeout', 0.1, 'native', 8, 2)
            self.assertEqual(result['status'], 'timeout')
            self.assertEqual(result['returncode'], -signal.SIGKILL)
            self.assertLess(result['seconds'], 5)

    def test_fixtures_have_correct_byte_offsets_and_identical_visible_content(self):
        streams = []
        for tagged in [False, True]:
            data = fixture(tagged)
            xref = int(data.split(b'startxref\n')[1].splitlines()[0])
            self.assertTrue(data[xref:].startswith(b'xref\n'))
            rows = data[xref:].splitlines()
            count = int(rows[1].split()[1])
            for object_id, row in enumerate(rows[3:count + 2], 1):
                offset = int(row.split()[0])
                self.assertTrue(data[offset:].startswith(f'{object_id} 0 obj\n'.encode()))
            content = data.split(b'stream\n', 1)[1].split(b'\nendstream')[0]
            length = int(data.split(b'/Length ')[1].split()[0])
            self.assertEqual(len(content), length)
            streams.append(content)
        self.assertEqual(streams[0], streams[1])
        self.assertIn(b'(Small heading)', streams[0])
        self.assertIn(b'/F1 24 Tf', streams[0])
