import unittest

from check_measurements import MAXIMUM_ADDED_BYTES, violations


class MeasurementsPolicyTests(unittest.TestCase):
    def test_records_and_small_summaries_pass(self):
        self.assertEqual(violations([('measurements/x/record.md', 4000), ('measurements/x/results.json', 20_000)]), [])

    def test_raw_captures_fail_whatever_their_size(self):
        for name in ['run.log', 'trace.gz', 'receipts.tar.gz', 'page.png', 'book.epub', 'source.pdf', 'page-1.plist']:
            with self.subTest(name=name):
                problems = violations([(f'measurements/x/{name}', 10)])
                self.assertEqual(len(problems), 1)
                self.assertIn('raw capture added', problems[0])

    def test_bulk_additions_fail_on_total_size(self):
        added = [(f'measurements/x/part-{i}.json', MAXIMUM_ADDED_BYTES // 2) for i in range(3)]
        problems = violations(added)
        self.assertEqual(len(problems), 1)
        self.assertIn('exceed', problems[0])
        self.assertEqual(violations(added, maximum_bytes=MAXIMUM_ADDED_BYTES * 2), [])

    def test_nothing_added_passes(self):
        self.assertEqual(violations([]), [])


if __name__ == '__main__':
    unittest.main()
