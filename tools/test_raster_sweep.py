"""Controls for the raster sweep driver's pure helpers; no Swift compilation or corpus source."""
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest

from PIL import Image

import raster_sweep


def png_bytes(image):
    buffer = io.BytesIO()
    image.save(buffer, format='PNG')
    return buffer.getvalue()


class PhraseAndLabelTests(unittest.TestCase):
    def test_phrase_coverage_ignores_whitespace_and_lists_missing(self):
        lines = ['FLAGPOLE HEIGHT (FT.)', '20', '.4x 6', '25', '5 x8']
        coverage = raster_sweep.phrase_coverage(lines, ['FLAGPOLE HEIGHT (FT.)', '4 x 6', '5 x 8', '40 x 50'])
        self.assertEqual((coverage['found'], coverage['expected']), (3, 4))
        self.assertEqual(coverage['missing'], ['40 x 50'])
        self.assertAlmostEqual(coverage['fraction'], 0.75)
        self.assertIsNone(raster_sweep.phrase_coverage(lines, [])['fraction'])

    def test_encoding_labels_match_the_probe(self):
        self.assertEqual(raster_sweep.encoding_label(None), 'png')
        self.assertEqual([raster_sweep.encoding_label(q) for q in (0.6, 0.75, 0.85, 0.9, 0.95)],
                         ['jpeg60', 'jpeg75', 'jpeg85', 'jpeg90', 'jpeg95'])


class ImageMetricTests(unittest.TestCase):
    def test_normalization_resamples_to_the_reference_resolution(self):
        image = Image.new('RGB', (100, 50), 'white')
        self.assertIs(raster_sweep.normalized_to_base(image, 180), image)
        self.assertEqual(raster_sweep.normalized_to_base(image, 90).size, (200, 100))
        self.assertEqual(raster_sweep.normalized_to_base(image, 300).size, (60, 30))

    def test_jpeg_metrics_distinguish_identical_from_altered_rasters(self):
        png = Image.new('RGB', (8, 8), (200, 100, 50))
        same = raster_sweep.jpeg_metrics(png, png.copy())
        self.assertIsNone(same['rgbPSNRdB'])
        self.assertEqual(same['maximumChannelError'], 0)
        altered = png.copy()
        altered.putpixel((0, 0), (0, 100, 50))
        changed = raster_sweep.jpeg_metrics(png, altered)
        self.assertEqual(changed['maximumChannelError'], 200)
        self.assertLess(changed['rgbPSNRdB'], 40)
        with self.assertRaises(ValueError):
            raster_sweep.jpeg_metrics(png, Image.new('RGB', (4, 4)))


class TargetLoadingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'cache').mkdir()
        source = self.root / 'cache/control.pdf'
        source.write_bytes(b'control source bytes')
        self.case = {'id': 'control', 'filename': 'control.pdf', 'bytes': source.stat().st_size,
                     'sha256': hashlib.sha256(source.read_bytes()).hexdigest(), 'pages': 3}
        self.manifest = {'documents': [self.case]}
        reference = self.root / 'refs/control/page-2-check.png'
        reference.parent.mkdir(parents=True)
        reference.write_bytes(png_bytes(Image.new('L', (4, 4), 0)))
        self.sidecar = {'sourceSHA256': self.case['sha256'], 'page': 2, 'renderDPI': 180, 'referenceDPI': 36,
                        'kind': 'region', 'regionPoints': [10.0, 10.0, 50.0, 30.0], 'sha256': 'x'}
        reference.with_suffix('.json').write_text(json.dumps(self.sidecar))

    def load(self, targets):
        path = self.root / 'targets.json'
        path.write_text(json.dumps(targets))
        return raster_sweep.load_targets(path, self.manifest, self.root / 'cache', root=self.root,
                                         box=lambda source, page, pdfinfo: (600.0, 800.0))

    def test_normalized_regions_become_points_and_references_resolve(self):
        targets = self.load([{'id': 'control-2', 'case': 'control', 'page': 2,
                              'regionNormalized': [0.5, 0.25, 0.25, 0.5], 'expectedPhrases': ['a'],
                              'references': ['refs/control/page-2-check.png']}])
        target = targets[0]
        self.assertEqual(target['region'], [300.0, 200.0, 450.0, 600.0])
        self.assertEqual(target['cropBoxPoints'], [600.0, 800.0])
        self.assertEqual(target['references'][0]['kind'], 'region')
        self.assertEqual(target['references'][0]['regionPoints'], [10.0, 10.0, 50.0, 30.0])
        self.assertEqual(raster_sweep.probe_targets(targets),
                         [{'id': 'control-2', 'source': str(self.root / 'cache/control.pdf'), 'page': 2,
                           'region': [300.0, 200.0, 450.0, 600.0]}])

    def test_rejections(self):
        base = {'id': 'control-2', 'case': 'control', 'page': 2, 'region': [10, 10, 50, 30]}
        for change, message in [({'region': [10, 10, 700, 30]}, 'crop box'), ({'region': [50, 10, 10, 30]}, 'crop box'),
                                ({'page': 4}, 'outside'), ({'id': 'Bad_ID'}, 'ids'),
                                ({'page': 3, 'references': ['refs/control/page-2-check.png']}, 'another source or page')]:
            with self.assertRaisesRegex(ValueError, message, msg=change):
                self.load([dict(base, **change)])
        with self.assertRaisesRegex(ValueError, 'unique'):
            self.load([base, dict(base)])
        (self.root / 'cache/control.pdf').write_bytes(b'tampered')
        with self.assertRaisesRegex(ValueError, 'pinned corpus identity'):
            self.load([base])


