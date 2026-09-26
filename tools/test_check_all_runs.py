"""Run the gate's results-directory bookkeeping, `scripts/check-all-runs.sh`, against a private TMPDIR.

`scripts/check-all.sh` prunes earlier runs' `pdfreflow-checks.*` directories on entry, and
parallel agents share one TMPDIR, so the prune must leave a run that is still in progress (#311)
while still removing finished runs beyond `PDFREFLOW_KEPT_RUNS` (#287). Every test calls the
script's own functions in bash, under the options check-all.sh sets, over real processes: a
`sleep` child stands in for a run in progress, and killing it finishes the run.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / 'scripts/check-all-runs.sh'
BASH = shutil.which('bash') or '/bin/bash'


def bash(function, *arguments, environment=None):
    """Sources the helper as check-all.sh does and calls one of its functions."""
    return subprocess.run([BASH, '-c', 'set -euo pipefail; source "$0"; "$@"', str(HELPER),
                           function, *map(str, arguments)],
                          capture_output=True, text=True, env=environment, check=False)


class RunDirectoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.scratch = Path(self.temp.name)
        self.children = []
        self.clock = time.time() - 1000

    def tearDown(self):
        for child in self.children:
            if child.poll() is None:
                child.kill()
                child.wait()
        self.temp.cleanup()

    def process(self):
        child = subprocess.Popen(['sleep', '600'])
        self.children.append(child)
        return child

    def finish(self, child):
        child.kill()
        child.wait()

    def run_directory(self, name, owner=None):
        """A results directory, newer than every one made before it in this test."""
        directory = self.scratch / name
        directory.mkdir()
        (directory / 'logs').mkdir()
        if owner is not None:
            recorded = bash('record_run', directory, owner.pid)
            self.assertEqual(recorded.returncode, 0, recorded.stderr)
        self.clock += 10
        os.utime(directory, (self.clock, self.clock))
        return directory

    def prune(self, kept_runs):
        pruned = bash('prune_old_runs', self.scratch, kept_runs)
        self.assertEqual(pruned.returncode, 0, pruned.stderr)
        return pruned.stdout

    def test_a_live_run_survives_a_prune_that_would_remove_it(self):
        run = self.process()
        live = self.run_directory('pdfreflow-checks.live01', owner=run)
        output = self.prune(0)
        self.assertTrue(live.is_dir())
        self.assertIn(f'Leaving a run still in progress: {live}', output)
        self.finish(run)
        output = self.prune(0)
        self.assertFalse(live.exists())
        self.assertIn(f"Removing an earlier run's results: {live}", output)

    def test_dead_and_unrecorded_runs_are_pruned_beyond_kept_runs(self):
        dead_run = self.process()
        unrecorded = self.run_directory('pdfreflow-checks.old001')
        dead = self.run_directory('pdfreflow-checks.dead01', owner=dead_run)
        newest = self.run_directory('pdfreflow-checks.new001')
        self.finish(dead_run)
        output = self.prune(1)
        self.assertTrue(newest.is_dir())
        self.assertFalse(dead.exists())
        self.assertFalse(unrecorded.exists())
        self.assertNotIn('still in progress', output)

    def test_a_live_run_does_not_push_a_finished_one_out(self):
        run = self.process()
        oldest = self.run_directory('pdfreflow-checks.fin001')
        older = self.run_directory('pdfreflow-checks.fin002')
        newer = self.run_directory('pdfreflow-checks.fin003')
        live = self.run_directory('pdfreflow-checks.live01', owner=run)
        self.prune(2)
        self.assertTrue(live.is_dir())
        self.assertTrue(newer.is_dir())
        self.assertTrue(older.is_dir(), 'the live run was counted among the two kept')
        self.assertFalse(oldest.exists())

    def test_a_recycled_pid_does_not_protect_the_directory(self):
        run = self.process()
        directory = self.run_directory('pdfreflow-checks.reused', owner=run)
        pid, started = (directory / 'owner').read_text().split(' ', 1)
        self.assertEqual(int(pid), run.pid)
        # The same PID, alive, but recorded with another process's start time: the PID was reused.
        (directory / 'owner').write_text(f'{pid} Thu Jan  1 00:00:00 1970\n')
        self.assertEqual(bash('run_is_live', directory).returncode, 1)
        output = self.prune(0)
        self.assertFalse(directory.exists())
        self.assertIn(f"Removing an earlier run's results: {directory}", output)
        self.assertIsNone(run.poll(), 'the recorded process must still be running')

    def test_a_run_reads_as_live_whatever_the_time_zone_of_the_reader(self):
        run = self.process()
        directory = self.scratch / 'pdfreflow-checks.zoned1'
        directory.mkdir()
        recorded = bash('record_run', directory, run.pid,
                        environment={**os.environ, 'TZ': 'America/Los_Angeles', 'LANG': 'fr_FR.UTF-8'})
        self.assertEqual(recorded.returncode, 0, recorded.stderr)
        read = bash('run_is_live', directory, environment={**os.environ, 'TZ': 'Asia/Tokyo'})
        self.assertEqual(read.returncode, 0)

    def test_a_new_run_directory_is_recorded_before_it_takes_its_name(self):
        # One process creates its directory and, while it still runs, a prune keeping none leaves it.
        created = subprocess.run(
            [BASH, '-c', 'set -euo pipefail; source "$0"; work="$(new_run_directory "$1")"; '
             'echo "$work"; prune_old_runs "$1" 0; cat "$work/owner"; echo "$$"',
             str(HELPER), str(self.scratch)], capture_output=True, text=True, check=False)
        self.assertEqual(created.returncode, 0, created.stderr)
        work, leaving, owner, shell = created.stdout.splitlines()
        self.assertRegex(Path(work).name, r'^pdfreflow-checks\.[A-Za-z0-9]{6}$')
        self.assertEqual(Path(work).parent, self.scratch)
        self.assertEqual(leaving, f'Leaving a run still in progress: {work}')
        self.assertEqual(owner.split(' ')[0], shell)
        self.assertEqual(sorted(path.name for path in self.scratch.iterdir()), [Path(work).name])
        # That process has exited, so the run is finished and a later prune removes it.
        self.prune(0)
        self.assertEqual(list(self.scratch.iterdir()), [])

    def test_a_staging_directory_is_removed_only_once_its_run_is_gone(self):
        live_run, dead_run = self.process(), self.process()
        creating = self.scratch / '.pdfreflow-checks.nordr1'
        creating.mkdir()
        live = self.scratch / '.pdfreflow-checks.alive1'
        live.mkdir()
        dead = self.scratch / '.pdfreflow-checks.gone01'
        dead.mkdir()
        for directory, run in ((live, live_run), (dead, dead_run)):
            self.assertEqual(bash('record_run', directory, run.pid).returncode, 0)
        self.finish(dead_run)
        self.prune(0)
        self.assertTrue(creating.is_dir(), 'a directory not yet recorded may be one being created')
        self.assertTrue(live.is_dir())
        self.assertFalse(dead.exists())

    def test_check_all_creates_and_prunes_through_the_helper(self):
        script = (ROOT / 'scripts/check-all.sh').read_text()
        self.assertIn('source scripts/check-all-runs.sh', script)
        self.assertIn('prune_old_runs "$SCRATCH" "$KEPT_RUNS"', script)
        self.assertIn('WORK="$(new_run_directory "$SCRATCH")"', script)
        self.assertNotIn('mktemp', script, 'a directory made outside the helper carries no record')
        self.assertLess(script.index('prune_old_runs "$SCRATCH"'), script.index('new_run_directory'))


if __name__ == '__main__':
    unittest.main()
