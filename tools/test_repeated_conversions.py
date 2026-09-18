import json
import unittest

from check_repeated_conversions import evaluate


def output(leaks, digests=None):
    """Harness lines: a start record, then one conversion and one leaks summary per round."""
    lines = [json.dumps({'event': 'start', 'footprint': 1})]
    for index, (objects, size) in enumerate(leaks):
        digest = (digests or ['a' * 64] * len(leaks))[index]
        lines.append(json.dumps({'input': 'x.pdf', 'round': index + 1, 'sha256': digest, 'pages': 10}))
        lines.append(json.dumps({'round': index + 1, 'leaks': f'Process 7: {objects} leaks for {size} total leaked bytes.'}))
    return lines


class RepeatedConversionGateTests(unittest.TestCase):
    def test_growth_is_measured_between_rounds(self):
        summary = evaluate(output([(500, 10_000), (900, 18_000), (1300, 26_000)]), pages=10,
                           maximum_objects_per_page=60)
        self.assertEqual(summary['leakedObjectsPerConversion'], 400)
        self.assertEqual(summary['leakedBytesPerConversion'], 8_000)
        self.assertEqual(summary['conversions'], 3)

    def test_growth_above_the_page_ceiling_fails(self):
        # One request per line (#4's regression) leaks an object graph per line.
        with self.assertRaisesRegex(ValueError, 'exceed 60 per page'):
            evaluate(output([(1000, 1), (2000, 2)]), pages=10, maximum_objects_per_page=60)

    def test_no_leaks_passes(self):
        summary = evaluate(output([(0, 0), (0, 0)]), pages=10, maximum_objects_per_page=60)
        self.assertEqual(summary['leakedObjectsPerConversion'], 0)
        singular = [line.replace('1 leaks for', '1 leak for') for line in output([(1, 16), (1, 16)])]
        self.assertEqual(evaluate(singular, pages=10, maximum_objects_per_page=60)['leakedObjectsPerConversion'], 0)

    def test_differing_outputs_fail(self):
        with self.assertRaisesRegex(ValueError, 'different EPUBs'):
            evaluate(output([(1, 1), (2, 2)], digests=['a' * 64, 'b' * 64]), pages=10, maximum_objects_per_page=60)

    def test_missing_or_unreadable_counts_fail_closed(self):
        lines = output([(1, 1), (2, 2)])
        for broken in [lines[:-1], lines[:3], [], lines[:-1] + [json.dumps({'round': 2, 'leaks': 'unavailable'})]]:
            with self.subTest(broken=broken), self.assertRaises(ValueError):
                evaluate(broken, pages=10, maximum_objects_per_page=60)


if __name__ == '__main__':
    unittest.main()
