import json
import unittest
from run import physical_identity, validate_metrics, validate_console


class ReceiptTests(unittest.TestCase):
    def test_rejects_simulators_and_another_device(self):
        hardware = {'reality': 'physical', 'udid': 'phone', 'productType': 'iPhone18,2'}
        self.assertEqual(physical_identity({'properties': {'hardware': hardware}}, 'phone')['productType'], 'iPhone18,2')
        for bad in ({**hardware, 'reality': 'simulated'}, {**hardware, 'udid': 'other'}, {}):
            with self.assertRaises(ValueError): physical_identity({'properties': {'hardware': bad}}, 'phone')

    def test_rejects_stale_case_settings_and_source(self):
        metrics = {'case': 'book', 'rasterDPI': 180, 'maximumRasterPixels': 12_000_000,
                   'sourceSHA256': 'abc', 'ocr': 'automatic', 'referenceImages': 'automatic'}
        validate_metrics(metrics, 'book', 180, 12_000_000, 'abc', 'automatic', 'automatic')
        for key, value in [('case', 'other'), ('rasterDPI', 96), ('maximumRasterPixels', 6_000_000),
                           ('sourceSHA256', 'tampered'), ('ocr', 'never'), ('referenceImages', 'always')]:
            with self.assertRaises(ValueError):
                validate_metrics({**metrics, key: value}, 'book', 180, 12_000_000, 'abc', 'automatic', 'automatic')

    def test_a_repeat_requires_its_fresh_console_result(self):
        for status in ('completed', 'failed'):
            metrics = {'case': 'book', 'status': status}
            validate_console('RASTER_RESULT ' + json.dumps(metrics) + '\r\nRASTER_DONE', metrics)
            for log in ('RASTER_START book', 'RASTER_RESULT {}'):
                with self.assertRaises(ValueError): validate_console(log, metrics)


if __name__ == '__main__': unittest.main()
