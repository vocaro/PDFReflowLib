#!/usr/bin/env python3
"""Measure scale, contrast and color agreement on real crops with real negative controls.

Usage: python3 measurements/image-appearance/controls.py <corpus-evaluation-directory>
Reads converted EPUBs from a complete corpus run; writes controls.json beside this script.
"""
import io
import json
from pathlib import Path
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
import image_appearance  # noqa: E402
from check_corpus_content import read_pages  # noqa: E402
from PIL import Image, ImageFilter, ImageOps  # noqa: E402


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
        path = ROOT / 'corpus/references' / case / f'{name}.png'
        return path.read_bytes(), json.loads(path.with_suffix('.json').read_text())['regionPoints']

    def best_image(case, name, page):
        data, region = reference(case, name)
        gray, rgb = image_appearance.load_reference(data)
        candidates = [(image_appearance.appearance(gray, rgb, region, Image.open(io.BytesIO(d)))['correlation'], d)
                      for d in page_images(case, page)]
        return Image.open(io.BytesIO(max(candidates)[1])).convert('RGB')

    def measure(label, case, name, images):
        data, region = reference(case, name)
        passed, metrics = image_appearance.appearance_score(data, region, images)
        entry = {'control': label, 'passed': passed, **metrics}
        print(json.dumps(entry))
        return entry

    def low_contrast(image, low=96, high=160):
        return image.point(lambda v: int(low + v * (high - low) / 255))

    def downscaled(image, factor):
        return image.resize((max(1, round(image.width * factor)), max(1, round(image.height * factor))), Image.BICUBIC)

    def channel_swap(image):
        r, g, b = image.split()
        return Image.merge('RGB', (b, g, r))

    flag, faa, usgs = 'gpo-our-flag-2003', 'faa-phak-8083-25c', 'usgs-mcs2025-copper'
    colorado, figure, table = 'page-33-colorado-flag-color', 'page-121-figure-5-36-color', 'page-1-salient-statistics'
    flag_image = best_image(flag, colorado, 33)
    faa_image = best_image(faa, figure, 121)
    table_image = best_image(usgs, table, 1)
    controls = [
        measure('positive: Our Flag page 33 Colorado flag, all page images', flag, colorado, page_images(flag, 33)),
        measure('positive: FAA page 121 figure 5-36, all page images', faa, figure, page_images(faa, 121)),
        measure('positive: USGS page 1 Salient Statistics table (grayscale reference), all page images', usgs, table, page_images(usgs, 1)),
        measure('tolerance: Colorado crop with 1.5-pixel Gaussian blur', flag, colorado, [png(flag_image.filter(ImageFilter.GaussianBlur(1.5)))]),
        measure('tolerance: Colorado crop saved as JPEG quality 75', flag, colorado, [jpeg(flag_image)]),
        measure('tolerance: figure 5-36 crop with 1.5-pixel Gaussian blur', faa, figure, [png(faa_image.filter(ImageFilter.GaussianBlur(1.5)))]),
        measure('negative: Colorado crop converted to grayscale', flag, colorado, [png(ImageOps.grayscale(flag_image).convert('RGB'))]),
        measure('negative: Colorado crop with red and blue channels swapped', flag, colorado, [png(channel_swap(flag_image))]),
        measure('negative: Colorado crop compressed to gray levels 96-160', flag, colorado, [png(low_contrast(flag_image))]),
        measure('negative: Colorado crop downscaled to half size', flag, colorado, [png(downscaled(flag_image, 0.5))]),
        measure('negative: Colorado crop downscaled to 80 percent', flag, colorado, [png(downscaled(flag_image, 0.8))]),
        measure('negative: figure 5-36 crop converted to grayscale', faa, figure, [png(ImageOps.grayscale(faa_image).convert('RGB'))]),
        measure('negative: figure 5-36 crop with red and blue channels swapped', faa, figure, [png(channel_swap(faa_image))]),
        measure('negative: figure 5-36 crop compressed to gray levels 96-160', faa, figure, [png(low_contrast(faa_image))]),
        measure('negative: table crop compressed to gray levels 96-160', usgs, table, [png(low_contrast(table_image))]),
        measure('negative: table crop downscaled to half size', usgs, table, [png(downscaled(table_image, 0.5))]),
        measure('negative: Colorado reference against figure 5-36 crop', flag, colorado, [png(faa_image)]),
    ]
    output = {'minimumScale': image_appearance.DEFAULT_MINIMUM_SCALE,
              'minimumContrast': image_appearance.DEFAULT_MINIMUM_CONTRAST,
              'minimumColorAgreement': image_appearance.DEFAULT_MINIMUM_COLOR_AGREEMENT, 'controls': controls}
    Path(__file__).with_name('controls.json').write_text(json.dumps(output, indent=2) + '\n')


def jpeg(image):
    data = io.BytesIO()
    image.save(data, format='JPEG', quality=75)
    return data.getvalue()


if __name__ == '__main__':
    main()
