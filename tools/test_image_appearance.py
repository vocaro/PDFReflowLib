import io
import json
from pathlib import Path
import tempfile
import unittest

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageOps

from check_corpus_content import assess
import image_appearance
import image_regions

REGION = [100.0, 200.0, 220.0, 280.0]  # points: 120 × 80 -> 300 × 200 pixels at 180 DPI


def flag(size=(300, 200), offset=(0, 0), scale=1.0, bands=('#0033a0', 'white', '#0033a0'), disc='#c8102e'):
    """A synthetic tricolour flag with a disc, at converted-image resolution."""
    image = Image.new('RGB', size, 'white')
    draw = ImageDraw.Draw(image)
    x, y = offset
    width, height = round(300 * scale), round(200 * scale)
    for index, color in enumerate(bands):
        draw.rectangle([x, y + index * height // 3, x + width, y + (index + 1) * height // 3], fill=color)
    draw.ellipse([x + width // 3, y + height // 4, x + 2 * width // 3, y + 3 * height // 4], fill=disc)
    draw.rectangle([x, y, x + width, y + height], outline='black', width=3)
    return image


def png(image):
    data = io.BytesIO()
    image.save(data, format='PNG')
    return data.getvalue()


def color_reference():
    rgb = image_regions.pooled_array(np.asarray(flag(), dtype=np.float64))
    return png(Image.fromarray(rgb.round().astype('uint8'), mode='RGB'))


def gray_reference():
    gray = image_regions.trimmed_to_ink(image_regions.pooled(flag().convert('L')))
    return png(Image.fromarray(gray.round().astype('uint8'), mode='L'))


class AppearanceTests(unittest.TestCase):
    def metrics(self, image, reference=None):
        gray, rgb = image_appearance.load_reference(reference or color_reference())
        return image_appearance.appearance(gray, rgb, REGION, image)

    def test_exact_offset_blurred_and_jpeg_copies_pass(self):
        jpeg = io.BytesIO()
        flag().save(jpeg, format='JPEG', quality=75)
        for image in [flag(), flag(size=(500, 400), offset=(83, 117)), flag().filter(ImageFilter.GaussianBlur(1.5)),
                      Image.open(io.BytesIO(jpeg.getvalue()))]:
            metrics = self.metrics(image)
            self.assertTrue(image_appearance.passes(metrics), metrics)
            self.assertGreater(metrics['colorAgreement'], 0.9, metrics)

    def test_grayscale_hue_shift_low_contrast_and_downscale_fail(self):
        gray = self.metrics(ImageOps.grayscale(flag()).convert('RGB'))
        self.assertLess(gray['colorAgreement'], 0.05, gray)
        r, g, b = flag().split()
        swapped = self.metrics(Image.merge('RGB', (b, g, r)))
        self.assertLess(swapped['colorAgreement'], 0.2, swapped)
        washed = self.metrics(flag().point(lambda v: 96 + v * 64 // 255))
        self.assertLess(washed['contrast'], image_appearance.DEFAULT_MINIMUM_CONTRAST, washed)
        small = self.metrics(flag().resize((150, 100), Image.BICUBIC))
        self.assertLess(small['scale'], image_appearance.DEFAULT_MINIMUM_SCALE, small)
        for metrics in (gray, swapped, washed, small):
            self.assertFalse(image_appearance.passes(metrics), metrics)

    def test_grayscale_reference_checks_scale_and_contrast_only(self):
        metrics = self.metrics(ImageOps.grayscale(flag()).convert('RGB'), gray_reference())
        self.assertNotIn('colorAgreement', metrics)
        self.assertTrue(image_appearance.passes(metrics), metrics)
        self.assertFalse(image_appearance.passes(self.metrics(flag().point(lambda v: 96 + v * 64 // 255), gray_reference())))

    def test_hue_and_reference_validation(self):
        hue, chroma = image_appearance.hue_and_chroma(np.array([[[255, 0, 0], [0, 255, 0], [0, 0, 255], [128, 128, 128]]], dtype=float))
        self.assertEqual(hue.round().tolist(), [[0, 120, 240, 0]])
        self.assertEqual(chroma.tolist(), [[255, 255, 255, 0]])
        with self.assertRaises(ValueError):
            image_appearance.load_reference(png(Image.new('RGBA', (4, 4))))
        with self.assertRaises(ValueError):
            image_appearance.color_agreement(np.full((4, 4, 3), 200.0), np.full((4, 4, 3), 200.0))

    def test_score_picks_a_passing_page_image(self):
        passed, metrics = image_appearance.appearance_score(color_reference(), REGION, [png(ImageOps.grayscale(flag()).convert('RGB')), png(flag())])
        self.assertTrue(passed, metrics)
        passed, _ = image_appearance.appearance_score(color_reference(), REGION, [png(ImageOps.grayscale(flag()).convert('RGB'))])
        self.assertFalse(passed)
        self.assertFalse(image_appearance.appearance_score(color_reference(), REGION, [])[0])


class AppearanceContractTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(); self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.case = {'id': 'fixture', 'sha256': 'source', 'bytes': 1, 'pages': 1}
        self.reference = 'corpus/references/fixture/page-1-flag-color.png'
        self.write_reference()
        self.contract = {'sourceSHA256': 'source', 'pages': [{'page': 1, 'imageAppearance': [{'reference': self.reference}]}]}
        self.pages = {1: {'text': '', 'images': ['EPUB/images/a.png', 'EPUB/images/b.png']}}
        self.images = {'EPUB/images/a.png': png(ImageOps.grayscale(flag()).convert('RGB')), 'EPUB/images/b.png': png(flag())}

    def write_reference(self, data=None, **sidecar):
        path = self.root / self.reference
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data or color_reference())
        values = {'sourceSHA256': 'source', 'page': 1, 'renderDPI': 180, 'referenceDPI': 36, 'kind': 'color', 'regionPoints': REGION}
        values.update(sidecar)
        path.with_suffix('.json').write_text(json.dumps(values))

    def check(self, images=None, loader=True):
        images = self.images if images is None else images
        return assess(self.case, self.contract, {'case': self.case, 'runPassed': True, 'conversionExitCode': 0},
                      {'pageCount': 1}, self.pages, [1], image_data=images.__getitem__ if loader else None,
                      reference_root=self.root)

    def test_colored_page_image_passes_and_grayscale_only_fails(self):
        result = self.check()
        self.assertTrue(result['passed'], result['errors'])
        self.assertEqual(result['contentChecks'], 1)
        self.pages[1]['images'] = ['EPUB/images/a.png']
        self.assertFalse(self.check()['passed'])
        self.assertFalse(self.check(loader=False)['passed'])

    def test_region_reference_allows_scale_and_contrast_but_not_color(self):
        self.write_reference(gray_reference(), kind='region')
        self.assertTrue(self.check()['passed'])
        self.contract['pages'][0]['imageAppearance'][0]['minimumColorAgreement'] = 0.9
        with self.assertRaises(ValueError):
            self.check()

    def test_kind_region_points_and_thresholds_are_validated(self):
        for sidecar in [{'kind': 'glyph'}, {'referenceDPI': 180}, {'regionPoints': [1, 2, 3]}, {'regionPoints': [5, 5, 1, 1]}, {'page': 2}]:
            self.write_reference(**sidecar)
            with self.assertRaises(ValueError):
                self.check()
        self.write_reference()
        for expectation in [{'reference': self.reference, 'minimumScale': 3}, {'reference': self.reference, 'minimumContrast': 0},
                            {'reference': self.reference, 'minimumColorAgreement': 0.2}, {'reference': self.reference, 'minimumCorrelation': 0.9}]:
            self.contract['pages'][0]['imageAppearance'] = [expectation]
            with self.assertRaises(ValueError):
                self.check()


if __name__ == '__main__':
    unittest.main()
