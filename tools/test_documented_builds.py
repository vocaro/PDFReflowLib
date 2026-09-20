"""The documented builds are found in the docs, matched to a probe, and rerouted to a scratch path."""
import unittest

import check_documented_builds as builds
from pdfreflow_tools import swift_sources
from pdfreflow_tools.corpus import ROOT

DOC = """Prose that mentions swiftc outside a block.

```sh
mkdir -p .build/raster-environment
xcrun swiftc -parse-as-library -O \\
  $(python3 tools/pdfreflow_tools/swift_sources.py probe-raster-environment.swift) \\
  -o .build/raster-environment/probe
python3 tools/evaluate_real_document.py --case dga-2025-2030
```

```sh
swiftc $(python3 tools/pdfreflow_tools/swift_sources.py capture-layout-fixture.swift) \\
  -o /tmp/capture-layout-fixture
/tmp/capture-layout-fixture faa-phak-8083-25c 91 /tmp/faa-91-layout.json
```
"""


class DocumentedBuildTests(unittest.TestCase):
    def test_continuations_join_and_prose_outside_blocks_is_ignored(self):
        found = builds.commands(DOC)
        self.assertEqual(len(found), 5)
        self.assertNotIn('Prose that mentions swiftc outside a block.', found)
        self.assertTrue(found[1].startswith('xcrun swiftc -parse-as-library -O '))
        self.assertTrue(found[1].endswith('-o .build/raster-environment/probe'))

    def test_every_swiftc_command_is_paired_with_the_probe_it_builds(self):
        self.assertEqual([probe for _, probe in builds.swift_builds(DOC)],
                         ['probe-raster-environment.swift', 'capture-layout-fixture.swift'])
        self.assertEqual(builds.swift_builds('```sh\nswiftc tools/probes/nothing.swift -o /tmp/x\n```'),
                         [('swiftc tools/probes/nothing.swift -o /tmp/x', None)])

    def test_the_output_target_is_the_only_rewritten_operand(self):
        rewritten, count = builds.OUTPUT.subn('-o /scratch/probe', builds.swift_builds(DOC)[0][0])
        self.assertEqual(count, 1)
        self.assertTrue(rewritten.endswith('-o /scratch/probe'))
        self.assertIn('swift_sources.py probe-raster-environment.swift', rewritten)

    def test_registered_documents_exist_and_name_registered_probes(self):
        for document, probe in builds.DOCUMENTED:
            with self.subTest(document=document, probe=probe):
                self.assertTrue((ROOT / document).is_file())
                self.assertIn(probe, swift_sources.PROBE_SOURCES)


if __name__ == '__main__':
    unittest.main()
