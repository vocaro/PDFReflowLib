"""Vision model cache fingerprints (#94)."""
from pathlib import Path
import tempfile
import unittest

from conversion_provenance import vision_cache_directory, vision_model_cache


class VisionModelCacheTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)

    def program(self, name, key, data, anehash='a_1'):
        directory = vision_cache_directory(name, self.home) / '26A428' / key / 'x.bundle/H17C.bundle'
        (directory / 'main/main_ane').mkdir(parents=True, exist_ok=True)
        (directory / 'H17C.e5').write_bytes(data)
        (directory / 'main/main_ane/model.anehash').write_text(anehash)

    def test_cache_is_keyed_by_executable_name_not_directory(self):
        self.assertEqual(vision_cache_directory('/a/.build/release/pdf-reflow', self.home),
                         vision_cache_directory('/tmp/copy/pdf-reflow', self.home))
        self.assertNotEqual(vision_cache_directory('/a/pdf-reflow', self.home),
                            vision_cache_directory('/a/pdf-reflow-394147f', self.home))
        self.assertEqual(vision_cache_directory('/x/pdf-reflow', self.home),
                         self.home / 'Library/Caches/pdf-reflow/com.apple.e5rt.e5bundlecache')

    def test_missing_cache_is_reported_as_absent(self):
        cache = vision_model_cache('/x/never-run', self.home)
        self.assertEqual((cache['executableName'], cache['exists'], cache['programCount']), ('never-run', False, 0))

    def test_programs_change_the_fingerprint_but_per_compile_anehash_does_not(self):
        self.program('pdf-reflow', 'K1', b'program-1')
        first = vision_model_cache('/bin/pdf-reflow', self.home)
        self.assertEqual((first['exists'], first['programCount']), (True, 1))
        self.program('pdf-reflow', 'K1', b'program-1', anehash='a_2')
        self.assertEqual(vision_model_cache('/bin/pdf-reflow', self.home), first)
        self.program('pdf-reflow', 'K1', b'recompiled')
        self.assertNotEqual(vision_model_cache('/bin/pdf-reflow', self.home)['programsSHA256'], first['programsSHA256'])
        self.program('pdf-reflow', 'K2', b'program-2')
        self.assertEqual(vision_model_cache('/bin/pdf-reflow', self.home)['programCount'], 2)


if __name__ == '__main__':
    unittest.main()
