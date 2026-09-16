"""Controls for the raster book comparison: synthetic evaluations with known drift and gate fields."""
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

import raster_book_comparison


class RasterBookComparisonTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def evaluation(self, name, *, options='library defaults', pages=('Alpha text', 'Beta text'), images=(1, 1),
                   image_bytes=100, warnings=(), rss=300 * 1048576, seconds=2.0):
        path = self.root / name
        path.mkdir()
        body = ''
        for number, (text, count) in enumerate(zip(pages, images), 1):
            body += f'<span epub:type="pagebreak" id="page-{number}"/><p>{text}</p>'
            body += ''.join(f'<img src="images/page-{number}-{i}.png"/>' for i in range(count))
        with zipfile.ZipFile(path / 'control.epub', 'w') as archive:
            archive.writestr('EPUB/package.opf', '<package xmlns="http://www.idpf.org/2007/opf">'
                             '<manifest><item id="c" href="chapter.xhtml"/></manifest>'
                             '<spine><itemref idref="c"/></spine></package>')
            archive.writestr('EPUB/chapter.xhtml', '<html xmlns="http://www.w3.org/1999/xhtml" '
                             'xmlns:epub="http://www.idpf.org/2007/ops"><body>' + body + '</body></html>')
            for number, count in enumerate(images, 1):
                for i in range(count):
                    archive.writestr(f'EPUB/images/page-{number}-{i}.png', b'x' * image_bytes)
        report = {'pageCount': len(pages), 'reflowedPageCount': len(pages), 'recognizedPageCount': 1,
                  'imageCount': sum(images), 'warnings': list(warnings)}
        (path / 'conversion-report.json').write_text(json.dumps(report))
        receipt = {'case': {'id': 'control'}, 'options': options, 'runPassed': True, 'converterSHA256': 'c' * 64,
                   'conversionExitCode': 0, 'memoryGate': {'passed': True}, 'epubcheckExitCode': 0,
                   'structuralCheck': 'passed', 'progressCheck': {'passed': True},
                   'environmentProbeCheck': {'passed': True}, 'converterPeakRSSBytes': rss,
                   'sampledPeakPhysicalFootprintBytes': rss // 2, 'conversionSeconds': seconds,
                   'outputBytes': 4096, 'conversionReport': report}
        (path / 'result.json').write_text(json.dumps(receipt))
        return path

    def test_baseline_summary_counts_images_warnings_and_ocr_pages(self):
        warnings = [{'code': 'ocrUsed', 'page': 2, 'message': 'm'}, {'code': 'imagePreserved', 'page': 1, 'message': 'm'},
                    {'code': 'imagePreserved', 'page': 2, 'message': 'm'}]
        result = raster_book_comparison.compare([('defaults', self.evaluation('a', warnings=warnings, images=(2, 1)))])
        run = result['runs'][0]
        self.assertEqual(run['label'], 'defaults')
        self.assertIsNone(run['drift'])
        self.assertEqual((run['imageCount'], run['imageBytes']), (3, 300))
        self.assertEqual(run['warningsByCode'], {'imagePreserved': 2, 'ocrUsed': 1})
        self.assertEqual(run['ocrPages'], [2])
        self.assertEqual(run['recognizedPageCount'], 1)
        self.assertNotIn('content', run)

    def test_drift_lists_changed_text_and_image_count_pages_only(self):
        baseline = self.evaluation('base')
        same = self.evaluation('same', options='--raster-dpi 180', image_bytes=200)
        changed = self.evaluation('changed', options='--raster-dpi 120', pages=('Alpha text', 'Beta changed'), images=(1, 2))
        result = raster_book_comparison.compare([('defaults', baseline), ('dpi-180', same), ('dpi-120', changed)])
        self.assertEqual(result['baseline'], 'defaults')
        self.assertEqual(result['runs'][1]['drift'], {'changedTextPages': [], 'changedImageCountPages': [], 'pageMarkersEqual': True})
        self.assertEqual(result['runs'][2]['drift'], {'changedTextPages': [2], 'changedImageCountPages': [2], 'pageMarkersEqual': True})
        self.assertEqual(result['runs'][1]['imageBytes'], 400)
        text = raster_book_comparison.markdown(result)
        self.assertIn('| dpi-120 | --raster-dpi 120 | True |', text)
        self.assertIn('| 1 |\n', text)

    def test_content_errors_split_reference_image_checks_from_others(self):
        classified = raster_book_comparison.classify_errors([
            'Page 1: no image shows corpus/references/control/page-1-table.png (best correlation -1.000 < 0.95)',
            'Page 2: missing text "Beta"'])
        self.assertEqual(len(classified['referenceImageErrors']), 1)
        self.assertEqual(classified['otherErrors'], ['Page 2: missing text "Beta"'])

    def test_contract_assessment_is_reported_per_run(self):
        case = {'id': 'control', 'sha256': 'b' * 64, 'bytes': 1, 'pages': 2}
        contract = {'id': 'control', 'sourceSHA256': 'b' * 64,
                    'pages': [{'page': 2, 'text': ['Beta text']}]}
        directory = self.evaluation('assessed', pages=('Alpha text', 'Beta changed'))
        receipt = json.loads((directory / 'result.json').read_text())
        receipt['case'] = case
        (directory / 'result.json').write_text(json.dumps(receipt))
        result = raster_book_comparison.compare([('defaults', directory)], case, contract)
        content = result['runs'][0]['content']
        self.assertFalse(content['passed'])
        self.assertEqual(content['referenceImageErrors'], [])
        self.assertTrue(any('Beta text' in error for error in content['otherErrors']))
        self.assertIn('fail (0/', raster_book_comparison.markdown(result))


if __name__ == '__main__':
    unittest.main()
