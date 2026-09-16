#!/usr/bin/env python3
"""Measure glyph-structure coverage on real equation and table crops with real negative controls.

Usage: python3 measurements/equation-structure/controls.py <corpus-evaluation-directory>
Reads converted EPUBs from a complete corpus run; writes controls.json beside this script.
Erasures are specified in reference pixel coordinates (see the component map in record.md) and
applied to the converted image at the reference's aligned position, so the controls do not depend
on where the converter placed its crop.
"""
import io
import json
from pathlib import Path
import sys
import zipfile

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
import glyph_structure  # noqa: E402
import image_regions  # noqa: E402
from check_corpus_content import read_pages  # noqa: E402
from PIL import Image, ImageDraw, ImageFilter  # noqa: E402


def png(image):
    data = io.BytesIO()
    image.save(data, format='PNG')
    return data.getvalue()


def main():
    corpus = Path(sys.argv[1])
    assets = {}

    def page_images(case, page):
        path = corpus / case / f'{case}.epub'
        if case not in assets:
            pages, _ = read_pages(path)
            with zipfile.ZipFile(path) as archive:
                assets[case] = (pages, {name: archive.read(name) for page_ in pages.values() for name in page_['images']})
        pages, data = assets[case]
        return [data[name] for name in pages[page]['images']]

    def reference(case, name):
        return (ROOT / 'corpus/references' / case / f'{name}.png').read_bytes()

    def aligned_image(case, name, page):
        """The converted page image that best matches the reference, with the aligned top-left."""
        values = glyph_structure.load_reference(reference(case, name))
        best = None
        for data in page_images(case, page):
            image = Image.open(io.BytesIO(data)).convert('L')
            ncc, top, left, _ = glyph_structure.align(values, np.asarray(image, dtype=np.float64))
            if best is None or ncc > best[0]:
                best = (ncc, top, left, image)
        return best[1], best[2], best[3]

    def erased(image, top, left, boxes):
        copy = image.copy()
        draw = ImageDraw.Draw(copy)
        for x0, y0, x1, y1 in boxes:
            draw.rectangle([left + x0, top + y0, left + x1 - 1, top + y1 - 1], fill=255)
        return copy

    def resampled(image, dpi):
        factor = dpi / image_regions.RENDER_DPI
        small = image.resize((max(1, round(image.width * factor)), max(1, round(image.height * factor))), Image.BICUBIC)
        return small.resize(image.size, Image.BICUBIC)

    def measure(label, case, name, images, region_case=None):
        passed, metrics = glyph_structure.structure_score(reference(case, name), images)
        coarse = image_regions.region_score(reference(region_case or case, name.replace('-glyphs', '')), images) \
            if (ROOT / 'corpus/references' / case / (name.replace('-glyphs', '') + '.png')).exists() else None
        entry = {'control': label, 'passed': passed, 'coverage': metrics['coverage'], 'extraInk': metrics['extraInk'],
                 'sharpness': metrics['sharpness'], 'weakestStroke': metrics['weakestStroke'],
                 'fullResolutionCorrelation': metrics['correlation'], 'components': metrics['components'],
                 'weakestComponent': metrics.get('weakestComponent')}
        if coarse is not None:
            entry['regionCorrelation36dpi'] = round(coarse, 3)
        print(json.dumps(entry))
        return entry

    algebra, usgs = 'wallace-algebra-2010', 'usgs-mcs2025-copper'
    solution = 'page-343-our-solution-glyphs'
    exercise = 'page-347-exercise-35-glyphs'
    statistics = 'page-1-salient-statistics-glyphs'
    # Reference-coordinate boxes from the component map (x0, y0, x1, y1).
    EXPONENT, FRACTION_BAR, RADICAL_SIGN = (168, 7, 177, 20), (54, 41, 259, 43), (132, 4, 156, 33)
    WHOLE_SOLUTION = (0, 0, 263, 73)
    FINAL_EXPONENT_35, WHOLE_EXERCISE_35, MINUS_SIGN_35 = (372, 4, 381, 17), (0, 0, 385, 39), (61, 17, 79, 25)
    top, left, image = aligned_image(algebra, solution, 343)
    top35, left35, image35 = aligned_image(algebra, exercise, 347)
    controls = [
        measure('positive: Wallace page 343 solution line, all page images', algebra, solution, page_images(algebra, 343)),
        measure('positive: Wallace page 347 exercise 35, all page images', algebra, exercise, page_images(algebra, 347)),
        measure('positive: USGS page 1 Salient Statistics table, all page images', usgs, statistics, page_images(usgs, 1)),
        measure('tolerance: solution crop with 0.75-pixel Gaussian blur', algebra, solution, [png(image.filter(ImageFilter.GaussianBlur(0.75)))]),
        measure('tolerance: solution crop with 1.5-pixel Gaussian blur', algebra, solution, [png(image.filter(ImageFilter.GaussianBlur(1.5)))]),
        measure('tolerance: solution crop resampled 180 to 150 to 180 DPI', algebra, solution, [png(resampled(image, 150))]),
        measure('tolerance: solution crop resampled 180 to 120 to 180 DPI', algebra, solution, [png(resampled(image, 120))]),
        measure('tolerance: exercise 35 crop with 0.75-pixel Gaussian blur', algebra, exercise, [png(image35.filter(ImageFilter.GaussianBlur(0.75)))]),
        measure('tolerance: exercise 35 crop with 1.5-pixel Gaussian blur', algebra, exercise, [png(image35.filter(ImageFilter.GaussianBlur(1.5)))]),
        measure('tolerance: exercise 35 crop resampled 180 to 150 to 180 DPI', algebra, exercise, [png(resampled(image35, 150))]),
        measure('tolerance: exercise 35 crop resampled 180 to 120 to 180 DPI', algebra, exercise, [png(resampled(image35, 120))]),
        measure('tolerance: solution crop shifted by (3, 2) pixels', algebra, solution,
                [png(image.transform(image.size, Image.AFFINE, (1, 0, -3, 0, 1, -2), fillcolor=255))]),
        measure('negative: solution crop with the b-squared exponent erased', algebra, solution, [png(erased(image, top, left, [EXPONENT]))]),
        measure('negative: solution crop with the fraction bar erased', algebra, solution, [png(erased(image, top, left, [FRACTION_BAR]))]),
        measure('negative: solution crop with the radical sign erased', algebra, solution, [png(erased(image, top, left, [RADICAL_SIGN]))]),
        measure('negative: solution line erased; the similar preceding line remains', algebra, solution, [png(erased(image, top, left, [WHOLE_SOLUTION]))]),
        measure('negative: exercise 35 crop with the final exponent erased', algebra, exercise, [png(erased(image35, top35, left35, [FINAL_EXPONENT_35]))]),
        measure('negative: exercise 35 erased; other exercises remain', algebra, exercise, [png(erased(image35, top35, left35, [WHOLE_EXERCISE_35]))]),
        measure('negative: solution reference against the page 347 exercise column', algebra, solution, page_images(algebra, 347)),
        measure('limitation: solution crop resampled 180 to 60 to 180 DPI (illegible, ink conserved)', algebra, solution, [png(resampled(image, 60))]),
        measure('limitation: exercise 35 crop resampled 180 to 60 to 180 DPI (illegible, ink conserved)', algebra, exercise, [png(resampled(image35, 60))]),
        measure('negative: solution crop with 4-pixel Gaussian blur', algebra, solution, [png(image.filter(ImageFilter.GaussianBlur(4)))]),
        measure('negative: exercise 35 crop with the minus sign before 3n erased', algebra, exercise, [png(erased(image35, top35, left35, [MINUS_SIGN_35]))]),
        measure('negative: all-black image', algebra, solution, [png(Image.new('L', image.size, 0))]),
    ]
    output = {'minimumCoverage': glyph_structure.DEFAULT_MINIMUM_COVERAGE,
              'maximumExtraInk': glyph_structure.DEFAULT_MAXIMUM_EXTRA_INK, 'controls': controls}
    Path(__file__).with_name('controls.json').write_text(json.dumps(output, indent=2) + '\n')


if __name__ == '__main__':
    main()
