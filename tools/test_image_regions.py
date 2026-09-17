import io
import json
from pathlib import Path
import tempfile
import unittest

import numpy as np
from PIL import Image, ImageDraw

from check_corpus_content import assess
import image_regions


def table_image(rows, scale=image_regions.POOL, offset=(0, 0), size=(400, 300)):
    """A deterministic table-like drawing at converted-image resolution."""
    image = Image.new('L', (size[0] * scale // image_regions.POOL, size[1] * scale // image_regions.POOL), 255)
    draw = ImageDraw.Draw(image)
    unit = scale
    for row, widths in enumerate(rows):
        y = offset[1] + (8 + row * 14) * unit
        x = offset[0] + 6 * unit
        for width in widths:
            draw.rectangle([x, y, x + width * unit, y + 6 * unit], fill=0)
            x += (width + 5) * unit
    return image


def png(image):
    data = io.BytesIO()
    image.save(data, format='PNG')
    return data.getvalue()


ROWS = [(12, 3, 20), (8, 9, 4), (15, 2, 11), (5, 14, 7), (10, 10, 3), (3, 6, 18)]
OTHER = [(3, 18, 6), (14, 4, 8), (2, 11, 15), (7, 5, 14), (3, 10, 10), (18, 6, 3)]


def reference_values(rows=ROWS):
    return image_regions.trimmed_to_ink(image_regions.pooled(table_image(rows)))


class RegionMatchingTests(unittest.TestCase):
    def score(self, image, rows=ROWS):
        return image_regions.best_correlation(reference_values(rows), image_regions.pooled(image))

    def test_contained_region_matches_at_any_placement_and_tight_crop(self):
        self.assertGreater(self.score(table_image(ROWS)), 0.99)
        self.assertGreater(self.score(table_image(ROWS, offset=(175, 90), size=(700, 600))), 0.99)
        # An offset off the averaging grid shifts sampling phase; the match weakens but remains clear.
        self.assertGreater(self.score(table_image(ROWS, offset=(173, 91), size=(700, 600))), 0.95)
        tight = table_image(ROWS)
        tight = tight.crop(Image.eval(tight, lambda v: 255 - v).getbbox())
        self.assertGreater(self.score(tight), 0.95)

    def test_missing_clipped_blank_or_different_content_does_not_match(self):
        full = table_image(ROWS)
        self.assertLess(self.score(full.crop((0, 0, full.width, full.height // 3))), image_regions.DEFAULT_MINIMUM_CORRELATION)
        self.assertLess(self.score(Image.new('L', full.size, 255)), image_regions.DEFAULT_MINIMUM_CORRELATION)
        self.assertLess(self.score(table_image(OTHER)), image_regions.DEFAULT_MINIMUM_CORRELATION)
        # Half the rows replaced by similar-looking rows stays below the default threshold.
        self.assertLess(self.score(table_image(ROWS[:3] + OTHER[3:])), image_regions.DEFAULT_MINIMUM_CORRELATION)

    def test_wrong_scale_does_not_match(self):
        self.assertLess(self.score(table_image(ROWS, scale=image_regions.POOL // 2 + 1, size=(800, 600))), image_regions.DEFAULT_MINIMUM_CORRELATION)

    def test_vectorized_search_equals_exhaustive_search(self):
        rng = np.random.default_rng(7)
        image = rng.uniform(0, 255, (23, 31))
        template = image[5:14, 9:20] + rng.normal(0, 8, (9, 11))
        padded = np.pad(image, image_regions.EDGE_TOLERANCE, constant_values=255.0)
        centered = template - template.mean()
        exhaustive = max(
            float((centered * (window - window.mean())).sum()
                  / (np.sqrt((centered ** 2).sum()) * np.sqrt(((window - window.mean()) ** 2).sum())))
            for y in range(padded.shape[0] - 8) for x in range(padded.shape[1] - 10)
            for window in [padded[y:y + 9, x:x + 11]])
        self.assertAlmostEqual(image_regions.best_correlation(template, image), exhaustive, places=9)

    def test_references_need_ink_and_grayscale(self):
        with self.assertRaises(ValueError):
            image_regions.trimmed_to_ink(np.full((5, 5), 255.0))
        with self.assertRaises(ValueError):
            image_regions.load_reference(png(Image.new('RGB', (4, 4), 'white')))


class ImageRegionContractTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(); self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.case = {'id': 'fixture', 'sha256': 'source', 'bytes': 1, 'pages': 1}
        self.reference = 'corpus/references/fixture/page-1-table.png'
        self.write_reference()
        self.contract = {'sourceSHA256': 'source', 'pages': [{'page': 1, 'imageRegions': [{'reference': self.reference}]}]}
        self.pages = {1: {'text': '', 'images': ['EPUB/images/a.png', 'EPUB/images/b.png']}}
        self.images = {'EPUB/images/a.png': png(table_image(OTHER)), 'EPUB/images/b.png': png(table_image(ROWS))}

    def write_reference(self, **sidecar):
        path = self.root / self.reference
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(png(Image.fromarray(reference_values().round().astype('uint8'), mode='L')))
        values = {'sourceSHA256': 'source', 'page': 1, 'renderDPI': 180, 'referenceDPI': 36}
        values.update(sidecar)
        path.with_suffix('.json').write_text(json.dumps(values))

    def check(self, images=None, loader=True):
        images = self.images if images is None else images
        return assess(self.case, self.contract, {'case': self.case, 'runPassed': True, 'conversionExitCode': 0},
                      {'pageCount': 1}, self.pages, [1], image_data=images.__getitem__ if loader else None,
                      reference_root=self.root)

    def test_any_page_image_can_satisfy_the_region(self):
        result = self.check()
        self.assertTrue(result['passed'], result['errors'])
        self.assertEqual(result['contentChecks'], 1)

    def test_missing_wrong_or_unavailable_images_fail(self):
        self.assertFalse(self.check({**self.images, 'EPUB/images/b.png': png(table_image(OTHER))})['passed'])
        self.pages[1]['images'] = ['EPUB/images/a.png']
        self.assertFalse(self.check()['passed'])
        self.pages[1]['images'] = []
        self.assertFalse(self.check()['passed'])
        self.pages[1]['images'] = ['EPUB/images/b.png']
        self.assertFalse(self.check(loader=False)['passed'])
        self.contract['pages'][0]['imageRegions'][0]['minimumCorrelation'] = 1
        self.assertFalse(self.check({'EPUB/images/b.png': png(table_image(ROWS, offset=(2, 1)))})['passed'])

    def test_an_excluded_page_reference_cannot_satisfy_a_region(self):
        # The source-page image beside reflowed text contains the region; only a crop may count.
        self.pages[1]['pageReferences'] = ['EPUB/images/b.png']
        self.assertTrue(self.check()['passed'])
        self.contract['pages'][0]['imageRegions'][0]['excludePageReference'] = True
        self.assertFalse(self.check()['passed'])
        self.pages[1]['images'].append('EPUB/images/c.png')
        self.assertTrue(self.check({**self.images, 'EPUB/images/c.png': png(table_image(ROWS))})['passed'])
        self.contract['pages'][0]['imageRegions'][0]['excludePageReference'] = 'yes'
        with self.assertRaises(ValueError):
            self.check()

    def test_reference_identity_path_and_threshold_are_validated(self):
        for sidecar in [{'sourceSHA256': 'other'}, {'page': 2}, {'renderDPI': 144}]:
            self.write_reference(**sidecar)
            with self.assertRaises(ValueError):
                self.check()
        self.write_reference()
        for expectation in [{'reference': 'corpus/references/other/page-1-table.png'},
                            {'reference': 'corpus/references/fixture/../fixture/page-1-table.png'},
                            {'reference': 'corpus/references/fixture/page-1-table.jpg'},
                            {'reference': self.reference, 'minimumCorrelation': 0.2},
                            {'reference': self.reference, 'minimumCorrelation': '0.9'},
                            {'reference': self.reference, 'extra': True}, {}]:
            self.contract['pages'][0]['imageRegions'] = [expectation]
            with self.assertRaises(ValueError):
                self.check()


if __name__ == '__main__':
    unittest.main()
