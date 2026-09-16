import io
import json
from pathlib import Path
import tempfile
import unittest

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from check_corpus_content import assess
import glyph_structure
import image_regions


def equation(size=(420, 120), offset=(0, 0), exponent=True, bar=True, radical=True, digit='4'):
    """A synthetic displayed formula at converted-image resolution: numerator with an exponent
    and a radical sign over a fraction bar above a denominator."""
    image = Image.new('L', size, 255)
    draw = ImageDraw.Draw(image)
    x, y = offset
    # Numerator glyph blocks: "b", exponent "2", "-", digit, "ac".
    draw.rectangle([x + 60, y + 20, x + 72, y + 48], fill=0)
    if exponent:
        draw.rectangle([x + 75, y + 12, x + 83, y + 24], fill=0)
    draw.rectangle([x + 92, y + 34, x + 108, y + 36], fill=0)
    for index, column in enumerate(range(x + 116, x + 176, 20)):
        if digit == '1' and index == 0:
            draw.rectangle([column + 5, y + 20, column + 6, y + 48], fill=0)  # a thin "1" replaces the block
        else:
            draw.rectangle([column, y + 20, column + 12, y + 48], fill=0)
    if radical:
        draw.line([(x + 40, y + 34), (x + 48, y + 52), (x + 56, y + 8), (x + 190, y + 8)], fill=0, width=2)
    if bar:
        draw.rectangle([x + 30, y + 60, x + 200, y + 62], fill=0)
    draw.rectangle([x + 100, y + 72, x + 112, y + 100], fill=0)
    draw.rectangle([x + 118, y + 80, x + 132, y + 100], fill=0)
    return image


def png(image):
    data = io.BytesIO()
    image.save(data, format='PNG')
    return data.getvalue()


def reference_values():
    return glyph_structure.trimmed_to_ink(np.asarray(equation(), dtype=np.float64))


def reference_png():
    return png(Image.fromarray(reference_values().astype('uint8'), mode='L'))


class GlyphStructureTests(unittest.TestCase):
    def metrics(self, image):
        return glyph_structure.structure(reference_values(), np.asarray(image.convert('L'), dtype=np.float64))

    def test_exact_offset_blurred_and_resampled_copies_pass(self):
        for image in [equation(), equation(size=(700, 400), offset=(137, 91)),
                      equation().filter(ImageFilter.GaussianBlur(0.75)),
                      equation().resize((350, 100), Image.BICUBIC).resize((420, 120), Image.BICUBIC)]:
            metrics = self.metrics(image)
            self.assertTrue(glyph_structure.passes(metrics), metrics)
            self.assertGreater(metrics['coverage'], 0.8, metrics)
            self.assertLess(metrics['extraInk'], 0.05, metrics)

    def test_alignment_recovers_the_reference_origin(self):
        metrics = self.metrics(equation(size=(700, 400), offset=(137, 91)))
        # The reference keeps a MARGIN of white around ink that starts 8 px below and 30 px right of the offset.
        self.assertEqual((metrics['top'], metrics['left']), (91 + 8 - glyph_structure.MARGIN, 137 + 30 - glyph_structure.MARGIN))

    def test_erasing_one_exponent_bar_or_radical_fails(self):
        for broken in [equation(exponent=False), equation(bar=False), equation(radical=False)]:
            metrics = self.metrics(broken)
            self.assertFalse(glyph_structure.passes(metrics), metrics)
            self.assertLess(metrics['coverage'], 0.2, metrics)

    def test_substituted_digit_blank_black_and_heavy_blur_fail(self):
        different = self.metrics(equation(digit='1'))
        self.assertFalse(glyph_structure.passes(different), different)
        self.assertLess(different['coverage'], 0.3, different)
        self.assertFalse(glyph_structure.passes(self.metrics(Image.new('L', (420, 120), 255))))
        black = self.metrics(Image.new('L', (420, 120), 0))
        self.assertFalse(glyph_structure.passes(black), black)
        self.assertGreater(black['extraInk'], glyph_structure.DEFAULT_MAXIMUM_EXTRA_INK)
        self.assertFalse(glyph_structure.passes(self.metrics(equation().filter(ImageFilter.GaussianBlur(4)))))

    def test_extra_ink_inside_the_formula_fails(self):
        extra = equation()
        ImageDraw.Draw(extra).rectangle([140, 70, 195, 100], fill=0)  # a stray block beside the denominator
        metrics = self.metrics(extra)
        self.assertGreater(metrics['extraInk'], glyph_structure.DEFAULT_MAXIMUM_EXTRA_INK, metrics)
        self.assertFalse(glyph_structure.passes(metrics))
        # Ink outside the reference window is another region's business, not extra ink here.
        beside = equation()
        ImageDraw.Draw(beside).rectangle([250, 20, 400, 100], fill=0)
        self.assertTrue(glyph_structure.passes(self.metrics(beside)))

    def test_sharpness_is_reported_and_optionally_gated(self):
        sharp, blurred = self.metrics(equation()), self.metrics(equation().filter(ImageFilter.GaussianBlur(2.5)))
        self.assertGreater(sharp['sharpness'], blurred['sharpness'])
        self.assertTrue(glyph_structure.passes(blurred), blurred)
        self.assertTrue(glyph_structure.passes(sharp, minimum_sharpness=0.99))
        self.assertFalse(glyph_structure.passes(blurred, minimum_sharpness=0.99), blurred)

    def test_components_and_tiles(self):
        mask = np.zeros((40, 80), dtype=bool)
        mask[5:8, 2:70] = True      # long rule -> several tiles
        mask[20:30, 10:18] = True   # block
        mask[35, 60] = True         # speck below the minimum area
        parts = glyph_structure.components(mask)
        self.assertEqual(len(parts), 2)
        self.assertEqual(len(parts[0][0]), 3 * 68)
        self.assertGreaterEqual(len(glyph_structure.tiles(parts)), 5)
        with self.assertRaises(ValueError):
            glyph_structure.trimmed_to_ink(np.full((5, 5), 255.0))
        with self.assertRaises(ValueError):
            glyph_structure.load_reference(png(Image.new('RGB', (4, 4), 'white')))

    def test_score_picks_a_passing_page_image(self):
        passed, metrics = glyph_structure.structure_score(reference_png(), [png(equation(bar=False)), png(equation())])
        self.assertTrue(passed, metrics)
        passed, metrics = glyph_structure.structure_score(reference_png(), [png(equation(bar=False)), png(equation(exponent=False))])
        self.assertFalse(passed, metrics)
        self.assertFalse(glyph_structure.structure_score(reference_png(), [])[0])


class GlyphContractTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(); self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.case = {'id': 'fixture', 'sha256': 'source', 'bytes': 1, 'pages': 1}
        self.reference = 'corpus/references/fixture/page-1-formula-glyphs.png'
        self.write_reference()
        self.contract = {'sourceSHA256': 'source', 'pages': [{'page': 1, 'glyphRegions': [{'reference': self.reference}]}]}
        self.pages = {1: {'text': '', 'images': ['EPUB/images/a.png', 'EPUB/images/b.png']}}
        self.images = {'EPUB/images/a.png': png(equation(exponent=False)), 'EPUB/images/b.png': png(equation())}

    def write_reference(self, **sidecar):
        path = self.root / self.reference
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(reference_png())
        values = {'sourceSHA256': 'source', 'page': 1, 'renderDPI': 180, 'referenceDPI': 180, 'kind': 'glyph'}
        values.update(sidecar)
        path.with_suffix('.json').write_text(json.dumps(values))

    def check(self, images=None, loader=True):
        images = self.images if images is None else images
        return assess(self.case, self.contract, {'case': self.case, 'runPassed': True, 'conversionExitCode': 0},
                      {'pageCount': 1}, self.pages, [1], image_data=images.__getitem__ if loader else None,
                      reference_root=self.root)

    def test_any_page_image_with_every_stroke_passes(self):
        result = self.check()
        self.assertTrue(result['passed'], result['errors'])
        self.assertEqual(result['contentChecks'], 1)

    def test_missing_stroke_wrong_image_or_unavailable_images_fail(self):
        self.assertFalse(self.check({**self.images, 'EPUB/images/b.png': png(equation(bar=False))})['passed'])
        self.pages[1]['images'] = ['EPUB/images/a.png']
        self.assertFalse(self.check()['passed'])
        self.pages[1]['images'] = ['EPUB/images/b.png']
        self.assertFalse(self.check(loader=False)['passed'])
        self.contract['pages'][0]['glyphRegions'][0]['minimumSharpness'] = 0.99
        self.assertFalse(self.check({'EPUB/images/b.png': png(equation().filter(ImageFilter.GaussianBlur(1.5)))})['passed'])

    def test_reference_kind_resolution_and_thresholds_are_validated(self):
        for sidecar in [{'kind': 'region'}, {'referenceDPI': 36}, {'page': 2}, {'sourceSHA256': 'other'}]:
            self.write_reference(**sidecar)
            with self.assertRaises(ValueError):
                self.check()
        self.write_reference()
        for expectation in [{'reference': self.reference, 'minimumCoverage': 0.1},
                            {'reference': self.reference, 'maximumExtraInk': 0.9},
                            {'reference': self.reference, 'minimumSharpness': '0.5'},
                            {'reference': self.reference, 'minimumCorrelation': 0.9}, {}]:
            self.contract['pages'][0]['glyphRegions'] = [expectation]
            with self.assertRaises(ValueError):
                self.check()


if __name__ == '__main__':
    unittest.main()
