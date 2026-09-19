"""Every probe is listed, every listed file exists, and the command line prints what swiftc needs."""
import contextlib
import io
import unittest

from pdfreflow_tools import swift_sources
from pdfreflow_tools.corpus import ROOT


class SwiftSourceTests(unittest.TestCase):
    def test_every_listed_source_exists(self):
        for probe in swift_sources.PROBE_SOURCES:
            for path in swift_sources.sources(probe):
                with self.subTest(probe=probe, path=path):
                    self.assertTrue((ROOT / path).is_file(), f'{path} is listed for {probe} but does not exist')

    def test_every_probe_is_listed_exactly_once_with_distinct_sources(self):
        on_disk = {path.name for path in (ROOT / swift_sources.PROBES).glob('*.swift')}
        self.assertEqual(on_disk, set(swift_sources.PROBE_SOURCES))
        for probe, names in swift_sources.PROBE_SOURCES.items():
            with self.subTest(probe=probe):
                self.assertEqual(len(names), len(set(names)))
                self.assertEqual(swift_sources.sources(probe)[-1], swift_sources.probe_path(probe))
                self.assertEqual(swift_sources.sources(probe)[:-1], swift_sources.library_sources(probe))

    def test_command_line_prints_sources_and_rejects_unknown_probes(self):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            self.assertEqual(swift_sources.main(['inspect-structure.swift']), 0)
            self.assertEqual(swift_sources.main(['unknown.swift']), 2)
            self.assertEqual(swift_sources.main([]), 2)
        self.assertEqual(out.getvalue().split(), swift_sources.sources('inspect-structure.swift'))
        self.assertIn('inspect-structure.swift', err.getvalue())


if __name__ == '__main__':
    unittest.main()
