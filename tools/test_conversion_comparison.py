import copy
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

from compare_conversion_runs import compare, compatible_receipts
from conversion_provenance import digest


class ConversionComparisonTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.receipt = {
            'provenanceSchemaVersion': 1, 'runID': 'run-control', 'outputSHA256': 'a' * 64,
            'case': {'id': 'control', 'sha256': 'b' * 64, 'pages': 1},
            'executionContext': 'host-terminal', 'system': 'macOS', 'systemBuild': 'build',
            'machine': 'arm64', 'options': 'library defaults', 'runPassed': True,
            'converterSHA256': 'c' * 64,
            'conversionReport': {'pageCount': 1, 'recognizedPageCount': 1, 'warnings': []},
            'environmentProbeCapture': {'executableSHA256': 'd' * 64, 'resultSHA256': 'e' * 64, 'exitCode': 0},
            'environmentProbe': {'schemaVersion': 1, 'runID': 'run-control', 'system': 'macOS build',
                'probeSHA256': 'd' * 64, 'sourceSHA256': 'b' * 64, 'page': 1,
                'packedPixelSHA256': 'f' * 64, 'metalDevice': 'device', 'colorSpaceName': 'DeviceRGB',
                'colorSpaceICC_SHA256': 'unavailable', 'width': 10, 'height': 10, 'bitsPerPixel': 32,
                'rasterDPI': 180, 'ocr': {'status': 'succeeded', 'lines': ['control']}},
        }

    def evaluation(self, name, *, body='<p>Original text</p>', image=b'pixels', receipt=None):
        path = self.root / name
        path.mkdir()
        with zipfile.ZipFile(path / 'control.epub', 'w') as archive:
            archive.writestr('EPUB/package.opf', '<package xmlns="http://www.idpf.org/2007/opf">'
                '<manifest><item id="c" href="chapter.xhtml"/></manifest>'
                '<spine><itemref idref="c"/></spine></package>')
            archive.writestr('EPUB/chapter.xhtml', '<html xmlns="http://www.w3.org/1999/xhtml" '
                'xmlns:epub="http://www.idpf.org/2007/ops"><body>'
                '<span epub:type="pagebreak" id="page-1"/>' + body +
                '<img src="images/image-1.png"/></body></html>')
            archive.writestr('EPUB/images/image-1.png', image)
            archive.comment = name.encode()  # ZIP identity is deliberately irrelevant.
        receipt = copy.deepcopy(receipt or self.receipt)
        (path / 'environment-probe.json').write_text(json.dumps(receipt['environmentProbe']))
        (path / 'conversion-report.json').write_text(json.dumps(receipt['conversionReport']))
        receipt['outputSHA256'] = digest(path / 'control.epub')
        receipt['environmentProbeCapture']['resultSHA256'] = digest(path / 'environment-probe.json')
        (path / 'result.json').write_text(json.dumps(receipt))
        return path

    def test_same_context_different_binaries_and_zip_metadata_pass(self):
        candidate = copy.deepcopy(self.receipt)
        candidate['converterSHA256'] = '1' * 64
        candidate['conversionReport']['outputURL'] = 'different path'
        result = compare(self.evaluation('left'), self.evaluation('right', receipt=candidate))
        self.assertTrue(result['passed'])

    def test_missing_or_incompatible_environment_provenance_refuses_comparison(self):
        for field in ['system', 'systemBuild', 'machine', 'options']:
            for replacement in [None, 'other']:
                candidate = copy.deepcopy(self.receipt)
                candidate[field] = replacement
                self.assertTrue(compatible_receipts(self.receipt, candidate), (field, replacement))
        unknown = dict(self.receipt)
        unknown.pop('provenanceSchemaVersion')
        result = compare(self.evaluation('left'), self.evaluation('right', receipt=unknown))
        self.assertFalse(result['passed'])
        self.assertNotIn('changedImages', result)

    def test_context_labels_are_supplemental(self):
        left = self.evaluation('left')
        for name, label in [('different', 'sandbox'), ('missing', None)]:
            candidate = dict(self.receipt, executionContext=label)
            self.assertTrue(compare(left, self.evaluation(name, receipt=candidate))['passed'])

    def test_probe_must_be_bound_to_this_run_source_and_executable(self):
        for field, value in [('runID', 'stale-run'), ('sourceSHA256', '0' * 64),
                             ('probeSHA256', '0' * 64), ('page', 2), ('schemaVersion', 2)]:
            candidate = copy.deepcopy(self.receipt)
            candidate['environmentProbe'][field] = value
            self.assertTrue(compatible_receipts(self.receipt, candidate), field)

    def test_missing_or_malformed_probe_refuses_comparison(self):
        for value in [None, {}, [], 'invalid']:
            candidate = dict(self.receipt, environmentProbe=value)
            self.assertTrue(compatible_receipts(self.receipt, candidate))
        for field in ['environmentProbeCapture', 'outputSHA256', 'converterSHA256']:
            candidate = copy.deepcopy(self.receipt)
            del candidate[field]
            self.assertTrue(compatible_receipts(self.receipt, candidate), field)

    def test_matching_but_incomplete_capability_receipts_are_refused(self):
        for field in self.receipt['environmentProbe']:
            candidate = copy.deepcopy(self.receipt)
            del candidate['environmentProbe'][field]
            self.assertTrue(compatible_receipts(candidate, candidate), field)

    def test_nan_dimensions_and_malformed_ocr_are_refused(self):
        for field, value in [('width', float('nan')), ('height', -1), ('rasterDPI', float('inf')),
                             ('ocr', {'status': 'succeeded'}), ('ocr', {'status': 'succeeded', 'lines': [1]})]:
            candidate = copy.deepcopy(self.receipt)
            candidate['environmentProbe'][field] = value
            self.assertTrue(compatible_receipts(candidate, candidate), (field, value))

    def test_changed_artifacts_are_refused_before_content_comparison(self):
        left = self.evaluation('left')
        for index, filename in enumerate(['control.epub', 'environment-probe.json', 'conversion-report.json']):
            right = self.evaluation('right' + str(index))
            with (right / filename).open('ab') as stream:
                stream.write(b' ' if filename.endswith('.json') else b'changed')
            if filename == 'conversion-report.json':
                (right / filename).write_text('{}')
            result = compare(left, right)
            self.assertFalse(result['passed'], filename)
            self.assertTrue(result['provenanceErrors'])
            self.assertNotIn('changedPages', result)

    def test_missing_artifact_is_a_failed_result(self):
        left, right = self.evaluation('left'), self.evaluation('right')
        (right / 'environment-probe.json').unlink()
        self.assertTrue(compare(left, right)['provenanceErrors'])

    def test_changed_source_and_failed_evaluation_are_not_comparable(self):
        for field in ['id', 'sha256', 'pages']:
            candidate = copy.deepcopy(self.receipt)
            candidate['case'][field] = 'other'
            self.assertTrue(compatible_receipts(self.receipt, candidate))
        candidate = dict(self.receipt, runPassed=False)
        self.assertTrue(compatible_receipts(self.receipt, candidate))

    def test_same_binary_opposite_capabilities_refuse_even_with_matching_context_label(self):
        candidate = copy.deepcopy(self.receipt)
        candidate['environmentProbe'].update(metalDevice='unavailable', packedPixelSHA256='other',
            ocr={'status': 'failed', 'description': 'Failed to create CVPixelBuffer'})
        result = compare(self.evaluation('left'), self.evaluation('right', receipt=candidate))
        self.assertFalse(result['passed'])
        self.assertIn('capability probe metalDevice differs', result['provenanceErrors'])
        self.assertIn('capability probe packedPixelSHA256 differs', result['provenanceErrors'])
        self.assertIn('candidate raster/Vision capability probe missing or failed', result['provenanceErrors'])

    def test_pixel_asset_change_fails_even_when_parsed_text_agrees(self):
        result = compare(self.evaluation('left'), self.evaluation('right', image=b'changed pixels'))
        self.assertFalse(result['passed'])
        self.assertEqual(result['changedPages'], [])
        self.assertEqual(result['changedImages'], ['EPUB/images/image-1.png'])

    def test_text_or_heading_change_fails_even_with_identical_images(self):
        left = self.evaluation('left')
        for name, body in [('text', '<p>Changed text</p>'), ('heading', '<h2>Original text</h2>')]:
            result = compare(left, self.evaluation(name, body=body))
            self.assertFalse(result['passed'])
            self.assertEqual(result['changedPages'], [1])
            self.assertEqual(result['changedImages'], [])

    def test_ocr_failure_is_visible_even_if_fallback_pixels_and_text_agree(self):
        candidate = copy.deepcopy(self.receipt)
        candidate['conversionReport'].update(recognizedPageCount=0,
            warnings=[{'code': 'ocrFailed', 'page': 1}])
        result = compare(self.evaluation('left'), self.evaluation('right', receipt=candidate))
        self.assertFalse(result['passed'])
        self.assertEqual(result['changedReportFields'], ['recognizedPageCount', 'warnings'])

    def test_added_null_report_field_is_still_a_difference(self):
        candidate = copy.deepcopy(self.receipt)
        candidate['conversionReport']['newField'] = None
        result = compare(self.evaluation('left'), self.evaluation('right', receipt=candidate))
        self.assertFalse(result['passed'])
        self.assertEqual(result['changedReportFields'], ['newField'])
