import contextlib
import io
import json
from pathlib import Path
import tempfile
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import run_corpus_regressions as runner


class CorpusRunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'corpus/cache').mkdir(parents=True)
        self.executable = self.root / 'stub'; self.executable.touch()
        self.cases = [{'id': name, 'filename': name + '.pdf'} for name in ['first', 'second']]
        (self.root / 'corpus/manifest.json').write_text(json.dumps({'documents': self.cases}))
        self.definitions = {'cases': [{'id': c['id']} for c in self.cases], 'excludedFullConversions': []}
        self.write_definitions()
        self.argv = ['run', '--converter', str(self.executable), '--epubcheck', str(self.executable),
                     '--output', str(self.root / 'output')]

    def write_definitions(self):
        (self.root / 'corpus/regressions.json').write_text(json.dumps(self.definitions))

    def run_main(self, extra=()):
        with patch.object(runner, 'ROOT', self.root), patch('sys.argv', self.argv + list(extra)), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return runner.main()

    def test_missing_source_is_an_error_without_conversion(self):
        with patch.object(runner.subprocess, 'run') as launch:
            with self.assertRaises(SystemExit) as error:
                self.run_main()
            self.assertEqual(error.exception.code, 2)
            launch.assert_not_called()

    def test_empty_unknown_or_duplicate_case_selection_is_rejected(self):
        for extra in [('--case', 'unknown'), ('--case', 'first', '--case', 'first')]:
            with self.assertRaises(SystemExit):
                self.run_main(extra)
        self.definitions['cases'] = []; self.write_definitions()
        with self.assertRaises(SystemExit):
            self.run_main()

    def test_failed_case_does_not_hide_later_checks(self):
        for case in self.cases:
            (self.root / 'corpus/cache' / case['filename']).touch()
        visited = []

        def launch(command, **kwargs):
            self.assertEqual(command[command.index('--execution-context') + 1], 'test-host')
            self.assertEqual(command[command.index('--environment-probe') + 1], str(self.executable.resolve()))
            name = command[command.index('--case') + 1]; visited.append(name)
            Path(command[command.index('--output') + 1]).mkdir()
            return SimpleNamespace(returncode=1 if name == 'first' else 0)

        with patch.object(runner.subprocess, 'run', side_effect=launch), \
                patch.object(runner, 'check_evaluation', return_value={'case': 'second', 'passed': True}):
            self.assertEqual(self.run_main(['--execution-context', 'test-host',
                                           '--environment-probe', str(self.executable)]), 1)
        summary = json.loads((self.root / 'output/summary.json').read_text())
        self.assertEqual(visited, ['first', 'second'])
        self.assertFalse(summary['passed'])
        self.assertEqual([r['passed'] for r in summary['results']], [False, True])

    def test_jobs_run_cases_at_once_largest_first_and_summarize_in_selection_order(self):
        for case, size in zip(self.cases, [1, 100]):
            (self.root / 'corpus/cache' / case['filename']).write_bytes(b'x' * size)
        both_running = threading.Barrier(2, timeout=10)
        scheduled = []

        class RecordingPool(runner.ThreadPoolExecutor):
            def map(self, function, names):
                scheduled.extend(names)
                return super().map(function, scheduled)

        def launch(command, **kwargs):
            self.assertEqual(command[command.index('--concurrent-evaluations') + 1], '2')
            both_running.wait()  # a sequential runner never releases this
            Path(command[command.index('--output') + 1]).mkdir()
            return SimpleNamespace(returncode=0)

        with patch.object(runner.subprocess, 'run', side_effect=launch), \
                patch.object(runner, 'ThreadPoolExecutor', RecordingPool), \
                patch.object(runner, 'check_evaluation', side_effect=lambda case, contract, directory:
                             {'case': case['id'], 'passed': case['id'] == 'second'}):
            self.assertEqual(self.run_main(['--jobs', '2']), 1)
        summary = json.loads((self.root / 'output/summary.json').read_text())
        self.assertEqual(scheduled, ['second', 'first'])
        self.assertEqual([r['case'] for r in summary['results']], ['first', 'second'])
        self.assertEqual([r['passed'] for r in summary['results']], [False, True])

    def test_nonpositive_jobs_are_rejected(self):
        with self.assertRaises(SystemExit) as error:
            self.run_main(['--jobs', '0'])
        self.assertEqual(error.exception.code, 2)
