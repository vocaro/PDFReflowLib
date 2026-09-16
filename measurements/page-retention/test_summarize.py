from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import summarize  # noqa: E402


class SummarizeTests(unittest.TestCase):
    def test_renders_identity_verdict_and_rows(self):
        results = {'allIdenticalAndSuccessful': False, 'cases': {'demo': {'runs': {
            'baseline': {'conversionSeconds': 1.5, 'converterCPUSeconds': 2.0, 'converterPeakRSSBytes': 2**20,
                         'sampledPeakPhysicalFootprintBytes': 2**19, 'peakEvaluationDirectoryBytes': 3 * 2**20,
                         'epubcheckExitCode': 0},
            'spill': {'conversionSeconds': 1.0, 'converterCPUSeconds': 1.0, 'converterPeakRSSBytes': 2**20,
                      'sampledPeakPhysicalFootprintBytes': 3 * 2**18, 'peakEvaluationDirectoryBytes': 2**20,
                      'identical': False, 'epubcheckExitCode': None}}}}}
        text = summarize.render(results)
        self.assertIn('FAILURES recorded', text)
        self.assertIn('| baseline | 1.50 | 2.00 | 1.0 | 0.5 | 3.0 | reference | pass |', text)
        self.assertIn('| spill | 1.00 | 1.00 | 1.0 | 0.8 | 1.0 | NO |  |', text)
        results['allIdenticalAndSuccessful'] = True
        self.assertIn('byte-identical', summarize.render(results))


if __name__ == '__main__':
    unittest.main()