class SummaryTests(unittest.TestCase):
    def rows(self):
        rows = []
        for dpi in (96, 180):
            for encoding in ('png', 'jpeg60'):
                for kind, size in (('page', (100 * dpi // 96, 200 * dpi // 96)), ('region', (20, 10))):
                    row = {'target': 't', 'kind': kind, 'requestedDPI': dpi, 'encoding': encoding,
                           'width': size[0], 'height': size[1], 'bytes': dpi * (2 if encoding == 'png' else 1)}
                    if encoding != 'png':
                        row['sameDPIPNGComparison'] = {'rgbPSNRdB': 30.0 + dpi / 10}
                    if kind == 'region':
                        row['phraseCoverage'] = {'expected': 4, 'found': 2 if dpi == 96 else 4, 'fraction': 0.5 if dpi == 96 else 1.0}
                        row['fidelity'] = [{'kind': 'glyph', 'normalized': {'coverage': dpi / 200}}]
                    rows.append(row)
        return rows

    def test_summary_totals_memory_and_markdown(self):
        processes = [{'dpi': 96, 'peakRSSBytes': 1048576, 'peakPhysicalFootprintBytes': 524288, 'elapsedSeconds': 1.5},
                     {'dpi': 180, 'peakRSSBytes': 2097152, 'peakPhysicalFootprintBytes': 1048576, 'elapsedSeconds': 2.5}]
        summary = raster_sweep.summarize(self.rows(), processes)
        self.assertEqual([(e['dpi'], e['encoding']) for e in summary['settings']],
                         [(96, 'png'), (96, 'jpeg60'), (180, 'png'), (180, 'jpeg60')])
        first = summary['settings'][0]
        self.assertEqual(first['page'], {'images': 1, 'bytes': 192, 'pixels': 20000})
        self.assertEqual(first['region']['bytes'], 192)
        self.assertIsNone(first['medianRGBPSNRdB'])
        self.assertEqual(summary['settings'][1]['medianRGBPSNRdB'], 39.6)
        self.assertEqual(first['meanPhraseFraction'], 0.5)
        self.assertEqual(first['minimumGlyphCoverageNormalizedRegion'], 0.48)
        self.assertEqual(summary['processes'][1]['peakRSSBytes'], 2097152)
        text = raster_sweep.markdown_tables(summary, self.rows())
        self.assertIn('| 96 | png | 1 | 0.000 | 0.02 | 0.2 | n/a | 0.5 |', text)
        self.assertIn('| 180 | 2.0 | 1.0 | 2.50 |', text)
        self.assertIn('| t | 2/4 | 2/4 | 4/4 | 4/4 |', text)


if __name__ == '__main__':
    unittest.main()
