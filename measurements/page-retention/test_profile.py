from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import profile  # noqa: E402


class ProfileTests(unittest.TestCase):
    def test_stage_boundaries_and_peak_location(self):
        samples = [
            {'seconds': 0.0, 'progress': 'starting', 'physicalFootprintBytes': 10},
            {'seconds': 0.1, 'progress': '2% extracting page 1/9', 'physicalFootprintBytes': 500},
            {'seconds': 0.2, 'progress': '57% extracting page 9/9', 'physicalFootprintBytes': 120},
            {'seconds': 0.3, 'progress': '70% reconstructing page 4/9', 'physicalFootprintBytes': 200},
            {'seconds': 0.4, 'progress': '82% reconstructing page 9/9', 'physicalFootprintBytes': 150},
            {'seconds': 0.5, 'progress': '90% writing', 'physicalFootprintBytes': 130},
            {'seconds': 0.6, 'progress': '100% completed', 'physicalFootprintBytes': 5},
        ]
        result = profile.profile(samples)
        self.assertEqual(result['extractionEndBytes'], 120)
        self.assertEqual(result['extractionPeakBytes'], 500)
        self.assertEqual(result['reconstructionPeakBytes'], 200)
        self.assertEqual(result['writingPeakBytes'], 130)
        self.assertEqual(result['peakBytes'], 500)
        self.assertEqual(result['peakProgress'], '2% extracting page 1/9')

    def test_missing_stage_is_blank_not_zero(self):
        result = profile.profile([{'seconds': 0.0, 'progress': '10% extracting page 1/2', 'physicalFootprintBytes': 7}])
        self.assertIsNone(result['reconstructionPeakBytes'])
        self.assertEqual(profile.mib(None), '')


if __name__ == '__main__':
    unittest.main()
